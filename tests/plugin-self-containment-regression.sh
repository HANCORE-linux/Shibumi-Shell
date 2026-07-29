#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
suite="$repo_root/contracts/plugin-suite-v1.json"

fail() {
  printf 'plugin self-containment regression failed: %s\n' "$*" >&2
  exit 1
}

"$repo_root/scripts/sync-shared.sh" --check >/dev/null
"$repo_root/scripts/sync-bar-host.sh" --check >/dev/null

found=0
while IFS= read -r plugin_id; do
  plugin_dir="$repo_root/$plugin_id"
  [[ -d $plugin_dir ]] || continue
  found=$((found + 1))
  if find "$plugin_dir" -type l -print -quit | grep -q .; then
    fail "$plugin_id payload contains a symlink"
  fi
  manifest="$plugin_dir/manifest.json"
  [[ -f $manifest ]] || fail "$plugin_id has no manifest"
  jq -e --arg id "$plugin_id" '
    .schemaVersion == 1 and .id == $id and
    (.kinds | type == "array" and length > 0) and
    (.entryPoints | type == "object")
  ' "$manifest" >/dev/null || fail "$plugin_id manifest does not match suite id"

  while IFS= read -r entry_point; do
    [[ $entry_point != /* && $entry_point != *".."* ]] \
      || fail "$plugin_id has unsafe entry point: $entry_point"
    [[ -f $plugin_dir/$entry_point ]] \
      || fail "$plugin_id is missing entry point: $entry_point"
  done < <(jq -r '.entryPoints[]' "$manifest")

  "$repo_root/tests/plugin-import-boundary.py" "$plugin_dir" \
    || fail "$plugin_id imports across its plugin boundary"
done < <(jq -r '.plugins[].id' "$suite")

(( found > 0 )) || fail "no extracted plugin directories found"
suffix=s
[[ $found -eq 1 ]] && suffix=
printf 'plugin self-containment regression passed (%d extracted plugin%s)\n' \
  "$found" "$suffix"
