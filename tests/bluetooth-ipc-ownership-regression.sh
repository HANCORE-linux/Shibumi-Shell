#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
qs_bin=${QS_BIN:-/usr/bin/qs}
timeout_bin=${TIMEOUT_BIN:-/usr/bin/timeout}
ipc_timeout_seconds=${SHIBUMI_BT_IPC_TIMEOUT_SECONDS:-2}
case_orders=${SHIBUMI_BT_CASES:-"service-first backend-first"}
signal_ready_file=${SHIBUMI_BT_SIGNAL_READY_FILE:-}
case_root=""
case_shell_pid=""
case_shell_pgid=""
case_snapshot=""
case_order=""
failure_count=0

ipc_call() {
  "$timeout_bin" --foreground "$ipc_timeout_seconds" \
    env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
    "$qs_bin" ipc -p "$case_root" call "$@"
}

ipc_show() {
  "$timeout_bin" --foreground "$ipc_timeout_seconds" \
    env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
    "$qs_bin" ipc -p "$case_root" show
}

process_group_alive() {
  local pgid=${1:-}
  [[ $pgid =~ ^[0-9]+$ ]] \
    && kill -0 -- "-$pgid" 2>/dev/null
}

leader_is_reapable() {
  local pid=${1:-}
  local state=""
  [[ $pid =~ ^[0-9]+$ ]] || return 1
  if ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  if [[ -r /proc/$pid/stat ]]; then
    state=$(awk '{ print $3 }' "/proc/$pid/stat" 2>/dev/null || true)
    [[ $state == Z ]]
    return
  fi
  return 1
}

stop_case_process_group() {
  local pid=$case_shell_pid
  local pgid=$case_shell_pgid
  [[ $pgid =~ ^[0-9]+$ ]] || return 0

  if process_group_alive "$pgid"; then
    kill -TERM -- "-$pgid" 2>/dev/null || true
    for _ in {1..40}; do
      process_group_alive "$pgid" || break
      sleep 0.05
    done
  fi
  if process_group_alive "$pgid"; then
    kill -KILL -- "-$pgid" 2>/dev/null || true
    for _ in {1..40}; do
      process_group_alive "$pgid" || break
      sleep 0.05
    done
  fi
  if process_group_alive "$pgid"; then
    record_failure "$case_order process group $pgid survived TERM/KILL cleanup"
  fi

  # Never block on a live leader. wait is used only after exit or zombie state
  # has already been observed, so this is a non-blocking reap of cached status.
  if leader_is_reapable "$pid"; then
    wait "$pid" 2>/dev/null || true
  elif [[ $pid =~ ^[0-9]+$ ]]; then
    record_failure "$case_order leader $pid was not reapable after group cleanup"
  fi
}

cleanup_case() {
  local restored_state=""
  local restore_generation=""
  if [[ -n $case_snapshot && -n $case_shell_pid && -n $case_root ]] \
      && kill -0 "$case_shell_pid" 2>/dev/null; then
    restore_generation=$(ipc_call \
      shibumi-bluetooth-ipc-test restoreBluetooth "$case_snapshot" \
      2>/dev/null || true)
    if [[ $restore_generation =~ ^[0-9]+$ ]]; then
      for _ in {1..20}; do
        restored_state=$(ipc_call \
          shibumi-bluetooth-ipc-test settledBluetoothState \
          "$restore_generation" 2>/dev/null || true)
        [[ $restored_state != pending ]] && break
        sleep 0.05
      done
    fi
    if [[ $restored_state != "$case_snapshot" ]]; then
      record_failure "$case_order rollback is $restored_state, expected $case_snapshot"
    else
      printf '%s: rollback settled bluetooth/discovery=%s\n' \
        "$case_order" "$restored_state"
    fi
  fi
  case_snapshot=""
  stop_case_process_group
  case_shell_pid=""
  case_shell_pgid=""
  if [[ -n $case_root && -d $case_root ]]; then
    rm -rf -- "$case_root"
  fi
  case_root=""
  case_order=""
  return 0
}
trap cleanup_case EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

