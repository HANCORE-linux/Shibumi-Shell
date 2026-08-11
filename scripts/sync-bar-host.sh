#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:---check}
target_root="$repo_root/hancore.shibumi.bar"

case "$mode" in
  --check | --write) ;;
  *)
    printf 'Usage: %s [--check|--write]\n' "$0" >&2
    exit 2
    ;;
esac

files=(
  Bar.qml
  core/BarPanel.qml
  core/BarSection.qml
  core/CenterSection.qml
  core/DragGhostPanel.qml
  core/DragSession.qml
  core/EditBackdropPanel.qml
  core/GroupRegistry.js
  core/GroupSlot.qml
  core/LayoutController.qml
  core/LayoutModel.js
  core/V2LayoutModel.js
  core/PanelRouting.js
  core/WidgetFamilies.js
  core/ResponsiveLayout.js
  core/RunGeometry.js
  core/HostedPanelConnector.qml
  core/WidgetSlot.qml
  core/WindowRecovery.qml
  services/HostWidgetResolver.qml
  styles/StyleRegistry.qml
  styles/shibumi/BarSurface.qml
  styles/shibumi/DragGhost.qml
  styles/shibumi/GapEffectsLayer.qml
  styles/shibumi/GroupSection.qml
  styles/shibumi/ReactorEventLayer.qml
  styles/shibumi/RunChrome.qml
  styles/shibumi/Style.qml
  styles/shibumi/TooltipSurface.qml
  styles/shibumi/VisualTokens.qml
)

failed=0
for path in "${files[@]}"; do
  source_file="$repo_root/$path"
  target_file="$target_root/$path"
  if [[ ! -f $source_file ]]; then
    printf 'Missing bar host source: %s\n' "$path" >&2
    failed=1
    continue
  fi

  if [[ $mode == --write ]]; then
    install -Dm0644 -- "$source_file" "$target_file"
  elif ! cmp -s -- "$source_file" "$target_file"; then
    printf 'Vendored bar host drift: %s\n' "$path" >&2
    failed=1
  fi
done

(( failed == 0 )) || exit 1
printf 'Shibumi bar host vendoring %s passed\n' "${mode#--}"
