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
rg -Fq 'enabled: root.persistentSeparators' styles/shibumi/GroupSection.qml \
  || fail "within-region separators are not clickable in locked V2 mode"
rg -Fq 'onClicked: root.bar.toggleGroupSeparator(' \
  styles/shibumi/GroupSection.qml && \
  fail "separator click bypasses the V2 interaction guard"
rg -Fq 'onClicked: root.toggleSeparator(horizontalCell.modelData)' \
  styles/shibumi/GroupSection.qml \
  || fail "within-region markers do not use the locked V2 interaction route"
rg -Fq 'return separated ? Math.max(0, splitGrow - groupSpacing)' \
  styles/shibumi/GroupSection.qml \
  || fail "active separators no longer follow the original V2 edge offset"
rg -Fq 'width: horizontalCell.emptySlot ? 28 : 0' \
  styles/shibumi/GroupSection.qml \
  || fail "V2 empty slot is not the original 28px square"
rg -Fq 'height: root.v2Shell' core/GroupSlot.qml \
  || fail "V2 widget fill is no longer constrained to the pill height"
rg -Fq 'decorated ? v2SurfaceHeight : 0' core/GroupSlot.qml \
  || fail "V2 fill height no longer follows the fixed 24px surface contract"
rg -Fq 'markerCenter: item.x + item.separatorCenter' \
  styles/shibumi/GroupSection.qml \
  || fail "separator geometry is not derived from the live widget edge"
for slot_add_contract in \
  'readonly property bool canAddV2Slot: v2Editing' \
  'text: "+"' \
  'onClicked: root.bar.layoutController.addV2Slot(root.region)'; do
  rg -Fq "$slot_add_contract" styles/shibumi/GroupSection.qml \
    || fail "V2 inline add-slot affordance drifted: $slot_add_contract"
done
rg -Fq 'enabled: root.bar.layoutController.v2Mode' \
  styles/shibumi/BarSurface.qml \
  || fail "boundary separators are not clickable in locked V2 mode"
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
  'visible: root.shellStyle === "full"' \
  'visible: root.shellStyle === "fit"' \
  'border.width: root.bar.visualTokens.pillBorderWidth' \
  '&& (root.shellStyle === "dock" || root.shellStyle === "notch")' \
  'readonly property real desktopEdgeInset:' \
  'y: root.atTop ? root.height - 1 : 0' \
  'width: Math.max(0, root.width - 2 * root.desktopEdgeInset)'; do
  rg -Fq "$v2_edge_contract" styles/shibumi/RunChrome.qml \
    || fail "V2 open-edge contour contract drifted: $v2_edge_contract"
done
full_block=$(sed -n '/visible: root.shellStyle === "full"/,/^  }/p' \
  styles/shibumi/RunChrome.qml)
if grep -Fq 'border.width:' <<<"$full_block"; then
  fail "Full regained a closed Rectangle border"
fi
rg -Fq 'return groupSpacing + (separated ? splitGrow : 0)' \
  styles/shibumi/GroupSection.qml \
  || fail "split marker is not centered across the full V1 22px gap"
rg -Fq 'clip: false' styles/shibumi/GroupSection.qml \
  || fail "unsplit V1 markers are clipped outside their 6px cells"
awk '/id: splitMouse/{seen=1} seen && /hoverEnabled: true/{found=1; exit} END{exit !found}' \
  styles/shibumi/GroupSection.qml \
  || fail "within-region split handles cannot reveal their V1 hover marker"
rg -Fq 'radius: root.bar.visualTokens.pillRadius' \
  styles/shibumi/GroupSection.qml \
  || fail "drop targets do not follow the selected V1 radius"
for pill_contract in \
  'property var settings: ({})' \
  'readonly property bool customDecorated:' \
  'readonly property bool surfaceDisabled:' \
  'readonly property bool shellPillVisible: shellStyle === "shibumi"' \
  'readonly property int renderedSurfaceCount: shellPillVisible ? 1 : 0' \
  'visible: root.shellPillVisible'; do
  rg -Fq "$pill_contract" shared/presentation/PillSurface.qml \
    || fail "V1/V2 widget surface separation drifted: $pill_contract"
done
for widget in ai audio battery bluetooth brightness center cpu gpu media \
    memory network power-profile quick-access status storage temperature \
    workspaces; do
  rg -Fq 'settings: root.settings' \
    "hancore.shibumi.$widget/BarWidget.qml" \
    || fail "$widget does not pass appearance state to its native pill"
done
for launcher_contract in \
  'readonly property bool customDecorated:' \
  'readonly property bool surfaceDisabled:' \
  'readonly property bool nativePillSurfaceVisible:'; do
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
rg -Fq 'font.pixelSize: root.mode === "none" ? 15 : 14' \
  hancore.shibumi.network/BarWidget.qml \
  || fail "full network icon sizing drifted from V1"
[[ $(rg -Fc 'font.pixelSize: root.mode === "none" ? 15 : 14' \
  hancore.shibumi.network/BarWidget.qml) -eq 3 ]] \
  || fail "network icon sizing drifted across appearance modes"
for power_glyph in '\uF06C' '\uF0E7' '\uF24E'; do
  rg -Fq "$power_glyph" hancore.shibumi.power-profile/BarWidget.qml \
    || fail "power-profile icon drifted from V1: $power_glyph"
done
rg -Fq 'font.pixelSize: root.profile === "balanced" ? 13 : 14' \
  hancore.shibumi.power-profile/BarWidget.qml \
  || fail "power-profile icon sizing drifted from V1"
for ai_contract in \
  'width: root.providerId === "opencode" ? 20' \
  'height: root.providerId === "opencode" ? 12' \
  '? Qt.size(20, 12) : Qt.size(56, 56)' \
  'root.providerId === "codex" ? 0.65 : 0.5'; do
  rg -Fq "$ai_contract" hancore.shibumi.ai/BarWidget.qml \
    || fail "AI icon contract drifted from V1: $ai_contract"
done
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
rg -Fq 'Commons.Util.alpha(root.tokens.ink, 0.5)' \
  hancore.shibumi.center/BarWidget.qml \
  || fail "center date color drifted from the V1 half-opacity foreground"

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
if rg -Fq 'text: "HDD "' hancore.shibumi.storage/BarWidget.qml; then
  fail "storage bar restored the obsolete HDD prefix"
fi
rg -Fq 'source: Qt.resolvedUrl("gpu-card.svg")' \
  hancore.shibumi.gpu/BarWidget.qml \
  || fail "GPU bar icon drifted from the original V2 card"
[[ -f hancore.shibumi.gpu/gpu-card.svg ]] \
  || fail "GPU plugin is missing its self-contained V2 card asset"
if rg -Fq 'text: "GPU "' hancore.shibumi.gpu/BarWidget.qml; then
  fail "GPU bar restored the obsolete GPU prefix"
fi
rg -Fq 'text: ""' hancore.shibumi.temperature/BarWidget.qml \
  || fail "temperature bar icon drifted from the original V2 glyph"

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
