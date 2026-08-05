#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
qs_bin=${QS_BIN:-/usr/bin/qs}
case_root=""
case_shell_pid=""
case_snapshot=""
case_order=""
failure_count=0

cleanup_case() {
  local restored_state=""
  if [[ -n $case_snapshot && -n $case_shell_pid && -n $case_root ]] \
      && kill -0 "$case_shell_pid" 2>/dev/null; then
    restored_state=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
      "$qs_bin" ipc -p "$case_root" call \
      shibumi-bluetooth-ipc-test restoreBluetooth "$case_snapshot" \
      2>/dev/null || true)
    if [[ $restored_state != "$case_snapshot" ]]; then
      record_failure "$case_order rollback is $restored_state, expected $case_snapshot"
    else
      printf '%s: rollback restored bluetooth/discovery=%s\n' \
        "$case_order" "$restored_state"
    fi
  fi
  case_snapshot=""
  if [[ -n $case_shell_pid ]] && kill -0 "$case_shell_pid" 2>/dev/null; then
    kill "$case_shell_pid" 2>/dev/null || true
    wait "$case_shell_pid" 2>/dev/null || true
  fi
  case_shell_pid=""
  if [[ -n $case_root && -d $case_root ]]; then
    rm -rf -- "$case_root"
  fi
  case_root=""
  case_order=""
}
trap cleanup_case EXIT

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

  env \
    QT_QPA_PLATFORM=offscreen \
    QT_QPA_PLATFORMTHEME= \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$case_root/runtime" \
    SHIBUMI_BT_IPC_ORDER="$load_order" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$case_root" --no-color \
    >"$case_root/quickshell.log" 2>&1 &
  case_shell_pid=$!

  for _ in {1..100}; do
    if ! kill -0 "$case_shell_pid" 2>/dev/null; then
      record_failure "$load_order shell exited before IPC readiness"
      sed -n '1,220p' "$case_root/quickshell.log" >&2
      cleanup_case
      return
    fi
    ready_state=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
      "$qs_bin" ipc -p "$case_root" call \
      shibumi-bluetooth-ipc-test ping 2>/dev/null || true)
    [[ $ready_state == "ready:$load_order" ]] && break
    sleep 0.05
  done

  if [[ $ready_state != "ready:$load_order" ]]; then
    record_failure "$load_order did not reach IPC readiness"
    sed -n '1,220p' "$case_root/quickshell.log" >&2
    cleanup_case
    return
  fi

  case_snapshot=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
    "$qs_bin" ipc -p "$case_root" call \
    shibumi-bluetooth-ipc-test bluetoothState)
  [[ $case_snapshot =~ ^[01]:[01]$ ]] \
    || record_failure "$load_order invalid bluetooth snapshot: $case_snapshot"
  printf '%s: bluetooth/discovery snapshot=%s\n' \
    "$load_order" "$case_snapshot"

  sleep 0.1
  ipc_output=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
    "$qs_bin" ipc -p "$case_root" show)
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
    env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
      "$qs_bin" ipc -p "$case_root" call \
      -- omarchy.bluetooth "$lifecycle_method" >/dev/null
    sleep 0.03
    lifecycle_state=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
      "$qs_bin" ipc -p "$case_root" call \
      shibumi-bluetooth-ipc-test state)
    printf '%s: after %s => %s\n' \
      "$load_order" "$lifecycle_method" "$lifecycle_state"
  done
  lifecycle_state=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
    "$qs_bin" ipc -p "$case_root" call \
    shibumi-bluetooth-ipc-test state)
  expected_state="0:3:3:2:1:0"
  [[ $lifecycle_state == "$expected_state" ]] \
    || record_failure "$load_order lifecycle/rollback state is $lifecycle_state, expected $expected_state"

  local settled_state=""
  settled_state=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
    "$qs_bin" ipc -p "$case_root" call \
    shibumi-bluetooth-ipc-test bluetoothState)
  [[ $settled_state == "$case_snapshot" ]] \
    || record_failure "$load_order success rollback is $settled_state, expected $case_snapshot"

  local aborted_state=""
  aborted_state=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$case_root/runtime" \
    "$qs_bin" ipc -p "$case_root" call \
    shibumi-bluetooth-ipc-test mutateBluetoothForAbort)
  [[ $aborted_state != "$case_snapshot" ]] \
    || record_failure "$load_order abort fixture did not mutate its isolated state"
  printf '%s: simulated abort state=%s\n' "$load_order" "$aborted_state"

  cleanup_case
}

[[ -d $omarchy_path/shell ]] \
  || record_failure "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] \
  || record_failure "Quickshell not found: $quickshell_bin"
[[ -x $qs_bin ]] \
  || record_failure "qs not found: $qs_bin"
[[ $failure_count -eq 0 ]] || exit 1

run_case service-first
run_case backend-first

if [[ $failure_count -ne 0 ]]; then
  printf 'bluetooth IPC ownership regression failed with %s invariant violation(s)\n' \
    "$failure_count" >&2
  exit 1
fi

printf 'bluetooth IPC ownership regression passed\n'
