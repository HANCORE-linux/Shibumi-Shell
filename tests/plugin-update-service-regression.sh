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
install -Dm0644 \
  "$repo_root/hancore.shibumi.control-center/PluginUpdateService.qml" \
  "$tmpdir/control/PluginUpdateService.qml"
install -Dm0644 "$repo_root/tests/plugin-update-service-smoke.qml" \
  "$tmpdir/shell.qml"

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
  5)
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
[[ $(<"$state_file") == 6 ]] || fail 'fixture did not execute all six scans'

printf 'plugin update service regression passed\n'
