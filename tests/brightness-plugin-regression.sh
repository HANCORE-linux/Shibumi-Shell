#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-brightness.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'brightness plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"
shibumi_stage_suite_runtime "$repo_root" "$tmpdir"
cp -a -- "$repo_root/hancore.shibumi.brightness" "$tmpdir/brightness"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/brightness-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/MonitorTestPanel.qml" \
  "$repo_root/tests/fixtures/MonitorTestView.qml" "$tmpdir/fixtures/"

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
[[ $rc -eq 0 ]] || fail "component smoke exited $rc"
grep -F 'brightness plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign|Internal error' \
    <<<"$output"; then
  fail "component smoke emitted a QML runtime error"
fi

widget="$repo_root/hancore.shibumi.brightness/BarWidget.qml"
service="$repo_root/hancore.shibumi.brightness/Service.qml"
panel="$repo_root/hancore.shibumi.brightness/BrightnessPanel.qml"
bridge="$repo_root/hancore.shibumi.brightness/MonitorPanelBridge.qml"
rg -q 'serviceFor\("hancore\.shibumi\.brightness"\)' "$widget" \
  || fail "brightness widget does not resolve the shared service"
if rg -q 'bar\.monitorService' "$repo_root/hancore.shibumi.brightness"; then
  fail "brightness plugin depends on transitional bar-owned monitor state"
fi
rg -Fq 'property var bar: Qt.isQtObject(shell) && "bar" in shell ? shell.bar : null' "$service" \
  || fail "monitor service does not guard the versioned active bar facade"
rg -q 'registeredComponent\("omarchy\.monitor"\)' "$service" \
  || fail "monitor service does not retain the official Omarchy owner"
rg -Fq 'property var barWidgetRegistry: null' "$service" \
  || fail "scoped monitor service cannot receive the accepted widget snapshot"
rg -Fq 'if (injectedEntry && injectedEntry.component) return injectedEntry.component' "$service" \
  || fail "scoped monitor service does not use the accepted native component"
rg -Fq 'if (scopedHost) return null' "$service" \
  || fail "scoped monitor service falls through to wider registry access"
rg -Fq '"barWidgetRegistry" in bar' "$service" \
  || fail "monitor service cannot resolve the official owner on stock Quattro"
[[ $(rg -c '^  MonitorPanelBridge \{' "$service") -eq 1 ]] \
  || fail "monitor service does not own exactly one official bridge"
if rg -Fq 'panel.bar = null' "$bridge"; then
  fail "monitor bridge clears the official panel host before destruction"
fi
rg -q 'readonly property color background: realBar && realBar\.background !== undefined' \
  "$bridge" \
  || fail "monitor host facade does not provide Quattro panel background color"
rg -q 'readonly property color barBackground: background' "$bridge" \
  || fail "monitor host facade does not provide the Quattro background alias"
rg -Fq 'ownerWidget: root' "$service" \
  || fail "scoped scalar bar state is still assigned to a visual Item property"
rg -Fq '? realBar.foreground : Commons.Color.foreground' "$bridge" \
  || fail "monitor host facade does not guard scoped missing foreground"
rg -Fq '? realBar.urgent : Commons.Color.urgent' "$bridge" \
  || fail "monitor host facade does not guard scoped missing urgent color"
rg -Fq '? realBar.shell : root.ownerShell' "$bridge" \
  || fail "monitor host facade does not retain the scoped shell fallback"
rg -Fq 'host.summon(ownId, "") === true' "$bridge" \
  || fail "scoped legacy IPC cannot summon the visible brightness widget"
rg -Fq 'function acquireVisualBar(holder, candidate)' "$service" \
  || fail "shared owner cannot acquire the active visual bar facade"
rg -Fq 'VisualBarLease {}' "$service" \
  || fail "visual bar registration is not holder-parented"
rg -Fq 'Commons.Util.wheelSteps(wheelAccumulator' "$widget" \
  || fail "brightness wheel does not accumulate high-resolution deltas"
rg -Fq 'if (!brightnessAvailable) return false' "$widget" \
  || fail "unavailable brightness still accumulates wheel deltas"
rg -Fq 'monitorService.showBrightnessOsd(monitorService.brightnessPercent)' "$widget" \
  || fail "effective brightness wheel changes do not forward native OSD"
rg -Fq 'function showBrightnessOsd(value)' "$bridge" \
  || fail "monitor bridge does not expose the native OSD action"
rg -Fq 'const leases = _visualBarLeases.slice()' "$service" \
  || fail "monitor service teardown does not retire external visual leases"
rg -Fq 'bridge.shutdown()' "$service" \
  || fail "monitor service does not drain its loaded backend before teardown"
rg -Fq 'function shutdown()' "$bridge" \
  || fail "monitor bridge has no explicit backend teardown path"
if rg -Fq 'Qt.callLater' "$bridge"; then
  fail "monitor bridge retains unowned delayed teardown callbacks"
fi
if rg -q 'Process \{|Quickshell\.Io|UPower' \
    "$widget" "$panel"; then
  fail "screen-local brightness presentation owns hardware work"
fi
rg -q '^  function refreshDisplayState\(\)' "$panel" \
  || fail "display panel does not expose its explicit refresh action"
