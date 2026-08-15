#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

fail() {
  printf 'style contract regression failed: %s\n' "$*" >&2
  exit 1
}

command -v rg >/dev/null 2>&1 || fail "rg is required"

rg -Fq 'root.bar.layoutController.v2Mode !== true' \
  styles/shibumi/BarSurface.qml \
  || fail "V1 gap animations can still load in V2 shell styles"

rg -q 'property string requestedId: "shibumi"' styles/StyleRegistry.qml \
  || fail "style registry default is not shibumi"
rg -q 'readonly property var availableIds: .*"shibumi"' styles/StyleRegistry.qml \
  || fail "shibumi is not registered"
rg -q 'case "shibumi": return Qt\.resolvedUrl\("shibumi/Style\.qml"\)' styles/StyleRegistry.qml \
  || fail "shibumi source is not registered"

mapfile -t style_dirs < <(find styles -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ ${#style_dirs[@]} -gt 0 ]] || fail "no production style is present"

for style_id in "${style_dirs[@]}"; do
  style_dir="styles/$style_id"
  rg -q "\"${style_id}\"" styles/StyleRegistry.qml \
    || fail "$style_id is not listed in the style registry"
  rg -q "case \"${style_id}\":" styles/StyleRegistry.qml \
    || fail "$style_id has no registry source mapping"
  for required_file in Style.qml BarSurface.qml TooltipSurface.qml VisualTokens.qml; do
    [[ -f "$style_dir/$required_file" ]] \
      || fail "$style_id is missing $required_file"
  done

  rg -q 'readonly property int contractVersion: 1' "$style_dir/Style.qml" \
    || fail "$style_id does not implement style contract version 1"
  rg -q "readonly property string styleId: \"${style_id}\"" "$style_dir/Style.qml" \
    || fail "$style_id does not declare its directory id"
  rg -q 'property var layoutSession:' "$style_dir/BarSurface.qml" \
    || fail "$style_id bar surface does not accept per-output layout state"

  for property_name in \
    displayName sizeHorizontal sizeVertical tooltipGap colorTransitionDuration \
    fontFamily foreground barForeground background urgent \
    exclusiveSizeHorizontal visualTokens barSurfaceComponent tooltipSurfaceComponent; do
    rg -q "readonly property .* ${property_name}:" "$style_dir/Style.qml" \
      || fail "$style_id is missing contract property $property_name"
  done

  if rg -q '\b(PanelWindow|ShellRoot|Variants|Process)\b' \
    "$style_dir"/*.qml; then
    fail "$style_id owns runtime lifecycle instead of presentation"
  fi
done

rg -q 'import "styles" as Styles' Bar.qml \
  || fail "Bar.qml does not import the style registry"
rg -q '^  Styles\.StyleRegistry \{' Bar.qml \
  || fail "Bar.qml does not instantiate the style registry"
rg -q 'requestedStyleId = String\(config\.style \|\| "shibumi"\)' Bar.qml \
  || fail "bar.style is not read from host configuration"
rg -q '^  function setStyle\(value\)' Bar.qml \
  || fail "style selection cannot be persisted through the host facade"
for v1_ipc_contract in \
  'function addV1Slot(region: string): string' \
  'function removeV1Slot(region: string): string' \
  'function moveV1GroupToSlot(groupId: string, region: string,'; do
  rg -Fq "$v1_ipc_contract" Bar.qml \
    || fail "V1 slot runtime IPC drifted: $v1_ipc_contract"
done
rg -q 'activeStyle\.barSurfaceComponent' core/BarPanel.qml \
  || fail "bar surface is not delegated to the active style"
rg -q 'activeStyle\.tooltipSurfaceComponent' core/BarPanel.qml \
  || fail "tooltip surface is not delegated to the active style"
rg -q 'exclusiveZone: bar\.barExclusiveSize' core/BarPanel.qml \
  || fail "bar reserve size does not follow the active style contract"
for edit_contract in \
  'radius: root.bar.layoutController.v2Mode' \
  '? 0 : root.bar.visualTokens.islandRadius + Commons.Style.space(2)' \
  'SequentialAnimation on opacity' \
  'duration: 900'; do
  rg -Fq "$edit_contract" styles/shibumi/BarSurface.qml \
    || fail "edit-mode frame drifted from V1: $edit_contract"
done
for protection_contract in \
  'readonly property bool separatorChangesAllowed: editing || !layoutProtected' \
  'if (!separatorChangesAllowed) return false' \
  'enabled: root ? root.persistentSeparators || !root.v2Mode : false' \
  'hoverEnabled: root ? root.separatorChangesAllowed : false' \
  'readonly property int enabledSeparatorHitTargetCount:' \
  'bar.toggleGroupSeparator(String(groupId || ""), editing)' \
  'bar.layoutController.toggleSplit(region, Number(index), editing)'; do
  rg -Fq "$protection_contract" styles/shibumi/GroupSection.qml \
    || fail "within-region layout protection drifted: $protection_contract"
done
for stable_group_contract in \
  'ListModel { id: stableGroupModel }' \
  'function syncStableGroups()' \
  'stableGroupModel.insert(target, { groupId: groupId })' \
  'stableGroupModel.remove(index)' \
  'model: stableGroupModel'; do
  rg -Fq "$stable_group_contract" styles/shibumi/GroupSection.qml \
    || fail "dynamic groups can rebuild existing widget owners: $stable_group_contract"
done
if rg -Fq 'model: root.groups' styles/shibumi/GroupSection.qml; then
  fail "group repeater still destroys every widget owner on layout changes"
fi
rg -Fq 'onClicked: root.bar.toggleGroupSeparator(' \
  styles/shibumi/GroupSection.qml && \
  fail "separator click bypasses the V2 interaction guard"
rg -Uq 'onClicked: \{\n[[:space:]]*if \(root\) root\.toggleSeparator\(' \
  styles/shibumi/GroupSection.qml \
  || fail "within-region markers do not use the guarded interaction route"
for v1_edit_interaction_contract in \
  'return !v2Mode && bar.layoutController' \
  'function onSlotEditingChanged()' \
  'enabled: root ? !root.slotEditing : false'; do
  rg -Fq "$v1_edit_interaction_contract" styles/shibumi/GroupSection.qml \
    || fail "V1 edit interaction drifted: $v1_edit_interaction_contract"
done
rg -Fq 'return separated ? Math.max(0, splitGrow - groupSpacing)' \
  styles/shibumi/GroupSection.qml \
  || fail "active separators no longer follow the original V2 edge offset"
rg -Fq 'width: root && horizontalCell.placeholderSlot' \
  styles/shibumi/GroupSection.qml \
  || fail "edit placeholder does not use the presentation-specific slot size"
rg -Fq 'height: root.v2Shell' core/GroupSlot.qml \
  || fail "V2 widget fill is no longer constrained to the pill height"
rg -Fq 'decorated ? v2SurfaceHeight : 0' core/GroupSlot.qml \
  || fail "V2 fill height no longer follows the fixed 24px surface contract"
for group_activation_contract in \
  'void(stateConfig)' \
  'void(stateRevision)' \
  'stateService.groupEnabledForVariant(' \
  'groupId, v2Shell ? "v2" : "v1")'; do
  rg -Fq "$group_activation_contract" core/GroupSlot.qml \
    || fail "optional group activation is not reactive: $group_activation_contract"
done
rg -Fq 'markerCenter: item.x + item.separatorCenter' \
  styles/shibumi/GroupSection.qml \
  || fail "separator geometry is not derived from the live widget edge"
for slot_add_contract in \
  'readonly property bool canAddSlot: slotEditing' \
  'text: "+"' \
  'root.bar.layoutController.addV2Slot(root.region)' \
  'root.bar.layoutController.addV1Slot(root.region)'; do
  rg -Fq "$slot_add_contract" styles/shibumi/GroupSection.qml \
    || fail "inline add-slot affordance drifted: $slot_add_contract"
done
for v1_slot_contract in \
  'readonly property bool proxySlot: root' \
  'readonly property bool removableEmptySlot: root && emptySlot' \
  '? root.v2Mode ? targetVisual.height : 32 : 0' \
  'anchors.verticalCenter: parent.verticalCenter' \
  'root.bar.layoutController.removeV1SlotAt(' \
  'root.bar.layoutController.isExtraV1Slot(root.region, index)'; do
  rg -Fq "$v1_slot_contract" styles/shibumi/GroupSection.qml \
    || fail "V1 editable slot proxy drifted: $v1_slot_contract"
done
for boundary_protection_contract in \
  'readonly property bool layoutChangesAllowed:' \
  'if (!root.layoutChangesAllowed) return false' \
  'enabled: root.layoutChangesAllowed' \
  'root.layoutSession && root.layoutSession.editing'; do
  rg -Fq "$boundary_protection_contract" styles/shibumi/BarSurface.qml \
    || fail "boundary layout protection drifted: $boundary_protection_contract"
done
for v1_boundary_contract in \
  'visible: root.bar.layoutController.v2Mode !== true' \
  '&& boundaryMarker.splitOn ? "│" : "•"'; do
  rg -Fq "$v1_boundary_contract" styles/shibumi/BarSurface.qml \
    || fail "V1 boundary marker drifted: $v1_boundary_contract"
done
rg -Fq 'root.tokenColor("separator", root.bar.visualTokens.sumi)' \
  styles/shibumi/GroupSection.qml \
  || fail "widget separator color does not use the quiet V2 token"
rg -Fq '? root.bar.visualTokens.separator : root.bar.visualTokens.sumi' \
  styles/shibumi/BarSurface.qml \
  || fail "boundary separator color does not use the quiet V2 token"
rg -Fq 'visible: boundaryX > 0 && boundaryIndex >= 0' \
  styles/shibumi/BarSurface.qml \
  || fail "boundary split handles are incorrectly gated by edit mode"
rg -Fq 'visible: hasFollowingGroup' styles/shibumi/GroupSection.qml \
  || fail "within-region split handles are incorrectly gated by edit mode"
rg -Fq 'readonly property int groupGap: Commons.Style.space(6)' \
  styles/shibumi/VisualTokens.qml \
  || fail "unsplit group gaps drifted from the V1 6px contract"
for v2_geometry_contract in \
  'readonly property int barHeight: Commons.Style.space(v2Shell ? 33 : 35)' \
  'readonly property int exclusiveHeight: Commons.Style.space(v2Shell ? 36 : 38)' \
  'readonly property int shellFitRadius: Commons.Style.space(6)' \
  'readonly property int shellDockRadius: Commons.Style.space(8)' \
  'readonly property int panelRadius: v2Shell' \
  'Math.max(Commons.Style.space(80), naturalShellWidth)' \
  'height: horizontalSurface.shibumiShell'; do
  rg -Fq "$v2_geometry_contract" styles/shibumi \
    || fail "original V2 shell geometry drifted: $v2_geometry_contract"
done
for v2_shadow_contract in \
  'visible: root.shellStyle !== "shibumi" && root.shellStyle !== "notch"' \
  'offset: Qt.vector2d(0, root.atTop ? 2 : -2)' \
  '? root.bar.visualTokens.shellShadow : Qt.rgba(0, 0, 0, 0.46)'; do
  rg -Fq "$v2_shadow_contract" styles/shibumi/RunChrome.qml \
    || fail "original V2 shell shadow drifted: $v2_shadow_contract"
done
for v2_edge_contract in \
  'visible: (root.shellStyle === "full" || root.shellStyle === "fit")' \
  'id: fitOuterBorder' \
  'visible: root.shellStyle === "fit"' \
  'strokeWidth: root.bar.visualTokens.pillBorderWidth' \
  '&& (root.shellStyle === "dock" || root.shellStyle === "notch")' \
  '? bar.visualTokens.shellWingWidth : 0' \
  'readonly property real notchBodyRadius: shellStyle === "notch" ? 9 : 0' \
  'readonly property real notchShoulderInset: wing + notchBodyRadius' \
  'readonly property real notchConnectedCenterX: connectedPanelActive' \
  'readonly property real borderEdgeY: atTop ? height - 0.5 : 0.5' \
  'readonly property real desktopEdgeInset:' \
  '? notchShoulderInset' \
  'x: root.desktopEdgeInset' \
  'x: root.width - root.desktopEdgeInset' \
  'y: root.atTop ? root.height - 1 : 0' \
  ': Math.max(0, root.width - 2 * root.desktopEdgeInset)'; do
  rg -Fq "$v2_edge_contract" styles/shibumi/RunChrome.qml \
    || fail "V2 open-edge contour contract drifted: $v2_edge_contract"
done
for notch_single_path_contract in \
  'id: notchBorderPath' \
  'x: root.notchConnectedCenterX - root.connectedCurveHalfWidth' \
  'x: root.notchConnectedCenterX + root.connectedCurveHalfWidth' \
  'visible: root.connectedPanelActive && root.shellStyle !== "notch"'; do
  rg -Fq "$notch_single_path_contract" styles/shibumi/RunChrome.qml \
    || fail "Notch border is no longer one fused contour: $notch_single_path_contract"
done
if rg -q 'widgetPadding|appearancePadding' styles/shibumi/RunChrome.qml; then
  fail "Notch border geometry depends on per-widget spacing"
fi
if awk '
  /^  Rectangle \{/ { in_rectangle=1 }
  in_rectangle && /visible: root.shellStyle === "full"/ { found=1 }
  in_rectangle && /^  }/ { in_rectangle=0 }
  END { exit !found }
' styles/shibumi/RunChrome.qml; then
  fail "Full regained a closed Rectangle border"
fi
rg -Fq 'return groupSpacing + (separated ? splitGrow : 0)' \
  styles/shibumi/GroupSection.qml \
  || fail "split marker is not centered across the full V1 22px gap"
rg -Fq 'clip: false' styles/shibumi/GroupSection.qml \
  || fail "unsplit V1 markers are clipped outside their 6px cells"
awk '/id: separatorHitRepeater/{seen=1} seen && /hoverEnabled: true/{found=1; exit} END{exit !found}' \
  styles/shibumi/GroupSection.qml \
  || fail "within-region split handles cannot reveal their V1 hover marker"
for inactive_drag_contract in \
  'visible: enabled' \
  'hoverEnabled: enabled' \
  ': Qt.ArrowCursor'; do
  sed -n '/id: dragMouse/,/function windowPoint/p' \
    styles/shibumi/GroupSection.qml \
    | rg -Fq "$inactive_drag_contract" \
    || fail "inactive drag handles can own the cursor: $inactive_drag_contract"
done
rg -Fq 'radius: root ? root.bar.visualTokens.pillRadius : 0' \
  styles/shibumi/GroupSection.qml \
  || fail "drop targets do not follow the selected V1 radius"
rg -Fq '? tokenNumber("tileRadius", 8) : tokenNumber("pillRadius", 12)' \
  styles/shibumi/GroupSection.qml \
  || fail "V1 expandable slots do not follow Radius 12/Radius 6"
for v1_host_contract in \
  'property real horizontalHostHeight: 0' \
  'horizontalHostHeight: root.v2Shell ? 0 : root.v1SlotHeight'; do
  rg -Fq "$v1_host_contract" core/WidgetSlot.qml core/GroupSlot.qml \
    || fail "V1 widgets lost the original 28px host contract: $v1_host_contract"
done
for dynamic_v1_contract in \
  'readonly property bool dynamicV1Group:' \
  'readonly property bool dynamicV1WidgetOwnsSurface:' \
  'readonly property bool dynamicV1CustomFill:' \
  '"hancore.shibumi.temperature"' \
  '"hancore.shibumi.gpu"' \
  '"hancore.shibumi.storage"' \
  '|| (root.dynamicV1Group && !root.dynamicV1WidgetOwnsSurface)' \
  'root.bar.visualTokens.pillBorderWidth' \
  'readonly property bool dynamicShadowLoaded:' \
  'id: dynamicShadowLoader' \
  'active: root.dynamicV1Group && !root.dynamicV1WidgetOwnsSurface' \
  'sourceComponent: active ? dynamicV1Shadow : null' \
  'id: dynamicV1Shadow' \
  'RectangularShadow {' \
  'root.bar.visualTokens.shadowEnabled === true'; do
  rg -Fq "$dynamic_v1_contract" core/GroupSlot.qml \
    || fail "dynamic V1 plugins lost standard pill chrome: $dynamic_v1_contract"
done
for edit_surface_contract in \
  'implicitHeight: !bar.vertical && validScreen ? screen.height : 0' \
  'mask: Region {' \
  'onClicked: dragSession.setEditing(false)'; do
  rg -Fq "$edit_surface_contract" core/BarPanel.qml \
    || fail "stable V1 edit surface drifted: $edit_surface_contract"
done
rg -Fq 'readonly property real appearancePadding: v2Shell && bar.visualTokens' \
  core/GroupSlot.qml \
  || fail "V2 widget padding leaked into the original V1 group geometry"
rg -Fq '? tokenNumber("slotHeight", 28) : tokenNumber("pillHeight", 24)' \
  styles/shibumi/GroupSection.qml \
  || fail "V1 expandable slots do not use the 24px pill size"
for pill_contract in \
  'property var settings: ({})' \
  'property var tokenSource: null' \
  'property bool v1AppearanceEnabled: false' \
  'readonly property bool v1CustomFill:' \
  'readonly property bool customDecorated:' \
  'readonly property bool surfaceDisabled:' \
  'readonly property bool shellPillVisible: shellStyle === "shibumi"' \
  'readonly property int renderedSurfaceCount: shellPillVisible ? 1 : 0' \
  'readonly property int renderedShadowCount:' \
  'RectangularShadow {' \
  'blur: 8' \
  'root.bar && root.bar.position === "bottom" ? -1 : 1' \
  'visible: root.shellPillVisible'; do
  rg -Fq "$pill_contract" shared/presentation/PillSurface.qml \
    || fail "V1/V2 widget surface separation drifted: $pill_contract"
done
for v1_shadow_contract in \
    'visible: root.bar.visualTokens.shadowEnabled === true' \
    'offset: Qt.vector2d(0, root.atTop ? 1 : -1)' \
    'root.bar.visualTokens.pillShadow !== undefined' \
    'Qt.rgba(0, 0, 0, 0.55)'; do
  rg -Fq "$v1_shadow_contract" styles/shibumi/RunChrome.qml \
    || fail "V1 island shadow drifted: $v1_shadow_contract"
done
for tooltip_shadow_contract in \
    'visible: root.bar.visualTokens.shellStyle === "shibumi"' \
    '&& root.bar.visualTokens.shadowEnabled === true' \
    'anchors.fill: tooltipBubble'; do
  rg -Fq "$tooltip_shadow_contract" styles/shibumi/TooltipSurface.qml \
    || fail "V1 tooltip shadow drifted: $tooltip_shadow_contract"
done
for widget in ai audio battery bluetooth brightness center control-center cpu gpu \
    media memory network power-profile quick-access status storage temperature \
    workspaces; do
  rg -Fq 'HostTokens { id: hostTokens; bar: root.bar }' \
    "hancore.shibumi.$widget/BarWidget.qml" \
    || fail "$widget does not provide standard-host visual tokens"
  rg -Fq 'if (value === "round") return pillHeight / 2' \
    "hancore.shibumi.$widget/HostTokens.qml" \
    || fail "$widget host tokens do not preserve the V2 Round shape"
done
for shape_tokens in \
    styles/shibumi/VisualTokens.qml \
    hancore.shibumi.bar/styles/shibumi/VisualTokens.qml \
    shared/presentation/HostTokens.qml; do
  rg -Fq 'if (value === "round") return pillHeight / 2' "$shape_tokens" \
    || fail "V2 Round shape is not half the widget surface: $shape_tokens"
  rg -Fq 'if (!v2Shell) return widgetColorId(settings) !== "inherit"' \
    "$shape_tokens" \
    || fail "V1 fill can still be disabled by hidden V2 state: $shape_tokens"
done
for widget in ai audio battery bluetooth brightness center cpu gpu media \
    memory network power-profile quick-access status storage temperature \
    workspaces; do
  rg -Fq 'settings: root.settings' \
    "hancore.shibumi.$widget/BarWidget.qml" \
    || fail "$widget does not pass appearance state to its native pill"
  rg -Fq 'tokenSource: root.tokens' \
    "hancore.shibumi.$widget/BarWidget.qml" \
    || fail "$widget does not pass its resolved host tokens to its pill"
  rg -Fq 'v1AppearanceEnabled: true' \
    "hancore.shibumi.$widget/BarWidget.qml" \
    || fail "$widget does not opt into V1 fill appearance"
done
for launcher_contract in \
  'readonly property bool customDecorated:' \
  'readonly property bool surfaceDisabled:' \
  'readonly property bool nativePillSurfaceVisible:' \
  'readonly property bool v1CustomFill:' \
  'readonly property color renderedPillFillColor:'; do
  rg -Fq "$launcher_contract" \
    hancore.shibumi.control-center/BarWidget.qml \
    || fail "Control Center appearance surface drifted: $launcher_contract"
done

panel_tooltip=shared/presentation/ShibumiPanelToolTip.qml
[[ -f $panel_tooltip ]] || fail "shared panel tooltip is missing"
for tooltip_contract in \
  'delay: 320' \
  'panel.bar.background' \
  'tokens.panelBorder' \
  'tokens.panelBorderWidth' \
  'root.tokens.tooltipRadius' \
  'font.pixelSize: 12' \
  'font.letterSpacing: 1'; do
  rg -Fq "$tooltip_contract" "$panel_tooltip" \
    || fail "panel tooltip lost Shibumi styling: $tooltip_contract"
done

for tooltip_owner in \
  hancore.shibumi.network/NetworkPanel.qml \
  hancore.shibumi.brightness/BrightnessPanel.qml \
  hancore.shibumi.bluetooth/BluetoothPanel.qml \
  hancore.shibumi.status/TrayDrawerPanel.qml \
  hancore.shibumi.update-center/PanelButton.qml \
  hancore.shibumi.update-center/ThemesTab.qml; do
  rg -q 'ShibumiPanelToolTip \{' "$tooltip_owner" \
    || fail "$tooltip_owner bypasses the Shibumi panel tooltip"
done

for header_action_owner in \
  hancore.shibumi.ai/AiUsagePanel.qml \
  hancore.shibumi.battery/BatteryPanel.qml \
  hancore.shibumi.center/WeatherPanel.qml \
  hancore.shibumi.control-center/ControlCenterPanel.qml \
  hancore.shibumi.media/MediaPanel.qml \
  hancore.shibumi.power-profile/PowerProfilePanel.qml \
  hancore.shibumi.status/NotificationPanel.qml \
  hancore.shibumi.status/TrayDrawerPanel.qml \
  hancore.shibumi.status/TrayAppMenuPanel.qml \
  hancore.shibumi.update-center/UpdateCenterPanel.qml \
  hancore.shibumi.workspaces/WorkspacePanelContent.qml; do
  rg -q 'component IconAction: Ui\.CursorSurface' "$header_action_owner" \
    || fail "$header_action_owner bypasses NetworkPanel header chrome"
  rg -q 'implicitWidth: Commons\.Style\.space\(28\)' "$header_action_owner" \
    || fail "$header_action_owner lost the 28px header action width"
  rg -q 'implicitHeight: Commons\.Style\.space\(28\)' "$header_action_owner" \
    || fail "$header_action_owner lost the 28px header action height"
  rg -q 'ShibumiPanelToolTip \{' "$header_action_owner" \
    || fail "$header_action_owner lost its local header tooltip"
done

# These exact V1 panels deliberately use their original unframed text close
# affordance instead of the later NetworkPanel 28px icon-button chrome.
for v1_text_close_owner in \
  hancore.shibumi.audio/AudioPanel.qml \
  hancore.shibumi.cpu/CpuPanel.qml \
  hancore.shibumi.memory/MemoryPanel.qml; do
  rg -Fq 'text: "\u2715"' "$v1_text_close_owner" \
    || fail "$v1_text_close_owner lost the original V1 text close affordance"
  rg -q 'id: closeMouse' "$v1_text_close_owner" \
    || fail "$v1_text_close_owner V1 close affordance is not interactive"
done

for refresh_action_owner in \
  hancore.shibumi.ai/AiUsagePanel.qml \
  hancore.shibumi.bluetooth/BluetoothPanel.qml \
  hancore.shibumi.brightness/BrightnessPanel.qml \
  hancore.shibumi.network/NetworkPanel.qml \
  hancore.shibumi.update-center/UpdateCenterPanel.qml; do
  rg -q 'icon: .*"refresh"|\? "sync" : "refresh"' "$refresh_action_owner" \
    || fail "$refresh_action_owner lost the shared refresh/rescan icon contract"
done

for workspace_heading_contract in \
  'font.pixelSize: 13' \
  'font.letterSpacing: 2'; do
  rg -Fq "$workspace_heading_contract" \
    hancore.shibumi.workspaces/WorkspacePanelContent.qml \
    || fail "workspace heading drifted from V1: $workspace_heading_contract"
done

for unclipped_header in \
  hancore.shibumi.ai/AiUsagePanel.qml \
  hancore.shibumi.update-center/UpdateCenterPanel.qml; do
  awk '/id: header/{seen=1} seen && /height: Commons.Style.space\(28\)/{found=1; exit} END{exit !found}' \
    "$unclipped_header" \
    || fail "$unclipped_header header is shorter than its 28px actions"
done
for badge_toggle in packageBadgeToggle themeBadgeToggle; do
  awk -v id="$badge_toggle" '$0 ~ "id: " id {seen=1} seen && /controlHeight: Commons.Style.space\(22\)/{found=1; exit} END{exit !found}' \
    hancore.shibumi.update-center/UpdateCenterPanel.qml \
    || fail "Update Center $badge_toggle no longer matches the notification DND height"
done
for dnd_parity_contract in \
  'fontWeight: Font.Medium' \
  'idleTextColor: panel.controlMutedHigh' \
  'hoverTextColor: panel.controlMutedHigh' \
  'hoverBorderColor: panel.controlHoverBorderColor'; do
  [[ $(rg -F -c "$dnd_parity_contract" \
    hancore.shibumi.update-center/UpdateCenterPanel.qml) -eq 2 ]] \
    || fail "Update Center badge toggles drifted from DND styling: $dnd_parity_contract"
done

if rg -q 'Ui\.PanelToolTip' hancore.shibumi.* widgets; then
  fail "a Shibumi panel still uses the host tooltip appearance"
fi

panel_surface=shared/presentation/ShibumiPanel.qml
[[ -f $panel_surface ]] || fail "shared Shibumi panel surface is missing"
rg -Fq 'property int gap: shellStyle === "shibumi" ? 8 : 6' \
  "$panel_surface" \
  || fail "V1/V2 panel offset drifted from the reference 8px/6px contract"
if rg -n '^\s+gap: 8\s*$' hancore.shibumi.* -g '*Panel.qml' \
    --glob '!ShibumiPanel.qml'; then
  fail "a panel bypasses the variant-aware shared offset"
fi
rg -q '^PanelWindow \{' "$panel_surface" \
  || fail "Shibumi panel does not own its single visible surface"
if rg -q '^Ui\.KeyboardPanel|shibumiSurfaceBleed' "$panel_surface"; then
  fail "Shibumi panel still layers custom chrome over host panel chrome"
fi
[[ $(rg -c '^  Ui\.BorderSurface \{' "$panel_surface") -eq 1 ]] \
  || fail "Shibumi panel must render exactly one bordered surface"
[[ $(rg -c '^  RectangularShadow \{' "$panel_surface") -eq 1 ]] \
  || fail "Shibumi panel must render at most one matching shadow contour"
rg -Fq '&& root.shellStyle === "shibumi"' "$panel_surface" \
  || fail "V2 connected panels still cast a shadow into the bar notch"
run_chrome=styles/shibumi/RunChrome.qml
for negative_space_contract in \
  'readonly property real connectedCurveHalfWidth: 7 * connectedReveal' \
  'readonly property real connectedDepth: 5 * connectedReveal' \
  'x: root.connectedCenterX + root.connectedCurveHalfWidth' \
  'x: root.connectedCenterX - root.connectedCurveHalfWidth' \
  'root.connectedCenterX - 12 - x' \
  'root.connectedCenterX + 12' \
  'the fill itself owns the negative-space'; do
  rg -Fq "$negative_space_contract" "$run_chrome" \
    || fail "V2 connected bar cutout drifted: $negative_space_contract"
done
if awk '/V2.s connected popover contract:/{seen=1} seen && /color: root.bar.background/{found=1} END{exit !found}' \
    "$run_chrome"; then
  fail "V2 connected notch is painted with bar color instead of transparent"
fi
for panel_contract in \
  'readonly property int renderedSurfaceCount: 1' \
  'root.shibumiTokens.panelRadius' \
  'root.shibumiTokens.tileRadius' \
  'readonly property real anchorWindowH:' \
  'readonly property real barH: barPos === "top" || barPos === "bottom"' \
  'Math.max(0, root.screenH - root.anchorWindowH)' \
  'surfaceRadiusOverride >= 0' \
  'root.shibumiTokens.panelRadius'; do
  rg -Fq "$panel_contract" "$panel_surface" \
    || fail "Shibumi panel lost dynamic radius contract: $panel_contract"
done

for adapter in ShibumiButtonGroup ShibumiDropdown ShibumiTextField; do
  adapter_file="shared/presentation/${adapter}.qml"
  [[ -f $adapter_file ]] || fail "missing dynamic-radius adapter: $adapter"
  rg -q 'property real controlRadius:' "$adapter_file" \
    || fail "$adapter does not expose the shared control radius"
  rg -q 'radius: root\.controlRadius' "$adapter_file" \
    || fail "$adapter does not render with the shared control radius"
done

for radius_owner in \
  hancore.shibumi.control-center/CompactSettingChoice.qml \
  hancore.shibumi.ai/AiUsagePanel.qml \
  hancore.shibumi.audio/AudioPanel.qml \
  hancore.shibumi.battery/BatteryPanel.qml \
  hancore.shibumi.bluetooth/BluetoothPanel.qml \
  hancore.shibumi.brightness/BrightnessPanel.qml \
  hancore.shibumi.center/CalendarPanel.qml \
  hancore.shibumi.center/WeatherPanel.qml \
  hancore.shibumi.cpu/CpuPanel.qml \
  hancore.shibumi.media/MediaPanel.qml \
  hancore.shibumi.memory/MemoryPanel.qml \
  hancore.shibumi.network/NetworkPanel.qml \
  hancore.shibumi.power-profile/PowerProfilePanel.qml \
  hancore.shibumi.status/NotificationPanel.qml \
  hancore.shibumi.status/TrayAppMenuPanel.qml \
  hancore.shibumi.status/TrayDrawerPanel.qml \
  hancore.shibumi.update-center/UpdateCenterPanel.qml \
  hancore.shibumi.workspaces/WorkspacePanelContent.qml; do
  rg -q 'radius: (panel|controller|root\.controller)\.controlRadius' \
    "$radius_owner" \
    || fail "$radius_owner bypasses the dynamic Shibumi control radius"
done

for workspace_color_contract in \
  'root.controller.controlFillColor' \
  'root.controller.controlHoverFillColor' \
  'root.controller.controlActiveFillColor' \
  'root.controller.controlBorderColor' \
  'root.controller.controlAccent'; do
  rg -Fq "$workspace_color_contract" \
    hancore.shibumi.workspaces/WorkspacePanelContent.qml \
    || fail "workspace panel drifted from V1 control colors: $workspace_color_contract"
done

[[ $(rg -Fc 'font.pixelSize: 14' hancore.shibumi.bluetooth/BarWidget.qml) -eq 2 ]] \
  || fail "Bluetooth icon sizing drifted from V1"
rg -Fq 'readonly property int iconSlotSize: tokens.v2Shell === true' \
  hancore.shibumi.bluetooth/BarWidget.qml \
  || fail "Bluetooth icon lost its stable optical slot"
rg -Fq '&& tokens.v2Shell !== true && displayMode === "full" ? 2 : 0' \
  hancore.shibumi.bluetooth/BarWidget.qml \
  || fail "Bluetooth lost its V1 optical alignment offset"
[[ $(rg -Fc 'font.pixelSize: root.mode === "none" ? 15 : 14' \
  hancore.shibumi.network/BarWidget.qml) -eq 2 ]] \
  || fail "compact/vertical network icon sizing drifted"
rg -Fq 'font.pixelSize: root.mode === "ethernet" ? 14 : 15' \
  hancore.shibumi.network/BarWidget.qml \
  || fail "V2 LAN icon sizing drifted from the reference"
rg -Fq 'width: visible ? 36 : 0' hancore.shibumi.network/BarWidget.qml \
  || fail "V1 network graph width drifted from the reference"
[[ $(rg -Fc 'width: 54' hancore.shibumi.network/BarWidget.qml) -eq 2 ]] \
  || fail "V1 stacked network rates drifted from the reference"
rg -Fq 'component V2TrafficMeter: Item' hancore.shibumi.network/BarWidget.qml \
  || fail "V2 RX/TX meter is missing"
rg -Fq 'width: visible ? 16 : 0' hancore.shibumi.network/BarWidget.qml \
  || fail "V2 RX/TX geometry drifted from the reference"
for power_glyph in '\uF06C' '\uF0E7' '\uF24E'; do
  rg -Fq "$power_glyph" hancore.shibumi.power-profile/BarWidget.qml \
    || fail "power-profile icon drifted from V1: $power_glyph"
done
rg -Fq 'font.pixelSize: root.profile === "balanced" ? 13 : 14' \
  hancore.shibumi.power-profile/BarWidget.qml \
  || fail "power-profile icon sizing drifted from V1"
for tinted_image_contract in \
  'readonly property color opaqueTint: Qt.rgba(' \
  'tint.r, tint.g, tint.b, 1)' \
  'opacity: root.tint.a' \
  'colorization: 1' \
  'colorizationColor: root.opaqueTint'; do
  rg -Fq "$tinted_image_contract" hancore.shibumi.ai/TintedImage.qml \
    || fail "AI tint opacity contract drifted: $tinted_image_contract"
done
if rg -Fq 'colorizationColor: root.tint' \
    hancore.shibumi.ai/TintedImage.qml; then
  fail "AI tint alpha is used as colorization strength instead of opacity"
fi
for ai_contract in \
  'readonly property int providerIconSlotWidth: 20' \
  'readonly property int providerIconSlotHeight: 16' \
  'readonly property int claudeGlyphPixelSize: 15' \
  'width: root.providerIconSlotWidth' \
  'height: root.providerIconSlotHeight' \
  'width: root.providerGlyphWidth' \
  'height: root.providerGlyphHeight' \
  'readonly property int providerContentHorizontalOffset:' \
  'providerId === "codex" && displayMode !== "text" ? -1 : 0' \
  'anchors.horizontalCenterOffset: root.providerContentHorizontalOffset' \
  'anchors.horizontalCenterOffset: root.providerGlyphHorizontalOffset' \
  '? Qt.size(20, 12) : Qt.size(56, 56)' \
  'readonly property color baseIconColor: customFillActive' \
  'readonly property color usageIconColor: widgetInk' \
  'readonly property bool customFillActive:' \
  'readonly property real baseIconOpacity:' \
  'readonly property bool claudeLayersAligned:' \
  'color: Qt.rgba(root.baseIconColor.r,' \
  'color: root.usageIconColor' \
  'font.pixelSize: root.claudeGlyphPixelSize' \
  'x: claudeGlyphBase.x' \
  'y: claudeGlyphBase.y - claudeUsageClip.y' \
  'width: claudeGlyphBase.width' \
  'height: claudeGlyphBase.height' \
  'tint: Qt.rgba(root.baseIconColor.r,' \
  'root.baseIconOpacity)' \
  'tint: root.usageIconColor' \
  'color: root.widgetInk' \
  'font.pixelSize: root.tokens.labelSize'; do
  rg -Fq "$ai_contract" hancore.shibumi.ai/BarWidget.qml \
    || fail "AI icon contract drifted from V1: $ai_contract"
done
[[ $(rg -Fc 'font.pixelSize: root.claudeGlyphPixelSize' \
  hancore.shibumi.ai/BarWidget.qml) -eq 2 ]] \
  || fail "Claude base/fill layers do not share the 15px glyph size"
if rg -Fq 'tint: root.widgetInk' hancore.shibumi.ai/BarWidget.qml \
    || rg -Uq 'text: "\\udb85\\ude7a"\n[[:space:]]+color: (Qt\.rgba\(root\.widgetInk|root\.widgetInk)' \
      hancore.shibumi.ai/BarWidget.qml; then
  fail "AI base/fill layers collapsed back to the old color source"
fi
rg -Fq 'font.pixelSize: 15' hancore.shibumi.status/NotificationStatusView.qml \
  || fail "notification icon sizing drifted from V1"
rg -Fq 'font.pixelSize: 16' hancore.shibumi.status/TrayStatusView.qml \
  || fail "tray drawer icon sizing drifted from V1"
rg -Fq 'font.pixelSize: 15' hancore.shibumi.center/SystemUpdateWidget.qml \
  || fail "Omarchy update icon sizing drifted from V1"
rg -Fq 'font.pixelSize: 14' hancore.shibumi.quick-access/BarWidget.qml \
  || fail "picker icon sizing drifted from V1"
rg -Fq 'font.pixelSize: 13' hancore.shibumi.media/BarWidget.qml \
  || fail "media control icon sizing drifted from V1"
rg -Fq 'Commons.Util.alpha(root.widgetInk, 0.5)' \
  hancore.shibumi.center/BarWidget.qml \
  || fail "center date no longer follows the half-opacity content tone"

# The four V2 shells use the original V2 module language: symbol plus value,
# without the V1 acronym prefixes. Shibumi itself keeps those V1 labels.
for widget in memory cpu network; do
  rg -Fq 'root.tokens.v2Shell !== true' \
    "hancore.shibumi.$widget/BarWidget.qml" \
    || fail "$widget does not preserve V1 labels only for the Shibumi shell"
done
for widget in audio battery brightness power-profile bluetooth; do
  rg -Fq 'root.tokens.v2Shell === true && root.displayMode === "full"' \
    "hancore.shibumi.$widget/BarWidget.qml" \
    || fail "$widget does not switch Full mode to its V2 presentation"
done
rg -Fq 'text: "󰋊"' hancore.shibumi.storage/BarWidget.qml \
  || fail "storage bar icon drifted from the original V2 glyph"
rg -Fq 'readonly property int iconSlotSize: 14' \
  hancore.shibumi.storage/BarWidget.qml \
  || fail "storage icon lost its stable optical slot"
if rg -Fq 'text: "HDD "' hancore.shibumi.storage/BarWidget.qml; then
  fail "storage bar restored the obsolete HDD prefix"
fi
rg -Fq 'GpuCardIcon {' \
  hancore.shibumi.gpu/BarWidget.qml \
  || fail "GPU bar icon is not rendered by its native QML component"
[[ -f hancore.shibumi.gpu/GpuCardIcon.qml ]] \
  || fail "GPU plugin is missing its native QML icon"
for gpu_icon_contract in \
  'implicitWidth: 20' \
  'implicitHeight: 14' \
  'radius: 1.5' \
  'radius: 2.5' \
  'border.width: 1' \
  'color: root.color'; do
  rg -Fq "$gpu_icon_contract" hancore.shibumi.gpu/GpuCardIcon.qml \
    || fail "GPU bar icon lost its rounded native geometry: $gpu_icon_contract"
done
if rg -q 'MultiEffect|sourceSize:|mipmap:|smooth:' \
    hancore.shibumi.gpu/BarWidget.qml; then
  fail "GPU bar icon reintroduced a filtered rendering stage"
fi
if rg -Fq 'text: "GPU "' hancore.shibumi.gpu/BarWidget.qml; then
  fail "GPU bar restored the obsolete GPU prefix"
fi
rg -Fq 'text: ""' hancore.shibumi.temperature/BarWidget.qml \
  || fail "temperature bar icon drifted from the shared Nerd Font glyph"
if rg -q 'device_thermostat|v1TemperatureIcon|v2TemperatureIcon' \
    hancore.shibumi.temperature/BarWidget.qml; then
  fail "temperature still switches icon families between V1 and V2"
fi
rg -Fq 'font.family: root.bar' hancore.shibumi.temperature/BarWidget.qml \
  || fail "temperature icon does not use the configured Nerd Font"
rg -Fq 'readonly property int iconSlotSize: 14' \
  hancore.shibumi.temperature/BarWidget.qml \
  || fail "temperature icon lost its stable optical slot"
rg -Fq 'anchors.horizontalCenterOffset: root.iconGlyphHorizontalOffset' \
  hancore.shibumi.temperature/BarWidget.qml \
  || fail "temperature glyph lost its optical slot offset"
rg -Fq 'tokens.v2Shell === true ? 2 : 3' \
  hancore.shibumi.temperature/BarWidget.qml \
  || fail "temperature glyph lost its V1/V2 trailing-edge alignment"
rg -Fq '&& tokens.v2Shell !== true ? -1 : 0' \
  hancore.shibumi.temperature/BarWidget.qml \
  || fail "temperature lost its V1 optical alignment offset"
rg -Fq 'if ("hostGroupId" in target) target.hostGroupId = region' \
  hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "dynamic V1 widgets do not receive their persisted group identity"

# Quattro owns the canonical foundational palette. Shibumi keeps its V1
# semantic names internally and reads the seven terminal swatches that the
# public Commons palette does not expose.
for palette_contract in \
  'readonly property color paper: Commons.Color.background' \
  'readonly property color ink: Commons.Color.foreground' \
  'readonly property color sumi: Commons.Color.muted'; do
  rg -Fq "$palette_contract" styles/shibumi/VisualTokens.qml \
    || fail "Shibumi bypasses the canonical Quattro palette: $palette_contract"
done
for widget_outline_contract in \
  'function widgetBorderColorId(settings)' \
  'settings.widgetBorderColor !== undefined' \
  'function widgetBorderWidth(settings)' \
  'return Math.round(bounded * 2) / 2' \
  'function widgetBorderColor(settings)' \
  'if (!widgetHasBorder(settings)) return "transparent"' \
  'settings.widgetBorderUsesSurfaceColor === true' \
  'return id !== "inherit" && stateService' \
  '? stateService.paletteColor(id) : panelBorder'; do
  rg -Fq "$widget_outline_contract" styles/shibumi/VisualTokens.qml \
    || fail "widget outline no longer consumes its selected palette color: $widget_outline_contract"
  rg -Fq "$widget_outline_contract" shared/presentation/HostTokens.qml \
    || fail "host-neutral widget outline color drifted: $widget_outline_contract"
done
for extra_swatch_contract in \
  'color01: values.color1 || values.red || ""' \
  'color02: values.color2 || values.green || ""' \
  'color03: values.color3 || values.yellow || ""' \
  'color04: values.color4 || values.blue || ""' \
  'color05: values.color5 || values.magenta || ""' \
  'color06: values.color6 || values.cyan || ""' \
  'color07: values.color7 || values.bright_fg || values.light_fg || ""' \
  'color08: values.color8 || values.bright_black || ""'; do
  rg -Fq "$extra_swatch_contract" shared/state/ThemePaletteModel.js \
    || fail "V1 palette swatch mapping drifted: $extra_swatch_contract"
done
if rg -q 'values\.(bg|fg|dark_bg|darker_bg|lighter_bg|dark_fg)\b' \
  shared/state/ThemePaletteModel.js; then
  fail "Shibumi restored removed Quattro bg/fg palette aliases"
fi
for remove_theme_contract in \
  'iconText: "\ue872"' \
  'materialIcon: true' \
  'fontSize: 12'; do
  rg -Fq "$remove_theme_contract" hancore.shibumi.update-center/ThemesTab.qml \
    || fail "remove-theme icon drifted from V1: $remove_theme_contract"
done

printf 'Shibumi style contract regression passed\n'
