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

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures" "$tmpdir/bin"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.network" "$tmpdir/network"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/network-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/NetworkTestService.qml" \
  "$repo_root/tests/fixtures/NetworkTestView.qml" \
  "$repo_root/tests/fixtures/NetworkTestPanel.qml" \
  "$repo_root/tests/fixtures/NetworkCurrentTestPanel.qml" "$tmpdir/fixtures/"
install -m 0755 "$repo_root/tests/fixtures/omarchy-network-speedtest" \
  "$repo_root/tests/fixtures/omarchy-network-speedtest-fail" \
  "$repo_root/tests/fixtures/omarchy-network-speedtest-empty" \
  "$repo_root/tests/fixtures/omarchy-network-speedtest-malformed" \
  "$repo_root/tests/fixtures/omarchy-network-speedtest-resistant" "$tmpdir/bin/"

set +e
output=$(timeout 12 env \
  PATH="$tmpdir/bin:$PATH" \
  SHIBUMI_SPEEDTEST_PID_LOG="$tmpdir/speedtest-pids" \
  SHIBUMI_SPEEDTEST_CHILD_PID_LOG="$tmpdir/speedtest-child-pids" \
  SHIBUMI_SPEEDTEST_RESISTANT_PID_LOG="$tmpdir/speedtest-resistant-pid" \
  SHIBUMI_SPEEDTEST_RESISTANT_CHILD_PID_LOG="$tmpdir/speedtest-resistant-child-pid" \
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
for pid_log in "$tmpdir/speedtest-pids" "$tmpdir/speedtest-child-pids" \
    "$tmpdir/speedtest-resistant-pid" \
    "$tmpdir/speedtest-resistant-child-pid"; do
  [[ -s $pid_log ]] || fail "speed-test cleanup fixture did not record PIDs"
  while IFS= read -r pid; do
    for _ in {1..50}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.02
    done
    kill -0 "$pid" 2>/dev/null \
      && fail "speed-test teardown left process $pid alive"
  done <"$pid_log"
done

normal_pid_log="$tmpdir/bounded-parent-pid"
normal_child_pid_log="$tmpdir/bounded-child-pid"
PATH="$tmpdir/bin:$PATH" \
SHIBUMI_SPEEDTEST_PID_LOG="$normal_pid_log" \
SHIBUMI_SPEEDTEST_CHILD_PID_LOG="$normal_child_pid_log" \
  "$repo_root/hancore.shibumi.network/InlineSpeedTestRunner.py" \
  omarchy-network-speedtest down >"$tmpdir/bounded-output" 2>&1 &
bounded_runner_pid=$!
for _ in {1..50}; do
  [[ -s $tmpdir/bounded-output ]] && break
  sleep 0.02
done
[[ -s $tmpdir/bounded-output ]] || fail "bounded cleanup runner produced no sample"
start_ns=$(date +%s%N)
kill -TERM "$bounded_runner_pid"
wait "$bounded_runner_pid" \
  || fail "bounded cleanup runner did not stop successfully"
elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
(( elapsed_ms < 1500 )) \
  || fail "normal speed-test cleanup took ${elapsed_ms}ms"
for pid_log in "$normal_pid_log" "$normal_child_pid_log"; do
  [[ -s $pid_log ]] || fail "bounded cleanup fixture did not record PIDs"
  while IFS= read -r pid; do
    kill -0 "$pid" 2>/dev/null \
      && fail "bounded cleanup left process $pid alive"
  done <"$pid_log"
done

if grep -F 'Binding loop detected' <<<"$output" >/dev/null; then
  fail "V1/V2 network presentation produced a binding loop"
fi

widget="$repo_root/hancore.shibumi.network/BarWidget.qml"
service="$repo_root/hancore.shibumi.network/Service.qml"
bridge="$repo_root/hancore.shibumi.network/NetworkPanelBridge.qml"
runner="$repo_root/hancore.shibumi.network/InlineSpeedTestRunner.py"
rg -Fq 'property string speedTestExecutable: "omarchy-network-speedtest"' \
  "$service" || fail "network service does not use the host speed-test command"
rg -Fq 'Qt.resolvedUrl("InlineSpeedTestRunner.py")' "$service" \
  || fail "network service does not resolve its crash-safe inline runner"
rg -Fq 'id: speedTestProc' "$service" \
  || fail "network service does not own the inline speed-test process"
rg -Fq 'String(speedTestExecutable || ""), String(phaseValue || "")' "$service" \
  || fail "network service does not pass down/up phases to the command"
rg -Fq 'stdout: SplitParser {' "$service" \
  || fail "network service does not consume live speed-test samples"
rg -Fq 'if (nextOwners.length === 0) stopSpeedTest()' "$service" \
  || fail "network service does not stop traffic after the final panel closes"
rg -Fq 'property bool speedTestPendingRun: false' "$service" \
  || fail "network service cannot queue an immediate close/reopen run"
rg -Fq 'if (speedTestPendingRun) {' "$service" \
  || fail "queued speed test does not restart after cleanup exit"
rg -Fq 'speedTestPhaseHasSample()' "$service" \
  || fail "network service accepts empty speed-test phases"
rg -Fq 'if (!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw)) return' "$service" \
  || fail "network service accepts malformed partial-number samples"
rg -Fq 'Unable to start network speed test' "$service" \
  || fail "network service does not surface process-start failures"
rg -Fq 'start_new_session=True' "$runner" \
  || fail "inline runner does not isolate the traffic process group"
rg -Fq 'supervise_worker' "$runner" \
  || fail "inline runner lacks a pre-spawn crash-safe cleanup owner"
rg -Fq 'os.killpg(process_group, signal.SIGKILL)' "$runner" \
  || fail "inline runner cannot escalate cleanup for resistant descendants"
if rg -q 'speedTestPanel|speedTestBackend|legacySpeedTestBackend|speedTestModalOpen' \
    "$repo_root/hancore.shibumi.network"; then
  fail "network plugin still embeds an official Omarchy speed-test panel/backend"
fi
[[ $(rg -c 'String\(id \|\| ""\) === "omarchy\.speedtest"' "$bridge") -eq 1 ]] \
  || fail "network bridge does not intercept the host speed-test summon exactly once"
rg -Fq 'networkService.runSpeedTest()' "$bridge" \
  || fail "host speed-test compatibility route does not use Shibumi's inline owner"
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
rg -Fq 'startSpeedTestPhase("down")' "$service" \
  || fail "inline speed test does not start its Shibumi-owned download phase"
rg -Fq 'startSpeedTestPhase("up")' "$service" \
  || fail "inline speed test does not advance to its Shibumi-owned upload phase"
if rg -q 'showSpeedTest\(|registeredPanelSource\("omarchy\.speedtest"\)|speedTestModalOpen' \
    "$repo_root/hancore.shibumi.network"; then
  fail "network plugin opens or embeds Omarchy's external speed-test panel"
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