rg -q 'onClicked: panel\.refreshDisplayState\(\)' "$panel" \
  || fail "display refresh button bypasses the tested action path"
if rg -q '^[[:space:]]+ShibumiSlider \{' "$panel"; then
  fail "V1 brightness still uses the thick legacy slider"
fi
[[ $(rg -c '^[[:space:]]+Ui\.PanelSlider \{' "$panel") -eq 2 ]] \
  || fail "V1/V2 Brightness and Text Size do not use Omarchy's PanelSlider geometry"
rg -Fq 'id: brightnessSlider' "$panel" \
  || fail "V1/V2 brightness does not share one thin slider"
brightness_slider_block=$(sed -n \
  '/^[[:space:]]*id: brightnessSlider$/,/^[[:space:]]*HoverHandler {/p' \
  "$panel")
[[ -n $brightness_slider_block ]] \
  || fail "brightness slider block could not be isolated"
if rg -q 'v1BrightnessSlider|v2BrightnessSlider' "$panel"; then
  fail "brightness slider remains unnecessarily split by shell variant"
fi
if rg -q 'v2BrightnessSegments' "$panel"; then
  fail "V2 brightness must remain a continuous, unsegmented slider"
fi
grep -Fq 'anchors.leftMargin: Commons.Style.space(6)' \
  <<<"$brightness_slider_block" \
  || fail "brightness slider does not preserve the Text Size left inset"
grep -Fq 'anchors.rightMargin: Commons.Style.space(6)' \
  <<<"$brightness_slider_block" \
  || fail "brightness slider does not preserve the Text Size right inset"
rg -Fq 'id: v2TextSizeSegments' "$panel" \
  || fail "V2 Text Size does not own an explicit segment layer"
rg -Fq 'visible: panel.shellStyle !== "shibumi"' "$panel" \
  || fail "V2 Text Size segments are not restricted to V2"
rg -Fq 'model: Math.max(0,' "$panel" \
  || fail "V2 Text Size segments do not follow the configured stop count"
rg -Fq 'height: textSizeSlider.trackHeight' "$panel" \
  || fail "V2 Text Size segments drifted from the V1 track height"
rg -Fq 'color: panel.controlActiveFillColor' "$panel" \
  || fail "V2 Text Size segment tracks do not use the themed active fill"
rg -Fq 'width: parent.width * Math.max(0, Math.min(1,' "$panel" \
  || fail "V2 Text Size segment fill does not follow the live slider value"
rg -Fq 'tickCount: panel.shellStyle === "shibumi"' "$panel" \
  || fail "V1 Text Size notches are not isolated from V2 segmentation"
rg -Fq 'id: textSizeRow' "$panel" \
  || fail "Text Size does not expose Omarchy's slider row"
rg -Fq 'height: textSizeSlider.implicitHeight' "$panel" \
  || fail "Text Size row does not use Omarchy's implicit slider height"
rg -Fq '+ Commons.Style.spacing.controlGap' "$panel" \
  || fail "Text Size row does not use Omarchy's control gap"
rg -Fq 'outline: true' "$panel" \
  || fail "Text Size row does not use Omarchy's cursor outline"
rg -Fq 'accent: panel.controlAccent' "$panel" \
  || fail "Text Size row cursor does not follow the Shibumi theme"
for colorBinding in \
  'knobColor: panel.controlAccent' \
  'tickColor: panel.renderedSurfaceColor'; do
  rg -Fq "$colorBinding" "$panel" \
    || fail "Text Size slider is not bound to the Shibumi theme: $colorBinding"
done
rg -Fq 'readonly property string displayGlyph: Quickshell.screens.length > 1' \
  "$widget" || fail "desktop display glyph does not follow the Omarchy screen-count source"
rg -Fq '&& hasInternalDisplay(monitorService.displays)' "$widget" \
  || fail "brightness presentation does not distinguish laptop and desktop displays"
rg -Fq '/^(eDP|LVDS|DSI)-/' "$widget" \
  || fail "internal display detection drifted from Omarchy's monitor source"
rg -Fq ': root.internalDisplay' "$widget" \
  || fail "desktop Display glyph is not selected from internal display availability"
rg -Fq '? "󰍺" : "󰍹"' "$widget" \
  || fail "desktop display glyphs drifted from the Omarchy Display widget"
rg -Fq 'text: "TEXT SIZE"' "$panel" \
  || fail "display panel does not expose Omarchy Text Size"
rg -Fq 'panel.monitorService.setTextSize(' "$panel" \
  || fail "Text Size slider does not forward its selected stop"
rg -Fq 'function setTextSize(value) { return bridge.setTextSize(value) }' \
  "$service" || fail "monitor service does not forward Text Size"
rg -Fq 'typeof panel.setTextSize === "function"' "$bridge" \
  || fail "monitor bridge does not feature-detect Omarchy Text Size"
for token in controlFillColor controlHoverFillColor controlActiveFillColor \
  controlBorderColor controlHoverBorderColor controlAccent; do
  rg -q "panel\.${token}" "$panel" \
    || fail "brightness controls bypass the shared V1 token: $token"
done
if rg -q 'component (PanelButton|ScaleButton|DisplayRow): Ui\.CursorSurface' \
    "$panel"; then
  fail "brightness action and selection groups still use host control chrome"
fi

printf 'brightness plugin regression passed\n'
