#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-audio-media.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'audio/media plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

run_smoke() {
  local name=$1 test_file=$2 marker=$3
  local smoke_root="$tmpdir/$name"

  mkdir -p "$smoke_root/runtime" "$smoke_root/fixtures"
  chmod 700 "$smoke_root/runtime"
  cp -a -- "$repo_root/hancore.shibumi.$name" "$smoke_root/$name"
  cp -a -- "$omarchy_path/shell/Commons" "$smoke_root/Commons"
  cp -a -- "$omarchy_path/shell/Ui" "$smoke_root/Ui"
  install -Dm0644 "$repo_root/tests/$test_file" "$smoke_root/shell.qml"

  if [[ $name == audio ]]; then
    cp "$repo_root/tests/fixtures/AudioTestPanel.qml" \
      "$repo_root/tests/fixtures/AudioTestView.qml" "$smoke_root/fixtures/"
  else
    cp "$repo_root/tests/fixtures/MediaTestPanel.qml" "$smoke_root/fixtures/"
  fi

  set +e
  local output rc
  output=$(timeout 8 env \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$smoke_root" 2>&1)
  rc=$?
  set -e

  printf '%s\n' "$output"
  [[ $rc -eq 0 ]] || fail "$name smoke exited $rc"
  grep -F "$marker" <<<"$output" >/dev/null \
    || fail "$name success marker missing"
}

run_smoke audio audio-plugin-smoke.qml 'audio plugin smoke passed'
run_smoke media media-plugin-smoke.qml 'media plugin smoke passed'

run_spectrum_smoke() {
  local mode=$1 marker=$2
  local smoke_root="$tmpdir/media-spectrum-$mode"

  mkdir -p "$smoke_root/runtime" "$smoke_root/bin"
  chmod 700 "$smoke_root/runtime"
  cp -a -- "$repo_root/hancore.shibumi.media" "$smoke_root/media"
  cp -a -- "$omarchy_path/shell/Commons" "$smoke_root/Commons"
  cp -a -- "$omarchy_path/shell/Ui" "$smoke_root/Ui"
  install -Dm0644 "$repo_root/tests/media-spectrum-service-smoke.qml" \
    "$smoke_root/shell.qml"
  if [[ $mode == unavailable ]]; then
    install -Dm0755 "$repo_root/tests/fixtures/fake-cava-probe-failure" \
      "$smoke_root/bin/sh"
  else
    install -Dm0755 "$repo_root/tests/fixtures/fake-cava" \
      "$smoke_root/bin/cava"
  fi

  set +e
  local output rc
  output=$(timeout 12 env \
    PATH="$smoke_root/bin:/usr/bin:/bin" \
    SHIBUMI_CAVA_TEST_MODE="$mode" \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$smoke_root/runtime" \
    QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
    QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    "$quickshell_bin" -p "$smoke_root" 2>&1)
  rc=$?
  set -e

  printf '%s\n' "$output"
  [[ $rc -eq 0 ]] || fail "media spectrum $mode smoke exited $rc"
  grep -F "$marker" <<<"$output" >/dev/null \
    || fail "media spectrum $mode success marker missing"
}

run_spectrum_smoke available 'media spectrum service smoke passed'
run_spectrum_smoke unavailable 'media spectrum unavailable smoke passed'
run_spectrum_smoke failure 'media spectrum failure smoke passed'
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml \
  "$repo_root/tests/cava-theme-model-regression.qml"

if rg -q 'Quickshell\.Services\.(Pipewire|Mpris)|MprisPlayer' \
    "$repo_root/hancore.shibumi.audio/BarWidget.qml" \
    "$repo_root/hancore.shibumi.media/BarWidget.qml"; then
  fail "bar presentation directly owns an official audio/media backend"
fi

audio_widget="$repo_root/hancore.shibumi.audio/BarWidget.qml"
embedded_audio_widget="$repo_root/widgets/AudioWidget.qml"
audio_panel="$repo_root/hancore.shibumi.audio/AudioPanel.qml"
audio_bridge="$repo_root/hancore.shibumi.audio/AudioPanelBridge.qml"
for volume_widget in "$audio_widget" "$embedded_audio_widget"; do
  full_content=$(sed -n \
    '/id: fullHorizontalContent/,/id: compactHorizontalContent/p' \
    "$volume_widget")
  compact_content=$(sed -n \
    '/id: compactHorizontalContent/,/id: verticalContent/p' \
    "$volume_widget")
  grep -Fq 'horizontalAlignment: Text.AlignRight' <<<"$full_content" \
    || fail "full audio value does not preserve its fixed right edge"
  grep -Fq 'horizontalAlignment: Text.AlignLeft' <<<"$compact_content" \
    || fail "compact audio value does not keep a fixed icon gap"
  if grep -Fq 'horizontalAlignment: Text.AlignRight' \
      <<<"$compact_content"; then
    fail "compact audio value still shifts inside its fixed-width field"
  fi
done
rg -q 'registeredWidgetSource' "$audio_widget" \
  || fail "audio bridge does not resolve the official Omarchy source"
rg -q 'registeredWidgetComponent' "$audio_widget" \
  || fail "audio bridge does not resolve the official Omarchy component"
rg -q 'registered(Source|Component)\("omarchy\.audio"\)' "$audio_widget" \
  || fail "audio bridge does not select the official Omarchy audio plugin"
rg -q 'readonly property color background: realBar && realBar\.background !== undefined' \
  "$audio_bridge" \
  || fail "audio host facade does not provide Quattro panel background color"
rg -q 'readonly property color barBackground: background' "$audio_bridge" \
  || fail "audio host facade does not provide the Quattro background alias"
rg -q 'firstPartyServiceFor\("omarchy\.media"\)' \
  "$repo_root/hancore.shibumi.media/BarWidget.qml" \
  || fail "media presentation bypasses the official Omarchy service"
jq -e '
  .kinds == ["bar-widget", "service"] and
  .keepLoaded == true and
  .entryPoints.service == "Service.qml"
' "$repo_root/hancore.shibumi.media/manifest.json" >/dev/null \
  || fail "media plugin manifest does not declare its process-wide service"
jq -e '
  .profiles[] | select(.id == "default") |
  (.layout.right | index("hancore.shibumi.media") != null) and
  (.enableServices | index("hancore.shibumi.media") == null)
' "$repo_root/contracts/plugin-suite-v1.json" >/dev/null \
  || fail "default profile must activate media once through its bar layout"
rg -q 'serviceFor\("hancore\.shibumi\.media"\)' \
  "$repo_root/hancore.shibumi.media/BarWidget.qml" \
  || fail "media presentation does not resolve the process-wide spectrum service"
if rg -q 'Process \{|FileView \{' \
    "$repo_root/hancore.shibumi.media/BarWidget.qml" \
    "$repo_root/hancore.shibumi.media/MediaPanel.qml" \
    "$repo_root/hancore.shibumi.media/MediaMuse.qml"; then
  fail "screen-local media presentations own spectrum workers"
fi
[[ $(rg -c 'Process \{' "$repo_root/hancore.shibumi.media/Service.qml") -eq 2 ]] \
  || fail "media spectrum service must own one probe and one Cava process"
rg -q 'property var spectrumClients: \[\]' \
  "$repo_root/hancore.shibumi.media/Service.qml" \
  || fail "media spectrum service lacks multi-output lease accounting"
rg -q 'bars = 24' "$repo_root/hancore.shibumi.media/Service.qml" \
  || fail "media spectrum service does not preserve the V1 band count"
rg -q 'maximumRetries: 3' "$repo_root/hancore.shibumi.media/Service.qml" \
  || fail "media spectrum service does not bound Cava retries"
rg -q 'target: "shibumi-media-spectrum"' \
  "$repo_root/hancore.shibumi.media/Service.qml" \
  || fail "media spectrum service lacks read-only runtime diagnostics"
rg -Fq 'readonly property string mediaStyle:' \
  "$repo_root/hancore.shibumi.media/BarWidget.qml" \
  || fail "G9 does not normalize its two-presentation style"
rg -Fq 'String(setting("mediaStyle", "default")) === "full"' \
  "$repo_root/hancore.shibumi.media/BarWidget.qml" \
  || fail "G9 does not expose Default and Full presentations"
rg -q 'readonly property bool museMode: fullMode' \
  "$repo_root/hancore.shibumi.media/BarWidget.qml" \
  || fail "G9 does not share FULL/muse across V1 and V2"
rg -q 'readonly property int bandCount: 24' \
  "$repo_root/hancore.shibumi.media/MediaMuse.qml" \
  || fail "G9 FULL presentation does not render 24 bands"
rg -q 'enabled: panel\.open && panel\.audioBackend' \
  "$audio_panel" \
  || fail "microphone metering is not panel-lifecycle bounded"
if rg -q 'ShibumiSlider \{' "$audio_panel"; then
  fail "audio panel still exposes the thick legacy slider presentation"
fi
[[ $(rg -c 'Ui\.PanelSlider \{' "$audio_panel") -eq 3 ]] \
  || fail "output, input, and application rows must share the thin PanelSlider"
rg -q 'contentWidth: fittedContentWidth\(280\)' \
  "$audio_panel" \
  || fail "audio panel does not preserve the V1 280px card width"
rg -q 'panel\.audioBackend\.setOutputVolume\(value\)' "$audio_panel" \
  || fail "output slider does not retain direct Quattro volume control"
rg -q 'id: outputControl' "$audio_panel" \
  || fail "output heading and slider are not compactly grouped"
[[ $(rg -c 'trackColor: panel\.controlActiveFillColor' "$audio_panel") -eq 3 ]] \
  || fail "audio sliders do not share the Text Size track color"
rg -Fq 'function sliderKnobColor(muted, sliderEnabled)' "$audio_panel" \
  || fail "audio panel does not centralize muted and disabled knob states"
rg -Fq '* (sliderEnabled ? 1 : 0.5)' "$audio_panel" \
  || fail "disabled audio sliders do not dim their knob"
[[ $(rg -c 'knobColor: panel\.sliderKnobColor' "$audio_panel") -eq 2 ]] \
  || fail "output and input sliders do not share the disabled knob state"
if rg -q 'anchors\.(left|right)Margin: Commons\.Style\.space\(6\)' \
    "$audio_panel"; then
  fail "audio sliders do not span the full microphone-meter width"
fi
if rg -q 'tickCount:' "$audio_panel"; then
  fail "volume sliders must remain continuous and unsegmented"
fi
rg -q 'function descriptiveNodeLabel\(node\)' "$audio_bridge" \
  || fail "audio bridge does not restore descriptive device labels"
if rg -q 'wiremix|Open audio|openMixer' "$audio_panel"; then
  fail "audio panel exposes the retired external mixer action"
fi
rg -Fq 'text: panel.inputMuted ? "Muted"' "$audio_panel" \
  || fail "microphone row does not expose its muted state and volume"
rg -q 'panel\.audioBackend\.setInputVolume\(value\)' "$audio_panel" \
  || fail "microphone slider does not forward input volume changes"
if rg -q 'text: "ACTIVITY"' "$audio_panel"; then
  fail "audio panel exposes a redundant microphone activity heading"
fi
[[ $(rg -c 'width: Commons\.Style\.space\(30\)' "$audio_widget") -eq 2 ]] \
  || fail "audio percentage labels do not preserve a stable panel anchor width"
rg -q 'readonly property bool spectrumRequested: open && active && spectrumEnabled' \
  "$repo_root/hancore.shibumi.media/MediaPanel.qml" \
  || fail "media spectrum work is not panel-lifecycle bounded"
for media_panel in \
    "$repo_root/hancore.shibumi.media/MediaPanel.qml" \
    "$repo_root/widgets/MediaPanel.qml"; do
  rg -q 'property Timer positionTimer: Timer \{' "$media_panel" \
    || fail "$(basename "$media_panel") assigns a non-visual Timer to ShibumiPanel content"
done
rg -q 'current/theme/cava_theme' \
  "$repo_root/hancore.shibumi.media/Service.qml" \
  || fail "media spectrum does not consume the active Cava theme"
rg -q 'themeColors: panel\.spectrumThemeColors' \
  "$repo_root/hancore.shibumi.media/MediaPanel.qml" \
  || fail "media spectrum does not receive the parsed Cava palette"

printf 'audio/media plugin regression passed\n'