record_failure() {
  printf 'bluetooth IPC ownership regression: %s\n' "$*" >&2
  failure_count=$((failure_count + 1))
}

run_case() {
  local load_order=$1
  local ready_state=""
  local ipc_output=""
  local target_block=""
  local target_count=0
  local method_count=0
  local duplicate_count=0

  cleanup_case
  case_order=$load_order
  case_root=$(mktemp -d "/tmp/shibumi-bluetooth-ipc-${load_order}.XXXXXX")
  mkdir -p "$case_root/runtime" "$case_root/fixtures"
  chmod 700 "$case_root/runtime"
  cp -a -- "$repo_root/hancore.shibumi.bluetooth" "$case_root/bluetooth"
  cp -a -- "$omarchy_path/shell/Commons" "$case_root/Commons"
  cp -a -- "$omarchy_path/shell/Ui" "$case_root/Ui"
  install -m 0644 "$repo_root/tests/bluetooth-ipc-ownership-smoke.qml" \
    "$case_root/shell.qml"
  install -m 0644 "$repo_root/tests/fixtures/BluetoothTestBackend.qml" \
    "$case_root/fixtures/"

  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME='' \
  WAYLAND_DISPLAY='' \
  XDG_RUNTIME_DIR="$case_root/runtime" \
  SHIBUMI_BT_IPC_ORDER="$load_order" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    setsid "$quickshell_bin" -p "$case_root" --no-color \
    >"$case_root/quickshell.log" 2>&1 &
  case_shell_pid=$!
  case_shell_pgid=$(ps -o pgid= -p "$case_shell_pid" | tr -d ' ')
  if [[ $case_shell_pgid != "$case_shell_pid" ]]; then
    record_failure "$load_order shell PID $case_shell_pid does not own PGID $case_shell_pgid"
    cleanup_case
    return
  fi

  for _ in {1..100}; do
    if ! kill -0 "$case_shell_pid" 2>/dev/null; then
      record_failure "$load_order shell exited before IPC readiness"
      sed -n '1,220p' "$case_root/quickshell.log" >&2
      cleanup_case
      return
    fi
    ready_state=$(ipc_call shibumi-bluetooth-ipc-test ping 2>/dev/null || true)
    [[ $ready_state == "ready:$load_order" ]] && break
    sleep 0.05
  done

  if [[ $ready_state != "ready:$load_order" ]]; then
    record_failure "$load_order did not reach IPC readiness"
    sed -n '1,220p' "$case_root/quickshell.log" >&2
    cleanup_case
    return
  fi

  case_snapshot=$(ipc_call shibumi-bluetooth-ipc-test bluetoothState)
  [[ $case_snapshot =~ ^[01]:[01]$ ]] \
    || record_failure "$load_order invalid bluetooth snapshot: $case_snapshot"
  printf '%s: bluetooth/discovery snapshot=%s\n' \
    "$load_order" "$case_snapshot"

  sleep 0.1
  ipc_output=$(ipc_show)
  target_count=$(grep -c '^target omarchy\.bluetooth$' <<<"$ipc_output" || true)
  target_block=$(awk '
    /^target omarchy\.bluetooth$/ { capture = 1; next }
    /^target / { if (capture) exit }
    capture { print }
  ' <<<"$ipc_output")
  method_count=$(grep -c '^  function ' <<<"$target_block" || true)
  duplicate_count=$(rg -c \
    'another handler is registered for target omarchy\.bluetooth' \
    "$case_root/quickshell.log" || true)
  duplicate_count=${duplicate_count:-0}

  printf '%s: targets=%s methods=%s duplicates=%s\n' \
    "$load_order" "$target_count" "$method_count" "$duplicate_count"
  printf '%s\n' "$target_block"

  [[ $target_count -eq 1 ]] \
    || record_failure "$load_order exposes $target_count omarchy.bluetooth targets"
  [[ $duplicate_count -eq 0 ]] \
    || record_failure "$load_order emitted $duplicate_count duplicate registration warning(s)"
  [[ $method_count -eq 6 ]] \
    || record_failure "$load_order exposes $method_count methods instead of 6"

  local expected_method
  for expected_method in open close show hide toggle toggleBluetooth; do
    grep -Eq "^  function ${expected_method}\\(" <<<"$target_block" \
      || record_failure "$load_order is missing IPC method $expected_method"
  done

  local lifecycle_state=""
  local expected_state=""
  local lifecycle_method
  for lifecycle_method in open close show hide toggle toggle toggleBluetooth toggleBluetooth; do
    ipc_call -- omarchy.bluetooth "$lifecycle_method" >/dev/null
    sleep 0.03
    lifecycle_state=$(ipc_call shibumi-bluetooth-ipc-test state)
    printf '%s: after %s => %s\n' \
      "$load_order" "$lifecycle_method" "$lifecycle_state"
  done
  lifecycle_state=$(ipc_call shibumi-bluetooth-ipc-test state)
  expected_state="0:3:3:2:1:0"
  [[ $lifecycle_state == "$expected_state" ]] \
    || record_failure "$load_order lifecycle/rollback state is $lifecycle_state, expected $expected_state"

  local settled_state=""
  local settle_generation=""
  settle_generation=$(ipc_call \
    shibumi-bluetooth-ipc-test settleBluetoothState 2>/dev/null || true)
  if [[ $settle_generation =~ ^[0-9]+$ ]]; then
    for _ in {1..20}; do
      settled_state=$(ipc_call \
        shibumi-bluetooth-ipc-test settledBluetoothState \
        "$settle_generation" 2>/dev/null || true)
      [[ $settled_state != pending ]] && break
      sleep 0.05
    done
  fi
  if [[ $settled_state == "$case_snapshot" ]]; then
    printf '%s: success rollback settled bluetooth/discovery=%s\n' \
      "$load_order" "$settled_state"
  else
    record_failure "$load_order settled success rollback is $settled_state, expected $case_snapshot"
  fi

  local aborted_state=""
  aborted_state=$(ipc_call shibumi-bluetooth-ipc-test mutateBluetoothForAbort)
  [[ $aborted_state != "$case_snapshot" ]] \
    || record_failure "$load_order abort fixture did not mutate its isolated state"
  printf '%s: simulated abort state=%s\n' "$load_order" "$aborted_state"

  if [[ -n $signal_ready_file ]]; then
    printf '%s:%s:%s\n' \
      "$case_shell_pid" "$case_shell_pgid" "$case_root" >"$signal_ready_file"
    while [[ -e $signal_ready_file ]]; do sleep 0.05; done
  fi

  cleanup_case
}

[[ -d $omarchy_path/shell ]] \
  || record_failure "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] \
  || record_failure "Quickshell not found: $quickshell_bin"
[[ -x $qs_bin ]] \
  || record_failure "qs not found: $qs_bin"
[[ -x $timeout_bin ]] \
  || record_failure "timeout not found: $timeout_bin"
[[ $ipc_timeout_seconds =~ ^[1-9][0-9]*$ ]] \
  || record_failure "invalid IPC timeout: $ipc_timeout_seconds"
[[ $failure_count -eq 0 ]] || exit 1

for case_order_name in $case_orders; do
  case "$case_order_name" in
    service-first|backend-first) run_case "$case_order_name" ;;
    *) record_failure "unsupported load order: $case_order_name" ;;
  esac
done

if [[ $failure_count -ne 0 ]]; then
  printf 'bluetooth IPC ownership regression failed with %s invariant violation(s)\n' \
    "$failure_count" >&2
  exit 1
fi

printf 'bluetooth IPC ownership regression passed\n'
