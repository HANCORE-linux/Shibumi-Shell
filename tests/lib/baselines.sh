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
  [[ -x /usr/bin/jq ]] \
    || shibumi_baseline_fail '/usr/bin/jq is required' || return
  command -v realpath >/dev/null 2>&1 \
    || shibumi_baseline_fail 'realpath is required' || return
  command -v sha256sum >/dev/null 2>&1 \
    || shibumi_baseline_fail 'sha256sum is required' || return
  command -v sort >/dev/null 2>&1 \
    || shibumi_baseline_fail 'sort is required' || return
  command -v stat >/dev/null 2>&1 \
    || shibumi_baseline_fail 'stat is required' || return
  [[ -x /usr/bin/python3 ]] \
    || shibumi_baseline_fail '/usr/bin/python3 is required' || return
}

shibumi_read_unique_json_snapshot() {
  local manifest=${1:-}
  /usr/bin/python3 -I - "$manifest" <<'PY'
import json
import math
import os
import stat
import sys


MAX_BYTES = 65536


def reject_duplicates(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate key: {key}")
        value[key] = item
    return value


def reject_nonfinite(value):
    raise ValueError(f"non-finite number: {value}")


def parse_finite_float(value):
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite float: {value}")
    return parsed


flags = os.O_RDONLY | os.O_CLOEXEC
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW
descriptor = os.open(sys.argv[1], flags)
try:
    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode):
        raise ValueError("manifest is not a regular file")
    payload = bytearray()
    while len(payload) <= MAX_BYTES:
        chunk = os.read(descriptor, min(8192, MAX_BYTES + 1 - len(payload)))
        if not chunk:
            break
        payload.extend(chunk)
    if not payload or len(payload) > MAX_BYTES:
        raise ValueError("manifest size is invalid")
finally:
    os.close(descriptor)
text = bytes(payload).decode("utf-8", errors="strict")
json.loads(
    text,
    object_pairs_hook=reject_duplicates,
    parse_constant=reject_nonfinite,
    parse_float=parse_finite_float,
)
sys.stdout.write(text)
PY
}

shibumi_validate_unique_json_keys() {
  local manifest=${1:-}
  shibumi_read_unique_json_snapshot "$manifest" >/dev/null 2>&1 \
    || shibumi_baseline_fail \
      "baseline manifest has duplicate or ambiguous JSON fields: $manifest" \
    || return
}

# Every later jq projection of an accepted manifest consumes the same bounded
# in-memory snapshot. Replacing or growing the pathname cannot change the
# identity between schema validation, tree validation, and provenance checks.
jq() {
  local argument_count=$#
  local final_argument=
  if (( argument_count > 0 )); then
    final_argument=${!argument_count}
  fi
  local snapshot_path=${SHIBUMI_BASELINE_JSON_PATH:-}
  local snapshot_json=${SHIBUMI_BASELINE_JSON:-}
  if [[ ${SHIBUMI_SCHEMA_SNAPSHOT_ACTIVE:-} == 1 ]]; then
    snapshot_path=${SHIBUMI_SCHEMA_SNAPSHOT_PATH:-}
    snapshot_json=${SHIBUMI_SCHEMA_SNAPSHOT_JSON:-}
  fi
  if [[ -n $snapshot_path && $final_argument == "$snapshot_path" ]]; then
    local -a snapshot_arguments=("${@:1:argument_count-1}")
    /usr/bin/jq "${snapshot_arguments[@]}" <<<"$snapshot_json"
  else
    /usr/bin/jq "$@"
  fi
}

