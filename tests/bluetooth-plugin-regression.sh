#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
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
install -m 0644 "$repo_root/tests/fixtures/BluetoothTestBackend.qml" \
  "$repo_root/tests/fixtures/BluetoothTestView.qml" "$tmpdir/fixtures/"

set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
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

install -m 0644 "$repo_root/tests/bluetooth-backend-regression.qml" \
  "$tmpdir/shell.qml"
set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" --no-color 2>&1)
status=$?
set -e
printf '%s\n' "$output"
[[ $status -eq 0 ]] || fail "Bluetooth backend regression exited with $status"
grep -F 'bluetooth backend regression passed' <<<"$output" >/dev/null \
  || fail "Bluetooth backend success marker missing"

install -m 0644 "$repo_root/tests/bluetooth-adapter-hotplug-regression.qml" \
  "$tmpdir/shell.qml"
set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" --no-color 2>&1)
status=$?
set -e
printf '%s\n' "$output"
[[ $status -eq 0 ]] || fail "Bluetooth adapter hotplug regression exited with $status"
grep -F 'bluetooth adapter hotplug regression passed' <<<"$output" >/dev/null \
  || fail "Bluetooth adapter hotplug success marker missing"

install -m 0644 "$repo_root/tests/bluetooth-audio-intent-regression.qml" \
  "$tmpdir/shell.qml"
set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" --no-color 2>&1)
status=$?
set -e
printf '%s\n' "$output"
[[ $status -eq 0 ]] || fail "Bluetooth audio intent regression exited with $status"
grep -F 'bluetooth audio intent regression passed' <<<"$output" >/dev/null \
  || fail "Bluetooth audio intent success marker missing"

OMARCHY_PATH="$omarchy_path" \
  bash "$repo_root/tests/bluetooth-ipc-ownership-regression.sh"
OMARCHY_PATH="$omarchy_path" \
  "$repo_root/tests/bluetooth-ipc-harness-signal-regression.sh"

widget="$repo_root/hancore.shibumi.bluetooth/BarWidget.qml"
service="$repo_root/hancore.shibumi.bluetooth/Service.qml"
adapter="$repo_root/hancore.shibumi.bluetooth/BluetoothBackendAdapter.qml"
model="$repo_root/hancore.shibumi.bluetooth/BluetoothModel.js"
discovery_guard="$repo_root/hancore.shibumi.bluetooth/BluetoothDiscoveryGuard.qml"
panel="$repo_root/hancore.shibumi.bluetooth/BluetoothPanel.qml"
rg -q 'serviceFor\("hancore\.shibumi\.bluetooth"\)' "$widget" \
  || fail "Bluetooth widget does not resolve the shared service"
if rg -q 'bar\.bluetoothService' "$repo_root/hancore.shibumi.bluetooth"; then
  fail "Bluetooth plugin depends on transitional bar-owned Bluetooth state"
fi
rg -q 'property var bar: shell \? shell\.bar : null' "$service" \
  || fail "Bluetooth service does not use the versioned active bar facade"
[[ $(rg -c '^  BluetoothBackendAdapter \{' "$service") -eq 1 ]] \
  || fail "Bluetooth service does not own exactly one native adapter"
if rg -q 'registeredWidget|registeredSource|registeredComponent|panelSource|panelComponent|Loader \{' \
    "$service" "$adapter"; then
  fail "Bluetooth still resolves or loads a foreign UI component"
fi
if rg -q 'official_bluetooth_panel|plugins/panels/bluetooth/Panel\.qml' \
    "$repo_root/tests/contract-regression.sh"; then
  fail "Bluetooth contract still depends on the retired official panel"
