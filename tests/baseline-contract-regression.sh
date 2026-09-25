#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/tests/lib/baselines.sh"
installed_package_baseline="$repo_root/contracts/baselines/omarchy-installed-package-v4.0.4.json"
installed_source_baseline="$repo_root/contracts/baselines/omarchy-installed-source-parity-v4.0.4.json"
previous_package_baseline="$repo_root/contracts/baselines/omarchy-installed-package-v4.0.3.json"
previous_source_baseline="$repo_root/contracts/baselines/omarchy-installed-source-parity-v4.0.3.json"
compat_package_baseline="$repo_root/contracts/baselines/omarchy-installed-package-v4.0.2.json"
compat_source_baseline="$repo_root/contracts/baselines/omarchy-installed-source-parity-v4.0.2.json"
historical_package_baseline="$repo_root/contracts/baselines/omarchy-installed-package-v4.0.0.json"
historical_source_baseline="$repo_root/contracts/baselines/omarchy-installed-source-parity-v4.0.0.json"
forward_compat_baseline="$repo_root/contracts/baselines/omarchy-forward-compat-ed7bae4a.json"
agents_baseline="$repo_root/contracts/baselines/omarchy-agents-v4.0.0.json"
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
[[ -r $previous_package_baseline && -r $previous_source_baseline ]] \
  || fail 'Omarchy 4.0.3 compatibility baselines are missing'
[[ -r $compat_package_baseline && -r $compat_source_baseline ]] \
  || fail 'Omarchy 4.0.2 compatibility baselines are missing'
[[ -r $forward_compat_baseline ]] \
  || fail 'forward-compat Omarchy baseline is missing'
[[ -r $agents_baseline ]] || fail 'Agents Omarchy baseline is missing'
[[ ! -e $repo_root/contracts/baselines/omarchy-12af188.json ]] \
  || fail 'legacy nine-file Omarchy baseline is still present'
[[ ! -e $repo_root/contracts/baselines/omarchy-installed-12af188.json ]] \
  || fail 'ambiguous installed baseline name is still present'
[[ ! -e $repo_root/contracts/baselines/omarchy-upstream-12af188.json ]] \
  || fail 'ambiguous upstream baseline name is still present'
[[ -r $historical_package_baseline ]] \
  || fail 'historical beta.11 installed-package baseline is missing'
[[ -r $historical_source_baseline ]] \
  || fail 'historical beta.11 source-parity baseline is missing'
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
  "$previous_package_baseline" \
  "$previous_source_baseline" \
  "$compat_package_baseline" \
  "$compat_source_baseline" \
  "$historical_package_baseline" \
  "$historical_source_baseline" \
  "$forward_compat_baseline"; do
  shibumi_validate_omarchy_baseline_schema "$manifest" \
    || fail "$(basename "$manifest") does not satisfy the central schema"
done

jq -e '
  .id == "installed-package-v4.0.4"
  and .profile == "installed-package"
  and .sourceRevision == "c668141e9c42b13c80c9ca4ea108e11708c5e8a5"
  and .provenance.kind == "package"
  and ([.provenance.packages[] | [.name, .version]] | sort) == ([
    ["omarchy", "4.0.4-1"],
    ["omarchy-settings", "4.0.4-1"]
  ] | sort)
  and .provenance.subtreeOwners == {
    "bin": "omarchy",
    "config": "omarchy-settings",
    "shell": "omarchy"
  }
  and .quickshellPackage == {"name": "quickshell", "version": "0.3.1-1"}
  and ([.subtrees[] | select(.path == "bin" and .entryPolicy == "absolute-symlinks")] | length) == 1
  and all(.subtrees[] | select(.path != "bin"); .entryPolicy == "regular-files")
' "$installed_package_baseline" >/dev/null \
  || fail 'installed-package baseline identity or provenance is invalid'
[[ $(sha256sum "$historical_package_baseline" | awk '{print $1}') \
    == 902f3d0af5bfca48a83f658f46d7921e93a0d12c608bbf8bdcd230580c65b584 ]] \
  || fail 'published beta.11 installed-package manifest bytes drifted'
