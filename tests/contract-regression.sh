#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
cd "$repo_root"

fail() {
  printf 'contract regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v rg >/dev/null 2>&1 || fail "rg is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
[[ -x /usr/bin/quickshell ]] || fail "quickshell is required for the complete contract"

"$repo_root/tests/baseline-contract-regression.sh"
"$repo_root/tests/documentation-regression.py"
python3 "$repo_root/tests/production-boundary-regression.py"
python3 "$repo_root/tests/shared-runtime-import-regression.py"
python3 "$repo_root/tests/isolated-process-regression.py"
python3 "$repo_root/tests/source-snapshot-regression.py"
python3 "$repo_root/tests/isolated-files-regression.py"
python3 "$repo_root/tests/test_package_release.py"
python3 "$repo_root/tests/native-catalog-resource-contract.py"
python3 "$repo_root/tests/test_shibumi_manager.py"
python3 "$repo_root/tests/test_shibumi_suite.py"
python3 "$repo_root/tests/test_lifecycle_admission.py"
python3 "$repo_root/tests/test_inc013_drain_contract.py"
python3 "$repo_root/tests/quickshell-empty-registry-mutation.py"
"$repo_root/tests/state-matrix-contract-regression.sh"
"$repo_root/tests/v1-feature-evidence-regression.sh"
"$repo_root/tests/v2-source-evidence-regression.sh"
"$repo_root/tests/v1-embedded-v2-differences-regression.sh"
"$repo_root/tests/v2-feature-evidence-regression.sh"
"$repo_root/tests/quattro-contract-regression.sh"
[[ -x $repo_root/tests/omarchy-agents-contract-regression.sh ]] \
  || fail "Omarchy agents contract regression is missing"
if [[ -n ${SHIBUMI_AGENTS_OMARCHY_PATH:-} ]]; then
  "$repo_root/tests/omarchy-agents-contract-regression.sh"
fi
"$repo_root/tests/group-section-lifecycle-regression.sh"
[[ -x $repo_root/tests/group-section-wayland-lifecycle.sh ]] \
  || fail "GroupSection Wayland lifecycle regression is missing"
[[ -f $repo_root/tests/group-section-wayland-shell.qml ]] \
  || fail "GroupSection Wayland lifecycle fixture is missing"
if [[ ${SHIBUMI_RUN_WAYLAND_LIFECYCLE:-0} == 1 ]]; then
  "$repo_root/tests/group-section-wayland-lifecycle.sh"
fi
[[ -x $repo_root/tests/widget-pipeline-diagnostics-regression.sh ]] \
  || fail "widget pipeline diagnostics regression is missing"
[[ -x $repo_root/tests/widget-pipeline-wayland-regression.sh ]] \
  || fail "widget pipeline Wayland regression is missing"
[[ -f $repo_root/tests/widget-pipeline-wayland-shell.qml ]] \
  || fail "widget pipeline Wayland fixture is missing"
"$repo_root/tests/widget-pipeline-diagnostics-regression.sh"
python3 "$repo_root/tests/widget-pipeline-classifier-regression.py"
if [[ ${SHIBUMI_RUN_WAYLAND_LIFECYCLE:-0} == 1 ]]; then
  "$repo_root/tests/widget-pipeline-wayland-regression.sh"
fi

[[ ! -e manifest.json ]] \
  || fail "repository root must not masquerade as one native Omarchy plugin"

for retired_root_copy in \
  Bar.qml \
  core \
  services \
  styles/StyleRegistry.qml \
  styles/shibumi \
  shared/state \
  shared/telemetry \
  shared/power-state \
  shared/quick-access \
  shared/reactor \
  scripts/sync-bar-host.sh \
  scripts/sync-power-source.py \
  scripts/shibumi-gpu-probe \
  scripts/shibumi-picker \
  adapters/BluetoothBackendAdapter.qml \
  adapters/BluetoothDiscoveryGuard.qml \
  adapters/BluetoothModel.js \
  adapters/WorkspaceActions.qml \
  scripts/opencode-usage; do
  [[ ! -e $retired_root_copy ]] \
    || fail "plugin-canonical source regained a root/shared copy: $retired_root_copy"
done
if rg -q 'shared/(state|telemetry|power-state|quick-access|reactor)/' \
    scripts/sync-shared.sh; then
  fail "shared sync regained an owner-local source mapping"
fi
unexpected_root_sources=$(find adapters assets widgets -type f 2>/dev/null \
  | grep -Ev '^widgets/ShibumiPanel\.qml$' \
  || true)
[[ -z $unexpected_root_sources ]] || fail \
  "historical root implementation remains outside declared presentation maps: $unexpected_root_sources"

jq -e '
  .schemaVersion == 1 and
  .id == "hancore.shibumi.bar" and
  .kinds == ["bar"] and
  .entryPoints.bar == "Bar.qml"
' hancore.shibumi.bar/manifest.json >/dev/null \
  || fail "invalid Shibumi bar manifest"

[[ -s hancore.shibumi.control-center/assets/logo-tint.frag.qsb ]] \
  || fail "G1 exact flat-tint shader is missing"
[[ ! -e hancore.shibumi.menu && ! -e menu ]] \
  || fail "retired Shibumi App Menu source is still present"
jq -e '
  .retiredPlugins == ["hancore.shibumi.menu"] and
  ([.plugins[].kinds[]] | index("menu") | not) and
  ([.plugins[].id] | index("hancore.shibumi.menu") | not) and
  ([.profiles[].install[]] | index("hancore.shibumi.menu") | not) and
  ([.profiles[].enableServices[]] | index("hancore.shibumi.menu") | not)
' contracts/plugin-suite-v1.json >/dev/null \
  || fail "suite still installs or exposes the retired Shibumi App Menu"

rg -q '^Item \{' hancore.shibumi.bar/Bar.qml || fail "hancore.shibumi.bar/Bar.qml must use Item as its root"
if rg -q '^ShellRoot \{' hancore.shibumi.bar/Bar.qml; then
  fail "a native full-bar plugin must not create a ShellRoot"
fi

for property_name in omarchyPath shell manifest pluginRegistry barWidgetRegistry barConfig; do
  rg -q "^[[:space:]]*property (string|var) ${property_name}:" hancore.shibumi.bar/Bar.qml \
    || fail "missing optional host property: $property_name"
  if rg -q "^[[:space:]]*required property .* ${property_name}" hancore.shibumi.bar/Bar.qml; then
    fail "asynchronously injected host property is required: $property_name"
  fi
done

rg -q 'typeof Util\.execDetached === "function"' hancore.shibumi.bar/Bar.qml \
  || fail "bar command launcher does not follow Quattro's current host contract"
rg -Fq 'Quickshell.execDetached(["bash", "-lc", text])' hancore.shibumi.bar/Bar.qml \
  || fail "bar command launcher has no compatibility fallback"
if rg -q 'omarchy-hyprland-launch|commandLauncher' hancore.shibumi.bar/Bar.qml; then
  fail "bar command launcher still depends on the removed legacy launcher"
fi

rg -Uq 'model: root\.outputWindowsEnabled && !root\.shutdownPrepared\n[[:space:]]*\? Quickshell\.screens : \[\]' hancore.shibumi.bar/Bar.qml \
  || fail "bar variants must preserve the shutdown-gated native Quickshell screen model"
if rg -q 'model: .*barScreens' hancore.shibumi.bar/Bar.qml; then
  fail "bar variants must not use a JavaScript copy of Quickshell.screens"
fi
if ! {
  rg -q 'screen\.name !== ""' hancore.shibumi.bar/core/BarPanel.qml \
    && rg -q 'screen\.width > 0' hancore.shibumi.bar/core/BarPanel.qml \
    && rg -q 'screen\.height > 0' hancore.shibumi.bar/core/BarPanel.qml
}; then
  fail "bar must reject invalid Wayland placeholder screens"
fi
rg -q '^PanelWindow \{' hancore.shibumi.bar/core/BarPanel.qml \
  || fail "output surface must be a PanelWindow"
rg -Fq 'implicitHeight: !bar.vertical && validScreen ? bar.barSize : 0' \
  hancore.shibumi.bar/core/BarPanel.qml \
  || fail "horizontal host must remain bar-height during edit"
rg -Fq 'implicitWidth: bar.vertical && validScreen ? bar.barSize : 0' \
  hancore.shibumi.bar/core/BarPanel.qml \
  || fail "vertical host must remain bar-width during edit"
rg -Fq 'WlrLayershell.keyboardFocus: dragSession.editing' \
  hancore.shibumi.bar/core/BarPanel.qml \
  || fail "stable bar surface must own temporary edit focus"
if rg -q '^  mask: Region \{|MouseArea \{' hancore.shibumi.bar/core/BarPanel.qml; then
  fail "bar-local window retained a fullscreen mask or outside-click area"
fi
for backdrop_contract in \
  'id: editBackdropLoader' \
  'active: dragSession.editing' \
  '&& barWindow.visible && barWindow.backingWindowVisible' \
  '&& windowRecovery.recoveryVisible' \
  'EditBackdropPanel {' \
  'barVisible: barWindow.visible && barWindow.backingWindowVisible'; do
  rg -Fq "$backdrop_contract" hancore.shibumi.bar/core/BarPanel.qml \
    || fail "edit backdrop lifecycle drifted: $backdrop_contract"
done
[[ $(rg -c 'EditBackdropPanel \{' hancore.shibumi.bar/core/BarPanel.qml) -eq 1 ]] \
  || fail "each bar output must declare exactly one edit-only backdrop component"
for backdrop_surface_contract in \
  'visible: layoutSession.editing && barVisible' \
  'readonly property real outsideY: bar.position === "top" ? bar.barSize : 0' \
  '? Math.max(0, height - bar.barSize) : height' \
  'WlrLayershell.layer: WlrLayer.Top' \
  'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' \
  'mask: Region { item: dismissArea }' \
  'y: root.outsideY' \
  'height: root.outsideHeight' \
  'onClicked: root.layoutSession.setEditing(false)'; do
  rg -Fq "$backdrop_surface_contract" hancore.shibumi.bar/core/EditBackdropPanel.qml \
    || fail "edit backdrop surface drifted: $backdrop_surface_contract"
done
rg -q '^PanelWindow \{' hancore.shibumi.bar/core/DragGhostPanel.qml \
  || fail "drag ghost must be isolated from the edge-local bar window"
rg -q 'mask: Region \{\}' hancore.shibumi.bar/core/DragGhostPanel.qml \
  || fail "drag ghost overlay must remain input-transparent"
rg -Fq 'DragGhostVisual {' hancore.shibumi.bar/core/DragGhostPanel.qml \
  || fail "drag layer must use the render-tested visual"
if rg -q 'barOrigin[XY]' hancore.shibumi.bar/core/DragGhostPanel.qml hancore.shibumi.bar/core/DragGhostVisual.qml; then
  fail "drag ghost must not add an edge offset to full-window coordinates"
fi
awk '/^[[:space:]]*id: barSurfaceLoader$/,/^  }$/' hancore.shibumi.bar/core/BarPanel.qml \
  | rg -q '^    anchors.fill: parent$' \
  || fail "bar surface must fill the edge-local bar window from local origin zero"
if rg -q 'barSurfaceLoader[[:space:]]*\.|id: barSurfaceLoader' hancore.shibumi.bar/core/BarPanel.qml \
    && rg -q '^[[:space:]]+(x|y): .*barWindow\.bar\.position' hancore.shibumi.bar/core/BarPanel.qml; then
  fail "bar surface retained a fullscreen-window edge offset"
fi
rg -q '^Scope \{' hancore.shibumi.bar/core/WindowRecovery.qml \
  || fail "per-output window recovery scope is missing"
rg -q 'function onResourcesLost\(\)' hancore.shibumi.bar/core/WindowRecovery.qml \
  || fail "window recovery does not handle resourcesLost"
rg -q 'function onClosed\(\)' hancore.shibumi.bar/core/WindowRecovery.qml \
  || fail "window recovery does not handle closed"
if rg -q 'targetWindow\.visible[[:space:]]*=' hancore.shibumi.bar/core/WindowRecovery.qml; then
  fail "window recovery imperatively destroys the bar visibility binding"
fi
rg -q 'visible: bar\.hostReady && bar\.styleReady && validScreen && !bar\.barHidden' hancore.shibumi.bar/core/BarPanel.qml \
  || fail "output must wait for host and style readiness and honor bar-off"
rg -q 'active: barWindow\.bar\.hostReady && barWindow\.bar\.styleReady' hancore.shibumi.bar/core/BarPanel.qml \
  || fail "bar surface may instantiate before host injection completes"
rg -Uq 'active: barWindow\.bar\.hostReady && barWindow\.bar\.styleReady\n[[:space:]]*&& barWindow\.validScreen && barWindow\.bar\.visualTokens !== null' \
  hancore.shibumi.bar/core/BarPanel.qml \
  || fail "bar surface may instantiate for an invalid Wayland placeholder"
rg -q 'Services\.HostWidgetResolver' hancore.shibumi.bar/Bar.qml \
  || fail "replacement bar does not retain its isolated legacy widget path"
rg -Fq 'function inlineSettingsDelta(current, next)' hancore.shibumi.bar/Bar.qml \
  || fail "bar host cannot distinguish inline state from structural layout changes"
rg -Fq 'function applyInlineSettingsDelta(changes)' hancore.shibumi.bar/Bar.qml \
  || fail "bar host recreates widgets for inline state persistence"
rg -Fq 'function applyInlineSettings(nextEntry)' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "widget slots cannot receive inline state without replacing their entry binding"
rg -Fq 'function hostEntryFor(moduleValue, layout)' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "grouped widgets do not expose their host settings layer"
rg -Fq 'function settingsOverridesFor(groupValue, moduleValue, groupValueSettings,' \
  hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "grouped widgets do not expose explicit local settings overrides"
if rg -Fq 'slot.entry = change.entry' hancore.shibumi.bar/Bar.qml; then
  fail "inline state persistence overwrites the delegate-owned slot entry binding"
fi
if rg -q 'Services\.(SystemTelemetry|GpuTelemetry|PowerService|StatusService|WeatherService|ThemePalette|AiUsageService|PickerService|ReactorService|QuoteService|WorkspaceService|ClockService|NetworkService|MonitorService|BluetoothService)|Adapters\.(SystemActions|WorkspaceActions)|Widgets\.WidgetRegistry' hancore.shibumi.bar/Bar.qml; then
  fail "registry-only bar host still instantiates a feature owner"
fi
rg -q 'Qt\.createComponent\(url, Component\.PreferSynchronous\)' hancore.shibumi.bar/services/HostWidgetResolver.qml \
  || fail "host widget resolver does not load official manifest entry points"
[[ $(rg -l 'bar\.registeredWidgetComponent' \
  hancore.shibumi.{audio,status,center}/BarWidget.qml | wc -l) -eq 3 ]] \
  || fail "host-backed composites bypass the stable widget resolver"
if rg -q 'registered(Component|Source)|registeredWidget(Component|Source)' \
    hancore.shibumi.network/Service.qml; then
  fail "native Network owner still resolves a host feature component"
fi
rg -q 'registeredComponent\("omarchy\.monitor"\)' hancore.shibumi.brightness/Service.qml \
  || fail "shipped monitor owner bypasses the stable widget resolver"
if rg -q 'registeredWidgetComponent\("omarchy\.bluetooth"\)' \
    hancore.shibumi.bluetooth/Service.qml; then
  fail "shipped Bluetooth owner must not instantiate the complete host widget"
fi
if rg -U -q 'visible: root\.anchorIndex < 0\n[[:space:]]*bar: root\.bar\n[[:space:]]*region: "center"\n[[:space:]]*entries: root\.entries' hancore.shibumi.bar/core/CenterSection.qml; then
  fail "inactive center fallback must not instantiate duplicate widgets"
fi
[[ $(rg -c 'entries: root\.anchorIndex < 0 \? root\.entries : \[\]' hancore.shibumi.bar/core/CenterSection.qml) -eq 2 ]] \
  || fail "both center orientations must suppress the inactive fallback model"
rg -q 'bar\.registeredWidgetComponent\(moduleName\)' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "legacy widget slots lost their isolated host resolver"
rg -Fq 'const widgets = registry ? registry.widgets : null' \
  hancore.shibumi.bar/core/WidgetSlot.qml \
  && rg -Fq 'const candidate = scopedEntry.component' \
    hancore.shibumi.bar/core/WidgetSlot.qml \
  && rg -Uq 'readonly property var resolvedComponent:\n[[:space:]]*scopedHost \? scopedComponent : legacyComponent' \
    hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "scoped WidgetSlot does not bind the exact host Component directly"
if rg -q 'target: root\.scoped \? root\.widgetRegistry' \
    hancore.shibumi.bar/services/HostWidgetResolver.qml; then
  fail "scoped widget snapshots still fan out through the legacy resolver"
fi
if rg -q 'internalWidgetRegistry|internalComponent|registryComponent' \
    hancore.shibumi.bar/Bar.qml hancore.shibumi.bar/core/WidgetSlot.qml; then
  fail "registry-only widget resolution retains a local component owner"
fi
[[ $(rg -c 'widgetLoader\.sourceComponent = nextSource' \
  hancore.shibumi.bar/core/WidgetSlot.qml) -eq 1 ]] \
  || fail "widget slots must have one provenance-recorded Loader source setter"
rg -Fq 'function submitLoaderSource(candidate)' \
  hancore.shibumi.bar/core/WidgetSlot.qml \
  && rg -Fq 'const nextSource = slotComplete && moduleEnabled ? candidate : null' \
    hancore.shibumi.bar/core/WidgetSlot.qml \
  && rg -Fq '!("claimLoadedOwner" in bar) || bar.widgetSlotLoadAdmitted(root)' \
    hancore.shibumi.bar/core/WidgetSlot.qml \
  && rg -Fq '? resolvedComponent : null)' \
    hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "widget slots must gate controlled source submission with a legacy fallback"
rg -q 'active: root\.slotComplete && root\.moduleEnabled' \
  hancore.shibumi.bar/core/WidgetSlot.qml \
  && rg -q 'root\._submission\.source !== null' \
    hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "disabled, unregistered, or source-less widgets remain instantiated"
for compatibility_contract in \
    'fallbackTooltipText' \
    'compatibilityPanelCandidate' \
    'compatibilityTraversalChildren' \
    'compatibilityTraversalDepthLimit' \
    'compatibilityTraversalObjectLimit' \
    'findCompatibilityPanel' \
    'findCompatibilityCard' \
    'hostedModule' \
    'hostPanelChromeEnabled' \
    'hostPanelPlacementEnabled' \
    'hostPanelHeightRepairEnabled' \
    'compatibilityAvailableContentHeight' \
    'findCompatibilityContentHolder' \
    'measureCompatibilityContent' \
    'compatibilitySurfaceTimer' \
    'compatibilityMeasureTimer' \
    'compatibilityOpenMeasureTimer' \
    'hostedCardOrigin' \
    'publishCompatibilityConnection'; do
  rg -Fq "$compatibility_contract" hancore.shibumi.bar/core/WidgetSlot.qml \
    || fail "third-party host compatibility lost $compatibility_contract"
done
rg -q 'readonly property bool hostedModule: !suiteNativeModule' \
  hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "hosted panel adapter is restricted to one external provider"
rg -Fq 'if (root.bar.pendingTooltipTarget || root.bar.tooltipTarget) return' \
  hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "manifest tooltip fallback can override a plugin tooltip"
rg -Fq 'Binding.RestoreBindingOrValue' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "third-party panel chrome cannot restore native bindings"
[[ $(rg -c 'value: root\.hostedCardOrigin\(root\.compatibilityPanel\)' \
  hancore.shibumi.bar/core/WidgetSlot.qml) -eq 2 ]] \
  || fail "hosted panels do not translate both card axes to the visible bar"
rg -Fq 'y = barThickness + gap' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "top hosted panels still derive their offset from the host window"
rg -Fq 'property: "contentHeight"' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "screen-sized hosted panels do not repair KeyboardPanel height"
rg -Fq 'screenHeight - barThickness - gap - margin' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "hosted panel height is not capped at the visible bar edge"
rg -Fq 'Math.min(compatibilityNativeContentHeight, currentNativeHeight)' \
  hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "opening a hosted panel can recapture its repaired height as native"
rg -Fq 'item.mapToItem(holder, 0, 0)' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "hosted panel height does not follow rendered child geometry"
rg -q '^PanelWindow \{' hancore.shibumi.bar/core/HostedPanelConnector.qml \
  || fail "hosted V2 caret overlay is missing"
rg -q 'mask: Region \{\}' hancore.shibumi.bar/core/HostedPanelConnector.qml \
  || fail "hosted V2 caret overlay must remain input-transparent"
rg -q 'width: 26' hancore.shibumi.bar/core/HostedPanelConnector.qml \
  || fail "hosted V2 caret does not retain the native panel-edge span"
rg -q 'joinStyle: ShapePath\.MiterJoin' hancore.shibumi.bar/core/HostedPanelConnector.qml \
  || fail "hosted V2 caret does not retain the native panel join"
awk '
  /Rectangle \{/ { bridge = 1 }
  bridge && /z: 1/ { found = 1; exit }
  END { exit(found ? 0 : 1) }
' hancore.shibumi.bar/core/HostedPanelConnector.qml \
  || fail "hosted V2 caret bridge must remain below the replacement edge"
awk '
  /Shape \{/ { shape = 1 }
  shape && /z: 2/ { found = 1; exit }
  END { exit(found ? 0 : 1) }
' hancore.shibumi.bar/core/HostedPanelConnector.qml \
  || fail "hosted V2 caret must remain above the foreign-border bridge"
connector_path_count="$(
  awk '
    /ShapePath \{/ { count += 1 }
    END { print count + 0 }
  ' hancore.shibumi.bar/core/HostedPanelConnector.qml
)"
[[ "$connector_path_count" -eq 1 ]] \
  || fail "hosted V2 caret must be one continuous panel-edge path"
rg -Fq 'HostedPanelConnector {' hancore.shibumi.bar/core/BarPanel.qml \
  || fail "bar output does not own its screen-local hosted connector"
rg -Fq 'connectedPanelHostCaret' hancore.shibumi.bar/Bar.qml \
  || fail "bar facade does not distinguish host-drawn panel carets"
rg -q 'active: root\.groupEnabled' hancore.shibumi.bar/core/GroupSlot.qml \
  || fail "disabled multi-module groups remain instantiated"
rg -Fq 'readonly property bool appearanceFill: v2Shell &&' \
  hancore.shibumi.bar/core/GroupSlot.qml \
  || fail "V2 group appearance settings leak into the V1 pill surface"
rg -Fq 'customDecorated: shellStyle !== "shibumi"' \
  hancore.shibumi.state/lib/presentation/PillSurface.qml \
  || fail "V2 widget appearance settings suppress the V1 native pill"
rg -Fq 'presentation.v2Border === undefined' \
  hancore.shibumi.bar/styles/shibumi/VisualTokens.qml \
  || fail "V1 and V2 still share one mutable bar-border state"
if rg -Fq 'pillBorderWidth > 0 ? 0.5 : 0' \
    hancore.shibumi.bar/styles/shibumi/RunChrome.qml; then
  fail "V1 run borders are shifted off their original integer geometry"
fi
if rg -q 'visible: activeItem' hancore.shibumi.bar/core/WidgetSlot.qml; then
  fail "widget slot visibility must not depend on child effective visibility"
fi

for injected_name in bar moduleName hostGroupId settings; do
  rg -q "if \(\"${injected_name}\" in target\)" hancore.shibumi.bar/core/WidgetSlot.qml \
    || fail "widget slot does not inject $injected_name"
done
rg -q 'if \("availableWidth" in target\)' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "widget slots do not inject the monitor-local width budget"
rg -q 'onAvailableWidthChanged: injectProperties\(\)' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "center width changes are not forwarded reactively"
rg -Fq 'availableWidth: Math.max(1, horizontalSurface.centerAvailableWidth)' hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "center width budget is not monitor-local or becomes unconstrained"
rg -Fq '+ leftExtras.width + centerExtras.width + rightExtras.width' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "responsive staging omits unassigned provider widths"
rg -Fq 'centerGap, measuredCenterSpan, centerExtras.width)' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "center extras do not reduce the grouped center budget"
rg -Fq 'ResponsiveLayout.centerAvailableWidth(compactShell, width,' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "compact V2 shells measure the center against their own fitted width"
rg -Fq 'readonly property real responsiveCapacity: compactShell' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "compact V2 shells do not retain the monitor responsive capacity"
rg -Fq 'responsiveCapacity, narrowCandidateWidths' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "responsive staging still feeds back the content-sized V2 shell width"
rg -Fq 'void(root.stateRevision)' hancore.shibumi.bar/styles/shibumi/GroupSection.qml \
  || fail "V2 separator geometry does not react to state-service commits"
rg -Fq 'void(root.stateConfig)' hancore.shibumi.bar/styles/shibumi/GroupSection.qml \
  || fail "V2 separator geometry does not bind to the replaced state config"
rg -Fq 'if (persistentSeparators) return appearanceSeparator' \
  hancore.shibumi.bar/styles/shibumi/GroupSection.qml \
  || fail "V2 separators still inherit V1 positional split state"
for shell_contract in shellStyle shellWidth shellX shellContentInset; do
  rg -Fq "$shell_contract" hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
    || fail "Shibumi surface lost V2 shell geometry: $shell_contract"
done
[[ $(rg -c 'horizontalSurface\.shellContentInset' hancore.shibumi.bar/styles/shibumi/BarSurface.qml) -eq 2 ]] \
  || fail "Shibumi side rows do not follow the active shell inset"
rg -q 'color: root\.bar\.background' hancore.shibumi.bar/styles/shibumi/TooltipSurface.qml \
  || fail "Shibumi tooltip does not follow the bar surface color"
rg -q 'radius: root\.bar\.visualTokens\.tooltipRadius' hancore.shibumi.bar/styles/shibumi/TooltipSurface.qml \
  || fail "Shibumi tooltip does not use the V1 radius token"
rg -q 'active: !root\.bar\.barHidden' hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "Reactor renderer remains active while the bar is hidden"
rg -q 'root\.reactorMode >= 1 && root\.reactorMode <= 8' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "Mode 0 does not prevent Reactor renderer construction"
rg -q 'root\.reactorMode >= 7 \? reactorEventComponent' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "Modes 7-8 do not select the shared swarm renderer"
if rg -q '\b(Process|FileView)\b' hancore.shibumi.bar/styles/shibumi/GapEffectsLayer.qml; then
  fail "style-owned Reactor modes 1-6 must not own backend workers"
fi
[[ $(rg -c 'Timer \{' hancore.shibumi.bar/styles/shibumi/GapEffectsLayer.qml) -eq 1 ]] \
  || fail "Reactor visual layer must own exactly one frame timer"
if rg -q '\b(Process|FileView)\b' hancore.shibumi.bar/styles/shibumi/ReactorEventLayer.qml; then
  fail "style-owned Reactor mode 7 must not own backend workers"
fi
[[ $(rg -c 'Timer \{' hancore.shibumi.bar/styles/shibumi/ReactorEventLayer.qml) -eq 1 ]] \
  || fail "Mode 7 renderer must own exactly one adaptive frame timer"
rg -q 'target: "shibumi-reactor"' hancore.shibumi.reactor/Service.qml \
  || fail "Reactor control IPC target is missing"
rg -Fq 'desiredBackendMode: ready && (mode === 7 || mode === 8) ? mode : 0' \
  hancore.shibumi.reactor/Service.qml \
  || fail "Reactor backend is not lifecycle-lazy"
rg -Fq 'backendLoader.active = next !== 0' hancore.shibumi.reactor/Service.qml \
  || fail "Reactor deferred loader ignores current mode"
rg -q 'root\.loadedBackendMode === 7 \? eventBackendComponent' \
  hancore.shibumi.reactor/Service.qml \
  || fail "Mode 7 Reactor service is not selected lazily"
[[ $(rg -c 'ReactorService \{' hancore.shibumi.reactor/Service.qml) -eq 1 ]] \
  || fail "Mode 7 Reactor service must be process-wide"
[[ $(rg -c 'QuoteService \{' hancore.shibumi.reactor/Service.qml) -eq 1 ]] \
  || fail "Mode 8 quote service must be process-wide"
if rg -q '\b(Process|FileView)\b' hancore.shibumi.reactor/QuoteService.qml; then
  fail "Mode 8 must delegate acquisition to its one bounded source"
fi
[[ $(rg -c 'BoundedTextSource \{' hancore.shibumi.reactor/QuoteService.qml) -eq 1 ]] \
  || fail "Mode 8 must own exactly one bounded quote source"
[[ $(rg -c 'BoundedTextSource \{' hancore.shibumi.reactor/ReactorService.qml) -eq 2 ]] \
  || fail "Mode 7 must own exactly two bounded text sources"
if rg -q 'FileView[[:space:]]*\{' hancore.shibumi.reactor/ReactorService.qml; then
  fail "Mode 7 must not bypass bounded text acquisition"
fi
[[ $(rg -c 'Process \{' hancore.shibumi.reactor/BoundedTextSource.qml) -eq 1 ]] \
  || fail "each bounded source must coalesce into one reader"
[[ $(rg -c 'Timer \{' hancore.shibumi.reactor/BoundedTextSource.qml) -eq 1 ]] \
  || fail "each bounded source must own one deadline only"
[[ $(rg -c 'FileView[[:space:]]*\{' hancore.shibumi.reactor/BoundedTextSource.qml) -eq 1 ]] \
  || fail "each bounded source must own exactly one metadata watcher"
[[ $(rg -c '^[[:space:]]*preload:' hancore.shibumi.reactor/BoundedTextSource.qml) -eq 1 ]] \
  || fail "bounded watcher has ambiguous preload settings"
rg -q '^[[:space:]]*preload: false$' hancore.shibumi.reactor/BoundedTextSource.qml \
  || fail "bounded watcher must not buffer input"
[[ $(rg -c 'Timer \{' hancore.shibumi.reactor/QuoteService.qml) -eq 1 ]] \
  || fail "Mode 8 must schedule quotes through exactly one root timer"
if rg -q 'Quickshell\.(Networking|Services\.(Pipewire|Mpris|Notifications))' \
  hancore.shibumi.reactor/ReactorService.qml; then
  fail "Reactor service duplicates a Quattro-owned service backend"
fi
[[ $(rg -c 'Process \{' hancore.shibumi.reactor/ReactorService.qml) -eq 1 ]] \
  || fail "Mode 7 may own only the single legacy pacman event tail"
rg -Uq 'Process[[:space:]]*\{[[:space:]]*id: pacmanTail' hancore.shibumi.reactor/ReactorService.qml \
  || fail "Mode 7 direct process is not the existing pacman tail"
rg -q 'firstPartyService\("omarchy\.media"\)' hancore.shibumi.reactor/ReactorService.qml \
  || fail "Reactor media events bypass Quattro media ownership"
rg -q 'statusService\.notificationService' hancore.shibumi.reactor/ReactorService.qml \
  || fail "Reactor notification events bypass Quattro notification ownership"
rg -q 'item\.screenName = barWindow\.screen' hancore.shibumi.bar/core/BarPanel.qml \
  || fail "Reactor renderer does not receive its physical output name"
rg -q 'G8: \["hancore.shibumi.center"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G8 is not owned by the Shibumi center composite"
rg -q 'G2: \["hancore.shibumi.workspaces"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G2 is not owned by the extracted Shibumi workspace plugin"
rg -q 'PanelRouting.findPanelWidget' hancore.shibumi.bar/Bar.qml \
  || fail "nested panel routing is not active"
rg -q 'PanelRouting.findPanelWidgetForScreen' hancore.shibumi.bar/Bar.qml \
  || fail "bar-widget IPC does not route to a requested output"
rg -q 'Hyprland.focusedMonitor' hancore.shibumi.bar/Bar.qml \
  || fail "bar-widget IPC does not prefer the focused output"
rg -q 'property string screenName:' hancore.shibumi.bar/core/WidgetSlot.qml \
  || fail "widget slots do not accept explicit output identity"
rg -q 'screenName: root\.screenName' hancore.shibumi.bar/core/GroupSlot.qml hancore.shibumi.bar/core/BarSection.qml \
  || fail "bar/group sections do not propagate explicit output identity"
rg -Fq 'screenName: root ? root.screenName : ""' \
  hancore.shibumi.bar/styles/shibumi/GroupSection.qml \
  || fail "group renderer does not propagate guarded output identity"
rg -q 'function childPanelWidget\(pluginId\)' hancore.shibumi.center/BarWidget.qml \
  || fail "center composite does not expose nested weather routing"
rg -q 'G3: \["hancore.shibumi.status"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G3 is not owned by the Shibumi status composite"
for consumed_alias in omarchy.audio omarchy.clock omarchy.network omarchy.power; do
  rg -Fq "\"$consumed_alias\"" hancore.shibumi.bar/core/GroupRegistry.js \
    || fail "stock Omarchy alias leaks into Shibumi: $consumed_alias"
done
rg -Fq 'entry.shibumiModule === true' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "explicit Quattro modules cannot opt into the Shibumi bar"
rg -q 'hancore\.shibumi\.status' contracts/plugin-suite-v1.json \
  || fail "Shibumi status composite is not registered"
rg -q 'hancore\.shibumi\.update-center' hancore.shibumi.status/BarWidget.qml \
  || fail "G3 status presentation does not own the Shibumi update center"
if rg -q 'omarchy\.system-update' hancore.shibumi.status/BarWidget.qml; then
  fail "G3 status presentation must not own the Omarchy update widget"
fi
rg -q 'omarchy\.system-update' hancore.shibumi.center/BarWidget.qml \
  || fail "G8 center presentation does not own the Omarchy update widget"
rg -q 'StatusIndicators' hancore.shibumi.center/BarWidget.qml \
  || fail "G8 does not render the V1 status indicator facade"
rg -q 'SystemUpdateWidget' hancore.shibumi.center/BarWidget.qml \
  || fail "G8 does not render the V1 Omarchy-update facade"
rg -q '^  width: implicitWidth$' hancore.shibumi.center/SystemUpdateWidget.qml \
  || fail "G8 update indicator does not expose its visual width as a hit target"
rg -q '^  height: implicitHeight$' hancore.shibumi.center/SystemUpdateWidget.qml \
  || fail "G8 update indicator does not expose its visual height as a hit target"
if rg -q 'Process \{|Timer \{|IpcHandler \{' hancore.shibumi.center/SystemUpdateWidget.qml; then
  fail "Omarchy-update facade duplicates the official backend owner"
fi
rg -q 'onTabRequested' hancore.shibumi.center/CalendarPanel.qml \
  || fail "G8 calendar is missing sibling-panel keyboard routing"
rg -q 'Presentation\.ShibumiPillToolTip \{' hancore.shibumi.center/CalendarPanel.qml \
  || fail "G8 calendar navigation bypasses the Shibumi tooltip"
if rg -q 'registeredSource\("omarchy\.indicators"\)' hancore.shibumi.center/BarWidget.qml; then
  fail "G8 must not instantiate Quattro's stock indicator presentation"
fi
rg -q '"service": "Service.qml"' hancore.shibumi.status/manifest.json \
  || fail "status backend is not process-wide"
rg -q 'WeatherService \{' hancore.shibumi.center/Service.qml \
  || fail "weather backend is not process-wide"
rg -q 'WeatherWidget' hancore.shibumi.center/BarWidget.qml \
  || fail "G8 does not render the V1 weather facade"
if rg -q 'SystemTray\.items|NotificationServer|Process \{|FileView \{' \
  hancore.shibumi.status/BarWidget.qml hancore.shibumi.status/TrayStatusView.qml \
  hancore.shibumi.status/NotificationStatusView.qml hancore.shibumi.status/TrayDrawerPanel.qml; then
  fail "status composite must not duplicate official service or polling ownership"
fi
[[ $(rg -c 'Timer \{' hancore.shibumi.status/BarWidget.qml) -eq 1 ]] \
  || fail "status composite must own exactly one lifecycle timer"
rg -U -q 'Timer \{\n[[:space:]]*id: childSyncTimer\n[[:space:]]*interval: 0\n' \
  hancore.shibumi.status/BarWidget.qml \
  || fail "status lifecycle timer must be the zero-delay child loader sync"
if rg -q 'Timer \{' hancore.shibumi.status/TrayStatusView.qml \
    hancore.shibumi.status/NotificationStatusView.qml hancore.shibumi.status/TrayDrawerPanel.qml; then
  fail "status child presentations must not own timers"
fi
rg -q 'trayBackend: root\.trayWidget' hancore.shibumi.status/BarWidget.qml \
  || fail "G3 tray presentation is not bound to the official tray owner"
rg -q 'notificationService: root\.notificationService' hancore.shibumi.status/BarWidget.qml \
  || fail "G3 notification presentation is not bound to the official service"
rg -q 'G6: \["hancore.shibumi.audio"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G6 is not owned by the Shibumi audio composite"
rg -q 'hancore\.shibumi\.audio' contracts/plugin-suite-v1.json \
  || fail "Shibumi audio composite is not registered"
rg -q 'AudioPanelBridge' hancore.shibumi.audio/BarWidget.qml \
  || fail "audio view does not use the primitive backend bridge"
rg -q 'nativeAudioService: root\.nativeBackendAccessEnabled' \
  hancore.shibumi.audio/BarWidget.qml \
  || fail "audio view is not wired to the native process-wide service"
rg -q 'property bool nativeBackendEnabled: true' \
  hancore.shibumi.audio/Service.qml \
  || fail "native audio ownership is not atomically enabled"
rg -q 'popupSource: Qt\.resolvedUrl\("AudioPanel\.qml"\)' hancore.shibumi.audio/BarWidget.qml \
  || fail "audio widget does not lazy-load the Shibumi mixer panel"
rg -q 'return String\(pluginId \|\| ""\) === "omarchy\.audio" \? root : null' \
  hancore.shibumi.audio/BarWidget.qml \
  || fail "official audio routing is not redirected to the Shibumi owner"
rg -q 'manageIpc: false' hancore.shibumi.audio/BarWidget.qml \
  || fail "audio aliases must use screen-aware host routing, not duplicate IPC handlers"
if rg -q 'Quickshell\.Services\.Pipewire|Pipewire\.' hancore.shibumi.audio/BarWidget.qml; then
  fail "Shibumi audio presentation must not create a second PipeWire owner"
fi
rg -q 'Pipewire\.ready === true' hancore.shibumi.audio/AudioPanelBridge.qml \
  || fail "transitional audio bridge does not use the authoritative PipeWire readiness signal"
if rg -q 'Process \{|FileView \{' hancore.shibumi.audio/BarWidget.qml \
  hancore.shibumi.audio/AudioPanelBridge.qml; then
  fail "audio presentation bridge must remain event-driven and worker-free"
fi
rg -q 'panelLoader\.active = false' hancore.shibumi.audio/AudioPanelBridge.qml \
  || fail "audio backend panel is not unloaded before its host facade"
if rg -q 'panel\.bar = null' hancore.shibumi.audio/AudioPanelBridge.qml; then
  fail "audio teardown invalidates the host facade before panel destruction"
fi
[[ $(rg -c 'Timer \{' hancore.shibumi.audio/BarWidget.qml) -eq 2 ]] \
  || fail "audio widget must own only the bounded wheel commit/settle timers"
rg -U -q 'Timer \{\n[[:space:]]*id: wheelCommitTimer\n[[:space:]]*interval: 70\n' \
  hancore.shibumi.audio/BarWidget.qml \
  || fail "audio wheel commit timer contract changed"
rg -U -q 'Timer \{\n[[:space:]]*id: wheelSettleTimer\n[[:space:]]*interval: 1000\n' \
  hancore.shibumi.audio/BarWidget.qml \
  || fail "audio wheel settle timer contract changed"
if rg -U -q 'Timer \{([^}]|\n)*(repeat:[[:space:]]*true|running:[[:space:]]*true)' \
  hancore.shibumi.audio/BarWidget.qml; then
  fail "audio wheel timers must remain dormant, non-repeating interaction timers"
fi
[[ $(rg -c 'PwNodePeakMonitor \{' hancore.shibumi.audio/AudioBackendAdapter.qml) -eq 1 ]] \
  || fail "native audio backend must own exactly one microphone meter"
rg -q 'audioBackend\.inputPeak' hancore.shibumi.audio/AudioPanel.qml \
  || fail "audio panel does not consume the primitive microphone peak"
rg -q 'next\.acquirePeakMonitoring\(\)' hancore.shibumi.audio/AudioPanel.qml \
  || fail "audio panel does not acquire microphone peak monitoring"
rg -q 'backend\.releasePeakMonitoring\(\)' hancore.shibumi.audio/AudioPanel.qml \
  || fail "audio panel does not release microphone peak monitoring"
rg -q 'enabled: root\.active && root\.peakMonitoringEnabled' \
  hancore.shibumi.audio/AudioBackendAdapter.qml \
  || fail "microphone meter is not bounded to the native backend lifecycle"
if rg -q 'Pipewire\.|Process \{|FileView \{' hancore.shibumi.audio/AudioPanel.qml; then
  fail "Shibumi audio panel duplicates Quattro audio ownership or shell workers"
fi
rg -q 'displaySinks = \[\]' hancore.shibumi.audio/AudioPanel.qml \
  || fail "audio panel does not release sink rows on close"
rg -q 'displaySources = \[\]' hancore.shibumi.audio/AudioPanel.qml \
  || fail "audio panel does not release source rows on close"
rg -q 'displayStreams = \[\]' hancore.shibumi.audio/AudioPanel.qml \
  || fail "audio panel does not release stream rows on close"
rg -q 'G9: \["hancore.shibumi.media"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G9 is not owned by the Shibumi media presentation"
rg -q 'hancore\.shibumi\.media' contracts/plugin-suite-v1.json \
  || fail "Shibumi media presentation is not registered"
rg -q 'firstPartyServiceFor\("omarchy\.media"\)' hancore.shibumi.media/BarWidget.qml \
  || fail "media presentation does not reuse the official service"
if rg -q 'Quickshell\.Services\.(Mpris|Pipewire)|Mpris\.|Pipewire\.' \
  hancore.shibumi.media/BarWidget.qml hancore.shibumi.media/MediaPanel.qml hancore.shibumi.media/MediaPulse.qml \
  hancore.shibumi.media/MediaSpectrum.qml hancore.shibumi.media/MediaMuse.qml \
  hancore.shibumi.media/Service.qml; then
  fail "Shibumi media presentation must not create a second media owner"
fi
if rg -q 'Process \{|Timer \{|FileView \{' hancore.shibumi.media/BarWidget.qml \
  hancore.shibumi.media/MediaPulse.qml hancore.shibumi.media/MediaSpectrum.qml hancore.shibumi.media/MediaMuse.qml; then
  fail "closed media bar presentation must remain worker-free"
fi
rg -q 'serviceFor\("hancore\.shibumi\.media"\)' hancore.shibumi.media/BarWidget.qml \
  || fail "media presentation does not resolve the process-wide spectrum service"
[[ $(rg -c 'Process \{' hancore.shibumi.media/Service.qml) -eq 2 ]] \
  || fail "media spectrum service must own one probe and one Cava process"
rg -q 'property var spectrumClients: \[\]' hancore.shibumi.media/Service.qml \
  || fail "media spectrum service lacks multi-output lease accounting"
rg -q 'readonly property bool spectrumWanted: runtimeWorkersEnabled' \
  hancore.shibumi.media/Service.qml \
  || fail "media spectrum worker is not lazy"
rg -q 'maximumRetries: 3' hancore.shibumi.media/Service.qml \
  || fail "media spectrum retry policy is not bounded"
rg -q 'target: "shibumi-media-spectrum"' hancore.shibumi.media/Service.qml \
  || fail "media spectrum service lacks read-only runtime diagnostics"
rg -q 'bars = 24' hancore.shibumi.media/Service.qml \
  || fail "media spectrum service does not preserve the V1 band count"
if rg -q 'Process \{|FileView \{' hancore.shibumi.media/MediaPanel.qml \
  hancore.shibumi.media/MediaPanel.qml; then
  fail "screen-local media panels must not own spectrum workers"
fi
rg -q 'G10: \["hancore.shibumi.quick-access"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G10 is not owned by the Shibumi quick-access presentation"
rg -q 'hancore\.shibumi\.quick-access' contracts/plugin-suite-v1.json \
  || fail "Shibumi quick-access presentation is not registered"
rg -q 'IdleInhibitor \{' hancore.shibumi.quick-access/BarWidget.qml \
  || fail "G10 idle inhibitor is not attached to the output surface"
rg -q 'readonly property bool overlayLoaded: overlayLoader\.item !== null' \
  hancore.shibumi.quick-access/Service.qml \
  || fail "G10 picker/media controller is not process-wide"
rg -q 'target: "shibumi-picker"' hancore.shibumi.quick-access/Service.qml \
  || fail "G10 picker/media IPC target is missing"
rg -q 'Hyprland\.focusedMonitor' hancore.shibumi.quick-access/Service.qml \
  || fail "G10 IPC picker does not resolve the focused output"
rg -Fq ': Quickshell.screens' hancore.shibumi.quick-access/Service.qml \
  || fail "G10 IPC picker does not use the public reactive screen collection"
if rg -Fq 'bar.screenForName' hancore.shibumi.quick-access/Service.qml; then
  fail "G10 IPC picker traverses the private/full bar for output objects"
fi
if rg -q 'Commons\.Style\.font\.size\.' hancore.shibumi.quick-access/PickerOverlay.qml \
  hancore.shibumi.quick-access/PickerImage.qml hancore.shibumi.quick-access/TanzakuPickerView.qml \
  hancore.shibumi.quick-access/HearthstonePickerView.qml; then
  fail "G10 picker uses V1-only font token paths"
fi
rg -q 'Commons\.Util\.fileUrl\(entry\.thumbnailPath\)' \
  hancore.shibumi.quick-access/Service.qml \
  || fail "G10 thumbnail URLs do not use the host-safe file URL helper"
rg -q 'file -Lb --mime-type' hancore.shibumi.quick-access/Service.qml \
  || fail "G10 screenshot copy hard-codes an incorrect image MIME type"
for picker_view in hancore.shibumi.quick-access/TanzakuPickerView.qml \
  hancore.shibumi.quick-access/HearthstonePickerView.qml; do
  if rg -q 'Process \{|Timer \{|FileView \{' "$picker_view"; then
    fail "picker presentation owns controller work: $picker_view"
  fi
done
rg -q 'readonly property bool spectrumRequested: open && active && spectrumEnabled' \
  hancore.shibumi.media/MediaPanel.qml \
  || fail "media spectrum worker is not panel-lifecycle gated"
rg -q 'command: \["cava", "-p", "/dev/stdin"\]' \
  hancore.shibumi.media/Service.qml \
  || fail "process-wide media spectrum does not own the Cava process"
rg -q 'stdinEnabled: true' hancore.shibumi.media/Service.qml \
  || fail "media spectrum configuration is not streamed over stdin"
if rg -q 'mktemp|/tmp/|<\(printf' hancore.shibumi.media/Service.qml; then
  fail "media spectrum worker must not create temporary config artifacts"
fi
rg -q 'G11: \["hancore.shibumi.network"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G11 is not owned by the Shibumi network presentation"
rg -q 'hancore\.shibumi\.network' contracts/plugin-suite-v1.json \
  || fail "Shibumi network presentation is not registered"
for owner in NetworkLivenessContinuity NetworkManagerLiveness \
    NetworkProfileCatalog NetworkTelemetry NetworkReachability \
    NetworkBackendAdapter NetworkScannerLease NetworkEnterpriseDispatcher \
    NetworkActionCoordinator NetworkSpeedTest NetworkProfileActionDispatcher \
    NetworkProfileActionLease \
    NetworkPanelBridge; do
  [[ $(rg -c "^[[:space:]]*$owner \\{" \
    hancore.shibumi.network/Service.qml) -eq 1 ]] \
    || fail "network service must own exactly one native $owner"
done
if rg -q 'NetworkPanelBridge|Quickshell\.Networking|Networking\.' \
  hancore.shibumi.network/BarWidget.qml hancore.shibumi.network/NetworkPanel.qml; then
  fail "screen-local network presentation must not own NetworkManager"
fi
if rg -q 'Process \{|FileView \{' hancore.shibumi.network/BarWidget.qml \
  hancore.shibumi.network/NetworkPanel.qml hancore.shibumi.network/NetworkPanelBridge.qml; then
  fail "screen-local network presentation must not own backend workers"
fi
rg -q 'property var ownerRecords: \[\]' hancore.shibumi.network/Service.qml \
  || fail "network service lacks multi-output lease accounting"
rg -q 'scanner\.release\(owner\)' hancore.shibumi.network/Service.qml \
  || fail "network scanner is not released after panel sessions"
rg -q 'reachability\.release\(owner\)' hancore.shibumi.network/Service.qml \
  || fail "network reachability is not released after panel sessions"
rg -q 'catalog\.release\(owner\)' hancore.shibumi.network/Service.qml \
  || fail "saved-profile catalog is not released after panel sessions"
rg -q 'telemetry\.release\(owner\)' hancore.shibumi.network/Service.qml \
  || fail "network telemetry is not demand-driven"
if rg -q 'InlineSpeedTestRunner|omarchy-network-|\bnmcli\b' \
    hancore.shibumi.network; then
  fail "native Network cutover retained a legacy backend helper"
fi
rg -q 'childPanelWidget\("omarchy\.network"\)' tests/network-plugin-smoke.qml \
  || fail "network alias routing is not regression-tested"
rg -q 'G13: \["hancore.shibumi.brightness"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G13 is not owned by the Shibumi brightness presentation"
rg -q 'hancore\.shibumi\.brightness' contracts/plugin-suite-v1.json \
  || fail "Shibumi brightness presentation is not registered"
[[ $(rg -c 'MonitorPanelBridge \{' hancore.shibumi.brightness/Service.qml) -eq 1 ]] \
  || fail "brightness service must own exactly one official backend"
rg -q 'serviceFor\("hancore\.shibumi\.brightness"\)' \
  hancore.shibumi.brightness/BarWidget.qml \
  || fail "brightness view does not consume the shared monitor owner"
if rg -q 'Quickshell\.Services\.UPower|UPower\.|Quickshell\.Io' \
  hancore.shibumi.brightness/BarWidget.qml hancore.shibumi.brightness/BrightnessPanel.qml \
  hancore.shibumi.brightness/MonitorPanelBridge.qml hancore.shibumi.brightness/Service.qml; then
  fail "Shibumi brightness presentation must not create a second monitor owner"
fi
if rg -q 'Process \{|FileView \{' hancore.shibumi.brightness/BarWidget.qml \
  hancore.shibumi.brightness/BrightnessPanel.qml hancore.shibumi.brightness/Service.qml \
  hancore.shibumi.brightness/MonitorPanelBridge.qml \
  || rg -q 'Timer \{' hancore.shibumi.brightness/BarWidget.qml \
    hancore.shibumi.brightness/BrightnessPanel.qml hancore.shibumi.brightness/Service.qml; then
  fail "brightness presentation and monitor adapter must remain worker-free"
fi
bridge=hancore.shibumi.brightness/MonitorPanelBridge.qml
[[ $(rg -o 'Timer[[:space:]]*\{' "$bridge" | wc -l) -eq 3 ]] \
  || fail "monitor adapter must own exactly three deferred timers"
if rg -q '\b(repeat|running)[[:space:]]*:' "$bridge"; then
  fail "monitor adapter deferred timers must not repeat or run independently"
fi
rg -Uq 'Timer \{\n[[:space:]]*id: panelSync\n[[:space:]]*interval: 0\n[[:space:]]*onTriggered: root\.syncPanelSource\(\)\n[[:space:]]*\}' "$bridge" \
  || fail "monitor adapter panel sync is not zero-interval and owner-bound"
rg -Uq 'Timer \{\n[[:space:]]*id: panelInjection\n[[:space:]]*interval: 0\n[[:space:]]*onTriggered: root\.injectPanel\(\)\n[[:space:]]*\}' "$bridge" \
  || fail "monitor adapter panel injection is not zero-interval and owner-bound"
rg -Uq 'Timer \{\n[[:space:]]*id: hiddenClose\n[[:space:]]*interval: 0\n[[:space:]]*onTriggered: \{\n([^\n]*\n){0,3}[[:space:]]*&& typeof root\.panel\.close === "function"\) root\.panel\.close\(\)\n[[:space:]]*\}\n[[:space:]]*\}' "$bridge" \
  || fail "monitor adapter hidden close is not zero-interval and owner-bound"
rg -Uq 'function shutdown\(\) \{\n([^\n]*\n){0,4}[[:space:]]*panelSync\.stop\(\)\n[[:space:]]*panelInjection\.stop\(\)\n[[:space:]]*hiddenClose\.stop\(\)' "$bridge" \
  || fail "monitor adapter shutdown does not stop every deferred timer"
if rg -q '^[[:space:]]*selected:' hancore.shibumi.brightness/BrightnessPanel.qml; then
  fail "brightness panel uses Button-only selected state on CursorSurface"
fi
rg -q 'childPanelWidget\("omarchy\.monitor"\)' tests/brightness-plugin-smoke.qml \
  || fail "monitor alias routing is not regression-tested"
rg -q 'G12: \["hancore.shibumi.battery"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G12 is not owned by the Shibumi battery presentation"
rg -q 'G14: \["hancore.shibumi.power-profile"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G14 is not owned by the Shibumi power-profile presentation"
for power_widget in hancore.shibumi.battery hancore.shibumi.power-profile; do
  rg -q "$power_widget" contracts/plugin-suite-v1.json \
    || fail "Shibumi power presentation is not registered: $power_widget"
done
rg -q '"service": "Service.qml"' hancore.shibumi.power-state/manifest.json \
  || fail "battery/profile state must have one process-wide power owner"
rg -q 'Quickshell.Services.UPower' hancore.shibumi.power-state/Service.qml \
  || fail "power owner does not consume the event-driven UPower singleton"
rg -Fq 'commandFor("profiles", ["omarchy-powerprofiles-list", "--active-state"])' \
  hancore.shibumi.power-state/Service.qml \
  || fail "power owner does not use the Quattro profile contract"
rg -Fq 'commandFor("activeProfile", ["busctl", "--system", "get-property",' \
  hancore.shibumi.power-state/Service.qml \
  || fail "power owner does not use the lightweight active-profile probe"
rg -Fq 'onTriggered: root.refreshActiveProfile()' \
  hancore.shibumi.power-state/Service.qml \
  || fail "power hot path still refreshes the complete profile list"
rg -Fq 'interval: 5 * 60 * 1000' hancore.shibumi.power-state/Service.qml \
  || fail "power profile list does not have a bounded reconcile fallback"
rg -q 'omarchy-battery-status --shell' \
  hancore.shibumi.power-state/Service.qml \
  || fail "power owner does not use the Quattro battery detail contract"
[[ $(rg -c 'PowerCommand \{' hancore.shibumi.power-state/Service.qml) -eq 4 ]] \
  || fail "power owner must retain exactly four operation slots"
[[ $(rg -c 'Process \{' hancore.shibumi.power-state/PowerCommand.qml) -eq 1 ]] \
  || fail "each power operation slot must own exactly one process"
if rg -q 'Quickshell\.Services\.UPower|Quickshell\.Io|Process \{|Timer \{|FileView \{' \
  hancore.shibumi.battery/BarWidget.qml hancore.shibumi.battery/BatteryPanel.qml \
  hancore.shibumi.power-profile/BarWidget.qml hancore.shibumi.power-profile/PowerProfilePanel.qml; then
  fail "power views must not duplicate UPower, worker, or polling ownership"
fi
rg -q 'acquireBatteryDetails' hancore.shibumi.battery/BarWidget.qml \
  || fail "battery detail process is not panel-lifecycle gated"
rg -q 'releaseBatteryDetails' hancore.shibumi.battery/BarWidget.qml \
  || fail "battery detail process lease is not released"
for monitor_plugin in cpu memory battery; do
  rg -q 'bar\.run\("omarchy-launch-or-focus-tui btop"\)' \
    "hancore.shibumi.${monitor_plugin}/BarWidget.qml" \
    || fail "$monitor_plugin does not use the Quattro TUI launcher"
  panel_name="$(tr '[:lower:]' '[:upper:]' \
    <<<"${monitor_plugin:0:1}")${monitor_plugin:1}Panel.qml"
  rg -q 'panel\.ownerWidget\.openSystemMonitor\(\)' \
    "hancore.shibumi.${monitor_plugin}/${panel_name}" \
    || fail "$monitor_plugin panel bypasses its owner action"
done
rg -q 'acquireProfiles' hancore.shibumi.power-profile/BarWidget.qml \
  || fail "profile state does not use the shared service lease"
rg -q 'releaseProfiles' hancore.shibumi.power-profile/BarWidget.qml \
  || fail "profile state lease is not released"
rg -q 'G15: \["hancore.shibumi.bluetooth"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G15 is not owned by the Shibumi bluetooth presentation"
jq -e '
  .id == "hancore.shibumi.bluetooth" and
  .entryPoints.barWidget == "BarWidget.qml" and
  .entryPoints.service == "Service.qml"
' hancore.shibumi.bluetooth/manifest.json >/dev/null \
  || fail "Shibumi Bluetooth plugin entry points are not declared"
bluetooth_service=hancore.shibumi.bluetooth/Service.qml
bluetooth_adapter=hancore.shibumi.bluetooth/BluetoothBackendAdapter.qml
bluetooth_audio_route=hancore.shibumi.bluetooth/BluetoothAudioRouteAdapter.qml
bluetooth_widget=hancore.shibumi.bluetooth/BarWidget.qml
bluetooth_panel=hancore.shibumi.bluetooth/BluetoothPanel.qml
[[ $(rg -c 'BluetoothBackendAdapter \{' "$bluetooth_service") -eq 1 ]] \
  || fail "Bluetooth state must have one shipped native owner"
rg -q 'serviceFor\("hancore\.shibumi\.bluetooth"\)' "$bluetooth_widget" \
  || fail "Bluetooth view does not resolve the shipped service"
rg -q 'property var sessionOwners: \[\]' "$bluetooth_service" \
  || fail "Bluetooth service lacks multi-output session accounting"
rg -q 'target: "omarchy\.bluetooth"' "$bluetooth_service" \
  || fail "Bluetooth service does not own the single legacy IPC target"
rg -q 'bar\.hideBarWidget\("omarchy\.bluetooth"\)' "$bluetooth_service" \
  || fail "Bluetooth legacy close/hide is not routed to the local panel"
rg -q 'adapter\.stopDiscovery\(\)' "$bluetooth_service" \
  || fail "Bluetooth discovery is not stopped after the final panel closes"
for bluetooth_adapter in "$bluetooth_adapter"; do
  rg -q '^import Quickshell\.Bluetooth$' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not own the native BlueZ model"
  [[ -f $bluetooth_audio_route ]] \
    || fail "$bluetooth_audio_route is missing"
  rg -q '^import Quickshell\.Services\.Pipewire$' "$bluetooth_audio_route" \
    || fail "$bluetooth_audio_route does not own PipeWire access"
  rg -q 'audioRouteOverride' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not expose the process-wide audio route seam"
  rg -q 'enabled: root\.audioRouteHandoffReady' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not gate its legacy PipeWire route"
  rg -q 'root\.audioRouteOverride === null && root\.backendOverride === null' \
    "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not disable its legacy PipeWire route after cutover"
  rg -Fq 'routeBluetoothDevice(request)' "$bluetooth_audio_route" \
    || fail "$bluetooth_audio_route lacks its narrow route method"
  for device_signal in ConnectedDevices KnownDevices DiscoveredDevices; do
    rg -U -q "on${device_signal}Changed: \\{[^}]*syncNativePendingActions\\(\\)[^}]*syncNativeAudioHandoffIntents\\(\\)" \
      "$bluetooth_adapter" \
      || fail "$bluetooth_adapter ignores ${device_signal} property transitions"
  done
  rg -Fq 'if (discovering && !discoveryOwned) return true' \
    "$bluetooth_adapter" \
    || fail "$bluetooth_adapter can claim an external discovery scan"
  rg -q 'property var discoveryOwnerAdapter: null' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not bind discovery ownership to an adapter"
  rg -U -q 'function confirmRequestedDiscovery\(\) \{(.|\n)*?requested\.discovering(.|\n)*?discoveryOwned = true(.|\n)*?\n  \}' \
    "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not confirm discovery ownership from observed state"
  rg -q 'property var audioHandoffIntent: null' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter lacks explicit latest-only audio intent state"
  rg -Fq 'nativeDeviceSnapshots())' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter publishes native QObjects instead of detached records"
  rg -q 'function resolveNativeDevice\(' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not resolve current entities before mutation"
  if rg -q 'device\.(connect|disconnect|pair|forget)\(' "$bluetooth_adapter"; then
    fail "$bluetooth_adapter has more than one device mutation path"
  fi
  rg -U -q 'function validatePendingAudioOutput\(\)[^}]*resolveNativeDevice\([^}]*!device\.connected[^}]*!deviceUsesCurrentAdapter' \
    "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not revalidate audio handoff identity/state"
  [[ $(rg -c '^  Timer \{' "$bluetooth_adapter") -eq 4 ]] \
    || fail "$bluetooth_adapter must have exactly four bounded lifecycle timers"
  if rg -q 'IpcHandler \{|Loader \{|panelSource|panelComponent|registeredWidget' \
      "$bluetooth_adapter"; then
    fail "$bluetooth_adapter still owns IPC or loads a foreign UI component"
  fi
done
rg -U -q 'id: discoveryRetry[^}]*repeat: true[^}]*running: root\.sessionCount > 0 && root\.adapterAvailable[^}]*root\.radioEnabled && !root\.discovering' \
  "$bluetooth_service" \
  || fail "Bluetooth service does not bound discovery retries to an open session"
if rg -q 'registeredWidget|registeredSource|registeredComponent|panelSource|panelComponent|Loader \{' \
    "$bluetooth_service"; then
  fail "Bluetooth service still resolves or loads the complete Omarchy panel"
fi
rg -q 'serviceFor\("hancore\.shibumi\.audio"\)' "$bluetooth_service" \
  || fail "Bluetooth service does not resolve the process-wide audio owner"
rg -q 'audioRouteOverride: root\.audioRouteOverride' "$bluetooth_service" \
  || fail "Bluetooth service does not hand off audio routing atomically"
if rg -q 'Quickshell\.Bluetooth|Quickshell\.Services\.Pipewire|Bluetooth\.|Pipewire\.' \
    "$bluetooth_widget" "$bluetooth_panel"; then
  fail "Bluetooth presentation bypasses the process-wide native adapter"
fi
if rg -q 'Process \{|Timer \{|FileView \{' \
    "$bluetooth_widget" "$bluetooth_panel"; then
  fail "Bluetooth presentation must remain worker-free"
fi
if rg -q 'Process \{|FileView \{' "$bluetooth_service" "$bluetooth_adapter"; then
  fail "Bluetooth native owner uses a worker instead of native APIs"
fi
rg -q 'childPanelWidget\("omarchy\.bluetooth"\)' tests/bluetooth-plugin-smoke.qml \
  || fail "Bluetooth alias routing is not regression-tested against shipped code"
rg -Fq 'result.ok === true' "$bluetooth_panel" \
  || fail "Bluetooth panel treats structured action results as booleans"
[[ -f tests/bluetooth-device-identity-regression.qml ]] \
  || fail "Bluetooth stale-identity regression is missing"

[[ $(rg -c 'SystemTelemetry \{' hancore.shibumi.telemetry/Service.qml) -eq 1 ]] \
  || fail "system telemetry must have one process-wide owner"
if rg -q 'Process \{' hancore.shibumi.telemetry/SystemTelemetry.qml; then
  fail "system telemetry must read procfs without child processes"
fi
rg -q '"service": "WorkspaceService.qml"' hancore.shibumi.workspaces/manifest.json \
  || fail "workspace state must have exactly one shipped owner"
workspace_service=hancore.shibumi.workspaces/WorkspaceService.qml
workspace_actions=hancore.shibumi.workspaces/WorkspaceActions.qml
workspace_widget=hancore.shibumi.workspaces/BarWidget.qml
workspace_panel=hancore.shibumi.workspaces/WorkspacePanel.qml
workspace_panel_content=hancore.shibumi.workspaces/WorkspacePanelContent.qml
[[ $(rg -c 'ClockService \{' hancore.shibumi.center/Service.qml) -eq 1 ]] \
  || fail "clock state must have exactly one process-wide owner"
if rg -q 'Process \{|Timer \{|FileView \{' hancore.shibumi.center/ClockService.qml \
  hancore.shibumi.center/ClockWidget.qml; then
  fail "clock slice must use the shared event-driven SystemClock"
fi
rg -q 'Ui\.WidgetButton \{' hancore.shibumi.center/ClockWidget.qml \
  || fail "clock interaction is not registered for overlay click forwarding"
[[ $(rg -c 'WorkspaceActions \{' hancore.shibumi.workspaces/WorkspaceService.qml) -eq 1 ]] \
  || fail "workspace actions must have exactly one root adapter"
[[ $(rg -c 'Core\.LayoutController \{' hancore.shibumi.bar/Bar.qml) -eq 1 ]] \
  || fail "layout persistence must have exactly one root controller"
[[ $(rg -c '^  DragSession \{' hancore.shibumi.bar/core/BarPanel.qml) -eq 1 ]] \
  || fail "each output must own exactly one transient drag session"
rg -q 'stateService: root\.pluginService\("hancore\.shibumi\.state"\)' hancore.shibumi.bar/Bar.qml \
  || fail "layout controller is not bound to normalized Shibumi state"
rg -q 'stateService\.setLayout' hancore.shibumi.bar/core/LayoutController.qml \
  || fail "layout mutations bypass the process-wide state owner"
rg -q 'layoutController: barWindow\.bar\.layoutController' hancore.shibumi.bar/core/BarPanel.qml \
  || fail "per-output drag session does not consume shared layout state"
for drag_geometry_contract in \
  'property real originX: 0' \
  'property real originY: 0' \
  'property string geometryKey: ""' \
  'onOriginXChanged: cancelForGeometryChange()' \
  'onOriginYChanged: cancelForGeometryChange()' \
  'onGeometryKeyChanged: cancelForGeometryChange()' \
  'function toOutputPoint(localX, localY)' \
  'function targetAtOutput(outputX, outputY)'; do
  rg -Fq "$drag_geometry_contract" hancore.shibumi.bar/core/DragSession.qml \
    || fail "drag output-geometry contract drifted: $drag_geometry_contract"
done
for bound_geometry_contract in \
  'originX: barWindow.bar.vertical && barWindow.bar.position === "right"' \
  'originY: !barWindow.bar.vertical && barWindow.bar.position === "bottom"' \
  'geometryKey: JSON.stringify([' \
  'String(barWindow.screen.name || "")' \
  'Number(barWindow.screen.width) || 0' \
  'Number(barWindow.screen.height) || 0' \
  'Number(barWindow.screen.devicePixelRatio) || 1' \
  'String(barWindow.bar.position || "")' \
  'Number(barWindow.bar.barSize) || 0'; do
  rg -Fq "$bound_geometry_contract" hancore.shibumi.bar/core/BarPanel.qml \
    || fail "bar does not bind complete primitive drag geometry: $bound_geometry_contract"
done
rg -q 'item\.layoutSession = dragSession' hancore.shibumi.bar/core/BarPanel.qml \
  || fail "bar surface does not receive its per-output drag session"
if rg -q 'LayoutController \{|DragSession \{' styles; then
  fail "styles must not own layout persistence or drag sessions"
fi
if rg -q 'Process \{|Timer \{|FileView \{' hancore.shibumi.bar/core/LayoutController.qml \
  hancore.shibumi.bar/core/DragSession.qml; then
  fail "layout and drag core must remain event-driven and worker-free"
fi
rg -q 'serviceFor\("hancore\.shibumi\.workspaces"\)' "$workspace_widget" \
  || fail "workspace widget does not resolve the shipped service"
rg -q '^ShibumiPanel \{' "$workspace_panel" \
  || fail "workspace panel does not use the screen-local keyboard panel contract"
if rg -q 'Process \{|Timer \{|FileView \{' \
    "$workspace_service" "$workspace_widget" "$workspace_panel" \
    "$workspace_panel_content"; then
  fail "workspace state and views must remain event-driven and worker-free"
fi
if rg -q 'Quickshell\.Hyprland|Hyprland\.' \
    "$workspace_widget" "$workspace_panel" "$workspace_panel_content"; then
  fail "workspace views must consume the shared workspace service"
fi
rg -q 'Number\.isInteger\(id\)' "$workspace_actions" \
  || fail "workspace action adapter does not validate ids"
rg -Fq '"hl.dsp.focus({ workspace = \"" + id + "\" })"' \
  "$workspace_actions" \
  || fail "workspace action adapter does not preserve the typed dispatch"
if rg -q 'bash|-c|bar\.run' "$workspace_actions"; then
  fail "workspace action crosses a shell or bar-command boundary"
fi
rg -q 'hancore\.shibumi\.memory' contracts/plugin-suite-v1.json \
  || fail "internal memory widget is not registered"
rg -q 'hancore\.shibumi\.cpu' contracts/plugin-suite-v1.json \
  || fail "internal CPU widget is not registered"
rg -q 'G7: \["hancore\.shibumi\.ai"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G7 is not owned by the Shibumi AI facade"
rg -q '"service": "Service.qml"' hancore.shibumi.ai/manifest.json \
  || fail "AI provider state must have one shipped owner"
rg -q 'function childPanelWidget\(pluginId\)' hancore.shibumi.ai/BarWidget.qml \
  || fail "AI facade does not expose legacy model-usage panel routing"
if rg -q 'CACHE_FILE|stale_last' \
    hancore.shibumi.ai/scripts/opencode-usage; then
  fail "OpenCode provider must not persist a V1 usage cache"
fi
if rg -q 'Process \{|Timer \{|FileView \{' \
    hancore.shibumi.ai/BarWidget.qml \
    hancore.shibumi.ai/AiUsagePanel.qml; then
  fail "AI views must not own provider polling or file watchers"
fi
rg -q 'G1: \["hancore.shibumi.control-center"\]' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "G1 does not resolve the extracted Control Center plugin"
rg -q 'function setGroupSetting\(groupId, key, value\)' \
  hancore.shibumi.state/Service.qml \
  || fail "G1 cannot persist group settings through the state owner"
rg -q 'function setPresentationSetting\(key, value\)' \
  hancore.shibumi.state/Service.qml \
  || fail "G1 cannot persist Shibumi presentation settings"
rg -q 'function setBarPosition\(value, ownerValue, screenName\)' hancore.shibumi.bar/Bar.qml \
  || fail "G1 cannot persist output-local top/bottom position"
rg -q 'function setAllSplits\(value\)' hancore.shibumi.bar/Bar.qml \
  || fail "G1 cannot persist split presets"
detail_panel_count=$(find hancore.shibumi.* -maxdepth 1 -type f \
  -name '*Panel.qml' ! -name ShibumiPanel.qml | wc -l)
[[ $(rg -l '^ShibumiPanel \{' hancore.shibumi.*/*Panel.qml | wc -l) \
  -eq $detail_panel_count ]] \
  || fail "shipped detail panels do not share the Shibumi surface contract"
[[ $(rg -l '^Ui\.KeyboardPanel \{' hancore.shibumi.*/*Panel.qml | wc -l) -eq 0 ]] \
  || fail "a shipped detail panel still layers host panel chrome"
rg -q 'default property alias panelContent: shibumiContent\.children' \
  widgets/ShibumiPanel.qml \
  || fail "Shibumi panel surface does not isolate chrome from panel content"
rg -q 'property int padding: Commons\.Style\.spacing\.popupPadding' \
  widgets/ShibumiPanel.qml \
  || fail "Shibumi panel border changes its V1 content inset"
rg -q '^PanelWindow \{' widgets/ShibumiPanel.qml \
  || fail "Shibumi panel does not own its visible surface"
rg -Fq 'function requestKeyboardFocus(target)' widgets/ShibumiPanel.qml \
  || fail "Shibumi panel cannot reacquire keyboard focus for inline editors"
rg -Fq 'focusPrimed ? WlrKeyboardFocus.OnDemand' widgets/ShibumiPanel.qml \
  || fail "Shibumi panel does not settle its keyboard-focus prime"
rg -q 'id: focusPrimeTimer' widgets/ShibumiPanel.qml \
  || fail "Shibumi panel does not bound its exclusive focus prime"
if rg -q '^Ui\.KeyboardPanel|shibumiSurfaceBleed' widgets/ShibumiPanel.qml; then
  fail "Shibumi panel still paints host and custom panel layers together"
fi
rg -q 'readonly property int renderedSurfaceCount: 1' \
  widgets/ShibumiPanel.qml \
  || fail "Shibumi panel does not guarantee one visible surface"
rg -q 'shibumiTokens\.tileRadius' widgets/ShibumiPanel.qml \
  || fail "Shibumi controls do not follow the selected radius"
for token in controlBorderColor controlHoverBorderColor controlFillColor \
  controlHoverFillColor dividerColor; do
  rg -q "readonly property color ${token}:" widgets/ShibumiPanel.qml \
    || fail "Shibumi panel is missing the shared inner-control token: $token"
done
for pair in \
  'hancore.shibumi.ai/AiUsagePanel.qml:panel.controlBorderColor' \
  'hancore.shibumi.audio/AudioPanel.qml:panel.controlHoverBorderColor' \
  'hancore.shibumi.bluetooth/BluetoothPanel.qml:panel.controlBorderColor' \
  'hancore.shibumi.brightness/BrightnessPanel.qml:panel.controlActiveFillColor' \
  'hancore.shibumi.brightness/BrightnessPanel.qml:panel.controlBorderColor' \
  'hancore.shibumi.network/NetworkPanel.qml:panel.controlBorderColor' \
  'hancore.shibumi.power-profile/PowerProfilePanel.qml:panel.controlBorderColor' \
  'hancore.shibumi.workspaces/WorkspacePanelContent.qml:root.controller.controlFillColor'; do
  file=${pair%%:*}
  token=${pair#*:}
  rg -Fq "$token" "$file" \
    || fail "$file bypasses the shared inner-control appearance"
done
[[ $(rg -c 'FileView \{' hancore.shibumi.state/ThemePalette.qml) -eq 2 ]] \
  || fail "V1 accent swatches require one palette reader and one theme swap watcher"
rg -q 'themeNamePath' hancore.shibumi.state/ThemePalette.qml \
  || fail "V1 accent swatches do not observe completed Quattro theme swaps"
if rg -q 'Process \{|Timer \{' hancore.shibumi.state/ThemePalette.qml; then
  fail "theme palette bridge must remain event-driven"
fi
rg -q 'omarchy\.clock' hancore.shibumi.bar/core/GroupRegistry.js \
  || fail "Shibumi clock does not override the host clock slot"
rg -q 'hancore\.shibumi\.center' contracts/plugin-suite-v1.json \
  || fail "Shibumi center composite is not registered"
rg -q 'GroupSection' hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "Shibumi surface does not render persisted groups"
rg -Uq 'id: leftGroups[[:space:][:print:]]*visibilityStage: horizontalSurface\.narrowStage' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "left groups do not receive the responsive visibility stage"
rg -Uq 'id: rightGroups[[:space:][:print:]]*visibilityStage: horizontalSurface\.narrowStage' \
  hancore.shibumi.bar/styles/shibumi/BarSurface.qml \
  || fail "right groups do not receive the responsive visibility stage"
rg -q 'GroupRegistry\.unassignedEntries' hancore.shibumi.bar/Bar.qml \
  || fail "custom host layout entries are not preserved"
if rg -q 'Process \{|FileView \{' hancore.shibumi.bar/core/GroupSlot.qml \
  hancore.shibumi.bar/styles/shibumi/GroupSection.qml; then
  fail "group renderer must remain event-driven and worker-free"
fi
if rg -q 'Timer \{' hancore.shibumi.bar/core/GroupSlot.qml; then
  fail "group slots must not own timers"
fi
[[ $(rg -c 'Timer \{' hancore.shibumi.bar/styles/shibumi/GroupSection.qml) -eq 2 ]] \
  || fail "group sections must own exactly two lifecycle-bound timers"
rg -U -q 'Timer \{\n[[:space:]]*id: layoutTimer\n[[:space:]]*interval: 0\n[[:space:]]*onTriggered: \{\n[[:space:]]*if \(horizontalRow\) horizontalRow\.forceLayout\(\)' \
  hancore.shibumi.bar/styles/shibumi/GroupSection.qml \
  || fail "group layout work is not owned by the horizontal row lifecycle"
if rg -Fq 'Qt.callLater' hancore.shibumi.bar/styles/shibumi/GroupSection.qml; then
  fail "group layout work can outlive its horizontal row context"
fi
rg -U -q 'Timer \{\n[[:space:]]*id: registrationTimer\n[[:space:]]*interval: 0\n' \
  hancore.shibumi.bar/styles/shibumi/GroupSection.qml \
  || fail "group lifecycle timer must be the zero-delay target registration sync"
for teardown_contract in \
  'const owner = root' \
  'if (!owner) {' \
  'clearTargetRegistration()' \
  'if (registrationTimer) registrationTimer.stop()' \
  'if (horizontalRow) horizontalRow.scheduleLayout()' \
  '? horizontalRow.nextShownIndex(index) : -1' \
  '? root.separatorCenterOffset(horizontalCell.separated) : 0'; do
  rg -Fq "$teardown_contract" hancore.shibumi.bar/styles/shibumi/GroupSection.qml \
    || fail "group teardown guard is missing: $teardown_contract"
done
for unsafe_teardown_access in \
  'const nextAsSlot = root.slotEditing' \
  'onWidthChanged: horizontalRow.scheduleLayout()' \
  'onVisibleChanged: horizontalRow.scheduleLayout()'; do
  if rg -Fq "$unsafe_teardown_access" hancore.shibumi.bar/styles/shibumi/GroupSection.qml; then
    fail "group teardown retains an unsafe owner access: $unsafe_teardown_access"
  fi
done
rg -q 'acquire\("memory"\)' hancore.shibumi.memory/BarWidget.qml \
  || fail "memory widget does not activate shared telemetry"
rg -q 'release\("memory"\)' hancore.shibumi.memory/BarWidget.qml \
  || fail "memory widget does not release shared telemetry"
rg -q 'acquire\("cpu"\)' hancore.shibumi.cpu/BarWidget.qml \
  || fail "CPU widget does not activate shared telemetry"
rg -q 'release\("cpu"\)' hancore.shibumi.cpu/BarWidget.qml \
  || fail "CPU widget does not release shared telemetry"

for facade_name in \
  position vertical barSize barHidden fontFamily foreground barForeground \
  background urgent foregroundAnimationEnabled activePopout \
  centerSectionRevealHeld centerHoverRevealSuppressed; do
  rg -q "^[[:space:]]*(readonly )?property .* ${facade_name}([: ])" hancore.shibumi.bar/Bar.qml \
    || fail "missing stock-widget bar facade property: $facade_name"
done

for facade_function in \
  run showTooltip hideTooltip requestPopout releasePopout \
  registerClickTarget unregisterClickTarget switchPanelFrom openConfigPanel \
  debugBarGeometry debugWidgetPipeline; do
  rg -q "^[[:space:]]*function ${facade_function}\(" hancore.shibumi.bar/Bar.qml \
    || fail "missing stock-widget bar facade function: $facade_function"
done

if find . -path ./.git -prune -o -type l -print -quit | grep -q .; then
  fail "plugin payload contains a symlink"
fi

if "${OMARCHY_PATH}/bin/omarchy-plugin-validate" "$repo_root" >/dev/null 2>&1; then
  fail "repository root unexpectedly passes the single-plugin validator"
fi
while IFS= read -r plugin_id; do
  [[ -d $repo_root/$plugin_id ]] || continue
  "${OMARCHY_PATH}/bin/omarchy-plugin-validate" "$repo_root/$plugin_id"
done < <(jq -r '.plugins[].id' contracts/plugin-suite-v1.json)

"$repo_root/tests/style-contract-regression.sh"
"$repo_root/tests/picker-helper-regression.sh"
"$repo_root/tests/plugin-suite-contract-regression.sh"
"$repo_root/tests/plugin-self-containment-regression.sh"
"$repo_root/tests/host-facade-contract-regression.sh" --strict-ownership
"$repo_root/tests/core-services-regression.sh"
"$repo_root/tests/gpu-probe-regression.sh"
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' \
  /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_root/tests/shibumi-config-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/theme-palette-model-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/reactor-model-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/reactor-renderer-regression.qml"
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' \
  /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_root/tests/picker-model-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/group-registry-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/center-model-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/responsive-layout-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/panel-routing-regression.qml"
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' \
  /usr/lib/qt6/bin/qmltestrunner \
  -input "$repo_root/tests/workspace-model-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/layout-model-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/v1-center-slot-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/layout-controller-regression.qml"
python3 "$repo_root/tests/qml-assertion-exit-regression.py"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/run-geometry-regression.qml"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/host-widget-resolver-regression.qml"

"$repo_root/tests/health-diagnostics-regression.sh"
"$repo_root/tests/plugin-update-selector-regression.sh"
"$repo_root/tests/plugin-update-service-regression.sh"
"$repo_root/tests/audio-network-ipc-contract-regression.sh"
"$repo_root/tests/network-ipc-routing-regression.sh"
"$repo_root/tests/third-party-integration-regression.sh"

quote_smoke_root=$(mktemp -d)
mkdir -p "$quote_smoke_root/services" "$quote_smoke_root/runtime" \
  "$quote_smoke_root/home"
chmod 700 "$quote_smoke_root/runtime"
cp hancore.shibumi.reactor/QuoteDefaults.js \
  hancore.shibumi.reactor/ReactorModel.js \
  hancore.shibumi.reactor/BoundedTextSource.qml \
  hancore.shibumi.reactor/QuoteService.qml "$quote_smoke_root/services/"
mkdir -p "$quote_smoke_root/services/scripts"
cp hancore.shibumi.reactor/scripts/read-reactor-text.py "$quote_smoke_root/services/scripts/"
cp tests/quote-service-smoke.qml "$quote_smoke_root/shell.qml"
set +e
quote_service_output=$(timeout 4 env \
  HOME="$quote_smoke_root/home" \
  QT_QPA_PLATFORM=offscreen \
  XDG_RUNTIME_DIR="$quote_smoke_root/runtime" \
  /usr/bin/quickshell -p "$quote_smoke_root" 2>&1)
quote_service_rc=$?
set -e
rm -rf -- "$quote_smoke_root"
printf '%s\n' "$quote_service_output"
[[ $quote_service_rc -eq 0 ]] \
  || fail "quote service smoke exited $quote_service_rc"
grep -q 'quote service smoke passed' <<<"$quote_service_output" \
  || fail "quote service smoke did not emit its first quote"

OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/state-service-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/theme-palette-runtime-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/control-center-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/telemetry-plugins-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/storage-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/presentation-icon-scaling-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/audio-media-plugins-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/workspaces-plugin-regression.sh"
  "$repo_root/tests/update-center-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/status-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/notification-adapter-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/center-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/network-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/brightness-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/bluetooth-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/power-plugins-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/ai-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/quick-access-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/reactor-plugin-regression.sh"
  "$repo_root/tests/host-registry-prime-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/bar-host-registry-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" python3 "$repo_root/tests/state-restore-control-regression.py"
  OMARCHY_PATH="$OMARCHY_PATH" python3 "$repo_root/tests/layout-transition-regression.py" --controls
  python3 "$repo_root/tests/native-catalog-regression.py" --controls
  python3 "$repo_root/tests/native-catalog-instance-selection-regression.py"
  python3 "$repo_root/tests/catalog-demand-regression.py" --controls
  "$repo_root/tests/window-recovery-regression.sh"
  "$repo_root/tests/drag-ghost-render-regression.sh"

  official_audio_panel=${OMARCHY_PATH}/shell/plugins/panels/audio/Panel.qml
  [[ -s $official_audio_panel ]] || fail "official Quattro audio panel is missing"
  for audio_contract in audioSinks audioSources audioStreams outputVolume \
    outputMuted inputVolume inputMuted setOutputVolume setInputVolume \
    toggleOutputMute toggleInputMute setDefaultSink setDefaultSource; do
    rg -q "${audio_contract}" "$official_audio_panel" \
      || fail "official audio panel contract changed: $audio_contract"
  done
  official_media_service=${OMARCHY_PATH}/shell/plugins/services/media/Service.qml
  [[ -s $official_media_service ]] || fail "official Quattro media service is missing"
  for media_contract in activePlayer sourcePlayers runAction playerKey \
    selectPlayer; do
    rg -q "${media_contract}" "$official_media_service" \
      || fail "official media service contract changed: $media_contract"
  done
  official_monitor_panel=${OMARCHY_PATH}/shell/plugins/panels/monitor/Panel.qml
  [[ -s $official_monitor_panel ]] || fail "official Quattro monitor panel is missing"
  for monitor_contract in brightnessAvailable brightnessPercent refresh \
    setBrightness previewBrightness monitorScale setScale displays \
    enabledDisplayCount toggleDisplay normalizeScale brightnessName; do
    rg -q "${monitor_contract}" "$official_monitor_panel" \
      || fail "official monitor panel contract changed: $monitor_contract"
  done
  official_power_panel=${OMARCHY_PATH}/shell/plugins/panels/power/Panel.qml
  [[ -s $official_power_panel ]] || fail "official Quattro power panel is missing"
  for power_contract in batteryPresent profiles activeProfile setProfile; do
    rg -q "$power_contract" "$official_power_panel" \
      || fail "official power contract changed: $power_contract"
  done
  official_update_widget=${OMARCHY_PATH}/shell/plugins/bar/widgets/SystemUpdate.qml
  official_tray_widget=${OMARCHY_PATH}/shell/plugins/bar/widgets/Tray.qml
  official_notification_service=${OMARCHY_PATH}/shell/plugins/notifications/Service.qml
  for status_source in "$official_update_widget" "$official_tray_widget" \
    "$official_notification_service"; do
    [[ -s $status_source ]] || fail "official Quattro status component is missing: $status_source"
  done
  for status_contract in updateAvailable refresh clear runUpdate; do
    rg -q "$status_contract" "$official_update_widget" \
      || fail "official update widget contract changed: $status_contract"
  done
  rg -Fq 'root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-update")' \
    "$official_update_widget" \
    || fail "official update widget no longer opens the Omarchy updater terminal"
  for status_contract in pinnedItems drawerItems close; do
    rg -q "$status_contract" "$official_tray_widget" \
      || fail "official tray widget contract changed: $status_contract"
  done
  if rg -q 'popupModel' "$official_notification_service"; then
    for status_contract in popupModel doNotDisturb setDoNotDisturb \
      dismissPopup clearPopups focusApp showRecentHistory; do
      rg -q "$status_contract" "$official_notification_service" \
        || fail "official current notification contract changed: $status_contract"
    done
  elif rg -q 'pendingModel' "$official_notification_service"; then
    for status_contract in pendingModel pastModel doNotDisturb setDoNotDisturb \
      markAllSeen dismissPending dismissPast clearPast; do
      rg -q "$status_contract" "$official_notification_service" \
        || fail "official legacy notification contract changed: $status_contract"
    done
  else
    fail "official notification service exposes neither current nor legacy model contract"
  fi

  host_has_module() {
    find "${OMARCHY_PATH}/shell/plugins" -type f \
      \( -name manifest.json -o -name '*.manifest.json' \) -print0 \
      | xargs -0 -r jq -r '.id // empty' \
      | grep -Fxq -- "$1"
  }
  if ! host_has_module omarchy.agents \
      && ! host_has_module omarchy.model-usage; then
    fail "Omarchy host provides neither supported AI usage contract"
  fi
  while IFS= read -r module_id; do
    case $module_id in
      omarchy.agents | omarchy.model-usage) continue ;;
    esac
    host_has_module "$module_id" \
      || fail "group registry references unavailable Quattro widget: $module_id"
  done < <(rg -o '"omarchy\.[a-z0-9-]+"' hancore.shibumi.bar/core/GroupRegistry.js \
    | tr -d '"' | sort -u)

  smoke_root=$(mktemp -d)
  fixture_group_pid=
  fixture_group_pgid=
  fixture_parent_pgid=$(ps -o pgid= -p "$BASHPID" | tr -d ' ')
  [[ $fixture_parent_pgid =~ ^[0-9]+$ ]] \
    || fail "could not identify the contract runner process group"
  fixture_pid_alive() {
    [[ -n $fixture_group_pid ]] && kill -0 -- "$fixture_group_pid" 2>/dev/null
  }
  fixture_group_alive() {
    [[ -n $fixture_group_pid \
      && $fixture_group_pgid == "$fixture_group_pid" \
      && $fixture_group_pgid != "$fixture_parent_pgid" ]] \
      && kill -0 -- "-$fixture_group_pgid" 2>/dev/null
  }
  signal_fixture_group() {
    local signal
    signal=$1
    [[ -n $fixture_group_pid \
      && $fixture_group_pgid == "$fixture_group_pid" \
      && $fixture_group_pgid != "$fixture_parent_pgid" ]] \
      || return 1
    kill -s "$signal" -- "-$fixture_group_pgid" 2>/dev/null
  }
  stop_fixture_group() {
    local group_term_sent
    group_term_sent=false
    [[ -n $fixture_group_pid && $fixture_group_pgid == "$fixture_group_pid" ]] || return 0
    if ! fixture_group_alive && fixture_pid_alive; then
      kill -TERM -- "$fixture_group_pid" 2>/dev/null || true
    fi
    if fixture_group_alive; then
      signal_fixture_group TERM || true
      group_term_sent=true
    fi
    for _ in {1..20}; do
      if fixture_group_alive; then
        if [[ $group_term_sent == false ]]; then
          signal_fixture_group TERM || true
          group_term_sent=true
        fi
      elif ! fixture_pid_alive; then
        break
      fi
      sleep 0.05
    done
    fixture_pid_alive && kill -KILL -- "$fixture_group_pid" 2>/dev/null || true
    fixture_group_alive && signal_fixture_group KILL || true
    for _ in {1..20}; do fixture_group_alive || break; sleep 0.05; done
    wait "$fixture_group_pid" 2>/dev/null || true
    ! fixture_group_alive
  }
  cleanup_smoke() {
    if ! stop_fixture_group; then
      printf 'contract regression failed: fixture group survived signal cleanup\n' >&2
      return 1
    fi
    rm -rf -- "$smoke_root"
  }
  trap cleanup_smoke EXIT
  trap 'cleanup_smoke || exit 125; exit 130' HUP INT TERM
  run_isolated_fixture() {
    local ticks output_file pgid rc i
    ticks=$1
    output_file=$2
    pgid=
    rc=0
    shift 2
    : >"$output_file"
    setsid "$@" >"$output_file" 2>&1 &
    fixture_group_pid=$! fixture_group_pgid=$!
    for _ in {1..50}; do
      pgid=$(ps -o pgid= -p "$fixture_group_pid" 2>/dev/null | tr -d ' ') || true
      [[ -n $pgid || ! -e /proc/$fixture_group_pid ]] && break
      sleep 0.01
    done
    if [[ -z $pgid && ! -e /proc/$fixture_group_pid ]]; then
      set +e; wait "$fixture_group_pid"; rc=$?; set -e
      stop_fixture_group || fail "fixture group survived early leader exit"
      fixture_group_pid=
      fixture_group_pgid=
      return "$rc"
    fi
    if [[ $pgid != "$fixture_group_pgid" ]]; then
      stop_fixture_group || fail "fixture group survived invalid ownership cleanup"
      fixture_group_pid=
      fixture_group_pgid=
      fail "fixture did not own its process group"
    fi
    for ((i=0; i<ticks; i++)); do
      fixture_group_alive || break
      sleep 0.1
    done
    if fixture_group_alive; then
      stop_fixture_group || fail "fixture process group survived TERM/KILL cleanup"
      rc=124
    else
      set +e; wait "$fixture_group_pid"; rc=$?; set -e
    fi
    fixture_group_pid=
    fixture_group_pgid=
    return "$rc"
  }
  mkdir -p "$smoke_root/adapters" "$smoke_root/core" "$smoke_root/services" \
    "$smoke_root/styles/shibumi" "$smoke_root/widgets" \
    "$smoke_root"/{home,config,cache,data,state,runtime,tmp,bin}
  chmod 700 "$smoke_root"/{home,config,cache,data,state,runtime,tmp}
  printf '#!/bin/sh\nexit 97\n' > "$smoke_root/bin/hyprctl"
  printf '#!/bin/sh\nexit 97\n' > "$smoke_root/bin/fc-match"
  chmod 700 "$smoke_root/bin"/{hyprctl,fc-match}
  cp -a "${OMARCHY_PATH}/shell/Commons" "$smoke_root/"
  cp -a "${OMARCHY_PATH}/shell/Ui" "$smoke_root/"
  cp widgets/ShibumiPanel.qml \
    hancore.shibumi.state/lib/presentation/PillSurface.qml \
    "$smoke_root/widgets/"
  cp hancore.shibumi.bar/core/BarSection.qml hancore.shibumi.bar/core/GroupRegistry.js hancore.shibumi.bar/core/GroupSlot.qml \
    hancore.shibumi.bar/core/LayoutController.qml hancore.shibumi.bar/core/LayoutModel.js hancore.shibumi.bar/core/LayoutTransition.qml hancore.shibumi.bar/core/V2LayoutModel.js \
    hancore.shibumi.bar/core/PanelRouting.js \
    hancore.shibumi.bar/core/ResponsiveLayout.js hancore.shibumi.bar/core/RunGeometry.js \
    hancore.shibumi.bar/core/WidgetSlot.qml "$smoke_root/core/"
  cp hancore.shibumi.bar/core/DragSession.qml "$smoke_root/core/"
  cp hancore.shibumi.bar/styles/shibumi/BarSurface.qml hancore.shibumi.bar/styles/shibumi/DragGhost.qml \
    hancore.shibumi.bar/styles/shibumi/GroupSection.qml hancore.shibumi.bar/styles/shibumi/RunChrome.qml \
    hancore.shibumi.bar/styles/shibumi/VisualTokens.qml hancore.shibumi.bar/styles/shibumi/GapEffectsLayer.qml \
    hancore.shibumi.bar/styles/shibumi/ReactorEventLayer.qml \
    "$smoke_root/styles/shibumi/"
  python3 - "$repo_root" "$smoke_root/shell.qml" <<'PY'
import sys
from pathlib import Path
repo, target = Path(sys.argv[1]), Path(sys.argv[2])
bar = (repo / "hancore.shibumi.bar/Bar.qml").read_text()
fixture = (repo / "tests/group-renderer-regression.qml").read_text()
declaration_start = "  property var loadedOwners: []"
declaration_end = "  property var clickTargets: []"
function_start = "  function widgetSlotLoadAdmitted("
function_end = "  function registerClickTarget("
declaration_markers = [
    "      // INJECT_BAR_LOADED_OWNER_DECLARATIONS",
    "        // INJECT_TEARDOWN_BAR_LOADED_OWNER_DECLARATIONS",
]
function_markers = [
    "      // INJECT_BAR_LOADED_OWNER_FUNCTIONS",
    "        // INJECT_TEARDOWN_BAR_LOADED_OWNER_FUNCTIONS",
]
if any(fixture.count(marker) != 1
        for marker in declaration_markers + function_markers):
    raise SystemExit("loaded-owner fixture injection marker drifted")
has_ownership = declaration_start in bar or function_start in bar
if has_ownership:
    if any(bar.count(anchor) != 1 for anchor in (declaration_start,
            declaration_end, function_start, function_end)):
        raise SystemExit("loaded-owner projection extraction anchor drifted")
    declarations = bar[bar.index(declaration_start):bar.index(declaration_end)].rstrip()
    functions = bar[bar.index(function_start):bar.index(function_end)].rstrip()
else:
    declarations = "  property var loadedOwners: []"
    functions = ""
for marker in declaration_markers:
    fixture = fixture.replace(marker, declarations)
for marker in function_markers:
    fixture = fixture.replace(marker, functions)
target.write_text(fixture)
PY

  early_child_file="$smoke_root/early-child.pid"
  set +e
  (
    trap - EXIT HUP INT TERM
    ps() { sleep 0.1; command ps "$@"; }
    run_isolated_fixture 10 "$smoke_root/early-leader.log" \
      /bin/sh -c '/bin/sh -c '\''sleep 30'\'' & echo $! >"$1"; exit 23' \
      fixture "$early_child_file"
  )
  early_leader_rc=$?
  set -e
  [[ $early_leader_rc -eq 23 ]] \
    || fail "early fixture leader exit did not preserve status 23"
  early_child_pid=$(<"$early_child_file")
  [[ $early_child_pid =~ ^[0-9]+$ ]] \
    || fail "early fixture leader did not publish its child PID"
  for _ in {1..20}; do
    kill -0 "$early_child_pid" 2>/dev/null || break
    sleep 0.05
  done
  kill -0 "$early_child_pid" 2>/dev/null \
    && fail "early fixture leader left a living process-group child"

  startup_leader_file="$smoke_root/startup-leader.pid"
  startup_child_file="$smoke_root/startup-child.pid"
  set +e
  (
    trap - EXIT HUP INT
    trap 'stop_fixture_group || exit 125; exit 130' TERM
    startup_signal_target=$BASHPID
    ps() { sleep 0.2; command ps "$@"; }
    run_isolated_fixture 10 "$smoke_root/startup-signal.log" \
      /bin/sh -c 'trap "" TERM; echo $$ >"$1"; /bin/sh -c '\''trap "" TERM; sleep 30'\'' & echo $! >"$2"; kill -TERM "$3"; wait' \
      fixture "$startup_leader_file" "$startup_child_file" "$startup_signal_target"
  )
  startup_signal_rc=$?
  set -e
  [[ $startup_signal_rc -eq 130 ]] \
    || fail "startup signal cleanup exited $startup_signal_rc instead of 130"
  startup_leader_pid=$(<"$startup_leader_file")
  startup_child_pid=$(<"$startup_child_file")
  [[ $startup_leader_pid =~ ^[0-9]+$ && $startup_child_pid =~ ^[0-9]+$ ]] \
    || fail "startup signal fixture did not publish exact owned PIDs"
  [[ $startup_leader_pid != "$fixture_parent_pgid" ]] \
    || fail "startup fixture unexpectedly matched the contract runner process group"
  for _ in {1..20}; do
    if ! kill -0 -- "-$startup_leader_pid" 2>/dev/null \
        && ! kill -0 -- "$startup_child_pid" 2>/dev/null; then
      break
    fi
    sleep 0.05
  done
  kill -0 -- "-$startup_leader_pid" 2>/dev/null \
    && fail "startup signal left the exact owned fixture group alive"
  kill -0 -- "$startup_child_pid" 2>/dev/null \
    && fail "startup signal left the exact owned fixture child alive"

  ipc_child_file="$smoke_root/ipc-child.pid"
  set +e
  run_isolated_fixture 10 "$smoke_root/hanging-ipc.log" \
    /bin/sh -c 'trap "" TERM; /bin/sh -c '\''trap "" TERM; sleep 30'\'' & echo $! >"$1"; wait' \
    fixture "$ipc_child_file"
  hanging_ipc_rc=$?
  set -e
  [[ $hanging_ipc_rc -eq 124 ]] \
    || fail "controlled hanging IPC child did not exercise timeout cleanup"
  ipc_child_pid=$(<"$ipc_child_file")
  [[ $ipc_child_pid =~ ^[0-9]+$ ]] || fail "hanging IPC child did not publish its PID"
  kill -0 "$ipc_child_pid" 2>/dev/null \
    && fail "controlled hanging IPC child survived process-group cleanup"

  set +e
  run_isolated_fixture 50 "$smoke_root/group-renderer.log" env \
    -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QS_CONFIG_PATH \
    HOME="$smoke_root/home" XDG_CONFIG_HOME="$smoke_root/config" \
    XDG_CACHE_HOME="$smoke_root/cache" XDG_DATA_HOME="$smoke_root/data" \
    XDG_STATE_HOME="$smoke_root/state" XDG_RUNTIME_DIR="$smoke_root/runtime" \
    TMPDIR="$smoke_root/tmp" PATH="$smoke_root/bin:/usr/bin" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$smoke_root/runtime/no-session-bus" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$smoke_root/runtime/no-system-bus" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
    QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software QT_OPENGL=software \
    /usr/bin/quickshell -p "$smoke_root"
  group_renderer_rc=$?
  set -e
  group_renderer_output=$(<"$smoke_root/group-renderer.log")
  printf '%s\n' "$group_renderer_output"
  group_renderer_failures=()
  [[ $group_renderer_rc -eq 0 ]] \
    || group_renderer_failures+=("exited $group_renderer_rc")
  grep -q 'group renderer regression passed' <<<"$group_renderer_output" \
    || group_renderer_failures+=("did not reach its marker")
  grep -q 'P10_106_PRIVATE_IPC' <<<"$group_renderer_output" \
    || group_renderer_failures+=("did not verify private IPC routing")
  grep -q 'P10_106_ACTUAL_BAR_TEARDOWN' <<<"$group_renderer_output" \
    || group_renderer_failures+=("did not destroy the actual Bar fixture owner")
  grep -q 'QQmlInvalidContext' <<<"$group_renderer_output" \
    && group_renderer_failures+=("used an invalid QML context during Bar teardown")
  grep -q 'owner sentinel changed .* item geometry' <<<"$group_renderer_output" \
    && group_renderer_failures+=("owner sentinel changed foreign geometry")
  grep -Fq 'another handler is registered for target fixture.shibumi.106.native-owner' \
    <<<"$group_renderer_output" \
    && group_renderer_failures+=("overlapped native IPC handlers")
  if ! python3 -c 'import re,sys
lines=sys.stdin.read().splitlines(); events=[]
for line in lines:
 m=re.search(r"P10_106_(IPC_QML_DESTRUCTION|SENTINEL_DESTRUCTION) ([0-9]+)",line)
 if m and int(m.group(2)) <= 3: events.append((m.group(1),int(m.group(2))))
expected=[x for n in range(1,4) for x in [("IPC_QML_DESTRUCTION",n),("SENTINEL_DESTRUCTION",n)]]
sys.exit(events != expected)' <<<"$group_renderer_output"; then
    group_renderer_failures+=("did not preserve handler-to-sentinel destruction ordering three times")
  fi
  ((${#group_renderer_failures[@]} == 0)) \
    || fail "group renderer smoke: ${group_renderer_failures[*]}"

  python3 - "$repo_root" "$smoke_root/shell.qml" <<'PY'
import sys
from pathlib import Path
repo, target = Path(sys.argv[1]), Path(sys.argv[2])
bar = (repo / "hancore.shibumi.bar/Bar.qml").read_text()
fixture = (repo / "tests/group-interaction-regression.qml").read_text()
def fragment(start, end):
    if bar.count(start) != 1 or bar.count(end) != 1:
        raise SystemExit("Bar projection extraction anchor drifted")
    return bar[bar.index(start):bar.index(end)].rstrip()
replacements = {
    "      // INJECT_BAR_LOADED_OWNER_DECLARATIONS": fragment(
        "  property var loadedOwners: []",
        "  property var clickTargets: []"),
    "      // INJECT_BAR_PROJECTION": fragment(
        "  function deduplicatedUnassignedEntries(",
        "  function pluginSpecsForLayout("),
    "      // INJECT_BAR_SLOT_REGISTRY": fragment(
        "  function registerModuleSlot(", "  function registerClickTarget("),
}
for marker, source in replacements.items():
    if fixture.count(marker) != 1:
        raise SystemExit("group interaction injection marker drifted")
    fixture = fixture.replace(marker, source)
target.write_text(fixture)
PY

  set +e
  run_isolated_fixture 80 "$smoke_root/group-interaction.log" env \
    -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QS_CONFIG_PATH \
    HOME="$smoke_root/home" XDG_CONFIG_HOME="$smoke_root/config" \
    XDG_CACHE_HOME="$smoke_root/cache" XDG_DATA_HOME="$smoke_root/data" \
    XDG_STATE_HOME="$smoke_root/state" XDG_RUNTIME_DIR="$smoke_root/runtime" \
    TMPDIR="$smoke_root/tmp" PATH="$smoke_root/bin:/usr/bin" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$smoke_root/runtime/no-session-bus" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$smoke_root/runtime/no-system-bus" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
    QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software QT_OPENGL=software \
    /usr/bin/quickshell -p "$smoke_root"
  group_interaction_rc=$?
  set -e
  group_interaction_output=$(<"$smoke_root/group-interaction.log")
  printf '%s\n' "$group_interaction_output"
  [[ $group_interaction_rc -eq 0 ]] \
    || fail "group interaction smoke exited $group_interaction_rc"
  for transfer_marker in 'group interaction regression passed' \
      'group transfer A passed' 'group transfer B passed' \
      'failed State write retained grouped widget' \
      'keepConfigured deck appeared once after finish'; do
    [[ $(grep -Fc "$transfer_marker" <<<"$group_interaction_output") -eq 1 ]] \
      || fail "group interaction smoke did not reach exactly one: $transfer_marker"
  done
  if grep -Fq 'another handler is registered for target fixture.p10.088.target' \
      <<<"$group_interaction_output"; then
    fail "group interaction smoke overlapped group/deck IPC owners"
  fi
  [[ $(grep -Fc 'removing.indexOf(id) >= 0' "$smoke_root/shell.qml") -eq 2 ]] \
    || fail "pending removeIds projection is missing from a V1/V2 branch"
  grep -Fq 'const removeIds = installed === true' hancore.shibumi.bar/Bar.qml \
    && grep -Fq '? conflictingLayoutProviderIds(id) : [id]' \
      hancore.shibumi.bar/Bar.qml \
    || fail "activation no longer projects displaced provider removeIds"

  cp tests/v1-slot-interaction-regression.qml "$smoke_root/shell.qml"

  set +e
  v1_slot_interaction_output=$(timeout 7 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  v1_slot_interaction_rc=$?
  set -e
  printf '%s\n' "$v1_slot_interaction_output"
  [[ $v1_slot_interaction_rc -eq 0 ]] \
    || fail "V1 slot interaction smoke exited $v1_slot_interaction_rc"
  grep -q 'V1 slot interaction regression passed' \
    <<<"$v1_slot_interaction_output" \
    || fail "V1 slot interaction smoke did not reach its marker"

  # Capability smokes above exercise the shipped plugin payloads directly.

  # Shared presentation is exercised through shipped capability smokes.

  shibumi_stage_suite_runtime "$repo_root" "$smoke_root"
  cp hancore.shibumi.workspaces/WorkspacePanelContent.qml \
    "$smoke_root/widgets/"
  cp tests/workspace-panel-smoke.qml "$smoke_root/shell.qml"
  set +e
  workspace_panel_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  workspace_panel_rc=$?
  set -e
  printf '%s\n' "$workspace_panel_output"
  [[ $workspace_panel_rc -eq 0 ]] || fail "workspace panel smoke exited $workspace_panel_rc"
  grep -q 'workspace panel smoke passed' <<<"$workspace_panel_output" \
    || fail "workspace panel smoke did not reach its lifecycle marker"
  if grep -q 'Unable to assign \[undefined\] to QColor' \
      <<<"$workspace_panel_output"; then
    fail "workspace panel smoke has an undefined control appearance token"
  fi

printf 'Shibumi complete contract regression passed (Omarchy baseline %s; source %s)\n' \
  "$SHIBUMI_OMARCHY_BASELINE_ID" "$SHIBUMI_OMARCHY_SOURCE_REVISION"
