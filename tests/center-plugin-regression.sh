#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-center.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'center plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

forecast_fixture="$repo_root/tests/fixtures/weather-curl"
geocode_fixture="$repo_root/tests/fixtures/weather-geocode-curl"
if bash "$forecast_fixture" --header 'X-Test: --max-filesize 131072' \
    'https://wttr.in/?format=j1' >/dev/null 2>&1 \
    || bash "$forecast_fixture" -fsS --max-time 5 --max-filesize 1 \
      'https://wttr.in/?format=j1' >/dev/null 2>&1 \
    || bash "$forecast_fixture" -fsS --max-time 5 --max-filesize \
      'https://wttr.in/?format=j1' >/dev/null 2>&1 \
    || bash "$forecast_fixture" -fsS --max-time 5 --max-filesize 131072 \
      'https://wttr.in/?format=j1' 'https://example.invalid/' >/dev/null 2>&1; then
  fail "weather forecast fixture accepted an inexact argument vector"
fi
if bash "$geocode_fixture" --header 'X-Test: --max-filesize 65536' \
    'https://geocoding-api.open-meteo.com/v1/search?language=de' >/dev/null 2>&1 \
    || bash "$geocode_fixture" -fsS --max-time 5 --max-filesize 1 \
      'https://geocoding-api.open-meteo.com/v1/search?language=de' >/dev/null 2>&1 \
    || bash "$geocode_fixture" -fsS --max-time 5 --max-filesize \
      'https://geocoding-api.open-meteo.com/v1/search?language=de' >/dev/null 2>&1 \
    || bash "$geocode_fixture" -fsS --max-time 5 --max-filesize 65536 \
      'https://geocoding-api.open-meteo.com/v1/search?language=de' \
      'https://example.invalid/' >/dev/null 2>&1; then
  fail "weather geocode fixture accepted an inexact argument vector"
fi

python3 "$repo_root/tests/weather-location-regression.py"
python3 "$repo_root/tests/weather-report-regression.py"
python3 "$repo_root/tests/weather-panel-control-regression.py" --host-shell "$omarchy_path/shell"

mkdir -p "$tmpdir/runtime"
chmod 700 "$tmpdir/runtime"
shibumi_stage_suite_runtime "$repo_root" "$tmpdir"
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

install -m 0644 "$repo_root/tests/weather-service-failure-smoke.qml" \
  "$tmpdir/shell.qml"
