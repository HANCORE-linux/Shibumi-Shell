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
python3 "$repo_root/tests/test_package_release.py"
python3 "$repo_root/tests/test_shibumi_manager.py"
python3 "$repo_root/tests/test_shibumi_suite.py"
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

[[ ! -e manifest.json ]] \
  || fail "repository root must not masquerade as one native Omarchy plugin"

jq -e '
  .schemaVersion == 1 and
  .id == "hancore.shibumi.bar" and
  .kinds == ["bar"] and
  .entryPoints.bar == "Bar.qml"
' hancore.shibumi.bar/manifest.json >/dev/null \
  || fail "invalid Shibumi bar manifest"

[[ -s assets/logo-tint.frag.qsb ]] \
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

rg -q '^Item \{' Bar.qml || fail "Bar.qml must use Item as its root"
if rg -q '^ShellRoot \{' Bar.qml; then
  fail "a native full-bar plugin must not create a ShellRoot"
fi

for property_name in omarchyPath shell manifest pluginRegistry barWidgetRegistry barConfig; do
  rg -q "^[[:space:]]*property (string|var) ${property_name}:" Bar.qml \
    || fail "missing optional host property: $property_name"
  if rg -q "^[[:space:]]*required property .* ${property_name}" Bar.qml; then
    fail "asynchronously injected host property is required: $property_name"
  fi
done

rg -q 'typeof Util\.execDetached === "function"' Bar.qml \
  || fail "bar command launcher does not follow Quattro's current host contract"
rg -Fq 'Quickshell.execDetached(["bash", "-lc", text])' Bar.qml \
  || fail "bar command launcher has no compatibility fallback"
if rg -q 'omarchy-hyprland-launch|commandLauncher' Bar.qml; then
  fail "bar command launcher still depends on the removed legacy launcher"
fi

rg -q 'model: root\.outputWindowsEnabled \? Quickshell\.screens : \[\]' Bar.qml \
  || fail "bar variants must preserve native Quickshell screen objects"
if rg -q 'model: .*barScreens' Bar.qml; then
  fail "bar variants must not use a JavaScript copy of Quickshell.screens"
fi
if ! {
  rg -q 'screen\.name !== ""' core/BarPanel.qml \
    && rg -q 'screen\.width > 0' core/BarPanel.qml \
    && rg -q 'screen\.height > 0' core/BarPanel.qml
}; then
  fail "bar must reject invalid Wayland placeholder screens"
fi
rg -q '^PanelWindow \{' core/BarPanel.qml \
  || fail "output surface must be a PanelWindow"
rg -Fq 'implicitHeight: !bar.vertical && validScreen ? screen.height : 0' \
  core/BarPanel.qml \
  || fail "horizontal host must stay screen-sized to avoid edit resize flashes"
rg -Fq 'WlrLayershell.keyboardFocus: dragSession.editing' \
  core/BarPanel.qml \
  || fail "stable bar surface must own temporary edit focus"
rg -q '^  mask: Region \{' core/BarPanel.qml \
  || fail "screen-sized bar surface must constrain its locked input region"
rg -Fq 'onClicked: dragSession.setEditing(false)' core/BarPanel.qml \
  || fail "stable edit surface does not dismiss from outside clicks"
rg -q '^PanelWindow \{' core/DragGhostPanel.qml \
  || fail "drag ghost must be isolated from the edge-local bar window"
rg -q 'mask: Region \{\}' core/DragGhostPanel.qml \
  || fail "drag ghost overlay must remain input-transparent"
rg -Fq 'y: !barWindow.bar.vertical && barWindow.bar.position === "bottom"' \
  core/BarPanel.qml \
  || fail "bottom bar surface must use stable explicit placement"
if rg -q 'anchors\.(top|bottom):.*barWindow\.bar\.position' core/BarPanel.qml; then
  fail "bar surface must not switch conditional vertical anchors at runtime"
fi
rg -q '^Scope \{' core/WindowRecovery.qml \
  || fail "per-output window recovery scope is missing"
rg -q 'function onResourcesLost\(\)' core/WindowRecovery.qml \
  || fail "window recovery does not handle resourcesLost"
rg -q 'function onClosed\(\)' core/WindowRecovery.qml \
  || fail "window recovery does not handle closed"
if rg -q 'targetWindow\.visible[[:space:]]*=' core/WindowRecovery.qml; then
  fail "window recovery imperatively destroys the bar visibility binding"
fi
rg -q 'visible: bar\.hostReady && bar\.styleReady && validScreen && !bar\.barHidden' core/BarPanel.qml \
  || fail "output must wait for host and style readiness and honor bar-off"
rg -q 'active: barWindow\.bar\.hostReady && barWindow\.bar\.styleReady' core/BarPanel.qml \
  || fail "bar surface may instantiate before host injection completes"
rg -Uq 'active: barWindow\.bar\.hostReady && barWindow\.bar\.styleReady\n[[:space:]]*&& barWindow\.validScreen && barWindow\.bar\.visualTokens !== null' \
  core/BarPanel.qml \
  || fail "bar surface may instantiate for an invalid Wayland placeholder"
rg -q 'Services\.HostWidgetResolver' Bar.qml \
  || fail "replacement bar does not own stable host widget components"
rg -Fq 'function inlineSettingsDelta(current, next)' Bar.qml \
  || fail "bar host cannot distinguish inline state from structural layout changes"
rg -Fq 'function applyInlineSettingsDelta(changes)' Bar.qml \
  || fail "bar host recreates widgets for inline state persistence"
rg -Fq 'function applyInlineSettings(nextEntry)' core/WidgetSlot.qml \
  || fail "widget slots cannot receive inline state without replacing their entry binding"
rg -Fq 'function hostEntryFor(moduleValue, layout)' core/GroupRegistry.js \
  || fail "grouped widgets do not expose their host settings layer"
rg -Fq 'function settingsOverridesFor(groupValue, moduleValue, groupValueSettings,' \
  core/GroupRegistry.js \
  || fail "grouped widgets do not expose explicit local settings overrides"
if rg -Fq 'slot.entry = change.entry' Bar.qml; then
  fail "inline state persistence overwrites the delegate-owned slot entry binding"
fi
if rg -q 'Services\.(SystemTelemetry|GpuTelemetry|PowerService|StatusService|WeatherService|ThemePalette|AiUsageService|PickerService|ReactorService|QuoteService|WorkspaceService|ClockService|NetworkService|MonitorService|BluetoothService)|Adapters\.(SystemActions|WorkspaceActions)|Widgets\.WidgetRegistry' Bar.qml; then
  fail "registry-only bar host still instantiates a feature owner"
fi
rg -q 'Qt\.createComponent\(url, Component\.PreferSynchronous\)' services/HostWidgetResolver.qml \
  || fail "host widget resolver does not load official manifest entry points"
[[ $(rg -l 'bar\.registeredWidgetComponent' widgets/{Audio,Status,Center}Widget.qml | wc -l) -eq 3 ]] \
  || fail "host-backed composites bypass the stable widget resolver"
rg -q 'registeredWidgetComponent\("omarchy\.network"\)' services/NetworkService.qml \
  || fail "root network owner bypasses the stable widget resolver"
rg -q 'registeredWidgetComponent\("omarchy\.monitor"\)' services/MonitorService.qml \
  || fail "root monitor owner bypasses the stable widget resolver"
if rg -q 'registeredWidgetComponent\("omarchy\.bluetooth"\)' services/BluetoothService.qml; then
  fail "root Bluetooth owner must not instantiate the complete host widget"
fi
if rg -U -q 'visible: root\.anchorIndex < 0\n[[:space:]]*bar: root\.bar\n[[:space:]]*region: "center"\n[[:space:]]*entries: root\.entries' core/CenterSection.qml; then
  fail "inactive center fallback must not instantiate duplicate widgets"
fi
[[ $(rg -c 'entries: root\.anchorIndex < 0 \? root\.entries : \[\]' core/CenterSection.qml) -eq 2 ]] \
  || fail "both center orientations must suppress the inactive fallback model"
rg -q 'bar\.registeredWidgetComponent\(moduleName\)' core/WidgetSlot.qml \
  || fail "widget slots do not resolve exclusively through the plugin registry"
if rg -q 'internalWidgetRegistry|internalComponent|registryComponent' \
    Bar.qml core/WidgetSlot.qml; then
  fail "registry-only widget resolution retains a local component owner"
fi
rg -q 'sourceComponent: root\.resolvedComponent' core/WidgetSlot.qml \
  || fail "widget slots must load the resolved component"
rg -q 'active: root\.moduleEnabled && root\.resolvedComponent !== null' \
  core/WidgetSlot.qml \
  || fail "disabled widgets remain instantiated"
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
  rg -Fq "$compatibility_contract" core/WidgetSlot.qml \
    || fail "third-party host compatibility lost $compatibility_contract"
done
rg -q 'readonly property bool hostedModule: !suiteNativeModule' \
  core/WidgetSlot.qml \
  || fail "hosted panel adapter is restricted to one external provider"
rg -Fq 'if (root.bar.pendingTooltipTarget || root.bar.tooltipTarget) return' \
  core/WidgetSlot.qml \
  || fail "manifest tooltip fallback can override a plugin tooltip"
