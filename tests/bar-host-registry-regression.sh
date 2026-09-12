#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
bar_root="$repo_root/hancore.shibumi.bar"
omarchy_path=$OMARCHY_PATH

fail() {
  printf 'bar host registry regression failed: %s\n' "$*" >&2
  exit 1
}

for endpoint in 'function prepareShutdown(): string' \
    'function openControlCenter(): string' \
    'function closeControlCenter(): string' \
    'function setWidgetAppearanceForVariant(groupId: string, variant: string,'; do
  rg -Fq "$endpoint" "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "missing Shibumi Control Center IPC endpoint: $endpoint"
done
rg -Fq 'if (name !== "separator") return "variant-required"' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "legacy appearance IPC still accepts variant-scoped keys"
for v2_native_widget in \
    'hancore.shibumi.temperature' \
    'hancore.shibumi.gpu' \
    'hancore.shibumi.storage'; do
  rg -Fq "\"$v2_native_widget\"" "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "V2 does not suppress the V1 provider entry for $v2_native_widget"
done
rg -Fq '!GroupRegistry.isAssignedModule(id)' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "assigned suite widgets do not require explicit V1 installation"
rg -Fq 'else if (isV1AdditionalSuiteWidget(id))' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "V1 suite removal does not preserve the neutral host entry"
for provider_lifecycle_contract in \
    'function onPluginsChanged()' \
    'v1PluginReconcileTimer.restart()' \
    'function restoreWidgetFamilyProviderStates(stateValues)' \
    'function removeBarWidgetAndRestoreFamilies(widgetId, groupValues)' \
    'function conflictingLayoutProviderIds(widgetId)'; do
  rg -Fq "$provider_lifecycle_contract" \
    "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "provider lifecycle contract drifted: $provider_lifecycle_contract"
done
for shutdown_contract in \
    'function prepareForShutdown()' \
    'outputWindowsEnabled = false' \
    'if (!shutdownPrepared) applyBarConfig()'; do
  rg -Fq "$shutdown_contract" "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "bar shutdown contract drifted: $shutdown_contract"
done

for bar_host in \
    "$repo_root/Bar.qml" \
    "$repo_root/hancore.shibumi.bar/Bar.qml"; do
  for fixed_property in \
      'readonly property bool requestedTransparent: false' \
      'readonly property bool transparent: false'; do
    rg -Fq "$fixed_property" "$bar_host" \
      || fail "opaque facade contract drifted in ${bar_host#"$repo_root"/}: $fixed_property"
  done
  if rg -q 'config\.transparent|^[[:space:]]*(requestedTransparent|transparent)[[:space:]]*=' \
      "$bar_host"; then
    fail "Shibumi applies the stock transparency preference in ${bar_host#"$repo_root"/}"
  fi
  rg -Uq 'function setRequestedTransparency\(value\) \{[^}]*return false' \
    "$bar_host" \
    || fail "transparency compatibility method is not a no-op in ${bar_host#"$repo_root"/}"
  rg -Fq 'function toggleGroupSeparator(groupId, editingValue)' "$bar_host" \
    || fail "V2 separator route lacks edit context in ${bar_host#"$repo_root"/}"
  rg -Fq 'layoutStateController.interactiveMutationAllowed(editingValue)' \
    "$bar_host" \
    || fail "V2 separator route bypasses layout protection in ${bar_host#"$repo_root"/}"
done

for bar_surface in \
    "$repo_root/styles/shibumi/BarSurface.qml" \
    "$repo_root/hancore.shibumi.bar/styles/shibumi/BarSurface.qml"; do
  rg -Fq 'visible: true' "$bar_surface" \
    || fail "V1/V2 chrome is not explicitly opaque in ${bar_surface#"$repo_root"/}"
  if rg -q 'bar\.transparent' "$bar_surface"; then
    fail "bar surface still consumes stock transparency in ${bar_surface#"$repo_root"/}"
  fi
done

[[ -n $omarchy_path && -d $omarchy_path/shell ]] \
  || fail 'OMARCHY_PATH must reference a Quattro checkout'
[[ -x /usr/bin/quickshell ]] || fail 'quickshell is required'
"$repo_root/scripts/sync-bar-host.sh" --check >/dev/null

