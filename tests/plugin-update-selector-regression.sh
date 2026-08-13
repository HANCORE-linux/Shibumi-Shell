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
# A deliberately long review proves Omarchy keeps ownership of its pager and
# reaches confirmation after the user exits that pager with `q`.
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

output=$(SHIBUMI_PLUGIN_DIR="$plugins" SHIBUMI_ALLOW_FILE_REMOTE=1 \
  "$updater" --list)
grep -Fxq 'PLUGIN_SCAN_EPOCH=0' <<< "$output" \
  || fail "default scanner epoch is not machine-readable"
grep -Fxq 'PLUGIN_UPDATE_COUNT=1' <<< "$output" \
  || fail "available update count is not derived before selection"
grep -Fxq 'PLUGIN_CHECKED_COUNT=1' <<< "$output" \
  || fail "Git-managed check count is not machine-readable"
grep -Fxq 'PLUGIN_UNMANAGED_COUNT=1' <<< "$output" \
  || fail "unmanaged count is not machine-readable"
grep -Fxq 'PLUGIN_FETCH_FAILED_COUNT=0' <<< "$output" \
  || fail "clean scan reported a failed Git check"
grep -Fxq 'PLUGIN_UPDATE_ID=third.party.git' <<< "$output" \
  || fail "Git-managed update is not selectable"
grep -Fxq 'PLUGIN_UNMANAGED_ID=third.party.archive' <<< "$output" \
  || fail "non-Git plugin is not reported separately"
if grep -Fq 'hancore.shibumi.fixture' <<< "$output"; then
  fail "suite-managed plugins must not enter third-party update selection"
fi

# Background scans must not follow plugin/.git symlinks or execute repository-
# local Git helpers. These fixtures are never passed to Git at all.
ln -s "$plugins/third.party.git" "$plugins/third.party.symlink"
mkdir -p "$plugins/third.party.gitlink"
printf '{"id":"third.party.gitlink"}\n' \
  > "$plugins/third.party.gitlink/manifest.json"
ln -s "$plugins/third.party.git/.git" "$plugins/third.party.gitlink/.git"
hardened_output=$(SHIBUMI_PLUGIN_DIR="$plugins" SHIBUMI_ALLOW_FILE_REMOTE=1 \
  "$updater" --list)
grep -Fxq 'PLUGIN_UNMANAGED_COUNT=3' <<<"$hardened_output" \
  || fail 'symlinked plugin repositories were not rejected as unmanaged'
grep -Fxq 'PLUGIN_UNMANAGED_ID=third.party.symlink' <<<"$hardened_output" \
  || fail 'symlinked plugin root was followed'
grep -Fxq 'PLUGIN_UNMANAGED_ID=third.party.gitlink' <<<"$hardened_output" \
  || fail 'symlinked .git path was followed'
rm -f -- "$plugins/third.party.symlink"
rm -rf -- "$plugins/third.party.gitlink"

# A repository whose object database has no valid HEAD is a per-plugin failure,
# not a reason to lose the machine-readable result for every healthy plugin.
mkdir -p "$plugins/third.party.broken"
printf '{"id":"third.party.broken"}\n' \
  > "$plugins/third.party.broken/manifest.json"
git -C "$plugins/third.party.broken" init --quiet --initial-branch=main
git -C "$plugins/third.party.broken" remote add origin "$author"
broken_output=$(SHIBUMI_PLUGIN_DIR="$plugins" SHIBUMI_ALLOW_FILE_REMOTE=1 \
  "$updater" --list)
grep -Fxq 'PLUGIN_UPDATE_COUNT=1' <<<"$broken_output" \
  || fail 'broken checkout discarded a healthy update result'
grep -Fxq 'PLUGIN_CHECKED_COUNT=1' <<<"$broken_output" \
  || fail 'broken checkout polluted the successful-check count'
grep -Fxq 'PLUGIN_FETCH_FAILED_COUNT=1' <<<"$broken_output" \
  || fail 'broken checkout did not increment failed-check count'
grep -Fxq 'PLUGIN_FETCH_FAILED_ID=third.party.broken (invalid checkout)' \
  <<<"$broken_output" \
  || fail 'broken checkout was not classified as invalid'
rm -rf -- "$plugins/third.party.broken"

mkdir -p "$plugins/third.party.noncommit"
printf '{"id":"third.party.noncommit"}\n' \
  > "$plugins/third.party.noncommit/manifest.json"
git -C "$plugins/third.party.noncommit" init --quiet --initial-branch=main
git -C "$plugins/third.party.noncommit" remote add origin "$author"
blob=$(printf 'not a commit\n' | git -C "$plugins/third.party.noncommit" hash-object -w --stdin)
printf '%s\n' "$blob" > "$plugins/third.party.noncommit/.git/refs/heads/main"
noncommit_output=$(SHIBUMI_PLUGIN_DIR="$plugins" SHIBUMI_ALLOW_FILE_REMOTE=1 \
  "$updater" --list)
grep -Fxq 'PLUGIN_UPDATE_COUNT=1' <<<"$noncommit_output" \
  || fail 'non-commit HEAD discarded a healthy update result'
grep -Fxq 'PLUGIN_FETCH_FAILED_COUNT=1' <<<"$noncommit_output" \
  || fail 'non-commit HEAD did not increment failed-check count'