rg -Fq 'Binding.RestoreBindingOrValue' core/WidgetSlot.qml \
  || fail "third-party panel chrome cannot restore native bindings"
[[ $(rg -c 'value: root\.hostedCardOrigin\(root\.compatibilityPanel\)' \
  core/WidgetSlot.qml) -eq 2 ]] \
  || fail "hosted panels do not translate both card axes to the visible bar"
rg -Fq 'y = barThickness + gap' core/WidgetSlot.qml \
  || fail "top hosted panels still derive their offset from the host window"
rg -Fq 'property: "contentHeight"' core/WidgetSlot.qml \
  || fail "screen-sized hosted panels do not repair KeyboardPanel height"
rg -Fq 'screenHeight - barThickness - gap - margin' core/WidgetSlot.qml \
  || fail "hosted panel height is not capped at the visible bar edge"
rg -Fq 'Math.min(compatibilityNativeContentHeight, currentNativeHeight)' \
  core/WidgetSlot.qml \
  || fail "opening a hosted panel can recapture its repaired height as native"
rg -Fq 'item.mapToItem(holder, 0, 0)' core/WidgetSlot.qml \
  || fail "hosted panel height does not follow rendered child geometry"
rg -q '^PanelWindow \{' core/HostedPanelConnector.qml \
  || fail "hosted V2 caret overlay is missing"
rg -q 'mask: Region \{\}' core/HostedPanelConnector.qml \
  || fail "hosted V2 caret overlay must remain input-transparent"
rg -q 'width: 26' core/HostedPanelConnector.qml \
  || fail "hosted V2 caret does not retain the native panel-edge span"
rg -q 'joinStyle: ShapePath\.MiterJoin' core/HostedPanelConnector.qml \
  || fail "hosted V2 caret does not retain the native panel join"
