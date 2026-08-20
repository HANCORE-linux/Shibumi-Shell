#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-notification-adapter.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'notification adapter regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell/Commons ]] || fail "Omarchy Commons not found"
[[ -d $omarchy_path/shell/Ui ]] || fail "Omarchy Ui not found"
[[ -x $quickshell_bin ]] || fail "Quickshell not found"

mkdir -p "$tmpdir/runtime" "$tmpdir/status"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.status/." "$tmpdir/status/"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
cp -- "$repo_root/tests/notification-adapter-smoke.qml" "$tmpdir/shell.qml"

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

[[ $rc -eq 0 ]] || fail "smoke exited $rc"
grep -Fq 'notification adapter smoke passed' <<<"$output" \
  || fail 'success marker missing'
if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load' \
    <<<"$output"; then
  fail 'runtime log contains a composition error'
fi

printf 'notification adapter regression passed\n'
