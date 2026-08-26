#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-network.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'network plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"
command -v zbarimg >/dev/null 2>&1 \
  || fail "zbarimg is required for exact Wi-Fi QR decode gates"
command -v magick >/dev/null 2>&1 \
  || fail "ImageMagick is required for Wi-Fi QR render gates"
python3 -c 'import dbus' >/dev/null 2>&1 \
  || fail "python-dbus is required for Enterprise source gates"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures" "$tmpdir/bin"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.network" "$tmpdir/network"
cp -a -- "$repo_root/hancore.shibumi.network" \
  "$tmpdir/hancore.shibumi.network"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/network-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/NetworkTestService.qml" \
  "$repo_root/tests/fixtures/NetworkTestView.qml" "$tmpdir/fixtures/"
install -m 0755 \
  "$repo_root/tests/fixtures/network-profile-catalog-fixture.py" \
  "$repo_root/tests/fixtures/network-telemetry-fixture.py" \
  "$repo_root/tests/fixtures/network-reachability-fixture.py" \
  "$repo_root/tests/fixtures/network-speed-test-fixture.py" \
  "$repo_root/tests/fixtures/network-enterprise-fixture.py" \
  "$repo_root/tests/fixtures/network-profile-action-fixture.py" \
  "$repo_root/tests/fixtures/network-qr-secret-fixture.py" \
  "$tmpdir/fixtures/"