awk '
  /Rectangle \{/ { bridge = 1 }
  bridge && /z: 1/ { found = 1; exit }
  END { exit(found ? 0 : 1) }
' core/HostedPanelConnector.qml \
  || fail "hosted V2 caret bridge must remain below the replacement edge"
awk '
  /Shape \{/ { shape = 1 }
  shape && /z: 2/ { found = 1; exit }
  END { exit(found ? 0 : 1) }
' core/HostedPanelConnector.qml \
  || fail "hosted V2 caret must remain above the foreign-border bridge"
connector_path_count="$(
  awk '
    /ShapePath \{/ { count += 1 }
    END { print count + 0 }
  ' core/HostedPanelConnector.qml
)"
[[ "$connector_path_count" -eq 1 ]] \
  || fail "hosted V2 caret must be one continuous panel-edge path"
rg -Fq 'HostedPanelConnector {' core/BarPanel.qml \
  || fail "bar output does not own its screen-local hosted connector"
rg -Fq 'connectedPanelHostCaret' Bar.qml \
  || fail "bar facade does not distinguish host-drawn panel carets"
rg -q 'active: root\.groupEnabled' core/GroupSlot.qml \
  || fail "disabled multi-module groups remain instantiated"
rg -Fq 'readonly property bool appearanceFill: v2Shell &&' \
  core/GroupSlot.qml \
  || fail "V2 group appearance settings leak into the V1 pill surface"
rg -Fq 'customDecorated: shellStyle !== "shibumi"' \
  widgets/PillSurface.qml \
  || fail "V2 widget appearance settings suppress the V1 native pill"
rg -Fq 'presentation.v2Border === undefined' \
  styles/shibumi/VisualTokens.qml \
  || fail "V1 and V2 still share one mutable bar-border state"
if rg -Fq 'pillBorderWidth > 0 ? 0.5 : 0' \
    styles/shibumi/RunChrome.qml; then
  fail "V1 run borders are shifted off their original integer geometry"
fi
if rg -q 'visible: activeItem' core/WidgetSlot.qml; then
  fail "widget slot visibility must not depend on child effective visibility"
fi

for injected_name in bar moduleName hostGroupId settings; do
  rg -q "if \(\"${injected_name}\" in target\)" core/WidgetSlot.qml \
    || fail "widget slot does not inject $injected_name"
done
rg -q 'if \("availableWidth" in target\)' core/WidgetSlot.qml \
  || fail "widget slots do not inject the monitor-local width budget"
rg -q 'onAvailableWidthChanged: injectProperties\(\)' core/WidgetSlot.qml \
  || fail "center width changes are not forwarded reactively"
rg -q 'availableWidth: horizontalSurface.centerAvailableWidth' styles/shibumi/BarSurface.qml \
  || fail "center width budget is not monitor-local"
rg -Fq 'ResponsiveLayout.centerAvailableWidth(compactShell, width,' \
  styles/shibumi/BarSurface.qml \
  || fail "compact V2 shells measure the center against their own fitted width"
rg -Fq 'readonly property real responsiveCapacity: compactShell' \
  styles/shibumi/BarSurface.qml \
  || fail "compact V2 shells do not retain the monitor responsive capacity"
rg -Fq 'responsiveCapacity, narrowCandidateWidths' \
  styles/shibumi/BarSurface.qml \
  || fail "responsive staging still feeds back the content-sized V2 shell width"
rg -Fq 'void(root.stateRevision)' styles/shibumi/GroupSection.qml \
  || fail "V2 separator geometry does not react to state-service commits"
rg -Fq 'void(root.stateConfig)' styles/shibumi/GroupSection.qml \
  || fail "V2 separator geometry does not bind to the replaced state config"
rg -Fq 'if (persistentSeparators) return appearanceSeparator' \
  styles/shibumi/GroupSection.qml \
  || fail "V2 separators still inherit V1 positional split state"
for shell_contract in shellStyle shellWidth shellX shellContentInset; do
  rg -Fq "$shell_contract" styles/shibumi/BarSurface.qml \
    || fail "Shibumi surface lost V2 shell geometry: $shell_contract"
done
[[ $(rg -c 'horizontalSurface\.shellContentInset' styles/shibumi/BarSurface.qml) -eq 2 ]] \
  || fail "Shibumi side rows do not follow the active shell inset"
rg -q 'color: root\.bar\.background' styles/shibumi/TooltipSurface.qml \
  || fail "Shibumi tooltip does not follow the bar surface color"
rg -q 'radius: root\.bar\.visualTokens\.tooltipRadius' styles/shibumi/TooltipSurface.qml \
  || fail "Shibumi tooltip does not use the V1 radius token"
rg -q 'active: !root\.bar\.barHidden' styles/shibumi/BarSurface.qml \
  || fail "Reactor renderer remains active while the bar is hidden"
rg -q 'root\.reactorMode >= 1 && root\.reactorMode <= 8' \
  styles/shibumi/BarSurface.qml \
  || fail "Mode 0 does not prevent Reactor renderer construction"
rg -q 'root\.reactorMode >= 7 \? reactorEventComponent' \
  styles/shibumi/BarSurface.qml \
  || fail "Modes 7-8 do not select the shared swarm renderer"
if rg -q '\b(Process|FileView)\b' styles/shibumi/GapEffectsLayer.qml; then
  fail "style-owned Reactor modes 1-6 must not own backend workers"
fi
[[ $(rg -c 'Timer \{' styles/shibumi/GapEffectsLayer.qml) -eq 1 ]] \
  || fail "Reactor visual layer must own exactly one frame timer"
if rg -q '\b(Process|FileView)\b' styles/shibumi/ReactorEventLayer.qml; then
  fail "style-owned Reactor mode 7 must not own backend workers"
fi
[[ $(rg -c 'Timer \{' styles/shibumi/ReactorEventLayer.qml) -eq 1 ]] \
  || fail "Mode 7 renderer must own exactly one adaptive frame timer"
rg -q 'target: "shibumi-reactor"' hancore.shibumi.reactor/Service.qml \
  || fail "Reactor control IPC target is missing"
rg -Fq 'active: root.ready && (root.mode === 7 || root.mode === 8)' \
  hancore.shibumi.reactor/Service.qml \
  || fail "Reactor backend is not lifecycle-lazy"
rg -q 'root\.mode === 7 \? eventBackendComponent' \
  hancore.shibumi.reactor/Service.qml \
  || fail "Mode 7 Reactor service is not selected lazily"
[[ $(rg -c 'ReactorService \{' hancore.shibumi.reactor/Service.qml) -eq 1 ]] \
  || fail "Mode 7 Reactor service must be process-wide"
[[ $(rg -c 'QuoteService \{' hancore.shibumi.reactor/Service.qml) -eq 1 ]] \
  || fail "Mode 8 quote service must be process-wide"
if rg -q '\bProcess\b' hancore.shibumi.reactor/QuoteService.qml; then
  fail "Mode 8 quote service must not spawn processes"
fi
[[ $(rg -c 'FileView \{' hancore.shibumi.reactor/QuoteService.qml) -eq 1 ]] \
  || fail "Mode 8 must read user quotes through exactly one root FileView"
[[ $(rg -c 'Timer \{' hancore.shibumi.reactor/QuoteService.qml) -eq 1 ]] \
  || fail "Mode 8 must schedule quotes through exactly one root timer"
if rg -q 'Quickshell\.(Networking|Services\.(Pipewire|Mpris|Notifications))' \
  hancore.shibumi.reactor/ReactorService.qml; then
  fail "Reactor service duplicates a Quattro-owned service backend"
fi
[[ $(rg -c 'Process \{' hancore.shibumi.reactor/ReactorService.qml) -eq 1 ]] \
  || fail "Mode 7 may own only the single legacy pacman event tail"
rg -q 'firstPartyService\("omarchy\.media"\)' hancore.shibumi.reactor/ReactorService.qml \
  || fail "Reactor media events bypass Quattro media ownership"
rg -q 'statusService\.notificationService' hancore.shibumi.reactor/ReactorService.qml \
  || fail "Reactor notification events bypass Quattro notification ownership"
rg -q 'item\.screenName = barWindow\.screen' core/BarPanel.qml \
  || fail "Reactor renderer does not receive its physical output name"
rg -q 'G8: \["hancore.shibumi.center"\]' core/GroupRegistry.js \
  || fail "G8 is not owned by the Shibumi center composite"
rg -q 'G2: \["hancore.shibumi.workspaces"\]' core/GroupRegistry.js \
  || fail "G2 is not owned by the extracted Shibumi workspace plugin"
rg -q 'PanelRouting.findPanelWidget' Bar.qml \
  || fail "nested panel routing is not active"
rg -q 'PanelRouting.findPanelWidgetForScreen' Bar.qml \
  || fail "bar-widget IPC does not route to a requested output"
rg -q 'Hyprland.focusedMonitor' Bar.qml \
  || fail "bar-widget IPC does not prefer the focused output"
rg -q 'property string screenName:' core/WidgetSlot.qml \
  || fail "widget slots do not accept explicit output identity"
rg -q 'screenName: root\.screenName' core/GroupSlot.qml core/BarSection.qml \
  || fail "bar/group sections do not propagate explicit output identity"
rg -Fq 'screenName: root ? root.screenName : ""' \
  styles/shibumi/GroupSection.qml \
  || fail "group renderer does not propagate guarded output identity"
rg -q 'function childPanelWidget\(pluginId\)' widgets/CenterWidget.qml \
  || fail "center composite does not expose nested weather routing"
rg -q 'G3: \["hancore.shibumi.status"\]' core/GroupRegistry.js \
  || fail "G3 is not owned by the Shibumi status composite"
for consumed_alias in omarchy.audio omarchy.clock omarchy.network omarchy.power; do
  rg -Fq "\"$consumed_alias\"" core/GroupRegistry.js \
    || fail "stock Omarchy alias leaks into Shibumi: $consumed_alias"
done
rg -Fq 'entry.shibumiModule === true' core/GroupRegistry.js \
  || fail "explicit Quattro modules cannot opt into the Shibumi bar"
rg -q 'hancore\.shibumi\.status' widgets/WidgetRegistry.qml \
  || fail "Shibumi status composite is not registered"
rg -q 'hancore\.shibumi\.update-center' widgets/StatusWidget.qml \
  || fail "G3 status presentation does not own the Shibumi update center"
if rg -q 'omarchy\.system-update' widgets/StatusWidget.qml; then
  fail "G3 status presentation must not own the Omarchy update widget"
fi
rg -q 'omarchy\.system-update' widgets/CenterWidget.qml \
  || fail "G8 center presentation does not own the Omarchy update widget"
rg -q 'StatusIndicators' widgets/CenterWidget.qml \
  || fail "G8 does not render the V1 status indicator facade"
rg -q 'SystemUpdateWidget' widgets/CenterWidget.qml \
  || fail "G8 does not render the V1 Omarchy-update facade"
rg -q '^  width: implicitWidth$' widgets/SystemUpdateWidget.qml \
  || fail "G8 update indicator does not expose its visual width as a hit target"
rg -q '^  height: implicitHeight$' widgets/SystemUpdateWidget.qml \
  || fail "G8 update indicator does not expose its visual height as a hit target"
if rg -q 'Process \{|Timer \{|IpcHandler \{' widgets/SystemUpdateWidget.qml; then
  fail "Omarchy-update facade duplicates the official backend owner"
fi
rg -q 'onTabRequested' widgets/CalendarPanel.qml \
  || fail "G8 calendar is missing sibling-panel keyboard routing"
rg -q 'ShibumiPanelToolTip \{' widgets/CalendarPanel.qml \
  || fail "G8 calendar navigation bypasses the Shibumi tooltip"
if rg -q 'registeredSource\("omarchy\.indicators"\)' widgets/CenterWidget.qml; then
  fail "G8 must not instantiate Quattro's stock indicator presentation"
fi
rg -q '"service": "Service.qml"' hancore.shibumi.status/manifest.json \
  || fail "status backend is not process-wide"
rg -q 'WeatherService \{' hancore.shibumi.center/Service.qml \
  || fail "weather backend is not process-wide"
rg -q 'WeatherWidget' widgets/CenterWidget.qml \
  || fail "G8 does not render the V1 weather facade"
if rg -q 'SystemTray\.items|NotificationServer|Process \{|FileView \{' \
  widgets/StatusWidget.qml widgets/TrayStatusView.qml \
  widgets/NotificationStatusView.qml widgets/TrayDrawerPanel.qml; then
  fail "status composite must not duplicate official service or polling ownership"
fi
[[ $(rg -c 'Timer \{' widgets/StatusWidget.qml) -eq 1 ]] \
  || fail "status composite must own exactly one lifecycle timer"
rg -U -q 'Timer \{\n[[:space:]]*id: childSyncTimer\n[[:space:]]*interval: 0\n' \
  widgets/StatusWidget.qml \
  || fail "status lifecycle timer must be the zero-delay child loader sync"
if rg -q 'Timer \{' widgets/TrayStatusView.qml \
    widgets/NotificationStatusView.qml widgets/TrayDrawerPanel.qml; then
  fail "status child presentations must not own timers"
fi
rg -q 'trayBackend: root\.trayWidget' widgets/StatusWidget.qml \
  || fail "G3 tray presentation is not bound to the official tray owner"
rg -q 'notificationService: root\.notificationService' widgets/StatusWidget.qml \
  || fail "G3 notification presentation is not bound to the official service"
rg -q 'G6: \["hancore.shibumi.audio"\]' core/GroupRegistry.js \
  || fail "G6 is not owned by the Shibumi audio composite"
rg -q 'hancore\.shibumi\.audio' widgets/WidgetRegistry.qml \
  || fail "Shibumi audio composite is not registered"
rg -q 'Adapters\.AudioPanelBridge' widgets/AudioWidget.qml \
  || fail "audio view does not preserve the official panel owner"
rg -q 'popupSource: Qt\.resolvedUrl\("AudioPanel\.qml"\)' widgets/AudioWidget.qml \
  || fail "audio widget does not lazy-load the Shibumi mixer panel"
rg -q 'return String\(pluginId \|\| ""\) === "omarchy\.audio" \? root : null' \
  widgets/AudioWidget.qml \
  || fail "official audio routing is not redirected to the Shibumi owner"
rg -q 'manageIpc: false' widgets/AudioWidget.qml \
  || fail "audio aliases must use screen-aware host routing, not duplicate IPC handlers"
if rg -q 'Quickshell\.Services\.Pipewire|Pipewire\.' widgets/AudioWidget.qml \
  adapters/AudioPanelBridge.qml; then
  fail "Shibumi audio presentation must not create a second PipeWire owner"
fi
if rg -q 'Process \{|FileView \{' widgets/AudioWidget.qml \
  adapters/AudioPanelBridge.qml; then
  fail "audio presentation bridge must remain event-driven and worker-free"
fi
rg -q 'panelLoader\.active = false' adapters/AudioPanelBridge.qml \
  || fail "audio backend panel is not unloaded before its host facade"
if rg -q 'panel\.bar = null' adapters/AudioPanelBridge.qml; then
  fail "audio teardown invalidates the host facade before panel destruction"
fi
[[ $(rg -c 'Timer \{' widgets/AudioWidget.qml) -eq 2 ]] \
  || fail "audio widget must own only the bounded wheel commit/settle timers"
rg -U -q 'Timer \{\n[[:space:]]*id: wheelCommitTimer\n[[:space:]]*interval: 70\n' \
  widgets/AudioWidget.qml \
  || fail "audio wheel commit timer contract changed"
rg -U -q 'Timer \{\n[[:space:]]*id: wheelSettleTimer\n[[:space:]]*interval: 300\n' \
  widgets/AudioWidget.qml \
  || fail "audio wheel settle timer contract changed"
if rg -U -q 'Timer \{([^}]|\n)*(repeat:[[:space:]]*true|running:[[:space:]]*true)' \
  widgets/AudioWidget.qml; then
  fail "audio wheel timers must remain dormant, non-repeating interaction timers"
fi
[[ $(rg -c 'PwNodePeakMonitor \{' widgets/AudioPanel.qml) -eq 1 ]] \
  || fail "audio panel must own exactly one lifecycle-bound microphone meter"
rg -q 'enabled: panel\.open' widgets/AudioPanel.qml \
  || fail "microphone meter is not bounded to the open mixer lifecycle"
if rg -q 'Pipewire\.|Process \{|FileView \{' widgets/AudioPanel.qml; then
  fail "Shibumi audio panel duplicates Quattro audio ownership or shell workers"
fi
rg -q 'displaySinks = \[\]' widgets/AudioPanel.qml \
  || fail "audio panel does not release sink rows on close"
rg -q 'displaySources = \[\]' widgets/AudioPanel.qml \
  || fail "audio panel does not release source rows on close"
rg -q 'displayStreams = \[\]' widgets/AudioPanel.qml \
  || fail "audio panel does not release stream rows on close"
rg -q 'G9: \["hancore.shibumi.media"\]' core/GroupRegistry.js \
  || fail "G9 is not owned by the Shibumi media presentation"
rg -q 'hancore\.shibumi\.media' widgets/WidgetRegistry.qml \
  || fail "Shibumi media presentation is not registered"
rg -q 'firstPartyServiceFor\("omarchy\.media"\)' widgets/MediaWidget.qml \
  || fail "media presentation does not reuse the official service"
if rg -q 'Quickshell\.Services\.(Mpris|Pipewire)|Mpris\.|Pipewire\.' \
  widgets/MediaWidget.qml widgets/MediaPanel.qml widgets/MediaPulse.qml \
  widgets/MediaSpectrum.qml widgets/MediaMuse.qml \
  hancore.shibumi.media/Service.qml; then
  fail "Shibumi media presentation must not create a second media owner"
fi
if rg -q 'Process \{|Timer \{|FileView \{' widgets/MediaWidget.qml \
  widgets/MediaPulse.qml widgets/MediaSpectrum.qml widgets/MediaMuse.qml; then
  fail "closed media bar presentation must remain worker-free"
fi
rg -q 'serviceFor\("hancore\.shibumi\.media"\)' widgets/MediaWidget.qml \
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
if rg -q 'Process \{|FileView \{' widgets/MediaPanel.qml \
  hancore.shibumi.media/MediaPanel.qml; then
  fail "screen-local media panels must not own spectrum workers"
fi
rg -q 'G10: \["hancore.shibumi.quick-access"\]' core/GroupRegistry.js \
  || fail "G10 is not owned by the Shibumi quick-access presentation"
rg -q 'hancore\.shibumi\.quick-access' widgets/WidgetRegistry.qml \
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
rg -q 'function screenForName\(value\)' Bar.qml \
  || fail "G10 IPC picker cannot resolve host output objects"
if rg -q 'Commons\.Style\.font\.size\.' widgets/PickerOverlay.qml \
  widgets/PickerImage.qml widgets/TanzakuPickerView.qml \
  widgets/HearthstonePickerView.qml; then
  fail "G10 picker uses V1-only font token paths"
fi
rg -q 'Commons\.Util\.fileUrl\(entry\.thumbnailPath\)' \
  hancore.shibumi.quick-access/Service.qml \
  || fail "G10 thumbnail URLs do not use the host-safe file URL helper"
rg -q 'file -Lb --mime-type' hancore.shibumi.quick-access/Service.qml \
  || fail "G10 screenshot copy hard-codes an incorrect image MIME type"
for picker_view in widgets/TanzakuPickerView.qml \
  widgets/HearthstonePickerView.qml; do
  if rg -q 'Process \{|Timer \{|FileView \{' "$picker_view"; then
    fail "picker presentation owns controller work: $picker_view"
  fi
done
rg -q 'readonly property bool spectrumRequested: open && active && spectrumEnabled' \
  widgets/MediaPanel.qml \
  || fail "media spectrum worker is not panel-lifecycle gated"
rg -q 'command: \["cava", "-p", "/dev/stdin"\]' \
  hancore.shibumi.media/Service.qml \
  || fail "process-wide media spectrum does not own the Cava process"
rg -q 'stdinEnabled: true' hancore.shibumi.media/Service.qml \
  || fail "media spectrum configuration is not streamed over stdin"
if rg -q 'mktemp|/tmp/|<\(printf' hancore.shibumi.media/Service.qml; then
  fail "media spectrum worker must not create temporary config artifacts"
fi
rg -q 'G11: \["hancore.shibumi.network"\]' core/GroupRegistry.js \
  || fail "G11 is not owned by the Shibumi network presentation"
rg -q 'hancore\.shibumi\.network' widgets/WidgetRegistry.qml \
  || fail "Shibumi network presentation is not registered"
[[ $(rg -c 'NetworkPanelBridge \{' hancore.shibumi.network/Service.qml) -eq 1 ]] \
  || fail "network backend must be process-wide"
rg -q 'Adapters\.NetworkPanelBridge' services/NetworkService.qml \
  || fail "root network service does not preserve the official panel owner"
if rg -q 'Adapters\.NetworkPanelBridge|Quickshell\.Networking|Networking\.' \
  widgets/NetworkWidget.qml widgets/NetworkPanel.qml; then
  fail "screen-local network presentation must not own NetworkManager"
fi
if rg -q 'Process \{|FileView \{' widgets/NetworkWidget.qml \
  widgets/NetworkPanel.qml adapters/NetworkPanelBridge.qml; then
  fail "screen-local network presentation must not own backend workers"
fi
if rg -q 'Timer \{' widgets/NetworkWidget.qml adapters/NetworkPanelBridge.qml; then
  fail "network widget and backend bridge must remain event-driven"
fi
[[ $(rg -c 'Adapters\.NetworkPanelBridge \{' services/NetworkService.qml) -eq 1 ]] \
  || fail "root network service must own exactly one official backend"
rg -q 'property var sessionOwners: \[\]' services/NetworkService.qml \
  || fail "network service lacks multi-output session accounting"
rg -q 'profileList\.running = false' services/NetworkService.qml \
  || fail "network service does not stop saved-profile discovery on final close"
rg -q 'detailsProc\.running = false' services/NetworkService.qml \
  || fail "network service does not stop detail sampling on final close"
rg -q 'property var scannerDevice: null' services/NetworkService.qml \
  || fail "network service does not track its scanner lease"
rg -q 'if \(scannerDevice && scannerDevice !== nextDevice\)' \
  services/NetworkService.qml \
  || fail "network service does not release replaced scanner devices"
rg -q 'releaseWifiScanner\(\)' services/NetworkService.qml \
  || fail "network scanner is not released outside panel sessions"
if rg -q 'scannerEnabled' adapters/NetworkPanelBridge.qml; then
  fail "network bridge competes with the root scanner owner"
fi
rg -q 'command: \["omarchy-network-status", "--verbose"\]' \
  services/NetworkService.qml \
  || fail "network panel details do not use the shared root lifecycle worker"
if rg -U -q 'id: detailsPoll[\s\S]{0,240}root\.refresh' \
  services/NetworkService.qml; then
  fail "network details poll must not restart DNS/profile refresh work"
fi
rg -q 'childPanelWidget\("omarchy\.network"\)' tests/network-widget-smoke.qml \
  || fail "network alias routing is not regression-tested"
rg -q 'G13: \["hancore.shibumi.brightness"\]' core/GroupRegistry.js \
  || fail "G13 is not owned by the Shibumi brightness presentation"
rg -q 'hancore\.shibumi\.brightness' widgets/WidgetRegistry.qml \
  || fail "Shibumi brightness presentation is not registered"
[[ $(rg -c 'MonitorPanelBridge \{' hancore.shibumi.brightness/Service.qml) -eq 1 ]] \
  || fail "brightness/display state must have one root monitor owner"
[[ $(rg -c 'Adapters\.MonitorPanelBridge \{' services/MonitorService.qml) -eq 1 ]] \
  || fail "root monitor service must own exactly one official backend"
rg -q 'bar\.monitorService' widgets/BrightnessWidget.qml \
  || fail "brightness view does not consume the shared monitor owner"
if rg -q 'Quickshell\.Services\.UPower|UPower\.|Quickshell\.Io' \
  widgets/BrightnessWidget.qml widgets/BrightnessPanel.qml \
  adapters/MonitorPanelBridge.qml services/MonitorService.qml; then
  fail "Shibumi brightness presentation must not create a second monitor owner"
fi
if rg -q 'Process \{|Timer \{|FileView \{' widgets/BrightnessWidget.qml \
  widgets/BrightnessPanel.qml services/MonitorService.qml \
  adapters/MonitorPanelBridge.qml; then
  fail "brightness presentation and monitor adapter must remain worker-free"
fi
if rg -q '^[[:space:]]*selected:' widgets/BrightnessPanel.qml; then
  fail "brightness panel uses Button-only selected state on CursorSurface"
fi
rg -q 'childPanelWidget\("omarchy\.monitor"\)' tests/brightness-widget-smoke.qml \
  || fail "monitor alias routing is not regression-tested"
rg -q 'G12: \["hancore.shibumi.battery"\]' core/GroupRegistry.js \
  || fail "G12 is not owned by the Shibumi battery presentation"
rg -q 'G14: \["hancore.shibumi.power-profile"\]' core/GroupRegistry.js \
  || fail "G14 is not owned by the Shibumi power-profile presentation"
for power_widget in hancore.shibumi.battery hancore.shibumi.power-profile; do
  rg -q "$power_widget" widgets/WidgetRegistry.qml \
    || fail "Shibumi power presentation is not registered: $power_widget"
done
rg -q '"service": "Service.qml"' hancore.shibumi.power-state/manifest.json \
  || fail "battery/profile state must have one root power owner"
rg -q 'Quickshell.Services.UPower' services/PowerService.qml \
  || fail "power owner does not consume the event-driven UPower singleton"
rg -q 'command: \["omarchy-powerprofiles-list", "--active-state"\]' \
  services/PowerService.qml \
  || fail "power owner does not use the Quattro profile contract"
rg -Fq 'command: ["busctl", "--system", "get-property",' \
  services/PowerService.qml \
  || fail "power owner does not use the lightweight active-profile probe"
rg -Fq 'onTriggered: root.refreshActiveProfile()' \
  services/PowerService.qml \
  || fail "power hot path still refreshes the complete profile list"
rg -Fq 'interval: 5 * 60 * 1000' services/PowerService.qml \
  || fail "power profile list does not have a bounded reconcile fallback"
rg -q 'omarchy-battery-status --shell' \
  services/PowerService.qml \
  || fail "power owner does not use the Quattro battery detail contract"
if rg -q 'Quickshell\.Services\.UPower|Quickshell\.Io|Process \{|Timer \{|FileView \{' \
  widgets/BatteryWidget.qml widgets/BatteryPanel.qml \
  widgets/PowerProfileWidget.qml widgets/PowerProfilePanel.qml; then
  fail "power views must not duplicate UPower, worker, or polling ownership"
fi
rg -q 'acquireBatteryDetails' widgets/BatteryWidget.qml \
  || fail "battery detail process is not panel-lifecycle gated"
rg -q 'releaseBatteryDetails' widgets/BatteryWidget.qml \
  || fail "battery detail process lease is not released"
for monitor_widget in Cpu Memory Battery; do
  rg -q 'bar\.run\("omarchy-launch-or-focus-tui btop"\)' \
    "widgets/${monitor_widget}Widget.qml" \
    || fail "$monitor_widget does not use the Quattro TUI launcher"
  rg -q 'panel\.ownerWidget\.openSystemMonitor\(\)' \
    "widgets/${monitor_widget}Panel.qml" \
    || fail "$monitor_widget panel bypasses its owner action"
done
rg -q 'acquireProfiles' widgets/PowerProfileWidget.qml \
  || fail "profile state does not use the shared service lease"
rg -q 'releaseProfiles' widgets/PowerProfileWidget.qml \
  || fail "profile state lease is not released"
rg -q 'G15: \["hancore.shibumi.bluetooth"\]' core/GroupRegistry.js \
  || fail "G15 is not owned by the Shibumi bluetooth presentation"
rg -q 'hancore\.shibumi\.bluetooth' widgets/WidgetRegistry.qml \
  || fail "Shibumi bluetooth presentation is not registered"
[[ $(rg -c 'BluetoothBackendAdapter \{' hancore.shibumi.bluetooth/Service.qml) -eq 1 ]] \
  || fail "Bluetooth state must have one root owner"
[[ $(rg -c 'Adapters\.BluetoothBackendAdapter \{' services/BluetoothService.qml) -eq 1 ]] \
  || fail "root Bluetooth service must own exactly one native backend"
rg -q 'bar\.bluetoothService' widgets/BluetoothWidget.qml \
  || fail "Bluetooth view does not consume the shared owner"
rg -q 'property var sessionOwners: \[\]' services/BluetoothService.qml \
  || fail "Bluetooth service lacks multi-output session accounting"
rg -q 'target: "omarchy\.bluetooth"' services/BluetoothService.qml \
  || fail "Bluetooth service does not own the single legacy IPC target"
rg -q 'bar\.hideBarWidget\("omarchy\.bluetooth"\)' services/BluetoothService.qml \
  || fail "Bluetooth legacy close/hide is not routed to the local panel"
rg -q 'adapter\.stopDiscovery\(\)' services/BluetoothService.qml \
  || fail "Bluetooth discovery is not stopped after the final panel closes"
for bluetooth_adapter in \
  adapters/BluetoothBackendAdapter.qml \
  hancore.shibumi.bluetooth/BluetoothBackendAdapter.qml; do
  rg -q '^import Quickshell\.Bluetooth$' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not own the native BlueZ model"
  rg -q '^import Quickshell\.Services\.Pipewire$' "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not own Bluetooth audio routing"
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
  rg -U -q 'function validatePendingAudioOutput\(\)[^}]*!radioEnabled[^}]*!device\.connected[^}]*!deviceUsesCurrentAdapter' \
    "$bluetooth_adapter" \
    || fail "$bluetooth_adapter does not revalidate audio handoff state"
  [[ $(rg -c '^  Timer \{' "$bluetooth_adapter") -eq 4 ]] \
    || fail "$bluetooth_adapter must have exactly four bounded lifecycle timers"
  if rg -q 'IpcHandler \{|Loader \{|panelSource|panelComponent|registeredWidget' \
      "$bluetooth_adapter"; then
    fail "$bluetooth_adapter still owns IPC or loads a foreign UI component"
  fi
done
cmp -s adapters/BluetoothBackendAdapter.qml \
  hancore.shibumi.bluetooth/BluetoothBackendAdapter.qml \
  || fail "root and plugin Bluetooth adapters drifted"
cmp -s adapters/BluetoothModel.js hancore.shibumi.bluetooth/BluetoothModel.js \
  || fail "root and plugin Bluetooth models drifted"
cmp -s adapters/BluetoothDiscoveryGuard.qml \
  hancore.shibumi.bluetooth/BluetoothDiscoveryGuard.qml \
  || fail "root and plugin Bluetooth discovery guards drifted"
for bluetooth_service in \
  services/BluetoothService.qml \
  hancore.shibumi.bluetooth/Service.qml; do
  rg -U -q 'id: discoveryRetry[^}]*repeat: true[^}]*running: root\.sessionCount > 0 && root\.adapterAvailable[^}]*root\.radioEnabled && !root\.discovering' \
    "$bluetooth_service" \
    || fail "$bluetooth_service does not bound discovery retries to an open session"
done
if rg -q 'registeredWidget|registeredSource|registeredComponent|panelSource|panelComponent|Loader \{' \
    services/BluetoothService.qml hancore.shibumi.bluetooth/Service.qml; then
  fail "Bluetooth service still resolves or loads the complete Omarchy panel"
fi
if rg -q 'Quickshell\.Bluetooth|Quickshell\.Services\.Pipewire|Bluetooth\.|Pipewire\.' \
  widgets/BluetoothWidget.qml widgets/BluetoothPanel.qml \
  services/BluetoothService.qml; then
  fail "Bluetooth presentation bypasses the process-wide native adapter"
fi
if rg -q 'Process \{|Timer \{|FileView \{' widgets/BluetoothWidget.qml \
    widgets/BluetoothPanel.qml; then
  fail "Bluetooth presentation must remain worker-free"
fi
if rg -q 'Process \{|FileView \{' services/BluetoothService.qml; then
  fail "Bluetooth service facade must remain process- and file-worker-free"
fi
if rg -q 'Process \{|FileView \{' adapters/BluetoothBackendAdapter.qml \
    hancore.shibumi.bluetooth/BluetoothBackendAdapter.qml; then
  fail "Bluetooth native adapter uses a worker instead of native APIs"
fi
rg -q 'childPanelWidget\("omarchy\.bluetooth"\)' tests/bluetooth-widget-smoke.qml \
  || fail "Bluetooth alias routing is not regression-tested"

[[ $(rg -c 'SystemTelemetry \{' hancore.shibumi.telemetry/Service.qml) -eq 1 ]] \
  || fail "system telemetry must have one root owner"
if rg -q 'Process \{' services/SystemTelemetry.qml; then
  fail "system telemetry must read procfs without child processes"
fi
rg -q '"service": "WorkspaceService.qml"' hancore.shibumi.workspaces/manifest.json \
  || fail "workspace state must have exactly one root owner"
[[ $(rg -c 'ClockService \{' hancore.shibumi.center/Service.qml) -eq 1 ]] \
  || fail "clock state must have exactly one root owner"
if rg -q 'Process \{|Timer \{|FileView \{' services/ClockService.qml \
  widgets/ClockWidget.qml; then
  fail "clock slice must use the shared event-driven SystemClock"
fi
rg -q 'Ui\.WidgetButton \{' widgets/ClockWidget.qml \
  || fail "clock interaction is not registered for overlay click forwarding"
[[ $(rg -c 'WorkspaceActions \{' hancore.shibumi.workspaces/WorkspaceService.qml) -eq 1 ]] \
  || fail "workspace actions must have exactly one root adapter"
[[ $(rg -c 'Core\.LayoutController \{' Bar.qml) -eq 1 ]] \
  || fail "layout persistence must have exactly one root controller"
[[ $(rg -c '^  DragSession \{' core/BarPanel.qml) -eq 1 ]] \
  || fail "each output must own exactly one transient drag session"
rg -q 'stateService: root\.pluginService\("hancore\.shibumi\.state"\)' Bar.qml \
  || fail "layout controller is not bound to normalized Shibumi state"
rg -q 'stateService\.setLayout' core/LayoutController.qml \
  || fail "layout mutations bypass the process-wide state owner"
rg -q 'layoutController: barWindow\.bar\.layoutController' core/BarPanel.qml \
  || fail "per-output drag session does not consume shared layout state"
rg -q 'item\.layoutSession = dragSession' core/BarPanel.qml \
  || fail "bar surface does not receive its per-output drag session"
if rg -q 'LayoutController \{|DragSession \{' styles; then
  fail "styles must not own layout persistence or drag sessions"
fi
if rg -q 'Process \{|Timer \{|FileView \{' core/LayoutController.qml \
  core/DragSession.qml; then
  fail "layout and drag core must remain event-driven and worker-free"
fi
rg -q 'omarchy\.workspaces' widgets/WidgetRegistry.qml \
  || fail "Shibumi workspace widget does not override the host workspace slot"
rg -q '^Ui\.Panel \{' widgets/WorkspaceWidget.qml \
  || fail "workspace widget does not implement the shared panel contract"
rg -q '^ShibumiPanel \{' widgets/WorkspacePanel.qml \
  || fail "workspace panel does not use the screen-local keyboard panel contract"
  if rg -q 'Process \{|Timer \{|FileView \{' services/WorkspaceService.qml \
  adapters/WorkspaceActions.qml widgets/WorkspaceWidget.qml widgets/WorkspacePanel.qml \
  widgets/WorkspacePanelContent.qml; then
  fail "workspace slice must remain event-driven and worker-free"
fi
if rg -q 'Quickshell\.Hyprland|Hyprland\.' widgets/WorkspaceWidget.qml \
  widgets/WorkspacePanel.qml; then
  fail "workspace views must consume the shared workspace service"
fi
rg -q 'Number\.isInteger\(id\)' adapters/WorkspaceActions.qml \
  || fail "workspace action adapter does not validate ids"
rg -q 'bar\.run\("hyprctl dispatch' adapters/WorkspaceActions.qml \
  || fail "workspace action adapter does not use the host launcher"
rg -q 'hancore\.shibumi\.memory' widgets/WidgetRegistry.qml \
  || fail "internal memory widget is not registered"
rg -q 'hancore\.shibumi\.cpu' widgets/WidgetRegistry.qml \
  || fail "internal CPU widget is not registered"
rg -q 'G7: \["hancore\.shibumi\.ai"\]' core/GroupRegistry.js \
  || fail "G7 is not owned by the Shibumi AI facade"
rg -q 'hancore\.shibumi\.ai' widgets/WidgetRegistry.qml \
  || fail "Shibumi AI facade is not registered"
rg -q '"service": "Service.qml"' hancore.shibumi.ai/manifest.json \
  || fail "AI provider state must have one root owner"
rg -q 'function childPanelWidget\(pluginId\)' widgets/AiUsageWidget.qml \
  || fail "AI facade does not expose legacy model-usage panel routing"
if rg -q 'CACHE_FILE|stale_last' scripts/opencode-usage; then
  fail "OpenCode provider must not persist a V1 usage cache"
fi
if rg -q 'Process \{|Timer \{|FileView \{' widgets/AiUsageWidget.qml \
  widgets/AiUsagePanel.qml; then
  fail "AI views must not own provider polling or file watchers"
fi
rg -q 'G1: \["hancore.shibumi.control-center"\]' core/GroupRegistry.js \
  || fail "G1 does not resolve the extracted Control Center plugin"
rg -q 'function setGroupSetting\(groupId, key, value\)' \
  hancore.shibumi.state/Service.qml \
  || fail "G1 cannot persist group settings through the state owner"
rg -q 'function setPresentationSetting\(key, value\)' \
  hancore.shibumi.state/Service.qml \
  || fail "G1 cannot persist Shibumi presentation settings"
rg -q 'function setBarPosition\(value, ownerValue, screenName\)' Bar.qml \
  || fail "G1 cannot persist output-local top/bottom position"
rg -q 'function setAllSplits\(value\)' Bar.qml \
  || fail "G1 cannot persist split presets"
detail_panel_count=$(rg --files widgets -g '*Panel.qml' \
  | rg -v '(^|/)ShibumiPanel\.qml$' | wc -l)
[[ $(rg -l '^ShibumiPanel \{' widgets/*Panel.qml | wc -l) \
  -eq $detail_panel_count ]] \
  || fail "local detail panels do not share the Shibumi surface contract"
[[ $(rg -l '^Ui\.KeyboardPanel \{' widgets/*Panel.qml | wc -l) -eq 0 ]] \
  || fail "a local detail panel still layers host panel chrome"
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
  'widgets/AiUsagePanel.qml:panel.controlBorderColor' \
  'widgets/AudioPanel.qml:panel.controlHoverBorderColor' \
  'widgets/BluetoothPanel.qml:panel.controlBorderColor' \
  'widgets/BrightnessPanel.qml:panel.controlActiveFillColor' \
  'widgets/BrightnessPanel.qml:panel.controlBorderColor' \
  'widgets/NetworkPanel.qml:panel.controlBorderColor' \
  'widgets/PowerProfilePanel.qml:panel.controlBorderColor' \
  'widgets/WorkspacePanelContent.qml:root.controller.controlFillColor'; do
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
rg -q 'omarchy\.clock' widgets/WidgetRegistry.qml \
  || fail "Shibumi clock does not override the host clock slot"
rg -q 'hancore\.shibumi\.center' widgets/WidgetRegistry.qml \
  || fail "Shibumi center composite is not registered"
rg -q 'GroupSection' styles/shibumi/BarSurface.qml \
  || fail "Shibumi surface does not render persisted groups"
rg -Uq 'id: leftGroups[[:space:][:print:]]*visibilityStage: horizontalSurface\.narrowStage' \
  styles/shibumi/BarSurface.qml \
  || fail "left groups do not receive the responsive visibility stage"
rg -Uq 'id: rightGroups[[:space:][:print:]]*visibilityStage: horizontalSurface\.narrowStage' \
  styles/shibumi/BarSurface.qml \
  || fail "right groups do not receive the responsive visibility stage"
rg -q 'GroupRegistry\.unassignedEntries' Bar.qml \
  || fail "custom host layout entries are not preserved"
if rg -q 'Process \{|FileView \{' core/GroupSlot.qml \
  styles/shibumi/GroupSection.qml; then
  fail "group renderer must remain event-driven and worker-free"
fi
if rg -q 'Timer \{' core/GroupSlot.qml; then
  fail "group slots must not own timers"
fi
[[ $(rg -c 'Timer \{' styles/shibumi/GroupSection.qml) -eq 2 ]] \
  || fail "group sections must own exactly two lifecycle-bound timers"
rg -U -q 'Timer \{\n[[:space:]]*id: layoutTimer\n[[:space:]]*interval: 0\n[[:space:]]*onTriggered: \{\n[[:space:]]*if \(horizontalRow\) horizontalRow\.forceLayout\(\)' \
  styles/shibumi/GroupSection.qml \
  || fail "group layout work is not owned by the horizontal row lifecycle"
if rg -Fq 'Qt.callLater' styles/shibumi/GroupSection.qml; then
  fail "group layout work can outlive its horizontal row context"
fi
rg -U -q 'Timer \{\n[[:space:]]*id: registrationTimer\n[[:space:]]*interval: 0\n' \
  styles/shibumi/GroupSection.qml \
  || fail "group lifecycle timer must be the zero-delay target registration sync"
for teardown_contract in \
  'const owner = root' \
  'if (!owner) {' \
  'clearTargetRegistration()' \
  'if (registrationTimer) registrationTimer.stop()' \
  'if (horizontalRow) horizontalRow.scheduleLayout()' \
  '? horizontalRow.nextShownIndex(index) : -1' \
  '? root.separatorCenterOffset(horizontalCell.separated) : 0'; do
  rg -Fq "$teardown_contract" styles/shibumi/GroupSection.qml \
    || fail "group teardown guard is missing: $teardown_contract"
done
for unsafe_teardown_access in \
  'const nextAsSlot = root.slotEditing' \
  'onWidthChanged: horizontalRow.scheduleLayout()' \
  'onVisibleChanged: horizontalRow.scheduleLayout()'; do
  if rg -Fq "$unsafe_teardown_access" styles/shibumi/GroupSection.qml; then
    fail "group teardown retains an unsafe owner access: $unsafe_teardown_access"
  fi
done
rg -q 'acquire\("memory"\)' widgets/MemoryWidget.qml \
  || fail "memory widget does not activate shared telemetry"
rg -q 'release\("memory"\)' widgets/MemoryWidget.qml \
  || fail "memory widget does not release shared telemetry"
rg -q 'acquire\("cpu"\)' widgets/CpuWidget.qml \
  || fail "CPU widget does not activate shared telemetry"
rg -q 'release\("cpu"\)' widgets/CpuWidget.qml \
  || fail "CPU widget does not release shared telemetry"

for facade_name in \
  position vertical barSize barHidden fontFamily foreground barForeground \
  background urgent foregroundAnimationEnabled activePopout \
  centerSectionRevealHeld centerHoverRevealSuppressed; do
  rg -q "^[[:space:]]*(readonly )?property .* ${facade_name}([: ])" Bar.qml \
    || fail "missing stock-widget bar facade property: $facade_name"
done

for facade_function in \
  run showTooltip hideTooltip requestPopout releasePopout \
  registerClickTarget unregisterClickTarget switchPanelFrom openConfigPanel \
  debugBarGeometry; do
  rg -q "^[[:space:]]*function ${facade_function}\(" Bar.qml \
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
  "$repo_root/tests/layout-controller-regression.qml"
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
cp services/QuoteDefaults.js services/ReactorModel.js \
  services/QuoteService.qml "$quote_smoke_root/services/"
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
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/center-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/network-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/brightness-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/bluetooth-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/power-plugins-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/ai-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/quick-access-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/reactor-plugin-regression.sh"
  OMARCHY_PATH="$OMARCHY_PATH" "$repo_root/tests/bar-host-registry-regression.sh"
  "$repo_root/tests/window-recovery-regression.sh"

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
  official_network_panel=${OMARCHY_PATH}/shell/plugins/panels/network/Panel.qml
  [[ -s $official_network_panel ]] || fail "official Quattro network panel is missing"
  for network_contract in networkManagerAvailable kind signalStrength \
    connectedWifiNetwork info wifiNetworks wifiDevice dnsProvider refresh \
    connectKnown connectWithPassphrase disconnect forget setDns; do
    rg -q "${network_contract}" "$official_network_panel" \
      || fail "official network panel contract changed: $network_contract"
  done
  official_network_speedtest=${OMARCHY_PATH}/bin/omarchy-network-speedtest
  [[ -x $official_network_speedtest ]] \
    || fail "official network speed-test command is missing"
  for speed_contract in \
    'direction="${1:-}"' \
    'down | up' \
    'omarchy-network-speedtest [down|up]' \
    'format_mbps' \
    'trap cleanup EXIT'; do
    rg -Fq "$speed_contract" "$official_network_speedtest" \
      || fail "network speed-test command changed: $speed_contract"
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
  for status_contract in pendingModel pastModel doNotDisturb setDoNotDisturb \
    markAllSeen dismissPending dismissPast clearPast; do
    rg -q "$status_contract" "$official_notification_service" \
      || fail "official notification widget contract changed: $status_contract"
  done

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
  done < <(rg -o '"omarchy\.[a-z0-9-]+"' core/GroupRegistry.js \
    | tr -d '"' | sort -u)

  smoke_root=$(mktemp -d)
  trap 'rm -rf -- "$smoke_root"' EXIT
  mkdir -p "$smoke_root/adapters" "$smoke_root/core" "$smoke_root/services" \
    "$smoke_root/styles/shibumi" "$smoke_root/widgets" "$smoke_root/runtime"
  chmod 700 "$smoke_root/runtime"
  cp -a "${OMARCHY_PATH}/shell/Commons" "$smoke_root/"
  cp -a "${OMARCHY_PATH}/shell/Ui" "$smoke_root/"
  cp widgets/ShibumiPanel.qml widgets/PillSurface.qml "$smoke_root/widgets/"
  cp core/BarSection.qml core/GroupRegistry.js core/GroupSlot.qml \
    core/LayoutController.qml core/LayoutModel.js core/V2LayoutModel.js \
    core/PanelRouting.js \
    core/ResponsiveLayout.js core/RunGeometry.js \
    core/WidgetSlot.qml "$smoke_root/core/"
  cp core/DragSession.qml "$smoke_root/core/"
  cp styles/shibumi/BarSurface.qml styles/shibumi/DragGhost.qml \
    styles/shibumi/GroupSection.qml styles/shibumi/RunChrome.qml \
    styles/shibumi/VisualTokens.qml styles/shibumi/GapEffectsLayer.qml \
    styles/shibumi/ReactorEventLayer.qml \
    "$smoke_root/styles/shibumi/"
  cp tests/group-renderer-regression.qml "$smoke_root/shell.qml"

  set +e
  group_renderer_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  group_renderer_rc=$?
  set -e
  printf '%s\n' "$group_renderer_output"
  [[ $group_renderer_rc -eq 0 ]] || fail "group renderer smoke exited $group_renderer_rc"
  grep -q 'group renderer regression passed' <<<"$group_renderer_output" \
    || fail "group renderer smoke did not reach its marker"

  cp tests/group-interaction-regression.qml "$smoke_root/shell.qml"

  set +e
  group_interaction_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  group_interaction_rc=$?
  set -e
  printf '%s\n' "$group_interaction_output"
  [[ $group_interaction_rc -eq 0 ]] \
    || fail "group interaction smoke exited $group_interaction_rc"
  grep -q 'group interaction regression passed' <<<"$group_interaction_output" \
    || fail "group interaction smoke did not reach its marker"

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

  cp services/SystemTelemetry.qml "$smoke_root/services/"
  cp services/ClockService.qml "$smoke_root/services/"
  cp widgets/MemoryWidget.qml "$smoke_root/widgets/"
  cp widgets/MemoryRing.qml "$smoke_root/widgets/"
  cp widgets/CpuWidget.qml "$smoke_root/widgets/"
  cp widgets/CpuWave.qml "$smoke_root/widgets/"
  cp widgets/PillSurface.qml widgets/IconText.qml "$smoke_root/widgets/"
  cp widgets/ClockWidget.qml "$smoke_root/widgets/"
  cp tests/memory-widget-smoke.qml "$smoke_root/shell.qml"
  sed -i \
    -e 's#import "../services"#import "services"#' \
    -e 's#import "../widgets"#import "widgets"#' \
    "$smoke_root/shell.qml"

  set +e
  smoke_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  smoke_rc=$?
  set -e
  printf '%s\n' "$smoke_output"
  [[ $smoke_rc -eq 0 ]] || fail "telemetry widget smoke exited $smoke_rc"
  grep -q 'telemetry widget smoke passed' <<<"$smoke_output" \
    || fail "telemetry widget smoke did not reach its lifecycle marker"

  cp tests/clock-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  clock_smoke_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  clock_smoke_rc=$?
  set -e
  printf '%s\n' "$clock_smoke_output"
  [[ $clock_smoke_rc -eq 0 ]] || fail "clock widget smoke exited $clock_smoke_rc"
  grep -q 'clock widget smoke passed' <<<"$clock_smoke_output" \
    || fail "clock widget smoke did not reach its lifecycle marker"

  cp widgets/CalendarModel.js widgets/CenterLayout.js widgets/CenterWidget.qml \
    widgets/IconText.qml widgets/StatusIndicators.qml widgets/SystemUpdateWidget.qml \
    widgets/WeatherWidget.qml \
    "$smoke_root/widgets/"
  cp tests/fixtures/CenterTestCalendar.qml \
    tests/fixtures/WeatherPanelTestView.qml "$smoke_root/"
  cp tests/center-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  center_smoke_output=$(timeout 6 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  center_smoke_rc=$?
  set -e
  printf '%s\n' "$center_smoke_output"
  [[ $center_smoke_rc -eq 0 ]] || fail "center widget smoke exited $center_smoke_rc"
  grep -q 'center widget smoke passed' <<<"$center_smoke_output" \
    || fail "center widget smoke did not reach its lifecycle marker"
  ! grep -Eq 'Type .* unavailable|No PanelWindow backend loaded' \
    <<<"$center_smoke_output" \
    || fail "center widget smoke accepted an unavailable panel type"

  cp adapters/AudioPanelBridge.qml "$smoke_root/adapters/"
  cp widgets/AudioWidget.qml "$smoke_root/widgets/"
  mkdir -p "$smoke_root/fixtures"
  cp tests/fixtures/AudioTestPanel.qml tests/fixtures/AudioTestView.qml \
    "$smoke_root/fixtures/"
  cp tests/audio-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  audio_smoke_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  audio_smoke_rc=$?
  set -e
  printf '%s\n' "$audio_smoke_output"
  [[ $audio_smoke_rc -eq 0 ]] || fail "audio widget smoke exited $audio_smoke_rc"
  grep -q 'audio widget smoke passed' <<<"$audio_smoke_output" \
    || fail "audio widget smoke did not reach its lifecycle marker"

  # Exercise the packaged plugin payload. The predecessor widget tree is not
  # part of release archives and may intentionally lag the extracted plugin.
  cp hancore.shibumi.network/BarWidget.qml \
    "$smoke_root/widgets/NetworkWidget.qml"
  cp hancore.shibumi.network/HostTokens.qml \
    hancore.shibumi.network/IconText.qml \
    hancore.shibumi.network/PillSurface.qml "$smoke_root/widgets/"
  cp tests/fixtures/NetworkTestService.qml tests/fixtures/NetworkTestView.qml \
    "$smoke_root/fixtures/"
  cp tests/network-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  network_smoke_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  network_smoke_rc=$?
  set -e
  printf '%s\n' "$network_smoke_output"
  [[ $network_smoke_rc -eq 0 ]] || fail "network widget smoke exited $network_smoke_rc"
  grep -q 'network widget smoke passed' <<<"$network_smoke_output" \
    || fail "network widget smoke did not reach its lifecycle marker"

  cp adapters/MonitorPanelBridge.qml "$smoke_root/adapters/"
  cp services/MonitorService.qml "$smoke_root/services/"
  cp widgets/BrightnessWidget.qml widgets/BrightnessPanel.qml \
    "$smoke_root/widgets/"
  cp tests/fixtures/MonitorTestPanel.qml tests/fixtures/MonitorTestView.qml \
    "$smoke_root/fixtures/"
  cp tests/brightness-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  brightness_smoke_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  brightness_smoke_rc=$?
  set -e
  printf '%s\n' "$brightness_smoke_output"
  [[ $brightness_smoke_rc -eq 0 ]] \
    || fail "brightness widget smoke exited $brightness_smoke_rc"
  grep -q 'brightness widget smoke passed' <<<"$brightness_smoke_output" \
    || fail "brightness widget smoke did not reach its lifecycle marker"

  cp services/PowerModel.js "$smoke_root/services/"
  cp widgets/BatteryWidget.qml widgets/BatteryPanel.qml \
    widgets/PowerProfileWidget.qml widgets/PowerProfilePanel.qml \
    "$smoke_root/widgets/"
  cp tests/fixtures/PowerTestService.qml tests/fixtures/PowerTestPanel.qml \
    "$smoke_root/fixtures/"
  cp tests/power-widgets-smoke.qml "$smoke_root/shell.qml"
  set +e
  power_smoke_output=$(timeout 7 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  power_smoke_rc=$?
  set -e
  printf '%s\n' "$power_smoke_output"
  [[ $power_smoke_rc -eq 0 ]] || fail "power widgets smoke exited $power_smoke_rc"
  grep -q 'power widgets smoke passed' <<<"$power_smoke_output" \
    || fail "power widgets smoke did not reach its lifecycle marker"

  cp services/PowerService.qml "$smoke_root/services/"
  mkdir -p "$smoke_root/power-bin"
  cp tests/fixtures/power-bin/* "$smoke_root/power-bin/"
  chmod 700 "$smoke_root/power-bin/"*
  printf 'balanced\n' >"$smoke_root/power-state"
  cp tests/power-service-runtime-smoke.qml "$smoke_root/shell.qml"
  set +e
  power_service_output=$(timeout 7 env \
    PATH="$smoke_root/power-bin:$PATH" \
    SHIBUMI_POWER_FIXTURE_STATE="$smoke_root/power-state" \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  power_service_rc=$?
  set -e
  printf '%s\n' "$power_service_output"
  [[ $power_service_rc -eq 0 ]] \
    || fail "power service runtime smoke exited $power_service_rc"
  grep -q 'power service runtime smoke passed' <<<"$power_service_output" \
    || fail "power service runtime smoke did not reach its lifecycle marker"
  [[ $(<"$smoke_root/power-state") == performance ]] \
    || fail "power service did not execute the exact validated profile action"

  cp adapters/BluetoothBackendAdapter.qml adapters/BluetoothModel.js \
    adapters/BluetoothDiscoveryGuard.qml adapters/qmldir \
    "$smoke_root/adapters/"
  cp services/BluetoothService.qml "$smoke_root/services/"
  cp widgets/BluetoothWidget.qml widgets/BluetoothPanel.qml "$smoke_root/widgets/"
  cp tests/fixtures/BluetoothTestBackend.qml \
    tests/fixtures/BluetoothTestView.qml "$smoke_root/fixtures/"
  cp tests/bluetooth-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  bluetooth_smoke_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  bluetooth_smoke_rc=$?
  set -e
  printf '%s\n' "$bluetooth_smoke_output"
  [[ $bluetooth_smoke_rc -eq 0 ]] \
    || fail "bluetooth widget smoke exited $bluetooth_smoke_rc"
  grep -q 'bluetooth widget smoke passed' <<<"$bluetooth_smoke_output" \
    || fail "bluetooth widget smoke did not reach its lifecycle marker"

  cp widgets/StatusWidget.qml widgets/TrayStatusView.qml \
    widgets/NotificationStatusView.qml widgets/TrayDrawerPanel.qml \
    "$smoke_root/widgets/"
  cp tests/fixtures/StatusTestWidget.qml "$smoke_root/fixtures/"
  cp tests/fixtures/TrayDrawerTestPanel.qml "$smoke_root/fixtures/"
  cp tests/fixtures/NotificationPanelTestView.qml "$smoke_root/fixtures/"
  cp tests/status-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  status_smoke_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  status_smoke_rc=$?
  set -e
  printf '%s\n' "$status_smoke_output"
  [[ $status_smoke_rc -eq 0 ]] \
    || fail "status widget smoke exited $status_smoke_rc"
  grep -q 'status widget smoke passed' <<<"$status_smoke_output" \
    || fail "status widget smoke did not reach its lifecycle marker"

  mkdir -p "$smoke_root/widgets/assets"
  cp hancore.shibumi.ai/BarWidget.qml \
    "$smoke_root/widgets/AiUsageWidget.qml"
  cp hancore.shibumi.ai/HostTokens.qml \
    hancore.shibumi.ai/IconText.qml \
    hancore.shibumi.ai/PillSurface.qml \
    hancore.shibumi.ai/TintedImage.qml "$smoke_root/widgets/"
  cp hancore.shibumi.ai/assets/codex.svg \
    hancore.shibumi.ai/assets/opencode-mark.svg \
    "$smoke_root/widgets/assets/"
  cp tests/fixtures/AiTestPanel.qml "$smoke_root/"
  cp tests/ai-usage-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  ai_usage_smoke_output=$(timeout 6 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  ai_usage_smoke_rc=$?
  set -e
  printf '%s\n' "$ai_usage_smoke_output"
  [[ $ai_usage_smoke_rc -eq 0 ]] \
    || fail "AI usage widget smoke exited $ai_usage_smoke_rc"
  grep -q 'ai usage widget smoke passed' <<<"$ai_usage_smoke_output" \
    || fail "AI usage widget smoke did not reach its lifecycle marker"

  cp widgets/MediaWidget.qml widgets/MediaPanel.qml widgets/MediaPulse.qml \
    widgets/MediaSpectrum.qml widgets/MediaMuse.qml widgets/CavaThemeModel.js \
    "$smoke_root/widgets/"
  cp tests/fixtures/MediaTestPanel.qml "$smoke_root/fixtures/"
  cp tests/media-widget-smoke.qml "$smoke_root/shell.qml"
  set +e
  media_smoke_output=$(timeout 7 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  media_smoke_rc=$?
  set -e
  printf '%s\n' "$media_smoke_output"
  [[ $media_smoke_rc -eq 0 ]] || fail "media widget smoke exited $media_smoke_rc"
  grep -q 'media widget smoke passed' <<<"$media_smoke_output" \
    || fail "media widget smoke did not reach its lifecycle marker"

  cp styles/shibumi/Style.qml styles/shibumi/VisualTokens.qml \
    styles/shibumi/BarSurface.qml styles/shibumi/TooltipSurface.qml \
    styles/shibumi/DragGhost.qml styles/shibumi/GroupSection.qml \
    styles/shibumi/RunChrome.qml styles/shibumi/GapEffectsLayer.qml \
    styles/shibumi/ReactorEventLayer.qml \
    "$smoke_root/styles/shibumi/"
  cp tests/shibumi-presentation-smoke.qml "$smoke_root/shell.qml"

  set +e
  presentation_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  presentation_rc=$?
  set -e
  printf '%s\n' "$presentation_output"
  [[ $presentation_rc -eq 0 ]] \
    || fail "Shibumi presentation smoke exited $presentation_rc"
  grep -q 'shibumi presentation smoke passed' <<<"$presentation_output" \
    || fail "Shibumi presentation smoke did not reach its marker"

  cp adapters/WorkspaceActions.qml "$smoke_root/adapters/"
  cp services/WorkspaceModel.js services/WorkspaceService.qml "$smoke_root/services/"
  cp widgets/WorkspaceWidget.qml widgets/PacmanWorkspaceMarker.qml \
    widgets/WorkspacePanel.qml \
    widgets/WorkspacePanelContent.qml widgets/ShibumiPanelToolTip.qml \
    "$smoke_root/widgets/"
  cp tests/fixtures/WorkspaceTestPanel.qml "$smoke_root/"
  cp tests/workspace-widget-smoke.qml "$smoke_root/shell.qml"

  set +e
  workspace_smoke_output=$(timeout 5 env \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="${OMARCHY_PATH}/shell${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}" \
    QML2_IMPORT_PATH="${OMARCHY_PATH}/shell${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}" \
    /usr/bin/quickshell -p "$smoke_root" 2>&1)
  workspace_smoke_rc=$?
  set -e
  printf '%s\n' "$workspace_smoke_output"
  [[ $workspace_smoke_rc -eq 0 ]] || fail "workspace widget smoke exited $workspace_smoke_rc"
  grep -q 'workspace widget smoke passed' <<<"$workspace_smoke_output" \
    || fail "workspace widget smoke did not reach its lifecycle marker"

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