jq -e '
  .id == "installed-package-v4.0.0"
  and .profile == "installed-package"
  and .sourceRevision == "f0020448ca87329199de7cb12f2015ebc4a3e5e7"
  and .provenance == {"kind": "package"}
  and .package == {"name": "omarchy", "version": "4.0.0-1"}
  and .quickshellPackage.name == "quickshell-git"
' "$historical_package_baseline" >/dev/null \
  || fail 'historical installed-package baseline identity is invalid'
historical_source_matches() {
  [[ $(sha256sum "$1" | awk '{print $1}') \
      == 18e5740d2a07116d9c49e3e5046f7d8c82d4f4d7aab7b994340ded617f273610 ]]
}
historical_source_matches "$historical_source_baseline" \
  || fail 'published beta.11 source-parity manifest bytes drifted'
historical_source_mutant=$(mktemp)
cp "$historical_source_baseline" "$historical_source_mutant"
printf ' ' >>"$historical_source_mutant"
if historical_source_matches "$historical_source_mutant"; then
  fail 'historical source-parity digest accepts a one-byte mutation'
fi
rm -f -- "$historical_source_mutant"
jq -e '
  .id == "installed-source-parity-v4.0.0"
  and .profile == "installed-source-parity"
  and .sourceRevision == "f0020448ca87329199de7cb12f2015ebc4a3e5e7"
  and .provenance.revision == .sourceRevision
' "$historical_source_baseline" >/dev/null \
  || fail 'historical source-parity baseline identity is invalid'

jq -e '
  .id == "installed-source-parity-v4.0.4"
  and .profile == "installed-source-parity"
  and .sourceRevision == "c668141e9c42b13c80c9ca4ea108e11708c5e8a5"
  and .provenance.kind == "git"
  and .provenance.revision == .sourceRevision
  and .quickshellPackage == {"name": "quickshell", "version": "0.3.1-1"}
  and all(.subtrees[]; .entryPolicy == "regular-files")
' "$installed_source_baseline" >/dev/null \
  || fail 'installed-source-parity baseline identity or provenance is invalid'
[[ $(sha256sum "$installed_package_baseline" | awk '{print $1}') \
    == 9dfb421f339f282d762a1d0a000dc038bbe6f13e1b5f65c1f5e428d9522152c2 ]] \
  || fail 'Omarchy 4.0.4 installed-package manifest bytes drifted'
[[ $(sha256sum "$installed_source_baseline" | awk '{print $1}') \
    == 96229f17b4c18a077f484c681d1331865a3558b8c27c19b3cafaf047f91042dc ]] \
  || fail 'Omarchy 4.0.4 source-parity manifest bytes drifted'
[[ $(sha256sum "$previous_package_baseline" | awk '{print $1}') \
    == e5d4a6eeecf2c66a412615252567a95c5674f5ee74d420700cf92583931c8603 ]] \
  || fail 'Omarchy 4.0.3 installed-package manifest bytes drifted'
[[ $(sha256sum "$previous_source_baseline" | awk '{print $1}') \
    == af0cebefc6fa6dfff350cb7b86aae7538712bf4256adcba100a6ec9d5b3563e6 ]] \
  || fail 'Omarchy 4.0.3 source-parity manifest bytes drifted'
[[ $(sha256sum "$compat_package_baseline" | awk '{print $1}') \
    == 869b7068442d2682846f762cbcdcc56a593eecb83f03b8dc9a111ee18c460f4f ]] \
  || fail 'Omarchy 4.0.2 compatibility package manifest bytes drifted'
[[ $(sha256sum "$compat_source_baseline" | awk '{print $1}') \
    == 5d360bc579ec4248f47f276335fd57b8aa43dcf6e1ee1c05e34daaba9a5e36d4 ]] \
  || fail 'Omarchy 4.0.2 compatibility source manifest bytes drifted'
