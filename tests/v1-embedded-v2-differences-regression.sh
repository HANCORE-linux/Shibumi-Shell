#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/contracts/v1-embedded-v2-differences.json"
baseline="$repo_root/$(jq -r '.referenceBaseline' "$contract")"

fail() {
  printf 'embedded V2 differences regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

jq -e '
  .schemaVersion == 1
  and (.referenceRepository | type == "string" and length > 0)
  and (.referenceRevision | type == "string" and test("^[0-9a-f]{40}$"))
  and (.referenceBaseline | type == "string" and length > 0)
  and .referenceRootId == "v1EmbeddedV2"
  and .standaloneRootId == "v2"
  and (.standaloneOnly | type == "array")
  and (.differences | type == "array" and length > 0)
  and all(.standaloneOnly[], .differences[];
    (.source | type == "string" and length > 0)
    and (.implementation | type == "array" and length > 0)
    and (.evidence | type == "array" and length > 0))
' "$contract" >/dev/null || fail "contract shape is invalid"
[[ -r $baseline ]] || fail "pinned embedded/standalone baseline is missing"

declared_reference_revision=$(jq -r '.referenceRevision' "$contract")
baseline_reference_revision=$(jq -r '.roots.v1EmbeddedV2.revision' "$baseline")
[[ $declared_reference_revision == "$baseline_reference_revision" ]] \
  || fail "embedded V2 revision is not bound to the pinned fixture"

declared_standalone_only=$(mktemp)
declared_differences=$(mktemp)
trap 'rm -f -- "$declared_standalone_only" "$declared_differences"' EXIT

jq -r '.standaloneOnly[].source' "$contract" \
  | LC_ALL=C sort >"$declared_standalone_only"
jq -r '.differences[].source' "$contract" \
  | LC_ALL=C sort >"$declared_differences"
expected_standalone_count=$(jq -r \
  '.comparisons.embeddedToStandaloneV2.standaloneOnlyCount' "$baseline")
expected_standalone_digest=$(jq -r \
  '.comparisons.embeddedToStandaloneV2.standaloneOnlySha256' "$baseline")
expected_difference_count=$(jq -r \
  '.comparisons.embeddedToStandaloneV2.changedCount' "$baseline")
expected_difference_digest=$(jq -r \
  '.comparisons.embeddedToStandaloneV2.changedSha256' "$baseline")
[[ $(wc -l <"$declared_standalone_only") == "$expected_standalone_count" \
    && $(sha256sum "$declared_standalone_only" | awk '{print $1}') \
      == "$expected_standalone_digest" ]] \
  || fail "standalone-only source inventory changed"
[[ $(wc -l <"$declared_differences") == "$expected_difference_count" \
    && $(sha256sum "$declared_differences" | awk '{print $1}') \
      == "$expected_difference_digest" ]] \
  || fail "embedded/standalone V2 difference inventory changed"

while IFS= read -r path; do
  [[ -s "$repo_root/$path" ]] \
    || fail "implementation evidence is missing: $path"
done < <(jq -r '.standaloneOnly[].implementation[],
  .differences[].implementation[]' "$contract")

while IFS= read -r path; do
  [[ -s "$repo_root/$path" ]] \
    || fail "test evidence is missing: $path"
done < <(jq -r '.standaloneOnly[].evidence[],
  .differences[].evidence[]' "$contract")

printf 'embedded V2 differences regression passed (%s reviewed deltas)\n' \
  "$(wc -l <"$declared_differences")"
