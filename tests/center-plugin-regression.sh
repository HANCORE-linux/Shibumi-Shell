#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/home/hancore/Projects/omarchy-updates-pr}
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-center.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'center plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.center" "$tmpdir/center"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/center-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/CenterTestCalendar.qml" \
  "$tmpdir/CenterTestCalendar.qml"
install -m 0644 "$repo_root/tests/fixtures/WeatherPanelTestView.qml" \
  "$tmpdir/WeatherPanelTestView.qml"

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
grep -F 'center plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

mkdir -p "$tmpdir/weather-runtime" "$tmpdir/weather-home" "$tmpdir/bin"
chmod 700 "$tmpdir/weather-runtime"
install -m 0755 "$repo_root/tests/fixtures/weather-curl" "$tmpdir/bin/curl"
install -m 0644 "$repo_root/tests/weather-service-start-smoke.qml" \
  "$tmpdir/shell.qml"

set +e
weather_output=$(timeout 8 env \
  HOME="$tmpdir/weather-home" \
  PATH="$tmpdir/bin:$PATH" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/weather-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
weather_rc=$?
set -e

printf '%s\n' "$weather_output"
[[ $weather_rc -eq 0 ]] || fail "weather start smoke exited $weather_rc"
grep -F 'weather service start smoke passed' <<<"$weather_output" >/dev/null \
  || fail "weather service did not load before interaction"

center_widget="$repo_root/hancore.shibumi.center/BarWidget.qml"
center_service="$repo_root/hancore.shibumi.center/Service.qml"
rg -q 'serviceFor\("hancore\.shibumi\.center"\)' "$center_widget" \
  || fail "center view does not resolve its shared service"
rg -q 'serviceFor\("hancore\.shibumi\.status"\)' "$center_widget" \
  || fail "center view does not resolve the shared status service"
if rg -q 'bar\.(clockService|weatherService|statusService)' \
    "$repo_root/hancore.shibumi.center"; then
  fail "center plugin depends on transitional bar-owned feature state"
fi
rg -q '^  ClockService \{ id: clockState \}$' "$center_service" \
  || fail "center service does not own one clock source"
rg -q '^  WeatherService \{' "$center_service" \
  || fail "center service does not own one weather source"
if rg -q 'StatusService|firstPartyServiceFor\("omarchy\.(idle|notifications)' \
    "$center_service"; then
  fail "center service duplicates the shared status owner"
fi
rg -q 'running: root\.enabled' \
  "$repo_root/hancore.shibumi.center/WeatherService.qml" \
  || fail "weather refresh is not service-lifecycle bounded"
if rg -q 'registered(Source|Component)\("omarchy\.weather"\)' "$center_widget"; then
  fail "center instantiates Quattro weather beside the Shibumi weather owner"
fi
rg -q 'WeatherPanel\.qml' "$repo_root/hancore.shibumi.center/WeatherWidget.qml" \
  || fail "weather facade does not lazy-load the V1 panel"
rg -q 'forecastDays' "$repo_root/hancore.shibumi.center/WeatherService.qml" \
  || fail "weather service does not own forecast state"
rg -q '\.local/state/omarchy/settings/weather\.json' \
  "$repo_root/hancore.shibumi.center/WeatherService.qml" \
  || fail "weather service ignores the Quattro location contract"
rg -q 'registered(Source|Component)\("omarchy\.system-update"\)' "$center_widget" \
  || fail "center does not retain the official update action owner"
if rg -U -q 'onLoaded: \{[^}]*root\.scheduleOfficialSync' "$center_widget"; then
  fail "loaded center children recursively reschedule their own loaders"
fi
calendar_panel="$repo_root/hancore.shibumi.center/CalendarPanel.qml"
rg -q 'component CalendarAction: Rectangle' "$calendar_panel" \
  || fail "calendar navigation does not own its V1 action appearance"
rg -q 'ShibumiPanelToolTip \{' "$calendar_panel" \
  || fail "calendar navigation bypasses the Shibumi tooltip"
if rg -q 'Ui\.PanelActionButton' "$calendar_panel"; then
  fail "calendar navigation still uses the host tooltip appearance"
fi

printf 'center plugin regression passed\n'
