#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/contracts/v1-embedded-v2-differences.json"

fail() {
  printf 'embedded V2 differences regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v realpath >/dev/null 2>&1 || fail "realpath is required"

jq -e '
  .schemaVersion == 1
  and (.standaloneOnly | type == "array")
  and (.differences | type == "array" and length > 0)
  and all(.standaloneOnly[], .differences[];
    (.source | type == "string" and length > 0)
    and (.implementation | type == "array" and length > 0)
    and (.evidence | type == "array" and length > 0))
' "$contract" >/dev/null || fail "contract shape is invalid"

embedded_root=$(realpath -e \
  "$repo_root/$(jq -r '.embeddedRoot' "$contract")") \
  || fail "embedded V2 root is missing"
standalone_root=$(realpath -e \
  "$repo_root/$(jq -r '.standaloneRoot' "$contract")") \
  || fail "standalone V2 root is missing"

embedded_files=$(mktemp)
standalone_files=$(mktemp)
actual_standalone_only=$(mktemp)
declared_standalone_only=$(mktemp)
actual_differences=$(mktemp)
declared_differences=$(mktemp)
trap 'rm -f -- "$embedded_files" "$standalone_files" \
  "$actual_standalone_only" "$declared_standalone_only" \
  "$actual_differences" "$declared_differences"' EXIT

find "$embedded_root" -maxdepth 2 -type f \
  \( -name '*.qml' -o -name '*.js' \) -printf '%P\n' \
  | sort >"$embedded_files"
find "$standalone_root" -maxdepth 2 -type f \
  \( -name '*.qml' -o -name '*.js' \) -printf '%P\n' \
  | sort >"$standalone_files"

comm -23 "$embedded_files" "$standalone_files" \
  | grep . && fail "embedded V2 has undeclared standalone-missing sources"
comm -13 "$embedded_files" "$standalone_files" >"$actual_standalone_only"
jq -r '.standaloneOnly[].source' "$contract" \
  | sort >"$declared_standalone_only"
cmp -s "$actual_standalone_only" "$declared_standalone_only" || {
  diff -u "$actual_standalone_only" "$declared_standalone_only" >&2 || true
  fail "standalone-only source inventory changed"
}

while IFS= read -r source; do
  cmp -s "$embedded_root/$source" "$standalone_root/$source" \
    || printf '%s\n' "$source"
done < <(comm -12 "$embedded_files" "$standalone_files") \
  | sort >"$actual_differences"
jq -r '.differences[].source' "$contract" | sort >"$declared_differences"
cmp -s "$actual_differences" "$declared_differences" || {
  diff -u "$actual_differences" "$declared_differences" >&2 || true
  fail "embedded/standalone V2 difference inventory changed"
}

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
  "$(wc -l <"$actual_differences")"