jq -e '
  .id == "installed-package-v4.0.2"
  and .sourceRevision == "346e69e1cec6c4e8924531874af6ba010a1bc99e"
  and ([.provenance.packages[] | [.name, .version]] | sort) == ([
    ["omarchy", "4.0.2-1"],
    ["omarchy-settings", "4.0.2-1"]
  ] | sort)
' "$compat_package_baseline" >/dev/null \
  || fail 'Omarchy 4.0.2 compatibility package identity drifted'
jq -e '
  .id == "installed-source-parity-v4.0.2"
  and .sourceRevision == "346e69e1cec6c4e8924531874af6ba010a1bc99e"
  and .provenance.revision == .sourceRevision
' "$compat_source_baseline" >/dev/null \
  || fail 'Omarchy 4.0.2 compatibility source identity drifted'
for parity_subtree in shell config; do
  package_row=$(jq -c --arg path "$parity_subtree" \
    '.subtrees[] | select(.path == $path)' "$installed_package_baseline")
  source_row=$(jq -c --arg path "$parity_subtree" \
    '.subtrees[] | select(.path == $path)' "$installed_source_baseline")
  [[ $package_row == "$source_row" ]] \
    || fail "Omarchy 4.0.4 package/source parity drifted: $parity_subtree"
done

jq -e '
  .id == "forward-compat-ed7bae4a"
  and .profile == "forward-compat"
  and .sourceRevision == "ed7bae4ac5a570e9df307486e0202fdafcc6ee24"
  and .provenance.kind == "git"
  and .provenance.revision == .sourceRevision
  and .quickshellPackage == {"name": "quickshell", "version": "0.3.1-1"}
  and all(.subtrees[]; .entryPolicy == "regular-files")
' "$forward_compat_baseline" >/dev/null \
  || fail 'forward-compat baseline identity or provenance is invalid'

shibumi_require_exact_package_identity \
  'host package' omarchy 4.0.4-1 'omarchy 4.0.4-1' \
  || fail 'exact package identity rejected its positive control'
for malformed_identity in \
  '' \
  'omarchy 4.0.4-2' \
  'omarchy-dev 4.0.4-1' \
  'prefix omarchy 4.0.4-1' \
  $'omarchy 4.0.4-1\nomarchy-settings 4.0.4-1'; do
  if shibumi_require_exact_package_identity \
      'host package' omarchy 4.0.4-1 "$malformed_identity" \
      >/dev/null 2>&1; then
    fail "exact package identity accepted malformed output: $malformed_identity"
  fi
done
shibumi_require_exact_subtree_owner shell omarchy omarchy \
  || fail 'exact subtree owner rejected its positive control'
for malformed_owner in '' omarchy-settings $'omarchy\nomarchy-settings'; do
  if shibumi_require_exact_subtree_owner \
      shell omarchy "$malformed_owner" >/dev/null 2>&1; then
    fail "exact subtree owner accepted malformed output: $malformed_owner"
  fi
done
relocation_output=''
if relocation_output=$(shibumi_validate_installed_package_provenance \
    "$repo_root" "$installed_package_baseline" 2>&1); then
  fail 'installed package provenance accepted a relocated repository tree'
fi
[[ $relocation_output == *'requires /usr/share/omarchy'* ]] \
  || fail "relocated package root failed through the wrong invariant: $relocation_output"

agents_fixture=$(mktemp)
trap 'rm -f -- "$agents_fixture"' EXIT
/usr/bin/python3 -I - "$installed_source_baseline" "$agents_fixture" top <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
mode = sys.argv[3]
if mode == "top":
    source = source.replace(
        '{\n  "schemaVersion": 2,',
        '{\n  "schemaVersion": 2,\n  "schemaVersion": 2,',
        1,
    )
else:
    source = source.replace(
        '"kind": "git",',
        '"kind": "git",\n    "kind": "git",',
        1,
    )
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
if shibumi_validate_omarchy_baseline_schema \
    "$agents_fixture" >/dev/null 2>&1; then
  fail 'central baseline schema accepts a duplicate top-level JSON key'
