#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/home/hancore/Projects/omarchy-updates-pr}
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
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -Dm0644 "$repo_root/tests/telemetry-plugins-smoke.qml" "$tmpdir/shell.qml"
mkdir -m 700 "$tmpdir/runtime"

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
for source_contract in cpu core gpu nvme memory; do
  rg -Fq "\"$source_contract\"" \
    "$repo_root/hancore.shibumi.telemetry/ThermalTelemetry.qml" \
    || fail "temperature source is missing: $source_contract"
done
rg -q 'setGroupSetting\("G16", "source", candidate\)' \
  "$repo_root/hancore.shibumi.temperature/BarWidget.qml" \
  || fail "temperature source selection is not persisted"
rg -q 'panel\.ownerWidget\.setTemperatureSource' \
  "$repo_root/hancore.shibumi.temperature/TemperaturePanel.qml" \
  || fail "thermals panel does not expose source selection"

printf 'telemetry plugin regression passed\n'
