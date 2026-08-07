#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
baseline="$repo_root/contracts/baselines/quickshell-dots-d0896fc-v2-deec8103.json"

fail() {
  printf 'reference baseline regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail 'jq is required'
command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required'
[[ -r $baseline ]] || fail "baseline is missing: $baseline"

inventory_digest() {
  local root=$1
  (cd "$root" && find . -maxdepth 2 -type f \
    \( -name '*.qml' -o -name '*.js' \) -printf '%P\n' | LC_ALL=C sort | sha256sum \
    | awk '{print $1}')
}

inventory_count() {
  local root=$1
  find "$root" -maxdepth 2 -type f \
    \( -name '*.qml' -o -name '*.js' \) -printf '.\n' | wc -l
}

content_digest() {
  local root=$1
  (cd "$root" && while IFS= read -r path; do
    local_hash=$(sha256sum -- "$path" | awk '{print $1}')
    printf '%s  %s\n' "$local_hash" "$path"
  done < <(find . -maxdepth 2 -type f \
    \( -name '*.qml' -o -name '*.js' \) -printf '%P\n' | LC_ALL=C sort) \
    | sha256sum | awk '{print $1}')
}

assert_declared_inventory() {
  local contract=$1
  local root_id=$2
  local actual_count actual_digest expected_count expected_digest
  actual_count=$(jq '[.features[].sources[]] | length' "$contract")
  actual_digest=$(jq -r '.features[].sources[]' "$contract" \
    | LC_ALL=C sort | sha256sum | awk '{print $1}')
  expected_count=$(jq -r --arg id "$root_id" '.roots[$id].sourceCount' "$baseline")
  expected_digest=$(jq -r --arg id "$root_id" \
    '.roots[$id].inventorySha256' "$baseline")
  [[ $actual_count == "$expected_count" ]] \
    || fail "$(basename "$contract") source count is not pinned to $root_id"
  [[ $actual_digest == "$expected_digest" ]] \
    || fail "$(basename "$contract") inventory is not pinned to $root_id"
}

assert_declared_inventory "$repo_root/contracts/v1-feature-evidence.json" v1
assert_declared_inventory "$repo_root/contracts/v2-source-evidence.json" v2

differences="$repo_root/contracts/v1-embedded-v2-differences.json"
standalone_count=$(jq '.standaloneOnly | length' "$differences")
standalone_digest=$(jq -r '.standaloneOnly[].source' "$differences" \
  | LC_ALL=C sort | sha256sum | awk '{print $1}')
changed_count=$(jq '.differences | length' "$differences")
changed_digest=$(jq -r '.differences[].source' "$differences" \
  | LC_ALL=C sort | sha256sum | awk '{print $1}')
expected_standalone_count=$(jq -r \
  '.comparisons.embeddedToStandaloneV2.standaloneOnlyCount' "$baseline")
expected_standalone_digest=$(jq -r \
  '.comparisons.embeddedToStandaloneV2.standaloneOnlySha256' "$baseline")
expected_changed_count=$(jq -r \
  '.comparisons.embeddedToStandaloneV2.changedCount' "$baseline")
expected_changed_digest=$(jq -r \
  '.comparisons.embeddedToStandaloneV2.changedSha256' "$baseline")
[[ $standalone_count == "$expected_standalone_count" \
    && $standalone_digest == "$expected_standalone_digest" ]] \
  || fail 'declared standalone-only V2 inventory drifted from the pinned snapshot'
[[ $changed_count == "$expected_changed_count" \
    && $changed_digest == "$expected_changed_digest" ]] \
  || fail 'declared embedded/standalone differences drifted from the pinned snapshot'

if [[ -n ${SHIBUMI_PREDECESSOR_PATH:-} ]]; then
  [[ $SHIBUMI_PREDECESSOR_PATH == /* && -d $SHIBUMI_PREDECESSOR_PATH ]] \
    || fail 'SHIBUMI_PREDECESSOR_PATH must be an absolute checkout path'
  reference_root=$(realpath -e -- "$SHIBUMI_PREDECESSOR_PATH")
  expected_revision=$(jq -r '.roots.v1.revision' "$baseline")
  actual_revision=$(git -C "$reference_root" rev-parse HEAD 2>/dev/null) \
    || fail 'predecessor checkout is not a Git worktree'
  [[ $actual_revision == "$expected_revision" ]] \
    || fail "predecessor revision drift: expected $expected_revision, got $actual_revision"

  for root_id in v1 v1EmbeddedV2 v2; do
    subtree=$(jq -r --arg id "$root_id" '.roots[$id].subtree' "$baseline")
    source_root="$reference_root/$subtree"
    [[ -d $source_root ]] || fail "predecessor subtree is missing: $subtree"
    expected_count=$(jq -r --arg id "$root_id" '.roots[$id].sourceCount' "$baseline")
    expected_inventory=$(jq -r --arg id "$root_id" \
      '.roots[$id].inventorySha256' "$baseline")
    expected_content=$(jq -r --arg id "$root_id" \
      '.roots[$id].contentSha256' "$baseline")
    [[ $(inventory_count "$source_root") == "$expected_count" ]] \
      || fail "$root_id source count drifted"
    [[ $(inventory_digest "$source_root") == "$expected_inventory" ]] \
      || fail "$root_id source inventory drifted"
    [[ $(content_digest "$source_root") == "$expected_content" ]] \
      || fail "$root_id source content drifted"
  done
  printf 'predecessor baseline regression passed (%s; external checkout verified)\n' \
    "$(jq -r '.id' "$baseline")"
else
  printf 'predecessor baseline regression passed (%s; portable pinned fixture)\n' \
    "$(jq -r '.id' "$baseline")"
fi
