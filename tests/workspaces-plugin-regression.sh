#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-workspaces.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'workspaces plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"
cmp -s "$repo_root/services/WorkspaceModel.js" \
  "$repo_root/hancore.shibumi.workspaces/WorkspaceModel.js" \
  || fail "standalone and plugin workspace models drifted"

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

for v2_style in kanji rings aurora pacman; do
  rg -Fq "root.renderStyle === \"$v2_style\"" \
    "$repo_root/hancore.shibumi.workspaces/BarWidget.qml" \
    || fail "V2 workspace style is missing: $v2_style"
done
pacman_marker="$repo_root/shared/presentation/PacmanWorkspaceMarker.qml"
rg -Fq 'text: root.focused ? "󰮯" : "󰊠"' \
  "$pacman_marker" \
  || fail "Pacman/ghost state glyphs drifted from the V2.1-2 reference"
rg -Fq 'id: emptyPellet' "$pacman_marker" \
  || fail "Pacman empty workspace pellet is missing"
rg -Fq 'visible: !root.focused && !root.occupied' "$pacman_marker" \
  || fail "Pacman pellet no longer represents empty workspaces"
rg -Fq 'readonly property int pelletSize: Commons.Style.space(5)' \
  "$pacman_marker" \
  || fail "Pacman empty workspace pellet does not follow theme scaling"
rg -Fq 'font.pixelSize: root.glyphSize' "$pacman_marker" \
  || fail "Pacman glyph does not follow theme scaling"
rg -Fq 'font.family: "JetBrainsMono Nerd Font"' "$pacman_marker" \
  || fail "Pacman marker does not use the reference Nerd Font"
rg -Fq 'paletteColor("color03"' \
  "$repo_root/hancore.shibumi.workspaces/BarWidget.qml" \
  || fail "Pacman does not follow the colors.toml yellow role"
for neutral_contract in \
    'readonly property color pacmanOccupiedColor: widgetInk' \
    'readonly property color pacmanEmptyColor: widgetInk' \
    'readonly property color pacmanHoverColor: widgetInk'; do
  rg -Fq "$neutral_contract" \
    "$repo_root/hancore.shibumi.workspaces/BarWidget.qml" \
    || fail "Pacman ghosts do not follow the selected bar color: $neutral_contract"
done
if rg -q 'paletteColor\("color0[16]"' \
    "$repo_root/hancore.shibumi.workspaces/BarWidget.qml"; then
  fail "Pacman ghosts still use dedicated colors.toml accents"
fi
for motion_contract in \
    'id: pacmanTravel' \
    'property: "pacmanTravelX"' \
    'property: "pacmanMouthClosure"' \
    'property: "pacmanEatProgress"' \
    'property int pacmanTravelSteps: 1' \
    'Math.min(720, 320 + pacmanTravelSteps * 100)' \
    'readonly property real pacmanMaxMouthClosure: 0.82' \
    'loops: root.pacmanBiteCount' \
    'id: pacmanRunnerGlyph' \
    'text: "󰮯"' \
    'id: pacmanMouthFill' \
    'context.arc(centerX, centerY, radius' \
    'readonly property int pacmanEatDuration: 240' \
    'root.finishPacmanTravel()'; do
  rg -Fq "$motion_contract" \
    "$repo_root/hancore.shibumi.workspaces/BarWidget.qml" \
    || fail "Pacman eat animation is missing: $motion_contract"
done
rg -Fq 'readonly property real numberMarkerRadius:' \
  "$repo_root/hancore.shibumi.workspaces/BarWidget.qml" \
  || fail "workspace widget does not expose the V1/V2 number radius contract"
rg -Fq 'readonly property real frameMarkerRadius:' \
  "$repo_root/hancore.shibumi.workspaces/BarWidget.qml" \
  || fail "workspace widget does not expose the V1/V2 frame radius contract"
if rg -Fq 'readonly property string versionStyle:' \
    "$repo_root/hancore.shibumi.workspaces/BarWidget.qml"; then
  fail "workspace widget still downgrades shared styles in V1"
fi
if rg -q 'root\.renderStyle === "(frame|aurora-streak)"' \
    "$repo_root/hancore.shibumi.workspaces/BarWidget.qml"; then
  fail "non-reference workspace style remains in the Shibumi renderer"
fi

printf 'workspaces plugin regression passed\n'
