#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
updater="$repo_root/hancore.shibumi.control-center/manager/shibumi-plugin-updates"
fixture_root=$(mktemp -d)
trap 'rm -rf -- "$fixture_root"' EXIT

fail() {
  echo "plugin update selector regression failed: $*" >&2
  exit 1
}

bash -n "$updater"

origin="$fixture_root/origin.git"
author="$fixture_root/author"
plugins="$fixture_root/plugins"
mkdir -p "$plugins"
git init --quiet --bare "$origin"
git clone --quiet "$origin" "$author"
git -C "$author" config user.name "Shibumi Test"
git -C "$author" config user.email "shibumi@example.invalid"
printf '{"id":"third.party.git"}\n' > "$author/manifest.json"
git -C "$author" add manifest.json
git -C "$author" commit --quiet -m initial
git -C "$author" push --quiet origin HEAD
git clone --quiet "$origin" "$plugins/third.party.git"
printf 'update\n' > "$author/update.txt"
git -C "$author" add update.txt
git -C "$author" commit --quiet -m update
git -C "$author" push --quiet origin HEAD

mkdir -p "$plugins/third.party.archive" "$plugins/hancore.shibumi.fixture"
printf '{"id":"third.party.archive"}\n' \
  > "$plugins/third.party.archive/manifest.json"
printf '{"id":"hancore.shibumi.fixture","x-shibumi":{"suiteId":"hancore.shibumi"}}\n' \
  > "$plugins/hancore.shibumi.fixture/manifest.json"

output=$(SHIBUMI_PLUGIN_DIR="$plugins" "$updater" --list)
grep -Fxq 'PLUGIN_UPDATE_COUNT=1' <<< "$output" \
  || fail "available update count is not derived before selection"
grep -Fxq 'PLUGIN_UPDATE_ID=third.party.git' <<< "$output" \
  || fail "Git-managed update is not selectable"
grep -Fxq 'PLUGIN_UNMANAGED_ID=third.party.archive' <<< "$output" \
  || fail "non-Git plugin is not reported separately"
if grep -Fq 'hancore.shibumi.fixture' <<< "$output"; then
  fail "suite-managed plugins must not enter third-party update selection"
fi

for delegation_contract in \
    'gum choose --no-limit' \
    'omarchy-plugin-update "$plugin_id" --yes'; do
  grep -Fq "$delegation_contract" "$updater" \
    || fail "update selection delegation drifted: $delegation_contract"
done

echo "plugin update selector regression passed"
