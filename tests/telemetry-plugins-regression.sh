#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-telemetry-plugins.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'telemetry plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

cp -a -- "$repo_root/hancore.shibumi.telemetry" "$tmpdir/telemetry"
cp -a -- "$repo_root/hancore.shibumi.memory" "$tmpdir/memory"
cp -a -- "$repo_root/hancore.shibumi.cpu" "$tmpdir/cpu"
cp -a -- "$repo_root/hancore.shibumi.gpu" "$tmpdir/gpu"
cp -a -- "$repo_root/hancore.shibumi.state" "$tmpdir/hancore.shibumi.state"
printf '{"suiteId":"hancore.shibumi","suitePayloadDigest":"%064d"}\n' 0 \
  > "$tmpdir/hancore.shibumi.state/.shibumi-managed.json"
cp -a -- "$repo_root/hancore.shibumi.temperature" "$tmpdir/temperature"
cp -a -- "$repo_root/hancore.shibumi.storage" "$tmpdir/storage"
for plugin in cpu memory gpu temperature storage; do
  install -m 0644 "$repo_root/tests/fixtures/ShibumiPanelTest.qml" \
    "$tmpdir/$plugin/ShibumiPanel.qml"
done
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -Dm0644 "$repo_root/tests/telemetry-plugins-smoke.qml" "$tmpdir/shell.qml"
mkdir -m 700 "$tmpdir/runtime"
mkdir -p "$tmpdir/home"
# All three QML entry points get private paths, including direct standalone use.
export HOME="$tmpdir/home" XDG_CONFIG_HOME="$tmpdir/home/.config"
export XDG_STATE_HOME="$tmpdir/home/.local/state" XDG_DATA_HOME="$tmpdir/home/.local/share"
export XDG_CACHE_HOME="$tmpdir/home/.cache" XDG_DATA_DIRS="$tmpdir/data"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$tmpdir/absent-session"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$tmpdir/absent-system"
export HYPRLAND_INSTANCE_SIGNATURE='' WAYLAND_DISPLAY='' DISPLAY=''
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software
export QT_FORCE_STDERR_LOGGING=1 QML_DISABLE_DISK_CACHE=1

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
[[ $rc -eq 0 ]] || fail "Quickshell exited $rc"
grep -F 'telemetry plugins smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"
if grep -Eq 'telemetry-plugins-smoke:|TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$output"; then
  fail "telemetry plugin QML runtime error detected"
fi

install -m 0644 "$repo_root/tests/gpu-selection-state-smoke.qml" \
  "$tmpdir/state-shell.qml"
mkdir -m 700 "$tmpdir/state-runtime"
python3 - "$tmpdir/state-home/.config/omarchy/shell.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.parent.mkdir(parents=True)
path.write_text(json.dumps({'version': 1,
    'bar': {'layout': {'left': [], 'center': [], 'right': []}},
    'plugins': [{'id': 'hancore.shibumi.state', 'shibumiStateSchemaVersion': 1,
                 'shibumi': {'version': 1}, 'foreign': {'keep': 42}}]}))
PY
set +e
state_output=$(timeout 8 env \
  HOME="$tmpdir/state-home" \
  XDG_CONFIG_HOME="$tmpdir/state-home/.config" \
  XDG_STATE_HOME="$tmpdir/state-home/.local/state" \
  XDG_DATA_HOME="$tmpdir/state-home/.local/share" \
  XDG_CACHE_HOME="$tmpdir/state-home/.cache" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$tmpdir/absent-session" \
  DBUS_SYSTEM_BUS_ADDRESS="unix:path=$tmpdir/absent-system" \
  HYPRLAND_INSTANCE_SIGNATURE= \
  OMARCHY_PATH="$tmpdir/absent-native-defaults" \
  QT_FORCE_STDERR_LOGGING=1 \
  QML_DISABLE_DISK_CACHE=1 \
  QT_QUICK_BACKEND=software \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/state-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir/state-shell.qml" 2>&1)
