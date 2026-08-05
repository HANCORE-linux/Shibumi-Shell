#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d "/tmp/shibumi-bluetooth-signals.XXXXXX")
trap 'rm -rf -- "$tmpdir"' EXIT

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
  IFS=: read -r shell_pid case_root <"$marker"
  [[ $shell_pid =~ ^[0-9]+$ ]] \
    || fail "$signal_name produced an invalid shell PID: $shell_pid"
  if kill -0 "$shell_pid" 2>/dev/null; then
    fail "$signal_name left Quickshell process $shell_pid alive"
  fi
  [[ ! -e $case_root ]] \
    || fail "$signal_name left its isolated case root behind: $case_root"
  rg -q 'rollback restored bluetooth/discovery=' "$output" \
    || fail "$signal_name did not restore the Bluetooth snapshot"
done

printf 'bluetooth IPC signal regression passed\n'
