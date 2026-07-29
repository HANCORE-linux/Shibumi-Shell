#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/home/hancore/Projects/omarchy-updates-pr}
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-network.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'network plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.network" "$tmpdir/network"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/network-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/NetworkTestService.qml" \
  "$repo_root/tests/fixtures/NetworkTestView.qml" \
  "$repo_root/tests/fixtures/NetworkTestPanel.qml" "$tmpdir/fixtures/"

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
grep -F 'network plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

widget="$repo_root/hancore.shibumi.network/BarWidget.qml"
service="$repo_root/hancore.shibumi.network/Service.qml"
rg -q 'serviceFor\("hancore\.shibumi\.network"\)' "$widget" \
  || fail "network widget does not resolve the shared service"
if rg -q 'bar\.networkService' "$repo_root/hancore.shibumi.network"; then
  fail "network plugin depends on transitional bar-owned network state"
fi
[[ $(rg -c '^import Quickshell\.Networking$' "$service") -eq 1 ]] \
  || fail "networking state does not have one service owner"
if rg -q 'Quickshell\.Networking|Networking\.' \
    "$widget" "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
    "$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml"; then
  fail "screen-local network presentation owns NetworkManager state"
fi
rg -q 'property var bar: shell \? shell\.bar : null' "$service" \
  || fail "network service does not use the versioned active bar facade"
rg -q 'registeredWidgetComponent\("omarchy\.network"\)' "$service" \
  || fail "network service does not retain the official Omarchy owner"
rg -Fq 'function connectedWifiLabel()' \
  "$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml" \
  || fail "network bridge does not normalize Quattro's current SSID owner"
rg -Fq 'rows[i].connected === true' \
  "$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml" \
  || fail "network bridge does not consume the connected official Wi-Fi row"
if rg -Fq 'panel.bar = null' \
    "$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml"; then
  fail "network bridge clears the official panel host before destruction"
fi
rg -Fq 'connectedVisibleLabel(visibleNetworks)' \
  "$repo_root/hancore.shibumi.network/Service.qml" \
  || fail "network service lacks the connected official-row SSID fallback"
rg -Fq 'function connectEnterprise(entry, identity, passphrase)' "$service" \
  || fail "network service lacks Quattro enterprise forwarding"
rg -Fq 'backend.connectEnterprise(entry.ssid, String(identity), String(passphrase))' \
  "$service" || fail "network service does not delegate 802.1X to the official owner"
rg -Fq 'placeholderText: "Identity (user@domain)"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel lacks the enterprise identity field"
rg -Fq 'networkService.connectEnterprise(entry, identityText, passwordText)' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel does not submit enterprise credentials"
if rg -q 'nmcli.*(802-1x|wpa-eap|password|identity)' \
    "$repo_root/hancore.shibumi.network"; then
  fail "network plugin bypasses the official Quattro enterprise owner"
fi
rg -q 'property var sessionOwners: \[\]' "$service" \
  || fail "network panel sessions are not centrally tracked"
rg -q 'detailsProc\.running = false' "$service" \
  || fail "network detail worker lacks final-close cleanup"
rg -q 'profileList\.running = false' "$service" \
  || fail "network profile worker lacks final-close cleanup"
rg -q 'label: "FREQUENCY"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel dropped the V1 frequency field"
rg -q 'label: "LINK SPEED"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel dropped the V1 link-speed field"
rg -q 'info\.bitrate' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel does not consume Quattro Wi-Fi bitrate data"
rg -Fq 'label: panel.networkService.wifiEnabled ? "ON" : "OFF"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel dropped the V1 Wi-Fi state button"
[[ $(rg -c 'onClicked: panel\.networkService\.toggleWifi\(\)' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml") -eq 1 ]] \
  || fail "network panel must expose exactly one V1 Wi-Fi state button"
rg -q 'label: "Network settings"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network settings dropped the V1 primary action treatment"
rg -q 'primary: true' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network settings dropped the V1 primary action treatment"
rg -Fq 'function canForget(entry) { return !!entry && entry.known === true }' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel does not preserve V1 Forget eligibility"
rg -Fq 'visible: panel.canForget(networkRow.modelData)' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel does not expose Forget for every saved profile"
rg -Fq 'if (!key || !canForget(entry)) return' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel Forget confirmation bypasses shared eligibility"
forget_function=$(sed -n '/^  function requestForget(entry) {$/,/^  }$/p' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml")
if grep -q 'connected' <<<"$forget_function"; then
  fail "network panel still blocks Forget for the connected saved profile"
fi

printf 'network plugin regression passed\n'
