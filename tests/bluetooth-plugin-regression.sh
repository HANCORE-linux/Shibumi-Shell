#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/home/hancore/Projects/omarchy-updates-pr}
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-bluetooth.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'bluetooth plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.bluetooth" "$tmpdir/bluetooth"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/bluetooth-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/BluetoothTestPanel.qml" \
  "$repo_root/tests/fixtures/BluetoothTestView.qml" "$tmpdir/fixtures/"

set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
rc=$?
set -e

printf '%s\n' "$output"
[[ $rc -eq 0 ]] || fail "component smoke exited $rc"
grep -F 'bluetooth plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

widget="$repo_root/hancore.shibumi.bluetooth/BarWidget.qml"
service="$repo_root/hancore.shibumi.bluetooth/Service.qml"
bridge="$repo_root/hancore.shibumi.bluetooth/BluetoothPanelBridge.qml"
rg -q 'serviceFor\("hancore\.shibumi\.bluetooth"\)' "$widget" \
  || fail "Bluetooth widget does not resolve the shared service"
if rg -q 'bar\.bluetoothService' "$repo_root/hancore.shibumi.bluetooth"; then
  fail "Bluetooth plugin depends on transitional bar-owned Bluetooth state"
fi
rg -q 'property var bar: shell \? shell\.bar : null' "$service" \
  || fail "Bluetooth service does not use the versioned active bar facade"
rg -q 'registeredWidgetComponent\("omarchy\.bluetooth"\)' "$service" \
  || fail "Bluetooth service does not retain the official Omarchy owner"
[[ $(rg -c '^  BluetoothPanelBridge \{' "$service") -eq 1 ]] \
  || fail "Bluetooth service does not own exactly one official bridge"
if rg -Fq 'panel.bar = null' "$bridge"; then
  fail "Bluetooth bridge clears the official panel host before destruction"
fi
rg -q 'property var sessionOwners: \[\]' "$service" \
  || fail "Bluetooth panel sessions are not centrally tracked"
rg -q 'bridge\.stopDiscovery\(\)' "$service" \
  || fail "Bluetooth discovery lacks final-close cleanup"
if rg -q 'Quickshell\.Bluetooth|Bluez|Process \{' \
    "$widget" "$repo_root/hancore.shibumi.bluetooth/BluetoothPanel.qml"; then
  fail "screen-local Bluetooth presentation owns backend work"
fi

printf 'bluetooth plugin regression passed\n'
