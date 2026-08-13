#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/tests/lib/baselines.sh"
installed_package_baseline="$repo_root/contracts/baselines/omarchy-installed-package-b99fd91.json"
installed_source_baseline="$repo_root/contracts/baselines/omarchy-installed-source-parity-b99fd91.json"
forward_compat_baseline="$repo_root/contracts/baselines/omarchy-forward-compat-d6b21f80.json"
agents_baseline="$repo_root/contracts/baselines/omarchy-agents-b99fd91.json"
predecessor_baseline="$repo_root/contracts/baselines/quickshell-dots-d0896fc-v2-deec8103.json"
installed_package_job="$repo_root/tests/omarchy-installed-package-contract-regression.sh"
installed_source_job="$repo_root/tests/omarchy-installed-source-parity-contract-regression.sh"
forward_compat_job="$repo_root/tests/omarchy-forward-compat-contract-regression.sh"
malformed_fixture="$repo_root/tests/fixtures/baselines/malformed.json"

fail() {
  printf 'baseline contract regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail 'jq is required'
command -v mkfifo >/dev/null 2>&1 || fail 'mkfifo is required'
command -v rg >/dev/null 2>&1 || fail 'ripgrep is required'
command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required'

[[ -r $helper ]] || fail 'central test baseline helper is missing'
[[ -r $installed_package_baseline ]] \
  || fail 'installed-package Omarchy baseline is missing'
[[ -r $installed_source_baseline ]] \
  || fail 'installed-source-parity Omarchy baseline is missing'
[[ -r $forward_compat_baseline ]] \
  || fail 'forward-compat Omarchy baseline is missing'
[[ -r $agents_baseline ]] || fail 'Agents Omarchy baseline is missing'
[[ ! -e $repo_root/contracts/baselines/omarchy-12af188.json ]] \
  || fail 'legacy nine-file Omarchy baseline is still present'
[[ ! -e $repo_root/contracts/baselines/omarchy-installed-12af188.json ]] \
  || fail 'ambiguous installed baseline name is still present'
[[ ! -e $repo_root/contracts/baselines/omarchy-upstream-12af188.json ]] \
  || fail 'ambiguous upstream baseline name is still present'
[[ -r $predecessor_baseline ]] || fail 'pinned predecessor baseline is missing'
[[ -r $malformed_fixture ]] || fail 'malformed baseline fixture is missing'
[[ -x $installed_package_job ]] \
  || fail 'installed-package job is missing or not executable'
[[ -x $installed_source_job ]] \
  || fail 'installed-source-parity job is missing or not executable'
[[ -x $forward_compat_job ]] \
  || fail 'forward-compat job is missing or not executable'
[[ -x $repo_root/tests/reference-baseline-regression.sh ]] \
  || fail 'predecessor baseline regression is missing or not executable'

# shellcheck source=tests/lib/baselines.sh
source "$helper"
for manifest in \
  "$installed_package_baseline" \
  "$installed_source_baseline" \
  "$forward_compat_baseline"; do
  shibumi_validate_omarchy_baseline_schema "$manifest" \
    || fail "$(basename "$manifest") does not satisfy the central schema"
done

jq -e '
  .id == "installed-package-b99fd91"
  and .profile == "installed-package"
  and .sourceRevision == "b99fd91cf11db92b03bbd69e4fff908662bd74a3"
  and .provenance.kind == "package"
  and .package.name == "omarchy-dev"
  and .package.version == "4.0.0.r1664.gb99fd91-1"
  and ([.subtrees[] | select(.path == "bin" and .entryPolicy == "absolute-symlinks")] | length) == 1
  and all(.subtrees[] | select(.path != "bin"); .entryPolicy == "regular-files")
' "$installed_package_baseline" >/dev/null \
  || fail 'installed-package baseline identity or provenance is invalid'
jq -e '
  .id == "installed-source-parity-b99fd91"
  and .profile == "installed-source-parity"
  and .sourceRevision == "b99fd91cf11db92b03bbd69e4fff908662bd74a3"
  and .provenance.kind == "git"
  and .provenance.revision == .sourceRevision
  and all(.subtrees[]; .entryPolicy == "regular-files")
' "$installed_source_baseline" >/dev/null \
  || fail 'installed-source-parity baseline identity or provenance is invalid'
jq -e '
  .id == "forward-compat-d6b21f80"
  and .profile == "forward-compat"
  and .sourceRevision == "d6b21f80750ccaf488373973f1ee25db21de7d26"
  and .provenance.kind == "git"
  and .provenance.revision == .sourceRevision
  and all(.subtrees[]; .entryPolicy == "regular-files")
' "$forward_compat_baseline" >/dev/null \
  || fail 'forward-compat baseline identity or provenance is invalid'

agents_fixture=$(mktemp)
trap 'rm -f -- "$agents_fixture"' EXIT
cp "$agents_baseline" "$agents_fixture"
shibumi_validate_agents_baseline_schema "$agents_baseline" \
  || fail 'Agents baseline does not satisfy its central schema'
jq '.sourceRevision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .provenance.revision = .sourceRevision' \
  "$agents_baseline" >"$agents_fixture"
if shibumi_validate_agents_baseline_schema \
    "$agents_fixture" >/dev/null 2>&1; then
  fail 'Agents baseline accepts revision substitution'
fi
jq 'del(.files["shell/plugins/agents/Agent.qml"])
  | .files["shell/plugins/agents/README.md"] =
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  "$agents_baseline" >"$agents_fixture"
if shibumi_validate_agents_baseline_schema \
    "$agents_fixture" >/dev/null 2>&1; then
  fail 'Agents baseline accepts contracted path substitution'
fi

jq -e '
  .schemaVersion == 1
  and (.id | type == "string" and length > 0)
  and (.repository | type == "string" and startswith("https://"))
  and (.roots.v1.provenance == "git")
  and (.roots.v1.revision | test("^[0-9a-f]{40}$"))
  and (.roots.v1EmbeddedV2.provenance == "git")
  and (.roots.v2.provenance == "content-snapshot")
  and all(.roots[];
    (.sourceCount | type == "number" and . > 0)
    and (.inventorySha256 | test("^[0-9a-f]{64}$"))
    and (.contentSha256 | test("^[0-9a-f]{64}$")))
' "$predecessor_baseline" >/dev/null \
  || fail 'predecessor baseline schema is invalid'

if rg -n '/home/hancore/Projects/(omarchy-updates-pr|Quickshell-Dots)' \
    "$repo_root/tests" "$repo_root/contracts" \
    "$repo_root/docs/development/testing.md" \
    "$repo_root/docs/development/setup.md" \
    "$repo_root/docs/release-readiness.md"; then
  fail 'active test contracts retain a maintainer-private baseline path'
fi

for contract in \
  contracts/v1-feature-evidence.json \
  contracts/v2-source-evidence.json \
  contracts/v2-feature-port.json \
  contracts/v2-feature-evidence.json \
  contracts/v1-embedded-v2-differences.json; do
  jq -e --arg baseline "contracts/baselines/$(basename "$predecessor_baseline")" '
    .referenceBaseline == $baseline
    and (.referenceRootId | type == "string" and length > 0)
  ' "$repo_root/$contract" >/dev/null \
    || fail "$contract is not bound to the portable predecessor baseline"
done

mapfile -t host_scripts < <(
  rg -l 'OMARCHY_PATH|tests/lib/baselines\.sh|shibumi_load_omarchy_baseline' \
    "$repo_root/tests"/*.sh | sort
)
for script in "${host_scripts[@]}"; do
  case $script in
    "$repo_root/tests/baseline-contract-regression.sh" | \
      "$installed_package_job" | "$installed_source_job" | \
      "$forward_compat_job") continue ;;
  esac
  rg -q '^[[:space:]]*source[[:space:]]+.*tests/lib/baselines\.sh' "$script" \
    || fail "$(basename "$script") bypasses the central Omarchy baseline helper"
  rg -q '^[[:space:]]*shibumi_load_omarchy_baseline[[:space:]]*(#.*)?$' \
    "$script" \
    || fail "$(basename "$script") imports but does not invoke the Omarchy baseline loader"
done

rg -Fq 'SHIBUMI_OMARCHY_BASELINE_PROFILE=installed-package' \
  "$installed_package_job" \
  || fail 'installed-package job selects the wrong baseline'
rg -Fq 'SHIBUMI_OMARCHY_BASELINE_PROFILE=installed-source-parity' \
  "$installed_source_job" \
  || fail 'installed-source-parity job selects the wrong baseline'
rg -Fq 'SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH' "$installed_source_job" \
  || fail 'installed-source-parity job has no portable checkout input'
rg -Fq 'SHIBUMI_OMARCHY_BASELINE_PROFILE=forward-compat' \
  "$forward_compat_job" \
  || fail 'forward-compat job selects the wrong baseline'
rg -Fq 'SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH' "$forward_compat_job" \
  || fail 'forward-compat job has no portable checkout input'

contract_runner="$repo_root/tests/contract-regression.sh"
rg -Fq 'shibumi_load_omarchy_baseline' "$contract_runner" \
  || fail 'aggregate does not require an Omarchy baseline'
if rg -Fq 'if [[ -n ${OMARCHY_PATH:-}' "$contract_runner"; then
  fail 'aggregate still makes installed-host coverage optional'
fi
rg -Fq 'Shibumi complete contract regression passed' "$contract_runner" \
  || fail 'aggregate does not distinguish complete success'

# Resolve and validate the caller-selected host before using it as the sole
# source for the disposable identity fixture.
shibumi_load_omarchy_baseline
selected_host_path=$OMARCHY_PATH
selected_manifest=$SHIBUMI_OMARCHY_BASELINE
selected_profile=$SHIBUMI_OMARCHY_BASELINE_PROFILE
selected_id=$SHIBUMI_OMARCHY_BASELINE_ID

mapfile -t available_locales < <(locale -a)
resolve_required_locale() {
  local label=$1
  shift
  local candidate available
  for candidate in "$@"; do
    for available in "${available_locales[@]}"; do
      if [[ ${available,,} == "${candidate,,}" ]]; then
        printf '%s\n' "$available"
        return 0
      fi
    done
  done
  fail "required EA-010 locale is unavailable: $label"
}

locale_matrix=(
  "$(resolve_required_locale C C POSIX)"
  "$(resolve_required_locale C.UTF-8 C.UTF-8 C.utf8)"
  "$(resolve_required_locale en_US.UTF-8 en_US.UTF-8 en_US.utf8)"
)
for validation_locale in "${locale_matrix[@]}"; do
  LC_ALL=$validation_locale shibumi_validate_omarchy_tree \
    "$selected_host_path" "$selected_manifest" \
    || fail "central helper rejected exact baseline bytes under $validation_locale"
done

fixture=$(mktemp -d /tmp/shibumi-baseline-contract.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
while IFS= read -r subtree; do
  [[ -d $selected_host_path/$subtree ]] \
    || fail "selected baseline subtree is missing: $subtree"
  mkdir -p "$fixture/omarchy"
  cp -a "$selected_host_path/$subtree" "$fixture/omarchy/$subtree"
done < <(jq -r '.subtrees[].path' "$selected_manifest")

shibumi_validate_omarchy_tree "$fixture/omarchy" "$selected_manifest" \
  || fail 'central helper rejected the exact selected subtree bytes'

printf '\n// EA-010 consumed-host mutation probe\n' \
  >>"$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
if shibumi_validate_omarchy_tree \
    "$fixture/omarchy" "$selected_manifest" >/dev/null 2>&1; then
  fail 'central helper accepted drift in consumed audio/Panel.qml'
fi

cp "$selected_host_path/shell/plugins/panels/audio/Panel.qml" \
  "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
mkdir -p "$fixture/external"
cp "$selected_host_path/shell/plugins/panels/audio/Panel.qml" \
  "$fixture/external/Panel.qml"
rm -f "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
ln -s "$fixture/external/Panel.qml" \
  "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
if shibumi_validate_omarchy_tree \
    "$fixture/omarchy" "$selected_manifest" >/dev/null 2>&1; then
  fail 'central helper accepted a consumed file replaced by an external symlink'
fi

rm -f "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
cp "$selected_host_path/shell/plugins/panels/audio/Panel.qml" \
  "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
mkfifo "$fixture/omarchy/shell/EA010Unexpected.fifo"
if shibumi_validate_omarchy_tree \
    "$fixture/omarchy" "$selected_manifest" >/dev/null 2>&1; then
  fail 'central helper accepted an additional FIFO in the shell subtree'
fi
rm -f "$fixture/omarchy/shell/EA010Unexpected.fifo"

rm -f "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
mkfifo "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
unsupported_output=''
if unsupported_output=$(
  shibumi_validate_omarchy_tree \
    "$fixture/omarchy" "$selected_manifest" 2>&1
); then
  fail 'central helper accepted a consumed file replaced by a FIFO'
fi
[[ $unsupported_output == *'unsupported entry type'* ]] \
  || fail "FIFO substitution failed through the wrong invariant: $unsupported_output"
rm -f "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
cp "$selected_host_path/shell/plugins/panels/audio/Panel.qml" \
  "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"

mkdir "$fixture/omarchy/shell/EA010Unexpected.empty"
if shibumi_validate_omarchy_tree \
    "$fixture/omarchy" "$selected_manifest" >/dev/null 2>&1; then
  fail 'central helper accepted an additional empty directory in the shell subtree'
fi
rmdir "$fixture/omarchy/shell/EA010Unexpected.empty"

cp "$selected_host_path/shell/plugins/panels/audio/Panel.qml" \
  "$fixture/omarchy/shell/EA010Unexpected.qml"
if shibumi_validate_omarchy_tree \
    "$fixture/omarchy" "$selected_manifest" >/dev/null 2>&1; then
  fail 'central helper accepted an additional file in the shell subtree'
fi

rm -f "$fixture/omarchy/shell/EA010Unexpected.qml"
rm -f "$fixture/omarchy/shell/plugins/panels/audio/Panel.qml"
if shibumi_validate_omarchy_tree \
    "$fixture/omarchy" "$selected_manifest" >/dev/null 2>&1; then
  fail 'central helper accepted a missing file in the shell subtree'
fi

if shibumi_validate_omarchy_tree \
    "$selected_host_path" "$fixture/missing.json" >/dev/null 2>&1; then
  fail 'central helper accepted a missing baseline manifest'
fi

cp "$selected_manifest" "$fixture/unreadable.json"
chmod 000 "$fixture/unreadable.json"
if shibumi_validate_omarchy_tree \
    "$selected_host_path" "$fixture/unreadable.json" >/dev/null 2>&1; then
  fail 'central helper accepted an unreadable baseline manifest'
fi

if shibumi_validate_omarchy_tree \
    "$selected_host_path" "$malformed_fixture" >/dev/null 2>&1; then
  fail 'central helper accepted a syntactically malformed baseline manifest'
fi

assert_schema_rejected() {
  local name=$1
  local source_manifest=$2
  local mutation=$3
  local expected_error=$4
  local mutant="$fixture/invalid-$name.json"
  local validation_output

  jq "$mutation" "$source_manifest" >"$mutant" \
    || fail "could not build isolated $name manifest mutation"
  if validation_output=$(
    shibumi_validate_omarchy_baseline_schema "$mutant" 2>&1
  ); then
    fail "central helper accepted isolated $name manifest mutation"
  fi
  [[ $validation_output == *"$expected_error"* ]] \
    || fail "isolated $name mutation failed through the wrong invariant: $validation_output"
}

# Each mutation starts from an otherwise valid canonical manifest and changes
# one declared invariant. The expected diagnostic makes the cases resistant to
# accidentally passing through a different, later validation rule.
assert_schema_rejected schema-version "$installed_package_baseline" \
  '.schemaVersion = 1' 'baseline schemaVersion must be 2'
assert_schema_rejected empty-id "$installed_package_baseline" \
  '.id = ""' 'baseline id must be a non-empty string'
assert_schema_rejected unsupported-profile "$installed_package_baseline" \
  '.profile = "upstream"' 'baseline profile is unsupported'
assert_schema_rejected repository "$installed_package_baseline" \
  '.repository = "file:///not-an-upstream"' \
  'baseline repository is not authoritative'
assert_schema_rejected source-revision "$installed_package_baseline" \
  '.sourceRevision = "not-a-revision"' \
  'baseline sourceRevision must be a full commit SHA'
assert_schema_rejected provenance-object "$installed_package_baseline" \
  '.provenance = null' 'baseline provenance must be an object'
assert_schema_rejected quickshell-package-object "$installed_package_baseline" \
  '.quickshellPackage = null' \
  'baseline Quickshell package identity is invalid'
assert_schema_rejected quickshell-package-name "$installed_package_baseline" \
  '.quickshellPackage.name = ""' \
  'baseline Quickshell package identity is invalid'
assert_schema_rejected quickshell-package-version "$installed_package_baseline" \
  '.quickshellPackage.version = ""' \
  'baseline Quickshell package identity is invalid'
assert_schema_rejected subtrees-type "$installed_package_baseline" \
  '.subtrees = {}' 'baseline subtrees must be an array'
assert_schema_rejected subtree-count "$installed_package_baseline" \
  'del(.subtrees[2])' 'baseline must declare exactly three subtrees'
assert_schema_rejected empty-subtree-path "$installed_package_baseline" \
  '.subtrees[0].path = ""' \
  'baseline subtree path must be a non-empty string'
assert_schema_rejected path-traversal "$installed_package_baseline" \
  '.subtrees[0].path = "../shell"' \
  'baseline subtree path must be a safe root-relative name'
assert_schema_rejected duplicate-subtree "$installed_package_baseline" \
  '.subtrees[2].path = "shell"' \
  'baseline subtree set must be exactly bin, config, and shell'
assert_schema_rejected entry-policy "$installed_package_baseline" \
  '.subtrees[0].entryPolicy = "anything"' \
  'baseline subtree entryPolicy is invalid'
assert_schema_rejected entry-count-zero "$installed_package_baseline" \
  '.subtrees[0].entryCount = 0' \
  'baseline subtree entryCount must be a positive integer'
assert_schema_rejected entry-count-fraction "$installed_package_baseline" \
  '.subtrees[0].entryCount = 1.5' \
  'baseline subtree entryCount must be a positive integer'
assert_schema_rejected entry-count-type "$installed_package_baseline" \
  '.subtrees[0].entryCount = "170"' \
  'baseline subtree entryCount must be a positive integer'
assert_schema_rejected inventory-digest "$installed_package_baseline" \
  '.subtrees[0].inventorySha256 = "invalid"' \
  'baseline subtree inventorySha256 is invalid'
assert_schema_rejected structure-digest "$installed_package_baseline" \
  '.subtrees[0].structureSha256 = "invalid"' \
  'baseline subtree structureSha256 is invalid'
assert_schema_rejected content-digest "$installed_package_baseline" \
  '.subtrees[0].contentSha256 = "invalid"' \
  'baseline subtree contentSha256 is invalid'
assert_schema_rejected package-provenance-kind "$installed_package_baseline" \
  '.provenance.kind = "git"' \
  'installed-package provenance is invalid'
assert_schema_rejected package-object "$installed_package_baseline" \
  '.package = null' 'installed-package provenance is invalid'
assert_schema_rejected package-name "$installed_package_baseline" \
  '.package.name = ""' 'installed-package provenance is invalid'
assert_schema_rejected package-version "$installed_package_baseline" \
  '.package.version = ""' 'installed-package provenance is invalid'
assert_schema_rejected package-bin-policy "$installed_package_baseline" \
  '(.subtrees[] | select(.path == "bin")).entryPolicy = "regular-files"' \
  'installed-package subtree policy is invalid'
assert_schema_rejected package-source-policy "$installed_package_baseline" \
  '(.subtrees[] | select(.path == "shell")).entryPolicy = "absolute-symlinks"' \
  'installed-package subtree policy is invalid'
assert_schema_rejected source-provenance-kind "$installed_source_baseline" \
  '.provenance.kind = "package"' \
  'installed-source-parity Git provenance is invalid'
assert_schema_rejected source-provenance-revision "$installed_source_baseline" \
  '.provenance.revision = "0000000000000000000000000000000000000000"' \
  'installed-source-parity Git provenance is invalid'
assert_schema_rejected source-entry-policy "$installed_source_baseline" \
  '(.subtrees[] | select(.path == "bin")).entryPolicy = "absolute-symlinks"' \
  'installed-source-parity subtree policy is invalid'
assert_schema_rejected forward-provenance-kind "$forward_compat_baseline" \
  '.provenance.kind = "package"' \
  'forward-compat Git provenance is invalid'
assert_schema_rejected forward-provenance-revision "$forward_compat_baseline" \
  '.provenance.revision = "0000000000000000000000000000000000000000"' \
  'forward-compat Git provenance is invalid'
assert_schema_rejected forward-entry-policy "$forward_compat_baseline" \
  '(.subtrees[] | select(.path == "bin")).entryPolicy = "absolute-symlinks"' \
  'forward-compat subtree policy is invalid'

if (
  export SHIBUMI_OMARCHY_BASELINE_PROFILE=unsupported
  unset OMARCHY_PATH
  # shellcheck source=tests/lib/baselines.sh
  source "$helper"
  shibumi_load_omarchy_baseline
) >/dev/null 2>&1; then
  fail 'central helper accepted an unsupported baseline profile'
fi

[[ $selected_profile == installed-package \
  || $selected_profile == installed-source-parity \
  || $selected_profile == forward-compat ]] \
  || fail 'selected baseline profile was not exported'
"$repo_root/tests/reference-baseline-regression.sh"

printf 'baseline contract regression passed (%s; complete subtrees verified)\n' \
  "$selected_id"