grep -Fxq 'PLUGIN_FETCH_FAILED_ID=third.party.noncommit (invalid checkout)' \
  <<<"$noncommit_output" \
  || fail 'non-commit HEAD was counted as checked'
rm -rf -- "$plugins/third.party.noncommit"

for hardening_contract in \
    'export GIT_ASKPASS=/bin/false' \
    'export SSH_ASKPASS=/bin/false' \
    '-c core.hooksPath=/dev/null' \
    '-c core.askPass=/bin/false' \
    '-c core.gitProxy=' \
    '-c credential.helper=' \
    '-c protocol.allow=never' \
    '-c protocol.ext.allow=never' \
    '-c protocol.file.allow="$git_file_protocol"' \
    '-c protocol.git.allow=never' \
    'fetch --quiet --no-write-fetch-head'; do
  grep -Fq -- "$hardening_contract" "$updater" \
    || fail "Git scan hardening drifted: $hardening_contract"
done

grep -Fq 'gum choose --no-limit' "$updater" \
  || fail 'multi-selection delegation drifted'
if grep -Fq 'GIT_PAGER=' "$updater"; then
  fail 'Shibumi overrides the authoritative Omarchy diff pager'
fi
grep -Fq "if Omarchy opens a diff pager, exit it with q" "$updater" \
  || fail 'changed-code review does not explain how to leave the pager'
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
      "env HOME='$test_home' PATH='$stub_bin:$PATH' SHIBUMI_ALLOW_FILE_REMOTE=1 TEST_CONFIRM='$decision' TEST_VALIDATION='$validation' '$updater'" \
      /dev/null
}

cancel_output=$(printf q | run_selector deny)
grep -Fq 'Changes for third.party.git:' <<<"$cancel_output" \
  || fail 'authoritative updater did not show the changed-code diff'
grep -Fq 'FIXTURE_CONFIRM=Update third.party.git?' <<<"$cancel_output" \
  || fail 'q did not leave the authoritative pager for final confirmation'
grep -Fq "Reviewing third.party.git: if Omarchy opens a diff pager, exit it with q" \
  <<<"$cancel_output" \
  || fail 'wrapper did not announce the authoritative pager sequence'
[[ $(git -C "$plugins/third.party.git" rev-parse HEAD) == "$initial_head" ]] \
  || fail 'cancelling changed-code review modified plugin HEAD'
[[ -z $(git -C "$plugins/third.party.git" status --porcelain) ]] \
  || fail 'cancelling changed-code review modified the plugin worktree'

# Tracked local changes block ff-only and must propagate failure to the caller.
printf 'local edit\n' > "$plugins/third.party.git/update.txt"
local_edit_hash=$(sha256sum "$plugins/third.party.git/update.txt" | awk '{print $1}')
set +e
local_output=$(printf q | run_selector allow 2>&1)
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
validation_output=$(printf q | run_selector allow fail 2>&1)
validation_rc=$?
set -e
[[ $validation_rc -eq 1 ]] || fail "validation failure returned $validation_rc"
grep -Fq "failed validation; rolled back" <<<"$validation_output" \
  || fail 'validation failure did not report rollback'
[[ $(git -C "$plugins/third.party.git" rev-parse HEAD) == "$initial_head" ]] \
  || fail 'validation rollback did not restore initial HEAD'
[[ -z $(git -C "$plugins/third.party.git" status --porcelain) ]] \
  || fail 'validation rollback left the plugin worktree dirty'

apply_output=$(printf q | run_selector allow)
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
diverged_output=$(SHIBUMI_PLUGIN_DIR="$plugins" \
  SHIBUMI_ALLOW_FILE_REMOTE=1 "$updater" --list)
grep -Fxq 'PLUGIN_UPDATE_COUNT=0' <<<"$diverged_output" \
  || fail 'diverged plugin was offered as a fast-forward update'
grep -Fxq 'PLUGIN_CHECKED_COUNT=0' <<<"$diverged_output" \
  || fail 'diverged Git plugin was counted as successfully checked'
grep -Fxq 'PLUGIN_FETCH_FAILED_COUNT=1' <<<"$diverged_output" \
  || fail 'diverged plugin did not increment failed-check count'
grep -Fxq 'PLUGIN_FETCH_FAILED_ID=third.party.git (diverged)' \
  <<<"$diverged_output" \
  || fail 'diverged plugin was not classified separately'

# A missing origin exercises the fetch-error result without touching any real
# third-party checkout.
git -C "$plugins/third.party.git" remote set-url origin \
  "$fixture_root/missing-origin"
fetch_output=$(SHIBUMI_PLUGIN_DIR="$plugins" \
  SHIBUMI_ALLOW_FILE_REMOTE=1 "$updater" --list 2>&1)
grep -Fxq 'PLUGIN_UPDATE_COUNT=0' <<<"$fetch_output" \
  || fail 'fetch-failed plugin was offered as an update'
grep -Fxq 'PLUGIN_CHECKED_COUNT=0' <<<"$fetch_output" \
  || fail 'fetch-failed plugin was counted as successfully checked'
grep -Fxq 'PLUGIN_FETCH_FAILED_COUNT=1' <<<"$fetch_output" \
  || fail 'fetch failure did not increment failed-check count'
grep -Fxq 'PLUGIN_FETCH_FAILED_ID=third.party.git' <<<"$fetch_output" \
  || fail 'fetch failure was not reported to the caller'

echo "plugin update selector regression passed"
