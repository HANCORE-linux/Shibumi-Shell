#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${SHIBUMI_TEST_NETWORK_IPC_MATRIX_CHILD:-0} != 1 ]]; then
  for style in current current-clone current-fallback legacy; do
    SHIBUMI_TEST_NETWORK_IPC_MATRIX_CHILD=1 \
      SHIBUMI_TEST_NETWORK_IPC_STYLE=$style "$0"
  done
  printf 'network IPC routing matrix regression passed\n'
  exit 0
fi

tmpdir=$(mktemp -d /tmp/shibumi-network-ipc-routing.XXXXXX)
shell_pid=""

fail() {
  printf 'network IPC routing regression failed: %s\n' "$*" >&2
  [[ -f $tmpdir/quickshell.log ]] && sed -n '1,220p' "$tmpdir/quickshell.log" >&2
  exit 1
}
cleanup() {
  if [[ -n $shell_pid ]] && kill -0 "$shell_pid" 2>/dev/null; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmpdir"
}
trap cleanup EXIT

mkdir -p "$tmpdir/home" "$tmpdir/runtime" "$tmpdir/network" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"
cp "$repo_root/tests/network-ipc-routing-smoke.qml" "$tmpdir/shell.qml"
cp "$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml" "$tmpdir/network/"
cp "$repo_root/tests/fixtures/NetworkIpcTestPanel.qml" "$tmpdir/fixtures/"

QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY='' \
SHIBUMI_TEST_NETWORK_IPC_STYLE="${SHIBUMI_TEST_NETWORK_IPC_STYLE:-current}" \
HOME="$tmpdir/home" XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" --no-color \
  >"$tmpdir/quickshell.log" 2>&1 &
shell_pid=$!

ipc() {
  timeout 2 env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$tmpdir/runtime" \
    /usr/bin/qs ipc -p "$tmpdir" call "$@"
}
state() { ipc network-ipc-routing-test state 2>/dev/null || true; }
backend_window_state() {
  ipc network-ipc-routing-test backendWindowState 2>/dev/null || true
}
overlay_window_state() {
  ipc network-ipc-routing-test overlayWindowState 2>/dev/null || true
}
wait_backend_hidden() {
  local actual=""
  for _ in {1..80}; do
    kill -0 "$shell_pid" 2>/dev/null || fail 'runtime exited unexpectedly'
    actual=$(backend_window_state)
    [[ $actual == closed:hidden ]] && return 0
    sleep 0.025
  done
  fail "hidden official KeyboardPanel became visible: $actual"
}
wait_state() {
  local expected=$1 actual=""
  for _ in {1..80}; do
    kill -0 "$shell_pid" 2>/dev/null || fail 'runtime exited unexpectedly'
    actual=$(state)
    [[ $actual == "$expected" ]] && return 0
    sleep 0.025
  done
  fail "expected state $expected, got $actual"
}

base='backend-closed:a-closed:b-closed:qr-closed:speed-idle:0:details-closed'
wait_state "$base"
wait_backend_hidden
[[ $(overlay_window_state) == qr-hidden:speed-hidden ]] \
  || fail 'authoritative overlay windows are visible while closed'
ipc network-ipc-routing-test probeSpeedWindow >/dev/null
[[ $(overlay_window_state) == qr-hidden:speed-visible ]] \
  || fail 'non-KeyboardPanel speed window binding was suppressed'
ipc network-ipc-routing-test clearSpeedWindowProbe >/dev/null
[[ $(overlay_window_state) == qr-hidden:speed-hidden ]] \
  || fail 'speed window probe did not close'
