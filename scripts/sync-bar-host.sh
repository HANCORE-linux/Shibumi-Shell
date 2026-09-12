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
  core/DragGhostVisual.qml
  core/DragSession.qml
  core/EditBackdropPanel.qml
  core/GroupRegistry.js
  core/GroupSlot.qml
  core/LayoutController.qml
  core/LayoutTransition.qml
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

# Canonical Bar.qml is at the repository root, the deployed entry point one
# level below it. Normalize only this exact declared shared-module import.
rendered_bar=$(mktemp)
trap 'rm -f -- "$rendered_bar"' EXIT
failed=0
for path in "${files[@]}"; do
  source_file="$repo_root/$path"
  target_file="$target_root/$path"
  if [[ ! -f $source_file ]]; then
    printf 'Missing bar host source: %s\n' "$path" >&2
    failed=1
    continue
  fi

  if [[ $path == Bar.qml ]]; then
    expected_import='import "hancore.shibumi.state/runtime" as SuiteRuntime'
    if [[ $(grep -Fxc -- "$expected_import" "$source_file") != 1 ]]; then
      printf 'Unexpected shared runtime import in canonical Bar.qml\n' >&2
      failed=1
      continue
    fi
    sed 's@^import "hancore.shibumi.state/runtime" as SuiteRuntime$@import "../hancore.shibumi.state/runtime" as SuiteRuntime@' \
      "$source_file" > "$rendered_bar"
    source_file=$rendered_bar
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
