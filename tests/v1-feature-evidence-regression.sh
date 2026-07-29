#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/contracts/v1-feature-evidence.json"

fail() {
  printf 'V1 feature evidence regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v realpath >/dev/null 2>&1 || fail "realpath is required"

jq -e '
  .schemaVersion == 1
  and (.features | type == "array" and length > 0)
  and all(.features[];
    (.id | type == "string" and length > 0)
    and (.strategy == "port" or .strategy == "adapt")
    and (.sources | type == "array" and length > 0)
    and (.implementation | type == "array" and length > 0)
    and (.evidence | type == "array" and length > 0))
' "$contract" >/dev/null || fail "contract shape is invalid"

reference_root=$(realpath -e "$repo_root/$(jq -r '.referenceRoot' "$contract")") \
  || fail "V1 reference root is missing"

actual=$(mktemp)
declared=$(mktemp)
duplicates=$(mktemp)
trap 'rm -f -- "$actual" "$declared" "$duplicates"' EXIT

find "$reference_root" -maxdepth 2 -type f \
  \( -name '*.qml' -o -name '*.js' \) -printf '%P\n' \
  | sort >"$actual"

jq -r '.features[].sources[]' "$contract" | sort >"$declared"
jq -r '.features[].sources[]' "$contract" | sort | uniq -d >"$duplicates"
[[ ! -s $duplicates ]] \
  || fail "V1 sources are covered more than once: $(tr '\n' ' ' <"$duplicates")"
cmp -s "$actual" "$declared" || {
  diff -u "$actual" "$declared" >&2 || true
  fail "V1 root/core/module/panel inventory is not covered exactly"
}

while IFS= read -r path; do
  [[ -s "$reference_root/$path" ]] \
    || fail "declared V1 source is missing: $path"
done < <(jq -r '.features[].sources[]' "$contract")

while IFS= read -r path; do
  [[ -s "$repo_root/$path" ]] \
    || fail "implementation evidence is missing: $path"
done < <(jq -r '.features[].implementation[]' "$contract")

while IFS= read -r path; do
  [[ -s "$repo_root/$path" ]] \
    || fail "test evidence is missing: $path"
done < <(jq -r '.features[].evidence[]' "$contract")

printf 'V1 feature evidence regression passed (%s source surfaces)\n' \
  "$(wc -l <"$actual")"