state_rc=$?
set -e
printf '%s\n' "$state_output"
[[ $state_rc -eq 0 ]] || fail "GPU state smoke exited $state_rc"
grep -F 'GPU selection state smoke passed' <<<"$state_output" >/dev/null \
  || fail "GPU state success marker missing"
if grep -Eq 'gpu-selection-state-smoke:|TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$state_output"; then
  fail "GPU state QML runtime error detected"
fi

install -m 0644 "$repo_root/tests/telemetry-runtime-smoke.qml" "$tmpdir/runtime-shell.qml"
mkdir -m 700 "$tmpdir/slice-runtime"
set +e
slice_output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$tmpdir/slice-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir/runtime-shell.qml" 2>&1)
slice_rc=$?
set -e
printf '%s\n' "$slice_output"
[[ $slice_rc -eq 0 ]] || fail "scoped telemetry smoke exited $slice_rc"
grep -F 'telemetry runtime smoke passed' <<<"$slice_output" >/dev/null \
  || fail "scoped telemetry success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error|Cannot assign' <<<"$slice_output"; then
  fail "scoped telemetry QML runtime error detected"
fi

for plugin in memory cpu; do
  if rg -q 'bar\.(systemTelemetry|gpuTelemetry|systemActions)' \
      "$repo_root/hancore.shibumi.$plugin" --glob '*.qml'; then
    fail "$plugin still consumes transitional bar-owned feature state"
  fi
done

rg -q 'serviceFor\("hancore\.shibumi\.telemetry"\)' \
  "$repo_root/hancore.shibumi.memory/BarWidget.qml" \
  || fail "memory does not resolve the shared telemetry service"
rg -q 'serviceFor\("hancore\.shibumi\.cpu"\)' \
  "$repo_root/hancore.shibumi.cpu/BarWidget.qml" \
  || fail "CPU does not resolve its GPU service"
for plugin in memory cpu; do
  rg -q 'bar\.run\("omarchy-launch-or-focus-tui btop"\)' \
    "$repo_root/hancore.shibumi.$plugin/BarWidget.qml" \
    || fail "$plugin widget does not use the Quattro TUI launcher"
  rg -q 'panel\.ownerWidget\.openSystemMonitor\(\)' \
    "$repo_root/hancore.shibumi.$plugin/${plugin^}Panel.qml" \
    || fail "$plugin panel bypasses its owner action"
done
rg -q 'text: "CPU · GPU"' \
  "$repo_root/hancore.shibumi.cpu/CpuPanel.qml" \
  || fail "CPU panel lost the V1 CPU/GPU heading"
rg -q 'visible: panel\.gpuTelemetry && panel\.gpuTelemetry\.available' \
  "$repo_root/hancore.shibumi.cpu/CpuPanel.qml" \
  || fail "CPU panel does not gate GPU data on a real telemetry backend"
gpu_widget="$repo_root/hancore.shibumi.gpu/BarWidget.qml"
gpu_panel="$repo_root/hancore.shibumi.gpu/GpuPanel.qml"
for gpu_fallback_contract in \
  'readonly property bool telemetryAvailable:' \
  'visible: true' \
  '"GPU telemetry unavailable"' \
  ': "--"'; do
  rg -Fq "$gpu_fallback_contract" "$gpu_widget" \
    || fail "GPU widget has no visible unsupported-hardware fallback: $gpu_fallback_contract"
done
if rg -Fq 'visible: root.gpu && root.gpu.available' "$gpu_widget"; then
  fail "active GPU widget still collapses to 0x0 without a telemetry backend"
fi
for panel_contract in \
  'const driver = String(device.driverName' \
  'label: "Device"' \
  'label: "Driver"' \
  'label: "Load"' \
  'label: "Temperature"' \
  'label: "VRAM"'; do
  rg -Fq "$panel_contract" "$gpu_panel" \
    || fail "GPU panel hardware contract is missing: $panel_contract"
