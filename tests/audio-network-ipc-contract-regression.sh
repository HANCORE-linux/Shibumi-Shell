#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline

fail() {
  printf 'audio/network IPC contract regression failed: %s\n' "$*" >&2
  exit 1
}

audio_service="$repo_root/hancore.shibumi.audio/Service.qml"
audio_widget="$repo_root/hancore.shibumi.audio/BarWidget.qml"
audio_bridge="$repo_root/hancore.shibumi.audio/AudioPanelBridge.qml"
network_service="$repo_root/hancore.shibumi.network/Service.qml"
network_widget="$repo_root/hancore.shibumi.network/BarWidget.qml"
network_bridge="$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml"

[[ $(rg -l 'target: "omarchy\.audio"' \
  "$audio_service" "$audio_widget" "$audio_bridge" | wc -l) -eq 1 ]] \
  || fail 'Audio does not expose exactly one process-wide compatibility target'
rg -Fq 'target: "omarchy.audio"' "$audio_service" \
  || fail 'Audio compatibility target is not owned by the process-wide service'
for method in open close show hide toggle; do
  rg -q "function ${method}\\(\\)" "$audio_service" \
    || fail "Audio compatibility target is missing $method"
done
rg -Fq 'manageIpc: false' "$audio_widget" \
  || fail 'visible Audio widget can duplicate direct IPC ownership'
rg -Fq 'manageIpc = false' "$audio_bridge" \
  || fail 'hidden official Audio backend can duplicate direct IPC ownership'
rg -Fq 'function suppressKeyboardPanel()' "$audio_bridge" \
  || fail 'hidden official Audio backend lacks KeyboardPanel suppression'
rg -Fq 'candidate.owner !== item' "$audio_bridge" \
  || fail 'hidden Audio suppression can match a foreign window'
rg -Fq 'typeof candidate.beginFocusPrime !== "function"' "$audio_bridge" \
  || fail 'hidden Audio suppression is not limited to KeyboardPanel'
rg -Fq 'candidate.open = false' "$audio_bridge" \
  || fail 'hidden Audio KeyboardPanel can retain dismissal surfaces'
rg -Fq 'candidate.visible = false' "$audio_bridge" \
  || fail 'hidden Audio KeyboardPanel can flash before redirect'

[[ $(rg -l 'target: "omarchy\.network"' \
  "$network_service" "$network_widget" "$network_bridge" | wc -l) -eq 1 ]] \
  || fail 'Network does not expose exactly one compatibility target'
rg -Fq 'target: "omarchy.network"' "$network_bridge" \
  || fail 'native Network bridge does not own the compatibility target'
if rg -q 'IpcHandler[[:space:]]*\{' \
    "$network_service" "$network_widget"; then
  fail 'screen-local Network state duplicates the compatibility IpcHandler'
fi
if rg -q 'Loader|panelSource|panelComponent|backendIpcSuppressed' \
    "$network_bridge"; then
  fail 'native Network compatibility route still loads a host backend'
fi
for contract in \
  'property var presentationOwner: null' \
  'const owner = focusedPresentationWidget()' \
  'owner.close()' \
  'function showQr(): void { root.summonNetworkPresentation("qr") }' \
  'function speedTest(): void { root.summonNetworkPresentation("speed") }' \
  'networkService.toggleWifi()'; do
  rg -Fq "$contract" "$network_bridge" \
    || fail "Network direct IPC redirect is incomplete: $contract"
done
rg -Fq 'function openNetworkPresentation(modeValue)' "$network_widget" \
  || fail 'Network output widget cannot receive compatibility presentations'

printf 'audio/network IPC contract regression passed\n'
