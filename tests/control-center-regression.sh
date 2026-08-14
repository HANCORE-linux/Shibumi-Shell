#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
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
install -Dm0644 "$repo_root/tests/fixtures/PluginUpdateTestService.qml" \
  "$tmpdir/control/PluginUpdateTestService.qml"
install -Dm0755 "$repo_root/tests/fixtures/slow-health-report" \
  "$tmpdir/home/.config/omarchy/plugins/hancore.shibumi.control-center/manager/shibumi-health"
mkdir -m 700 "$tmpdir/runtime"

set +e
output=$(timeout 8 env \
  HOME="$tmpdir/home" \
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
if grep -Eq 'attempted to evaluate a function in an invalid context|TypeError:.*showRoute' \
    <<<"$output"; then
  fail "destroyed Control Center context received a deferred route update"
fi

control_dir=$repo_root/hancore.shibumi.control-center

for lifecycle_contract in \
    'ControlSettings.qml:property string pendingConfigureRoute: ""' \
    'ControlSettings.qml:function scheduleConfigureRoute(value)' \
    'ControlSettings.qml:id: configureRouteSync' \
    'control-center-smoke.qml:malformed Health result replaced the last report' \
    'control-center-smoke.qml:closing the panel stopped or destroyed Health' \
    'control-center-smoke.qml:reopened Health did not expose the completed report'; do
  file=${lifecycle_contract%%:*}
  label=${lifecycle_contract#*:}
  target="$control_dir/$file"
  [[ -f $target ]] || target="$repo_root/tests/$file"
  rg -Fq "$label" "$target" \
    || fail "Health lifecycle contract drifted: $label"
done

rg -q 'contentWidth: fittedContentWidth\(Commons\.Style\.space\(820\)' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "control card does not use the compact control-center workspace"
rg -q 'readonly property string barPosition:' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "panel does not expose the bar-position facade"
rg -q 'root\.toggle\(\)' "$control_dir/BarWidget.qml" \
  || fail "G1 does not use its native panel lifecycle"
rg -Fq 'readonly property bool animationActive: pointer.containsMouse' \
  "$control_dir/BarWidget.qml" \
  || fail "G1 background motion is not hover-only"
rg -Fq 'readonly property bool nativePillSurfaceVisible: !stockOmarchyHost' \
  "$control_dir/BarWidget.qml" \
  || fail "stock Omarchy return icon inherits a Shibumi pill surface"
rg -Fq 'readonly property color renderedPillFillColor:' \
  "$control_dir/BarWidget.qml" \
  || fail "G1 does not expose its V1 fill on the native pill surface"
if rg -Fq 'pointer.containsMouse || opened' "$control_dir/BarWidget.qml"; then
  fail "G1 background motion still runs for the full panel lifetime"
fi
rg -Fq 'text: "SHIBUMI"' "$control_dir/BarWidget.qml" \
  || fail "G1 does not render the Shibumi wordmark"
rg -Fq 'HostIdentity.isStockOmarchyHost(bar)' "$control_dir/BarWidget.qml" \
  || fail "G1 does not resolve the active host through Quattro shell state"
rg -Fq 'function triggerPress(mouseButton)' "$control_dir/BarWidget.qml" \
  || fail "G1 does not expose the Omarchy bar click-forwarding contract"
rg -Fq 'onClicked: function(mouse) { root.triggerPress(mouse.button) }' \
  "$control_dir/BarWidget.qml" \
  || fail "G1 bypasses its shared host click path"
[[ -f $control_dir/assets/shibumi-icon-hikiryo.svg ]] \
  || fail "stock Omarchy host icon is missing"
rg -Fq 'source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")' \
  "$control_dir/BarWidget.qml" \
  || fail "stock Omarchy host does not render the Hikiryō icon"
rg -Fq 'width: root.stockOmarchyHost ? 18 : 16' \
  "$control_dir/BarWidget.qml" \
  || fail "stock Omarchy host icon is not pixel-centered in its even slot"
for hikiryo_tone_contract in \
  'root.launcherConfig.icon === "shibumi" && !root.v1CustomFill' \
  'id: v1TintedLauncherIcon' \
  '&& root.v1CustomFill' \
  'tint: root.widgetInk'; do
  rg -Fq "$hikiryo_tone_contract" "$control_dir/BarWidget.qml" \
    || fail "Hikiryō V1 tone contract drifted: $hikiryo_tone_contract"
done
rg -Fq 'HostIdentity.shellName(bar)' "$control_dir/ControlCenterPanel.qml" \
  || fail "Bars page does not resolve the active host through Quattro shell state"
rg -Fq 'readonly property real returnOnlyQuickPanelHeight:' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "Omarchy return panel does not derive its compact content height"
rg -Fq '? fittedContentHeight(returnOnlyQuickPanelHeight,' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "Omarchy return panel still reserves a full Control Center viewport"
rg -Fq 'text: "shibumi"' "$repo_root/hancore.shibumi.state/ShibumiConfig.js" \
  || fail "G1 does not default to the Shibumi identity"

if rg -q 'hancore\.shibumi\.menu|hostShell\.toggle|shell\.mutateShellConfig' \
    "$control_dir" --glob '*.qml'; then
  fail "control center still owns or invokes the App Menu"
fi

for contract in \
  'ControlMainPage.qml:ATTENTION  ·  ' \
  'ControlMainPage.qml:RUNTIME' \
  'ActiveBarSettingsPage.qml:BAR FORM' \
  'ActiveBarSettingsPage.qml:V1 LAYOUT' \
  'ActiveBarSettingsPage.qml:V2 LAYOUT' \
  'ActiveBarSettingsPage.qml:GAP ANIMATIONS' \
  'BarSurfaceSettings.qml:BAR SURFACE' \
  'BarSurfaceSettings.qml:BAR ACCENT' \
  'WorkspaceSettingsPage.qml:VISIBLE WORKSPACES' \
  'WorkspaceSettingsPage.qml:MARKER STYLE' \
  'PickerSettingsPage.qml:THEMES & WALLPAPERS' \
  'PickerSettingsPage.qml:SCREENSHOTS & VIDEOS'; do
  file=${contract%%:*}
  section=${contract#*:}
  rg -Fq "text: \"$section\"" "$control_dir/$file" \
    || fail "missing control-center section: $section"
done

for launcher_owner_contract in \
    'BarWidget.qml:|| String(launcherConfig.mode || "text") === "icon"' \
    'BarWidget.qml:String(launcherConfig.text || "shibumi")' \
    'WidgetAppearanceWorkbench.qml:readonly property bool selectedLauncher: selectedCatalogGroup === "G1"' \
    'WidgetAppearanceWorkbench.qml:if (catalogGroup === "G1") return []' \
    'WidgetAppearanceWorkbench.qml:if (!selectedSupported || selectedLauncher) return false' \
    'WidgetAppearanceWorkbench.qml:visible: !root.selectedLauncher' \
    'WidgetAppearanceWorkbench.qml:return "Logo · " + (String(controller.launcherConfig.mode || "text")' \
    'BarFunctionsPage.qml:Launcher identity stays under Logo.'; do
  file=${launcher_owner_contract%%:*}
  label=${launcher_owner_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "launcher presentation ownership drifted: $label"
done
if rg -q 'setting\("displayMode"|displayMode ===' \
    "$control_dir/BarWidget.qml"; then
  fail "launcher rendering still depends on generic widget presentation"
fi
for header_contract in \
  'ControlCenterPanel.qml:id: headerBand' \
  'ControlCenterPanel.qml:id: headerDivider' \
  'ControlCenterPanel.qml:ActiveBarStatus {' \
  'ActiveBarStatus.qml:stateService.paletteColor("color03")' \
  'ActiveBarStatus.qml:"OMARCHY BAR ACTIVE"' \
  'ActiveBarStatus.qml:"SHIBUMI V2 ACTIVE" : "SHIBUMI V1 ACTIVE"' \
  'ControlCenterPanel.qml:anchors.leftMargin: Commons.Style.space(20)' \
  'ControlCenterPanel.qml:anchors.rightMargin: Commons.Style.space(20)' \
  'ControlSettings.qml:anchors.leftMargin: Commons.Style.space(20)' \
  'ControlSettings.qml:anchors.rightMargin: Commons.Style.space(20)'; do
  file=${header_contract%%:*}
  label=${header_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "header/search alignment drifted: $label"
done

for shell_style in full fit dock notch; do
  rg -Fq "value: \"$shell_style\"" \
    "$control_dir/ActiveBarSettingsPage.qml" \
    || fail "missing V2 bar shell style: $shell_style"
done
rg -Fq 'name === "shellStyle"' \
  "$repo_root/hancore.shibumi.state/Service.qml" \
  || fail "bar shell style is not persisted by the state service"
for variant_memory_contract in \
    'ShibumiConfig.js:v2ShellStyle: "full"' \
    'Service.qml:function setShellVariant(target)' \
    'Service.qml:next.presentation.v2ShellStyle = current' \
    'ControlCenterPanel.qml:function setBarVariant(target)' \
    'QuickControlPage.qml:return controller.setBarVariant(requested)' \
    'QuickControlPage.qml:"bar-v2-" + v2ShellStyle'; do
  file=${variant_memory_contract%%:*}
  label=${variant_memory_contract#*:}
  target_file="$control_dir/$file"
  [[ -f $target_file ]] || target_file="$repo_root/hancore.shibumi.state/$file"
  rg -Fq "$label" "$target_file" \
    || fail "V1/V2 style-memory contract drifted: $label"
done
for layout_protection_contract in \
    'ShibumiConfig.js:function defaultLayoutProtectionConfig()' \
    'Service.qml:function setLayoutProtection(variantValue, enabled)' \
    'ControlCenterPanel.qml:function setLayoutProtection(variant, enabled)' \
    'ActiveBarSettingsPage.qml:controller.setLayoutProtection(' \
    'ActiveBarSettingsPage.qml:? controller.v2LayoutProtected === true' \
    'ActiveBarSettingsPage.qml:: controller.v1LayoutProtected === true'; do
  file=${layout_protection_contract%%:*}
  label=${layout_protection_contract#*:}
  target_file="$control_dir/$file"
  [[ -f $target_file ]] || target_file="$repo_root/hancore.shibumi.state/$file"
  rg -Fq "$label" "$target_file" \
    || fail "V1/V2 layout protection contract drifted: $label"
done
rg -Fq 'restoreBar.scheduleOpenControlCenterRestores(' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "shell-style changes do not preserve the open Control Center page"
rg -Fq 'presentationName === "shellStyle"' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "shell-style restore does not wait for the replacement panel owner"
rg -Fq 'settings.restorePage, true, ownerWidget, popoutScreenName' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "V1/V2 restore does not wait for replacement owners"
layout_protection_controller=$(sed -n \
  '/^  function setLayoutProtection(variant, enabled) {$/,/^  }$/p' \
  "$control_dir/ControlCenterPanel.qml")
for protection_restore_contract in \
    'restoreBar.scheduleOpenControlCenterRestores' \
    'settings.restorePage, false, ownerWidget, popoutScreenName' \
    'restoreBar.cancelCreatedWidgetRestores(created)'; do
  grep -Fq "$protection_restore_contract" \
    <<<"$layout_protection_controller" \
    || fail "layout lock restore drifted: $protection_restore_contract"
done
rg -A18 -F 'function setBarPosition(value, ownerValue, screenName)' \
    "$repo_root/hancore.shibumi.bar/Bar.qml" \
  | rg -Fq 'root.scheduleOpenControlCenterRestores(' \
  || fail "Top/Bottom changes do not preserve the Control Center route"
for output_restore_contract in \
    'property var pendingWidgetRestores: []' \
    'function widgetRestoreIndex(pluginId, owner, screenName)' \
    'function widgetRestorePendingForOutput(pluginId, owner, screenName)' \
    'function findPanelWidgetOnScreen(pluginId, screenName)' \
    'record.activeOwner === owner' \
    'function trackWidgetRestorePage(pluginId, page, ownerValue, screenName)' \
    'if (record.attempts < 20) next.push(record)'; do
  rg -Fq "$output_restore_contract" \
    "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "output-local panel restore drifted: $output_restore_contract"
done
rg -Fq 'controller.trackSettingsPage(next)' \
  "$control_dir/ControlSettings.qml" \
  || fail "Control Center navigation is not handed to the restore lifecycle"
rg -Fq 'bar.cancelWidgetRestore(moduleName, root, outputName)' \
  "$control_dir/BarWidget.qml" \
  || fail "closing the Control Center does not cancel its output-local restore"
rg -Fq 'function runWithControlCenterRestore(callback)' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "widget Appearance changes do not preserve the Control Center"
plugin_bar_toggle=$(sed -n \
  '/^  function setPluginBarWidgetEnabled(pluginId, enabled, section) {$/,/^  }$/p' \
  "$control_dir/ControlCenterPanel.qml")
grep -Fq 'return runWithControlCenterRestore(function() {' \
    <<<"$plugin_bar_toggle" \
  || fail "V1 plugin activation does not preserve the Control Center"
rg -Fq 'restoreBar.scheduleOpenControlCenterRestores(' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "state mutations are not enrolled in panel-owner handoff"
rg -Fq 'function trackControlCenterWidgetDetail(groupId, pluginId)' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "widget detail selection does not survive panel-owner replacement"
rg -Fq 'root.controller.restoreWidgetDetails(item)' \
  "$control_dir/ControlSettings.qml" \
  || fail "the rebuilt Icons page does not restore its selected widget"
rg -Fq '"accent", "border", "panelBorder", "frost", "shadow"' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "bar presentation changes do not preserve the Control Center page"
rg -Fq 'readonly property bool barsChildRouteActive:' \
  "$control_dir/ControlSettings.qml" \
  || fail "V1 Gap Animations child route has no active-state contract"
rg -Fq 'anchors.bottomMargin: Commons.Style.space(3)' \
  "$control_dir/BarSurfaceSettings.qml" \
  || fail "selected accent does not use the QS-Dots underline treatment"
rg -Fq 'scale: hovered ? 1.04 : 1' \
  "$control_dir/BarSurfaceSettings.qml" \
  || fail "accent hover feedback lost its QS-Dots motion treatment"
if rg -q 'centerOnBar:[[:space:]]*true' \
    "$control_dir/ControlCenterPanel.qml"; then
  fail "Control Center is centered instead of anchored to its launcher widget"
fi
rg -Fq 'typeof bar.setBarWidgetInstalled' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "Add plugin does not mutate the Quattro bar layout"
rg -Fq 'AVAILABLE PLUGINS' "$control_dir/ControlSettings.qml" \
  || fail "plugin picker does not expose the available bar-plugin catalog"
for installer_contract in \
  'property bool installerDirect: false' \
  'function openPluginInstaller()' \
  'installMode = true' \
  'installerDirect = true' \
  'label: root.installerDirect ? "Cancel" : "Back"' \
  'root.controller.accentColor("color03")' \
  'root.controller.accentColor("color01")' \
  'opacity: root.validInstallUrl ? 1 : 0.32' \
  'loops: 2' \
  'renderType: Text.NativeRendering'; do
  rg -Fq "$installer_contract" "$control_dir/ControlSettings.qml" \
    || fail "direct Git installer contract drifted: $installer_contract"
done

for page in quick configure main bars bars-motion plugins workspaces pickers logo splits \
    functions health preferences; do
  rg -Fq "\"$page\"" "$control_dir/ControlSettings.qml" \
    || fail "missing control-center page: $page"
done

configure_page_order=$(
  sed -n '/const pages = \[/,/^    \]/p' \
    "$control_dir/ControlSettings.qml" \
    | sed -n 's/.*{ id: "\([^"]*\)".*/\1/p' \
    | paste -sd, -
)
[[ $configure_page_order == \
  "bars,functions,logo,workspaces,pickers,plugins,health" ]] \
  || fail "Configure page order drifted: $configure_page_order"
rg -Fq '{ id: "functions", label: "Icons"' \
  "$control_dir/ControlSettings.qml" \
  || fail "Configure Icons route lost its user-facing label"
rg -Fq 'title: "Icons"' "$control_dir/BarFunctionsPage.qml" \
  || fail "Icons page title drifted"

[[ -f $control_dir/ConfigureLandingPage.qml ]] \
  || fail "Configure landing page is missing"
[[ -f $control_dir/ActiveBarSettingsPage.qml ]] \
  || fail "active-bar drill-down is missing"
for configure_contract in \
  'ControlSettings.qml:return setPage("configure")' \
  'ControlSettings.qml:ConfigureLandingPage {' \
  'ControlSettings.qml:property string configureDetailPage: ""' \
  'ControlSettings.qml:id: configureDetailPane' \
  'ControlSettings.qml:sourceComponent: root.pageComponent(' \
  'ControlSettings.qml:id: activeBarPage' \
  'ControlSettings.qml:ActiveBarSettingsPage {' \
  'ControlSettings.qml:function showBarsChildRoute()' \
  'ControlSettings.qml:onBarsChildRequested: root.showBarsChildRoute()' \
  'ConfigureLandingPage.qml:function openRoute(pageId)' \
  'ConfigureLandingPage.qml:function showRoute(pageId)' \
  'ConfigureLandingPage.qml:signal backRequested()' \
  'ConfigureLandingPage.qml:signal barsChildRequested()' \
  'ConfigureLandingPage.qml:context.bezierCurveTo(' \
  'ConfigureLandingPage.qml:routeColumn.width + routeGraph.portOffset' \
  'ConfigureLandingPage.qml:context.arc(startX, startY, 3.6, 0, Math.PI * 2)' \
  'ConfigureLandingPage.qml:activeFocusOnTab: true' \
  'ConfigureLandingPage.qml:property int focusIndex: -1' \
  'ConfigureLandingPage.qml:onActiveFocusChanged:' \
  'ControlSettings.qml:configureLanding.focus = false' \
  'ConfigureLandingPage.qml:Keys.onReturnPressed:' \
  'ConfigureLandingPage.qml:function activateFocusedRoute()' \
  'ConfigureLandingPage.qml:id: detailRouteCanvas' \
  'ConfigureLandingPage.qml:x: -Commons.Style.space(14)' \
  'ConfigureLandingPage.qml:height: root.transitioning ? 0 : implicitHeight' \
  'ConfigureLandingPage.qml:spacing: root.transitioning ? 0 : Commons.Style.space(14)' \
  'ConfigureLandingPage.qml:return 0' \
  'ConfigureLandingPage.qml:context.lineTo(nodeX, lastY)' \
  'ConfigureLandingPage.qml:context.arc(nodeX, nodeY, 3.6, 0, Math.PI * 2)' \
  'ConfigureLandingPage.qml:? "Favorites" : root.barsChildRouteLabel' \
  'ConfigureLandingPage.qml:activeFocusOnTab: visible' \
  'ConfigureLandingPage.qml:if (root.childRouteActive) {' \
  'ConfigureLandingPage.qml:context.lineTo(railX, nodeY)' \
  'ConfigureLandingPage.qml:root.pageRequested(routeCard.modelData.id)' \
  'ConfigureLandingPage.qml:? root.targetY(modelData.id) + homeY : homeY' \
  'ConfigureLandingPage.qml:? Commons.Style.space(154) : routeColumn.width' \
  'ConfigureLandingPage.qml:enabled: !root.transitioning || root.detailOpen' \
  'ConfigureLandingPage.qml:id: intro' \
  'ConfigureLandingPage.qml:opacity: 1' \
  'ConfigureLandingPage.qml:Behavior on x {' \
  'ConfigureLandingPage.qml:interval: 330' \
  'ActiveBarSettingsPage.qml:readonly property string childRouteLabel: "Gap Animations"' \
  'ActiveBarSettingsPage.qml:property bool motionDetailOpen: false' \
  'ActiveBarSettingsPage.qml:columns: 3' \
  'ActiveBarSettingsPage.qml:motionEnabled && (selected || previewPointer.containsMouse)' \
  'ActiveBarSettingsPage.qml:detail: "Add slots and dividers"' \
  'ControlSettings.qml:id: page.id === "main" ? "configure" : page.id' \
  'ControlCenterPanel.qml:: settings.restorePage === "configure" ? "CONFIGURE"'; do
  file=${configure_contract%%:*}
  label=${configure_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Configure landing transition drifted: $label"
done
if rg -Fq '{ id: "main", label: "Overview"' \
    "$control_dir/ControlSettings.qml"; then
  fail "Configure landing still exposes the redundant Overview route"
fi
[[ -f $control_dir/ConfigureRoutePreview.qml ]] \
  || fail "Configure route preview is missing"
rg -Fq 'ConfigureRoutePreview {' "$control_dir/ConfigureLandingPage.qml" \
  || fail "Configure landing does not show route-specific previews"
for configure_preview_contract in \
    'SemanticPreviewImage.qml:if (route === "bars") {' \
    'SemanticPreviewImage.qml:visible: root.semanticRoute === "plugins"' \
    'SemanticPreviewImage.qml:text: String(modelData.provider || "Community").toUpperCase()' \
    'SemanticPreviewImage.qml:visible: root.semanticRoute === "workspaces"' \
    'SemanticPreviewImage.qml:delegate: WorkspaceMarkerPreviewCard {' \
    'SemanticPreviewImage.qml:visible: root.semanticRoute === "pickers"' \
    'SemanticPreviewImage.qml:delegate: PickerPreviewCard {' \
    'SemanticPreviewImage.qml:visible: root.semanticRoute === "appearance"' \
    'SemanticPreviewImage.qml:text: modelData.mode' \
    'SemanticPreviewImage.qml:visible: root.semanticRoute === "health"' \
    'SemanticPreviewImage.qml:text: "RUNTIME HEALTH"' \
    'SemanticPreviewImage.qml:root.healthPreviewWarningCount > 0 ? "REVIEW" : "HEALTHY"' \
    'SemanticPreviewImage.qml:property bool compact: false' \
    'PageMotionStage.qml:compact: true' \
    'SemanticPreviewImage.qml:visible: root.semanticRoute === "logo"' \
    'SemanticPreviewImage.qml:source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")' \
    'ConfigureLandingPage.qml:property int lastPreviewIndex: 0' \
    'ConfigureLandingPage.qml:previewDetail: previewDetails[page.id] || "Settings preview"' \
    'ConfigureLandingPage.qml:detail: root.previewRoute.previewDetail' \
    'ControlSettings.qml:readonly property bool compactConfigureLanding:' \
    'ControlSettings.qml:readonly property real compactConfigureLandingPanelHeight:' \
    'ControlCenterPanel.qml:: settings.compactConfigureLanding' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactConfigureLandingPanelHeight,'; do
  file=${configure_preview_contract%%:*}
  label=${configure_preview_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Configure semantic preview contract drifted: $label"
done
if rg -q 'previewTransition|previewScale|previewOpacity' \
    "$control_dir/ConfigureRoutePreview.qml"; then
  fail "Configure route preview still dims or scales on hover changes"
fi
for header_status_contract in \
    'ControlSettings.qml:readonly property int healthErrorCount:' \
    'ControlSettings.qml:readonly property int healthWarningCount:' \
    'ControlSettings.qml:readonly property bool healthPassed:' \
    'ControlSettings.qml:controller.accentColor("color01")' \
    'ControlSettings.qml:? "HEALTH  ·  " + root.healthErrorCount' \
    'ControlSettings.qml:? "HEALTH  ·  REVIEW"' \
    'ControlSettings.qml:root.healthPassed ? "HEALTH  ·  PASS" : "HEALTH"' \
    'ControlSettings.qml:controller.accentColor("color03")' \
    'ControlSettings.qml:text: "PLUGINS"' \
    'ControlSettings.qml:color: root.registryValueColor' \
    'ControlCenterPanel.qml:readonly property int headerHealthErrorCount: settings.healthErrorCount' \
    'control-center-smoke.qml:panel.headerHealthErrorCount !== 1'; do
  file=${header_status_contract%%:*}
  label=${header_status_contract#*:}
  target="$control_dir/$file"
  if [[ $file == control-center-smoke.qml ]]; then
    target="$repo_root/tests/$file"
  fi
  rg -Fq "$label" "$target" \
    || fail "Control header status contract drifted: $label"
done
if rg -Fq 'ConfigureNavigation {' "$control_dir/ControlSettings.qml"; then
  fail "retired Configure sidebar is still instantiated"
fi
if rg -Fq 'text: "CONFIGURE"' \
    "$control_dir/ConfigureLandingPage.qml"; then
  fail "Configure landing repeats the already-selected mode label"
fi
if rg -Fq 'id: routeArrow' "$control_dir/ConfigureLandingPage.qml" \
    || rg -q 'text:.*[‹›]' "$control_dir/ConfigureLandingPage.qml"; then
  fail "Configure routes use ambiguous chevrons instead of an explicit back action"
fi
if rg -Fq 'Back to Configure' \
    "$control_dir/ConfigureLandingPage.qml"; then
  fail "persistent Configure navigation still renders a redundant back route"
fi
if rg -Fq 'x: root.transitioning && selected ? -Commons.Style.space(20) : 0' \
    "$control_dir/ConfigureLandingPage.qml"; then
  fail "Configure detail anchor no longer aligns with the Quick content axis"
fi
if rg -Fq 'return -routeGraph.y' \
    "$control_dir/ConfigureLandingPage.qml"; then
  fail "Configure route cards render outside their pointer hit-test parent"
fi

for contract in \
  'ControlOverviewPage.qml:Control Center' \
  'PluginCatalogPage.qml:title: root.favoritesOnly ? "Favorites" : "Plugins"' \
  'ControlSettings.qml:Add plugin' \
  'ControlSettings.qml:Install plugin from Git' \
  'ControlSettings.qml:function extractInstallUrl(value)' \
  'ControlSettings.qml:function pluginInstallCommand(value)' \
  'ControlSettings.qml:if (repository !== "") return ""' \
  'ControlSettings.qml:"omarchy", "plugin", "add", repository, "--yes"' \
  'ControlSettings.qml:onEditingFinished: root.normalizeInstallInput()' \
  'ControlSettings.qml:Plugins run as unsandboxed code'; do
  file=${contract%%:*}
  label=${contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "missing V4 control-center contract: $label"
done

for refined_contract in \
  'ControlSettings.qml:sequence: "Ctrl+K"' \
  'ControlSettings.qml:placeholder: "Search settings, options, or plugins…"' \
  'ControlSettings.qml:{ value: "quick", label: "QUICK" }' \
  'ControlSettings.qml:{ value: "configure", label: "CONFIGURE" }' \
  'ControlCenterPanel.qml:contentHeight: settings.currentPage === "quick"' \
  'QuickControlPage.qml:label: "V1"' \
  'QuickControlPage.qml:label: "V2"' \
  'QuickControlPage.qml:label: "Omarchy Bar"' \
  'QuickControlPage.qml:id: "add-plugin", label: "+ Add plugin"' \
  'QuickControlPage.qml:id: "reload", label: "Reload Shibumi"' \
  'QuickControlPage.qml:id: "bars", label: "Bars"' \
  'QuickControlPage.qml:id: "pickers", label: "Pickers"' \
  'QuickControlPage.qml:glyph: "align_vertical_center"' \
  'QuickControlPage.qml:id: "screensaver", label: "Screensaver"' \
  'QuickControlPage.qml:id: "lock", label: "Lock"' \
  'QuickControlPage.qml:id: "reboot", label: "Reboot"' \
  'QuickControlPage.qml:id: "shutdown", label: "Shutdown"' \
  'QuickControlPage.qml:text: "Cancel"' \
  'QuickControlPage.qml:? "Reboot now"' \
  'QuickControlPage.qml:? "Shutdown now"' \
  'ActiveBarSettingsPage.qml:root.activeLabel + " ACTIVE"' \
  'ActiveBarSettingsPage.qml:visible: root.shibumiActive && !root.v2Active' \
  'ActiveBarSettingsPage.qml:visible: root.v2Active' \
  'ActiveBarSettingsPage.qml:surfaceEffectOptionCount:' \
  'ActiveBarSettingsPage.qml:surfaceRadiusOptionCount:' \
  'ControlSettings.qml:protect protection lock split gap slots divider separator'; do
  file=${refined_contract%%:*}
  label=${refined_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "refined Control Center contract drifted: $label"
done

[[ -f $control_dir/SearchEngine.js ]] \
  || fail "shared predictive-search engine is missing"
[[ -f $control_dir/PredictiveSearchInput.qml ]] \
  || fail "shared predictive-search input is missing"
for search_contract in \
  'SearchEngine.js:function fuzzyScore(queryValue, candidateValue)' \
  'SearchEngine.js:return 100 + gaps' \
  'SearchEngine.js:function filterAndRank(entries, queryValue)' \
  'SearchEngine.js:function primaryEntryFields(entry)' \
  'SearchEngine.js:function collectMatches(source, query, scorer, includeDescription)' \
  'SearchEngine.js:source, query, directEntryScore, false' \
  'SearchEngine.js:source, query, directEntryScore, true' \
  'SearchEngine.js:function completions(entries, queryValue, limitValue)' \
  'SearchEngine.js:if (primaryDirect.length > 0)' \
  'PredictiveSearchInput.qml:Qt.Key_Down' \
  'PredictiveSearchInput.qml:Qt.Key_Up' \
  'PredictiveSearchInput.qml:Qt.Key_Tab' \
  'PredictiveSearchInput.qml:Qt.Key_Right' \
  'PredictiveSearchInput.qml:searchInput.cursorPosition === searchInput.length' \
  'PredictiveSearchInput.qml:Qt.Key_Return' \
  'PredictiveSearchInput.qml:Qt.Key_Enter' \
  'PredictiveSearchInput.qml:function handleEscape()' \
  'PredictiveSearchInput.qml:function blur()' \
  'PredictiveSearchInput.qml:return "suggestions"' \
  'PredictiveSearchInput.qml:searchInput.focus = false' \
  'PredictiveSearchInput.qml:return "clear"' \
  'PredictiveSearchInput.qml:id: suggestionPopup' \
  'PredictiveSearchInput.qml:id: suggestionPointer' \
  'PredictiveSearchInput.qml:property string popupStyle: "global"' \
  'PredictiveSearchInput.qml:readonly property bool catalogPopup:' \
  'PredictiveSearchInput.qml:readonly property real reservedPopupHeight:' \
  'PredictiveSearchInput.qml:anchors.topMargin: Commons.Style.space(4)' \
  'PredictiveSearchInput.qml:root.controller.marketPanel.r' \
  'PredictiveSearchInput.qml:root.controller.marketPanel.b' \
  'PredictiveSearchInput.qml:border.width: 1' \
  'PredictiveSearchInput.qml:border.color: root.controller.controlBorderColor' \
  'PredictiveSearchInput.qml:anchors.margins: 1' \
  'PluginCatalogPage.qml:PredictiveSearchInput {' \
  'PluginCatalogPage.qml:popupStyle: "catalog"' \
  'PluginCatalogPage.qml:suggestionLimit: 4' \
  'ControlSettings.qml:PredictiveSearchInput {' \
  'ControlSettings.qml:popupStyle: "catalog"' \
  'ControlSettings.qml:suggestionLimit: 4' \
  'ControlSettings.qml:+ settingsSearch.reservedPopupHeight' \
  'PluginCatalogPage.qml:+ pluginSearch.reservedPopupHeight' \
  'ControlSearchPage.qml:SearchEngine.filterAndRank(searchEntries, query)' \
  'ControlCenterPanel.qml:searchTags:'; do
  file=${search_contract%%:*}
  label=${search_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "shared predictive-search contract drifted: $label"
done
if rg -Fq 'width: Commons.Style.space(28)' \
    "$control_dir/PredictiveSearchInput.qml"; then
  fail "predictive search still draws the obsolete focus underline"
fi
for click_away_contract in \
    'height: Commons.Style.space(42)' \
    'function dismissSearchesAt(x, y)' \
    'TapHandler {' \
    'gesturePolicy: TapHandler.ReleaseWithinBounds' \
    'onTapped: function(eventPoint, _button)' \
    'eventPoint.position.x, eventPoint.position.y'; do
  rg -Fq "$click_away_contract" "$control_dir/ControlSettings.qml" \
    || fail "global search click-away contract drifted: $click_away_contract"
done
if rg -Fq 'propagateComposedEvents: true' \
    "$control_dir/ControlSettings.qml"; then
  fail "search click-away can still leak into the panel dismiss layer"
fi
for disabled_search_contract in \
    'function applyPluginSearchQuery(value)' \
    '&& selectedProvider === "Active"' \
    'selectedProvider = "All"' \
    'onEdited: function(value) { root.applyPluginSearchQuery(value) }'; do
  rg -Fq "$disabled_search_contract" "$control_dir/PluginCatalogPage.qml" \
    || fail "disabled plugin search drifted: $disabled_search_contract"
done
for favorite_contract in \
    'ConfigureLandingPage.qml:signal favoritesRequested()' \
    'ConfigureLandingPage.qml:text: root.pluginFavoritesVisible' \
    'ControlSettings.qml:function showPluginFavorites()' \
    'ControlSettings.qml:onFavoritesRequested: root.showPluginFavorites()' \
    'PluginCatalogPage.qml:property bool favoritesOnly: false' \
    'PluginCatalogPage.qml:function toggleFavoriteById(pluginId)' \
    'WidgetModuleTile.qml:controller.accentColor("color03")' \
    'WidgetModuleTile.qml:favorite ? "󰓎" : "star_border"' \
    'WidgetModuleTile.qml:font.family: "JetBrainsMono Nerd Font"' \
    'ControlCenterPanel.qml:function setPluginFavorite(pluginId, favorite)' \
    'Service.qml:function setPluginFavorite(pluginId, favorite)' \
    'ShibumiConfig.js:plugins: defaultPluginConfig()'; do
  file=${favorite_contract%%:*}
  label=${favorite_contract#*:}
  if [[ $file == Service.qml || $file == ShibumiConfig.js ]]; then
    rg -Fq "$label" "$repo_root/hancore.shibumi.state/$file" \
      || fail "plugin favorite persistence drifted: $label"
  else
    rg -Fq "$label" "$control_dir/$file" \
      || fail "plugin favorite UI drifted: $label"
  fi
done
rg -Fq 'surfaceEffectOptionCount !== 2' \
  "$repo_root/tests/control-center-smoke.qml" \
  || fail "QML smoke does not reject V1 effects in V2"
rg -Fq 'surfaceRadiusOptionCount !== 0' \
  "$repo_root/tests/control-center-smoke.qml" \
  || fail "QML smoke does not reject V1 radii in V2"

[[ ! -e $control_dir/PresetMotionCanvas.qml ]] \
  || fail "retired continuous p5 animation remains"
[[ -f $control_dir/PageMotionStage.qml ]] \
  || fail "contained page-motion stage is missing"
[[ -f $control_dir/PageHeaderHero.qml ]] \
  || fail "page-header landing component is missing"
[[ -f $control_dir/SemanticPreviewImage.qml ]] \
  || fail "shared static semantic preview is missing"
[[ -f $control_dir/BarStylePreviewCard.qml ]] \
  || fail "visual bar-form selector is missing"
[[ -f $control_dir/WordmarkPreview.qml ]] \
  || fail "visual wordmark selector is missing"
for preview_contract in \
  'root.styleValue === "full"' \
  'root.styleValue === "fit"' \
  'root.styleValue === "dock"' \
  'const wing = Math.min(15, compactWidth / 5)' \
  'context.moveTo(0, atTop ? shellY + shellHeight : shellY)'; do
  rg -Fq "$preview_contract" "$control_dir/BarStylePreviewCard.qml" \
    || fail "bar-form preview drifted from RunChrome: $preview_contract"
done
for logo_contract in \
  'LogoSettingsPage.qml:WordmarkPreview {' \
  'LogoSettingsPage.qml:source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")' \
  'ControlCenterPanel.qml:"shibumi", "omarchy", "hyprland"' \
  'BarWidget.qml:root.launcherConfig.icon !== "shibumi"' \
  'WordmarkPreview.qml:Qt.resolvedUrl("assets/bob2.png")' \
  'WordmarkPreview.qml:Qt.resolvedUrl("assets/bob3.png")' \
  'WordmarkPreview.qml:Qt.resolvedUrl("assets/omacom-text.png")'; do
  file=${logo_contract%%:*}
  label=${logo_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "logo preview contract drifted: $label"
done
for shared_page in LogoSettingsPage.qml PickerSettingsPage.qml \
    ControlMainPage.qml; do
  if rg -q 'v2LayoutActive|v2Active' "$control_dir/$shared_page"; then
    fail "$shared_page contains an unintended V1/V2 capability gate"
  fi
done
for motion_contract in \
  'PageMotionStage.qml:clip: true' \
  'PageMotionStage.qml:radius: controller.controlRadius' \
  'PageHeaderHero.qml:PageMotionStage {' \
  'PageMotionStage.qml:SemanticPreviewImage {' \
  'ConfigureRoutePreview.qml:SemanticPreviewImage {' \
  'SemanticPreviewImage.qml:renderStrategy: Canvas.Threaded' \
  'PageMotionStage.qml:onPageKeyChanged: previewTransition.restart()' \
  'PageMotionStage.qml:duration: 280' \
  'PageMotionStage.qml:activeFocusOnTab: interactive' \
  'PageMotionStage.qml:Keys.onReturnPressed:'; do
  file=${motion_contract%%:*}
  label=${motion_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "page-motion contract drifted: $label"
done
if rg -q 'PresetMotionCanvas|frameInterval|requestAnimationFrame' \
    "$control_dir" --glob '*.qml'; then
  fail "continuous decorative animation remains in the Control Center"
fi

for landing_contract in \
  'id: barButtonColumn' \
  'width: parent.width' \
  'radius: root.controller.controlRadius' \
  'id: routeCanvas' \
  'context.bezierCurveTo(' \
  'barButtonColumn.width + barLanding.portOffset' \
  'context.arc(startX, startY, 3.6, 0, Math.PI * 2)' \
  'function onHoveredBarIndexChanged()' \
  'root.previewing ? "BAR PREVIEW" : "ACTIVE BAR"' \
  'pageKey: root.previewRoute' \
  'interactive: !root.returnOnly && !root.previewing' \
  'onClicked: root.controller.showSettingsPage("bars")' \
  'onEntered: root.hoveredBarIndex = barOption.index' \
  'onClicked: barOption.activate()' \
  'PageMotionStage {'; do
  rg -Fq "$landing_contract" "$control_dir/QuickControlPage.qml" \
    || fail "BAR landing-page contract drifted: $landing_contract"
done
if rg -q 'triggerQuickAction|toggleQuickWidget|toggleWifi|toggleBluetooth|wpctl.*set-mute|cycleProfile' \
    "$control_dir/ControlCenterPanel.qml" "$control_dir/QuickControlPage.qml"; then
  fail "retired Quick widget toggles remain reachable"
fi
if rg -q 'BAR WIDGETS|\+ Add widget|V1 / V2 applies|SectionLabel \{ text: "BAR"' \
    "$control_dir/QuickControlPage.qml"; then
  fail "retired Quick copy or widget section remains"
fi
if rg -Fq 'anchors.bottom: parent.bottom' \
    "$control_dir/PageMotionStage.qml"; then
  fail "motion stage reintroduced a decorative left-edge rail"
fi
if rg -q 'barOption\\.modelData\\.active.*[●›]|text:.*[●›]' \
    "$control_dir/QuickControlPage.qml"; then
  fail "BAR routes use chevrons instead of circular connection ports"
fi
if rg -Fq 'id: routeIndicator' "$control_dir/QuickControlPage.qml"; then
  fail "BAR route renders a duplicate connection point inside its card"
fi
for quick_contract in \
  'QuickControlPage.qml:controller.paletteColor("color04")' \
  'ControlSettings.qml:onClicked: root.setPage("plugins")' \
  'ControlSettings.qml:onClicked: root.setPage("health")' \
  'ControlSettings.qml:id: statusSelector' \
  'ControlSettings.qml:id: healthStatusShortcut' \
  'ControlSettings.qml:id: healthStatusPointer' \
  'ControlSettings.qml:id: pluginRegistryStatus' \
  'ControlSettings.qml:id: pluginRegistryPointer' \
  'ControlSettings.qml:|| modeOptionPointer.containsMouse' \
  'ControlSettings.qml:|| healthStatusPointer.containsMouse ? 1 : 0.62' \
  'ControlSettings.qml:|| pluginRegistryPointer.containsMouse ? 1 : 0.62' \
  'ControlSettings.qml:hoverEnabled: true' \
  'ControlSettings.qml:width: Math.min(Commons.Style.space(270), parent.width * 0.42)' \
  'ControlSettings.qml:spacing: Commons.Style.space(34)' \
  'ControlSettings.qml:+ " S · "' \
  'ControlSettings.qml:+ " O · "' \
  'ControlSettings.qml:+ " EXT"' \
  'QuickControlPage.qml:function surfaceFill(active, hovered)' \
  'QuickControlPage.qml:function surfaceBorder(active, hovered)' \
  'CompactSettingChoice.qml:property int textWeight:' \
  'ControlCenterPanel.qml:registryShibumiPluginCount:' \
  'ControlCenterPanel.qml:registryOmarchyPluginCount:' \
  'ControlCenterPanel.qml:registryExternalPluginCount:' \
  'ControlCenterPanel.qml:source.v2Border : source.v1Border' \
  'ControlSettings.qml:radius: Math.max(0, root.controller.controlRadius - 2)' \
  'ControlSettings.qml:id: activePage' \
  'ControlSettings.qml:width: parent.width' \
  'ControlSettings.qml:const acceptedPages = Array.isArray(validPageIds)' \
  'ControlCenterPanel.qml:switchPhase === "error" ? 488 : 436' \
  'ControlCenterPanel.qml:Commons.Style.space(495))'; do
  file=${quick_contract%%:*}
  label=${quick_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Quick runtime geometry drifted: $label"
done
if rg -q 'AT A GLANCE|label: "POSITION"|statRepeater|statGrid' \
    "$control_dir/QuickControlPage.qml"; then
  fail "Quick page reintroduced the oversized ambiguous status grid"
fi
for route_contract in \
  'label: "Top"' \
  'label: "Bottom"' \
  'label: "V1 · Islands"' \
  'label: "V2 · Full"' \
  'label: "V2 · Fit"' \
  'label: "V2 · Dock"' \
  'label: "V2 · Notch"' \
  'model: root.visibleShellStyleOptions' \
  '? shellStyleOptions.slice(1) : [shellStyleOptions[0]]' \
  'label: "Split all"' \
  'label: "Merge all"' \
  'readonly property int splitActionPreviewCount:' \
  'SplitLayoutChoice {' \
  'label: "Edit slots"' \
  'label: "Edit layout"' \
  'label: "Restore layout"' \
  'label: "Lock V1 layout"' \
  'label: "Lock V2 layout"' \
  'readonly property bool activeLayoutProtected:' \
  'readonly property int layoutActionCount:' \
  'readonly property bool layoutActionLabelsFit:' \
  'function toggleActiveLayoutProtection()' \
  'component LayoutProtectionToggle: Rectangle' \
  'Accessible.role: Accessible.CheckBox' \
  'Accessible.checked: selected' \
  'border.color: activeFocus ? foreground : selected' \
  'layoutToggle.focus = false' \
  'id: protectionTrack' \
  'width: (parent.width - parent.spacing * 2) / 3' \
  'id: reactorRepeater'; do
  rg -Fq "$route_contract" "$control_dir/ActiveBarSettingsPage.qml" \
    || fail "active Bars drill-down drifted: $route_contract"
done
for split_preview_contract in \
    'required property bool splitAll' \
    'Accessible.role: Accessible.Button' \
    'Accessible.description: detail' \
    'id: splitPreview' \
    'visible: root.splitAll' \
    'id: mergePreview' \
    'visible: !root.splitAll' \
    'width: Commons.Style.space(14)' \
    'width: Commons.Style.space(4)' \
    'model: 3'; do
  rg -Fq "$split_preview_contract" \
    "$control_dir/SplitLayoutChoice.qml" \
    || fail "V1 split-layout preview drifted: $split_preview_contract"
done
split_row_line="$(rg -n -m1 'id: v1SplitChoiceRow' \
  "$control_dir/ActiveBarSettingsPage.qml" | cut -d: -f1)"
position_row_line="$(rg -n -m1 'id: positionChoiceRow' \
  "$control_dir/ActiveBarSettingsPage.qml" | cut -d: -f1)"
if [[ -z "$split_row_line" || -z "$position_row_line" \
    || "$split_row_line" -ge "$position_row_line" ]]; then
  fail "V1 split actions are no longer placed above bar position"
fi
if rg -q 'SLOT CAPACITY|v2SlotRepeater|controller\.(add|remove)V2Slot|Add slots and place dividers directly' \
    "$control_dir/ActiveBarSettingsPage.qml"; then
  fail "Bars reintroduced redundant V2 layout or slot-capacity copy"
fi
if rg -q 'Choose the active V2 shape|V1 uses the Islands form|V1 supports positional slots' \
    "$control_dir/ActiveBarSettingsPage.qml"; then
  fail "Bars reintroduced redundant copy below Bar Form or Layout"
fi
for v1_slot_contract in \
  'ControlCenterPanel.qml:v1LayoutSlots' \
  'ControlCenterPanel.qml:function addV1Slot(region)' \
  'ControlCenterPanel.qml:function removeV1Slot(region)' \
  'ActiveBarSettingsPage.qml:onClicked: root.controller.beginBarEditing()'; do
  file=${v1_slot_contract%%:*}
  contract=${v1_slot_contract#*:}
  rg -Fq "$contract" "$control_dir/$file" \
    || fail "V1 slot editor contract drifted: $v1_slot_contract"
done
position_layout_line=$(rg -n -m1 '"POSITION & LAYOUT"' \
  "$control_dir/ActiveBarSettingsPage.qml" | cut -d: -f1)
split_row_line=$(rg -n -m1 'id: v1SplitChoiceRow' \
  "$control_dir/ActiveBarSettingsPage.qml" | cut -d: -f1)
v1_layout_line=$(rg -n -m1 'text: "V1 LAYOUT"' \
  "$control_dir/ActiveBarSettingsPage.qml" | cut -d: -f1)
if [[ -z $position_layout_line || -z $split_row_line || -z $v1_layout_line ]] \
    || (( split_row_line <= position_layout_line \
      || split_row_line >= v1_layout_line )); then
  fail "V1 Split/Merge is not compactly grouped under Position & Layout"
fi
if rg -Fq 'showSettingsPage("splits")' \
    "$control_dir/ActiveBarSettingsPage.qml"; then
  fail "Bars still delegates layout settings to a submenu"
fi
if rg -Fq '{ id: "splits", label: "Layout"' \
    "$control_dir/ControlSettings.qml"; then
  fail "retired Layout route is still visible beside Bars"
fi
if rg -q 'shellStyleRepeater|positionRepeater|BAR SHELL' \
    "$control_dir/BarFunctionsPage.qml"; then
  fail "Appearance still duplicates Bars shell controls"
fi

for page_file in ControlOverviewPage.qml \
    BarFunctionsPage.qml ControlMainPage.qml WorkspaceSettingsPage.qml \
    PickerSettingsPage.qml LogoSettingsPage.qml ControlSearchPage.qml \
    PluginCatalogPage.qml; do
  rg -Fq 'PageHeaderHero {' "$control_dir/$page_file" \
    || fail "page motion is missing from $page_file"
done
for header_contract in \
    'property real preferredHeight: Commons.Style.space(80)' \
    'property real previewWidth: Commons.Style.space(150)' \
    'property real actionWidth: Commons.Style.space(116)' \
    'anchors.topMargin: Commons.Style.space(5)' \
    'property bool descriptionWrap: false' \
    'wrapMode: root.descriptionWrap ? Text.WordWrap : Text.NoWrap' \
    'maximumLineCount: root.descriptionWrap ? 2 : 1' \
    'property string actionLabel: ""' \
    'signal actionRequested()'; do
  rg -Fq "$header_contract" "$control_dir/PageHeaderHero.qml" \
    || fail "shared Configure header geometry drifted: $header_contract"
done

rg -Fq 'visible: root.shibumiActive && !root.v2Active' \
  "$control_dir/ActiveBarSettingsPage.qml" \
  || fail "V1 split and gap controls are not capability-gated"
rg -Fq 'visible: root.v2Active' \
  "$control_dir/ActiveBarSettingsPage.qml" \
  || fail "V2 slot and divider controls are not capability-gated"
rg -Fq 'detail: "Add slots and dividers"' \
  "$control_dir/ActiveBarSettingsPage.qml" \
  || fail "V2 edit mode does not explain its layout capability"

for theme_contract in \
  'ControlCenterPanel.qml:surfaceOverrideEnabled: false' \
  'ControlCenterPanel.qml:? shibumiTokens.panelBackground : Commons.Color.popups.background' \
  'ControlCenterPanel.qml:? shibumiTokens.panelBorder : Commons.Color.popups.border' \
  'ControlCenterPanel.qml:? shibumiTokens.fontFamily : Commons.Style.font.family' \
  'QuickControlPage.qml:radius: root.controller.controlRadius' \
  'ConfigureLandingPage.qml:radius: root.controller.controlRadius' \
  'ActiveBarSettingsPage.qml:radius: root.controller.controlRadius' \
  'ControlSettings.qml:radius: root.controller.controlRadius' \
  'CompactSettingChoice.qml:radius: controller.controlRadius'; do
  file=${theme_contract%%:*}
  label=${theme_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Control Center theme-token contract drifted: $label"
done

if rg -q '"#[0-9a-fA-F]{6,8}"|JetBrainsMono' \
    "$control_dir/ControlCenterPanel.qml"; then
  fail "Control Center panel surface bypasses the active colors.toml theme"
fi
if rg -q 'surface(Color|BorderColor|BorderWidth|Radius)Override:' \
    "$control_dir/ControlCenterPanel.qml"; then
  fail "Control Center overrides the host panel surface contract"
fi

if rg -n 'font\.pixelSize:.*uiScale[[:space:]]*\\*[[:space:]]*0\\.' \
    "$control_dir/QuickControlPage.qml" \
    "$control_dir/ConfigureLandingPage.qml" \
    "$control_dir/ActiveBarSettingsPage.qml" \
    "$control_dir/ControlSearchPage.qml" \
    "$control_dir/ControlSettings.qml"; then
  fail "refined Control Center introduces inconsistent micro typography"
fi
rg -Fq 'font.pixelSize: Commons.Style.space(24) * root.uiScale' \
  "$control_dir/PageHeaderHero.qml" \
  || fail "shared page-title typography drifted"

rg -Fq '"omarchy", "plugin", "add", repository, "--yes"' \
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
for icon in align_vertical_center widgets brush health_and_safety download; do
  rg -Fq "\"$icon\"" "$control_dir" --glob '*.qml' \
    || fail "missing Material Symbol in V4 navigation: $icon"
done
rg -Fq 'IconText {' "$control_dir/PluginCatalogPage.qml" \
  || fail "plugin catalog does not use the shared Material Symbol renderer"
rg -Fq 'font.pixelSize: Commons.Style.font.bodySmall * root.uiScale' \
  "$control_dir/ConfigureLandingPage.qml" \
  || fail "Configure route labels are not balanced against their icons"
rg -Fq 'fill: 0' "$control_dir/ConfigureLandingPage.qml" \
  || fail "Configure route icons change shape between states"

for contract in \
  'ControlCenterPanel.qml:switchShell' \
  'ControlCenterPanel.qml:manager/shibumi-manager'; do
  file=${contract%%:*}
  label=${contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "missing V5 State Canvas contract: $label"
done
for duplicate_page in BarsPage.qml SplitSettingsPage.qml ConfigureNavigation.qml; do
  [[ ! -e $control_dir/$duplicate_page ]] \
    || fail "retired duplicate control surface remains: $duplicate_page"
done
if rg -Fq 'label: "Switch to "' \
    "$control_dir/ActiveBarSettingsPage.qml"; then
  fail "Bars still duplicates the Quick-level host switch"
fi
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

if rg -q 'setWorkspacePreference|setImagePickerStyle|setMediaPickerStyle|WORKSPACES|PICKER STYLE' \
    "$control_dir/BarFunctionsPage.qml"; then
  fail "Appearance still duplicates Workspaces or Pickers controls"
fi
rg -Fq 'setWorkspacePreference' "$control_dir/WorkspaceSettingsPage.qml" \
  || fail "workspace preferences are not owned by the Workspaces page"
rg -Fq 'workspaceStyleRepeater.count === workspaceStyleOptions.length' \
  "$control_dir/WorkspaceSettingsPage.qml" \
  || fail "Workspaces readiness does not cover all marker styles"

[[ -f $control_dir/CompactSettingChoice.qml ]] \
  || fail "shared compact choice is missing"
rg -q 'property int controlHeight: Commons\.Style\.space\(25\)' \
  "$control_dir/CompactSettingChoice.qml" \
  || fail "compact choices do not use the V1 25px height"
rg -q 'property real fontSize: Commons\.Style\.font\.bodySmall' \
  "$control_dir/CompactSettingChoice.qml" \
  || fail "compact choices do not use the readable label token"
for keyboard_contract in \
    'activeFocusOnTab: true' \
    'Accessible.role: Accessible.Button' \
    'Keys.onReturnPressed: if (enabled) root.clicked()' \
    'Keys.onSpacePressed: if (enabled) root.clicked()'; do
  rg -Fq "$keyboard_contract" "$control_dir/CompactSettingChoice.qml" \
    || fail "compact choice keyboard contract drifted: $keyboard_contract"
done

for health_contract in \
    'title: "Health"' \
    'eyebrow: "RUNTIME DIAGNOSTICS"' \
    'label: root.busy && !root.controller.healthFetching' \
    'onClicked: root.controller.runHealthChecks(false)' \
    'onClicked: root.controller.runHealthChecks(true)' \
    'return controller.accentColor("color01")' \
    'return controller.accentColor("color03")' \
    '["runtime-errors", "bar-runtime", "managed-plugins"]' \
    'return parts.length > 0 ? parts.join("  ·  ") : "Not checked yet"' \
    'verticalAlignment: Text.AlignVCenter' \
    'checkRow.interactive && checkRow.extra !== ""' \
    'readonly property int statusColumnWidth: 62' \
    'width: root.statusColumnWidth' \
    'width: Math.max(1, checkRow.width - root.rowHorizontalPadding * 2)' \
    'horizontalAlignment: Text.AlignLeft' \
    'anchors.leftMargin: 0' \
    'text: "Shibumi " + root.installedShibumiVersion' \
    'text: root.installChannelLabel' \
    'report.installOrigin === "package"' \
    '? "ARCH PACKAGE" : report.installOrigin === "checkout"' \
    '? "SOURCE CHECKOUT" : "CHECKING …"' \
    'return "SHIBUMI-HEALTH/" + String(check.id || "UNKNOWN")' \
    'function diagnosticIssueUrl(check)' \
    'Qt.openUrlExternally(diagnosticIssueUrl(check))' \
    'label: root.copiedCheckId === String(checkRow.check.id || "")' \
    '? "Copied" : "Copy"' \
    'label: "Open issue"' \
    'interactive: false' \
    'const next = requested === "preferences" ? "health"'; do
  rg -Fq "$health_contract" "$control_dir/ControlMainPage.qml" \
    "$control_dir/ControlSettings.qml" \
    || fail "Health route contract drifted: $health_contract"
done

for health_error_contract in \
    'id: "runtime-errors"' \
    'status: "error"' \
    'health.diagnosticCode(error)' \
    'health.diagnosticIssueUrl(error)' \
    'health.copyDiagnostic(error)'; do
  rg -Fq "$health_error_contract" "$repo_root/tests/control-center-smoke.qml" \
    || fail "Health error-action smoke contract drifted: $health_error_contract"
done

if rg -q 'additional checks|detailChecks|detailsOpen' \
    "$control_dir/ControlMainPage.qml"; then
  fail "Health still exposes successful implementation-detail checks"
fi
if rg -Fq 'warning(s)' "$control_dir/ControlMainPage.qml"; then
  fail "Health still exposes machine-oriented status grammar"
fi

if rg -q 'runQuickSystemAction|omarchy-system-lock|omarchy-system-reboot|omarchy-system-shutdown|systemctl.*suspend' \
    "$control_dir/ControlMainPage.qml"; then
  fail "Health still duplicates authoritative App Menu session actions"
fi
for action_contract in \
    'function runQuickSystemAction(action)' \
    'screensaver: ["omarchy-launch-screensaver", "force"]' \
    'lock: ["omarchy-system-lock"]' \
    'reboot: ["omarchy-system-reboot"]' \
    'shutdown: ["omarchy-system-shutdown"]' \
    'if (stockOmarchyHost) return false'; do
  rg -Fq "$action_contract" "$control_dir/ControlCenterPanel.qml" \
    || fail "Quick system-action delegation drifted: $action_contract"
done
rg -Fq 'function setAllSplits(enabled: string): string' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "runtime split mutation is unavailable for switch continuity checks"
[[ $(rg -l -F 'function reloadShell()' "$control_dir" \
  --glob '*.qml' | wc -l) -eq 1 ]] \
  || fail "Reload Shibumi is not owned exclusively by Quick"

for return_contract in \
    'ControlSettings.qml:readonly property bool returnOnly: controller.stockOmarchyHost === true' \
    'ControlSettings.qml:return root.returnOnly ? [] : pages' \
    'ControlSettings.qml:if (returnOnly && next !== "quick") return false' \
    'ControlSettings.qml:enabled: !root.returnOnly' \
    'QuickControlPage.qml:model: root.returnOnly ? [] :' \
    'QuickControlPage.qml:if (returnOnly) return false' \
    'QuickControlPage.qml:id: actionConnector' \
    'QuickControlPage.qml:x: shibumiActionColumn.width' \
    'QuickControlPage.qml:width: actionDeck.width - shibumiActionColumn.width' \
    'QuickControlPage.qml:context.bezierCurveTo(' \
    'QuickControlPage.qml:function onHoveredShibumiActionIndexChanged()' \
    'QuickControlPage.qml:function onHoveredSystemActionIndexChanged()' \
    'QuickControlPage.qml:leftHovered || rightHovered ? 3.2 : 2.7' \
    'ControlCenterPanel.qml:onCloseRequested: panel.handleEscape()' \
    'ControlCenterPanel.qml:if (settings.dismissEscapeState()) return true' \
    'SwitchService.qml:watchChanges: true' \
    'SwitchService.qml:running: root.busy'; do
  file=${return_contract%%:*}
  label=${return_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "return-only or Escape contract drifted: $label"
done

for label in Status Battery \
    'Bar border' 'Panel + tooltip' Border Frost Shadow \
    'Radius 12' 'Radius 6'; do
  rg -Fq "label: \"$label\"" "$control_dir" \
    --glob '*.qml' --glob '*.js' \
    || fail "missing explicit control label: $label"
done

for surface_contract in \
  'property bool v2Active: false' \
  'property bool showSurface: true' \
  'property bool showAccent: true' \
  'readonly property var effectOptions: v2Active' \
  'readonly property var radiusOptions: v2Active' \
  'readonly property int previewEffectOptionCount:' \
  'height: Commons.Style.space(root.v2Active ? 30 : 52)' \
  'spacing: Commons.Style.space(8)' \
  'controlHeight: effectRow.height' \
  'sourceComponent: root.v2Active ? compactEffect : previewEffect' \
  'SurfaceEffectChoice {' \
  'uiScale: root.uiScale' \
  'effectRepeater.count === (showSurface ? effectOptions.length : 0)' \
  'radiusRepeater.count === (showSurface ? radiusOptions.length : 0)' \
  'colorRepeater.count === (showAccent ? colorOptions.length : 0)'; do
  rg -Fq "$surface_contract" "$control_dir/BarSurfaceSettings.qml" \
    || fail "version-aware bar-surface contract drifted: $surface_contract"
done
for effect_preview_contract in \
    'required property string effectKey' \
    'Accessible.role: Accessible.CheckBox' \
    'Accessible.checked: selected' \
    'visible: root.effectKey === "frost"' \
    'Commons.Util.alpha(root.controller.marketPanelRaised, 0.68)' \
    'visible: root.effectKey === "shadow"' \
    'id: frostPattern' \
    'root.effectKey === "border"' \
    '|| root.effectKey === "frost" ? 1 : 0'; do
  rg -Fq "$effect_preview_contract" \
    "$control_dir/SurfaceEffectChoice.qml" \
    || fail "V1 surface-effect preview drifted: $effect_preview_contract"
done
rg -Fq 'v2Active: root.v2Active' \
  "$control_dir/ActiveBarSettingsPage.qml" \
  || fail "active bar version is not forwarded to Bar Surface"
for split_surface_contract in \
    'id: primaryControlRow' \
    'id: positionChoiceRow' \
    'id: barAccentSettings' \
    'showSurface: true' \
    'showAccent: false' \
    'showSurface: false' \
    'showAccent: true'; do
  rg -Fq "$split_surface_contract" \
    "$control_dir/ActiveBarSettingsPage.qml" \
    || fail "compact Position/Surface split drifted: $split_surface_contract"
done
if rg -Fq 'fontSize: Commons.Style.font.caption' \
    "$control_dir/BarSurfaceSettings.qml"; then
  fail "bar-surface buttons retain a smaller typography override"
fi
for active_bar_density in \
    'height: Commons.Style.space(62)' \
    'font.pixelSize: Commons.Style.space(20) * root.uiScale'; do
  rg -Fq "$active_bar_density" \
    "$control_dir/ActiveBarSettingsPage.qml" \
    || fail "active-bar status card is not compact: $active_bar_density"
done
if rg -Fq 'text: "ACTIVE BAR"' \
    "$control_dir/ActiveBarSettingsPage.qml"; then
  fail "Bars repeats the already explicit V1/V2 active state"
fi
position_line=$(rg -n -m1 'text: root.v2Active ? "POSITION"' -F \
  "$control_dir/ActiveBarSettingsPage.qml" | cut -d: -f1)
surface_line=$(rg -n -m1 'id: barSurfaceSettings' \
  "$control_dir/ActiveBarSettingsPage.qml" | cut -d: -f1)
form_line=$(rg -n -m1 'SectionLabel \{ text: "BAR FORM" \}' \
  "$control_dir/ActiveBarSettingsPage.qml" | cut -d: -f1)
if (( surface_line <= position_line || surface_line >= form_line )); then
  fail "Bar Surface is not directly aligned with Position"
fi

for color_contract in \
  '{ value: "color01", label: "01" }' \
  '{ value: "color02", label: "02" }' \
  '{ value: "color03", label: "03" }' \
  '{ value: "color04", label: "04" }' \
  '{ value: "color05", label: "05" }' \
  '{ value: "color06", label: "06" }' \
  '{ value: "color07", label: "07" }' \
  '{ value: "foreground", label: "FG" }'; do
  rg -Fq "$color_contract" "$control_dir/BarSurfaceSettings.qml" \
    || fail "missing V1 palette choice: $color_contract"
done
rg -Fq 'columns: 8' "$control_dir/BarSurfaceSettings.qml" \
  || fail "Bars palette picker is not a compact eight-column strip"
rg -Fq 'activeFocusOnTab: true' "$control_dir/BarSurfaceSettings.qml" \
  || fail "Bars palette choices are not keyboard-focusable"
if rg -Fq '{ value: "color08", label: "08" }' \
    "$control_dir/BarSurfaceSettings.qml"; then
  fail "Bars exposes color08 beyond the accepted V1/V2 palette contract"
fi
rg -Fq 'radius: root.controller.controlRadius' \
  "$control_dir/BarSurfaceSettings.qml" \
  || fail "V1 palette swatches do not follow the live radius setting"
rg -Fq 'controlHeight: radiusRow.height' \
  "$control_dir/BarSurfaceSettings.qml" \
  || fail "V1 surface and radius controls do not share one row height"
rg -Fq 'root.controller.contrastColor(swatch.modelData.value)' \
  "$control_dir/BarSurfaceSettings.qml" \
  || fail "V1 palette swatches lack contrast-aware labels"
if rg -Fq '{ value: "red"' "$control_dir/BarSurfaceSettings.qml" \
    || rg -Fq '{ value: "accent"' "$control_dir/BarSurfaceSettings.qml"; then
  fail "retired pre-V1 palette choices remain"
fi

for contract in 'THEMES & WALLPAPERS' 'SCREENSHOTS & VIDEOS' \
    'value: "omarchy", label: "Omarchy · Default"'; do
  rg -Fq "$contract" "$control_dir/PickerSettingsPage.qml" \
    || fail "missing split picker setting: $contract"
done
image_picker_block=$(sed -n '/id: imagePickerRepeater/,/delegate:/p' \
  "$control_dir/PickerSettingsPage.qml")
if rg -Fq 'value: "carousel"' <<<"$image_picker_block"; then
  fail "Carousel remains selectable for themes and wallpapers"
fi
rg -Fq 'readonly property bool ready: imagePickerRepeater.count === 3' \
  "$control_dir/PickerSettingsPage.qml" \
  || fail "theme/wallpaper picker exposes more than three choices"
rg -U -q 'id: mediaPickerRepeater[\s\S]*model: \[\n[[:space:]]*\{ value: "carousel", label: "Carousel · Default" \},\n[[:space:]]*\{ value: "tanzaku", label: "Tanzaku" \},\n[[:space:]]*\{ value: "hearthstone", label: "Hearthstone" \}' \
  "$control_dir/PickerSettingsPage.qml" \
  || fail "media picker choices are not ordered Carousel, Tanzaku, Hearthstone"
[[ -f $control_dir/PickerPreviewCard.qml ]] \
  || fail "picker preview card is missing"
if [[ $(rg -F -c 'delegate: PickerPreviewCard {' \
    "$control_dir/PickerSettingsPage.qml") -ne 2 ]]; then
  fail "picker choices remain text-only controls"
fi
for picker_preview in \
    'function drawOmarchy(context, w, h)' \
    'function drawCarousel(context, w, h)' \
    'function drawTanzaku(context, w, h)' \
    'function drawHearthstone(context, w, h)' \
    'root.styleValue === "carousel") drawCarousel(context, w, h)' \
    'root.styleValue === "tanzaku") drawTanzaku(context, w, h)'; do
  rg -Fq "$picker_preview" "$control_dir/PickerPreviewCard.qml" \
    || fail "missing picker preview contract: $picker_preview"
done
omarchy_preview_block=$(sed -n \
  '/function drawOmarchy(context, w, h)/,/function drawCarousel(context, w, h)/p' \
  "$control_dir/PickerPreviewCard.qml")
rg -Fq 'drawCarousel(context, w, h)' <<<"$omarchy_preview_block" \
  || fail "Omarchy Default does not reuse the Carousel schematic"
carousel_preview_block=$(sed -n \
  '/function drawCarousel(context, w, h)/,/function drawTanzaku(context, w, h)/p' \
  "$control_dir/PickerPreviewCard.qml")
for carousel_shape in 'skewedCard(context' 'const sliceWidth = w * 0.09' \
    'const skew = w * 0.025' 'focusWidth, focusHeight, skew, true'; do
  rg -Fq "$carousel_shape" <<<"$carousel_preview_block" \
    || fail "Carousel schematic lost its skewed slices: $carousel_shape"
done
tanzaku_preview_block=$(sed -n \
  '/function drawTanzaku(context, w, h)/,/function hearthCard(/p' \
  "$control_dir/PickerPreviewCard.qml")
rg -Fq 'const sliceWidth = w * 0.055' <<<"$tanzaku_preview_block" \
  || fail "Tanzaku did not receive the former focus-and-slice schematic"
if rg -q 'Image[[:space:]]*\{|previewSource' \
    "$control_dir/PickerPreviewCard.qml"; then
  fail "picker schematic previews unexpectedly load image content"
fi

[[ -f $control_dir/WorkspaceMarkerPreviewCard.qml ]] \
  || fail "workspace marker preview card is missing"
rg -Fq 'delegate: WorkspaceMarkerPreviewCard {' \
  "$control_dir/WorkspaceSettingsPage.qml" \
  || fail "workspace marker styles remain text-only controls"
for marker_preview in \
    'root.styleValue === "default"' \
    'root.styleValue === "numbers"' \
    'root.styleValue === "magic"' \
    'root.styleValue === "kanji"' \
    'root.styleValue === "rings"' \
    'root.styleValue === "aurora"' \
    'root.styleValue === "pacman"'; do
  rg -Fq "$marker_preview" "$control_dir/WorkspaceMarkerPreviewCard.qml" \
    || fail "workspace marker preview is missing: $marker_preview"
done

for source_contract in \
  'readonly property real filterFontSize:' \
  'font.pixelSize: root.filterFontSize' \
  'font.weight: root.filterFontWeight' \
  'verticalAlignment: Text.AlignVCenter'; do
  rg -Fq "$source_contract" "$control_dir/ProviderFilter.qml" \
    || fail "Widgets Source typography is not baseline-aligned: $source_contract"
done
if rg -Fq 'anchors.verticalCenterOffset:' "$control_dir/ProviderFilter.qml"; then
  fail "Widgets Source options retain a manual baseline offset"
fi

for provider in All Shibumi 'Omarchy Quattro' Third-party; do
  rg -Fq "\"$provider\"" "$control_dir/ProviderFilter.qml" \
    || fail "missing widget provider filter: $provider"
done
for plugin_contract in \
    'spacing: Commons.Style.space(10)' \
    'title: "FILTER"' \
    '"All", "Active", "Shibumi", "Omarchy Quattro", "Third-party"' \
    'title: "PROVIDER SWITCHES"' \
    'title: "ACTIVE"' \
    'title: "AVAILABLE"' \
    'controller.accentColor("color03")' \
    'controller.accentColor("color02")' \
    'countColor: root.activeCountColor' \
    'countColor: root.availableCountColor' \
    'text: "UNDO"' \
    'id: undoButton' \
    'undoPointer.containsMouse' \
    'controller.accentColor("color01")' \
    'id: feedbackCountdown' \
    'duration: 7000' \
    'paused: feedbackHover.hovered || undoButton.activeFocus' \
    'Math.max(0, Math.min(1, feedbackProgress))' \
    'Commons.Style.space(4), Number(controller.controlRadius || 0))' \
    'statusSlot.width - 2 * feedbackProgressInset' \
    'id: feedbackProgressBar' \
    'anchors.leftMargin: root.feedbackProgressInset' \
    'anchors.bottomMargin: Commons.Style.space(2)' \
    '* root.boundedFeedbackProgress' \
    'id: pluginSearch' \
    'height: Commons.Style.space(34)' \
    'border.color: root.controller.controlBorderColor' \
    'Find plugins, tags, authors, or providers…' \
    'property bool activeExpanded: false' \
    'property bool availableExpanded: false' \
    'function requestPluginRemoval(entry)' \
    'function confirmPluginRemoval()' \
    'text: "REMOVE"' \
    'interval: 7000' \
    'function undoLastChange()' \
    'undoMode === "provider-snapshot"' \
    'controller.restoreProviderUndoSnapshot(undoProviderSnapshot)' \
    'displacedProviderIds.length > 0' \
    'controller.setProviderGroupStates(undoGroupStates)' \
    'controller.restoreShibumiProviderStates(undoGroupStates)' \
    'controller.restoreShibumiProviders(undoGroups)' \
    'actionLabel: "Add plugin"' \
    'onActionRequested: root.controller.openPluginInstaller()' \
    'secondaryActionLabel: root.favoritesOnly ? "" : "Check plugins"' \
    'secondaryActionGlyph: "refresh"' \
    'secondaryActionStatusText: root.favoritesOnly ? ""' \
    'secondaryActionDescription: root.favoritesOnly ? ""' \
    'controller.pluginUpdateShortStatusText' \
    'controller.pluginUpdateStatusText' \
    'function syncPluginUpdateConsumer()' \
    'service.acquireConsumer()' \
    'service.releaseConsumer()' \
    'Component.onDestruction:' \
    'actionWidth: Commons.Style.space(132)' \
    'onSecondaryActionRequested: root.controller.openPluginUpdater()' \
    'function providerCatalogCount(provider)' \
    'shibumiCount: root.shibumiProviderCount' \
    'omarchyCount: root.omarchyProviderCount' \
    'thirdPartyCount: root.thirdPartyProviderCount'; do
  rg -Fq "$plugin_contract" "$control_dir/PluginCatalogPage.qml" \
    || fail "plugin provider-feedback contract drifted: $plugin_contract"
done
for provider_summary_contract in \
    'assets/shibumi-icon-hikiryo.svg' \
    'file:///usr/share/omarchy/icon.png' \
    'INSTALLED SHIBUMI PLUGINS' \
    'COMPATIBLE OMARCHY WIDGETS' \
    'THIRD-PARTY' \
    'onCountKeyChanged: if (active) Qt.callLater(runGloss)' \
    'visible: root.reducedMotion' \
    'Commons.Util.alpha(root.accent, 0.15)' \
    'loops:'; do
  if [[ $provider_summary_contract == loops: ]]; then
    rg -Fq 'loops:' "$control_dir/PluginProviderSummary.qml" \
      && fail "plugin provider gloss must not loop"
    continue
  fi
  rg -Fq "$provider_summary_contract" \
    "$control_dir/PluginProviderSummary.qml" \
    || fail "plugin provider summary drifted: $provider_summary_contract"
done
[[ $(rg -c '^    ProviderRow \{' \
  "$control_dir/PluginProviderSummary.qml") -eq 3 ]] \
  || fail "plugin provider summary must render three equal rows"
for plugin_height_contract in \
    'ControlSettings.qml:readonly property bool compactPluginsPage:' \
    'ControlSettings.qml:configureDetailPage === "plugins"' \
    'ControlSettings.qml:readonly property real compactPluginsPanelHeight:' \
    'ControlCenterPanel.qml:: settings.compactPluginsPage' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactPluginsPanelHeight,'; do
  file=${plugin_height_contract%%:*}
  label=${plugin_height_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Plugins compact panel-height contract drifted: $label"
done
for plugin_update_contract in \
    'function checkPluginUpdates(force)' \
    'effectivePluginUpdateService.check(force === true)' \
    'function openPluginUpdater()' \
    'pluginUpdateCheckRunning) return false' \
    '"omarchy-launch-floating-terminal-with-presentation"' \
    'pluginUpdateCommand'; do
  rg -Fq "$plugin_update_contract" "$control_dir/ControlCenterPanel.qml" \
    || fail "manual plugin update action drifted: $plugin_update_contract"
done
rg -Fq 'hostShell.serviceFor("hancore.shibumi.control-center")' \
  "$control_dir/BarWidget.qml" \
  || fail 'plugin update status owner is not shared through the host service'
jq -e '
  (.kinds | index("service")) != null and
  .entryPoints.service == "PluginUpdateService.qml"
' "$control_dir/manifest.json" >/dev/null \
  || fail 'control-center manifest does not declare its shared update service'
for plugin_update_service_contract in \
    'updateCheck.command = [' \
    'command, "--list"' \
    '"PLUGIN_UPDATE_COUNT"' \
    '"PLUGIN_CHECKED_COUNT"' \
    '"PLUGIN_UNMANAGED_COUNT"' \
    '"PLUGIN_FETCH_FAILED_COUNT"' \
    '? Date.now() : 0' \
    'function acquireConsumer()' \
    'function releaseConsumer()' \
    'updateCheck.running = false' \
    'function invalidate(rescan)' \
    'const stale = finishedEpoch !== root.invalidationEpoch' \
    'updateCount + " available"'; do
  rg -Fq "$plugin_update_service_contract" \
    "$control_dir/PluginUpdateService.qml" \
    || fail "plugin update status service drifted: $plugin_update_service_contract"
done
for stacked_action_contract in \
    'anchors.left: root.secondaryActionLabel !== ""' \
    'anchors.left: parent.left' \
    'anchors.leftMargin: Commons.Style.space(10)' \
    'property string secondaryActionStatusText: ""' \
    'property string secondaryActionDescription: ""' \
    'Accessible.description: root.secondaryActionDescription' \
    'anchors.top: secondaryAction.bottom' \
    'text: root.secondaryActionStatusText'; do
  rg -Fq "$stacked_action_contract" "$control_dir/PageHeaderHero.qml" \
    || fail "stacked header actions lost their shared left edge"
done
[[ $(rg -c 'horizontalAlignment: Text.AlignLeft' \
  "$control_dir/PageHeaderHero.qml") -eq 2 ]] \
  || fail "stacked header action labels must share one text edge"
[[ $(rg -c 'width: Commons.Style.space\(17\) \* root.uiScale' \
  "$control_dir/PageHeaderHero.qml") -eq 2 ]] \
  || fail "stacked header action icons must share one fixed column"
for provider_model in \
    'const replacementGroups = group === "" && bar' \
    'replacementGroups: replacementGroups' \
    'replacementTargetStates: replacementTargetStates' \
    'conflictingProviderIds: conflictingProviderIds' \
    'conflictingProviderStates: conflictingProviderStates' \
    'replacementLabel: group === "" && bar' \
    'replacementTargetEnabled:' \
    'replacementInEffect: false' \
    'replacedByIds: []' \
    'removable: manifest.__isFirstParty !== true && !suiteManaged' \
    'function removePlugin(pluginId)' \
    '["omarchy", "plugin", "remove", id, "--yes"]' \
    'id: pluginRemoval' \
    'Control Center rejected non-removable plugin:' \
    'function restoreShibumiProviders(groupValues)' \
    'function restoreShibumiProviderStates(stateValues)' \
    'function providerUndoSnapshot(pluginId)' \
    'function restoreProviderUndoSnapshot(snapshotValue)' \
    'function setProviderGroupStates(stateValues)' \
    'removalPluginWasInBar = entry.barWidget === true' \
    'panel.bar.removeBarWidgetAndRestoreFamilies(' \
    'Plugin removed, but bar provider cleanup failed.' \
    'function restoreShibumiProvider(groupId)'; do
  rg -Fq "$provider_model" "$control_dir/ControlCenterPanel.qml" \
    || fail "plugin provider model drifted: $provider_model"
done
for tile_contract in \
    'property bool replaced: false' \
    'text: root.inserted ? "ACTIVE"' \
    ': root.replaced ? "REPLACED" : "AVAILABLE"' \
    '? "Replaced by " + root.replacedBy' \
    'property bool removable: false' \
    'controller.accentColor("color03")' \
    'controller.accentColor("color01")' \
    ': root.replaced ? root.replacedStatusColor : root.foreground' \
    'text: root.removalBusy ? "hourglass_top" : "delete"' \
    'onClicked: root.removeRequested()'; do
  rg -Fq "$tile_contract" "$control_dir/WidgetModuleTile.qml" \
    || fail "plugin replacement tile drifted: $tile_contract"
done
tile_pointer_line=$(rg -n -F 'id: pointer' \
  "$control_dir/WidgetModuleTile.qml" | head -1 | cut -d: -f1)
tile_row_line=$(rg -n -F 'id: actionRow' \
  "$control_dir/WidgetModuleTile.qml" | head -1 | cut -d: -f1)
tile_favorite_line=$(rg -n -F 'id: favoritePointer' \
  "$control_dir/WidgetModuleTile.qml" | head -1 | cut -d: -f1)
[[ -n $tile_pointer_line && -n $tile_row_line && -n $tile_favorite_line \
    && $tile_pointer_line -lt $tile_row_line \
    && $tile_row_line -lt $tile_favorite_line ]] \
  || fail "plugin tile actions can leak into the card toggle"
[[ -f $control_dir/PluginSectionHeader.qml ]] \
  || fail "collapsible plugin section header is missing"
for section_contract in \
    'property color countColor: foreground' \
    'text: root.title' \
    'text: root.count' \
    'color: root.countColor' \
    'root.expanded ? "expand_more" : "chevron_right"' \
    'onClicked: root.toggled()'; do
  rg -Fq "$section_contract" "$control_dir/PluginSectionHeader.qml" \
    || fail "plugin section hierarchy drifted: $section_contract"
done
if rg -Fq 'height: visible ? Commons.Style.space(48) : 0' \
    "$control_dir/PluginCatalogPage.qml"; then
  fail "plugin feedback still shifts the catalog layout"
fi
for suite_boundary in \
    'userToggleable: barWidget && (!suiteManaged || group !== "")' \
    'styleAvailable: true' \
    'V1 has no free extension slot.' \
    'Control Center rejected suite-internal plugin toggle:' \
    '? String(manifest.barWidget.defaultSection) : "center"' \
    'setPluginBarWidgetEnabled(id, enabled === true, section)'; do
  rg -Fq "$suite_boundary" "$control_dir/ControlCenterPanel.qml" \
    || fail "plugin-manager suite boundary drifted: $suite_boundary"
done
for parity_contract in \
    'bar.layoutContains(id)' \
    'setPluginBarWidgetEnabled(id, enabled === true, section)' \
    'property string pluginActionError: ""'; do
  rg -Fq "$parity_contract" "$control_dir/ControlCenterPanel.qml" \
    || fail "V1/V2 plugin management parity drifted: $parity_contract"
done
rg -Fq 'controller.pluginActionError' \
  "$control_dir/PluginCatalogPage.qml" \
  || fail "plugin capacity failure is not actionable in the catalog"
for widget_surface in PluginCatalogPage.qml ControlSettings.qml; do
  rg -Fq 'entry.userToggleable === true' "$control_dir/$widget_surface" \
    || fail "$widget_surface exposes suite-internal helper plugins"
  rg -Fq 'entry.styleAvailable !== false' "$control_dir/$widget_surface" \
    || fail "$widget_surface exposes plugins unsupported by the active style"
done
if rg -q 'model: 5' "$control_dir/WidgetModuleTile.qml"; then
  fail "decorative connector contacts remain on widget tiles"
fi
for visual_contract in \
    'value: "icon", label: "Icon"' \
    'value: "full", label: "Icon + text"' \
    'value: "text", label: "Text"' \
    'text: "PRESENTATION"' \
    'id: integratedPreviewContent' \
    'text: "FILL COLOR"' \
    'text: "OUTLINE COLOR"' \
    'root.displayModeLabel(' \
    'root.widgetPresentationLabel(widgetRow.option.group,' \
    '{ value: "none", label: "None" }' \
    '{ value: "fill", label: "Fill" }' \
    '{ value: "border", label: "Outline" }' \
    '{ value: "both", label: "Both" }' \
    'visible: surfaceRow.modelData.value !== "none"' \
    'text: "CONTENT TONE"' \
    'text: "GEOMETRY"' \
    'text: "SHAPE"' \
    'text: "INNER SPACE · AROUND CONTENT"' \
    'text: "OPACITY"' \
    'text: "OUTLINE"' \
    '{ value: 0.5, label: "0.5 px" }' \
    '{ value: 1, label: "1 px" }' \
    '{ value: 1.5, label: "1.5 px" }' \
    '{ value: 2, label: "2 px" }'; do
  rg -Fq "$visual_contract" "$control_dir/WidgetAppearanceWorkbench.qml" \
    || fail "Appearance is missing widget visual control: $visual_contract"
done
for workspace_contract in 'label: "Magic"' 'label: "Kanji"' \
    'label: "Frame"' 'label: "Aurora"'; do
  rg -Fq "$workspace_contract" "$control_dir/WorkspaceSettingsPage.qml" \
    || fail "Workspaces is missing visual control: $workspace_contract"
done
if rg -Fq 'Each marker is a workspace.' \
    "$control_dir/WorkspaceSettingsPage.qml"; then
  fail "Workspaces reintroduced redundant marker explanation copy"
fi
if rg -Fq 'concat(v2Active ?' "$control_dir/WorkspaceSettingsPage.qml"; then
  fail "Workspace marker choices still differ between V1 and V2"
fi
for radius_contract in \
    'readonly property real numberMarkerRadius:' \
    'readonly property real frameMarkerRadius:'; do
  rg -Fq "$radius_contract" \
    "$control_dir/WorkspaceMarkerPreviewCard.qml" \
    || fail "Workspace preview is missing radius contract: $radius_contract"
done
rg -Fq 'label: "Edit layout"' \
  "$control_dir/ActiveBarSettingsPage.qml" \
  || fail "V2 settings are missing the direct divider editor"
rg -Fq 'function beginBarEditing()' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "control center cannot enter bar edit mode"
rg -Fq 'visible: root.shibumiActive && !root.v2Active' \
  "$control_dir/ActiveBarSettingsPage.qml" \
  || fail "V1-only split and gap controls are not capability-gated"
rg -Fq 'detail: "Add slots and dividers"' \
  "$control_dir/ActiveBarSettingsPage.qml" \
  || fail "V2 layout action does not explain its capability contract"
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
    'readonly property var overviewOptions: buildOverviewOptions()' \
    'readonly property var activeOptions: overviewOptions.active' \
    'readonly property var inactiveOptions: overviewOptions.inactive' \
    'readonly property var editableOptions: activeOptions.concat(inactiveOptions)' \
    'function buildActiveOptions()' \
    'function buildInactiveOptions(activeValues)' \
    'function buildOverviewOptions()' \
    'void(controller.activeWidgetOrder)' \
    'title: "ACTIVE WIDGETS"' \
    'title: "INACTIVE WIDGETS"' \
    'model: root.activeOptions' \
    'model: root.inactiveOptions' \
    'id: inspectorCard' \
    'property bool detailOpen: false' \
    'signal widgetRequested(string groupId, string pluginId)' \
    'signal overviewRequested()' \
    'text: "ALL WIDGETS"' \
    'visible: !root.detailOpen' \
    'visible: root.detailOpen' \
    'interactive: false' \
    'columns: 3' \
    'columns: root.inactiveOptions.length <= 5 ? 1 : 2' \
    'readonly property var activeGroupIds:' \
    'function settingsGroupForCatalogGroup(groupValue)' \
    'pluginId !== "" ? "G:" + pluginId : group' \
    'component WidgetOptionTile: Rectangle' \
    'component WidgetSectionHeader: Item' \
    'component WidgetMoveAction: FocusScope' \
    'function setWidgetActive(option, enabled)' \
    'controller.setPluginEnabled(pluginId, enabled === true)' \
    'id: editorPointer' \
    'id: moveAction' \
    'onRequested: root.setWidgetActive(' \
    'text: moveActionControl.locked ? "lock"' \
    ': moveActionControl.active ? "arrow_forward" : "arrow_back"' \
    'Keys.onRightPressed:' \
    'Keys.onLeftPressed:' \
    'id: contentModeChoices' \
    'id: profileModeChoices' \
    'id: contentToneChoices' \
    'id: surfaceModeChoices' \
    'id: outlineChoices' \
    'id: fillColorPalette' \
    'id: outlineColorPalette' \
    'id: opacityChoices' \
    'enabled: root.selectedHasBorder' \
    'component GroupDivider: Rectangle' \
    'component SurfaceChoiceList: Column' \
    'component ColorPalette: Grid' \
    'component RadioChoiceList: Column' \
    'component OpacityChoiceList: Column' \
    'component ShapeRow: Row' \
    'component ShapeChoice: Rectangle' \
    'component SpacingRow: Row' \
    'component SpacingChoice: Rectangle' \
    'readonly property real choiceControlHeight:' \
    'readonly property real choiceListHeight:' \
    'readonly property real choiceRowHeight:' \
    'readonly property real choiceFontSize:' \
    'function widgetAppearanceChanged(groupValue)' \
    'function widgetAppearanceIndicatorColor(groupValue)' \
    'return controller.accentColor("color03")' \
    'id: appearanceStateDot' \
    'visible: widgetRow.active && widgetRow.appearanceChanged' \
    'root.controller.resetGroupAppearance('; do
  rg -Fq "$workbench_contract" "$workbench" \
    || fail "widget Appearance workbench contract drifted: $workbench_contract"
done
if rg -Fq 'Inactive ·' "$workbench"; then
  fail "inactive Icons tiles redundantly repeat their section state"
fi
if rg -Fq 'component WidgetStateToggle' "$workbench"; then
  fail "Icons still uses redundant state switches instead of direct movement"
fi
if rg -Fq 'drag.target: widgetRow' "$workbench"; then
  fail "Icons still uses ambiguous drag movement instead of split actions"
fi
if rg -Fq 'text: "FINISH"' "$workbench"; then
  fail "Icons still exposes the redundant Finish section"
fi
for compact_surface_row_contract in \
    'width: (parent.width - parent.spacing * 2) / 3' \
    'width: root.v1LayoutActive ? parent.width' \
    'height: root.choiceRowHeight * 4' \
    'readonly property real surfaceChoiceHeight: choiceRowHeight * 4'; do
  rg -Fq "$compact_surface_row_contract" "$workbench" \
    || fail "Surface/Outline/Opacity row alignment drifted: $compact_surface_row_contract"
done
choice_height_uses=$(rg -c 'height: root\.choiceControlHeight' "$workbench")
choice_font_uses=$(rg -c 'font\.(pixelSize|Size): root\.choiceFontSize' \
  "$workbench")
[[ $choice_height_uses -ge 4 ]] \
  || fail "Icons visual choices no longer share one control height"
[[ $choice_font_uses -ge 5 ]] \
  || fail "Icons visual choices no longer share one font size"
for content_cycle_contract in \
    'BarFunctionsPage.qml:readonly property string selectedWidgetMode:' \
    'BarFunctionsPage.qml:function cycleSelectedWidgetMode()' \
    'WidgetAppearanceWorkbench.qml:id: contentModeChoices' \
    'WidgetAppearanceWorkbench.qml:onChosen: value => root.setWidgetMode(value)' \
    'control-center-smoke.qml:V1 Default/Compact choice did not cycle'; do
  file=${content_cycle_contract%%:*}
  label=${content_cycle_contract#*:}
  if [[ $file == control-center-smoke.qml ]]; then
    target="$repo_root/tests/$file"
  else
    target="$control_dir/$file"
  fi
  rg -Fq "$label" "$target" \
    || fail "single Content cycle contract drifted: $label"
done
for profile_icon_contract in \
    'WidgetAppearanceWorkbench.qml:{ value: "icon", label: "Icon" }' \
    'WidgetAppearanceWorkbench.qml:{ value: "full", label: "Icon + text" }' \
    'WidgetAppearanceWorkbench.qml:{ value: "text", label: "Text" }' \
    'WidgetAppearanceWorkbench.qml:readonly property var mediaStyleOptions:' \
    'WidgetAppearanceWorkbench.qml:{ value: "full", label: "Full" }' \
    'WidgetAppearanceWorkbench.qml:readonly property var v1CompactGroupIds:' \
    'WidgetAppearanceWorkbench.qml:if (catalogGroup === "G9") return mediaStyleOptions' \
    'WidgetAppearanceWorkbench.qml:if (controller.v2LayoutActive === true) return displayModeOptions' \
    'WidgetAppearanceWorkbench.qml:{ value: "full", label: "Default", enabled: true }' \
    'WidgetAppearanceWorkbench.qml:{ value: "icon", label: "Compact", enabled: true }' \
    'WidgetAppearanceWorkbench.qml:readonly property bool selectedV1Appearance:' \
    'WidgetAppearanceWorkbench.qml:id: mediaContentToneChoices' \
    'WidgetAppearanceWorkbench.qml:enabled: radioList.enabled && radioRow.available' \
    'WidgetAppearanceWorkbench.qml:function isShibumiWidgetOption(source)' \
    'WidgetAppearanceWorkbench.qml:|| !isShibumiWidgetOption(source)' \
    'WidgetAppearanceWorkbench.qml:&& !root.v1LayoutActive' \
    'ControlCenterPanel.qml:stateService.groupAppearanceSettingForVariant' \
    'ControlCenterPanel.qml:stateService.setGroupAppearanceSettingForVariant' \
    'ControlCenterPanel.qml:stateService.resetGroupAppearanceForVariant' \
    'ControlCenterPanel.qml:stateService.resetAllGroupAppearancesForVariant'; do
  file=${profile_icon_contract%%:*}
  label=${profile_icon_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "V1/V2 icon capability boundary drifted: $label"
done
for compact_cycle_contract in \
    'BarFunctionsPage.qml:function cycleSelectedWidgetSurface()' \
    'WidgetAppearanceWorkbench.qml:id: surfaceModeChoices' \
    'WidgetAppearanceWorkbench.qml:onChosen: value => root.setWidgetSurface(value)' \
    'control-center-smoke.qml:single Surface button did not cycle its value'; do
  file=${compact_cycle_contract%%:*}
  label=${compact_cycle_contract#*:}
  if [[ $file == control-center-smoke.qml ]]; then
    target="$repo_root/tests/$file"
  else
    target="$control_dir/$file"
  fi
  rg -Fq "$label" "$target" \
    || fail "compact widget cycle contract drifted: $label"
done
for radio_choice_contract in \
    'id: outlineChoices' \
    'id: contentToneChoices' \
    'id: radioMarker' \
    'visible: radioRow.selected' \
    'font.pixelSize: root.choiceFontSize' \
    'font.weight: radioRow.selected ? Font.DemiBold : Font.Normal'; do
  rg -Fq "$radio_choice_contract" "$workbench" \
    || fail "compact radio-choice contract drifted: $radio_choice_contract"
done
for outline_color_contract in \
    'readonly property string selectedOutlineColor:' \
    '"widgetBorderColor"' \
    'id: fillColorPalette' \
    'id: outlineColorPalette' \
    'text: "FILL COLOR"' \
    'text: "OUTLINE COLOR"' \
    '&& root.selectedHasFill' \
    '&& root.selectedHasBorder' \
    'component ColorPalette: Grid'; do
  rg -Fq "$outline_color_contract" "$workbench" \
    || fail "independent fill/outline color choice drifted: $outline_color_contract"
done
for preview_center_contract in \
    'id: previewGlyph' \
    'id: previewLabel' \
    'anchors.verticalCenter: parent.verticalCenter'; do
  rg -Fq "$preview_center_contract" "$workbench" \
    || fail "integrated widget preview centering drifted: $preview_center_contract"
done
for opacity_cycle_contract in \
    'BarFunctionsPage.qml:readonly property real selectedWidgetOpacity:' \
    'BarFunctionsPage.qml:function cycleSelectedWidgetOpacity()' \
    'WidgetAppearanceWorkbench.qml:id: opacityChoices' \
    'WidgetAppearanceWorkbench.qml:component OpacityChoiceList: Column' \
    'WidgetAppearanceWorkbench.qml:{ value: 1, label: "100%" }' \
    'WidgetAppearanceWorkbench.qml:{ value: 0.8, label: "80%" }' \
    'WidgetAppearanceWorkbench.qml:{ value: 0.6, label: "60%" }' \
    'WidgetAppearanceWorkbench.qml:{ value: 0.4, label: "40%" }' \
    'control-center-smoke.qml:single Opacity button did not cycle its value'; do
  file=${opacity_cycle_contract%%:*}
  label=${opacity_cycle_contract#*:}
  if [[ $file == control-center-smoke.qml ]]; then
    target="$repo_root/tests/$file"
  else
    target="$control_dir/$file"
  fi
  rg -Fq "$label" "$target" \
    || fail "single Opacity cycle contract drifted: $label"
done
color_palette_line=$(rg -n -m1 'text: "FILL COLOR"' "$workbench" \
  | cut -d: -f1)
content_line=$(rg -n -m1 'text: "PRESENTATION"' "$workbench" | cut -d: -f1)
[[ -n $color_palette_line && -n $content_line \
    && $color_palette_line -lt $content_line ]] \
  || fail "Fill/Outline Color must sit directly before Content"
if rg -Fq 'visible: modeChoice.selected' "$workbench" \
    || rg -Fq 'visible: surfaceChoice.selected' "$workbench"; then
  fail "Icons choice buttons must not use palette-style selection underlines"
fi
for icons_drilldown_contract in \
    'BarFunctionsPage.qml:property bool widgetDetailOpen: false' \
    'BarFunctionsPage.qml:readonly property int inactiveWidgetCount:' \
    'BarFunctionsPage.qml:readonly property bool selectedWidgetActive:' \
    'BarFunctionsPage.qml:function openWidgetDetails(groupId, pluginId)' \
    'BarFunctionsPage.qml:function setWidgetEnabled(groupId, enabled)' \
    'BarFunctionsPage.qml:function widgetUsesCustomAppearance(groupId)' \
    'BarFunctionsPage.qml:function showWidgetOverview()' \
    'BarFunctionsPage.qml:visible: !root.widgetDetailOpen' \
    'BarFunctionsPage.qml:detailOpen: root.widgetDetailOpen' \
    'WidgetAppearanceWorkbench.qml:+ (root.selectedActive ? "ACTIVE" : "INACTIVE")'; do
  file=${icons_drilldown_contract%%:*}
  label=${icons_drilldown_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Icons drill-down contract drifted: $label"
done
for bars_height_contract in \
    'ControlSettings.qml:readonly property bool compactBarsPage:' \
    'ControlSettings.qml:configureDetailPage === "bars"' \
    'ControlSettings.qml:readonly property real compactBarsPanelHeight:' \
    'ControlCenterPanel.qml:: settings.compactBarsPage' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactBarsPanelHeight,'; do
  file=${bars_height_contract%%:*}
  label=${bars_height_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Bars no-scroll panel-height contract drifted: $label"
done
for icons_height_contract in \
    'WidgetAppearanceWorkbench.qml:readonly property int overviewRowCount:' \
    'BarFunctionsPage.qml:readonly property int widgetOverviewRowCount:' \
    'ControlSettings.qml:readonly property bool compactIconsOverview:' \
    'ControlSettings.qml:readonly property real compactIconsPanelHeight:' \
    'ControlSettings.qml:pageLoader.item.widgetDetailOpen === false' \
    'ControlCenterPanel.qml:: settings.compactIconsOverview' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactIconsPanelHeight,'; do
  file=${icons_height_contract%%:*}
  label=${icons_height_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Icons compact panel-height contract drifted: $label"
done
for fitted_detail_height_contract in \
    'ControlSettings.qml:readonly property real configureDetailPanelChromeHeight:' \
    'ControlSettings.qml:readonly property bool compactIconsSelection:' \
    'ControlSettings.qml:readonly property real compactIconsSelectionPanelHeight:' \
    'ControlSettings.qml:pageLoader.item.widgetDetailOpen === true' \
    'ControlCenterPanel.qml:: settings.compactIconsSelection' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactIconsSelectionPanelHeight,' \
    'ControlSettings.qml:readonly property bool compactHealthPage:' \
    'ControlSettings.qml:readonly property real compactHealthPanelHeight:' \
    'ControlSettings.qml:configureDetailPage === "health"' \
    'ControlCenterPanel.qml:: settings.compactHealthPage' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactHealthPanelHeight,'; do
  file=${fitted_detail_height_contract%%:*}
  label=${fitted_detail_height_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "fitted detail panel-height contract drifted: $label"
done
rg -Uq 'readonly property real compactIconsSelectionPanelHeight:\n(?:.*\n){0,2}    Commons\.Style\.space\(550\)' \
  "$control_dir/ControlSettings.qml" \
  || fail "Icons selection no-scroll panel height drifted"
for pickers_height_contract in \
    'ControlSettings.qml:readonly property bool compactPickersPage:' \
    'ControlSettings.qml:configureDetailPage === "pickers"' \
    'ControlSettings.qml:readonly property real compactPickersPanelHeight:' \
    'ControlCenterPanel.qml:: settings.compactPickersPage' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactPickersPanelHeight,'; do
  file=${pickers_height_contract%%:*}
  label=${pickers_height_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Pickers compact panel-height contract drifted: $label"
done
for workspaces_height_contract in \
    'ControlSettings.qml:readonly property bool compactWorkspacesPage:' \
    'ControlSettings.qml:configureDetailPage === "workspaces"' \
    'ControlSettings.qml:readonly property real compactWorkspacesPanelHeight:' \
    'ControlCenterPanel.qml:: settings.compactWorkspacesPage' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactWorkspacesPanelHeight,'; do
  file=${workspaces_height_contract%%:*}
  label=${workspaces_height_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Workspaces compact panel-height contract drifted: $label"
done
for logo_height_contract in \
    'LogoSettingsPage.qml:readonly property int optionRowCount:' \
    'ControlSettings.qml:readonly property bool compactLogoPage:' \
    'ControlSettings.qml:configureDetailPage === "logo"' \
    'ControlSettings.qml:readonly property real compactLogoPanelHeight:' \
    'ControlCenterPanel.qml:: settings.compactLogoPage' \
    'ControlCenterPanel.qml:? fittedContentHeight(settings.compactLogoPanelHeight,'; do
  file=${logo_height_contract%%:*}
  label=${logo_height_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Logo compact panel-height contract drifted: $label"
done
for icons_hero_contract in \
    'PageHeaderHero.qml:property real preferredHeight:' \
    'PageHeaderHero.qml:property real previewWidth:' \
    'PageMotionStage.qml:anchors.centerIn: parent' \
    'BarFunctionsPage.qml:motionActive && !widgetDetailOpen' \
    'BarFunctionsPage.qml:preferredHeight: Commons.Style.space(80)' \
    'BarFunctionsPage.qml:previewWidth: Commons.Style.space(150)' \
    'BarFunctionsPage.qml:resetActionVisible: root.resetActionVisible' \
    'BarFunctionsPage.qml:resetActionColor: root.resetActionColor' \
    'BarFunctionsPage.qml:controller.v2LayoutActive === true ? "v2" : "v1"' \
    'BarFunctionsPage.qml:resetConfirmationPending ? "color01" : "color03"' \
    'BarFunctionsPage.qml:function requestAppearanceReset()' \
    'WidgetAppearanceWorkbench.qml:actionLabel: root.resetActionVisible' \
    'WidgetAppearanceWorkbench.qml:text: "|"' \
    'WidgetAppearanceWorkbench.qml:font.weight: Font.DemiBold' \
    'WidgetAppearanceWorkbench.qml:font.letterSpacing: 1' \
    'WidgetAppearanceWorkbench.qml:Accessible.onPressAction:' \
    'WidgetAppearanceWorkbench.qml:!event.isAutoRepeat'; do
  file=${icons_hero_contract%%:*}
  label=${icons_hero_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Icons reset/header contract drifted: $label"
done
if rg -q 'utilityAction|previewVerticalOffset' \
    "$control_dir/PageHeaderHero.qml" "$control_dir/PageMotionStage.qml"; then
  fail "Icons reset still displaces or overlays the schematic preview"
fi
reset_repeat_guards=$(rg -c '!event\.isAutoRepeat' "$workbench")
[[ $reset_repeat_guards -eq 3 ]] \
  || fail "all three Icons reset keyboard paths must reject auto-repeat"
rg -Fq 'height: Commons.Style.space(25)' "$workbench" \
  || fail "Icons reset header target is smaller than 24 px"
widget_tile_block=$(awk '
  /component WidgetOptionTile: Rectangle/ { capture=1 }
  /component WidgetMoveAction: FocusScope/ { capture=0 }
  capture { print }
' "$workbench")
for tile_move_contract in \
    'anchors.rightMargin: Commons.Style.space(27)' \
    'id: moveAction' \
    'anchors.right: parent.right' \
    'anchors.top: parent.top' \
    'anchors.bottom: parent.bottom'; do
  grep -Fq "$tile_move_contract" <<<"$widget_tile_block" \
    || fail "Icons tile move-action geometry drifted: $tile_move_contract"
done
move_action_block=$(awk '
  /component WidgetMoveAction: FocusScope/ { capture=1 }
  /component ContentCycleChoice: Rectangle/ { capture=0 }
  capture { print }
' "$workbench")
for move_action_contract in \
    'width: Commons.Style.space(22)' \
    'clip: true' \
    'root.controller.accentColor("color03")' \
    'id: moveActionStrip' \
    'anchors.fill: parent' \
    'anchors.leftMargin: -root.controller.controlRadius' \
    '? Commons.Util.alpha(moveActionControl.actionAccent, 0.18)' \
    'Commons.Util.alpha(root.foreground, 0.06)' \
    '? moveActionControl.actionAccent : root.foreground'; do
  grep -Fq "$move_action_contract" <<<"$move_action_block" \
    || fail "Icons move-action strip contract drifted: $move_action_contract"
done
if grep -Eq 'root\.controller\.dividerColor|border\.(width|color)' \
    <<<"$move_action_block"; then
  fail "Icons move-action strip restored a retired divider or hover border"
fi
if rg -q 'providerFilter|providerOptions|providerRepeater|chooseProvider' \
    "$workbench"; then
  fail "Icons editor still exposes provider filtering"
fi
for active_order_contract in \
    'ControlCenterPanel.qml:readonly property var activeWidgetOrder:' \
    'ControlCenterPanel.qml:bar.layoutController.order' \
    'WidgetAppearanceWorkbench.qml:settingsGroup, "enabled", true' \
    'WidgetAppearanceWorkbench.qml:region: region'; do
  file=${active_order_contract%%:*}
  label=${active_order_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Icons active-order contract drifted: $label"
done
for palette_contract in \
    'readonly property bool hovered:' \
    'border.width: 1' \
    'border.color: root.controller.controlBorderColor' \
    'scale: hovered ? 1.04 : 1' \
    'duration: 120' \
    'width: Commons.Style.space(16)'; do
  rg -Fq "$palette_contract" "$workbench" \
    || fail "Icons palette no longer matches Bars: $palette_contract"
done
[[ ! -e $control_dir/WidgetEditorPage.qml ]] \
  || fail "Plugins still owns a second widget Appearance editor"
if rg -q 'widget-editor|editRequested|scopeMode|editorOnly' \
    "$control_dir" --glob '*.qml'; then
  fail "retired cross-style widget editor remains reachable"
fi
rg -Fq 'function resetGroupAppearance(groupId)' \
  "$repo_root/hancore.shibumi.state/Service.qml" \
  || fail "widget Appearance reset is not atomic in the state service"
rg -Fq 'function resetGroupAppearanceForVariant(groupId, variantValue)' \
  "$repo_root/hancore.shibumi.state/Service.qml" \
  || fail "profile-specific widget Appearance reset is missing"
rg -Fq 'function resetAllGroupAppearancesForVariant(variantValue)' \
  "$repo_root/hancore.shibumi.state/Service.qml" \
  || fail "global profile-specific widget Appearance reset is missing"
rg -Fq '"widgetBorderColor"' \
  "$repo_root/hancore.shibumi.state/Service.qml" \
  || fail "widget outline-color choice is not covered by appearance reset"

if rg -q 'Regular|Minimal|heightGroup|barPresentation\.height|Ui\.Toggle|Ui\.Dropdown' \
    "$control_dir" --glob '*.qml'; then
  fail "retired oversized setting controls remain"
fi

[[ -f $control_dir/ThinScrollBar.qml ]] \
  || fail "shared thin scrollbar is missing"
for scrollbar_contract in \
    'width: root.engaged ? 3 : 2' \
    'visible: active && !!flickable && flickable.visible && scrollable' \
    'root.flickable.contentY = ratio * contentRange' \
    'flickable.contentHeight > flickable.height + 0.5'; do
  rg -Fq "$scrollbar_contract" "$control_dir/ThinScrollBar.qml" \
    || fail "thin scrollbar contract drifted: $scrollbar_contract"
done
scrollbar_instances=$(rg -n '^[[:space:]]*ThinScrollBar \{' \
  "$control_dir/ControlCenterPanel.qml" \
  "$control_dir/ControlSettings.qml" \
  "$control_dir/WidgetAppearanceWorkbench.qml" | wc -l)
[[ $scrollbar_instances -eq 6 ]] \
  || fail "expected 6 scroll surfaces, found $scrollbar_instances"
for scroll_surface in settingsFlick quickFlick configureLandingFlick pageFlick \
    resultsFlick inspectorFlick; do
  rg -Fq "flickable: $scroll_surface" "$control_dir" --glob '*.qml' \
    || fail "scroll surface has no thin scrollbar: $scroll_surface"
done
if rg -q '(^|[[:space:]])ScrollBar[[:space:].{]' \
    "$control_dir" --glob '*.qml'; then
  fail "control center depends on a foreign styled scrollbar"
fi
rg -q 'id: settingsViewport' "$control_dir/ControlCenterPanel.qml" \
  || fail "settings viewport is missing"
sed -n '/id: settingsViewport/,/Flickable {/p' \
  "$control_dir/ControlCenterPanel.qml" | rg -q 'clip: true' \
  || fail "settings viewport does not clip the scroll indicator"

for density_contract in \
    'LogoSettingsPage.qml:height: Commons.Style.space(56)' \
    'WordmarkPreview.qml:implicitHeight: 24' \
    'WorkspaceMarkerPreviewCard.qml:height: Commons.Style.space(68)' \
    'BarStylePreviewCard.qml:height: Commons.Style.space(92)' \
    'WidgetModuleTile.qml:implicitHeight: Commons.Style.space(58)' \
    'AppearanceWidgetTile.qml:implicitHeight: Commons.Style.space(62)'; do
  file=${density_contract%%:*}
  label=${density_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "compact card geometry drifted: $file"
done

printf 'control center regression passed\n'
