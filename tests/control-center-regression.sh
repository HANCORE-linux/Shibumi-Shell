#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/home/hancore/Projects/omarchy-updates-pr}
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-control-center.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'control center regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

cp -a -- "$repo_root/hancore.shibumi.state" "$tmpdir/state"
cp -a -- "$repo_root/hancore.shibumi.control-center" "$tmpdir/control"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -Dm0644 "$repo_root/tests/control-center-smoke.qml" "$tmpdir/shell.qml"
install -Dm0644 "$repo_root/tests/fixtures/ControlCenterTestPanel.qml" \
  "$tmpdir/fixtures/ControlCenterTestPanel.qml"
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
grep -F 'control center smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

control_dir=$repo_root/hancore.shibumi.control-center

rg -q 'contentWidth: fittedContentWidth\(Commons\.Style\.space\(820\)' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "control card does not use the compact control-center workspace"
rg -q 'readonly property string barPosition:' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "panel does not expose the bar-position facade"
rg -q 'root\.toggle\(\)' "$control_dir/BarWidget.qml" \
  || fail "G1 does not use its native panel lifecycle"
rg -Fq 'text: "SHIBUMI"' "$control_dir/BarWidget.qml" \
  || fail "G1 does not render the Shibumi wordmark"
rg -Fq 'HostIdentity.isStockOmarchyHost(bar)' "$control_dir/BarWidget.qml" \
  || fail "G1 does not resolve the active host through Quattro shell state"
rg -Fq 'HostIdentity.shellName(bar)' "$control_dir/ControlCenterPanel.qml" \
  || fail "Bars page does not resolve the active host through Quattro shell state"
rg -Fq 'text: "shibumi"' "$repo_root/hancore.shibumi.state/ShibumiConfig.js" \
  || fail "G1 does not default to the Shibumi identity"

if rg -q 'hancore\.shibumi\.menu|hostShell\.toggle|shell\.mutateShellConfig' \
    "$control_dir" --glob '*.qml'; then
  fail "control center still owns or invokes the App Menu"
fi

