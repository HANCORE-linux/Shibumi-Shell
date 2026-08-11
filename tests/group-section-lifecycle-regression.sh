#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
fixture_root=""

fail() {
  printf 'group section lifecycle regression failed: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z $fixture_root ]] || rm -rf -- "$fixture_root"
}
trap cleanup EXIT

[[ -x $quickshell_bin ]] || fail "Quickshell executable is missing: $quickshell_bin"
[[ -d $omarchy_path/shell/Commons ]] \
  || fail "Omarchy Commons tree is missing: $omarchy_path/shell/Commons"
command -v timeout >/dev/null 2>&1 || fail "timeout is required"

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/shibumi-group-lifecycle.XXXXXX")
mkdir -p "$fixture_root"/{home,config,cache,data,state,runtime,fixture}
chmod 700 "$fixture_root/runtime"
cp -a "$repo_root/core" "$repo_root/styles" "$fixture_root/fixture/"
cp -a "$omarchy_path/shell/Commons" "$fixture_root/fixture/"
cp "$repo_root/tests/incidents/inc012/SectionHost.qml" "$fixture_root/fixture/"

run_mode() {
  local mode=$1 vertical=$2 label output_file rc
  label="$mode-vertical-$vertical"
  output_file="$fixture_root/$label.log"

  cp "$repo_root/tests/incidents/inc012/$mode-shell.qml" \
    "$fixture_root/fixture/shell.qml"

  set +e
  timeout --signal=TERM --kill-after=10 40 env \
    -u WAYLAND_DISPLAY \
    -u HYPRLAND_INSTANCE_SIGNATURE \
    -u QS_CONFIG_PATH \
    HOME="$fixture_root/home" \
    XDG_CONFIG_HOME="$fixture_root/config" \
    XDG_CACHE_HOME="$fixture_root/cache" \
    XDG_DATA_HOME="$fixture_root/data" \
    XDG_STATE_HOME="$fixture_root/state" \
    XDG_RUNTIME_DIR="$fixture_root/runtime" \
    OMARCHY_PATH="$omarchy_path" \
    SHIBUMI_TEST_VERTICAL="$vertical" \
    QT_QPA_PLATFORM=offscreen \
    QT_QPA_PLATFORMTHEME= \
    QSG_RHI_BACKEND=software \
    "$quickshell_bin" -p "$fixture_root/fixture" --no-color \
    >"$output_file" 2>&1
  rc=$?
  set -e

  if (( rc != 0 )); then
    cat "$output_file" >&2
    fail "$label matrix exited $rc"
  fi
  if ! grep -Fq "INC012_COMPLETE $mode" "$output_file"; then
    cat "$output_file" >&2
    fail "$label matrix did not complete"
  fi
  if grep -Eiq \
      'TypeError|ReferenceError|Cannot read propert(y|ies).*null|QQmlVMEMetaObject: Internal error|INC012_HARNESS_ERROR' \
      "$output_file"; then
    cat "$output_file" >&2
    fail "$label matrix emitted a teardown error"
  fi
}

run_mode direct 0
run_mode async 0
run_mode async 1
printf 'GroupSection lifecycle regression passed (%s)\n' \
  "$($quickshell_bin --version 2>&1 | head -1)"
