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
panel="$repo_root/hancore.shibumi.bluetooth/BluetoothPanel.qml"
rg -q 'serviceFor\("hancore\.shibumi\.bluetooth"\)' "$widget" \
  || fail "Bluetooth widget does not resolve the shared service"
if rg -q 'bar\.bluetoothService' "$repo_root/hancore.shibumi.bluetooth"; then
  fail "Bluetooth plugin depends on transitional bar-owned Bluetooth state"
fi
rg -q 'property var bar: shell \? shell\.bar : null' "$service" \
  || fail "Bluetooth service does not use the versioned active bar facade"
rg -q 'registeredComponent\("omarchy\.bluetooth"\)' "$service" \
  || fail "Bluetooth service does not retain the official Omarchy owner"
rg -Fq '"barWidgetRegistry" in bar' "$service" \
  || fail "Bluetooth service cannot resolve the official owner on stock Quattro"
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
    "$widget" "$panel"; then
  fail "screen-local Bluetooth presentation owns backend work"
fi
rg -q 'id: heroPowerToggle' "$panel" \
  || fail "Bluetooth radio toggle is not grouped with adapter status"
if sed -n '/id: headerActions/,/^        }/p' "$panel" \
    | rg -q 'PowerToggle'; then
  fail "Bluetooth radio toggle must not split refresh and close actions"
fi
rg -Fq 'const current = rowAt(index)' "$panel" \
  || fail "Bluetooth section boundaries do not guard transient model rows"
rg -Fq 'connected ? "\uE1A8" : "\uE1A7"' "$widget" \
  || fail "connected Bluetooth bar state does not use stable glyph codepoints"
rg -Fq 'readonly property bool showConnectedCount: connected' "$widget" \
  || fail "connected Bluetooth count has no horizontal bar presentation state"
[[ $(rg -Fc 'visible: root.showConnectedCount' "$widget") -eq 2 ]] \
  || fail "connected Bluetooth count is not shown in every horizontal mode"
rg -Fq '? "\uE1A8" : "\uE1A7"' "$panel" \
  || fail "connected Bluetooth panel state does not use stable glyph codepoints"
rg -Fq 'if (icon === "phone" || icon === "smartphone") return ""' "$panel" \
  || fail "Bluetooth phone rows expose untrusted battery precision"
if rg -q 'omarchy-launch-bluetooth|Bluetooth settings' "$widget" "$panel"; then
  fail "Bluetooth presentation retains a launcher absent from current Quattro"
fi

printf 'bluetooth plugin regression passed\n'
