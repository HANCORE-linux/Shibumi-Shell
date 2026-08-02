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
rg -Fq 'readonly property bool animationActive: pointer.containsMouse' \
  "$control_dir/BarWidget.qml" \
  || fail "G1 background motion is not hover-only"
rg -Fq 'readonly property bool nativePillSurfaceVisible: !stockOmarchyHost && !!(tokens' \
  "$control_dir/BarWidget.qml" \
  || fail "stock Omarchy return icon inherits a Shibumi pill surface"
if rg -Fq 'pointer.containsMouse || opened' "$control_dir/BarWidget.qml"; then
  fail "G1 background motion still runs for the full panel lifetime"
fi
rg -Fq 'text: "SHIBUMI"' "$control_dir/BarWidget.qml" \
  || fail "G1 does not render the Shibumi wordmark"
rg -Fq 'HostIdentity.isStockOmarchyHost(bar)' "$control_dir/BarWidget.qml" \
  || fail "G1 does not resolve the active host through Quattro shell state"
[[ -f $control_dir/assets/shibumi-icon-hikiryo.svg ]] \
  || fail "stock Omarchy host icon is missing"
rg -Fq 'source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")' \
  "$control_dir/BarWidget.qml" \
  || fail "stock Omarchy host does not render the Hikiryō icon"
rg -Fq 'width: root.stockOmarchyHost ? 18 : 16' \
  "$control_dir/BarWidget.qml" \
  || fail "stock Omarchy host icon is not pixel-centered in its even slot"
if rg -A8 -F 'source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")' \
    "$control_dir/BarWidget.qml" | rg -Fq 'tint:'; then
  fail "multicolor Hikiryō icon is flattened by a tint"
fi
rg -Fq 'HostIdentity.shellName(bar)' "$control_dir/ControlCenterPanel.qml" \
  || fail "Bars page does not resolve the active host through Quattro shell state"
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
rg -Fq 'restoreBar.scheduleWidgetRestore(' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "shell-style changes do not preserve the open Control Center page"
rg -Fq 'presentationName === "shellStyle"' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "shell-style restore does not wait for the replacement panel owner"
rg -Fq 'preservePage, true)' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "V1/V2 restore does not wait for the replacement panel owner"
rg -A14 -F 'function setBarPosition(value)' \
    "$repo_root/hancore.shibumi.bar/Bar.qml" \
  | rg -Fq 'root.scheduleWidgetRestore(' \
  || fail "Top/Bottom changes do not preserve the Control Center route"
rg -Fq 'pendingWidgetRestoreAttempts < 20' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "V1/V2 restore window no longer covers late owner replacement"
rg -Fq 'even after the first successful open' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "V1/V2 restore no longer protects a second panel-owner rebuild"
rg -Fq 'property var pendingWidgetRestoreActiveOwner: null' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "V1/V2 restore does not track the established replacement owner"
rg -Fq 'pendingWidgetRestorePage = currentPage' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "V1/V2 restore overwrites navigation performed during handoff"
rg -Fq 'function trackWidgetRestorePage(pluginId, page)' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "V1/V2 restore does not preserve navigation during owner handoff"
rg -Fq 'controller.trackSettingsPage(next)' \
  "$control_dir/ControlSettings.qml" \
  || fail "Control Center navigation is not handed to the restore lifecycle"
rg -Fq 'bar.cancelWidgetRestore(moduleName)' \
  "$control_dir/BarWidget.qml" \
  || fail "closing the Control Center does not cancel a pending restore"
rg -Fq 'function runWithControlCenterRestore(callback)' \
  "$control_dir/ControlCenterPanel.qml" \
  || fail "widget Appearance changes do not preserve the Control Center"
rg -Fq 'restoreBar.scheduleWidgetRestore(' \
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
  'ActiveBarSettingsPage.qml:detail: "Add slots and place dividers"' \
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
  'ActiveBarSettingsPage.qml:root.activeLabel + " ACTIVE"' \
  'ActiveBarSettingsPage.qml:visible: root.shibumiActive && !root.v2Active' \
  'ActiveBarSettingsPage.qml:visible: root.v2Active' \
  'ActiveBarSettingsPage.qml:surfaceEffectOptionCount:' \
  'ActiveBarSettingsPage.qml:surfaceRadiusOptionCount:' \
  'ControlSettings.qml:split gap slots divider separator full fit dock notch'; do
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
    'WidgetModuleTile.qml:text: root.favorite ? "star" : "star_border"' \
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
  'ControlCenterPanel.qml:switchPhase === "error" ? 250 : 205' \
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
  'label: "Edit slots"' \
  'label: "Edit layout"' \
  'label: "Restore layout"' \
  'id: reactorRepeater'; do
  rg -Fq "$route_contract" "$control_dir/ActiveBarSettingsPage.qml" \
    || fail "active Bars drill-down drifted: $route_contract"
done
if rg -q 'SLOT CAPACITY|V2 LAYOUT|v2SlotRepeater|controller\.(add|remove)V2Slot|Add slots and place dividers directly' \
    "$control_dir/ActiveBarSettingsPage.qml"; then
  fail "Bars reintroduced redundant V2 layout or slot-capacity copy"