ipc omarchy.network open >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-idle:0:details-closed'
wait_backend_hidden
ipc network-ipc-routing-test focusB >/dev/null
ipc network-ipc-routing-test closeA >/dev/null
wait_state "$base"
ipc omarchy.network toggle >/dev/null
wait_state 'backend-closed:a-closed:b-open:qr-closed:speed-idle:0:details-closed'
ipc network-ipc-routing-test openA >/dev/null
wait_state 'backend-closed:a-open:b-open:qr-closed:speed-idle:0:details-closed'
ipc network-ipc-routing-test closeB >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-idle:0:details-closed'
ipc omarchy.network toggle >/dev/null
wait_state 'backend-closed:a-open:b-open:qr-closed:speed-idle:0:details-closed'
ipc omarchy.network close >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-idle:0:details-closed'
ipc network-ipc-routing-test closeA >/dev/null
wait_state "$base"
ipc network-ipc-routing-test focusA >/dev/null
ipc network-ipc-routing-test openA >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-idle:0:details-closed'
ipc omarchy.network close >/dev/null
wait_state "$base"
ipc network-ipc-routing-test openA >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-idle:0:details-closed'
ipc omarchy.network toggle >/dev/null
wait_state "$base"
ipc omarchy.network open >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-idle:0:details-closed'
ipc network-ipc-routing-test focusB >/dev/null
ipc network-ipc-routing-test openB >/dev/null
wait_state 'backend-closed:a-open:b-open:qr-closed:speed-idle:0:details-closed'
ipc omarchy.network close >/dev/null
wait_state "$base"
ipc network-ipc-routing-test focusA >/dev/null
ipc omarchy.network open >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-idle:0:details-closed'
ipc omarchy.network showQr >/dev/null
wait_state 'backend-closed:a-closed:b-closed:qr-open:speed-idle:0:details-closed'
[[ $(overlay_window_state) == qr-visible:speed-hidden ]] \
  || fail 'authoritative QR overlay was suppressed with KeyboardPanel'
ipc omarchy.network close >/dev/null
wait_state "$base"
[[ $(overlay_window_state) == qr-hidden:speed-hidden ]] \
  || fail 'authoritative QR overlay did not close through public IPC'
ipc omarchy.network showQr >/dev/null
wait_state 'backend-closed:a-closed:b-closed:qr-open:speed-idle:0:details-closed'
ipc omarchy.network toggle >/dev/null
wait_state "$base"
[[ $(overlay_window_state) == qr-hidden:speed-hidden ]] \
  || fail 'authoritative or cloned QR overlay did not close through toggle'
ipc network-ipc-routing-test reloadBackend >/dev/null
wait_state "$base"
ipc omarchy.network speedTest >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-running:1:details-open'
[[ $(overlay_window_state) == qr-hidden:speed-hidden ]] \
  || fail 'inline speed-test routing opened an Omarchy speed overlay'
ipc network-ipc-routing-test closeA >/dev/null
wait_state 'backend-closed:a-closed:b-closed:qr-closed:speed-idle:1:details-open'
ipc omarchy.network open >/dev/null
wait_state 'backend-closed:a-open:b-closed:qr-closed:speed-idle:1:details-open'
ipc omarchy.network close >/dev/null
wait_state 'backend-closed:a-closed:b-closed:qr-closed:speed-idle:1:details-open'
wait_backend_hidden
[[ $(ipc network-ipc-routing-test backendOpenCount) == 0 ]] \
  || fail "${SHIBUMI_TEST_NETWORK_IPC_STYLE:-current} host backend opened behind Shibumi"
[[ $(ipc network-ipc-routing-test officialSpeedRuns) == 0 ]] \
  || fail "${SHIBUMI_TEST_NETWORK_IPC_STYLE:-current} host IPC started its official speed test"

ipc_show=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/qs ipc -p "$tmpdir" show)
[[ $(grep -c '^target omarchy\.network$' <<<"$ipc_show") -eq 1 ]] \
  || fail 'omarchy.network does not have exactly one authoritative owner'
if grep -q 'another handler is registered for target' "$tmpdir/quickshell.log"; then
  fail 'runtime registered a duplicate IPC owner'
fi
if grep -Eq 'TypeError|ReferenceError|Binding loop|failed to load' \
    "$tmpdir/quickshell.log"; then
  fail 'runtime emitted a QML error'
fi

printf 'network IPC routing regression passed (%s host style)\n' \
  "${SHIBUMI_TEST_NETWORK_IPC_STYLE:-current}"
