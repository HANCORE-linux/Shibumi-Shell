#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline

fail() {
  printf 'panel window geometry regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -x /usr/bin/quickshell ]] || fail '/usr/bin/quickshell is required'
[[ -x /usr/bin/python3 ]] || fail '/usr/bin/python3 is required'
keyboard_panel="$OMARCHY_PATH/shell/Ui/KeyboardPanel.qml"
[[ -f $keyboard_panel ]] || fail 'pinned KeyboardPanel.qml is missing'
[[ $(sha256sum "$keyboard_panel" | awk '{print $1}') == \
  96245f2da8d38baa0017caa285d596c485bd19a3a4d2cd1675bee9d84ffba42d ]] \
  || fail 'KeyboardPanel.qml does not match pinned Omarchy v4.0.3 source'
printf 'PINNED_KEYBOARD_PANEL source=%s sha256=%s\n' \
  "$SHIBUMI_OMARCHY_SOURCE_REVISION" \
  '96245f2da8d38baa0017caa285d596c485bd19a3a4d2cd1675bee9d84ffba42d'

/usr/bin/python3 -I - "$repo_root" <<'PY'
import hashlib
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
expected = {
    "hancore.shibumi.ai/AiUsagePanel.qml": "215bc466aff11b593c9731a13e90316b1702aeed19d696654e8f0f555a12f946",
    "hancore.shibumi.audio/AudioPanel.qml": "fedbe78ccc91b1e86764eaa5234f64b1f2519555b47cc6043ded86e6127d7d4e",
    "hancore.shibumi.battery/BatteryPanel.qml": "46f3fad436b76672cb1344822f40f6441a95d166aee66ba4ee1b8877d7daf6f9",
    "hancore.shibumi.bluetooth/BluetoothPanel.qml": "44a5f3dd0346cf31ec470f783a46b97fd7dffbc4aa2e97cc6f8fabee533988fa",
    "hancore.shibumi.brightness/BrightnessPanel.qml": "44a5f3dd0346cf31ec470f783a46b97fd7dffbc4aa2e97cc6f8fabee533988fa",
    "hancore.shibumi.center/CalendarPanel.qml": "4c4b6cd37c2284166e5f06bd037d1173952a855c6a8be91e45b9c359c8cd18f2",
    "hancore.shibumi.center/WeatherPanel.qml": "ed9571177bf7690969eab4cb71746caedd3442722ae472b9bc6e8c430f49f818",
    "hancore.shibumi.control-center/ControlCenterPanel.qml": "c94871647554290ab86a21b2184c95525934be5cacf5b8e28ebcde7645323f26",
    "hancore.shibumi.cpu/CpuPanel.qml": "c8bd3c667882561c857c55b7b7e98345219c33cf4437d7040e38c0ff8c9a8009",
    "hancore.shibumi.gpu/GpuPanel.qml": "0fca054d78877aafb9844f608a76a79b5f6ef6189421c1b85b1afa8b726f4568",
    "hancore.shibumi.media/MediaPanel.qml": "11209c97c06d1dd0a7a9baf4a6b4d447fc038ec5525a2fe7f2c9460cc91a9f76",
    "hancore.shibumi.memory/MemoryPanel.qml": "c8bd3c667882561c857c55b7b7e98345219c33cf4437d7040e38c0ff8c9a8009",
    "hancore.shibumi.network/NetworkPanel.qml": "c678e7f266f8a3570e78f7ee268fd0f77ddec4594d829035449dda05dfcb059c",
    "hancore.shibumi.power-profile/PowerProfilePanel.qml": "c350266a42d45effecafc8c2b00f131995afcb722103568893e0181eac2e65a9",
    "hancore.shibumi.status/NotificationPanel.qml": "7cf613c857a6d693627f04818cab0e531db0cf7d0b297dd164a5ed91328e5028",
    "hancore.shibumi.status/TrayAppMenuPanel.qml": "a598a319bb1f0026dc04818eb4d38efb4c707118e3cb57b4521b3a37547e0ca2",
    "hancore.shibumi.status/TrayDrawerPanel.qml": "cacc5af5542ffa68b1e7c4badb6c6eaa6bf107b5e712f7f70d5d478e5b515005",
    "hancore.shibumi.storage/StoragePanel.qml": "d2be53979ea4b18ccaeb4793d003dd5283912520e773abea3ac3fa4d320806ea",
    "hancore.shibumi.temperature/TemperaturePanel.qml": "11209c97c06d1dd0a7a9baf4a6b4d447fc038ec5525a2fe7f2c9460cc91a9f76",
    "hancore.shibumi.update-center/UpdateCenterPanel.qml": "5e0b6b0fd3acf36c0e8939a2690fc48604d9b1529a478398dd496a8528c06f2b",
    "hancore.shibumi.workspaces/WorkspacePanel.qml": "20e29863f8899f892940842544d98bad977d9fd8cbe0ba1482835ec3319f8db5",
}
keys = (
    "anchorWindowH", "barH", "cardOrigin", "centerOnBar",
    "centerOnBarOffset", "contentHeight", "contentWidth", "height",
    "padding", "width", "x", "y",
)
found = {}
centered = 0
for path in sorted(repo.glob("hancore.shibumi.*/*Panel.qml")):
    if path.name == "ShibumiPanel.qml":
        continue
    text = path.read_text(encoding="utf-8")
    if not re.search(r"^ShibumiPanel \{", text, re.MULTILINE):
        continue
    lines = text.splitlines()
    chunks = []
    index = 0
    pattern = re.compile(r"^  (" + "|".join(keys) + r"):\s*(.*)$")
    while index < len(lines):
        match = pattern.match(lines[index])
        if not match:
            index += 1
            continue
        chunk = [lines[index]]
        if match.group(1) == "centerOnBar" and match.group(2).strip() == "true":
            centered += 1
        index += 1
        while index < len(lines) and (lines[index].startswith("    ") or not lines[index].strip()):
            chunk.append(lines[index])
            index += 1
        chunks.append("\n".join(chunk).rstrip())
    payload = ("\n".join(chunks) + "\n").encode()
    found[str(path.relative_to(repo))] = hashlib.sha256(payload).hexdigest()
if found != expected:
    missing = sorted(set(expected) - set(found))
    extra = sorted(set(found) - set(expected))
    drift = sorted(key for key in expected if key in found and expected[key] != found[key])
    raise SystemExit(
        "panel definition geometry drift: "
        f"missing={missing} extra={extra} changed={drift}"
    )
if centered != 2:
    raise SystemExit(f"centered panel count drifted: {centered}")
print("PANEL_DEFINITION_GEOMETRY_PASS count=21 anchored=19 centered=2")
PY

"$repo_root/scripts/sync-shared.sh" --check >/dev/null

# Bind the focused gate to the real bar source as well as the synthetic anchors.
rg -Fq 'implicitHeight: !bar.vertical && validScreen ? bar.barSize : 0' \
  "$repo_root/hancore.shibumi.bar/core/BarPanel.qml" \
  || fail 'BarPanel source is not bar-height'
rg -Fq 'implicitWidth: bar.vertical && validScreen ? bar.barSize : 0' \
  "$repo_root/hancore.shibumi.bar/core/BarPanel.qml" \
  || fail 'BarPanel source is not bar-width'

tmpdir=$(mktemp -d /tmp/shibumi-panel-geometry.XXXXXX)
active_pid=
cleanup_group() {
  local pid=${1:-}
  [[ -n $pid ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM -- "-$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.05
    done
    kill -KILL -- "-$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}
cleanup() {
  cleanup_group "$active_pid"
  rm -rf -- "$tmpdir"
}
trap cleanup EXIT HUP INT TERM

base="$tmpdir/base"
mkdir -p "$base/fixtures" "$base/shared" "$base/hancore.shibumi.bar/core"
cp -a -- "$OMARCHY_PATH/shell/Commons" "$base/"
cp -a -- "$OMARCHY_PATH/shell/Ui" "$base/"
cp -- "$repo_root/hancore.shibumi.bar/core/WidgetSlot.qml" \
  "$base/hancore.shibumi.bar/core/"
cp -- "$repo_root/tests/fixtures/FixturePanelWindow.qml" \
  "$repo_root/tests/fixtures/ProviderBoundHostedPanelWidget.qml" "$base/fixtures/"
cp -- "$repo_root/shared/presentation/ShibumiPanel.qml" "$base/shared/"
cp -- "$repo_root/tests/panel-window-geometry-smoke.qml" "$base/shell.qml"

/usr/bin/python3 -I - "$base" <<'PY'
import re
import sys
from pathlib import Path

base = Path(sys.argv[1])
fixture = base / "fixtures/FixturePanelWindow.qml"

def platform_stub(path, expected_windows, expected_edges, expected_layer_lines):
    text = path.read_text(encoding="utf-8")
    if text.count("PanelWindow {") != expected_windows:
        raise SystemExit(f"PanelWindow count drifted in {path}")
    text = text.replace("PanelWindow {", "FixturePanelWindow {")
    screen_binding = "  screen: anchorWindow ? anchorWindow.screen : null\n"
    if text.count(screen_binding) != 1:
        raise SystemExit(f"anchor screen binding drifted in {path}")
    # QQuickWindow's screen type cannot accept QuickshellScreenInfo. The
    # offscreen component stub keeps its own default screen; no geometry,
    # card, holder, or fitted-height implementation is replaced.
    text = text.replace(screen_binding, "")
    edge = re.compile(
        r"(?m)^(?P<i>\s*)anchors \{\n(?P=i)  top: true\n(?P=i)  bottom: true\n"
        r"(?P=i)  left: true\n(?P=i)  right: true\n(?P=i)\}"
    )
    text, count = edge.subn(
        lambda match: match.group("i") + "width: root.screenW\n"
        + match.group("i") + "height: root.screenH",
        text,
    )
    if count != expected_edges:
        raise SystemExit(f"edge-anchor count drifted in {path}: {count}")
    filtered = []
    focus_indent = None
    removed = 0
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        indentation = len(line) - len(line.lstrip())
        if focus_indent is not None:
            if stripped and indentation > focus_indent:
                removed += 1
                continue
            focus_indent = None
        if stripped.startswith("WlrLayershell.namespace:") or stripped.startswith("WlrLayershell.layer:"):
            removed += 1
            continue
        if line == "        screen: modelData\n":
            continue
        if stripped.startswith("WlrLayershell.keyboardFocus:"):
            removed += 1
            if stripped.endswith("open"):
                focus_indent = indentation
            continue
        filtered.append(line)
    if removed != expected_layer_lines:
        raise SystemExit(f"layer-shell line count drifted in {path}: {removed}")
    path.write_text("".join(filtered), encoding="utf-8")

platform_stub(base / "Ui/KeyboardPanel.qml", 2, 2, 8)
platform_stub(base / "shared/ShibumiPanel.qml", 1, 1, 6)
for directory in (base / "Ui", base / "shared"):
    (directory / "FixturePanelWindow.qml").write_bytes(fixture.read_bytes())
    qmldir = directory / "qmldir"
    current = qmldir.read_text(encoding="utf-8") if qmldir.exists() else ""
    if "FixturePanelWindow 1.0 FixturePanelWindow.qml" not in current:
        qmldir.write_text(current + "\nFixturePanelWindow 1.0 FixturePanelWindow.qml\n", encoding="utf-8")
PY

run_case() {
  local name=$1 expected=$2 diagnostic=$3
  local root="$tmpdir/$name"
  cp -a -- "$base" "$root"
  mkdir -p "$root/home/.config" "$root/home/.local/state" \
    "$root/home/.local/share" "$root/home/.cache" "$root/run" \
    "$root/tmp" "$root/data" "$root/bin"
  chmod 700 "$root/home" "$root/run" "$root/tmp"
  printf '#!/bin/sh\nexit 97\n' > "$root/bin/hyprctl"
  cp "$root/bin/hyprctl" "$root/bin/fc-match"
  chmod 700 "$root/bin/hyprctl" "$root/bin/fc-match"

  # This changes a fixture anchor, not the production BarPanel implementation.
  if [[ $name == synthetic-screen-height-control ]]; then
    /usr/bin/python3 -I - "$root/shell.qml" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "property int nativeAnchorHeight: 35"
if text.count(old) != 1:
    raise SystemExit("fullscreen anchor mutant drifted")
path.write_text(text.replace(old, "property int nativeAnchorHeight: 800"), encoding="utf-8")
PY
  elif [[ $name == provider-height-override-source-mutant ]]; then
    /usr/bin/python3 -I - "$root/hancore.shibumi.bar/core/WidgetSlot.qml" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
anchor = "  Binding {\n    target: root.compatibilityPanel\n    property: \"borderSpec\""
mutant = """  // Calibrated retired behavior: a host binding replaces provider height.\n  Binding {\n    target: root.compatibilityPanel\n    property: \"contentHeight\"\n    value: 999\n    when: root.hostPanelChromeEnabled\n  }\n\n"""
if text.count(anchor) != 1:
    raise SystemExit("measurement repair mutant drifted")
path.write_text(text.replace(anchor, mutant + anchor), encoding="utf-8")
PY
  fi

  local log="$root/output.log" rc=124
  setsid /usr/bin/env -i \
    HOME="$root/home" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    XDG_CONFIG_HOME="$root/home/.config" \
    XDG_STATE_HOME="$root/home/.local/state" \
    XDG_DATA_HOME="$root/home/.local/share" \
    XDG_CACHE_HOME="$root/home/.cache" XDG_DATA_DIRS="$root/data" \
    XDG_RUNTIME_DIR="$root/run" TMPDIR="$root/tmp" PATH="$root/bin" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$root/run/no-session" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$root/run/no-system" \
    HYPRLAND_INSTANCE_SIGNATURE= WAYLAND_DISPLAY= DISPLAY= \
    PIPEWIRE_REMOTE=shibumi-panel-fixture-absent \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
    QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    QML_DISABLE_DISK_CACHE=1 \
    /usr/bin/quickshell -p "$root" >"$log" 2>&1 &
  active_pid=$!
  for _ in $(seq 1 240); do
    if ! kill -0 "$active_pid" 2>/dev/null; then
      set +e
      wait "$active_pid"
      rc=$?
      set -e
      break
    fi
    sleep 0.05
  done
  if kill -0 "$active_pid" 2>/dev/null; then
    printf 'fixture deadline\n' >>"$log"
    cleanup_group "$active_pid"
    rc=124
  fi
  local pgid=$active_pid
  active_pid=
  local survivors
  survivors=$(ps -eo pgid=,pid= | awk -v pg="$pgid" '$1 == pg { print $2 }')
  if [[ -n $survivors ]]; then
    kill -KILL -- "-$pgid" 2>/dev/null || true
    fail "$name left owned process-group members: $survivors"
  fi

  printf '%s\n' "--- $name rc=$rc cleanup=owned-pgid-empty ---"
  cat "$log"
  if [[ $expected == pass ]]; then
    [[ $rc -eq 0 ]] || fail "$name exited $rc"
    grep -Fq "$diagnostic" "$log" || fail "$name missed success marker"
    grep -Fq 'PINNED_KEYBOARD_PANEL_COMPONENT_CASES' "$log" \
      || fail "$name missed component coverage marker"
    if grep -q 'NATIVE_' "$log"; then
      fail "$name incorrectly labels component evidence as native"
    fi
    if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load' "$log"; then
      fail "$name emitted a composition error"
    fi
  else
    [[ $rc -ne 0 ]] || fail "$name unexpectedly passed"
    grep -Fq "$diagnostic" "$log" || fail "$name missed calibrated failure: $diagnostic"
  fi
}

run_case synthetic-screen-height-control fail \
  'fixture anchor window height drifted: 800/800'
run_case provider-height-override-source-mutant fail \
  'Basecamp/HEY main provider binding was not 278+30=308: 999/999'
run_case current pass \
  'PANEL_WINDOW_GEOMETRY_PASS component-stub-not-native-wayland'
printf 'panel window geometry regression passed (2 negative controls, 1 current component stub)\n'
