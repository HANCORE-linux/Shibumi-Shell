#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-power-plugins.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'power plugins regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.battery" "$tmpdir/battery"
cp -a -- "$repo_root/hancore.shibumi.power-profile" "$tmpdir/powerProfile"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/fixtures/ShibumiPanelTest.qml" \
  "$tmpdir/powerProfile/ShibumiPanel.qml"
install -m 0644 "$repo_root/tests/power-plugins-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/PowerTestService.qml" \
  "$repo_root/tests/fixtures/PowerTestPanel.qml" "$tmpdir/fixtures/"

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
grep -F 'power plugins smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

for plugin in battery power-profile; do
  widget="$repo_root/hancore.shibumi.$plugin/BarWidget.qml"
  rg -q 'serviceFor\("hancore\.shibumi\.power-state"\)' "$widget" \
    || fail "$plugin does not resolve the shared power-state service"
  if rg -q 'bar\.(powerService|systemActions)' \
      "$repo_root/hancore.shibumi.$plugin" --glob '*.qml'; then
    fail "$plugin consumes transitional bar-owned feature state"
  fi
  if rg -q 'Quickshell\.Services\.UPower|UPower\.|Process \{|Timer \{|FileView \{' \
      "$repo_root/hancore.shibumi.$plugin" --glob '*.qml' \
      --glob '!ShibumiPanel.qml'; then
    fail "$plugin presentation owns hardware state or background work"
  fi
done

rg -q 'bar\.run\("omarchy-launch-or-focus-tui btop"\)' \
  "$repo_root/hancore.shibumi.battery/BarWidget.qml" \
  || fail "battery system-monitor action bypasses the host facade"
rg -q 'panel\.powerService\.profileLabel\(profileRow\.modelData\)' \
  "$repo_root/hancore.shibumi.power-profile/PowerProfilePanel.qml" \
  || fail "power-profile view duplicates the shared profile model"
for glyph in '\uF06C' '\uF24E' '\uF0E7'; do
  rg -Fq "$glyph" "$repo_root/hancore.shibumi.power-profile/PowerProfilePanel.qml" \
    || fail "power-profile panel icon drifted from V1: $glyph"
done
if rg -Fq 'rotation: -90' "$repo_root/hancore.shibumi.battery/BarWidget.qml"; then
  fail "battery bar gauge drifted from the horizontal V1 presentation"
fi
for charging_contract in \
    'id: chargingBolt' \
    'ctx.lineTo(width * 0.88, height * 0.45)' \
    'visible: gauge.charging && !gauge.full' \
    'clip: true'; do
  rg -Fq "$charging_contract" "$repo_root/hancore.shibumi.battery/BarWidget.qml" \
    || fail "battery charging presentation drifted from V1: $charging_contract"
done
if rg -A8 -F 'NumberAnimation on pos' \
    "$repo_root/hancore.shibumi.battery/BarWidget.qml" | rg -Fq 'Animation.Infinite'; then
  fail "battery charging shimmer keeps the scene graph permanently active"
fi
rg -q 'function profileLabel\(profile\)' \
  "$repo_root/hancore.shibumi.power-state/Service.qml" \
  || fail "power-state service does not expose profile labels"
rg -Fq 'command: ["busctl", "--system", "get-property",' \
  "$repo_root/hancore.shibumi.power-state/Service.qml" \
  || fail "power-state service does not use the lightweight active-profile probe"
rg -Fq 'onTriggered: root.refreshActiveProfile()' \
  "$repo_root/hancore.shibumi.power-state/Service.qml" \
  || fail "power-state hot path still refreshes the complete profile list"
rg -q 'readonly property string batteryId:' \
  "$repo_root/hancore.shibumi.power-state/Service.qml" \
  || fail "power-state service does not expose the physical battery id"
rg -Fq 'String(batteryInfo.time || "")' \
  "$repo_root/hancore.shibumi.power-state/Service.qml" \
  || fail "power-state service does not retain the Omarchy battery-life fallback"
rg -Fq "printf 'health\\\\t%s\\\\n'" \
  "$repo_root/hancore.shibumi.power-state/Service.qml" \
  || fail "power-state service does not retain the V1 sysfs health fallback"
rg -q 'panel\.powerService\.batteryHealthText' \
  "$repo_root/hancore.shibumi.battery/BatteryPanel.qml" \
  || fail "battery panel does not render the shared health fallback"
rg -q 'width: parent \? parent\.width : 0' \
  "$repo_root/hancore.shibumi.battery/BatteryPanel.qml" \
  || fail "battery information rows can collapse to zero width"

printf 'power plugins regression passed\n'
