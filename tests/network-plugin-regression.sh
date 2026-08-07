#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
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
if grep -F 'Binding loop detected' <<<"$output" >/dev/null; then
  fail "V1/V2 network presentation produced a binding loop"
fi

widget="$repo_root/hancore.shibumi.network/BarWidget.qml"
service="$repo_root/hancore.shibumi.network/Service.qml"
[[ $(rg -c 'BoundedLabel \{' "$widget") -eq 2 ]] \
  || fail "V1/V2 bounded labels do not share the independent metrics path"
rg -Fq 'component BoundedLabel: Text' "$widget" \
  || fail "bounded network labels lack a reusable text component"
rg -Fq 'TextMetrics {' "$widget" \
  || fail "bounded network labels do not use independent text metrics"
if rg -Fq 'width: visible ? Math.min(88, implicitWidth) : 0' "$widget" \
    || rg -Fq 'width: Math.min(implicitWidth, Commons.Style.space(128))' "$widget"; then
  fail "network labels still derive width from their own implicit width"
fi
rg -q 'serviceFor\("hancore\.shibumi\.network"\)' "$widget" \
  || fail "network widget does not resolve the shared service"
rg -Fq 'property url popupSource: Qt.resolvedUrl("NetworkPanel.qml")' "$widget" \
  || fail "V1 and V2 do not resolve the same NetworkPanel content"
rg -Fq 'if (networkService.kind === "ethernet") return ethernetAddress()' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "Ethernet headline does not show its address beside the panel icon"
rg -Fq 'return String(info.ip) + (info.prefix ? "/" + info.prefix : "")' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "Ethernet headline dropped the network prefix"
rg -Fq 'if (networkService.kind !== "ethernet" && info.ip)' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "Ethernet metadata still repeats the IP address"
rg -Fq 'if (networkService.kind === "wifi") return networkService.label || "Wi-Fi connected"' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "Wi-Fi headline behavior changed while adjusting Ethernet"
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
rg -q 'registeredComponent\("omarchy\.network"\)' "$service" \
  || fail "network service does not retain the official Omarchy owner"
rg -Fq '"barWidgetRegistry" in bar' "$service" \
  || fail "network service cannot resolve the official owner on stock Quattro"
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
rg -Fq 'readonly property bool wifiControlsVisible: networkService' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml" \
  || fail "network panel does not derive Wi-Fi UI from adapter availability"
[[ $(rg -c 'visible: panel\.wifiControlsVisible' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml") -ge 6 ]] \
  || fail "desktop network panel still exposes Wi-Fi-only controls"
rg -Fq 'const shouldScanWifi = scanWifi === true && wifiAvailable' "$service" \
  || fail "desktop network sessions still request Wi-Fi scans"
rg -Fq 'if (!backendAvailable || !wifiAvailable) return false' "$service" \
  || fail "Wi-Fi toggle is not guarded by adapter availability"
rg -Fq 'return (speed >= 100 ? speed.toFixed(0) : speed.toFixed(1)) + " Mbps"' \
  "$service" || fail "speed-test results do not use the source Mbps formatter"
status_block=$(sed -n '/^[[:space:]]*Ui\.PanelSeparator { width: parent.width }$/,/^[[:space:]]*Grid {$/p' \
  "$repo_root/hancore.shibumi.network/NetworkPanel.qml")
grep -Fq 'spacing: Commons.Style.space(8)' <<<"$status_block" \
  || fail "network panel status row drifted from the repository layout"
grep -Fq 'source: Qt.resolvedUrl("lan.svg")' <<<"$status_block" \
  || fail "network panel Ethernet status does not use the crisp LAN vector"
grep -Fq 'sourceSize: Qt.size(20, 20)' <<<"$status_block" \
  || fail "network panel LAN vector is not rasterized on its native 20px grid"
grep -Fq 'smooth: false' <<<"$status_block" \
  || fail "network panel LAN vector is still being smoothed"
grep -Fq 'colorizationColor: panel.bar' <<<"$status_block" \
  || fail "network panel LAN vector does not follow the active theme"
grep -Fq 'font.pixelSize: Commons.Style.font.heading' <<<"$status_block" \
  || fail "network panel status icon drifted from the repository size"
grep -Fq 'font.hintingPreference: Font.PreferFullHinting' <<<"$status_block" \
  || fail "network panel status icon lacks the crisp hinted render path"
grep -Fq 'renderType: Text.NativeRendering' <<<"$status_block" \
  || fail "network panel status icon does not use native glyph rasterization"
if grep -Eq 'height: 8|id: connectionStatus|statusHeadline' <<<"$status_block" \
    || grep -Fq '"\uEB2F"' <<<"$status_block"; then
  fail "network panel still contains the non-repository hero/progress layout"
fi
rg -Fq 'backend.runSpeedTest()' "$service" \
  || fail "inline speed test does not delegate directly to Omarchy's runner"
if rg -q 'showSpeedTest\(' "$repo_root/hancore.shibumi.network"; then
  fail "network plugin opens Omarchy's external speed-test overlay"
fi
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

# Preserve the two reference presentations independently: V1 owns the wide
# history/rate view, while V2 owns the LAN glyph and compact RX/TX meter.
for contract in \
  'readonly property int trafficHistoryLimit: 30' \
  'width: visible ? 36 : 0' \
  'height: 14' \
  'interval: 2000' \
  'running: root.mode === "ethernet" && !root.v2Presentation' \
  'y: height - (Math.max(0, Number(values[index]) || 0)' \
  'text: "↓" + root.v1Rate(root.downloadRate)' \
  'text: "↑" + root.v1Rate(root.uploadRate)' \
  'font.pixelSize: 10' \
  'text: root.stateGlyph' \
  'font.pixelSize: root.mode === "ethernet" ? 14 : 15' \
  'component V2TrafficMeter: Item' \
  'x: 10' \
  'text: "RX"' \
  'text: "TX"'; do
  rg -Fq "$contract" "$widget" \
    || fail "network reference presentation drifted: $contract"
done

v2_meter=$(sed -n '/^  component V2TrafficMeter: Item {$/,/^  }$/p' "$widget")
for source_contract in \
  'color: Qt.rgba(parent.ink.r, parent.ink.g, parent.ink.b, 0.72)' \
  'font.family: root.v2MonoFont' \
  'y: 13' \
  'Behavior on color { ColorAnimation { duration: 160 } }'; do
  grep -Fq "$source_contract" <<<"$v2_meter" \
    || fail "V2 RX/TX meter drifted from source: $source_contract"
done

printf 'network plugin regression passed\n'
