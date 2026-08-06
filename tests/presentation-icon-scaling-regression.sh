#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-presentation-scaling.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'presentation icon scaling regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/gpu" "$tmpdir/presentation"
chmod 700 "$tmpdir/runtime"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
install -m 0644 "$repo_root/hancore.shibumi.gpu/GpuCardIcon.qml" \
  "$tmpdir/gpu/GpuCardIcon.qml"
install -m 0644 "$repo_root/shared/presentation/PacmanWorkspaceMarker.qml" \
  "$tmpdir/presentation/PacmanWorkspaceMarker.qml"
install -m 0644 "$repo_root/tests/presentation-icon-scaling-smoke.qml" \
  "$tmpdir/shell.qml"

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
grep -F 'presentation icon scaling smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

printf 'presentation icon scaling regression passed\n'
