#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d "/tmp/shibumi-bluetooth-signals.XXXXXX")
real_quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
stubborn_pgid=""

cleanup() {
  if [[ $stubborn_pgid =~ ^[0-9]+$ ]]; then
    kill -KILL -- "-$stubborn_pgid" 2>/dev/null || true
  fi
  rm -rf -- "$tmpdir"
}
trap cleanup EXIT

fail() {
  printf 'bluetooth IPC signal regression: %s\n' "$*" >&2
  exit 1
}

for signal_spec in INT:130 TERM:143 HUP:129; do
  signal_name=${signal_spec%%:*}
  expected_status=${signal_spec##*:}
  marker="$tmpdir/$signal_name.ready"
  output="$tmpdir/$signal_name.log"

  set +e
  SHIBUMI_BT_CASES=service-first \
  SHIBUMI_BT_SIGNAL_READY_FILE="$marker" \
    timeout --preserve-status --signal="$signal_name" --kill-after=3 4 \
      bash "$repo_root/tests/bluetooth-ipc-ownership-regression.sh" \
      >"$output" 2>&1
  status=$?
  set -e

  [[ $status -eq $expected_status ]] \
    || fail "$signal_name returned $status instead of $expected_status"
  [[ -s $marker ]] \
    || fail "$signal_name arrived before the simulated abort was ready"
  IFS=: read -r shell_pid shell_pgid case_root <"$marker"
  [[ $shell_pid =~ ^[0-9]+$ && $shell_pgid =~ ^[0-9]+$ ]] \
    || fail "$signal_name produced invalid shell process identity"
  if kill -0 "$shell_pid" 2>/dev/null; then
    fail "$signal_name left Quickshell process $shell_pid alive"
  fi
  if kill -0 -- "-$shell_pgid" 2>/dev/null; then
    fail "$signal_name left Quickshell process group $shell_pgid alive"
  fi
  [[ ! -e $case_root ]] \
    || fail "$signal_name left its isolated case root behind: $case_root"
  rg -q 'rollback settled bluetooth/discovery=' "$output" \
    || fail "$signal_name did not restore the Bluetooth snapshot"
done

marker="$tmpdir/stubborn.ready"
output="$tmpdir/stubborn.log"
child_state="$tmpdir/stubborn-child.state"
set +e
QUICKSHELL_BIN="$repo_root/tests/fixtures/quickshell-with-stubborn-child.sh" \
REAL_QUICKSHELL_BIN="$real_quickshell_bin" \
SHIBUMI_BT_STUBBORN_CHILD_FILE="$child_state" \
SHIBUMI_BT_CASES=service-first \
SHIBUMI_BT_SIGNAL_READY_FILE="$marker" \
  timeout --preserve-status --signal=TERM --kill-after=3 4 \
    bash "$repo_root/tests/bluetooth-ipc-ownership-regression.sh" \
    >"$output" 2>&1
status=$?
set -e

[[ $status -eq 143 ]] || fail "stubborn process-group case returned $status instead of 143"
[[ -s $marker ]] || fail "stubborn case did not publish its shell process identity"
IFS=: read -r stubborn_shell_pid stubborn_shell_pgid stubborn_case_root <"$marker"
[[ $stubborn_shell_pid =~ ^[0-9]+$ && $stubborn_shell_pgid =~ ^[0-9]+$ ]] \
  || fail "stubborn case produced invalid shell process identity"
[[ -s $child_state ]] || fail "stubborn child did not publish its PID and PGID"
IFS=: read -r stubborn_child_pid stubborn_pgid <"$child_state"
[[ $stubborn_child_pid =~ ^[0-9]+$ && $stubborn_pgid =~ ^[0-9]+$ ]] \
  || fail "stubborn child produced invalid process identity"
if kill -0 -- "-$stubborn_pgid" 2>/dev/null; then
  fail "TERM cleanup left process group $stubborn_pgid alive"
fi
if kill -0 "$stubborn_shell_pid" 2>/dev/null; then
  fail "TERM cleanup left Quickshell process $stubborn_shell_pid alive"
fi
if kill -0 -- "-$stubborn_shell_pgid" 2>/dev/null; then
  fail "TERM cleanup left Quickshell process group $stubborn_shell_pgid alive"
fi
[[ ! -e $stubborn_case_root ]] \
  || fail "stubborn case left its isolated case root behind: $stubborn_case_root"
snapshot_state=$(sed -n 's/^service-first: bluetooth\/discovery snapshot=//p' "$output" | tail -n 1)
rollback_state=$(sed -n 's/^service-first: rollback settled bluetooth\/discovery=//p' "$output" | tail -n 1)
[[ $snapshot_state =~ ^[01]:[01]$ ]] \
  || fail "stubborn case lacks a valid Bluetooth snapshot"
[[ $rollback_state == "$snapshot_state" ]] \
  || fail "stubborn case restored $rollback_state instead of $snapshot_state"

for rollback_log in "$tmpdir"/INT.log "$tmpdir"/TERM.log "$tmpdir"/HUP.log; do
  rg -q 'rollback settled bluetooth/discovery=' "$rollback_log" \
    || fail "$(basename "$rollback_log" .log) lacks event-loop-settled rollback proof"
done

printf 'bluetooth IPC signal regression passed\n'
