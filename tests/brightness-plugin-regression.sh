#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/home/hancore/Projects/omarchy-updates-pr}
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

widget="$repo_root/hancore.shibumi.brightness/BarWidget.qml"
service="$repo_root/hancore.shibumi.brightness/Service.qml"
panel="$repo_root/hancore.shibumi.brightness/BrightnessPanel.qml"
bridge="$repo_root/hancore.shibumi.brightness/MonitorPanelBridge.qml"
rg -q 'serviceFor\("hancore\.shibumi\.brightness"\)' "$widget" \
  || fail "brightness widget does not resolve the shared service"
if rg -q 'bar\.monitorService' "$repo_root/hancore.shibumi.brightness"; then
  fail "brightness plugin depends on transitional bar-owned monitor state"
fi
rg -q 'property var bar: shell \? shell\.bar : null' "$service" \
  || fail "monitor service does not use the versioned active bar facade"
rg -q 'registeredComponent\("omarchy\.monitor"\)' "$service" \
  || fail "monitor service does not retain the official Omarchy owner"
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
if rg -q 'Process \{|Quickshell\.Io|UPower' \
    "$widget" "$panel"; then
  fail "screen-local brightness presentation owns hardware work"
fi
rg -q '^  function refreshDisplayState\(\)' "$panel" \
  || fail "display panel does not expose its explicit refresh action"
rg -q 'onClicked: panel\.refreshDisplayState\(\)' "$panel" \
  || fail "display refresh button bypasses the tested action path"
[[ $(rg -c '^[[:space:]]+ShibumiSlider \{' "$panel") -eq 1 ]] \
  || fail "brightness control does not use the Shibumi slider"
[[ $(rg -c '^[[:space:]]+Ui\.PanelSlider \{' "$panel") -eq 1 ]] \
  || fail "Text Size does not use Omarchy's exact PanelSlider"
rg -Fq 'tickCount: panel.monitorService.textSizeStops.length' "$panel" \
  || fail "Text Size does not expose Omarchy's curated slider notches"
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
  'trackColor: panel.controlActiveFillColor' \
  'fillColor: panel.controlAccent' \
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