shibumi_validate_omarchy_baseline_schema() {
  SHIBUMI_BASELINE_JSON=
  SHIBUMI_BASELINE_JSON_PATH=
  local manifest=${1:-}
  [[ -n $manifest && $manifest == /* ]] \
    || shibumi_baseline_fail 'baseline manifest path must be absolute' || return
  [[ -e $manifest ]] \
    || shibumi_baseline_fail "baseline manifest is missing: $manifest" || return
  [[ -f $manifest && -r $manifest ]] \
    || shibumi_baseline_fail "baseline manifest is unreadable: $manifest" || return
  local SHIBUMI_SCHEMA_SNAPSHOT_ACTIVE=1
  local SHIBUMI_SCHEMA_SNAPSHOT_JSON
  local SHIBUMI_SCHEMA_SNAPSHOT_PATH=$manifest
  SHIBUMI_SCHEMA_SNAPSHOT_JSON=$(shibumi_read_unique_json_snapshot \
      "$manifest" 2>/dev/null) \
    || shibumi_baseline_fail \
      "baseline manifest has duplicate or ambiguous JSON fields: $manifest" \
    || return
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
    if .id == "installed-package-v4.0.2"
        or .id == "installed-source-parity-v4.0.2"
        or .id == "forward-compat-ed7bae4a" then
      .quickshellPackage == {"name": "quickshell", "version": "0.3.1-1"}
    elif .id == "installed-package-v4.0.0"
        or .id == "installed-source-parity-v4.0.0" then
      .quickshellPackage == {
        "name": "quickshell-git",
        "version": "0.3.0.r20.g28771c7-1"
      }
    else
      false
    end
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
        if .id == "installed-package-v4.0.2" then
          .provenance.kind == "package"
          and (.provenance.packages | type == "array" and length == 2)
          and ([.provenance.packages[].name] | sort
            == ["omarchy", "omarchy-settings"])
          and ([.provenance.packages[].name] | unique | length == 2)
          and all(.provenance.packages[];
            (.name | type == "string"
              and test("^[a-z0-9@._+:-]+$")
              and length <= 64)
            and (.version | type == "string"
              and test("^[A-Za-z0-9@._+:-]+$")
              and length <= 128))
          and (.provenance.subtreeOwners | type == "object")
          and (.provenance.subtreeOwners | keys | sort
            == ["bin", "config", "shell"])
          and .provenance.subtreeOwners.bin == "omarchy"
          and .provenance.subtreeOwners.config == "omarchy-settings"
          and .provenance.subtreeOwners.shell == "omarchy"
        elif .id == "installed-package-v4.0.0" then
          .sourceRevision
            == "f0020448ca87329199de7cb12f2015ebc4a3e5e7"
          and .provenance == {"kind": "package"}
          and .package == {"name": "omarchy", "version": "4.0.0-1"}
          and .quickshellPackage.name == "quickshell-git"
        else
          false
        end
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
  SHIBUMI_BASELINE_JSON=$SHIBUMI_SCHEMA_SNAPSHOT_JSON
  SHIBUMI_BASELINE_JSON_PATH=$SHIBUMI_SCHEMA_SNAPSHOT_PATH
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
  # The schema reader already opened this exact absolute path with O_NOFOLLOW.
  # Keep using its in-memory snapshot instead of resolving or reopening it.
  canonical_manifest=$requested_manifest

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

shibumi_require_exact_package_identity() {
  local label=${1:-package}
  local expected_name=${2:-}
  local expected_version=${3:-}
  local actual_identity=${4:-}
  [[ $actual_identity == "$expected_name $expected_version" ]] \
    || shibumi_baseline_fail \
      "$label identity drift: expected $expected_name $expected_version, got $actual_identity" \
    || return
}

shibumi_require_exact_subtree_owner() {
  local subtree=${1:-}
  local expected_owner=${2:-}
  local actual_owner=${3:-}
  [[ $actual_owner == "$expected_owner" ]] \
    || shibumi_baseline_fail \
      "Omarchy subtree owner drift: expected $subtree -> $expected_owner, got $actual_owner" \
    || return
}

shibumi_validate_quickshell_package_provenance() {
  shibumi_require_baseline_tools || return

  local requested_manifest=${1:-}
  local reuse_snapshot=${2:-}
  if [[ $reuse_snapshot == reuse ]]; then
    [[ ${SHIBUMI_BASELINE_JSON_PATH:-} == "$requested_manifest" ]] \
      || shibumi_baseline_fail \
        "Quickshell provenance has no matching baseline snapshot" || return
  else
    shibumi_validate_omarchy_baseline_schema "$requested_manifest" || return
  fi
  [[ -x /usr/bin/pacman ]] \
    || shibumi_baseline_fail "/usr/bin/pacman is required" || return

  local package_name expected_version actual_identity
  package_name=$(jq -r '.quickshellPackage.name' "$requested_manifest")
  expected_version=$(jq -r '.quickshellPackage.version' "$requested_manifest")
  actual_identity=$(/usr/bin/pacman -Q -- "$package_name" 2>/dev/null) \
    || shibumi_baseline_fail \
      "required Quickshell package is unavailable: $package_name" || return
  shibumi_require_exact_package_identity \
    "Quickshell package" "$package_name" "$expected_version" \
    "$actual_identity" || return
}

shibumi_validate_installed_package_provenance() {
  shibumi_require_baseline_tools || return

  local requested_path=${1:-}
  local requested_manifest=${2:-}
  local reuse_snapshot=${3:-}
  if [[ $reuse_snapshot == reuse ]]; then
    [[ ${SHIBUMI_BASELINE_JSON_PATH:-} == "$requested_manifest" ]] \
      || shibumi_baseline_fail \
        "installed package provenance has no matching baseline snapshot" \
      || return
  else
    shibumi_validate_omarchy_baseline_schema "$requested_manifest" || return
  fi
  [[ $(jq -r '.profile' "$requested_manifest") == installed-package \
      && $(jq -r '.id' "$requested_manifest") == installed-package-v4.0.2 ]] \
    || shibumi_baseline_fail \
      "installed package provenance requires the active installed-package manifest" \
    || return

  local canonical_path
  canonical_path=$(realpath -e -- "$requested_path") \
    || shibumi_baseline_fail \
      "cannot resolve installed Omarchy package root: $requested_path" || return
  [[ $canonical_path == /usr/share/omarchy ]] \
    || shibumi_baseline_fail \
      "installed-package baseline requires /usr/share/omarchy" || return
  [[ -x /usr/bin/pacman ]] \
    || shibumi_baseline_fail "/usr/bin/pacman is required" || return

  local package_name expected_version actual_identity
  while IFS=$'\t' read -r package_name expected_version; do
    actual_identity=$(/usr/bin/pacman -Q -- "$package_name" 2>/dev/null) \
      || shibumi_baseline_fail \
        "required host package is unavailable: $package_name" || return
    shibumi_require_exact_package_identity \
      "host package" "$package_name" "$expected_version" "$actual_identity" \
      || return
  done < <(jq -r '.provenance.packages[] | [.name, .version] | @tsv' \
    "$requested_manifest")

  local subtree expected_owner actual_owner
  while IFS=$'\t' read -r subtree expected_owner; do
    actual_owner=$(/usr/bin/pacman -Qqo -- "$canonical_path/$subtree" 2>/dev/null) \
      || shibumi_baseline_fail \
        "cannot resolve package owner for Omarchy subtree: $subtree" || return
    shibumi_require_exact_subtree_owner \
      "$subtree" "$expected_owner" "$actual_owner" || return
  done < <(jq -r '
    .provenance.subtreeOwners | to_entries[] | [.key, .value] | @tsv
  ' "$requested_manifest")
}

shibumi_validate_agents_baseline_schema() {
  SHIBUMI_BASELINE_JSON=
  SHIBUMI_BASELINE_JSON_PATH=
  shibumi_require_baseline_tools || return

  local requested_manifest=${1:-}
  [[ $requested_manifest == /* && -f $requested_manifest \
    && -r $requested_manifest ]] \
    || shibumi_baseline_fail \
      "Omarchy agents manifest is unreadable: $requested_manifest" || return
  local SHIBUMI_SCHEMA_SNAPSHOT_ACTIVE=1
  local SHIBUMI_SCHEMA_SNAPSHOT_JSON
  local SHIBUMI_SCHEMA_SNAPSHOT_PATH=$requested_manifest
  SHIBUMI_SCHEMA_SNAPSHOT_JSON=$(shibumi_read_unique_json_snapshot \
      "$requested_manifest" 2>/dev/null) \
    || shibumi_baseline_fail \
      "Omarchy agents manifest has duplicate or ambiguous JSON fields: $requested_manifest" \
    || return

  jq -e '
    .schemaVersion == 1
    and .id == "omarchy-agents-v4.0.0"
    and .profile == "agents-current"
    and .repository == "https://github.com/basecamp/omarchy"
    and .sourceRevision == "f0020448ca87329199de7cb12f2015ebc4a3e5e7"
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
  SHIBUMI_BASELINE_JSON=$SHIBUMI_SCHEMA_SNAPSHOT_JSON
  SHIBUMI_BASELINE_JSON_PATH=$SHIBUMI_SCHEMA_SNAPSHOT_PATH
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
  # The schema reader already opened this exact absolute path with O_NOFOLLOW.
  # Keep using its in-memory snapshot instead of resolving or reopening it.
  canonical_manifest=$requested_manifest
  command -v git >/dev/null 2>&1 \
    || shibumi_baseline_fail 'git is required for agents-current' || return
  expected_revision=$(jq -r '.sourceRevision' "$canonical_manifest")
  actual_revision=$(git -C "$canonical_path" rev-parse 'HEAD^{commit}' 2>/dev/null) \
    || shibumi_baseline_fail \
      "agents-current baseline has no resolvable HEAD commit: $canonical_path" \
    || return
  git -C "$canonical_path" cat-file -e "$expected_revision^{commit}" 2>/dev/null \
    || shibumi_baseline_fail \
      "agents-current baseline is missing its declared commit object" \
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
      requested_path=/usr/share/omarchy
      manifest="$shibumi_baseline_repo_root/contracts/baselines/omarchy-installed-package-v4.0.2.json"
      ;;
    installed-source-parity)
      requested_path=${OMARCHY_PATH:-}
      [[ -n $requested_path ]] \
        || shibumi_baseline_fail \
          'OMARCHY_PATH is required for installed-source-parity' || return
      manifest="$shibumi_baseline_repo_root/contracts/baselines/omarchy-installed-source-parity-v4.0.2.json"
      ;;
    forward-compat)
      requested_path=${OMARCHY_PATH:-}
      [[ -n $requested_path ]] \
        || shibumi_baseline_fail \
          'OMARCHY_PATH is required for forward-compat' || return
      manifest="$shibumi_baseline_repo_root/contracts/baselines/omarchy-forward-compat-ed7bae4a.json"
      ;;
    agents-current)
      requested_path=${OMARCHY_PATH:-}
      [[ -n $requested_path ]] \
        || shibumi_baseline_fail \
          'OMARCHY_PATH is required for agents-current' || return
      manifest="$shibumi_baseline_repo_root/contracts/baselines/omarchy-agents-v4.0.0.json"
      shibumi_validate_agents_baseline "$requested_path" "$manifest" || return
      ;;
    *)
      shibumi_baseline_fail "unsupported Omarchy baseline profile: $profile"
      return
      ;;
  esac

  if [[ $profile != agents-current ]]; then
    shibumi_validate_omarchy_tree "$requested_path" "$manifest" || return
    shibumi_validate_quickshell_package_provenance "$manifest" reuse || return
    if [[ $profile == installed-package ]]; then
      shibumi_validate_installed_package_provenance \
        "$requested_path" "$manifest" reuse || return
    fi
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
    actual_revision=$(git -C "$canonical_path" rev-parse 'HEAD^{commit}' 2>/dev/null) \
      || shibumi_baseline_fail \
        "$profile Omarchy baseline has no resolvable HEAD commit: $canonical_path" \
      || return
    git -C "$canonical_path" cat-file -e "$expected_revision^{commit}" \
      2>/dev/null \
      || shibumi_baseline_fail \
        "$profile Omarchy baseline is missing its declared commit object" \
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

shibumi_stage_suite_runtime() {
  local repo_root=$1 fixture_root=$2
  local state_root="$fixture_root/hancore.shibumi.state"
  mkdir -p "$state_root"
  cp -a -- "$repo_root/hancore.shibumi.state/runtime" "$state_root/"
}
