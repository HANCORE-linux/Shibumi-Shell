#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-plugin-update-service.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'plugin update service regression failed: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$tmpdir/control/manager" \
  "$tmpdir/home/.config/omarchy/plugins/hancore.shibumi.control-center/manager" \
  "$tmpdir/runtime"
for catalog_source in PluginUpdateService.qml CatalogDemand.qml CatalogDemandRecord.qml NativeCatalog.qml \
    NativeCatalogCommand.qml NativeCatalogModel.js manager/shibumi-native-catalog; do
  install -Dm0644 "$repo_root/hancore.shibumi.control-center/$catalog_source" \
    "$tmpdir/control/$catalog_source"
done
install -Dm0644 "$repo_root/tests/plugin-update-service-smoke.qml" \
  "$tmpdir/shell.qml"
mkdir -p "$tmpdir/hancore.shibumi.state"
cp -a "$repo_root/hancore.shibumi.state/runtime" "$tmpdir/hancore.shibumi.state/"
printf '{"suiteId":"hancore.shibumi","suitePayloadDigest":"%064d"}\n' 0 \
  > "$tmpdir/hancore.shibumi.state/.shibumi-managed.json"

state_file="$tmpdir/state"
printf '0\n' > "$state_file"
cat > "$tmpdir/control/manager/shibumi-plugin-updates" <<'SH'
#!/bin/bash
set -euo pipefail
state_file=${SHIBUMI_PLUGIN_UPDATE_TEST_STATE:?}
state=$(<"$state_file")
printf '%s\n' "$((state + 1))" > "$state_file"
printf 'PLUGIN_SCAN_EPOCH=%s\n' "${SHIBUMI_PLUGIN_SCAN_EPOCH:-0}"
case $state in
  0)
    sleep 1
    printf '%s\n' \
      'PLUGIN_UPDATE_COUNT=2' \
      'PLUGIN_CHECKED_COUNT=3' \
      'PLUGIN_UNMANAGED_COUNT=1' \
      'PLUGIN_FETCH_FAILED_COUNT=1'
    ;;
  1)
    printf '%s\n' \
      'PLUGIN_UPDATE_COUNT=2' \
      'PLUGIN_CHECKED_COUNT=3' \
      'PLUGIN_UNMANAGED_COUNT=1' \
      'PLUGIN_FETCH_FAILED_COUNT=1'
    ;;
  2)
    printf '%s\n' \
      'PLUGIN_UPDATE_COUNT=1' \
      'PLUGIN_UPDATE_COUNT=1' \
      'PLUGIN_CHECKED_COUNT=1' \
      'PLUGIN_UNMANAGED_COUNT=0' \
      'PLUGIN_FETCH_FAILED_COUNT=0'
    ;;
  3)
    sleep 5
    ;;
  4)
    printf '%s\n' \
      'PLUGIN_UPDATE_COUNT=120' \
      'PLUGIN_CHECKED_COUNT=120' \
      'PLUGIN_UNMANAGED_COUNT=0' \
      'PLUGIN_FETCH_FAILED_COUNT=0'
    ;;
  5|6)
    sleep 5
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$tmpdir/control/manager/shibumi-plugin-updates"
ln -s "$tmpdir/control/manager/shibumi-plugin-updates" \
  "$tmpdir/home/.config/omarchy/plugins/hancore.shibumi.control-center/manager/shibumi-plugin-updates"

set +e
output=$(timeout 8 env \
  HOME="$tmpdir/home" \
  SHIBUMI_PLUGIN_UPDATE_TEST_STATE="$state_file" \
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
grep -Fq 'plugin update service smoke passed' <<<"$output" \
  || fail 'success marker missing'
[[ $(<"$state_file") == 7 ]] || fail 'fixture did not execute all seven scans'

install -Dm0644 "$repo_root/tests/plugin-update-start-failure-smoke.qml" \
  "$tmpdir/shell.qml"
cat > "$tmpdir/control/manager/shibumi-plugin-updates" <<'SH'
#!/bin/bash
printf '%s\n' \
  'PLUGIN_UPDATE_COUNT=0' \
  'PLUGIN_CHECKED_COUNT=1' \
  'PLUGIN_UNMANAGED_COUNT=0' \
  'PLUGIN_FETCH_FAILED_COUNT=0'
SH
chmod +x "$tmpdir/control/manager/shibumi-plugin-updates"
mkdir -p "$tmpdir/retry-bin"
retry_ready="$tmpdir/retry-ready"
(
  /usr/bin/sleep 1.4
  /usr/bin/ln -s /usr/bin/timeout "$tmpdir/retry-bin/timeout"
  printf 'ready\n' > "$retry_ready"
) &
retry_preparer=$!
set +e
start_output=$(/usr/bin/timeout 7 /usr/bin/env \
  PATH="$tmpdir/retry-bin" \
  HOME="$tmpdir/home" \
  SHIBUMI_START_RETRY_READY="$retry_ready" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
start_rc=$?
wait "$retry_preparer" 2>/dev/null || true
set -e
printf '%s\n' "$start_output"
[[ $start_rc -eq 0 ]] || fail "start-failure Quickshell exited $start_rc"
grep -Fq 'plugin update start failure settled and retry passed' <<<"$start_output" \
  || fail 'start-failure retry marker missing'
if grep -Eq 'TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign|Internal error' \
    <<<"$start_output"; then
  fail 'start-failure retry emitted a QML runtime error'
fi

printf 'plugin update service regression passed\n'
