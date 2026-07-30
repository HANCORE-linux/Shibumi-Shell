#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/home/hancore/Projects/omarchy-updates-pr}
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-workspaces.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'workspaces plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.workspaces" "$tmpdir/workspaces"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/workspaces-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/WorkspaceTestPanel.qml" \
  "$tmpdir/WorkspaceTestPanel.qml"

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
grep -F 'workspaces plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

rg -q 'serviceFor\("hancore\.shibumi\.workspaces"\)' \
  "$repo_root/hancore.shibumi.workspaces/BarWidget.qml" \
  || fail "bar widget does not resolve the shared workspace service"
if rg -q 'bar\.(workspaceService|workspaceActions)' \
    "$repo_root/hancore.shibumi.workspaces"; then
  fail "workspace plugin depends on transitional bar-owned feature state"
fi
rg -q '^import Quickshell\.Hyprland$' \
  "$repo_root/hancore.shibumi.workspaces/WorkspaceService.qml" \
  || fail "workspace service does not own the Hyprland model"
rg -q 'launcher\.command = command' \
  "$repo_root/hancore.shibumi.workspaces/WorkspaceActions.qml" \
  || fail "workspace action is not passed as an argument vector"
if rg -q 'bash|-c|bar\.run' \
    "$repo_root/hancore.shibumi.workspaces/WorkspaceActions.qml"; then
  fail "workspace action crosses a shell or bar-command boundary"
fi
rg -q 'contentWidth: fittedContentWidth\(240\)' \
  "$repo_root/hancore.shibumi.workspaces/WorkspacePanel.qml" \
  || fail "workspace panel does not retain the compact V1 width"
rg -q 'height: 30' \
  "$repo_root/hancore.shibumi.workspaces/WorkspacePanelContent.qml" \
  || fail "workspace rows do not retain the compact V1 height"

for v2_style in kanji rings aurora; do
  rg -Fq "root.renderStyle === \"$v2_style\"" \
    "$repo_root/hancore.shibumi.workspaces/BarWidget.qml" \
    || fail "V2 workspace style is missing: $v2_style"
done
if rg -q 'root\.renderStyle === "(frame|aurora-streak)"' \
    "$repo_root/hancore.shibumi.workspaces/BarWidget.qml"; then
  fail "non-reference workspace style remains in the Shibumi renderer"
fi

printf 'workspaces plugin regression passed\n'