fi
if rg -q 'Choose the active V2 shape|V1 uses the Islands form' \
    "$control_dir/ActiveBarSettingsPage.qml"; then
  fail "Bars reintroduced redundant copy below Bar Form"
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
rg -Fq 'detail: "Add slots and place dividers"' \
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
    'text: "LOCAL SUITE"' \
    'return "SHIBUMI-HEALTH/" + String(check.id || "UNKNOWN")' \
    'function diagnosticIssueUrl(check)' \
    'Qt.openUrlExternally(diagnosticIssueUrl(check))' \
    'label: root.copiedCheckId === String(checkRow.check.id || "")' \
    'label: "Open issue ↗"' \
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
  'height: Commons.Style.space(30)' \
  'spacing: Commons.Style.space(8)' \
  'controlHeight: effectRow.height' \
  'uiScale: root.uiScale' \
  'effectRepeater.count === (showSurface ? effectOptions.length : 0)' \
  'radiusRepeater.count === (showSurface ? radiusOptions.length : 0)' \
  'colorRepeater.count === (showAccent ? colorOptions.length : 0)'; do
  rg -Fq "$surface_contract" "$control_dir/BarSurfaceSettings.qml" \
    || fail "version-aware bar-surface contract drifted: $surface_contract"
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
rg -U -q 'id: mediaPickerRepeater[\s\S]*model: \[\n[[:space:]]*\{ value: "carousel", label: "Carousel" \},\n[[:space:]]*\{ value: "tanzaku", label: "Tanzaku" \},\n[[:space:]]*\{ value: "hearthstone", label: "Hearthstone" \}' \
  "$control_dir/PickerSettingsPage.qml" \
  || fail "media picker choices are not ordered Carousel, Tanzaku, Hearthstone"
[[ -f $control_dir/PickerPreviewCard.qml ]] \
  || fail "picker preview card is missing"
if [[ $(rg -F -c 'delegate: PickerPreviewCard {' \
    "$control_dir/PickerSettingsPage.qml") -ne 2 ]]; then
  fail "picker choices remain text-only controls"
fi
for picker_preview in \
    'root.styleValue === "omarchy"' \
    'root.styleValue === "carousel"' \
    'root.styleValue === "tanzaku"' \
    'function hearthCard(' \
    'larger, lifted focus card'; do
  rg -Fq "$picker_preview" "$control_dir/PickerPreviewCard.qml" \
    || fail "missing picker preview contract: $picker_preview"
done

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
    'root.styleValue === "aurora"'; do
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
    'text: "UNDO"' \
    'id: undoButton' \
    'undoPointer.containsMouse' \
    'controller.accentColor("color01")' \
    'id: feedbackCountdown' \
    'duration: 7000' \
    'paused: feedbackHover.hovered || undoButton.activeFocus' \
    '(parent.width - 2) * root.feedbackProgress' \
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
    'controller.restoreShibumiProvider(undoGroup)' \
    'actionLabel: "Add plugin"' \
    'onActionRequested: root.controller.openPluginInstaller()' \
    'function providerCountSummary(entries)' \
    'return parts.join(" + ")' \
    'root.catalogSummary()'; do
  rg -Fq "$plugin_contract" "$control_dir/PluginCatalogPage.qml" \
    || fail "plugin provider-feedback contract drifted: $plugin_contract"
done
for provider_model in \
    'const replacementGroup = group === "" && bar' \
    'replacementLabel: group === "" && bar' \
    'replacementTargetEnabled:' \
    'replacementInEffect: false' \
    'replacedByIds: []' \
    'removable: manifest.__isFirstParty !== true && !suiteManaged' \
    'function removePlugin(pluginId)' \
    '["omarchy", "plugin", "remove", id, "--yes"]' \
    'id: pluginRemoval' \
    'Control Center rejected non-removable plugin:' \
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
    'root.title + "  " + root.count' \
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
    'bar.setBarWidgetInstalled(id, enabled === true, section)'; do
  rg -Fq "$suite_boundary" "$control_dir/ControlCenterPanel.qml" \
    || fail "plugin-manager suite boundary drifted: $suite_boundary"
done
for parity_contract in \
    'bar.layoutContains(id)' \
    'bar.setBarWidgetInstalled(id, enabled === true, section)' \
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
rg -Fq 'detail: "Add slots and place dividers"' \
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
    ': (parent.width - parent.spacing * 2) / 3 * 2' \
    '+ parent.spacing' \
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
    'WidgetAppearanceWorkbench.qml:{ value: "text", label: "Text", enabled: false }' \
    'WidgetAppearanceWorkbench.qml:enabled: radioList.enabled && radioRow.available' \
    'WidgetAppearanceWorkbench.qml:function isShibumiWidgetOption(source)' \
    'WidgetAppearanceWorkbench.qml:|| !isShibumiWidgetOption(source)' \
    'WidgetAppearanceWorkbench.qml:&& !root.v1LayoutActive' \
    'ControlCenterPanel.qml:stateService.groupAppearanceSettingForVariant' \
    'ControlCenterPanel.qml:stateService.setGroupAppearanceSettingForVariant' \
    'ControlCenterPanel.qml:stateService.resetGroupAppearanceForVariant'; do
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
    'BarFunctionsPage.qml:preferredHeight: Commons.Style.space(80)' \
    'BarFunctionsPage.qml:previewWidth: Commons.Style.space(150)'; do
  file=${icons_hero_contract%%:*}
  label=${icons_hero_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "Icons compact hero contract drifted: $label"
done
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
