#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/contracts/v2-source-evidence.json"
baseline="$repo_root/$(jq -r '.referenceBaseline' "$contract")"

fail() {
  printf 'V2 source evidence regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

jq -e '
  .schemaVersion == 1
  and .referenceRootId == "v2"
  and (.referenceBaseline | type == "string" and length > 0)
  and (.features | type == "array" and length > 0)
  and all(.features[];
    (.id | type == "string" and length > 0)
    and (.strategy == "port" or .strategy == "adapt")
    and (.sources | type == "array" and length > 0)
    and (.implementation | type == "array" and length > 0)
    and (.evidence | type == "array" and length > 0))
' "$contract" >/dev/null || fail "contract shape is invalid"

declared=$(mktemp)
duplicates=$(mktemp)
trap 'rm -f -- "$declared" "$duplicates"' EXIT
[[ -r $baseline ]] || fail "pinned V2 baseline is missing"

jq -r '.features[].sources[]' "$contract" | LC_ALL=C sort >"$declared"
jq -r '.features[].sources[]' "$contract" \
  | LC_ALL=C sort | uniq -d >"$duplicates"
[[ ! -s $duplicates ]] \
  || fail "V2 sources are covered more than once: $(tr '\n' ' ' <"$duplicates")"
expected_count=$(jq -r '.roots.v2.sourceCount' "$baseline")
expected_inventory=$(jq -r '.roots.v2.inventorySha256' "$baseline")
[[ $(wc -l <"$declared") == "$expected_count" ]] \
  || fail "V2 source count is not bound to the pinned fixture"
[[ $(sha256sum "$declared" | awk '{print $1}') == "$expected_inventory" ]] \
  || fail "V2 source inventory is not bound to the pinned fixture"

while IFS= read -r path; do
  [[ -s "$repo_root/$path" ]] \
    || fail "implementation evidence is missing: $path"
done < <(jq -r '.features[].implementation[]' "$contract")

while IFS= read -r path; do
  [[ -s "$repo_root/$path" ]] \
    || fail "test evidence is missing: $path"
done < <(jq -r '.features[].evidence[]' "$contract")

printf 'V2 source evidence regression passed (%s source surfaces)\n' \
  "$(wc -l <"$declared")"
