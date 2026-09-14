#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-quick-access-plugin.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'quick access plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

expected_action_warnings=$'Shibumi wallpaper action failed: Could not apply broken.jpg. denied by fixture\nShibumi theme action failed: Could not apply broken-theme. theme denied by fixture'
expected_notifications=$'-a\nShibumi\nWallpaper change failed\nCould not apply broken.jpg. denied by fixture\n-a\nShibumi\nTheme change failed\nCould not apply broken-theme. theme denied by fixture'

stage_fixture() {
  local fixture_root=$1
  mkdir -p "$fixture_root/runtime" "$fixture_root/bin" \
    "$fixture_root/barcore" "$fixture_root/images" "$fixture_root/home" \
    "$fixture_root/config" "$fixture_root/state" "$fixture_root/cache" \
    "$fixture_root/data"
  chmod 700 "$fixture_root/runtime" "$fixture_root/home" \
    "$fixture_root/config" "$fixture_root/state" "$fixture_root/cache" \
    "$fixture_root/data"
  shibumi_stage_suite_runtime "$repo_root" "$fixture_root"
  cat >"$fixture_root/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$SHIBUMI_NOTIFY_LOG"
EOF
  cat >"$fixture_root/bin/readlink" <<'EOF'
#!/usr/bin/env bash
# Keep the controlled current-wallpaper worker alive until the screen-removal
# case terminates it. exec ensures QProcess owns the only process involved.
exec /usr/bin/sleep 30
EOF
  chmod 700 "$fixture_root/bin/notify-send" "$fixture_root/bin/readlink"
  cp -a -- "$repo_root/hancore.shibumi.quick-access" \
    "$fixture_root/quickaccess"
  cp -a -- "$omarchy_path/shell/Commons" "$fixture_root/Commons"
  install -m 0644 "$repo_root/hancore.shibumi.bar/core/WidgetSlot.qml" \
    "$fixture_root/barcore/WidgetSlot.qml"
  # The fixture exercises the production overlay body without creating a real
  # layer surface. Only the window-shell-only properties are removed.
  python3 -I -S - "$fixture_root/quickaccess/PickerOverlay.qml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
replacements = {
    "PanelWindow {": "Item {",
    "  screen: controller.activeScreen\n": "",
    "  anchors { top: true; bottom: true; left: true; right: true }\n": "",
    "  color: \"transparent\"\n": "",
    "  exclusionMode: ExclusionMode.Ignore\n": "",
    "  WlrLayershell.namespace: \"shibumi-picker\"\n": "",
    "  WlrLayershell.layer: WlrLayer.Overlay\n": "",
    "  WlrLayershell.keyboardFocus: visible\n    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n": "",
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f"unexpected PickerOverlay fixture source: {old!r}")
    text = text.replace(old, new)
path.write_text(text, encoding="utf-8")
PY
  # Use real, private PNGs so active image delegates exercise decoding without
  # reading arbitrary /tmp paths or producing missing-image warnings.
  python3 -I -S - "$fixture_root/images" <<'PY'
from pathlib import Path
import struct
import sys
import zlib

image_dir = Path(sys.argv[1])

def chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))

for index in range(100):
    pixel = bytes((0, (index * 37) % 256, (index * 67) % 256,
                   (index * 97) % 256))
    image = (b"\x89PNG\r\n\x1a\n"
             + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
             + chunk(b"IDAT", zlib.compress(pixel))
             + chunk(b"IEND", b""))
    for prefix in ("source", "thumb"):
        path = image_dir / f"{prefix}-{index}.png"
        path.write_bytes(image)
        path.chmod(0o644)
PY
  install -m 0644 "$repo_root/tests/quick-access-plugin-smoke.qml" \
    "$fixture_root/shell.qml"
}