set +e
weather_failure_output=$(timeout 8 env \
  HOME="$tmpdir/weather-home" \
  PATH="$tmpdir/bin:$PATH" \
  SHIBUMI_WEATHER_CURL_EXIT=63 \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/weather-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
weather_failure_rc=$?
set -e

printf '%s\n' "$weather_failure_output"
[[ $weather_failure_rc -eq 0 ]] \
  || fail "weather failed-transfer smoke exited $weather_failure_rc"
grep -F 'weather failed transfer stayed unpublished' \
  <<<"$weather_failure_output" >/dev/null \
  || fail "failed weather transfer published its output"

mkdir -p "$tmpdir/teardown-runtime" "$tmpdir/teardown-bin"
chmod 700 "$tmpdir/teardown-runtime"
install -m 0755 "$repo_root/tests/fixtures/weather-curl" \
  "$tmpdir/teardown-bin/weather-curl"
cat >"$tmpdir/teardown-bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'call\n' >>"$WEATHER_CURL_LOG"
sleep 0.2
exec "$(dirname -- "$0")/weather-curl" "$@"
EOF
chmod 0755 "$tmpdir/teardown-bin/curl"
install -m 0644 "$repo_root/tests/weather-service-teardown-smoke.qml" \
  "$tmpdir/shell.qml"
set +e
weather_teardown_output=$(timeout 8 env \
  HOME="$tmpdir/weather-home" \
  PATH="$tmpdir/teardown-bin:$PATH" \
  WEATHER_CURL_LOG="$tmpdir/teardown-curl.log" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/teardown-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
weather_teardown_rc=$?
set -e

printf '%s\n' "$weather_teardown_output"
[[ $weather_teardown_rc -eq 0 ]] \
  || fail "weather teardown smoke exited $weather_teardown_rc"
grep -F 'weather pending refresh teardown passed' \
  <<<"$weather_teardown_output" >/dev/null \
  || fail "weather teardown success marker is missing"
if grep -Eq 'Internal error|TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$weather_teardown_output"; then
  fail "weather teardown produced a QML lifecycle warning"
fi
[[ -f $tmpdir/teardown-curl.log ]] \
  || fail "weather teardown fixture was not called"
[[ $(wc -l <"$tmpdir/teardown-curl.log") -eq 1 ]] \
  || fail "destroyed weather service started a pending refresh"

mkdir -p "$tmpdir/location-runtime"
chmod 700 "$tmpdir/location-runtime"
install -m 0644 "$repo_root/tests/fixtures/ShibumiPanelTest.qml" \
  "$tmpdir/center/ShibumiPanel.qml"
install -m 0755 "$repo_root/tests/fixtures/weather-geocode-curl" \
  "$tmpdir/bin/curl"
install -m 0755 "$repo_root/tests/fixtures/weather-location-helper" \
  "$tmpdir/bin/omarchy-weather-location"
install -m 0644 "$repo_root/tests/weather-panel-location-smoke.qml" \
  "$tmpdir/shell.qml"

set +e
location_output=$(timeout 8 env \
  HOME="$tmpdir/weather-home" \
  PATH="$tmpdir/bin:$PATH" \
  WEATHER_LOCATION_LOG="$tmpdir/location.log" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/location-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
location_rc=$?
set -e

printf '%s\n' "$location_output"
[[ $location_rc -eq 0 ]] || fail "weather location smoke exited $location_rc"
grep -F 'weather panel location smoke passed' <<<"$location_output" >/dev/null \
  || fail "weather location success marker missing"
if grep -Eq 'weather-panel-location-smoke:|TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$location_output"; then
  fail "weather location QML runtime error detected"
fi
[[ -f $tmpdir/location.log ]] || fail "weather location helper was not called"
grep -Fx -- '--set|Berlin|52.52,13.405' "$tmpdir/location.log" >/dev/null \
  || fail "manual weather coordinates were not persisted"
grep -Fx -- '--clear' "$tmpdir/location.log" >/dev/null \
  || fail "automatic weather location was not restored"
[[ $(wc -l <"$tmpdir/location.log") -eq 2 ]] \
  || fail "unexpected weather location helper calls"

center_widget="$repo_root/hancore.shibumi.center/BarWidget.qml"
center_service="$repo_root/hancore.shibumi.center/Service.qml"
weather_panel="$repo_root/hancore.shibumi.center/WeatherPanel.qml"
rg -U -q 'Presentation\.PillSurface \{\n([^\n]*\n)*[[:space:]]*anchors\.verticalCenter: parent\.verticalCenter\n[[:space:]]*height: root\.tokens \? root\.tokens\.pillHeight : 0' \
  "$center_widget" \
  || fail "G8 pill does not retain the exact shared pill height"
if rg -q 'anchors\.(top|bottom)Margin:.*pillHeight' "$center_widget"; then
  fail "G8 pill height still depends on independently rounded margins"
fi
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
for location_contract in \
  'WeatherLocationModel.parseGeocodingResults' \
  'geocoding-api.open-meteo.com/v1/search' \
  '["omarchy-weather-location", "--set"' \
  '["omarchy-weather-location", "--clear"]' \
  'blocked: panel.editingLocation' \
  'enabled: panel.locationCanCommit' \
  'locationError = "No matching location"' \
  'readonly property string geocodeLanguage: "de"' \
  'id: locationHoverSurface' \
  'width: parent.width + 8' \
  'background: Rectangle {' \
  'radius: panel.controlRadius'; do
  rg -Fq "$location_contract" "$weather_panel" \
    || fail "weather location contract missing: $location_contract"
done
rg -q 'registered(Source|Component)\("omarchy\.system-update"\)' "$center_widget" \
  || fail "center does not retain the official update action owner"
if rg -U -q 'onLoaded: \{[^}]*root\.scheduleOfficialSync' "$center_widget"; then
  fail "loaded center children recursively reschedule their own loaders"
fi
calendar_panel="$repo_root/hancore.shibumi.center/CalendarPanel.qml"
rg -q 'component CalendarAction: Rectangle' "$calendar_panel" \
  || fail "calendar navigation does not own its V1 action appearance"
rg -q 'Presentation\.ShibumiPillToolTip \{' "$calendar_panel" \
  || fail "calendar navigation bypasses the Shibumi tooltip"
if rg -q 'Ui\.PanelActionButton' "$calendar_panel"; then
  fail "calendar navigation still uses the host tooltip appearance"
fi

printf 'center plugin regression passed\n'
