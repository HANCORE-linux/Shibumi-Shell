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
  'ControlMainPage.qml:MAINTENANCE' \
  'ControlMainPage.qml:SESSION' \
  'ControlMainPage.qml:SHORTCUTS' \
  'SplitSettingsPage.qml:SPLIT & MERGE' \
  'SplitSettingsPage.qml:GAP ANIMATION' \
  'ActiveBarSettingsPage.qml:BAR FORM' \
  'ActiveBarSettingsPage.qml:V1 LAYOUT' \
  'ActiveBarSettingsPage.qml:V2 LAYOUT' \
  'ActiveBarSettingsPage.qml:SLOT CAPACITY' \
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

for page in quick configure main bars plugins workspaces pickers logo splits \
    functions preferences; do
  rg -Fq "\"$page\"" "$control_dir/ControlSettings.qml" \
    || fail "missing control-center page: $page"
done

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
  'ConfigureLandingPage.qml:function openRoute(pageId)' \
  'ConfigureLandingPage.qml:function showRoute(pageId)' \
  'ConfigureLandingPage.qml:signal backRequested()' \
  'ConfigureLandingPage.qml:context.bezierCurveTo(' \
  'ConfigureLandingPage.qml:routeColumn.width + routeGraph.portOffset' \
  'ConfigureLandingPage.qml:context.arc(startX, startY, 3.6, 0, Math.PI * 2)' \
  'ConfigureLandingPage.qml:activeFocusOnTab: true' \
  'ConfigureLandingPage.qml:Keys.onReturnPressed:' \
  'ConfigureLandingPage.qml:function activateFocusedRoute()' \
  'ConfigureLandingPage.qml:id: detailRouteCanvas' \
  'ConfigureLandingPage.qml:x: -Commons.Style.space(14)' \
  'ConfigureLandingPage.qml:height: root.transitioning ? 0 : implicitHeight' \
  'ConfigureLandingPage.qml:spacing: root.transitioning ? 0 : Commons.Style.space(14)' \
  'ConfigureLandingPage.qml:return 0' \
  'ConfigureLandingPage.qml:context.lineTo(nodeX, lastY)' \
  'ConfigureLandingPage.qml:context.arc(nodeX, nodeY, 3.6, 0, Math.PI * 2)' \
  'ConfigureLandingPage.qml:if (pageId !== selectedPage) pageRequested(pageId)' \
  'ConfigureLandingPage.qml:? root.targetY(modelData.id) + homeY : homeY' \
  'ConfigureLandingPage.qml:? Commons.Style.space(154) : routeColumn.width' \
  'ConfigureLandingPage.qml:enabled: !root.transitioning || root.detailOpen' \
  'ConfigureLandingPage.qml:id: intro' \
  'ConfigureLandingPage.qml:opacity: 1' \
  'ConfigureLandingPage.qml:Behavior on x {' \
  'ConfigureLandingPage.qml:interval: 330' \
  'ControlSearchPage.qml:id: page.id === "main" ? "configure" : page.id' \
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
  'PluginCatalogPage.qml:title: "Widgets"' \
  'ControlSettings.qml:Add widget' \
  'ControlSettings.qml:Install plugin from Git' \
  'ControlSettings.qml:Plugins run as unsandboxed code'; do
  file=${contract%%:*}
  label=${contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "missing V4 control-center contract: $label"
done

for refined_contract in \
  'ControlSettings.qml:sequence: "Ctrl+K"' \
  'ControlSettings.qml:text: "Search settings…"' \
  'ControlSettings.qml:{ value: "quick", label: "QUICK" }' \
  'ControlSettings.qml:{ value: "configure", label: "CONFIGURE" }' \
  'ControlCenterPanel.qml:contentHeight: settings.currentPage === "quick"' \
  'QuickControlPage.qml:label: "V1"' \
  'QuickControlPage.qml:label: "V2"' \
  'QuickControlPage.qml:label: "Omarchy"' \
  'QuickControlPage.qml:SectionLabel { text: "BAR WIDGETS" }' \
  'QuickControlPage.qml:root.controller.toggleQuickWidget(' \
  'ControlCenterPanel.qml:function quickWidgetVisible(pluginId)' \
  'ControlCenterPanel.qml:function toggleQuickWidget(pluginId)' \
  'ActiveBarSettingsPage.qml:root.activeLabel + " ACTIVE"' \
  'ActiveBarSettingsPage.qml:visible: root.shibumiActive && !root.v2Active' \
  'ActiveBarSettingsPage.qml:visible: root.v2Active' \
  'ActiveBarSettingsPage.qml:surfaceEffectOptionCount:' \
  'ActiveBarSettingsPage.qml:surfaceRadiusOptionCount:' \
  'ControlSearchPage.qml:split gap slots divider separator full fit dock notch'; do
  file=${refined_contract%%:*}
  label=${refined_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "refined Control Center contract drifted: $label"
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
  'label: "ACTIVE BAR"' \
  'interactive: true' \
  'onClicked: root.controller.showSettingsPage("bars")' \
  'if (modelData.active)' \
  'PageMotionStage {'; do
  rg -Fq "$landing_contract" "$control_dir/QuickControlPage.qml" \
    || fail "BAR landing-page contract drifted: $landing_contract"
done
if rg -q 'triggerQuickAction|toggleWifi|toggleBluetooth|wpctl.*set-mute|cycleProfile' \
    "$control_dir/ControlCenterPanel.qml" "$control_dir/QuickControlPage.qml"; then
  fail "BAR WIDGETS still mutate hardware state"
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
  'QuickControlPage.qml:? root.activeStateColor : root.controller.dividerColor' \
  'ControlSettings.qml:id: widgetsShortcut' \
  'ControlSettings.qml:onClicked: root.setPage("plugins")' \
  'ControlSettings.qml:id: pluginRegistryStatus' \
  'ControlSettings.qml:+ " / " + root.controller.availableWidgetCount' \
  'ControlSettings.qml:+ " SHIBUMI · "' \
  'ControlSettings.qml:+ " OMARCHY · "' \
  'ControlSettings.qml:+ " EXT"' \
  'QuickControlPage.qml:function surfaceFill(active, hovered)' \
  'QuickControlPage.qml:function surfaceBorder(active, hovered)' \
  'QuickControlPage.qml:textWeight: root.valueFontWeight' \
  'CompactSettingChoice.qml:property int textWeight:' \
  'ControlCenterPanel.qml:registryShibumiPluginCount:' \
  'ControlCenterPanel.qml:registryOmarchyPluginCount:' \
  'ControlCenterPanel.qml:registryExternalPluginCount:' \
  'ControlSettings.qml:radius: Math.max(0, root.controller.controlRadius - 2)' \
  'ControlSettings.qml:id: activePage' \
  'ControlSettings.qml:width: parent.width' \
  'ControlCenterPanel.qml:? fittedContentHeight(Commons.Style.space(495),' \
  'ControlCenterPanel.qml:Commons.Style.space(550))'; do
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
  'label: "Edit dividers"' \
  'label: "Restore layout"' \
  'id: v2SlotRepeater' \
  'root.controller.addV2Slot(' \
  'root.controller.removeV2Slot(' \
  'id: reactorRepeater' \
  'root.controller.switchShell('; do
  rg -Fq "$route_contract" "$control_dir/ActiveBarSettingsPage.qml" \
    || fail "active Bars drill-down drifted: $route_contract"
done
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

for page_file in ControlOverviewPage.qml PluginCatalogPage.qml \
    SplitSettingsPage.qml BarFunctionsPage.qml ControlMainPage.qml \
    BarsPage.qml WidgetEditorPage.qml WorkspaceSettingsPage.qml \
    PickerSettingsPage.qml LogoSettingsPage.qml ControlSearchPage.qml; do
  rg -Fq 'PageHeaderHero {' "$control_dir/$page_file" \
    || fail "page motion is missing from $page_file"
done

rg -Fq 'visible: root.controller.v2LayoutActive !== true' \
  "$control_dir/SplitSettingsPage.qml" \
  || fail "V1 split and gap controls are not capability-gated"
rg -Fq 'visible: root.controller.v2LayoutActive === true' \
  "$control_dir/SplitSettingsPage.qml" \
  || fail "V2 slot and divider controls are not capability-gated"
rg -Fq 'V1 split islands, merge and gap animations do not apply.' \
  "$control_dir/SplitSettingsPage.qml" \
  || fail "V2 layout does not explain its capability boundary"

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
for icon in radio_button_checked align_vertical_center widgets brush \
    view_week settings download; do
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

for command in omarchy-system-lock 'systemctl", "suspend' \
    omarchy-system-reboot omarchy-system-shutdown; do
  rg -Fq "$command" "$control_dir/ControlCenterPanel.qml" \
    || fail "missing session-aware power action: $command"
done

for label in Status Battery \
    'Bar border' 'Panel & tooltip border' Border Frost Shadow \
    'Radius 12' 'Radius 6'; do
  rg -Fq "label: \"$label\"" "$control_dir" \
    --glob '*.qml' --glob '*.js' \
    || fail "missing explicit control label: $label"
done

for surface_contract in \
  'property bool v2Active: false' \
  'readonly property var effectOptions: v2Active' \
  'readonly property var radiusOptions: v2Active' \
  'effectRepeater.count === effectOptions.length' \
  'radiusRepeater.count === radiusOptions.length'; do
  rg -Fq "$surface_contract" "$control_dir/BarSurfaceSettings.qml" \
    || fail "version-aware bar-surface contract drifted: $surface_contract"
done
rg -Fq 'v2Active: root.v2Active' \
  "$control_dir/ActiveBarSettingsPage.qml" \
  || fail "active bar version is not forwarded to Bar Surface"

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
  rg -Fq "$color_contract" "$control_dir/BarSurfaceSettings.qml" \
    || fail "missing V1 palette choice: $color_contract"
done
rg -Fq 'columns: 9' "$control_dir/BarSurfaceSettings.qml" \
  || fail "Bars palette picker is not a compact nine-column strip"
rg -Fq 'radius: root.controller.controlRadius' \
  "$control_dir/BarSurfaceSettings.qml" \
  || fail "V1 palette swatches do not follow the live radius setting"
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
    'text: "OPACITY"' \
    'label: "2 px outline"'; do
  rg -Fq "$visual_contract" "$control_dir/WidgetAppearanceWorkbench.qml" \
    || fail "Appearance is missing widget visual control: $visual_contract"
done
for workspace_contract in 'label: "Magic"' 'label: "Frame"' \
    'Each marker is a workspace.'; do
  rg -Fq "$workspace_contract" "$control_dir/WorkspaceSettingsPage.qml" \
    || fail "Workspaces is missing visual control: $workspace_contract"
done
rg -Fq 'label: "Edit dividers on bar"' \
  "$control_dir/SplitSettingsPage.qml" \
  || fail "V2 settings are missing the direct divider editor"
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
    'property bool editorOnly: false' \
    'property string scopeMode: "shared"' \
    'id: displayModeRepeater' \
    'id: surfaceModeRepeater' \
    'id: widgetColorRepeater' \
    'text: root.advancedOpen ? "Advanced" : "More"' \
    'root.controller.resetGroupAppearance('; do
  rg -Fq "$workbench_contract" "$workbench" \
    || fail "widget Appearance workbench contract drifted: $workbench_contract"
done
for editor_contract in \
    'WidgetEditorPage.qml:BOTH · V1 + V2' \
    'WidgetEditorPage.qml:V1 ONLY' \
    'WidgetEditorPage.qml:V2 ONLY' \
    'WidgetAppearanceWorkbench.qml:Open Bars settings' \
    'WidgetAppearanceWorkbench.qml:Divider after ' \
    'WidgetAppearanceWorkbench.qml:Edit V2 dividers on bar' \
    'WidgetModuleTile.qml:signal editRequested()' \
    'PluginCatalogPage.qml:onEditRequested:'; do
  file=${editor_contract%%:*}
  label=${editor_contract#*:}
  rg -Fq "$label" "$control_dir/$file" \
    || fail "widget editor drill-down contract drifted: $label"
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
