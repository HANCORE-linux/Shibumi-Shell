#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
source "$repo_root/tests/lib/qs-runner.sh"
shibumi_load_omarchy_baseline

fail() {
  printf 'scoped loader admission regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -x ${QUICKSHELL_BIN:-/usr/bin/quickshell} ]] || fail 'quickshell is required'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
[[ -n ${OMARCHY_PATH:-} && -d $OMARCHY_PATH/shell/Commons ]] \
  || fail 'OMARCHY_PATH must reference an admitted Quattro tree'

tmpdir=$(mktemp -d /tmp/shibumi-scoped-loader.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
prepare_fixture() {
  local variant=$1
  local fixture_dir="$tmpdir/$variant"
  mkdir -p "$fixture_dir/home" "$fixture_dir/runtime" \
    "$fixture_dir/fixtures" "$fixture_dir/hancore.shibumi.bar/core" \
    "$fixture_dir/hancore.shibumi.bar/services"
  chmod 700 "$fixture_dir/runtime"
  cp -a "$OMARCHY_PATH/shell/Commons" "$fixture_dir/"
  cp "$repo_root/hancore.shibumi.bar/core/"{WidgetSlot.qml,GroupRegistry.js} \
    "$fixture_dir/hancore.shibumi.bar/core/"
  cp "$repo_root/hancore.shibumi.bar/services/HostWidgetResolver.qml" \
    "$fixture_dir/hancore.shibumi.bar/services/"
  cp "$repo_root/tests/scoped-loader-admission-regression.qml" \
    "$fixture_dir/shell.qml"
  printf '%s\n' 'import QtQuick' 'Item { property string broken: }' \
    > "$fixture_dir/fixtures/ScopedLoaderBroken.qml"
  printf '%s\n' "$fixture_dir"
}

install_stale_direct_source_mutant() {
  local source_path=$1
  python3 - "$source_path" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
fixed = """    if (resolvedComponent !== nextSource) {
      requestLoaderSourceSync()
      return
    }
"""
mutant = """    if (false) {
      requestLoaderSourceSync()
      return
    }
"""
if source.count(fixed) != 1:
    raise SystemExit("direct source revalidation was not found exactly once")
path.write_text(source.replace(fixed, mutant))
PY
}

run_fixture() {
  local variant=$1
  local expected_rc=$2
  local expected_marker=$3
  local fixture_dir
  local output
  local rc

  fixture_dir=$(prepare_fixture "$variant")
  if [[ $variant == stale-direct-source ]]; then
    # Mutate only the private copy. This lets a superseded direct binding reach
    # the Loader after reentrant completion invalidation.
    install_stale_direct_source_mutant \
      "$fixture_dir/hancore.shibumi.bar/core/WidgetSlot.qml"
  fi

  local -a qs_fixture_env=(
    HOME="$fixture_dir/home" \
    XDG_CONFIG_HOME="$fixture_dir/home/.config" \
    XDG_STATE_HOME="$fixture_dir/home/.local/state" \
    XDG_DATA_HOME="$fixture_dir/home/.local/share" \
    XDG_CACHE_HOME="$fixture_dir/home/.cache" \
    XDG_DATA_DIRS="$fixture_dir/data" \
    XDG_RUNTIME_DIR="$fixture_dir/runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$fixture_dir/absent-session" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$fixture_dir/absent-system" \
    HYPRLAND_INSTANCE_SIGNATURE= WAYLAND_DISPLAY= DISPLAY= \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
    QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    QML_DISABLE_DISK_CACHE=1 \
  )
  local -a qs_fixture_args=(--no-color)
  set +e
  qs_run_fixture "$fixture_dir/shell.qml" "$fixture_dir" 12 >"$fixture_dir/output.log" 2>&1
  rc=$?
  set -e
  output=$(<"$fixture_dir/output.log")
  printf '%s\n' "$output"

  [[ $rc -eq $expected_rc ]] \
    || fail "$variant fixture exited $rc instead of $expected_rc"
  grep -q "$expected_marker" <<<"$output" \
    || fail "$variant fixture did not reach its expected marker"
  # The deliberately malformed asynchronous QML source must produce
  # Loader.Error. Rejected non-Components must never reach the typed property.
  if grep -Eqi 'Unable to assign|Cannot assign|expected (type )?QQmlComponent|Binding loop|TypeError|ReferenceError' \
      <<<"$output"; then
    fail "$variant log contains an assignment, binding, or JavaScript error"
  fi
}

run_fixture stale-direct-source 1 \
  'invalidation reentry dispatched stale source B'
run_fixture candidate 0 'scoped loader admission regression passed'