run_smoke() {
  local fixture_root=$1
  : >"$fixture_root/notify.log"
  set +e
  RUN_OUTPUT=$(timeout 8 env \
    HOME="$fixture_root/home" \
    XDG_CONFIG_HOME="$fixture_root/config" \
    XDG_STATE_HOME="$fixture_root/state" \
    XDG_CACHE_HOME="$fixture_root/cache" \
    XDG_DATA_HOME="$fixture_root/data" \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    PATH="$fixture_root/bin:$PATH" \
    SHIBUMI_NOTIFY_LOG="$fixture_root/notify.log" \
    SHIBUMI_QUICK_ACCESS_IMAGE_DIR="$fixture_root/images" \
    XDG_RUNTIME_DIR="$fixture_root/runtime" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$fixture_root" 2>&1)
  RUN_RC=$?
  set -e
  RUN_PLAIN_OUTPUT=$(sed $'s/\033\\[[0-9;]*m//g' <<<"$RUN_OUTPUT")
  RUN_WARNINGS=$(sed -n -E \
    's/^[[:space:]]*WARN([^:]*)?:[[:space:]]*//p' <<<"$RUN_PLAIN_OUTPUT")
}

validate_common_completion() {
  local label=$1
  [[ $RUN_RC -eq 0 ]] || fail "$label component smoke exited $RUN_RC"
  grep -F 'quick access plugin smoke passed' <<<"$RUN_PLAIN_OUTPUT" >/dev/null \
    || fail "$label success marker missing"
  if grep -Eq '(^|[[:space:]])(ERROR|CRITICAL)([[:space:]]|:)|ReferenceError|Binding loop|Cannot assign|Internal error|quick-access-plugin-smoke:' \
      <<<"$RUN_PLAIN_OUTPUT"; then
    fail "$label emitted an unrelated QML runtime diagnostic"
  fi
}

validate_notifications() {
  local fixture_root=$1 label=$2 actual=""
  for _ in {1..20}; do
    actual=$(<"$fixture_root/notify.log")
    [[ $actual == "$expected_notifications" ]] && break
    sleep 0.05
  done
  [[ $actual == "$expected_notifications" ]] \
    || fail "$label action-failure notifications did not match exactly"
}

validate_positive() {
  local fixture_root=$1 label=$2
  validate_common_completion "$label"
  [[ $RUN_WARNINGS == "$expected_action_warnings" ]] \
    || fail "$label emitted warnings other than the two intentional action failures"
  if grep -Eq 'TypeError|Unable to assign|Cannot read propert(y|ies)' \
      <<<"$RUN_PLAIN_OUTPUT"; then
    fail "$label emitted a QML binding warning"
  fi
  validate_notifications "$fixture_root" "$label"
}

positive_root="$tmpdir/positive"
negative_root="$tmpdir/negative"
stage_fixture "$positive_root"
run_smoke "$positive_root"
printf '%s\n' "$RUN_OUTPUT"
validate_positive "$positive_root" "positive"

stage_fixture "$negative_root"
python3 -I -S - "$negative_root/quickaccess/Service.qml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "bar: pickerPresentation,"
if text.count(old) != 1:
    raise SystemExit("pickerPresentation handoff mutation target drifted")
path.write_text(text.replace(old, "bar: root.bar,"), encoding="utf-8")
PY
run_smoke "$negative_root"
validate_common_completion "pickerPresentation negative control"
validate_notifications "$negative_root" "pickerPresentation negative control"
[[ $(grep -Fxc 'Shibumi wallpaper action failed: Could not apply broken.jpg. denied by fixture' \
  <<<"$RUN_WARNINGS" || true) -eq 1 ]] \
  || fail "negative control lost the intentional wallpaper warning"
[[ $(grep -Fxc 'Shibumi theme action failed: Could not apply broken-theme. theme denied by fixture' \
  <<<"$RUN_WARNINGS" || true) -eq 1 ]] \
  || fail "negative control lost the intentional theme warning"
negative_warnings=$(grep -Fvx \
  -e 'Shibumi wallpaper action failed: Could not apply broken.jpg. denied by fixture' \
  -e 'Shibumi theme action failed: Could not apply broken-theme. theme denied by fixture' \
  <<<"$RUN_WARNINGS" || true)
[[ -n $negative_warnings ]] \
  || fail "pickerPresentation negative control did not trigger a warning"
if grep -Ev "Unable to assign \\[undefined\\] to QColor|TypeError: Cannot read property 'r' of undefined" \
    <<<"$negative_warnings" >/dev/null; then
  fail "pickerPresentation negative control failed for an unrelated warning"
fi
undefined_color_warnings=$(grep -F 'Unable to assign [undefined] to QColor' \
  <<<"$negative_warnings" || true)
[[ -n $undefined_color_warnings ]] \
  || fail "pickerPresentation negative control missed the undefined-color failure"
negative_warning_count=$(wc -l <<<"$negative_warnings")
undefined_color_warning_count=$(wc -l <<<"$undefined_color_warnings")
printf 'pickerPresentation negative control caught %d undefined-color warnings (%d related facade warnings total)\n' \
  "$undefined_color_warning_count" "$negative_warning_count"

run_smoke "$positive_root"
printf '%s\n' "$RUN_OUTPUT"
validate_positive "$positive_root" "restored positive"

plugin="$repo_root/hancore.shibumi.quick-access"
widget="$plugin/BarWidget.qml"
service="$plugin/Service.qml"

rg -q 'readonly property bool textMode: displayMode === "text"' "$widget" \
  || fail "quick access does not expose text display mode"
for label in IDLE MEDIA THEME; do
  rg -Fq "label: \"$label\"" "$widget" \
    || fail "quick-access text mode is missing action: $label"
done
rg -q 'serviceFor\("hancore\.shibumi\.quick-access"\)' "$widget" \
  || fail "widget does not resolve the shared quick-access service"
rg -q 'serviceFor\("hancore\.shibumi\.state"\)' "$service" \
  || fail "service does not resolve the state owner"
for presentation_contract in \
    'HostTokens { id: pickerTokens; bar: root.bar; serviceShell: suiteShell }' \
    'readonly property QtObject pickerPresentation: QtObject {' \
    'bar: pickerPresentation,' \
    'screenListOverride !== null' \
    ': Quickshell.screens'; do
  rg -Fq "$presentation_contract" "$service" \
    || fail "missing scalar-Bar picker presentation contract: $presentation_contract"
done
if rg -Fq 'bar.screenForName' "$service"; then
  fail "picker screen resolution traverses the private/full bar"
fi
rg -Fq 'if (!presentationEnabled || targetScreen === null) return "native"' \
  "$service" || fail "picker routing can consume the native fallback without a presentation"
rg -Fq 'if (!opened || activeScreen !== targetScreen || !overlayLoaded)' \
  "$service" || fail "picker routing reports handled before its presentation opens"
for screen_lifecycle_contract in \
    'function activeTargetPresent()' \
    'screenForName(activeScreenName) === activeScreen' \
    'onScreenListOverrideChanged: closeIfTargetMissing()' \
    'function onScreensChanged() { root.closeIfTargetMissing() }' \
    'activeScreen = null'; do
  rg -Fq "$screen_lifecycle_contract" "$service" \
    || fail "picker active-screen lifecycle drifted: $screen_lifecycle_contract"
done
for setter in setImagePickerStyle setMediaPickerStyle; do
  rg -q "stateService\\.$setter" "$service" \
    || fail "picker style persistence bypasses the state owner: $setter"
done
for command in omarchy-theme-switcher omarchy-theme-bg-switcher; do
  rg -Fq "\"$command\"" "$service" \
    || fail "official Omarchy image picker adapter is missing: $command"
done
rg -Fq '["omarchy-shell", "image-selector", "cancel"]' "$service" \
  || fail "official Omarchy image picker cannot be cancelled"
rg -q 'usingOfficialPicker' "$service" \
  || fail "official image picker is not isolated from the Shibumi overlay"
if rg -q 'bar\.(pickerService|mutateShibumiConfig|idleInhibited)' "$plugin" \
    --glob '*.qml'; then
  fail "plugin consumes transitional bar-owned feature state"
fi
rg -q 'IdleInhibitor \{' "$widget" \
  || fail "screen-local idle inhibitor is missing"
rg -q 'window: root\.targetWindow' "$widget" \
  || fail "idle inhibitor is not bound to its bar window"
rg -q 'String\.fromCodePoint\(0xF06E8\)' "$widget" \
  || fail "active idle-inhibitor glyph drifted from V1"
rg -q 'String\.fromCodePoint\(0xF06E9\)' "$widget" \
  || fail "inactive idle-inhibitor glyph drifted from V1"
rg -q 'font\.pixelSize: Commons\.Style\.space\(14\)' "$widget" \
  || fail "idle-inhibitor glyph size drifted from V1"
[[ $(rg -F -c 'typeof bar.releasePopout === "function"' "$widget") -eq 2 ]] \
  || fail "quick-access teardown does not guard both optional popout releases"
rg -U -q 'bar\.activePopout === activeItem\n[[:space:]]*&& typeof bar\.releasePopout === "function"\)\n[[:space:]]*bar\.releasePopout\(activeItem\)' \
  "$repo_root/hancore.shibumi.bar/core/WidgetSlot.qml" \
  || fail "WidgetSlot teardown does not guard optional popout release"
[[ $(rg -c 'Qt\.resolvedUrl\("PickerOverlay\.qml"\)' "$service") -eq 1 ]] \
  || fail "picker overlay does not have exactly one lazy service owner"
rg -q 'target: "shibumi-picker"' "$service" \
  || fail "picker IPC is not owned by the extracted service"
rg -Fq 'function route(mode: string): string' "$service" \
  || fail "picker provider route IPC is missing"
if rg -q 'Process \{|Timer \{|FileView \{' "$widget" \
    "$plugin/PickerOverlay.qml" "$plugin/TanzakuPickerView.qml" \
    "$plugin/HearthstonePickerView.qml" \
    "$plugin/CarouselPickerView.qml" \
    "$plugin/PickerImage.qml"; then
  fail "screen-local quick-access presentation owns background workers"
fi
[[ -s $plugin/CarouselPickerView.qml ]] \
  || fail "V2 carousel picker is not packaged"
rg -q 'CarouselPickerView' "$plugin/PickerOverlay.qml" \
  || fail "V2 carousel picker is not reachable from the overlay"
rg -q '"carousel"' "$plugin/Service.qml" \
  || fail "V2 carousel picker is not reachable from the service"
for carousel_contract in \
  'readonly property real sliceHeight: previewHeight * 0.90' \
  'readonly property real sliceGap: -sliceWidth * 0.28' \
  'readonly property real skewOffset: Commons.Style.space(20)' \
  'function itemHeight(relative)' \
  'CarouselPickerImage {'; do
  rg -Fq "$carousel_contract" "$plugin/CarouselPickerView.qml" \
    || fail "Carousel lost its distinct stepped-card geometry: $carousel_contract"
done
for skew_contract in \
  'import QtQuick.Effects' \
  'import QtQuick.Shapes' \
  'readonly property real topLeft:' \
  'readonly property real bottomRight:' \
  'maskSource: maskShape' \
  'PathLine { x: root.bottomRight; y: root.height }'; do
  rg -Fq "$skew_contract" "$plugin/CarouselPickerImage.qml" \
    || fail "Carousel lost its skewed mask geometry: $skew_contract"
done
rg -q 'centerY: height / 2 - Commons\.Style\.space\(10\)' \
  "$plugin/TanzakuPickerView.qml" \
  || fail "Tanzaku stage no longer matches the V1 vertical center"
rg -q 'y: root\.centerY - height / 2$' "$plugin/TanzakuPickerView.qml" \
  || fail "Tanzaku strips are no longer vertically aligned"
rg -q 'readonly property int maxVisible: 5' \
  "$plugin/TanzakuPickerView.qml" \
  || fail "Tanzaku visible-strip contract drifted"
rg -q 'function itemWidth\(relative\)' \
  "$plugin/TanzakuPickerView.qml" \
  || fail "Tanzaku does not resolve final target widths independently"
rg -q 'x: root\.itemX\(relative\)$' \
  "$plugin/TanzakuPickerView.qml" \
  || fail "Tanzaku x target depends on an animated item width"
if rg -q 'itemX\(relative,[[:space:]]*width\)' \
    "$plugin/TanzakuPickerView.qml"; then
  fail "Tanzaku navigation retargets x during its width animation"
fi
rg -q 'id: tanzakuFooter' "$plugin/PickerOverlay.qml" \
  || fail "Tanzaku V1 footer hierarchy is missing"
rg -q 'function selectedHeadline\(\)' \
  "$plugin/PickerOverlay.qml" \
  || fail "Tanzaku footer dereferences an empty selection"
rg -Fq 'PickerModel.mediaLabel(entry.sourcePath)' \
  "$plugin/PickerOverlay.qml" \
  || fail "media footer does not use the V1 date/time label"
if rg -Fq 'Enter open  ·  Ctrl+C copy  ·  Delete trash' \
    "$plugin/PickerOverlay.qml"; then
  fail "media footer repeats shortcuts already shown in the primary hint row"
fi
if rg -Fq 'Enter apply     Esc cancel' "$plugin/PickerOverlay.qml"; then
  fail "Tanzaku labels media activation as apply instead of open"
fi
rg -q 'visible: !root\.tanzakuActive' "$plugin/PickerOverlay.qml" \
  || fail "generic footer still overlaps the Tanzaku presentation"
rg -q 'import QtQuick\.Shapes' "$plugin/HearthstonePickerView.qml" \
  || fail "Hearthstone lost its V1 rounded passepartout renderer"
rg -q 'readonly property real focusScale: 1\.24' \
  "$plugin/HearthstonePickerView.qml" \
  || fail "Hearthstone focus geometry drifted from V1"
rg -q 'readonly property real spreadDegrees: 6' \
  "$plugin/HearthstonePickerView.qml" \
  || fail "Hearthstone card fan geometry drifted from V1"
rg -q 'fillRule: ShapePath\.OddEvenFill' \
  "$plugin/HearthstonePickerView.qml" \
  || fail "Hearthstone photo passepartout is missing"
rg -Fq 'PickerModel.mediaLabel(card.modelData.sourcePath)' \
  "$plugin/HearthstonePickerView.qml" \
  || fail "Hearthstone media cards do not use the V1 date/time label"
rg -q 'Qt\.rgba\(0\.035, 0\.035, 0\.05, 0\.975\)' \
  "$plugin/PickerOverlay.qml" \
  || fail "Hearthstone felt backdrop drifted from V1"
rg -q 'requestSerial\+\+' "$service" \
  || fail "picker requests are not generation guarded"
rg -q 'stopForegroundWorkers\(\)' "$service" \
  || fail "picker close does not cancel foreground workers"
rg -Fq '[scriptPath, "cleanup"]' "$service" \
  || fail "picker close does not reconcile interrupted scan artifacts"
rg -q 'activeScreenName' "$service" \
  || fail "picker does not retain focused-output routing"
rg -Fq 'PickerModel.entriesEqual(entries, parsed)' "$service" \
  || fail "equivalent cache/live scans still replace the picker model"
rg -Fq 'readyThumbnails[thumbnailPath] = true' "$service" \
  || fail "thumbnail readiness is not tracked outside the picker model"
rg -Fq 'thumbnailRevision++' "$service" \
  || fail "thumbnail readiness does not refresh image bindings"
if sed -n '/function noteThumbnailReady(/,/^[[:space:]]*}/p' "$service" \
    | rg -q 'entries[[:space:]]*='; then
  fail "thumbnail readiness still replaces the complete picker model"
fi
stage_line=$(rg -n 'id: stage' "$plugin/PickerOverlay.qml" | cut -d: -f1)
dismiss_line=$(rg -n 'id: dismissArea' "$plugin/PickerOverlay.qml" | cut -d: -f1)
view_line=$(rg -n 'id: viewLoader' "$plugin/PickerOverlay.qml" | cut -d: -f1)
if [[ -z $stage_line || -z $dismiss_line || -z $view_line \
    || $dismiss_line -le $stage_line || $dismiss_line -ge $view_line ]]; then
  fail "picker dismiss target is not below the views in the active focus scope"
fi
rg -q 'WheelHandler \{' "$plugin/PickerOverlay.qml" \
  || fail "picker modes do not share mouse-wheel navigation"
rg -Fq 'root.controller.moveSelection(delta > 0 ? -1 : 1)' \
  "$plugin/PickerOverlay.qml" \
  || fail "picker wheel events do not move the current selection"
rg -q 'ClippingRectangle \{' "$plugin/PickerImage.qml" \
  || fail "picker images lost the V1 anti-aliased rounded mask"
rg -Fq 'root.controller.isThumbnailReady(root.entry)' \
  "$plugin/PickerImage.qml" \
  || fail "rounded picker images ignore incremental thumbnail readiness"
rg -Fq 'root.controller.isThumbnailReady(card.modelData)' \
  "$plugin/HearthstonePickerView.qml" \
  || fail "Hearthstone images ignore incremental thumbnail readiness"
rg -Fq 'source: root.sourceActive ? root.controller.thumbnailUrl(root.entry) : ""' \
  "$plugin/PickerImage.qml" \
  || fail "rounded picker images are not bounded to the active source window"
rg -Fq 'source: card.imageSourceActive' \
  "$plugin/HearthstonePickerView.qml" \
  || fail "Hearthstone images are not bounded to the active source window"
for picker_view in TanzakuPickerView.qml HearthstonePickerView.qml \
    CarouselPickerView.qml; do
  rg -Fq 'readonly property int activeImageSourceCount:' "$plugin/$picker_view" \
    || fail "picker view does not expose the real active source count: $picker_view"
done
rg -Fq 'readonly property int imagePreloadRadius: imageVisibleRadius + 1' \
  "$service" || fail "picker image preloading is not bounded to one extra entry"
rg -Fq 'Math.abs(candidate - selectedIndex) <= imagePreloadRadius' "$service" \
  || fail "picker image sources are not tied to the current bounded window"
if rg -q 'visitedImageSources|markImageWindowVisited|resetVisitedImages' \
    "$service"; then
  fail "picker image sources can grow beyond the current bounded window"
fi
rg -Fq 'function finishCacheLoad(text, serial)' "$service" \
  || fail "picker cache load does not own deferred refresh scheduling"
rg -Fq 'id: scanDelay' "$service" \
  || fail "picker live scan is not delayed after a warm cache hit"
rg -Fq 'scanDelay.stop()' "$service" \
  || fail "picker close does not cancel the deferred live scan"
rg -Fq '["nice", "-n", "10", scriptPath,' "$service" \
  || fail "picker refresh scan does not yield priority to the first render"
rg -q 'radius: Math\.max\(0, root\.imageRadius - anchors\.margins\)' \
  "$plugin/PickerImage.qml" \
  || fail "picker image mask is no longer concentric with the outer frame"
rg -q 'function startSelectionAction\(' "$service" \
  || fail "picker actions do not share one guarded process path"
rg -Fq '["notify-send", "-a", "Shibumi"' "$service" \
  || fail "failed picker actions have no visible user feedback"

rg -Fq 'function mediaLabel(path)' "$plugin/PickerModel.js" \
  || fail "picker model is missing V1 media label formatting"
[[ -x $plugin/scripts/shibumi-picker ]] || fail "picker helper is not executable"
[[ -x $plugin/scripts/shibumi-picker-route ]] \
  || fail "Omarchy menu picker router is not executable"
for route_contract in \
    'omarchy-shell shibumi-picker route "$mode"' \
    'omarchy-theme-switcher' \
    'omarchy-theme-bg-switcher'; do
  rg -Fq "$route_contract" "$plugin/scripts/shibumi-picker-route" \
    || fail "missing Omarchy menu picker route contract: $route_contract"
done

PICKER_HELPER="$plugin/scripts/shibumi-picker" \
  "$repo_root/tests/picker-helper-regression.sh" >/dev/null

printf 'quick access plugin regression passed\n'