set +e
output=$(timeout 12 env \
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
grep -F 'network plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

install -m 0644 "$repo_root/tests/network-native-panel-smoke.qml" \
  "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/ShibumiPanelTest.qml" \
  "$tmpdir/network/ShibumiPanel.qml"
mkdir -p "$tmpdir/panel-runtime"
chmod 700 "$tmpdir/panel-runtime"
set +e
panel_output=$(timeout 12 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/panel-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
panel_rc=$?
set -e
printf '%s\n' "$panel_output"
[[ $panel_rc -eq 0 ]] || fail "native Network panel smoke exited $panel_rc"
grep -F 'network native panel smoke passed' <<<"$panel_output" >/dev/null \
  || fail "native Network panel success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$panel_output"; then
  fail "native Network panel produced a QML runtime error"
fi

install -m 0644 \
  "$repo_root/tests/network-service-recovery-barrier-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/recovery-barrier-runtime"
chmod 700 "$tmpdir/recovery-barrier-runtime"
set +e
recovery_barrier_output=$(timeout 12 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/recovery-barrier-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
recovery_barrier_rc=$?
set -e
printf '%s\n' "$recovery_barrier_output"
[[ $recovery_barrier_rc -eq 0 ]] \
  || fail "network recovery barrier smoke exited $recovery_barrier_rc"
grep -F 'network service recovery barrier regression passed' \
  <<<"$recovery_barrier_output" >/dev/null \
  || fail "network recovery barrier success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$recovery_barrier_output"; then
  fail "network recovery barrier produced a QML runtime error"
fi

install -m 0644 "$repo_root/tests/network-native-backend-seam-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/native-runtime" "$tmpdir/native-home"
chmod 700 "$tmpdir/native-runtime"
set +e
native_output=$(timeout 12 env \
  HOME="$tmpdir/native-home" \
  DBUS_SYSTEM_BUS_ADDRESS="unix:path=$tmpdir/missing-system-bus" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/native-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
native_rc=$?
set -e
printf '%s\n' "$native_output"
[[ $native_rc -eq 0 ]] \
  || fail "network native backend seam smoke exited $native_rc"
grep -F 'network native backend seam regression passed' \
  <<<"$native_output" >/dev/null \
  || fail "network native backend seam success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$native_output"; then
  fail "native seam produced a QML runtime error"
fi

"$repo_root/tests/network-manager-owner-watch-regression.py" \
  || fail "NetworkManager owner watcher regression failed"

install -m 0644 \
  "$repo_root/tests/network-manager-liveness-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/liveness-runtime" "$tmpdir/liveness-home"
chmod 700 "$tmpdir/liveness-runtime"
set +e
liveness_output=$(timeout 12 env \
  HOME="$tmpdir/liveness-home" \
  DBUS_SYSTEM_BUS_ADDRESS="unix:path=$tmpdir/missing-liveness-system-bus" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/liveness-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
liveness_rc=$?
set -e
printf '%s\n' "$liveness_output"
[[ $liveness_rc -eq 0 ]] \
  || fail "NetworkManager liveness smoke exited $liveness_rc"
grep -F 'network manager liveness regression passed' \
  <<<"$liveness_output" >/dev/null \
  || fail "NetworkManager liveness success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$liveness_output"; then
  fail "NetworkManager liveness seam produced a QML runtime error"
fi

install -m 0644 \
  "$repo_root/tests/network-manager-liveness-reload-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/liveness-reload-runtime"
chmod 700 "$tmpdir/liveness-reload-runtime"
set +e
liveness_reload_output=$(timeout 15 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/liveness-reload-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
liveness_reload_rc=$?
set -e
printf '%s\n' "$liveness_reload_output"
[[ $liveness_reload_rc -eq 0 ]] \
  || fail "NetworkManager soft-reload smoke exited $liveness_reload_rc"
grep -F 'network manager liveness reload regression passed' \
  <<<"$liveness_reload_output" >/dev/null \
  || fail "NetworkManager soft-reload success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$liveness_reload_output"; then
  fail "NetworkManager soft-reload seam produced a QML runtime error"
fi

"$repo_root/tests/network-profile-catalog-helper-regression.py" \
  || fail "saved-profile helper regression failed"
install -m 0644 \
  "$repo_root/tests/network-profile-catalog-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/profile-catalog-runtime"
chmod 700 "$tmpdir/profile-catalog-runtime"
set +e
profile_catalog_output=$(timeout 15 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/profile-catalog-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
profile_catalog_rc=$?
set -e
printf '%s\n' "$profile_catalog_output"
[[ $profile_catalog_rc -eq 0 ]] \
  || fail "saved-profile catalog smoke exited $profile_catalog_rc"
grep -F 'network profile catalog regression passed' \
  <<<"$profile_catalog_output" >/dev/null \
  || fail "saved-profile catalog success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$profile_catalog_output"; then
  fail "saved-profile catalog produced a QML runtime error"
fi

install -m 0644 \
  "$repo_root/tests/network-profile-catalog-destruction-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/profile-catalog-destruction-runtime"
chmod 700 "$tmpdir/profile-catalog-destruction-runtime"
set +e
profile_catalog_destruction_output=$(timeout 10 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/profile-catalog-destruction-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
profile_catalog_destruction_rc=$?
set -e
printf '%s\n' "$profile_catalog_destruction_output"
[[ $profile_catalog_destruction_rc -eq 0 ]] \
  || fail "saved-profile catalog destruction smoke exited $profile_catalog_destruction_rc"
grep -F 'network profile catalog destruction regression passed' \
  <<<"$profile_catalog_destruction_output" >/dev/null \
  || fail "saved-profile catalog destruction marker missing"
profile_catalog_resistant_pid_file="$tmpdir/fixtures/network-profile-catalog-resistant.pid"
[[ -s $profile_catalog_resistant_pid_file ]] \
  || fail "saved-profile resistant worker recorded no PID"
profile_catalog_resistant_pid=$(<"$profile_catalog_resistant_pid_file")
for _ in {1..100}; do
  kill -0 "$profile_catalog_resistant_pid" 2>/dev/null || break
  sleep 0.02
done
kill -0 "$profile_catalog_resistant_pid" 2>/dev/null \
  && fail "saved-profile catalog left a resistant worker alive"

"$repo_root/tests/network-telemetry-helper-regression.py" \
  || fail "network telemetry helper regression failed"
install -m 0644 \
  "$repo_root/tests/network-telemetry-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/telemetry-runtime"
chmod 700 "$tmpdir/telemetry-runtime"
set +e
telemetry_output=$(timeout 15 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/telemetry-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
telemetry_rc=$?
set -e
printf '%s\n' "$telemetry_output"
[[ $telemetry_rc -eq 0 ]] \
  || fail "network telemetry smoke exited $telemetry_rc"
grep -F 'network telemetry regression passed' \
  <<<"$telemetry_output" >/dev/null \
  || fail "network telemetry success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$telemetry_output"; then
  fail "network telemetry produced a QML runtime error"
fi

for telemetry_case in destruction start-failure rate-boundary deferred-launch; do
  install -m 0644 \
    "$repo_root/tests/network-telemetry-${telemetry_case}-regression.qml" \
    "$tmpdir/shell.qml"
  mkdir -p "$tmpdir/telemetry-${telemetry_case}-runtime"
  chmod 700 "$tmpdir/telemetry-${telemetry_case}-runtime"
  set +e
  telemetry_case_output=$(timeout 15 env \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$tmpdir/telemetry-${telemetry_case}-runtime" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$tmpdir" 2>&1)
  telemetry_case_rc=$?
  set -e
  printf '%s\n' "$telemetry_case_output"
  [[ $telemetry_case_rc -eq 0 ]] \
    || fail "network telemetry $telemetry_case smoke exited $telemetry_case_rc"
  telemetry_case_marker="network telemetry ${telemetry_case//-/ } regression passed"
  grep -F "$telemetry_case_marker" <<<"$telemetry_case_output" >/dev/null \
    || fail "network telemetry $telemetry_case success marker missing"
  if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
      <<<"$telemetry_case_output"; then
    fail "network telemetry $telemetry_case produced a QML runtime error"
  fi
done

"$repo_root/tests/network-reachability-helper-regression.py" \
  || fail "network reachability helper regression failed"
for reachability_case in main model lifecycle destruction prestart stream route-race; do
  reachability_test="$repo_root/tests/network-reachability-regression.qml"
  if [[ $reachability_case != main ]]; then
    reachability_test="$repo_root/tests/network-reachability-${reachability_case}-regression.qml"
  fi
  install -m 0644 "$reachability_test" "$tmpdir/shell.qml"
  mkdir -p "$tmpdir/reachability-${reachability_case}-runtime"
  chmod 700 "$tmpdir/reachability-${reachability_case}-runtime"
  set +e
  reachability_output=$(timeout 15 env \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$tmpdir/reachability-${reachability_case}-runtime" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$tmpdir" 2>&1)
  reachability_rc=$?
  set -e
  printf '%s\n' "$reachability_output"
  [[ $reachability_rc -eq 0 ]] \
    || fail "network reachability $reachability_case smoke exited $reachability_rc"
  reachability_marker="network reachability regression passed"
  if [[ $reachability_case != main ]]; then
    reachability_marker="network reachability ${reachability_case//-/ } regression passed"
  fi
  grep -F "$reachability_marker" <<<"$reachability_output" >/dev/null \
    || fail "network reachability $reachability_case success marker missing"
  if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
      <<<"$reachability_output"; then
    fail "network reachability $reachability_case produced a QML runtime error"
  fi
  reachability_pid_file=""
  if [[ $reachability_case == lifecycle ]]; then
    reachability_pid_file="$tmpdir/fixtures/network-reachability-slow-invocations.pid"
  elif [[ $reachability_case == destruction ]]; then
    reachability_pid_file="$tmpdir/fixtures/network-reachability-destruction-invocations.pid"
  elif [[ $reachability_case == stream ]]; then
    reachability_pid_file="$tmpdir/fixtures/network-reachability-stream-invocations.pid"
  elif [[ $reachability_case == route-race ]]; then
    reachability_pid_file="$tmpdir/fixtures/network-reachability-route-race-invocations.pid"
  fi
  if [[ -n $reachability_pid_file ]]; then
    [[ -s $reachability_pid_file ]] \
      || fail "network reachability $reachability_case fixture recorded no PID"
    reachability_pid=$(<"$reachability_pid_file")
    for _ in {1..50}; do
      kill -0 "$reachability_pid" 2>/dev/null || break
      sleep 0.02
    done
    kill -0 "$reachability_pid" 2>/dev/null \
      && fail "network reachability $reachability_case left process $reachability_pid alive"
  fi
done

"$repo_root/tests/network-speed-test-helper-regression.py" \
  || fail "network speed-test helper regression failed"
for speed_case in main model failure destruction transition; do
  speed_test="$repo_root/tests/network-speed-test-regression.qml"
  if [[ $speed_case != main ]]; then
    speed_test="$repo_root/tests/network-speed-test-${speed_case}-regression.qml"
  fi
  install -m 0644 "$speed_test" "$tmpdir/shell.qml"
  mkdir -p "$tmpdir/speed-${speed_case}-runtime"
  chmod 700 "$tmpdir/speed-${speed_case}-runtime"
  set +e
  speed_output=$(timeout 18 env \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$tmpdir/speed-${speed_case}-runtime" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$tmpdir" 2>&1)
  speed_rc=$?
  set -e
  printf '%s\n' "$speed_output"
  [[ $speed_rc -eq 0 ]] \
    || fail "network speed-test $speed_case smoke exited $speed_rc"
  speed_marker="network speed-test regression passed"
  if [[ $speed_case != main ]]; then
    speed_marker="network speed-test ${speed_case//-/ } regression passed"
  fi
  grep -F "$speed_marker" <<<"$speed_output" >/dev/null \
    || fail "network speed-test $speed_case success marker missing"
  if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
      <<<"$speed_output"; then
    fail "network speed-test $speed_case produced a QML runtime error"
  fi
  speed_pid_file=""
  if [[ $speed_case == failure ]]; then
    speed_pid_file="$tmpdir/fixtures/network-speed-test-failure-invocations.pid"
  elif [[ $speed_case == destruction ]]; then
    speed_pid_file="$tmpdir/fixtures/network-speed-test-destruction-invocations.pid"
  fi
  if [[ -n $speed_pid_file ]]; then
    [[ -s $speed_pid_file ]] \
      || fail "network speed-test $speed_case fixture recorded no PID"
    speed_pid=$(<"$speed_pid_file")
    for _ in {1..100}; do
      kill -0 "$speed_pid" 2>/dev/null || break
      sleep 0.02
    done
    kill -0 "$speed_pid" 2>/dev/null \
      && fail "network speed-test $speed_case left process $speed_pid alive"
  fi
  if [[ $speed_case == failure ]]; then
    speed_flood_pid_file="$tmpdir/fixtures/network-speed-test-failure-invocations.flood.pid"
    [[ -s $speed_flood_pid_file ]] \
      || fail "network speed-test stdout flood fixture recorded no PID"
    speed_flood_pid=$(<"$speed_flood_pid_file")
    for _ in {1..100}; do
      kill -0 "$speed_flood_pid" 2>/dev/null || break
      sleep 0.02
    done
    kill -0 "$speed_flood_pid" 2>/dev/null \
      && fail "network speed-test stdout flood left process $speed_flood_pid alive"
  fi
done

"$repo_root/tests/network-enterprise-helper-regression.py" \
  || fail "network Enterprise helper regression failed"
for enterprise_case in model adapter dispatcher destruction; do
  enterprise_test="$repo_root/tests/network-enterprise-${enterprise_case}-regression.qml"
  install -m 0644 "$enterprise_test" "$tmpdir/shell.qml"
  mkdir -p "$tmpdir/enterprise-${enterprise_case}-runtime"
  chmod 700 "$tmpdir/enterprise-${enterprise_case}-runtime"
  set +e
  enterprise_output=$(timeout 18 env \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$tmpdir/enterprise-${enterprise_case}-runtime" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$tmpdir" 2>&1)
  enterprise_rc=$?
  set -e
  printf '%s\n' "$enterprise_output"
  [[ $enterprise_rc -eq 0 ]] \
    || fail "network Enterprise $enterprise_case smoke exited $enterprise_rc"
  enterprise_marker="network enterprise ${enterprise_case//-/ } regression passed"
  grep -F "$enterprise_marker" <<<"$enterprise_output" >/dev/null \
    || fail "network Enterprise $enterprise_case success marker missing"
  if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
      <<<"$enterprise_output"; then
    fail "network Enterprise $enterprise_case produced a QML runtime error"
  fi
  if [[ $enterprise_case == dispatcher ]]; then
    enterprise_capture="$tmpdir/fixtures/network-enterprise-capture.json"
    [[ -s $enterprise_capture ]] \
      || fail "network Enterprise dispatcher fixture captured no request"
    jq -e '
      .hasIdentity == true and .hasPassword == true and
      .method == "peap-mschapv2" and
      (has("identity") | not) and (has("password") | not) and
      (has("serverDomain") | not)
    ' "$enterprise_capture" >/dev/null \
      || fail "network Enterprise fixture persisted credential values"
  elif [[ $enterprise_case == destruction ]]; then
    enterprise_pid_file="$tmpdir/fixtures/network-enterprise-destruction.pid"
    [[ -s $enterprise_pid_file ]] \
      || fail "network Enterprise destruction fixture recorded no PID"
    enterprise_pid=$(<"$enterprise_pid_file")
    for _ in {1..100}; do
      kill -0 "$enterprise_pid" 2>/dev/null || break
      sleep 0.02
    done
    kill -0 "$enterprise_pid" 2>/dev/null \
      && fail "network Enterprise destruction left process $enterprise_pid alive"
  fi
done

python3 "$repo_root/tests/network-qr-encoder-regression.py"
python3 "$repo_root/tests/network-qr-secret-helper-regression.py"
install -m 0644 "$repo_root/tests/network-qr-secret-dispatcher-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/qr-secret-runtime"
chmod 700 "$tmpdir/qr-secret-runtime"
set +e
qr_secret_output=$(timeout 20 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/qr-secret-runtime" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
qr_secret_rc=$?
set -e
printf '%s\n' "$qr_secret_output"
[[ $qr_secret_rc -eq 0 ]] || fail "network QR secret dispatcher exited $qr_secret_rc"
grep -F 'network QR secret dispatcher regression passed' \
  <<<"$qr_secret_output" >/dev/null \
  || fail "network QR secret dispatcher success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$qr_secret_output"; then
  fail "network QR secret dispatcher produced a QML runtime error"
fi

install -m 0644 "$repo_root/tests/network-qr-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/qr-runtime"
chmod 700 "$tmpdir/qr-runtime"
set +e
qr_output=$(timeout 20 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/qr-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
qr_rc=$?
set -e
printf '%s\n' "$qr_output"
[[ $qr_rc -eq 0 ]] || fail "network QR smoke exited $qr_rc"
grep -F 'network QR regression passed' <<<"$qr_output" >/dev/null \
  || fail "network QR success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error' \
    <<<"$qr_output"; then
  fail "network QR smoke produced a QML runtime error"
fi

install -m 0644 "$repo_root/tests/network-qr-render-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/qr-render-runtime"
chmod 700 "$tmpdir/qr-render-runtime"
qr_render_path="$tmpdir/qr-render.png"
set +e
qr_render_output=$(timeout 20 env \
  SHIBUMI_QR_RENDER_PATH="$qr_render_path" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/qr-render-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
qr_render_rc=$?
set -e
printf '%s\n' "$qr_render_output"
[[ $qr_render_rc -eq 0 ]] || fail "network QR render smoke exited $qr_render_rc"
grep -F 'network QR render regression passed' \
  <<<"$qr_render_output" >/dev/null \
  || fail "network QR render success marker missing"
qr_secured_render_path="$qr_render_path.secured.png"
[[ -s $qr_render_path && -s $qr_secured_render_path ]] \
  || fail "network QR render produced no image"
qr_decoded=$(zbarimg --quiet --raw "$qr_render_path") \
  || fail "replacement Wi-Fi QR render did not decode"
[[ $qr_decoded == 'WIFI:T:nopass;S:Bravo;H:false;;' ]] \
  || fail "replacement Wi-Fi QR render retained the previous matrix"
qr_secured_decoded=$(zbarimg --quiet --raw "$qr_secured_render_path") \
  || fail "secured Wi-Fi QR render did not decode"
[[ $qr_secured_decoded == 'WIFI:T:WPA;S:Private;P:correct horse;H:false;;' ]] \
  || fail "secured Wi-Fi QR render retained stale presentation state"
for qr_image in "$qr_render_path" "$qr_secured_render_path"; do
  qr_render_dimensions=$(magick identify -format '%wx%h' "$qr_image")
  qr_render_width=${qr_render_dimensions%x*}
  qr_render_height=${qr_render_dimensions#*x}
  [[ $qr_render_width == "$qr_render_height" ]] \
    || fail "Wi-Fi QR render is not square"
  qr_render_last=$((qr_render_width - 1))
  for qr_corner in 0,0 "$qr_render_last",0 \
      0,"$qr_render_last" "$qr_render_last","$qr_render_last"; do
    qr_x=${qr_corner%,*}
    qr_y=${qr_corner#*,}
    qr_pixel=$(magick "$qr_image" \
      -crop "1x1+$qr_x+$qr_y" +repage \
      -format '%[fx:int(255*r)],%[fx:int(255*g)],%[fx:int(255*b)],%[fx:int(255*a)]' info:)
    [[ $qr_pixel == 255,255,255,255 ]] \
      || fail "Wi-Fi QR quiet-zone corner is not opaque white"
  done
done

for action_case in coordinator model lifecycle destruction shutdown-completion generation-replay throwing-result profile-name-boundary; do
  action_test="$repo_root/tests/network-action-${action_case}-regression.qml"
  install -m 0644 "$action_test" "$tmpdir/shell.qml"
  mkdir -p "$tmpdir/action-${action_case}-runtime"
  chmod 700 "$tmpdir/action-${action_case}-runtime"
  set +e
  action_output=$(timeout 15 env \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$tmpdir/action-${action_case}-runtime" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$tmpdir" 2>&1)
  action_rc=$?
  set -e
  printf '%s\n' "$action_output"
  [[ $action_rc -eq 0 ]] \
    || fail "network action $action_case smoke exited $action_rc"
  action_marker="network action ${action_case//-/ } regression passed"
  grep -F "$action_marker" <<<"$action_output" >/dev/null \
    || fail "network action $action_case success marker missing"
  if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error' \
      <<<"$action_output"; then
    fail "network action $action_case produced a QML runtime error"
  fi
done

"$repo_root/tests/network-profile-action-helper-regression.py" \
  || fail "exact catalog profile helper regression failed"
install -m 0644 \
  "$repo_root/tests/network-profile-action-dispatcher-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/profile-action-dispatcher-runtime"
chmod 700 "$tmpdir/profile-action-dispatcher-runtime"
set +e
profile_action_dispatcher_output=$(timeout 12 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/profile-action-dispatcher-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
profile_action_dispatcher_rc=$?
set -e
printf '%s\n' "$profile_action_dispatcher_output"
[[ $profile_action_dispatcher_rc -eq 0 ]] \
  || fail "profile action dispatcher smoke exited $profile_action_dispatcher_rc"
grep -F 'network profile action dispatcher regression passed' \
  <<<"$profile_action_dispatcher_output" >/dev/null \
  || fail "profile action dispatcher success marker missing"

install -m 0644 \
  "$repo_root/tests/network-profile-action-lease-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/profile-action-lease-runtime"
chmod 700 "$tmpdir/profile-action-lease-runtime"
set +e
profile_action_lease_output=$(timeout 10 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/profile-action-lease-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
profile_action_lease_rc=$?
set -e
printf '%s\n' "$profile_action_lease_output"
[[ $profile_action_lease_rc -eq 0 ]] \
  || fail "profile action lease smoke exited $profile_action_lease_rc"
grep -F 'network profile action lease regression passed' \
  <<<"$profile_action_lease_output" >/dev/null \
  || fail "profile action lease success marker missing"

install -m 0644 \
  "$repo_root/tests/network-native-scanner-lease-regression.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/scanner-native-runtime" "$tmpdir/scanner-native-home"
chmod 700 "$tmpdir/scanner-native-runtime"
set +e
scanner_native_output=$(timeout 15 env \
  HOME="$tmpdir/scanner-native-home" \
  DBUS_SYSTEM_BUS_ADDRESS="unix:path=$tmpdir/missing-scanner-system-bus" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/scanner-native-runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
scanner_native_rc=$?
set -e
printf '%s\n' "$scanner_native_output"
[[ $scanner_native_rc -eq 0 ]] \
  || fail "network native scanner smoke exited $scanner_native_rc"
grep -F 'network native scanner lease regression passed' \
  <<<"$scanner_native_output" >/dev/null \
  || fail "network native scanner success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$scanner_native_output"; then
  fail "native scanner seam produced a QML runtime error"
fi

if grep -F 'Binding loop detected' <<<"$output" >/dev/null; then
  fail "V1/V2 network presentation produced a binding loop"
fi

widget="$repo_root/hancore.shibumi.network/BarWidget.qml"
service="$repo_root/hancore.shibumi.network/Service.qml"
bridge="$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml"
native_adapter="$repo_root/hancore.shibumi.network/NetworkBackendAdapter.qml"
native_gateway="$repo_root/hancore.shibumi.network/NetworkNativeGateway.qml"
native_model="$repo_root/hancore.shibumi.network/NetworkModel.js"
scanner_lease="$repo_root/hancore.shibumi.network/NetworkScannerLease.qml"
scanner_gateway="$repo_root/hancore.shibumi.network/NetworkScannerNativeGateway.qml"
scanner_authority="$repo_root/hancore.shibumi.network/NetworkScannerAuthority.js"
liveness="$repo_root/hancore.shibumi.network/NetworkManagerLiveness.qml"
liveness_continuity="$repo_root/hancore.shibumi.network/NetworkLivenessContinuity.qml"
liveness_model="$repo_root/hancore.shibumi.network/NetworkLivenessModel.js"
liveness_authority="$repo_root/hancore.shibumi.network/NetworkLivenessAuthority.js"
liveness_helper="$repo_root/hancore.shibumi.network/scripts/network-manager-owner-watch"
profile_catalog="$repo_root/hancore.shibumi.network/NetworkProfileCatalog.qml"
profile_catalog_model="$repo_root/hancore.shibumi.network/NetworkProfileCatalogModel.js"
profile_catalog_authority="$repo_root/hancore.shibumi.network/NetworkProfileCatalogAuthority.js"
profile_catalog_helper="$repo_root/hancore.shibumi.network/scripts/network-profile-catalog"
profile_action_dispatcher="$repo_root/hancore.shibumi.network/NetworkProfileActionDispatcher.qml"
profile_action_model="$repo_root/hancore.shibumi.network/NetworkProfileActionModel.js"
profile_action_authority="$repo_root/hancore.shibumi.network/NetworkProfileActionAuthority.js"
profile_action_helper="$repo_root/hancore.shibumi.network/scripts/network-profile-action"
telemetry="$repo_root/hancore.shibumi.network/NetworkTelemetry.qml"
telemetry_model="$repo_root/hancore.shibumi.network/NetworkTelemetryModel.js"
telemetry_authority="$repo_root/hancore.shibumi.network/NetworkTelemetryAuthority.js"
telemetry_helper="$repo_root/hancore.shibumi.network/scripts/network-telemetry-snapshot"
reachability="$repo_root/hancore.shibumi.network/NetworkReachability.qml"
reachability_model="$repo_root/hancore.shibumi.network/NetworkReachabilityModel.js"
reachability_authority="$repo_root/hancore.shibumi.network/NetworkReachabilityAuthority.js"
reachability_helper="$repo_root/hancore.shibumi.network/scripts/network-reachability-probe"
speed_test="$repo_root/hancore.shibumi.network/NetworkSpeedTest.qml"
speed_test_model="$repo_root/hancore.shibumi.network/NetworkSpeedTestModel.js"
speed_test_authority="$repo_root/hancore.shibumi.network/NetworkSpeedTestAuthority.js"
speed_test_helper="$repo_root/hancore.shibumi.network/scripts/network-speed-test"
enterprise_dispatcher="$repo_root/hancore.shibumi.network/NetworkEnterpriseDispatcher.qml"
enterprise_model="$repo_root/hancore.shibumi.network/NetworkEnterpriseModel.js"
enterprise_authority="$repo_root/hancore.shibumi.network/NetworkEnterpriseAuthority.js"
enterprise_helper="$repo_root/hancore.shibumi.network/scripts/network-enterprise-connect"
action_coordinator="$repo_root/hancore.shibumi.network/NetworkActionCoordinator.qml"
action_model="$repo_root/hancore.shibumi.network/NetworkActionModel.js"
action_authority="$repo_root/hancore.shibumi.network/NetworkActionAuthority.js"
qr_encoder="$repo_root/hancore.shibumi.network/NetworkQrEncoder.js"
qr_model="$repo_root/hancore.shibumi.network/NetworkQrModel.js"
qr_session="$repo_root/hancore.shibumi.network/NetworkQrSession.qml"
qr_button="$repo_root/hancore.shibumi.network/NetworkQrButton.qml"
qr_dialog="$repo_root/hancore.shibumi.network/NetworkQrDialog.qml"
qr_secret_model="$repo_root/hancore.shibumi.network/NetworkQrSecretModel.js"
qr_secret_dispatcher="$repo_root/hancore.shibumi.network/NetworkQrSecretDispatcher.qml"
qr_secret_authority="$repo_root/hancore.shibumi.network/NetworkQrSecretAuthority.js"
qr_secret_helper="$repo_root/hancore.shibumi.network/scripts/network-qr-secret"
[[ -f $native_adapter && -f $native_gateway && -f $native_model \
    && -f $scanner_lease && -f $scanner_gateway \
    && -f $scanner_authority && -f $liveness \
    && -f $liveness_continuity && -f $liveness_model \
    && -f $liveness_authority && -x $liveness_helper \
    && -f $profile_catalog && -f $profile_catalog_model \
    && -f $profile_catalog_authority && -x $profile_catalog_helper \
    && -f $profile_action_dispatcher && -f $profile_action_model \
    && -f $profile_action_authority && -x $profile_action_helper \
    && -f $telemetry && -f $telemetry_model \
    && -f $telemetry_authority && -x $telemetry_helper \
    && -f $reachability && -f $reachability_model \
    && -f $reachability_authority && -x $reachability_helper \
    && -f $speed_test && -f $speed_test_model \
    && -f $speed_test_authority && -x $speed_test_helper \
    && -f $enterprise_dispatcher && -f $enterprise_model \
    && -f $enterprise_authority && -x $enterprise_helper \
    && -f $action_coordinator && -f $action_model \
    && -f $action_authority && -f $qr_encoder && -f $qr_model \
    && -f $qr_session && -f $qr_button && -f $qr_dialog \
    && -f $qr_secret_model && -f $qr_secret_dispatcher \
    && -f $qr_secret_authority && -f $qr_secret_helper ]] \
  || fail "native Network seam inventory is incomplete"
rg -Fq 'active: root.active && root.backendOverride === null' \
  "$native_adapter" \
  || fail "native Network gateway is not isolated behind the activation Loader"
rg -Fq '&& root.nativeServiceAvailable' "$native_adapter" \
  || fail "native Network gateway can initialize before owner monitoring"
rg -Fq 'property var nativeLiveness: null' "$native_adapter" \
  || fail "native Network availability lacks the shared liveness seam"
rg -Fq 'root.nativeLiveness.serviceUsable === true' "$native_adapter" \
  || fail "native Network availability bypasses reactive owner liveness"
rg -Fq 'onNativeServiceEpochChanged: generation++' "$native_adapter" \
  || fail "owner transitions do not invalidate Network action generations"
rg -Fq 'gateway.backendInitialized === true' "$native_adapter" \
  || fail "native Network availability trusts singleton initialization alone"
if rg -q '^import Quickshell\.Networking$|Networking\.' "$native_adapter"; then
  fail "outer Network adapter can bypass fake isolation"
fi
rg -Fq 'import Quickshell.Networking' "$native_gateway" \
  || fail "native Network gateway does not use the public Quickshell API"
rg -Fq 'return IdPrefix + JSON.stringify(values)' "$native_model" \
  || fail "Network entity IDs are not collision-safe versioned tuples"
rg -Fq 'return tupleId("profile", [device, uuid])' "$native_model" \
  || fail "saved-profile identity is not scoped to its current device"
rg -Fq 'var MaxBackendObjects = 8192' "$native_model" \
  || fail "native Network traversal has no aggregate object budget"
rg -Fq 'return root.result(false, "unsupported",' "$native_adapter" \
  || fail "native Network aggregate forget is not rejected"
if rg -q '(target|network)\.forget\(' "$native_adapter" "$native_gateway"; then
  fail "Step 5A can invoke Quickshell aggregate network forget"
fi
rg -Fq 'function networkResolution(entityId)' "$native_adapter" \
  || fail "native actions do not resolve current raw Network objects"
rg -Fq 'function profileResolution(entityId)' "$native_adapter" \
  || fail "saved-profile actions do not resolve current NMSettings objects"
rg -Fq 'readonly property bool snapshotDegraded:' "$native_adapter" \
  || fail "oversized native Network snapshots do not fail closed"
rg -Fq 'if (resolved.count > 1 || resolved.row && resolved.row.ambiguous)' \
  "$native_adapter" \
  || fail "duplicate native Network identities do not fail closed"
rg -Fq 'if (request.generation !== root.generation)' "$native_adapter" \
  || fail "native Network actions do not enforce topology generations"
rg -Fq 'const keys = Reflect.ownKeys(request)' "$native_adapter" \
  || fail "native Network actions repeatedly evaluate untrusted request getters"
rg -Fq 'const safeRequest = parsed.request' "$native_adapter" \
  || fail "native Network actions do not dispatch from primitive request copies"
rg -Fq 'value = gateway.connectProfile(network, profile)' "$native_adapter" \
  || fail "saved-profile connect bypasses the private native gateway"
rg -Fq 'const ok = value.ok' "$native_adapter" \
  || fail "native Network adapter repeatedly evaluates delegate result getters"
rg -Fq 'value = gateway.forgetProfile(profile)' "$native_adapter" \
  || fail "exact saved-profile removal bypasses the private native gateway"
rg -Fq 'network.connectWithSettings(profile)' "$native_gateway" \
  || fail "saved-profile connect does not use exact Quickshell NMSettings"
rg -Fq 'profile.forget()' "$native_gateway" \
  || fail "saved-profile removal does not use exact NMSettings"
if rg -q 'profileSettings|\.read\(' "$native_adapter" "$native_gateway"; then
  fail "native profile projection materializes unbounded NMSettings maps"
fi
rg -Fq 'Saved-profile removal dispatch accepted.' "$native_gateway" \
  || fail "profile removal acceptance is presented as synchronous completion"
rg -Fq 'DBUS_SYSTEM_BUS_ADDRESS="unix:path=$tmpdir/missing-system-bus"' \
  "$repo_root/tests/network-plugin-regression.sh" \
  || fail "fake Network seam is not tested without the system bus"
rg -Fq 'active: root.authorized && root.backendOverride === null' \
  "$scanner_lease" \
  || fail "native scanner gateway is not isolated behind exclusive authority"
rg -Fq 'root.nativeLiveness.serviceUsable === true' "$scanner_lease" \
  || fail "native scanner bypasses shared NetworkManager liveness"
rg -Fq 'property bool nativeGatewayAdmitted: false' "$scanner_lease" \
  || fail "native scanner gateway has no monitored admission latch"
rg -Fq '&& implementation.nativeGatewayAdmitted' "$scanner_lease" \
  || fail "native scanner gateway can initialize before owner monitoring"
rg -Fq 'onNativeServiceEpochChanged: implementation.reconcile()' \
  "$scanner_lease" \
  || fail "scanner does not close on NetworkManager owner transitions"
rg -Fq 'A monitoring gap or owner loss' "$liveness" \
  || fail "NetworkManager recovery policy is undocumented"
rg -Fq 'record.sequence !== root.lastSequence + 1' "$liveness" \
  || fail "NetworkManager owner protocol does not reject sequence gaps"
rg -Fq 'currentClaim = token' "$liveness_authority" \
  || fail "NetworkManager owner watcher is not process-wide"
rg -Fq 'continuityBlocked = true' "$liveness_authority" \
  || fail "liveness authority handoff forgets monitoring gaps"
rg -Fq 'if (root.monitorEstablished) blockRecovery()' "$liveness" \
  || fail "NetworkManager monitoring gaps do not block stale recovery"
rg -Fq 'property bool processRestartRequired: false' \
  "$liveness_continuity" \
  || fail "NetworkManager recovery block does not survive soft reloads"
rg -Fq 'readonly property bool recoveryBlocked: liveness.recoveryBlocked' \
  "$service" \
  || fail "native service does not publish the live recovery block"
rg -Fq 'readonly property bool mutationBlocked: root.processRestartRequired' \
  "$service" \
  || fail "native service does not centralize the restart mutation barrier"
[[ $(grep -Fc 'invalidAction("restart-required")' "$service") -ge 6 ]] \
  || fail "native service does not reject every stale public mutation route"
rg -Fq 'networkService.livenessPhase === "recovery-blocked"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "native panel cannot explain a live NetworkManager recovery block"
rg -Fq 'property var continuityState: null' "$liveness" \
  || fail "NetworkManager watcher can hide its reload-continuity owner"
rg -Fq 'if (JSON.stringify(parsed) !== value)' "$liveness_model" \
  || fail "NetworkManager owner protocol does not reject duplicate keys"
rg -Fq '"/usr/bin/gdbus"' "$liveness_helper" \
  || fail "NetworkManager watcher does not use the declared GLib D-Bus boundary"
rg -Fq 'OBJECT_PATH = "/org/hancore/Shibumi/NetworkManagerOwnerWatch"' \
  "$liveness_helper" \
  || fail "NetworkManager watcher observes an unbounded D-Bus object scope"
rg -Fq 'PR_SET_PDEATHSIG = 1' "$liveness_helper" \
  || fail "NetworkManager monitor child lacks parent-death supervision"
if rg -q 'omarchy|nmcli' "$liveness" "$liveness_model" "$liveness_helper"; then
  fail "NetworkManager liveness watcher depends on a feature helper or CLI poller"
fi
rg -Fq 'currentClaim = token' "$profile_catalog_authority" \
  || fail "saved-profile catalog worker is not process-wide"
rg -Fq 'leaseTokenComponent.createObject(owner' "$profile_catalog" \
  || fail "saved-profile catalog work is not demand-driven by owner leases"
rg -Fq 'if (records.length === 1) refresh()' "$profile_catalog" \
  || fail "first saved-profile consumer does not request a snapshot"
rg -Fq 'if (records.length === 0) {' "$profile_catalog" \
  || fail "last saved-profile consumer does not release state and work"
rg -Fq 'if (JSON.stringify(parsed) !== value)' "$profile_catalog_model" \
  || fail "saved-profile protocol does not reject duplicate JSON keys"
rg -Fq 'function catalogProfileId(uuidValue)' "$native_model" \
  || fail "global saved-profile catalog lacks a stable UUID identity"
rg -Fq 'function savedProfileProjection()' "$native_adapter" \
  || fail "native adapter does not validate the saved-profile catalog"
rg -Fq 'savedProfileCatalog.available === true' "$native_adapter" \
  || fail "native adapter can publish an incomplete saved-profile catalog"
rg -Fq 'MAX_SETTINGS_BYTES = 256 * 1024' "$profile_catalog_helper" \
  || fail "saved-profile settings reads have no per-profile byte bound"
rg -Fq 'MAX_RUNTIME_SECONDS = 20.0' "$profile_catalog_helper" \
  || fail "saved-profile catalog has no aggregate runtime bound"
rg -Fq 'def bounded_command(' "$profile_catalog_helper" \
  || fail "saved-profile D-Bus reads buffer before enforcing bounds"
rg -Fq '"Unsaved", "VersionId"' "$profile_catalog_helper" \
  || fail "saved-profile catalog cannot reject unsaved or racing settings"
rg -Fq 'if list_connections(deadline, owner_before) != initial_paths:' \
  "$profile_catalog_helper" \
  || fail "saved-profile catalog does not close on topology races"
if rg -q 'GetSecrets|identity|password|ca-cert|nmcli|omarchy' \
    "$profile_catalog_helper"; then
  fail "saved-profile helper crosses the bounded non-secret metadata boundary"
fi
rg -Fq 'currentClaim = token' "$telemetry_authority" \
  || fail "network telemetry worker is not process-wide"
rg -Fq 'permanentlyBlocked = true' "$telemetry_authority" \
  || fail "destroyed telemetry workers do not block fail-closed"
rg -Fq 'leaseTokenComponent.createObject(owner' "$telemetry" \
  || fail "network telemetry is not demand-driven by owner leases"
rg -Fq 'pollIntervalMs: 2000' "$telemetry" \
  || fail "network telemetry lacks a bounded central polling cadence"
rg -Fq 'if (implementation.shutdownRequested)' "$telemetry" \
  || fail "failed process starts can retain telemetry authority"
rg -Fq 'if (JSON.stringify(parsed) !== value)' "$telemetry_model" \
  || fail "network telemetry protocol does not reject duplicate JSON keys"
rg -Fq 'function telemetryProjection()' "$native_adapter" \
  || fail "native adapter does not validate active connection telemetry"
rg -Fq 'get_name_owner(deadline)' "$telemetry_helper" \
  || fail "network telemetry does not bind snapshots to one D-Bus owner"
rg -Fq 'MAX_PROPERTY_BYTES = 64 * 1024' "$telemetry_helper" \
  || fail "network telemetry D-Bus reads have no byte bound"
rg -Fq 'MAX_RUNTIME_SECONDS = 10.0' "$telemetry_helper" \
  || fail "network telemetry has no aggregate runtime bound"
rg -Fq 'ip_snapshot(active["Ip4Config"], 4, deadline, owner_before)' \
  "$telemetry_helper" \
  || fail "network telemetry does not revalidate IP and DNS state"
rg -Fq 'os.O_NOFOLLOW' "$telemetry_helper" \
  || fail "network telemetry counter reads can follow a forged final symlink"
if rg -q 'GetSecrets|nmcli|omarchy|/usr/bin/(ip|ping|resolvectl)' \
    "$telemetry_helper"; then
  fail "network telemetry crosses its bounded NetworkManager/sysfs boundary"
fi
rg -Fq 'currentClaim = token' "$reachability_authority" \
  || fail "network reachability worker is not process-wide"
rg -Fq 'permanentlyBlocked = true' "$reachability_authority" \
  || fail "destroyed reachability workers do not block fail-closed"
rg -Fq 'leaseTokenComponent.createObject(owner' "$reachability" \
  || fail "network reachability is not demand-driven by owner leases"
rg -Fq 'function reachabilityProjection()' "$native_adapter" \
  || fail "native adapter does not validate reachability snapshots"
rg -Fq 'PING = "/usr/bin/ping"' "$reachability_helper" \
  || fail "network reachability does not pin its ICMP probe"
rg -Fq 'INTERNET_TARGET = "1.1.1.1"' "$reachability_helper" \
  || fail "network reachability internet identity is not fixed"
rg -Fq 'MAX_OUTPUT_BYTES = 8192' "$reachability_helper" \
  || fail "network reachability output has no byte bound"
rg -Fq 'MAX_RUNTIME_SECONDS = 4.0' "$reachability_helper" \
  || fail "network reachability has no aggregate runtime bound"
rg -Fq 'signal.SIGKILL' "$reachability_helper" \
  || fail "reachability probe children lack parent-death cleanup"
if rg -q 'GetSecrets|nmcli|omarchy|shell=True|/bin/(sh|bash)' \
    "$reachability_helper"; then
  fail "network reachability crosses its fixed process boundary"
fi
rg -Fq 'currentClaim = token' "$speed_test_authority" \
  || fail "network speed-test worker is not process-wide"
rg -Fq 'permanentlyBlocked = true' "$speed_test_authority" \
  || fail "destroyed speed-test workers do not block fail-closed"
rg -Fq 'ownerTokenComponent.createObject(owner' "$speed_test" \
  || fail "network speed tests are not bound to requesting owners"
rg -Fq 'function canSignalProcess()' "$speed_test" \
  || fail "network speed-test cancellation can signal an unstarted process"
rg -Fq 'if (canSignalProcess()) speedProcess.signal(15)' "$speed_test" \
  || fail "network speed-test termination bypasses positive PID validation"
rg -Fq 'if (JSON.stringify(parsed) !== value)' "$speed_test_model" \
  || fail "network speed-test protocol does not reject duplicate JSON keys"
rg -Fq 'up.sampleMonotonicMs <= down.sampleMonotonicMs' "$speed_test_model" \
  || fail "network speed-test phases accept replayed timestamps"
rg -Fq 'measurement.runToken === runToken' "$speed_test_model" \
  || fail "network speed-test results are not bound to the current run"
rg -Fq 'up.interfaceIndex !== down.interfaceIndex' "$speed_test_model" \
  || fail "network speed-test phases can cross interface identities"
rg -Fq '"--expected-interface-index", expectedInterfaceIndex' "$speed_test" \
  || fail "upload speed tests do not pin the download interface identity"
rg -Fq 'HOST = "speed.cloudflare.com"' "$speed_test_helper" \
  || fail "network speed-test endpoint is not fixed"
rg -Fq 'DOWNLOAD_LIMIT_BYTES = 1024 * 1024 * 1024' "$speed_test_helper" \
  || fail "network speed-test download traffic is unbounded"
rg -Fq 'UPLOAD_LIMIT_BYTES = 512 * 1024 * 1024' "$speed_test_helper" \
  || fail "network speed-test upload traffic is unbounded"
rg -Fq 'MAX_REQUESTS_PER_WORKER = 64' "$speed_test_helper" \
  || fail "network speed-test request count is unbounded"
rg -Fq 'PR_SET_PDEATHSIG = 1' "$speed_test_helper" \
  || fail "network speed-test helper lacks parent-death supervision"
rg -Fq 'socket.SO_BINDTODEVICE' "$speed_test_helper" \
  || fail "network speed-test traffic is not bound to its telemetry interface"
rg -Fq 'interface_index(INTERFACE_NAME) != INTERFACE_INDEX' \
  "$speed_test_helper" \
  || fail "network speed-test does not revalidate interface identity"
if rg -q 'GetSecrets|nmcli|omarchy|subprocess|urllib|import requests|curl|shell=True|/bin/(sh|bash)' \
    "$speed_test_helper"; then
  fail "network speed test crosses its fixed TLS worker boundary"
fi
rg -Fq 'currentClaim = token' "$enterprise_authority" \
  || fail "network Enterprise dispatcher is not process-wide"
rg -Fq 'permanentlyBlocked = true' "$enterprise_authority" \
  || fail "uncertain Enterprise destruction does not block fail-closed"
rg -Fq 'inputLine = ""' "$enterprise_dispatcher" \
  || fail "network Enterprise dispatcher does not clear its stdin frame"
rg -Fq 'clearEnvironment: true' "$enterprise_dispatcher" \
  || fail "network Enterprise helper inherits an injectable Python environment"
rg -Fq 'return ["/usr/bin/python3", "-I", root.helperPath]' "$enterprise_dispatcher" \
  || fail "network Enterprise helper can import user-site Python modules"
rg -Fq 'if (canSignalProcess()) enterpriseProcess.signal(15)' \
  "$enterprise_dispatcher" \
  || fail "network Enterprise cancellation bypasses positive PID validation"
rg -Fq '"persist": dbus.String("volatile")' "$enterprise_helper" \
  || fail "network Enterprise credentials can persist in NetworkManager"
rg -Fq '"system-ca-certs": dbus.Boolean(True)' "$enterprise_helper" \
  || fail "network Enterprise server trust does not use system CAs"
rg -Fq '"domain-suffix-match": dbus.String(request["serverDomain"])' \
  "$enterprise_helper" \
  || fail "network Enterprise server certificate identity is not pinned"
rg -Fq 'if name_owner(bus, deadline) != owner:' "$enterprise_helper" \
  || fail "network Enterprise mutation is not owner-race protected"
rg -Fq '"HwAddress", deadline' "$enterprise_helper" \
  || fail "network Enterprise mutation is not hardware-identity bound"
rg -Fq 'MAX_INPUT_BYTES = 8192' "$enterprise_helper" \
  || fail "network Enterprise credential input is unbounded"
rg -Fq 'function enterpriseConnectionDescriptor(request)' "$native_adapter" \
  || fail "network Enterprise actions lack a primitive topology descriptor"
rg -Fq 'function connectNetworkEnterprise(request, credentials)' \
  "$action_coordinator" \
  || fail "network action authority does not own Enterprise completion"
rg -Fq '"connect-enterprise"' "$action_model" \
  || fail "network action model cannot reconcile Enterprise connections"
rg -Fq 'EnterpriseModel.completionMatches(completion,' "$action_coordinator" \
  || fail "network Enterprise completion lacks exact helper evidence"
rg -Fq 'Model.enterpriseConnected(state, view)' "$action_coordinator" \
  || fail "network Enterprise completion accepts a disconnected target"
rg -Fq '"id": dbus.String(request["requestToken"])' "$enterprise_helper" \
  || fail "network Enterprise activation lacks an exact connection identity"
if rg -q 'GetSecrets|nmcli|omarchy|subprocess|shell=True|/bin/(sh|bash)' \
    "$enterprise_helper"; then
  fail "network Enterprise helper crosses its direct D-Bus boundary"
fi
if rg -q 'property [^:]*\b(secret|passphrase|password|identity)\b' \
    "$enterprise_dispatcher" "$action_coordinator"; then
  fail "network Enterprise action owners retain named credential properties"
fi
rg -Fq 'currentClaim = token' "$action_authority" \
  || fail "network action completion authority is not process-wide"
rg -Fq 'appendBits(bits, 26, 8)' "$qr_encoder" \
  || fail "Wi-Fi QR byte mode does not declare UTF-8 ECI"
rg -Fq 'Copyright (c) Project Nayuki. (MIT License)' "$repo_root/LICENSE" \
  || fail "Wi-Fi QR encoder attribution is missing from the shipped license"
rg -Fq 'var MaxInputBytes = 240' "$qr_encoder" \
  || fail "Wi-Fi QR encoder has no fixed input bound"
rg -Fq 'NetworkModel.validPsk(passphrase, network.security)' "$qr_model" \
  || fail "Wi-Fi QR passphrases bypass the native credential contract"
rg -Fq 'primary: true' "$qr_dialog" \
  || fail "Wi-Fi QR close action does not match the primary panel action style"
rg -Fq 'root.visualTokens.seal' "$qr_dialog" \
  || fail "Wi-Fi QR close action does not use the primary panel fill"
rg -Fq 'root.visualTokens.paper' "$qr_dialog" \
  || fail "Wi-Fi QR primary action lacks readable token contrast"
rg -Fq 'left.network.generation === right.network.generation' "$qr_session" \
  || fail "Wi-Fi QR passphrase submission is not generation-bound"
if rg -q '[Oo]marchy|nmcli|GetSecrets|Quickshell\.Io|\bProcess\b' \
    "$qr_encoder" "$qr_model" "$qr_session" "$qr_button" "$qr_dialog"; then
  fail "Shibumi Wi-Fi QR surface depends on an external feature backend"
fi
if rg -q 'property [^:]*\b(passphrase|password|psk)\b' \
    "$qr_session" "$qr_dialog" "$qr_secret_dispatcher"; then
  fail "Wi-Fi QR owners retain a credential property"
fi
rg -Fq 'CONNECTION_INTERFACE, "GetSecrets"' "$qr_secret_helper" \
  || fail "Wi-Fi QR helper does not scope its explicit secret read"
rg -Fq 'message.append("802-11-wireless-security", signature="s")' \
  "$qr_secret_helper" \
  || fail "Wi-Fi QR helper does not bind the exact secret setting argument"
rg -Fq 'message.set_auto_start(False)' "$qr_secret_helper" \
  || fail "Wi-Fi QR secret authorization can activate a replacement service"
rg -Fq 'message.set_allow_interactive_authorization(True)' \
  "$qr_secret_helper" \
  || fail "Wi-Fi QR helper cannot invoke Omarchy native Polkit authorization"
rg -Fq 'AUTHORIZATION_TIMEOUT_SECONDS = 55.0' "$qr_secret_helper" \
  || fail "Wi-Fi QR interactive authorization has no fixed timeout"
rg -Fq 'property int workerTimeoutMs: 60000' "$qr_secret_dispatcher" \
  || fail "Wi-Fi QR dispatcher cannot bound interactive authorization"
rg -Fq 'Math.min(60000, root.workerTimeoutMs)' "$qr_secret_dispatcher" \
  || fail "Wi-Fi QR interactive worker timeout can grow unbounded"
rg -Fq 'MAX_SETTINGS_BYTES = 256 * 1024' "$qr_secret_helper" \
  || fail "Wi-Fi QR profile settings revalidation is unbounded"
rg -Fq 'MAX_ADDRESS_SPACE_BYTES = 128 * 1024 * 1024' \
  "$qr_secret_helper" \
  || fail "Wi-Fi QR D-Bus worker lacks a pre-acquisition memory ceiling"
rg -Fq 'resource.setrlimit(resource.RLIMIT_AS' "$qr_secret_helper" \
  || fail "Wi-Fi QR D-Bus worker does not apply its memory ceiling"
rg -Fq ').GetSettings()' "$qr_secret_helper" \
  || fail "Wi-Fi QR helper does not revalidate current persisted settings"
rg -Fq 'CONNECTION_INTERFACE, "VersionId"' "$qr_secret_helper" \
  || fail "Wi-Fi QR helper does not bind the saved profile version"
if rg -Uq 'CONNECTION_INTERFACE,\s*"(Uuid|Type)"' "$qr_secret_helper"; then
  fail "Wi-Fi QR helper queries nonexistent Settings.Connection properties"
fi
rg -Fq 'settings_after != settings_before' "$qr_secret_helper" \
  || fail "Wi-Fi QR helper accepts a profile race around GetSecrets"
[[ $(grep -Fc 'owner_unchanged(bus, destination)' "$qr_secret_helper") -ge 2 ]] \
  || fail "Wi-Fi QR helper omits final NetworkManager owner revalidation"
rg -Fq 'set(str(key) for key in setting) != {"psk"}' "$qr_secret_helper" \
  || fail "Wi-Fi QR helper accepts an unbounded secret field map"
rg -Fq 'clearEnvironment: true' "$qr_secret_dispatcher" \
  || fail "Wi-Fi QR secret worker inherits an injectable environment"
rg -Fq '["/usr/bin/python3", "-I", root.helperPath]' "$qr_secret_dispatcher" \
  || fail "Wi-Fi QR secret worker can import user-site modules"
rg -Fq 'completion.psk = ""' "$qr_secret_dispatcher" \
  || fail "Wi-Fi QR secret completion is not cleared before staging returns"
if rg -q 'property [^:]*stdoutBuffer' "$qr_secret_dispatcher"; then
  fail "Wi-Fi QR secret worker retains partial stdout in a QML property"
fi
rg -Fq 'const failure = Model.parseFailure(line)' "$qr_secret_dispatcher" \
  || fail "Wi-Fi QR secret failures bypass bounded completion parsing"
rg -Fq '"authorization-failed", "secret-response", "connection-changed"' \
  "$qr_secret_model" \
  || fail "Wi-Fi QR secret diagnostic reasons are not explicitly allowlisted"
rg -Fq '"status": "failed"' "$qr_secret_helper" \
  || fail "Wi-Fi QR helper lacks secret-free stage diagnostics"
rg -Fq 'splitMarker: ""' "$qr_secret_dispatcher" \
  || fail "Wi-Fi QR secret stderr does not use chunk-discard framing"
if rg -q 'print\([^\n]*(str|repr)\(error\)' "$qr_secret_helper"; then
  fail "Wi-Fi QR helper exposes variable exception text"
fi
rg -Fq 'function beginQrGesture(owner, entry)' "$service" \
  || fail "Wi-Fi QR secret reads lack a one-shot gesture boundary"
rg -Fq 'function qrShareEligible(' "$native_model" \
  || fail "secured QR action lacks persisted-profile eligibility"
rg -Fq 'adapter.savedProfileCatalogAvailable !== true' "$service" \
  || fail "secured QR secret dispatch accepts an incomplete profile catalog"
rg -Fq 'onClicked: panel.activateQrButton(networkRow.modelData)' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "adjacent QR button bypasses explicit gesture activation"
if rg -q 'nmcli|omarchy|subprocess|shell=True|/bin/(sh|bash)' \
    "$qr_secret_helper"; then
  fail "Wi-Fi QR secret helper crosses its exact D-Bus boundary"
fi
rg -Fq 'permanentlyBlocked = true' "$action_authority" \
  || fail "uncertain action destruction does not block fail-closed"
rg -Fq 'actionTimeout.restart()' "$action_coordinator" \
  || fail "accepted network actions have no completion timeout"
rg -Fq 'deferredReconcile.restart()' "$action_coordinator" \
  || fail "network action completion can miss settled snapshot bindings"
rg -Fq 'result.generation !== currentGeneration' "$action_coordinator" \
  || fail "network action dispatch acceptance is not generation-bound"
rg -Fq 'if (!result.ok) {' "$action_coordinator" \
  || fail "negative post-dispatch results can release the action barrier"
rg -Fq 'dispatchInProgress = true' "$action_coordinator" \
  || fail "network action delegates can re-enter before the busy barrier"
rg -Fq 'const keys = Reflect.ownKeys(request)' "$action_coordinator" \
  || fail "network action coordinator accepts hidden request fields"
rg -Fq '"Network dispatch outcome is uncertain.", id, safeRequest' \
  "$action_coordinator" \
  || fail "network action state can expose raw backend messages"
rg -Fq 'probe.sampleMonotonicMs <= previous.sampleMonotonicMs' \
  "$reachability_model" \
  || fail "network reachability accepts replayed samples"
rg -Fq 'view.generation > pending.dispatchGeneration' "$action_model" \
  || fail "destructive action completion accepts its dispatch snapshot"
if rg -q 'property [^:]*\b(secret|passphrase|password)\b' \
    "$action_coordinator"; then
  fail "network action coordinator retains credential state"
fi
rg -Fq 'currentClaim = token' "$scanner_authority" \
  || fail "scanner mutation authority is not process-wide"
rg -Fq 'function onObjectRemovedPre(object, _index)' "$scanner_gateway" \
  || fail "native scanner does not close removed devices before deletion"
rg -Fq 'tombstonedDevices' "$scanner_gateway" \
  || fail "native scanner removal has no private tombstone phase"
rg -Fq 'Component.onDestruction: closeScanner()' "$scanner_gateway" \
  || fail "native scanner gateway lacks owned-device teardown"
rg -Fq 'property int pendingEpoch: 0' "$scanner_lease" \
  || fail "scanner delay callbacks are not epoch guarded"
rg -Fq 'phase = "delay-pending"' "$scanner_lease" \
  || fail "scanner rescan lacks an explicit closed delay phase"
rg -Fq 'phase = "cleanup-pending"' "$scanner_lease" \
  || fail "failed scanner cleanup does not block backend replacement"
rg -Fq 'readonly property bool snapshotDegraded:' "$scanner_lease" \
  || fail "malformed scanner snapshots are not rejected as a whole"
rg -Fq 'Scanner device is owned by another provider.' "$scanner_gateway" \
  || fail "native scanner gateway can claim a foreign scanner"
rg -Fq 'function onScannerEnabledChanged()' "$scanner_gateway" \
  || fail "hot-reload scanner handoff cannot observe foreign release"
rg -Fq 'leaseTokenComponent.createObject(owner' "$scanner_lease" \
  || fail "scanner clients are not lifetime-bound by owner-parented tokens"
if rg -q 'ownedDevices|tombstonedDevices|leaseBackend' "$service"; then
  fail "production Network service exposes private scanner ownership objects"
fi
# The atomic cutover must activate every process-wide native owner exactly once
# and leave presentation files on primitive service state only.
for component in NetworkLivenessContinuity NetworkManagerLiveness \
    NetworkProfileCatalog NetworkTelemetry NetworkReachability \
    NetworkBackendAdapter NetworkScannerLease NetworkEnterpriseDispatcher \
    NetworkActionCoordinator NetworkSpeedTest NetworkProfileActionDispatcher \
    NetworkProfileActionLease \
    NetworkPanelBridge; do
  [[ $(rg -c "^[[:space:]]*$component \{" "$service") -eq 1 ]] \
    || fail "production Network service does not own exactly one $component"
done
if rg -q '^import Quickshell\.Networking$|Networking\.' \
    "$service" "$widget" \
    "$repo_root/hancore.shibumi.network/NetworkPanel.qml" "$bridge"; then
  fail "Network presentation bypasses the private native adapter"
fi
if rg -q 'InlineSpeedTestRunner|omarchy-network-|\bnmcli\b' \
    "$repo_root/hancore.shibumi.network"; then
  fail "Network cutover retained a legacy Omarchy/nmcli backend"
fi
[[ $(rg -c 'target: "omarchy\.network"' "$bridge") -eq 1 ]] \
  || fail "Network compatibility IPC does not have exactly one owner"
if rg -q 'Loader|panelSource|panelComponent|omarchy\.wifiqr|omarchy\.speedtest' \
    "$bridge"; then
  fail "Network compatibility route still loads a host feature backend"
fi
rg -Fq 'networkService.runSpeedTest(root) !== true' "$widget" \
  || fail "cold speed IPC clears before the native owner accepts it"
rg -Fq 'function onSpeedTestReadyChanged()' "$widget" \
  || fail "cold speed IPC does not retry when telemetry becomes ready"
rg -Fq 'if (!networkReady) {' "$widget" \
  || fail "cold speed IPC is not preserved before service readiness"
rg -Fq 'beginTrafficConsumer(root)' "$widget" \
  || fail "Ethernet bar does not acquire demand-driven telemetry"
rg -Fq 'endTrafficConsumer(root)' "$widget" \
  || fail "Ethernet bar does not release demand-driven telemetry"
rg -Fq 'id: trafficRetry' "$widget" \
  || fail "Ethernet telemetry has no transient authority retry"
rg -Fq 'objectName: "networkQrAction:" + networkRow.key' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "native connected row has no adjacent Shibumi QR action"
rg -Fq 'label: "QR Code"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "native connected row does not label its adjacent QR action"
rg -Fq 'Accessible.onPressAction: button.activate()' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "native panel actions have no assistive press route"
rg -Fq 'onTextKey: function(text) { panel.handleTextKey(text) }' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "native Network keyboard dispatcher cannot route QR sharing"
rg -Fq 'NetworkQrDialog {' "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "native panel has no Shibumi QR presentation"
rg -Fq 'placeholderText: "Authentication server domain"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "Enterprise UI cannot provide the mandatory server domain"
rg -Fq 'serverDomain: serverDomain' "$service" \
  || fail "Enterprise server-domain evidence does not reach the dispatcher"
rg -Fq 'entry.entityKind === "catalog"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "catalog-only saved profiles do not fail closed to settings"
rg -Fq 'entityKind: "profile"' "$service" \
  || fail "saved-profile rows do not retain UUID-exact action identity"
rg -Fq 'actions.forgetProfile(request)' "$service" \
  || fail "saved-profile removal bypasses the action coordinator"
rg -Fq 'NetworkProfileActionDispatcher {' "$service" \
  || fail "catalog-only profiles have no exact native action seam"
rg -Fq 'owner_unchanged(bus, destination)' "$profile_action_helper" \
  || fail "catalog profile mutations are not owner-revalidated"
if rg -q 'GetSecrets|GetSettings|nmcli' "$profile_action_helper"; then
  fail "catalog profile mutation reads secrets or unbounded settings"
fi
rg -Fq 'NetworkProfileActionLease {' "$service" \
  || fail "pending profile actions do not own completion evidence leases"
rg -Fq 'function refreshForgottenProfile()' "$service" \
  || fail "saved-profile removal does not refresh catalog completion evidence"
rg -Fq 'savedCatalogAbsent(state.profileUuid)' "$action_coordinator" \
  || fail "saved-profile completion ignores the bounded catalog"
rg -Fq 'actions.connectProfile(request)' "$service" \
  || fail "saved-profile connect bypasses the action coordinator"
rg -Fq 'function activeConnectionUuidForDevice(deviceId)' "$native_adapter" \
  || fail "exact profile completion follows only the primary connection"
rg -Fq 'activeConnections: source.activeConnections' "$native_adapter" \
  || fail "per-device active connection telemetry is not validated"
rg -Fq 'readonly property var connectionFailureSnapshot:' "$native_adapter" \
  || fail "native connection failure evidence is not primitive"
rg -Fq 'Model.connectionFailure(state, snapshot, observed)' \
  "$action_coordinator" \
  || fail "native connection failures are not generation reconciled"
rg -Fq 'owner_before = get_name_owner(deadline)' "$profile_catalog_helper" \
  || fail "saved-profile catalog is not bound to one NetworkManager owner"
rg -Fq 'get_name_owner(deadline) != owner_before' "$profile_catalog_helper" \
  || fail "saved-profile catalog does not revalidate owner identity"
rg -Fq 'Authority.block(authorityClaim)' "$profile_catalog" \
  || fail "catalog destruction cannot block unsafe worker handoff"
rg -Fq 'function finishShutdown()' "$profile_catalog" \
  || fail "catalog authority is released before drain settlement"
for worker in "$liveness" "$profile_catalog" "$telemetry" \
    "$reachability" "$speed_test" "$enterprise_dispatcher"; do
  rg -Fq '["/usr/bin/python3", "-I",' "$worker" \
    || fail "Python Network worker is not isolated: $worker"
done
for dependency in python-dbus iputils glib2 systemd; do
  rg -Fq "\"$dependency\"" \
    "$repo_root/contracts/package-runtime-v1.json" \
    || fail "Network runtime dependency is missing: $dependency"
  rg -Fq "  '$dependency'" "$repo_root/packaging/aur/PKGBUILD" \
    || fail "AUR Network dependency is missing: $dependency"
done
[[ $(rg -c 'BoundedLabel \{' "$widget") -eq 2 ]] \
  || fail "V1/V2 bounded labels do not share the independent metrics path"
rg -Fq 'component BoundedLabel: Text' "$widget" \
  || fail "bounded network labels lack a reusable text component"
rg -Fq 'TextMetrics {' "$widget" \
  || fail "bounded network labels do not use independent text metrics"
rg -q 'serviceFor\("hancore\.shibumi\.network"\)' "$widget" \
  || fail "network widget does not resolve the shared service"
rg -Fq 'property url popupSource: Qt.resolvedUrl("NetworkPanel.qml")' "$widget" \
  || fail "V1 and V2 do not resolve the same NetworkPanel content"
rg -Fq 'function canForget(entry) { return !!entry && entry.canForget === true }' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "Forget is not gated by exact native profile capability"
rg -Fq 'visible: panel.canForget(networkRow.modelData)' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "exact saved profiles do not expose Forget"
if rg -q 'entry\.network|modelData\.network|network: source\.network' \
    "$service" "$repo_root/hancore.shibumi.network/NetworkPanel.qml"; then
  fail "Network view/action contract exposes a raw WifiNetwork object"
fi
if rg -q 'DNS SERVERS|dnsText\(' \
    "$repo_root/hancore.shibumi.network/NetworkPanel.qml"; then
  fail "redundant DNS telemetry is still presented in the Network panel"
fi
if rg -q 'setDns|dnsProviders' \
    "$service" "$repo_root/hancore.shibumi.network/NetworkPanel.qml"; then
  fail "cutover exposes a DNS mutation without a typed native seam"
fi
rg -Fq 'return (measured >= 100 ? measured.toFixed(0) : measured.toFixed(1))' \
  "$service" || fail "native speed results dropped source Mbps formatting"

# Preserve the two reference presentations independently: V1 owns the wide
# history/rate view, while V2 owns the LAN glyph and compact RX/TX meter.
for contract in \
  'readonly property int trafficHistoryLimit: 30' \
  'width: visible ? 36 : 0' \
  'height: 14' \
  'interval: 2000' \
  'running: root.mode === "ethernet" && !root.v2Presentation' \
  'y: height - (Math.max(0, Number(values[index]) || 0)' \
  'text: "↓" + root.v1Rate(root.downloadRate)' \
  'text: "↑" + root.v1Rate(root.uploadRate)' \
  'font.pixelSize: 10' \
  'text: root.stateGlyph' \
  'font.pixelSize: root.mode === "ethernet" ? 14 : 15' \
  'component V2TrafficMeter: Item' \
  'x: 10' \
  'text: "RX"' \
  'text: "TX"'; do
  rg -Fq "$contract" "$widget" \
    || fail "network reference presentation drifted: $contract"
done

v2_meter=$(sed -n '/^  component V2TrafficMeter: Item {$/,/^  }$/p' "$widget")
for source_contract in \
  'color: Qt.rgba(parent.ink.r, parent.ink.g, parent.ink.b, 0.72)' \
  'font.family: root.v2MonoFont' \
  'y: 13' \
  'Behavior on color { ColorAnimation { duration: 160 } }'; do
  grep -Fq "$source_contract" <<<"$v2_meter" \
    || fail "V2 RX/TX meter drifted from source: $source_contract"
done

printf 'network plugin regression passed\n'