tmpdir=$(mktemp -d /tmp/shibumi-bar-host.XXXXXX)
ipc_pid=""
cleanup() {
  if [[ -n $ipc_pid ]]; then
    kill "$ipc_pid" 2>/dev/null || true
    wait "$ipc_pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmpdir"
}
trap cleanup EXIT
mkdir -p "$tmpdir/home" "$tmpdir/runtime" "$tmpdir/fixtures" "$tmpdir/native"
chmod 700 "$tmpdir/runtime"
# Standalone and nested control runs must not inherit production XDG/bus paths.
export HOME="$tmpdir/home" XDG_CONFIG_HOME="$tmpdir/home/.config"
export XDG_STATE_HOME="$tmpdir/home/.local/state" XDG_DATA_HOME="$tmpdir/home/.local/share"
export XDG_CACHE_HOME="$tmpdir/home/.cache" XDG_DATA_DIRS="$tmpdir/data"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$tmpdir/absent-session"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$tmpdir/absent-system"
export HYPRLAND_INSTANCE_SIGNATURE='' WAYLAND_DISPLAY='' DISPLAY=''
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export QT_FORCE_STDERR_LOGGING=1 QML_DISABLE_DISK_CACHE=1

cp -a "$omarchy_path/shell/Commons" "$tmpdir/"
cp -a "$omarchy_path/shell/Ui" "$tmpdir/"
cp -a "$bar_root/core" "$tmpdir/"
cp "$repo_root/tests/fixtures/BarPanelStub.qml" "$tmpdir/core/BarPanel.qml"
mkdir -p "$tmpdir/services"
cp "$bar_root/services/HostWidgetResolver.qml" "$tmpdir/services/"
cp -a "$bar_root/styles" "$tmpdir/"
# This fixture lays Bar.qml at its root, so use the canonical relative import.
# sync-bar-host --check above verifies the sole deployment-path normalization.
cp "$repo_root/Bar.qml" "$tmpdir/Bar.qml"
# Calibrated controls alter only the captured fixture, never repository sources.
python3 - "$tmpdir/Bar.qml" "${SHIBUMI_TEST_RESTORE_CONTROL:-none}" <<'PY'
import sys
from pathlib import Path
path, mode = Path(sys.argv[1]), sys.argv[2]
controls = {
    'navigation-rollback': ('if (record.scheduled && live.restoreRevision !== record.restoreRevision) continue',
        'if (record.scheduled && (live !== record.scheduled || live.restoreRevision !== record.restoreRevision)) continue'),
    'output-dedup': ('if (Object.prototype.hasOwnProperty.call(outputs, screenName)) continue', ''),
    'bar-admission': ('return root.restoreAdmitted && (!record.stateBound', 'return (!record.stateBound'),
    'sync-settlement': ('activeRestoreCalls.push(call)', '// control: settlement not observed during callback'),
    'rejected-existing': ('if (record.created === false) {', 'if (record.created === false) { continue'),
    'window-reset': ('page: String(page || current.page || ""),\n        attempts: 0,',
        'page: String(page || current.page || ""),\n        attempts: Number(current.attempts || 0),'),
    'pending-window': ('if (record.waitingWrites && record.waitingWrites.length) continue', ''),
    'native-window': ('if (record.waitingLayout) continue', ''),
    'false-settlement': ('const changed = result === "confirmed" || (result === "unchanged"\n'
        '        && completed.some(function(request) { return request.revision !== revision }))',
        'const changed = true'),
    'snapshot-replay': ('if (root.pendingWidgetRestores.length === 0) stop()',
        'root.pendingWidgetRestores = records.filter(record => record.attempts < 20)\n'
        '      if (root.pendingWidgetRestores.length === 0) stop()'),
}
if mode != 'none':
    if mode not in controls:
        raise SystemExit('unknown restore control')
    old, new = controls[mode]
    source = path.read_text()
    if source.count(old) != 1:
        raise SystemExit('restore control anchor drifted')
    path.write_text(source.replace(old, new))
PY
mkdir -p "$tmpdir/hancore.shibumi.state"
cp -a "$repo_root/hancore.shibumi.state/runtime" "$tmpdir/hancore.shibumi.state/"
cp "$repo_root/tests/fixtures/ResolverTestWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/ResolverReplacementWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/CloneSelectionChecks.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/StateRestoreChecks.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/LayoutRestoreChecks.qml" "$tmpdir/fixtures/"
cp "$omarchy_path/shell/services/PluginRegistry.qml" "$tmpdir/native/"
python3 - "$repo_root" "$tmpdir" <<'PY'
import sys
from pathlib import Path
repo, target = map(Path, sys.argv[1:])
panel = (repo / 'hancore.shibumi.control-center/ControlCenterPanel.qml').read_text()
start = panel.index('  function removePlugin(pluginId) {')
end = panel.index('  function rescanPlugins() {', start)
fixture = (repo / 'tests/fixtures/PluginRemovalChecks.qml').read_text()
if fixture.count('  // INJECT_REMOVE_PLUGIN') != 1:
    raise SystemExit('plugin removal fixture injection marker drifted')
(target / 'fixtures/PluginRemovalChecks.qml').write_text(
    fixture.replace('  // INJECT_REMOVE_PLUGIN', panel[start:end]))