fi
/usr/bin/python3 -I - "$installed_source_baseline" "$agents_fixture" nested <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
source = source.replace(
    '"kind": "git",',
    '"kind": "git",\n    "kind": "git",',
    1,
)
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY
if shibumi_validate_omarchy_baseline_schema \
    "$agents_fixture" >/dev/null 2>&1; then
  fail 'central baseline schema accepts a duplicate nested JSON key'
fi
for nonfinite in 1e309 -1e309; do
  for placement in top nested; do
    if [[ $placement == top ]]; then
      printf '{"ignored":%s}\n' "$nonfinite" >"$agents_fixture"
    else
      printf '{"ignored":{"value":%s}}\n' \
        "$nonfinite" >"$agents_fixture"
    fi
    if shibumi_validate_unique_json_keys \
        "$agents_fixture" >/dev/null 2>&1; then
      fail "central baseline parser accepts overflowing JSON number: $nonfinite"
    fi
  done
done
for manifest_size in 65535 65536 65537; do
  /usr/bin/python3 -I - "$agents_fixture" "$manifest_size" <<'PY'
from pathlib import Path
import sys

size = int(sys.argv[2])
prefix = '{"padding":"'
suffix = '"}\n'
payload = prefix + ("a" * (size - len(prefix) - len(suffix))) + suffix
assert len(payload.encode("utf-8")) == size
Path(sys.argv[1]).write_text(payload, encoding="utf-8")
PY
  if (( manifest_size <= 65536 )); then
    shibumi_validate_unique_json_keys "$agents_fixture" \
      || fail "central baseline parser rejected bounded size $manifest_size"
  elif shibumi_validate_unique_json_keys \
      "$agents_fixture" >/dev/null 2>&1; then
    fail "central baseline parser accepted oversized manifest $manifest_size"
  fi
done

cp "$installed_source_baseline" "$agents_fixture"
shibumi_validate_omarchy_baseline_schema "$agents_fixture" \
  || fail 'baseline replacement probe could not capture its initial snapshot'
printf '{"sourceRevision":"replaced"}\n' >"$agents_fixture"
[[ $(jq -r '.sourceRevision' "$agents_fixture") \
    == c668141e9c42b13c80c9ca4ea108e11708c5e8a5 ]] \
  || fail 'baseline replacement changed an already accepted snapshot'
if shibumi_validate_omarchy_baseline_schema \
    "$agents_fixture" >/dev/null 2>&1; then
  fail 'complete schema accepted the semantic-invalid replacement'
fi
[[ -z ${SHIBUMI_BASELINE_JSON:-} \
    && -z ${SHIBUMI_BASELINE_JSON_PATH:-} ]] \
  || fail 'failed complete schema left rejected snapshot state active'
[[ $(jq -r '.sourceRevision' "$agents_fixture") == replaced ]] \
  || fail 'jq served stale complete snapshot after schema rejection'
rm -f -- "$agents_fixture"
if shibumi_validate_omarchy_baseline_schema \
    "$agents_fixture" >/dev/null 2>&1; then
  fail 'complete schema accepted a missing same-path manifest'
fi
[[ -z ${SHIBUMI_BASELINE_JSON:-} \
    && -z ${SHIBUMI_BASELINE_JSON_PATH:-} ]] \
  || fail 'missing complete manifest preserved stale snapshot state'
if jq -e . "$agents_fixture" >/dev/null 2>&1; then
  fail 'jq served stale complete snapshot for a missing manifest'
fi

cp "$agents_baseline" "$agents_fixture"
shibumi_validate_agents_baseline_schema "$agents_fixture" \
  || fail 'Agents replacement probe could not capture its initial snapshot'
printf '{"sourceRevision":"replaced"}\n' >"$agents_fixture"
[[ $(jq -r '.sourceRevision' "$agents_fixture") \
    == f0020448ca87329199de7cb12f2015ebc4a3e5e7 ]] \
  || fail 'Agents replacement changed an already accepted snapshot'
