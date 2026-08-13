#!/usr/bin/env bash

# Shared, fail-closed baseline loading for every test that consumes Omarchy
# host sources. Call shibumi_load_omarchy_baseline after repo_root is known.

shibumi_baseline_repo_root=$(cd -- \
  "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

shibumi_baseline_fail() {
  printf 'Shibumi baseline error: %s\n' "$*" >&2
  return 1
}

shibumi_require_baseline_tools() {
  command -v find >/dev/null 2>&1 \
    || shibumi_baseline_fail 'find is required' || return
  command -v jq >/dev/null 2>&1 \
    || shibumi_baseline_fail 'jq is required' || return
  command -v realpath >/dev/null 2>&1 \
    || shibumi_baseline_fail 'realpath is required' || return
  command -v sha256sum >/dev/null 2>&1 \
    || shibumi_baseline_fail 'sha256sum is required' || return
  command -v sort >/dev/null 2>&1 \
    || shibumi_baseline_fail 'sort is required' || return
}

shibumi_validate_omarchy_baseline_schema() {
  local manifest=${1:-}
  [[ -n $manifest && $manifest == /* ]] \
    || shibumi_baseline_fail 'baseline manifest path must be absolute' || return
  [[ -e $manifest ]] \
    || shibumi_baseline_fail "baseline manifest is missing: $manifest" || return
  [[ -f $manifest && -r $manifest ]] \
    || shibumi_baseline_fail "baseline manifest is unreadable: $manifest" || return
  jq -e . "$manifest" >/dev/null 2>&1 \
    || shibumi_baseline_fail \
      "baseline manifest is not valid JSON: $manifest" || return

  jq -e '.schemaVersion == 2' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline schemaVersion must be 2: $manifest" || return
  jq -e '.id | type == "string" and length > 0' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline id must be a non-empty string: $manifest" || return
  jq -e '
    .profile == "installed-package"
    or .profile == "installed-source-parity"
    or .profile == "forward-compat"
  ' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline profile is unsupported: $manifest" || return
  jq -e '.repository == "https://github.com/basecamp/omarchy"' \
    "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline repository is not authoritative: $manifest" || return
  jq -e '
    .sourceRevision
    | type == "string" and test("^[0-9a-f]{40}$")
  ' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline sourceRevision must be a full commit SHA: $manifest" || return
  jq -e '.provenance | type == "object"' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline provenance must be an object: $manifest" || return
  jq -e '
    .quickshellPackage | type == "object"
    and (.name | type == "string" and length > 0)
    and (.version | type == "string" and length > 0)
  ' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline Quickshell package identity is invalid: $manifest" || return
  jq -e '.subtrees | type == "array"' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline subtrees must be an array: $manifest" || return
  jq -e '.subtrees | length == 3' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline must declare exactly three subtrees: $manifest" || return
  jq -e 'all(.subtrees[]; .path | type == "string" and length > 0)' \
    "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline subtree path must be a non-empty string: $manifest" || return
  jq -e '
    all(.subtrees[];
      (.path | startswith("/") | not)
      and .path != "."
      and .path != ".."
      and (.path | contains("/") | not))
  ' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline subtree path must be a safe root-relative name: $manifest" \
    || return
  jq -e '
    [.subtrees[].path] | sort == ["bin", "config", "shell"]
  ' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline subtree set must be exactly bin, config, and shell: $manifest" \
    || return
  jq -e '
    all(.subtrees[];
      .entryPolicy == "regular-files"
      or .entryPolicy == "absolute-symlinks")
  ' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline subtree entryPolicy is invalid: $manifest" || return
  jq -e '
    all(.subtrees[];
      .entryCount
      | type == "number" and . > 0 and floor == .)
  ' "$manifest" >/dev/null \
    || shibumi_baseline_fail \
      "baseline subtree entryCount must be a positive integer: $manifest" \
    || return
  local digest_field
  for digest_field in inventorySha256 structureSha256 contentSha256; do
    jq -e --arg field "$digest_field" '
      all(.subtrees[];
        .[$field] | type == "string" and test("^[0-9a-f]{64}$"))
    ' "$manifest" >/dev/null \
      || shibumi_baseline_fail \
        "baseline subtree $digest_field is invalid: $manifest" || return
  done

  local profile
  profile=$(jq -r '.profile' "$manifest")
  case $profile in
    installed-package)
      jq -e '
        .provenance.kind == "package"
        and (.package | type == "object")
        and (.package.name | type == "string" and length > 0)
        and (.package.version | type == "string" and length > 0)
      ' "$manifest" >/dev/null \
        || shibumi_baseline_fail \
          "installed-package provenance is invalid: $manifest" || return
      jq -e '
        all(.subtrees[];
          if .path == "bin" then
            .entryPolicy == "absolute-symlinks"
          else
            .entryPolicy == "regular-files"
          end)
      ' "$manifest" >/dev/null \
        || shibumi_baseline_fail \
          "installed-package subtree policy is invalid: $manifest" || return
      ;;
    installed-source-parity | forward-compat)
      jq -e '
        .provenance.kind == "git"
        and .provenance.revision == .sourceRevision
      ' "$manifest" >/dev/null \
        || shibumi_baseline_fail \
          "$profile Git provenance is invalid: $manifest" || return
      jq -e 'all(.subtrees[]; .entryPolicy == "regular-files")' \
        "$manifest" >/dev/null \
        || shibumi_baseline_fail \
          "$profile subtree policy is invalid: $manifest" || return
      ;;
  esac
}

shibumi_validate_omarchy_tree() {
  shibumi_require_baseline_tools || return

  local requested_path=${1:-}
  local requested_manifest=${2:-}
  [[ $requested_path == /* ]] \
    || shibumi_baseline_fail 'OMARCHY_PATH must be absolute' || return
  [[ -d $requested_path ]] \
    || shibumi_baseline_fail "Omarchy baseline root is missing: $requested_path" \
    || return
  shibumi_validate_omarchy_baseline_schema "$requested_manifest" || return

  local canonical_path canonical_manifest
  canonical_path=$(realpath -e -- "$requested_path") \
    || shibumi_baseline_fail "cannot resolve OMARCHY_PATH: $requested_path" \
    || return
  canonical_manifest=$(realpath -e -- "$requested_manifest") \
    || shibumi_baseline_fail \
      "cannot resolve baseline manifest: $requested_manifest" || return

  local subtree entry_policy expected_count expected_inventory
  local expected_structure expected_content subtree_root
  local actual_count actual_inventory actual_structure actual_content
  local relative_path candidate link_target executable
  local -a entries=() content_entries=()
  while IFS=$'\t' read -r subtree entry_policy expected_count \
      expected_inventory expected_structure expected_content; do
    subtree_root="$canonical_path/$subtree"
    [[ -d $subtree_root && ! -L $subtree_root ]] \
      || shibumi_baseline_fail \
        "required Omarchy baseline subtree is missing or linked: $subtree" \
      || return
    [[ $(realpath -e -- "$subtree_root") == "$canonical_path/$subtree" ]] \
      || shibumi_baseline_fail \
        "Omarchy baseline subtree escapes its root: $subtree" || return

    entries=()
    mapfile -d '' entries < <(
      find "$subtree_root" -mindepth 1 -printf '%P\0' | LC_ALL=C sort -z
    )
    content_entries=()
    mapfile -d '' content_entries < <(
      find "$subtree_root" -mindepth 1 \( -type f -o -type l \) \
        -printf '%P\0' | LC_ALL=C sort -z
    )
    actual_count=${#entries[@]}
    [[ $actual_count == "$expected_count" ]] \
      || shibumi_baseline_fail \
        "Omarchy baseline inventory count drift: $subtree expected $expected_count, got $actual_count" \
      || return

    actual_inventory=$(printf '%s\0' "${entries[@]}" \
      | sha256sum | awk '{print $1}')
    [[ $actual_inventory == "$expected_inventory" ]] \
      || shibumi_baseline_fail \
        "Omarchy baseline inventory drift: $subtree expected $expected_inventory, got $actual_inventory" \
      || return

    for relative_path in "${entries[@]}"; do
      candidate="$subtree_root/$relative_path"
      if [[ -L $candidate ]]; then
        [[ $entry_policy == absolute-symlinks ]] \
          || shibumi_baseline_fail \
            "Omarchy baseline type drift: $subtree/$relative_path must be a regular file" \
          || return
        link_target=$(readlink -- "$candidate")
        [[ $link_target == /* && -f $candidate ]] \
          || shibumi_baseline_fail \
            "Omarchy baseline symlink target is invalid: $subtree/$relative_path -> $link_target" \
          || return
      elif [[ -d $candidate ]]; then
        :
      elif [[ -f $candidate ]]; then
        [[ $entry_policy == regular-files && -f $candidate ]] \
          || shibumi_baseline_fail \
            "Omarchy baseline type drift: $subtree/$relative_path must be an absolute symlink" \
          || return
      else
        shibumi_baseline_fail \
          "Omarchy baseline contains an unsupported entry type: $subtree/$relative_path" \
          || return
      fi
    done

    actual_structure=$(
      for relative_path in "${entries[@]}"; do
        candidate="$subtree_root/$relative_path"
        executable=0
        [[ -x $candidate ]] && executable=1
        if [[ -L $candidate ]]; then
          link_target=$(readlink -- "$candidate")
          printf '%s\0symlink\0%s\0%s\0' \
            "$relative_path" "$link_target" "$executable"
        elif [[ -d $candidate ]]; then
          printf '%s\0directory\0%s\0' "$relative_path" "$executable"
        else
          printf '%s\0file\0%s\0' "$relative_path" "$executable"
        fi
      done | sha256sum | awk '{print $1}'
    )
    [[ $actual_structure == "$expected_structure" ]] \
      || shibumi_baseline_fail \
        "Omarchy baseline structure drift: $subtree expected $expected_structure, got $actual_structure" \
      || return

    actual_content=$(
      cd "$subtree_root" || exit 1
      sha256sum -- "${content_entries[@]}" | sha256sum | awk '{print $1}'
    )
    [[ $actual_content == "$expected_content" ]] \
      || shibumi_baseline_fail \
        "Omarchy baseline content drift: $subtree expected $expected_content, got $actual_content" \
      || return
  done < <(jq -r '
    .subtrees[] |
    [.path, .entryPolicy, .entryCount, .inventorySha256,
     .structureSha256, .contentSha256] | @tsv
  ' "$canonical_manifest")

  SHIBUMI_VALIDATED_OMARCHY_PATH=$canonical_path
  SHIBUMI_VALIDATED_OMARCHY_BASELINE=$canonical_manifest
}

shibumi_validate_agents_baseline_schema() {
  shibumi_require_baseline_tools || return

  local requested_manifest=${1:-}
  [[ $requested_manifest == /* && -f $requested_manifest \
    && -r $requested_manifest ]] \
    || shibumi_baseline_fail \
      "Omarchy agents manifest is unreadable: $requested_manifest" || return

  jq -e '
    .schemaVersion == 1
    and .id == "omarchy-agents-b99fd91"
    and .profile == "agents-current"
    and .repository == "https://github.com/basecamp/omarchy"
    and .sourceRevision == "b99fd91cf11db92b03bbd69e4fff908662bd74a3"
    and .provenance.kind == "git"
    and .provenance.revision == .sourceRevision
    and (.files | type == "object" and length == 6)
    and ((.files | keys | sort) == [
      "bin/omarchy-agent-usage-claude",
      "bin/omarchy-agent-usage-codex",
      "bin/omarchy-agent-usage-update",
      "shell/plugins/agents/Agent.qml",
      "shell/plugins/agents/Main.qml",
      "shell/plugins/agents/manifest.json"
    ])
    and all(.files | to_entries[];
      (.key | type == "string" and length > 0
        and (startswith("/") | not)
        and (contains("..") | not))
      and (.value | test("^[0-9a-f]{64}$")))
  ' "$requested_manifest" >/dev/null \
    || shibumi_baseline_fail \
      "Omarchy agents baseline schema is invalid: $requested_manifest" \
    || return
}

shibumi_validate_agents_baseline() {
  shibumi_require_baseline_tools || return

  local requested_path=${1:-}
  local requested_manifest=${2:-}
  [[ $requested_path == /* ]] \
    || shibumi_baseline_fail 'OMARCHY_PATH must be absolute' || return
  [[ -d $requested_path ]] \
    || shibumi_baseline_fail \
      "Omarchy agents baseline root is missing: $requested_path" || return
  shibumi_validate_agents_baseline_schema "$requested_manifest" || return

  local canonical_path canonical_manifest expected_revision actual_revision
  canonical_path=$(realpath -e -- "$requested_path") \
    || shibumi_baseline_fail \
      "cannot resolve OMARCHY_PATH: $requested_path" || return
  canonical_manifest=$(realpath -e -- "$requested_manifest") \
    || shibumi_baseline_fail \
      "cannot resolve agents manifest: $requested_manifest" || return
  command -v git >/dev/null 2>&1 \
    || shibumi_baseline_fail 'git is required for agents-current' || return
  expected_revision=$(jq -r '.sourceRevision' "$canonical_manifest")
  actual_revision=$(git -C "$canonical_path" rev-parse HEAD 2>/dev/null) \
    || shibumi_baseline_fail \
      "agents-current baseline is not a Git checkout: $canonical_path" \
    || return
  [[ $actual_revision == "$expected_revision" ]] \
    || shibumi_baseline_fail \
      "agents-current revision drift: expected $expected_revision, got $actual_revision" \
    || return

  local relative_path expected_hash candidate actual_hash
  while IFS=$'\t' read -r relative_path expected_hash; do
    candidate="$canonical_path/$relative_path"
    [[ -f $candidate && ! -L $candidate ]] \
      || shibumi_baseline_fail \
        "agents-current file is missing or linked: $relative_path" || return
    [[ $(realpath -e -- "$candidate") == "$canonical_path/$relative_path" ]] \
      || shibumi_baseline_fail \
        "agents-current file escapes its root: $relative_path" || return
    actual_hash=$(sha256sum "$candidate" | awk '{print $1}')
    [[ $actual_hash == "$expected_hash" ]] \
      || shibumi_baseline_fail \
        "agents-current content drift: $relative_path" || return
  done < <(jq -r '.files | to_entries[] | [.key, .value] | @tsv' \
    "$canonical_manifest")

  SHIBUMI_VALIDATED_OMARCHY_PATH=$canonical_path
  SHIBUMI_VALIDATED_OMARCHY_BASELINE=$canonical_manifest
}

shibumi_load_omarchy_baseline() {
  shibumi_require_baseline_tools || return

  local profile=${SHIBUMI_OMARCHY_BASELINE_PROFILE:-installed-package}
  local requested_path manifest
  case $profile in
    installed-package)
      requested_path=${OMARCHY_PATH:-/usr/share/omarchy}
      manifest="$shibumi_baseline_repo_root/contracts/baselines/omarchy-installed-package-b99fd91.json"
      ;;
    installed-source-parity)
      requested_path=${OMARCHY_PATH:-}
      [[ -n $requested_path ]] \
        || shibumi_baseline_fail \
          'OMARCHY_PATH is required for installed-source-parity' || return
      manifest="$shibumi_baseline_repo_root/contracts/baselines/omarchy-installed-source-parity-b99fd91.json"
      ;;
    forward-compat)
      requested_path=${OMARCHY_PATH:-}
      [[ -n $requested_path ]] \
        || shibumi_baseline_fail \
          'OMARCHY_PATH is required for forward-compat' || return
      manifest="$shibumi_baseline_repo_root/contracts/baselines/omarchy-forward-compat-d6b21f80.json"
      ;;
    agents-current)
      requested_path=${OMARCHY_PATH:-}
      [[ -n $requested_path ]] \
        || shibumi_baseline_fail \
          'OMARCHY_PATH is required for agents-current' || return
      manifest="$shibumi_baseline_repo_root/contracts/baselines/omarchy-agents-b99fd91.json"
      shibumi_validate_agents_baseline "$requested_path" "$manifest" || return
      ;;
    *)
      shibumi_baseline_fail "unsupported Omarchy baseline profile: $profile"
      return
      ;;
  esac

  if [[ $profile != agents-current ]]; then
    shibumi_validate_omarchy_tree "$requested_path" "$manifest" || return
  fi
  local canonical_path=$SHIBUMI_VALIDATED_OMARCHY_PATH
  local canonical_manifest=$SHIBUMI_VALIDATED_OMARCHY_BASELINE

  [[ $(jq -r '.profile' "$canonical_manifest") == "$profile" ]] \
    || shibumi_baseline_fail \
      "baseline profile mismatch in $canonical_manifest" || return

  if [[ $profile == installed-source-parity || $profile == forward-compat \
      || $profile == agents-current ]]; then
    command -v git >/dev/null 2>&1 \
      || shibumi_baseline_fail "git is required for $profile" \
      || return
    local expected_revision actual_revision
    expected_revision=$(jq -r '.sourceRevision' "$canonical_manifest")
    actual_revision=$(git -C "$canonical_path" rev-parse HEAD 2>/dev/null) \
      || shibumi_baseline_fail \
        "$profile Omarchy baseline is not a Git checkout: $canonical_path" \
      || return
    [[ $actual_revision == "$expected_revision" ]] \
      || shibumi_baseline_fail \
        "$profile Omarchy revision drift: expected $expected_revision, got $actual_revision" \
      || return
  fi

  OMARCHY_PATH=$canonical_path
  SHIBUMI_OMARCHY_BASELINE=$canonical_manifest
  SHIBUMI_OMARCHY_BASELINE_PROFILE=$profile
  SHIBUMI_OMARCHY_BASELINE_ID=$(jq -r '.id' "$canonical_manifest")
  SHIBUMI_OMARCHY_SOURCE_REVISION=$(jq -r '.sourceRevision' "$canonical_manifest")
  export OMARCHY_PATH SHIBUMI_OMARCHY_BASELINE
  export SHIBUMI_OMARCHY_BASELINE_PROFILE SHIBUMI_OMARCHY_BASELINE_ID
  export SHIBUMI_OMARCHY_SOURCE_REVISION
}