done
for selection_contract in \
  'readonly property string configuredDeviceId:' \
  'readonly property var availableGpus:' \
  'readonly property var selectedGpu:' \
  'stateService.setGroupSetting(stateGroupId, "device", target)' \
  'gpuForDevice(configuredDeviceId)' \
  'root.selectedGpu.utilization'; do
  rg -Fq "$selection_contract" "$gpu_widget" \
    || fail "GPU source-selection contract is missing: $selection_contract"
done
for selection_contract in \
  'text: "BAR SOURCE"' \
  'sourceId: "auto"' \
  'model: panel.devices.length' \
  'panel.ownerWidget.configuredDeviceId === sourceId' \
  'panel.selectDevice(sourceId)' \
  'onMoveRequested: function(dx, dy) { panel.moveSourceCursor(dx, dy) }' \
  'onActivateRequested: panel.activateSourceCursor()' \
  'contentHeight: content.implicitHeight' \
  'Accessible.onPressAction: choice.triggered()'; do
  rg -Fq "$selection_contract" "$gpu_panel" \
    || fail "GPU panel selection contract is missing: $selection_contract"
done
if rg -q 'topProcesses|acquireDetails|releaseDetails|GPU PROCESSES|process data' \
    "$gpu_panel" "$repo_root/hancore.shibumi.cpu/GpuTelemetry.qml"; then
  fail "removed GPU process telemetry is still reachable"
fi
for removed_process_contract in pmon SHIBUMI_GPU_PROC_ROOT \
    emit_drm_processes "printf 'proc|" "printf 'counter|"; do
  if rg -Fq "$removed_process_contract" \
      "$repo_root/hancore.shibumi.cpu/scripts/shibumi-gpu-probe"; then
    fail "GPU helper still collects per-process activity: $removed_process_contract"
  fi
done
rg -Fq 'command: ["timeout", "--signal=TERM"' \
  "$repo_root/hancore.shibumi.cpu/GpuTelemetry.qml" \
  || fail "GPU helper probe is not time-bounded"
for source_contract in cpu core gpu nvme memory; do
  rg -Fq "\"$source_contract\"" \
    "$repo_root/hancore.shibumi.telemetry/ThermalTelemetry.qml" \
    || fail "temperature source is missing: $source_contract"
done
rg -q 'setGroupSetting\(stateGroupId, "source", candidate\)' \
  "$repo_root/hancore.shibumi.temperature/BarWidget.qml" \
  || fail "temperature source selection is not persisted"
rg -q 'setGroupSetting\(stateGroupId, "unit", candidate\)' \
  "$repo_root/hancore.shibumi.temperature/BarWidget.qml" \
  || fail "temperature unit selection is not persisted"
for temperature_contract in \
  'text: root.temperatureText(root.temperatureC)' \
  'root.sourceLabel + " · " + root.temperatureText(root.temperatureC)'; do
  rg -Fq "$temperature_contract" \
    "$repo_root/hancore.shibumi.temperature/BarWidget.qml" \
    || fail "temperature rendering contract missing: $temperature_contract"
done
if rg -Fq 'temperatureValueSlotWidth' \
    "$repo_root/hancore.shibumi.temperature/BarWidget.qml"; then
  fail "temperature value still reserves trailing maximum-width space"
fi
rg -q 'panel\.ownerWidget\.setTemperatureSource' \
  "$repo_root/hancore.shibumi.temperature/TemperaturePanel.qml" \
  || fail "thermals panel does not expose source selection"
for panel_contract in \
  'label: "°C"' \
  'label: "°F"' \
  'panel.ownerWidget.setTemperatureUnit(unit)' \
  'panel.ownerWidget.temperatureText(modelData.temperatureC)' \
  'onMoveRequested: function(dx, _dy)' \
  'onActivateRequested: panel.activateUnitCursor()' \
  'Accessible.checked: selected' \
  'Accessible.onPressAction: unitChoice.triggered()'; do
  rg -Fq "$panel_contract" \
    "$repo_root/hancore.shibumi.temperature/TemperaturePanel.qml" \
    || fail "thermals panel unit contract missing: $panel_contract"
done

printf 'telemetry plugin regression passed\n'