fi
jq -e '
  .plugins[] | select(.id == "hancore.shibumi.bluetooth") |
  (.hostContracts // []) == []
' "$repo_root/contracts/plugin-suite-v1.json" >/dev/null \
  || fail "Bluetooth suite metadata still declares a host backend contract"
rg -q '^import Quickshell\.Bluetooth$' "$adapter" \
  || fail "Bluetooth adapter does not own the native BlueZ model"
rg -q '^import Quickshell\.Services\.Pipewire$' "$adapter" \
  || fail "Bluetooth adapter does not own Bluetooth audio routing"
rg -Fq 'executeDeviceCommand(deviceCommand(action, device.address))' "$adapter" \
  || fail "Bluetooth adapter does not preserve the device helper contract"
rg -Fq 'Model.deviceLists(nativeDevices)' "$adapter" \
  || fail "Bluetooth adapter does not normalize the native device model"
for device_signal in ConnectedDevices KnownDevices DiscoveredDevices; do
  rg -U -q "on${device_signal}Changed: \\{[^}]*syncNativePendingActions\\(\\)[^}]*syncNativeAudioHandoffIntents\\(\\)" \
    "$adapter" \
    || fail "Bluetooth pending actions ignore ${device_signal} property transitions"
done
rg -Fq 'if (discovering && !discoveryOwned) return true' "$adapter" \
  || fail "Bluetooth refresh can claim an externally owned discovery scan"
rg -q 'property var discoveryOwnerAdapter: null' "$adapter" \
  || fail "Bluetooth discovery ownership is not tied to its adapter instance"
[[ -f $model ]] || fail "Bluetooth native model is missing"
cmp -s "$repo_root/adapters/BluetoothBackendAdapter.qml" "$adapter" \
  || fail "root and plugin Bluetooth adapters drifted"
cmp -s "$repo_root/adapters/BluetoothModel.js" "$model" \
  || fail "root and plugin Bluetooth models drifted"
cmp -s "$repo_root/adapters/BluetoothDiscoveryGuard.qml" "$discovery_guard" \
  || fail "root and plugin Bluetooth discovery guards drifted"
if rg -q 'IpcHandler \{' "$adapter"; then
  fail "Bluetooth backend adapter must not register a second IPC owner"
fi
for termination_signal in INT TERM HUP; do
  rg -q "^trap .* ${termination_signal}$" \
    "$repo_root/tests/bluetooth-ipc-ownership-regression.sh" \
    || fail "Bluetooth IPC harness does not trap $termination_signal"
done
rg -q 'setsid .*quickshell|setsid .*quickshell_bin' \
  "$repo_root/tests/bluetooth-ipc-ownership-regression.sh" \
  || fail "Bluetooth IPC harness does not isolate the Quickshell process group"
rg -q 'process_group_alive.*|kill -0 -- "-\$pgid"' \
  "$repo_root/tests/bluetooth-ipc-ownership-regression.sh" \
  || fail "Bluetooth IPC harness does not observe the entire process group"
rg -q '"\$timeout_bin" --foreground "\$ipc_timeout_seconds"' \
  "$repo_root/tests/bluetooth-ipc-ownership-regression.sh" \
  || fail "Bluetooth IPC harness calls are not time-bounded"
for settle_method in settleBluetoothState settledBluetoothState; do
  rg -q "$settle_method" \
    "$repo_root/tests/bluetooth-ipc-ownership-regression.sh" \
    || fail "Bluetooth IPC success/abort rollback lacks $settle_method"
done
rg -q 'property var sessionOwners: \[\]' "$service" \
  || fail "Bluetooth panel sessions are not centrally tracked"
rg -q 'adapter\.stopDiscovery\(\)' "$service" \
  || fail "Bluetooth discovery lacks final-close cleanup"
rg -U -q 'id: discoveryRetry[^}]*repeat: true[^}]*running: root\.sessionCount > 0 && root\.adapterAvailable[^}]*root\.radioEnabled && !root\.discovering' \
  "$service" \
  || fail "Bluetooth discovery retry is not bounded to an open, powered idle session"
rg -U -q 'function confirmRequestedDiscovery\(\) \{(.|\n)*?requested\.discovering(.|\n)*?discoveryOwned = true(.|\n)*?\n  \}' \
  "$adapter" \
  || fail "Bluetooth discovery ownership is not confirmed from observed adapter state"
rg -q 'property var audioHandoffIntent: null' "$adapter" \
  || fail "Bluetooth audio handoff intent is not an explicit latest-only state"
rg -U -q 'function validatePendingAudioOutput\(\)[^}]*!radioEnabled[^}]*!device\.connected[^}]*!deviceUsesCurrentAdapter' \
  "$adapter" \
  || fail "Bluetooth audio handoff is not revalidated immediately before execution"
if rg -q 'Quickshell\.Bluetooth|Bluez|Process \{' \
    "$widget" "$panel"; then
  fail "screen-local Bluetooth presentation owns backend work"
fi
if rg -q 'Process \{|FileView \{' "$service" "$adapter"; then
  fail "Bluetooth owner uses an unbounded worker instead of native APIs"
fi
[[ $(rg -c '^  Timer \{' "$adapter") -eq 4 ]] \
  || fail "Bluetooth adapter must keep exactly the four bounded lifecycle timers"
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
