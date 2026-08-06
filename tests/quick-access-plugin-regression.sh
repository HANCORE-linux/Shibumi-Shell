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

mkdir -p "$tmpdir/runtime" "$tmpdir/bin"
chmod 700 "$tmpdir/runtime"
cat >"$tmpdir/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$SHIBUMI_NOTIFY_LOG"
EOF
chmod 700 "$tmpdir/bin/notify-send"
notify_log="$tmpdir/notify.log"
cp -a -- "$repo_root/hancore.shibumi.quick-access" "$tmpdir/quickaccess"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
install -m 0644 "$repo_root/tests/quick-access-plugin-smoke.qml" "$tmpdir/shell.qml"

set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  PATH="$tmpdir/bin:$PATH" \
  SHIBUMI_NOTIFY_LOG="$notify_log" \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
rc=$?
set -e

printf '%s\n' "$output"
[[ $rc -eq 0 ]] || fail "component smoke exited $rc"
grep -F 'quick access plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"
for _ in {1..20}; do
  [[ -s $notify_log ]] && break
  sleep 0.05
done
grep -Fx 'Wallpaper change failed' "$notify_log" >/dev/null \
  || fail "wallpaper failure notification title is missing"
grep -F 'Could not apply broken.jpg. denied by fixture' "$notify_log" >/dev/null \
  || fail "wallpaper failure notification detail is missing"
grep -Fx 'Theme change failed' "$notify_log" >/dev/null \
  || fail "theme failure notification title is missing"
grep -F 'Could not apply broken-theme. theme denied by fixture' \
  "$notify_log" >/dev/null \
  || fail "theme failure notification detail is missing"

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

cmp -s -- "$repo_root/shared/quick-access/PickerModel.js" \
  "$plugin/PickerModel.js" || fail "vendored picker model drift"
rg -Fq 'function mediaLabel(path)' "$plugin/PickerModel.js" \
  || fail "picker model is missing V1 media label formatting"
cmp -s -- "$repo_root/shared/quick-access/shibumi-picker" \
  "$plugin/scripts/shibumi-picker" || fail "vendored picker helper drift"
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
