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
printf 'initial line\n' > "$author/update.txt"
git -C "$author" add manifest.json update.txt
git -C "$author" commit --quiet -m initial
git clone --quiet "$author" "$plugins/third.party.git"
# A deliberately long review proves the Shibumi wrapper reaches Omarchy's
# confirmation without an implicit git pager swallowing the terminal first.
for line in $(seq 1 400); do
  printf 'changed line %04d\n' "$line"
done > "$author/update.txt"
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
grep -Fq 'export GIT_PAGER=cat' "$updater" \
  || fail 'long changed-code review can disappear behind an implicit pager'
grep -Fq 'full diff, then ask for confirmation' "$updater" \
  || fail 'changed-code review does not explain the second confirmation'
grep -Fq 'omarchy-plugin-update "$plugin_id"' "$updater" \
  || fail 'updates are not delegated to the authoritative Omarchy updater'
if grep -Fq 'omarchy-plugin-update "$plugin_id" --yes' "$updater"; then
  fail 'third-party updates bypass the authoritative diff confirmation with --yes'
fi

test_home="$fixture_root/home"
stub_bin="$fixture_root/bin"
mkdir -p "$test_home/.config/omarchy" "$stub_bin"
ln -s "$plugins" "$test_home/.config/omarchy/plugins"
cat >"$stub_bin/omarchy-plugin-update" <<'SH'
#!/bin/bash
[[ -t 0 && -t 1 ]] || exit 72
exec /usr/share/omarchy/bin/omarchy-plugin-update "$@"
SH
cat >"$stub_bin/gum" <<'SH'
#!/bin/bash
case "${1:-}" in
  choose)
    head -n 1
    ;;
  confirm)
    printf 'FIXTURE_CONFIRM=%s\n' "${2:-}" >&2
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
[[ ${TEST_VALIDATION:-pass} == pass ]]
SH
cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
# The authoritative updater rescans after apply. Keep that mutation inside the
# fixture instead of contacting the user's running shell.
exit 0
SH
chmod +x "$stub_bin/omarchy-plugin-update" "$stub_bin/gum" \
  "$stub_bin/omarchy-cmd-present" "$stub_bin/omarchy-plugin-validate" \
  "$stub_bin/omarchy-shell"

initial_head=$(git -C "$plugins/third.party.git" rev-parse HEAD)
remote_head=$(git -C "$author" rev-parse HEAD)
run_selector() {
  local decision=$1 validation=${2:-pass}
  timeout --foreground --signal=TERM --kill-after=2 20 \
    script -qec \
      "env HOME='$test_home' PATH='$stub_bin:$PATH' TEST_CONFIRM='$decision' TEST_VALIDATION='$validation' '$updater'" \
      /dev/null
}

cancel_output=$(run_selector deny)
grep -Fq 'Changes for third.party.git:' <<<"$cancel_output" \
  || fail 'authoritative updater did not show the changed-code diff'
grep -Fq 'FIXTURE_CONFIRM=Update third.party.git?' <<<"$cancel_output" \
  || fail 'long changed-code review did not reach the final TTY confirmation'
grep -Fq 'Reviewing third.party.git: Omarchy will show the full diff' \
  <<<"$cancel_output" \
  || fail 'wrapper did not announce the review and confirmation sequence'
[[ $(git -C "$plugins/third.party.git" rev-parse HEAD) == "$initial_head" ]] \
  || fail 'cancelling changed-code review modified plugin HEAD'
[[ -z $(git -C "$plugins/third.party.git" status --porcelain) ]] \
  || fail 'cancelling changed-code review modified the plugin worktree'

# Tracked local changes block ff-only and must propagate failure to the caller.
printf 'local edit\n' > "$plugins/third.party.git/update.txt"
local_edit_hash=$(sha256sum "$plugins/third.party.git/update.txt" | awk '{print $1}')
set +e
local_output=$(run_selector allow 2>&1)
local_rc=$?
set -e
[[ $local_rc -eq 1 ]] || fail "local-change failure returned $local_rc"
grep -Fq "cannot fast-forward 'third.party.git'" <<<"$local_output" \
  || fail 'local-change failure was not attributed to the plugin checkout'
[[ $(git -C "$plugins/third.party.git" rev-parse HEAD) == "$initial_head" ]] \
  || fail 'local-change failure advanced plugin HEAD'
[[ $(sha256sum "$plugins/third.party.git/update.txt" | awk '{print $1}') \
    == "$local_edit_hash" ]] \
  || fail 'local-change failure modified the user edit'
[[ $(git -C "$plugins/third.party.git" status --short -- update.txt) \
    == ' M update.txt' ]] \
  || fail 'local-change failure did not preserve the tracked edit state'
git -C "$plugins/third.party.git" restore -- update.txt
[[ -z $(git -C "$plugins/third.party.git" status --porcelain) ]] \
  || fail 'local-change fixture did not return to a clean checkout'

# Validation failure must rollback the fetched fast-forward and return failure.
set +e
validation_output=$(run_selector allow fail 2>&1)
validation_rc=$?
set -e
[[ $validation_rc -eq 1 ]] || fail "validation failure returned $validation_rc"
grep -Fq "failed validation; rolled back" <<<"$validation_output" \
  || fail 'validation failure did not report rollback'
[[ $(git -C "$plugins/third.party.git" rev-parse HEAD) == "$initial_head" ]] \
  || fail 'validation rollback did not restore initial HEAD'
[[ -z $(git -C "$plugins/third.party.git" status --porcelain) ]] \
  || fail 'validation rollback left the plugin worktree dirty'

apply_output=$(run_selector allow)
grep -Fq 'Changes for third.party.git:' <<<"$apply_output" \
  || fail 'confirmed update did not show the changed-code diff'
[[ $(git -C "$plugins/third.party.git" rev-parse HEAD) == "$remote_head" ]] \
  || fail 'explicit confirmation did not apply the selected update'
[[ -z $(git -C "$plugins/third.party.git" status --porcelain) ]] \
  || fail 'confirmed update left the plugin worktree dirty'

# Divergence is detected during Shibumi's scan and never offered for update.
printf 'remote divergence\n' > "$author/remote.txt"
git -C "$author" add remote.txt
git -C "$author" commit --quiet -m remote-divergence
printf 'local divergence\n' > "$plugins/third.party.git/local.txt"
git -C "$plugins/third.party.git" add local.txt
git -C "$plugins/third.party.git" \
  -c user.name='Shibumi Test' -c user.email='shibumi@example.invalid' \
  commit --quiet -m local-divergence
diverged_output=$(SHIBUMI_PLUGIN_DIR="$plugins" "$updater" --list)
grep -Fxq 'PLUGIN_UPDATE_COUNT=0' <<<"$diverged_output" \
  || fail 'diverged plugin was offered as a fast-forward update'
grep -Fxq 'PLUGIN_FETCH_FAILED_ID=third.party.git (diverged)' \
  <<<"$diverged_output" \
  || fail 'diverged plugin was not classified separately'

# A missing origin exercises the fetch-error result without touching any real
# third-party checkout.
git -C "$plugins/third.party.git" remote set-url origin \
  "$fixture_root/missing-origin"
fetch_output=$(SHIBUMI_PLUGIN_DIR="$plugins" "$updater" --list 2>&1)
grep -Fxq 'PLUGIN_UPDATE_COUNT=0' <<<"$fetch_output" \
  || fail 'fetch-failed plugin was offered as an update'
grep -Fxq 'PLUGIN_FETCH_FAILED_ID=third.party.git' <<<"$fetch_output" \
  || fail 'fetch failure was not reported to the caller'

echo "plugin update selector regression passed"
