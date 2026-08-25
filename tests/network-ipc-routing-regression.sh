#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
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

mkdir -p "$tmpdir/home" "$tmpdir/runtime" "$tmpdir/network"
chmod 700 "$tmpdir/runtime"
cp "$repo_root/tests/network-ipc-routing-smoke.qml" "$tmpdir/shell.qml"
cp "$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml" "$tmpdir/network/"

QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY='' \
HOME="$tmpdir/home" XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" --no-color \
  >"$tmpdir/quickshell.log" 2>&1 &
shell_pid=$!

ipc() {
  timeout 2 env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$tmpdir/runtime" \
    /usr/bin/qs ipc -p "$tmpdir" call "$@"
}
state() { ipc network-ipc-routing-test state 2>/dev/null || true; }
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

wait_state 'a-closed:none:b-closed:none:0'
ipc omarchy.network open >/dev/null
wait_state 'a-open:panel:b-closed:none:0'
ipc omarchy.network toggle >/dev/null
wait_state 'a-closed:none:b-closed:none:0'
ipc network-ipc-routing-test focusB >/dev/null
ipc omarchy.network showQr >/dev/null
wait_state 'a-closed:none:b-open:qr:0'
ipc omarchy.network close >/dev/null
wait_state 'a-closed:none:b-closed:none:0'
ipc network-ipc-routing-test focusA >/dev/null
ipc omarchy.network speedTest >/dev/null
wait_state 'a-open:speed:b-closed:none:0'
ipc omarchy.network toggleNetwork >/dev/null
wait_state 'a-open:speed:b-closed:none:1'
ipc omarchy.network hide >/dev/null
wait_state 'a-closed:none:b-closed:none:1'

ipc_show=$(env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/qs ipc -p "$tmpdir" show)
[[ $(grep -c '^target omarchy\.network$' <<<"$ipc_show") -eq 1 ]] \
  || fail 'omarchy.network does not have exactly one compatibility owner'
if grep -q 'another handler is registered for target' "$tmpdir/quickshell.log"; then
  fail 'runtime registered a duplicate IPC owner'
fi
if grep -Eq 'TypeError|ReferenceError|Binding loop|failed to load' \
    "$tmpdir/quickshell.log"; then
  fail 'runtime emitted a QML error'
fi
if rg -q 'Loader|panelSource|panelComponent|omarchy\.wifiqr|omarchy\.speedtest' \
    "$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml"; then
  fail 'compatibility route still loads an Omarchy feature backend'
fi

printf 'network IPC routing regression passed\n'