if shibumi_validate_agents_baseline_schema \
    "$agents_fixture" >/dev/null 2>&1; then
  fail 'Agents schema reused stale snapshot state across validation calls'
fi
[[ -z ${SHIBUMI_BASELINE_JSON:-} \
    && -z ${SHIBUMI_BASELINE_JSON_PATH:-} ]] \
  || fail 'failed Agents schema left rejected snapshot state active'
[[ $(jq -r '.sourceRevision' "$agents_fixture") == replaced ]] \
  || fail 'jq served stale Agents snapshot after schema rejection'
rm -f -- "$agents_fixture"
if shibumi_validate_agents_baseline_schema \
    "$agents_fixture" >/dev/null 2>&1; then
  fail 'Agents schema accepted a missing same-path manifest'
fi
[[ -z ${SHIBUMI_BASELINE_JSON:-} \
    && -z ${SHIBUMI_BASELINE_JSON_PATH:-} ]] \
  || fail 'missing Agents manifest preserved stale snapshot state'
if jq -e . "$agents_fixture" >/dev/null 2>&1; then
  fail 'jq served stale Agents snapshot for a missing manifest'
fi

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

for mutation in \
  '.quickshellPackage.name = "quickshell-git"' \
  '.quickshellPackage.version = "0.3.1-2"'; do
  mutant="$fixture/quickshell-provenance-mutant.json"
  jq "$mutation" "$selected_manifest" >"$mutant"
  if shibumi_validate_quickshell_package_provenance \
      "$mutant" >/dev/null 2>&1; then
    fail "Quickshell package provenance accepted mutation: $mutation"
  fi
done

if [[ $selected_profile == installed-package ]]; then
  for mutation in \
    '.provenance.packages[0].version = "4.0.4-2"' \
    '.provenance.packages[1].version = "4.0.4-2"' \
    '.provenance.subtreeOwners.config = "omarchy"'; do
    mutant="$fixture/installed-provenance-mutant.json"
    jq "$mutation" "$selected_manifest" >"$mutant"
    if shibumi_validate_installed_package_provenance \
        "$selected_host_path" "$mutant" >/dev/null 2>&1; then
      fail "installed package provenance accepted mutation: $mutation"
    fi
  done
fi

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
assert_schema_rejected quickshell-package-installed-substitution \
  "$installed_package_baseline" \
  '.quickshellPackage = {"name": "omarchy", "version": "4.0.4-1"}' \
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
assert_schema_rejected package-list "$installed_package_baseline" \
  '.provenance.packages = null' 'installed-package provenance is invalid'
assert_schema_rejected package-duplicate "$installed_package_baseline" \
  '.provenance.packages[1] = .provenance.packages[0]' \
  'installed-package provenance is invalid'
assert_schema_rejected package-name "$installed_package_baseline" \
  '.provenance.packages[0].name = "../omarchy"' \
  'installed-package provenance is invalid'
assert_schema_rejected package-version "$installed_package_baseline" \
  '.provenance.packages[0].version = ""' \
  'installed-package provenance is invalid'
assert_schema_rejected package-owner-set "$installed_package_baseline" \
  'del(.provenance.subtreeOwners.config)' \
  'installed-package provenance is invalid'
assert_schema_rejected package-owner-value "$installed_package_baseline" \
  '.provenance.subtreeOwners.config = "omarchy"' \
  'installed-package provenance is invalid'
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
  export SHIBUMI_OMARCHY_BASELINE_PROFILE=installed-package
  export SHIBUMI_OMARCHY_BASELINE_VERSION=4.0.4-unsupported
  unset OMARCHY_PATH
  # shellcheck source=tests/lib/baselines.sh
  source "$helper"
  shibumi_load_omarchy_baseline
) >/dev/null 2>&1; then
  fail 'central helper accepted an unsupported installed baseline version'
fi

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