for contract in \
  'ControlMainPage.qml:MAINTENANCE' \
  'ControlMainPage.qml:SESSION' \
  'ControlMainPage.qml:SHORTCUTS' \
  'SplitSettingsPage.qml:SPLIT & MERGE' \
  'SplitSettingsPage.qml:GAP ANIMATION' \
  'BarFunctionsPage.qml:BAR SHELL' \
  'BarFunctionsPage.qml:SURFACE' \
  'BarFunctionsPage.qml:BAR COLOR' \
  'BarFunctionsPage.qml:WIDGET APPEARANCE' \
  'BarFunctionsPage.qml:WORKSPACES' \
  'BarFunctionsPage.qml:LOGO' \
  'BarFunctionsPage.qml:PICKER STYLE'; do
  file=${contract%%:*}
  section=${contract#*:}
  rg -Fq "text: \"$section\"" "$control_dir/$file" \
    || fail "missing control-center section: $section"
done

for shell_style in full fit dock notch; do
  rg -Fq "{ value: \"$shell_style\"" \
    "$control_dir/BarFunctionsPage.qml" \
    || fail "missing V2 bar shell style: $shell_style"
done
rg -Fq 'name === "shellStyle"' \
  "$repo_root/hancore.shibumi.state/Service.qml" \
  || fail "bar shell style is not persisted by the state service"
rg -Fq 'restoreBar.scheduleWidgetRestore(' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "shell-style changes do not preserve the open Control Center page"
if rg -q 'centerOnBar:[[:space:]]*true' \
    "$control_dir/ControlCenterPanel.qml"; then
  fail "Control Center is centered instead of anchored to its launcher widget"
fi
rg -Fq 'typeof bar.setBarWidgetInstalled' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "Add widget does not mutate the Quattro bar layout"
rg -Fq 'AVAILABLE WIDGETS' "$control_dir/ControlSettings.qml" \
  || fail "widget picker does not expose the available widget catalog"

for page in main bars plugins splits functions preferences; do
  rg -Fq "\"$page\"" "$control_dir/ControlSettings.qml" \
    || fail "missing control-center page: $page"
done

for contract in \
  'ControlOverviewPage.qml:control center' \
  'PluginCatalogPage.qml:browse widgets' \
  'ControlSettings.qml:Add widget' \
  'ControlSettings.qml:Install plugin from Git' \
  'ControlSettings.qml:Plugins run as unsandboxed code'; do
  file=${contract%%:*}
  label=${contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "missing V4 control-center contract: $label"
done

rg -Fq '"omarchy", "plugin", "add", installUrl.trim(), "--yes"' \
  "$control_dir/ControlSettings.qml" \
  || fail "Git plugin installation does not use Quattro's plugin contract"
rg -Fq 'typeof pluginRegistry.setEnabled' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "plugin activation does not use PluginRegistry"
rg -Fq 'if (kinds.indexOf("bar") >= 0) continue' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "full bars leak into the widget/plugin catalog"
rg -Fq 'Control Center rejected full-bar toggle:' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "controller does not reject full-bar mutations defensively"
for icon in radio_button_checked align_vertical_center widgets brush \
    view_week settings download; do
  rg -Fq "\"$icon\"" "$control_dir/ControlSettings.qml" \
    || fail "missing Material Symbol in V4 navigation: $icon"
done
rg -Fq 'IconText {' "$control_dir/PluginCatalogPage.qml" \
  || fail "plugin catalog does not use the shared Material Symbol renderer"
rg -Fq 'font.pixelSize: Commons.Style.font.subtitle * root.uiScale' \
  "$control_dir/ControlSettings.qml" \
  || fail "V4 navigation labels are not balanced against the 18px icons"
rg -Fq 'fill: 0' "$control_dir/ControlSettings.qml" \
  || fail "V4 navigation icons change shape between active and idle states"

for contract in \
  'BarsPage.qml:SHELL CONTINUITY' \
  'BarsPage.qml:SNAPSHOT' \
  'BarsPage.qml:APPLY' \
  'BarsPage.qml:VERIFY' \
  'BarsPage.qml:USER EXTRAS' \
  'BarsPage.qml:ROLLBACK' \
  'BarsPage.qml:RECOVERY READY' \
  'ControlCenterPanel.qml:switchShell' \
  'ControlCenterPanel.qml:manager/shibumi-manager'; do
  file=${contract%%:*}
  label=${contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "missing V5 State Canvas contract: $label"
done
[[ -x $control_dir/manager/shibumi-manager ]] \
  || fail "persistent continuity manager is missing or not executable"

for retired in GeneralSettingsPage.qml WidgetSettingsPage.qml \
    LayoutSettingsPage.qml StyleSettingsPage.qml SystemSettingsPage.qml; do
  [[ ! -e $control_dir/$retired ]] \
    || fail "retired generic settings page remains: $retired"
done

for section in LAUNCHER APPLICATIONS SELECTION SCALE BACKGROUND 'BAR HEIGHT'; do
  if rg -Fq "text: \"$section\"" "$control_dir" --glob '*.qml'; then
    fail "retired or menu-only section remains: $section"
  fi
done

rg -Fq 'setWorkspacePreference' "$control_dir/BarFunctionsPage.qml" \
  || fail "workspace visuals are not owned by Appearance"
rg -Fq 'workspaceStyleRepeater.count === 8' \
  "$control_dir/BarFunctionsPage.qml" \
  || fail "appearance readiness does not cover all workspace styles"

[[ -f $control_dir/CompactSettingChoice.qml ]] \
  || fail "shared compact choice is missing"
rg -q 'property int controlHeight: Commons\.Style\.space\(25\)' \
  "$control_dir/CompactSettingChoice.qml" \
  || fail "compact choices do not use the V1 25px height"
rg -q 'property real fontSize: Commons\.Style\.font\.bodySmall' \
  "$control_dir/CompactSettingChoice.qml" \
  || fail "compact choices do not use the readable label token"

for command in omarchy-system-lock 'systemctl", "suspend' \
    omarchy-system-reboot omarchy-system-shutdown; do
  rg -Fq "$command" "$control_dir/ControlCenterPanel.qml" \
    || fail "missing session-aware power action: $command"
done

for label in Status Battery \
    Border Frost Shadow 'Radius 12' 'Radius 6'; do
  rg -Fq "label: \"$label\"" "$control_dir" --glob '*.qml' \
    || fail "missing explicit control label: $label"
done

for color_contract in \
  '{ value: "color01", label: "01" }' \
  '{ value: "color02", label: "02" }' \
  '{ value: "color03", label: "03" }' \
  '{ value: "color04", label: "04" }' \
  '{ value: "color05", label: "05" }' \
  '{ value: "color06", label: "06" }' \
  '{ value: "color07", label: "07" }' \
  '{ value: "color08", label: "08" }' \
  '{ value: "foreground", label: "FG" }'; do
  rg -Fq "$color_contract" "$control_dir/BarFunctionsPage.qml" \
    || fail "missing V1 palette choice: $color_contract"
done
rg -Fq 'readonly property int colorSwatchCount: barColorRepeater.count' \
  "$control_dir/BarFunctionsPage.qml" \
  || fail "V1 palette picker does not require all eight choices"
rg -Fq 'columns: 9' "$control_dir/BarFunctionsPage.qml" \
  || fail "Appearance palette picker is not a compact nine-column strip"
rg -Fq 'radius: root.controller.controlRadius' \
  "$control_dir/BarFunctionsPage.qml" \
  || fail "V1 palette swatches do not follow the live radius setting"
rg -Fq 'root.controller.contrastColor(barSwatch.modelData.value)' \
  "$control_dir/BarFunctionsPage.qml" \
  || fail "V1 palette swatches lack contrast-aware labels"
if rg -Fq '{ value: "red"' "$control_dir/BarFunctionsPage.qml" \
    || rg -Fq '{ value: "accent"' "$control_dir/BarFunctionsPage.qml"; then
  fail "retired pre-V1 palette choices remain"
fi

for contract in 'Themes & wallpapers' 'Screenshots & videos' \
    'value: "omarchy", label: "Omarchy"'; do
  rg -Fq "$contract" "$control_dir/BarFunctionsPage.qml" \
    || fail "missing split picker setting: $contract"
done

for provider in All Shibumi 'Omarchy Quattro' Third-party; do
  rg -Fq "\"$provider\"" "$control_dir/ProviderFilter.qml" \
    || fail "missing widget provider filter: $provider"
done
for suite_boundary in \
    'userToggleable: barWidget && (!suiteManaged || group !== "")' \
    'Control Center rejected suite-internal plugin toggle:' \
    '? String(manifest.barWidget.defaultSection) : "center"' \
    'bar.setBarWidgetInstalled(id, enabled === true, section)'; do
  rg -Fq "$suite_boundary" "$control_dir/ControlCenterPanel.qml" \
    || fail "plugin-manager suite boundary drifted: $suite_boundary"
done
for widget_surface in PluginCatalogPage.qml ControlSettings.qml; do
  rg -Fq 'entry.userToggleable === true' "$control_dir/$widget_surface" \
    || fail "$widget_surface exposes suite-internal helper plugins"
done
if rg -q 'model: 5' "$control_dir/WidgetModuleTile.qml"; then
  fail "decorative connector contacts remain on widget tiles"
fi
if rg -q 'model: 5' "$control_dir/BarsPage.qml"; then
  fail "ambiguous five-box decoration remains in the shell preview"
fi
for visual_contract in \
    'value: "none", label: "None"' \
    'value: "border", label: "Outline"' \
    'text: "CONTENT TONE"' \
    'text: "SHAPE"' \
    'text: "SPACING"' \
    'text: "SURFACE OPACITY"' \
    'label: "2 px outline"' \
    'label: "Magic dots"' \
    'Each marker is a workspace.'; do
  rg -Fq "$visual_contract" "$control_dir/BarFunctionsPage.qml" \
    || fail "Appearance is missing widget visual control: $visual_contract"
done
rg -Fq 'label: "Edit separators on bar"' \
  "$control_dir/SplitSettingsPage.qml" \
  || fail "V2 settings are missing the direct separator editor"
rg -Fq 'function beginBarEditing()' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "control center cannot enter bar edit mode"
rg -Fq 'visible: root.controller.v2LayoutActive !== true' \
  "$control_dir/SplitSettingsPage.qml" \
  || fail "V1-only split and gap controls are not capability-gated"
rg -Fq 'V1 split islands, merge and gap animations do not apply.' \
  "$control_dir/SplitSettingsPage.qml" \
  || fail "V2 layout does not explain its reduced capability contract"
if rg -Fq 'label: "Group separator"' "$control_dir/BarFunctionsPage.qml"; then
  fail "separator placement still appears as a widget Appearance option"
fi

if rg -q 'Text ·|Icon ·' "$control_dir/ControlCenterPanel.qml"; then
  fail "launcher choice labels still expose implementation-mode prefixes"
fi

workbench="$control_dir/WidgetAppearanceWorkbench.qml"
[[ -f $workbench ]] \
  || fail "direct widget Appearance workbench is missing"
for workbench_contract in \
    'property string providerFilter: "All"' \
    'readonly property var filteredOptions:' \
    'height: Commons.Style.space(310)' \
    'id: displayModeRepeater' \
    'id: surfaceModeRepeater' \
    'id: widgetColorRepeater' \
    'text: root.advancedOpen ? "Advanced" : "More"' \
    'root.controller.resetGroupAppearance('; do
  rg -Fq "$workbench_contract" "$workbench" \
    || fail "widget Appearance workbench contract drifted: $workbench_contract"
done
rg -Fq 'function resetGroupAppearance(groupId)' \
  "$repo_root/hancore.shibumi.state/Service.qml" \
  || fail "widget Appearance reset is not atomic in the state service"

if rg -q 'Regular|Minimal|heightGroup|barPresentation\.height|Ui\.Toggle|Ui\.Dropdown' \
    "$control_dir" --glob '*.qml'; then
  fail "retired oversized setting controls remain"
fi

rg -q 'color: panel\.dividerColor' "$control_dir/ControlCenterPanel.qml" \
  || fail "scroll indicator is not a neutral divider"
rg -q 'id: settingsViewport' "$control_dir/ControlCenterPanel.qml" \
  || fail "settings viewport is missing"
sed -n '/id: settingsViewport/,/Flickable {/p' \
  "$control_dir/ControlCenterPanel.qml" | rg -q 'clip: true' \
  || fail "settings viewport does not clip the scroll indicator"
rg -Fq 'settingsViewport.height - height' "$control_dir/ControlCenterPanel.qml" \
  || fail "scroll indicator is not clamped to the settings viewport"

printf 'control center regression passed\n'