PY
cp "$repo_root/tests/fixtures/DirectPreferredHostedPanelWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/MisleadingItemHostedPanelWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/NestedHostedPanelWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/hosted-panel-loader-smoke.qml" "$tmpdir/shell.qml"

set +e
nested_output=$(timeout 8 env \
  HOME="$tmpdir/home" \
  WAYLAND_DISPLAY= \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" 2>&1)
nested_rc=$?
set -e
printf '%s\n' "$nested_output"

[[ $nested_rc -eq 0 ]] || fail "nested hosted-panel smoke exited $nested_rc"
grep -q 'hosted panel loader smoke passed' <<<"$nested_output" \
  || fail 'nested hosted-panel smoke did not reach its success marker'
if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load' \
    <<<"$nested_output"; then
  fail 'nested hosted-panel runtime log contains a composition error'
fi

sed "s#testOmarchyPath#\"${omarchy_path//\\/\\\\}\"#" \
  "$repo_root/tests/bar-host-registry-smoke.qml" \
  | sed "s#testCommandMarker#\"$tmpdir/run-marker\"#" \
  > "$tmpdir/shell.qml"

set +e
output=$(timeout 15 env \
  HOME="$tmpdir/home" \
  WAYLAND_DISPLAY= \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" 2>&1)
rc=$?
set -e
printf '%s\n' "$output"

[[ $rc -eq 0 ]] || fail "smoke exited $rc"
grep -q 'bar host registry smoke passed' <<<"$output" \
  || fail 'smoke did not reach its success marker'
grep -q 'asynchronous output-local State restoration passed' <<<"$output" \
  || fail 'asynchronous restore fixture did not reach its success marker'
grep -q 'actual Bar restoration waited for separate native publication passed' <<<"$output" \
  || fail 'native layout restore fixture did not reach its success marker'
[[ $(<"$tmpdir/run-marker") == ok ]] \
  || fail 'bar run() did not execute through the Quattro host contract'
if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load|rejected invalid bar style' \
    <<<"$output"; then
  fail 'runtime log contains a host composition error'
fi

# A fresh engine receives an admitted shared-runtime marker and controlled
# scoped services. It has no live shell, network or platform mutation route.
printf '%s\n' '{"suiteId":"hancore.shibumi","suitePayloadDigest":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}' \
  > "$tmpdir/hancore.shibumi.state/.shibumi-managed.json"
cp "$repo_root/tests/bar-catalog-consumer-smoke.qml" "$tmpdir/shell.qml"
set +e
catalog_output=$(timeout 8 env \
  HOME="$tmpdir/home" \
  WAYLAND_DISPLAY= \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" 2>&1)
catalog_rc=$?
set -e
printf '%s\n' "$catalog_output"
[[ $catalog_rc -eq 0 ]] || fail "catalog consumer smoke exited $catalog_rc"
grep -q 'bar catalog consumer smoke passed' <<<"$catalog_output" \
  || fail 'catalog consumer smoke did not reach its success marker'
if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load|rejected invalid bar style' \
    <<<"$catalog_output"; then
  fail 'catalog consumer runtime log contains a composition error'
fi

cp "$repo_root/tests/bar-shutdown-ipc-smoke.qml" "$tmpdir/shell.qml"
ipc_log="$tmpdir/bar-shutdown-ipc.log"
env HOME="$tmpdir/home" WAYLAND_DISPLAY= QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" --no-color >"$ipc_log" 2>&1 &
ipc_pid=$!
ipc_response=""
for _ in {1..80}; do
  if ! kill -0 "$ipc_pid" 2>/dev/null; then
    cat "$ipc_log" >&2
    fail 'shutdown IPC smoke exited before the endpoint became ready'
  fi
  set +e
  ipc_response=$(env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
    /usr/bin/quickshell ipc --pid "$ipc_pid" call \
      shibumi-suite prepareShutdown 2>/dev/null)
  ipc_rc=$?
  set -e
  [[ $ipc_rc -eq 0 && $ipc_response == ok ]] && break
  sleep 0.05
done
[[ $ipc_response == ok ]] \
  || fail 'shutdown IPC endpoint did not return ok'
set +e
wait "$ipc_pid"
ipc_rc=$?
set -e
ipc_pid=""
ipc_output=$(<"$ipc_log")
printf '%s\n' "$ipc_output"
[[ $ipc_rc -eq 0 ]] || fail "shutdown IPC smoke exited $ipc_rc"
grep -q 'bar shutdown IPC smoke passed' <<<"$ipc_output" \
  || fail 'shutdown IPC smoke did not observe the prepared bar'
if grep -Eq 'another handler is registered for target shibumi-suite|Binding loop|TypeError|ReferenceError' \
    <<<"$ipc_output"; then
  fail 'shutdown IPC smoke log contains an ownership or binding error'
fi

printf 'bar host registry regression passed\n'
