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

author="$fixture_root/author"
plugins="$fixture_root/plugins"
mkdir -p "$author" "$plugins"
git -C "$author" init --quiet --initial-branch=main
git -C "$author" config user.name "Shibumi Test"
git -C "$author" config user.email "shibumi@example.invalid"
printf '{"id":"third.party.git"}\n' > "$author/manifest.json"
git -C "$author" add manifest.json
git -C "$author" commit --quiet -m initial
git clone --quiet "$author" "$plugins/third.party.git"
printf 'update\n' > "$author/update.txt"
git -C "$author" add update.txt
git -C "$author" commit --quiet -m update

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

grep -Fq 'gum choose --no-limit' "$updater" \
  || fail 'multi-selection delegation drifted'
grep -Fq 'omarchy-plugin-update "$plugin_id"' "$updater" \
  || fail 'updates are not delegated to the authoritative Omarchy updater'
if grep -Fq 'omarchy-plugin-update "$plugin_id" --yes' "$updater"; then
  fail 'third-party updates bypass the authoritative diff confirmation with --yes'
fi

test_home="$fixture_root/home"
stub_bin="$fixture_root/bin"
mkdir -p "$test_home/.config/omarchy" "$stub_bin"
ln -s "$plugins" "$test_home/.config/omarchy/plugins"
ln -s /usr/share/omarchy/bin/omarchy-plugin-update \
  "$stub_bin/omarchy-plugin-update"
cat >"$stub_bin/gum" <<'SH'
#!/bin/bash
case "${1:-}" in
  choose)
    head -n 1
    ;;
  confirm)
    [[ ${TEST_CONFIRM:-deny} == allow ]]
    ;;
  *)
    exit 2
    ;;
esac
SH
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$stub_bin/omarchy-plugin-validate" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
# The authoritative updater rescans after apply. Keep that mutation inside the
# fixture instead of contacting the user's running shell.
exit 0
SH
chmod +x "$stub_bin/gum" "$stub_bin/omarchy-cmd-present" \
  "$stub_bin/omarchy-plugin-validate" "$stub_bin/omarchy-shell"

initial_head=$(git -C "$plugins/third.party.git" rev-parse HEAD)
remote_head=$(git -C "$author" rev-parse HEAD)
run_selector() {
  local decision=$1
  script -qec \
    "env HOME='$test_home' PATH='$stub_bin:$PATH' TEST_CONFIRM='$decision' '$updater'" \
    /dev/null
}

cancel_output=$(run_selector deny)
grep -Fq 'Changes for third.party.git:' <<<"$cancel_output" \
  || fail 'authoritative updater did not show the changed-code diff'
[[ $(git -C "$plugins/third.party.git" rev-parse HEAD) == "$initial_head" ]] \
  || fail 'cancelling changed-code review modified plugin HEAD'
[[ -z $(git -C "$plugins/third.party.git" status --porcelain) ]] \
  || fail 'cancelling changed-code review modified the plugin worktree'

apply_output=$(run_selector allow)
grep -Fq 'Changes for third.party.git:' <<<"$apply_output" \
  || fail 'confirmed update did not show the changed-code diff'
[[ $(git -C "$plugins/third.party.git" rev-parse HEAD) == "$remote_head" ]] \
  || fail 'explicit confirmation did not apply the selected update'
[[ -z $(git -C "$plugins/third.party.git" status --porcelain) ]] \
  || fail 'confirmed update left the plugin worktree dirty'

echo "plugin update selector regression passed"
