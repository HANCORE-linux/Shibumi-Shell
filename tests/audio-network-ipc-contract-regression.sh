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
embedded_audio_bridge="$repo_root/adapters/AudioPanelBridge.qml"
embedded_network_bridge="$repo_root/adapters/NetworkPanelBridge.qml"
host_network="$OMARCHY_PATH/shell/plugins/panels/network/Panel.qml"

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
for bridge in "$audio_bridge" "$network_bridge" \
    "$embedded_audio_bridge" "$embedded_network_bridge"; do
  rg -Fq 'function suppressBackendKeyboardPanel()' "$bridge" \
    || fail "hidden official backend lacks KeyboardPanel suppression: $bridge"
  rg -Fq 'typeof candidate.beginFocusPrime !== "function"' "$bridge" \
    || fail "hidden backend suppression is not limited to KeyboardPanel: $bridge"
  rg -Fq 'candidate.owner !== panel' "$bridge" \
    || fail "hidden backend suppression can match a foreign window: $bridge"
  rg -Fq 'candidate.open = false' "$bridge" \
    || fail "hidden official KeyboardPanel can retain dismissal surfaces: $bridge"
  rg -Fq 'candidate.visible = false' "$bridge" \
    || fail "hidden official KeyboardPanel can flash before redirect: $bridge"
done

rg -Fq 'target: "omarchy.network"' "$host_network" \
  || fail 'Network host backend no longer exposes its compatibility target'
rg -Fq 'target: "omarchy.network"' "$network_bridge" \
  || fail 'Shibumi bridge does not own the intercepted compatibility target'
if rg -q 'IpcHandler[[:space:]]*\{' \
    "$network_service" "$network_widget"; then
  fail 'screen-local Network state duplicates the compatibility IpcHandler'
fi
for contract in \
  'function suppressBackendIpc()' \
  'candidate.enabled = false' \
  'enabled: root.backendIpcSuppressed' \
  'function onOpenedChanged()' \
  'function onQrVisibleChanged()' \
  'property var presentationOwner: null' \
  'const owner = focusedPresentationWidget()' \
  'if (owner.opened !== true) owner.open()' \
  'owner.close()' \
  'if (panel && panel.opened === true && typeof panel.close === "function")' \
  'speedDetailsVisible = true' \
  'function speedTest(): void { root.summonNetworkPresentation("speed") }' \
  'networkService.runSpeedTest()'; do
  rg -Fq "$contract" "$network_bridge" \
    || fail "Network direct IPC redirect is incomplete: $contract"
done

printf 'audio/network IPC contract regression passed\n'
