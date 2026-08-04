#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:---check}

case "$mode" in
  --check | --write) ;;
  *)
    printf 'Usage: %s [--check|--write]\n' "$0" >&2
    exit 2
    ;;
esac

mappings=(
  "shared/state/ShibumiConfig.js:core/ShibumiConfig.js"
  "shared/state/ShibumiConfig.js:hancore.shibumi.state/ShibumiConfig.js"
  "shared/state/ThemePalette.qml:services/ThemePalette.qml"
  "shared/state/ThemePalette.qml:hancore.shibumi.state/ThemePalette.qml"
  "shared/state/ThemePaletteModel.js:services/ThemePaletteModel.js"
  "shared/state/ThemePaletteModel.js:hancore.shibumi.state/ThemePaletteModel.js"
  "shared/telemetry/SystemTelemetry.qml:services/SystemTelemetry.qml"
  "shared/telemetry/SystemTelemetry.qml:hancore.shibumi.telemetry/SystemTelemetry.qml"
  "shared/telemetry/ThermalTelemetry.qml:services/ThermalTelemetry.qml"
  "shared/telemetry/ThermalTelemetry.qml:hancore.shibumi.telemetry/ThermalTelemetry.qml"
  "shared/telemetry/GpuTelemetry.qml:services/GpuTelemetry.qml"
  "shared/telemetry/GpuTelemetry.qml:hancore.shibumi.cpu/GpuTelemetry.qml"
  "shared/power-state/Service.qml:services/PowerService.qml"
  "shared/power-state/Service.qml:hancore.shibumi.power-state/Service.qml"
  "shared/power-state/PowerModel.js:services/PowerModel.js"
  "shared/power-state/PowerModel.js:hancore.shibumi.power-state/PowerModel.js"
  "shared/quick-access/PickerModel.js:services/PickerModel.js"
  "shared/quick-access/PickerModel.js:hancore.shibumi.quick-access/PickerModel.js"
  "shared/reactor/ReactorModel.js:services/ReactorModel.js"
  "shared/reactor/ReactorModel.js:hancore.shibumi.reactor/ReactorModel.js"
  "shared/reactor/QuoteDefaults.js:services/QuoteDefaults.js"
  "shared/reactor/QuoteDefaults.js:hancore.shibumi.reactor/QuoteDefaults.js"
  "shared/presentation/PillSurface.qml:widgets/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.memory/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.cpu/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.audio/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.media/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.workspaces/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.status/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.center/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.network/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.brightness/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.bluetooth/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.battery/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.power-profile/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.ai/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.quick-access/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.temperature/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.gpu/PillSurface.qml"
  "shared/presentation/PillSurface.qml:hancore.shibumi.storage/PillSurface.qml"
  "shared/presentation/PacmanWorkspaceMarker.qml:widgets/PacmanWorkspaceMarker.qml"
  "shared/presentation/PacmanWorkspaceMarker.qml:hancore.shibumi.workspaces/PacmanWorkspaceMarker.qml"
  "shared/presentation/PacmanWorkspaceMarker.qml:hancore.shibumi.control-center/PacmanWorkspaceMarker.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.memory/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.cpu/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.audio/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.media/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.workspaces/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.status/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.center/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.network/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.brightness/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.bluetooth/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.battery/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.power-profile/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.ai/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.quick-access/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.temperature/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.gpu/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.storage/HostTokens.qml"
  "shared/presentation/HostTokens.qml:hancore.shibumi.control-center/HostTokens.qml"
  "shared/presentation/ShibumiPanel.qml:widgets/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.control-center/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.update-center/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.memory/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.cpu/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.audio/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.media/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.workspaces/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.status/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.center/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.network/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.brightness/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.bluetooth/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.battery/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.power-profile/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.ai/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.temperature/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.gpu/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.storage/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanelToolTip.qml:widgets/ShibumiPanelToolTip.qml"
  "shared/presentation/ShibumiPanelToolTip.qml:hancore.shibumi.update-center/ShibumiPanelToolTip.qml"
  "shared/presentation/ShibumiPanelToolTip.qml:hancore.shibumi.status/ShibumiPanelToolTip.qml"
  "shared/presentation/ShibumiPanelToolTip.qml:hancore.shibumi.network/ShibumiPanelToolTip.qml"
  "shared/presentation/ShibumiPanelToolTip.qml:hancore.shibumi.brightness/ShibumiPanelToolTip.qml"
  "shared/presentation/ShibumiPanelToolTip.qml:hancore.shibumi.bluetooth/ShibumiPanelToolTip.qml"
  "shared/presentation/ShibumiPanelToolTip.qml:hancore.shibumi.workspaces/ShibumiPanelToolTip.qml"
  "shared/presentation/ShibumiButtonGroup.qml:widgets/ShibumiButtonGroup.qml"
  "shared/presentation/ShibumiButtonGroup.qml:hancore.shibumi.workspaces/ShibumiButtonGroup.qml"
  "shared/presentation/ShibumiSlider.qml:widgets/ShibumiSlider.qml"
  "shared/presentation/ShibumiSlider.qml:hancore.shibumi.audio/ShibumiSlider.qml"
  "shared/presentation/ShibumiSlider.qml:hancore.shibumi.brightness/ShibumiSlider.qml"
  "shared/presentation/IconText.qml:widgets/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.cpu/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.audio/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.media/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.status/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.center/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.network/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.brightness/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.bluetooth/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.power-profile/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.ai/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.quick-access/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.temperature/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.gpu/IconText.qml"
  "shared/presentation/IconText.qml:hancore.shibumi.storage/IconText.qml"
)

executable_mappings=(
  "shared/telemetry/shibumi-gpu-probe:scripts/shibumi-gpu-probe"
  "shared/telemetry/shibumi-gpu-probe:hancore.shibumi.cpu/scripts/shibumi-gpu-probe"
  "shared/quick-access/shibumi-picker:scripts/shibumi-picker"
  "shared/quick-access/shibumi-picker:hancore.shibumi.quick-access/scripts/shibumi-picker"
)

failed=0
for mapping in "${mappings[@]}"; do
  source_path=${mapping%%:*}
  target_path=${mapping#*:}
  source_file="$repo_root/$source_path"
  target_file="$repo_root/$target_path"

  [[ -f $source_file ]] || {
    printf 'Missing shared source: %s\n' "$source_path" >&2
    failed=1
    continue
  }

  if [[ $mode == --write ]]; then
    install -Dm0644 -- "$source_file" "$target_file"
  elif ! cmp -s -- "$source_file" "$target_file"; then
    printf 'Vendored file drift: %s -> %s\n' "$source_path" "$target_path" >&2
    failed=1
  fi
done

for mapping in "${executable_mappings[@]}"; do
  source_path=${mapping%%:*}
  target_path=${mapping#*:}
  source_file="$repo_root/$source_path"
  target_file="$repo_root/$target_path"

  [[ -f $source_file ]] || {
    printf 'Missing shared source: %s\n' "$source_path" >&2
    failed=1
    continue
  }

  if [[ $mode == --write ]]; then
    install -Dm0755 -- "$source_file" "$target_file"
  elif ! cmp -s -- "$source_file" "$target_file" || [[ ! -x $target_file ]]; then
    printf 'Vendored executable drift: %s -> %s\n' \
      "$source_path" "$target_path" >&2
    failed=1
  fi
done

(( failed == 0 )) || exit 1
printf 'Shibumi shared vendoring %s passed\n' "${mode#--}"
