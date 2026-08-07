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

[[ $(rg -l 'target: "omarchy\.network"' \
  "$network_service" "$network_widget" "$network_bridge" "$host_network" \
  | wc -l) -eq 1 ]] \
  || fail 'Network does not retain exactly one authoritative direct IPC target'
rg -Fq 'target: "omarchy.network"' "$host_network" \
  || fail 'authoritative Network target moved away from the host backend'
if rg -q 'IpcHandler[[:space:]]*\{' \
    "$network_service" "$network_widget" "$network_bridge"; then
  fail 'Shibumi duplicates the authoritative Network IpcHandler'
fi
for contract in \
  'function onOpenedChanged()' \
  'function onQrVisibleChanged()' \
  'function onSpeedTestModalOpenChanged()' \
  'property var presentationOwner: null' \
  'const owner = focusedPresentationWidget()' \
  'if (owner.opened !== true) owner.open()' \
  'owner.close()' \
  'speedDetailsVisible = true'; do
  rg -Fq "$contract" "$network_bridge" \
    || fail "Network direct IPC redirect is incomplete: $contract"
done

printf 'audio/network IPC contract regression passed\n'
