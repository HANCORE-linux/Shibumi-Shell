#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
bar_root="$repo_root/hancore.shibumi.bar"
omarchy_path=$OMARCHY_PATH
widget_slot_source=${SHIBUMI_TEST_WIDGET_SLOT_SOURCE:-$bar_root/core/WidgetSlot.qml}

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
[[ $(rg -Fc 'target: "omarchy.bar"' \
  "$repo_root/hancore.shibumi.state/runtime/Runtime.qml") -eq 1 ]] \
  || fail 'shared runtime does not uniquely own the Omarchy visibility nudge'
rg -Fq 'enabled: runtime.visibilityIpcArmed' \
  "$repo_root/hancore.shibumi.state/runtime/Runtime.qml" \
  || fail 'Omarchy visibility nudge is not gated by delayed singleton admission'
rg -Fq 'owner.barConfig.id !== lease.id' \
  "$repo_root/hancore.shibumi.state/runtime/Runtime.qml" \
  || fail 'outgoing Shibumi visibility ownership is not revoked before host takeover'
rg -Fq 'function syncHidden()' "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail 'active Shibumi bar does not implement the Omarchy visibility nudge'
for restore_contract in \
    'widget.panelItem.settingsPageReady !== true' \
    'widget.panelItem.settingsPageReady === true' \
    'item.restoreId === record.restoreId' \
    '&& item.restoreRevision === record.restoreRevision' \
    'Never let a missing owner fall back to another output.'; do
  rg -Fq "$restore_contract" "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "Control Center restore contract drifted: $restore_contract"
done
if rg -Fq 'record.needsReplacement && widget === record.owner' \
    "$repo_root/hancore.shibumi.bar/Bar.qml"; then
  fail 'ready Control Center restore still vetoes its current owner'
fi
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
    "$repo_root/hancore.shibumi.bar/styles/shibumi/BarSurface.qml"; do
  rg -Fq 'visible: true' "$bar_surface" \
    || fail "V1/V2 chrome is not explicitly opaque in ${bar_surface#"$repo_root"/}"
  if rg -q 'bar\.transparent' "$bar_surface"; then
    fail "bar surface still consumes stock transparency in ${bar_surface#"$repo_root"/}"
  fi
done

[[ -n $omarchy_path && -d $omarchy_path/shell ]] \
  || fail 'OMARCHY_PATH must reference a Quattro checkout'
[[ -f $widget_slot_source ]] || fail 'WidgetSlot fixture source is missing'
[[ -x /usr/bin/quickshell ]] || fail 'quickshell is required'

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
cp -a "$bar_root" "$tmpdir/hancore.shibumi.bar"

# Exercise WidgetSlot teardown in the host-owned gate without another runner.
# This private engine has no production bus, display, PATH, or PipeWire route.
lifecycle_root="$tmpdir/lifecycle"
mkdir -p "$lifecycle_root/staged/barcore" "$lifecycle_root/home" \
  "$lifecycle_root/runtime" "$lifecycle_root/tmp" "$lifecycle_root/bin" \
  "$lifecycle_root/config-dirs" "$lifecycle_root/pipewire"
chmod 700 "$lifecycle_root/runtime" "$lifecycle_root/tmp" \
  "$lifecycle_root/pipewire"
cp -a "$omarchy_path/shell/Commons" "$lifecycle_root/"
install -m 0644 "$widget_slot_source" \
  "$lifecycle_root/staged/barcore/WidgetSlot.qml"
install -m 0644 "$repo_root/tests/fixtures/BarContextLifecycleHost.qml" \
  "$lifecycle_root/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/PrivateLifecycleBar.qml" \
  "$lifecycle_root/PrivateLifecycleBar.qml"
set +e
lifecycle_output=$(timeout --foreground --kill-after=1 10 env \
  HOME="$lifecycle_root/home" \
  XDG_CONFIG_HOME="$lifecycle_root/home/.config" \
  XDG_STATE_HOME="$lifecycle_root/home/.local/state" \
  XDG_DATA_HOME="$lifecycle_root/home/.local/share" \
  XDG_CACHE_HOME="$lifecycle_root/home/.cache" \
  XDG_DATA_DIRS="$lifecycle_root/data" \
  XDG_CONFIG_DIRS="$lifecycle_root/config-dirs" \
  XDG_RUNTIME_DIR="$lifecycle_root/runtime" TMPDIR="$lifecycle_root/tmp" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$lifecycle_root/absent-session" \
  DBUS_SYSTEM_BUS_ADDRESS="unix:path=$lifecycle_root/absent-system" \
  PIPEWIRE_RUNTIME_DIR="$lifecycle_root/pipewire" \
  PIPEWIRE_REMOTE=shibumi-fixture-unavailable \
  HYPRLAND_INSTANCE_SIGNATURE= WAYLAND_DISPLAY= DISPLAY= \
  PATH="$lifecycle_root/bin" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
  QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 QML_DISABLE_DISK_CACHE=1 \
  /usr/bin/quickshell -p "$lifecycle_root" --no-color 2>&1)
lifecycle_rc=$?
set -e
printf '%s\n' "$lifecycle_output"
[[ $lifecycle_rc -eq 0 ]] || fail "bar context lifecycle fixture exited $lifecycle_rc"
grep -Fq 'bar context lifecycle regression passed' <<<"$lifecycle_output" \
  || fail 'bar context lifecycle fixture did not reach its success marker'
grep -Fq 'registry-update-after-revoke' <<<"$lifecycle_output" \
  || fail 'bar context lifecycle fixture missed its post-revoke update'
if grep -Eqi 'attempted to evaluate a function in an invalid context|TypeError|ReferenceError|Binding loop|Unable to assign|Cannot assign|Internal error' \
    <<<"$lifecycle_output"; then
  fail 'bar context lifecycle fixture log contains a QML context or binding error'
fi

cp "$repo_root/tests/fixtures/BarPanelStub.qml" \
  "$tmpdir/hancore.shibumi.bar/core/BarPanel.qml"
# Preserve the deployed plugin depth so Bar.qml keeps its canonical
# ../hancore.shibumi.state/runtime import unchanged in the fixture.
# Calibrated controls alter only the captured fixture, never repository sources.
python3 - "$tmpdir/hancore.shibumi.bar/Bar.qml" \
  "${SHIBUMI_TEST_RESTORE_CONTROL:-none}" <<'PY'
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
        'const replay = records.some(record => !root.pendingWidgetRestores.some(item =>\n'
        '        item.restoreId === record.restoreId))\n'
        '      if (replay) root.pendingWidgetRestores = records.filter(record => record.attempts < 20)\n'
        '      if (root.pendingWidgetRestores.length === 0) stop()'),
    'same-owner-veto': ('if (!record || !widget || widget.opened !== true) return false',
        'if (!record || !widget || widget.opened !== true) return false\n'
        '    if (record.needsReplacement && widget === record.owner) return false'),
    'active-page-readiness': ('if (widget.panelLoaded !== true || !widget.panelItem\n'
        '            || widget.panelItem.settingsPageReady !== true) return false',
        'if (widget.panelLoaded !== true || !widget.panelItem) return false'),
    'page-readiness': ('const pageReady = widget.panelLoaded === true && widget.panelItem\n'
        '      && widget.panelItem.settingsPageReady === true\n'
        '      && String(widget.panelItem.settingsPage || "") === record.page',
        'const pageReady = widget.panelLoaded === true && widget.panelItem\n'
        '      && String(widget.panelItem.settingsPage || "") === record.page'),
    'copied-record-prune': ('const current = root.pendingWidgetRestores.findIndex(item =>\n'
        '          item.restoreId === record.restoreId\n'
        '            && item.restoreRevision === record.restoreRevision)',
        'const current = root.pendingWidgetRestores.indexOf(record)'),
    'revision-prune': ('const current = root.pendingWidgetRestores.findIndex(item =>\n'
        '          item.restoreId === record.restoreId\n'
        '            && item.restoreRevision === record.restoreRevision)',
        'const current = root.pendingWidgetRestores.findIndex(item =>\n'
        '          item.restoreId === record.restoreId)'),
    'output-prune': ('const current = root.pendingWidgetRestores.findIndex(item =>\n'
        '          item.restoreId === record.restoreId\n'
        '            && item.restoreRevision === record.restoreRevision)',
        'const current = root.pendingWidgetRestores.findIndex(item =>\n'
        '          item.restoreRevision === record.restoreRevision)'),
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
removal_start = panel.index('  function removePlugin(pluginId) {')
removal_end = panel.index('  function rescanPlugins() {', removal_start)
catalog_start = panel.index('  function pluginGlyph(pluginId, kinds) {')
catalog_end = panel.index('  function pluginActivationAvailable(entry) {', catalog_start)
group_states_start = panel.index('  function groupVariantStates(groupValues) {')
group_states_end = panel.index('  function setGroupEnabled(', group_states_start)
fixture = (repo / 'tests/fixtures/PluginRemovalChecks.qml').read_text()
for marker in ('  // INJECT_REMOVE_PLUGIN', '  // INJECT_BUILD_PLUGIN_ENTRIES'):
    if fixture.count(marker) != 1:
        raise SystemExit(f'plugin fixture injection marker drifted: {marker}')
fixture = fixture.replace(
    '  // INJECT_REMOVE_PLUGIN', panel[removal_start:removal_end])
fixture = fixture.replace('  // INJECT_BUILD_PLUGIN_ENTRIES',
    panel[catalog_start:catalog_end] + panel[group_states_start:group_states_end])
(target / 'fixtures/PluginRemovalChecks.qml').write_text(fixture)
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
if grep -Eq 'another handler is registered for target omarchy\.bar' \
    <<<"$output"; then
  fail 'overlapping Bar fixtures registered duplicate Omarchy visibility targets'
fi

# A fresh engine receives an admitted shared-runtime marker and controlled
# scoped services. It has no live shell, network or platform mutation route.
printf '%s\n' '{"suiteId":"hancore.shibumi","suitePayloadDigest":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}' \
  | tee "$tmpdir/hancore.shibumi.bar/.shibumi-managed.json" \
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

cp "$repo_root/tests/bar-visibility-ipc-smoke.qml" "$tmpdir/shell.qml"
visibility_bar="$tmpdir/hancore.shibumi.bar/Bar.qml"
cp "$visibility_bar" "$tmpdir/Bar.qml.before-visibility"
# This case is specifically about the IPC nudge. Disable the ordinary directory
# watcher in the isolated copy, and hold each sampled result long enough to
# force a deterministic in-flight marker change. Production bytes are untouched.
python3 - "$visibility_bar" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
watch = '''  FileView {
    path: root.hostReady ? root.home + "/.local/state/omarchy/toggles" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: root.requestBarHiddenProbe()
  }'''
quiet_watch = "  Item {} // fixture: ordinary bar-off directory watcher disabled"
command = '    command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]'
delayed = ('    command: ["bash", "-lc", "rm -f \\\"$HOME/probe-sampled\\\"; '
           'if [[ -f $HOME/.local/state/omarchy/toggles/bar-off ]]; then result=yes; '
           'else result=no; fi; : > \\\"$HOME/probe-sampled\\\"; sleep 0.15; echo \\\"$result\\\""]')
if source.count(watch) != 1 or source.count(command) != 1:
    raise SystemExit("visibility fixture calibration anchor drifted")
path.write_text(source.replace(watch, quiet_watch).replace(command, delayed))
PY
visibility_log="$tmpdir/bar-visibility-ipc.log"
toggle_dir="$tmpdir/home/.local/state/omarchy/toggles"
mkdir -p "$toggle_dir"
rm -f "$toggle_dir/bar-off" "$tmpdir/home/probe-sampled"
env HOME="$tmpdir/home" WAYLAND_DISPLAY= QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" --no-color >"$visibility_log" 2>&1 &
ipc_pid=$!

visibility_state=""
wait_visibility_state() {
  local expected=$1 label=$2
  for _ in {1..100}; do
    if ! kill -0 "$ipc_pid" 2>/dev/null; then
      cat "$visibility_log" >&2
      fail "bar visibility IPC smoke exited while waiting for $label"
    fi
    visibility_state=$(env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
      /usr/bin/quickshell ipc --pid "$ipc_pid" call \
        bar-visibility-test state 2>/dev/null || true)
    [[ $visibility_state == "$expected" ]] && return 0
    sleep 0.05
  done
  fail "bar visibility IPC smoke did not reach $label: $visibility_state"
}

wait_visibility_state handoff-gap 'the bounded incoming-handler gap'
touch "$toggle_dir/bar-off"
handoff_gap_response=$(env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
  /usr/bin/quickshell ipc --pid "$ipc_pid" call \
    omarchy.bar syncHidden 2>/dev/null || true)
[[ $handoff_gap_response == *'Target not found'* ]] \
  || fail 'incoming handoff gap unexpectedly retained an active visibility endpoint'
wait_visibility_state idle-hidden \
  'the arm-time resample of a marker changed during handoff'

rm -f "$toggle_dir/bar-off"
env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
  /usr/bin/quickshell ipc --pid "$ipc_pid" call \
    omarchy.bar syncHidden >/dev/null \
  || fail 'Omarchy visibility nudge did not accept the visible marker'
wait_visibility_state idle-visible 'the restored visible marker state'

# Sample hidden, mutate back to visible while that delayed sample is in flight,
# then require the one queued follow-up to publish the final marker state.
rm -f "$tmpdir/home/probe-sampled"
touch "$toggle_dir/bar-off"
env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
  /usr/bin/quickshell ipc --pid "$ipc_pid" call \
    omarchy.bar syncHidden >/dev/null \
  || fail 'Omarchy visibility nudge did not start the delayed hidden sample'
for _ in {1..80}; do
  [[ -e $tmpdir/home/probe-sampled ]] && break
  sleep 0.01
done
[[ -e $tmpdir/home/probe-sampled ]] \
  || fail 'delayed visibility probe did not sample the hidden marker'
rm -f "$toggle_dir/bar-off"
env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
  /usr/bin/quickshell ipc --pid "$ipc_pid" call \
    omarchy.bar syncHidden >/dev/null \
  || fail 'Omarchy visibility nudge did not queue the final visible sample'
wait_visibility_state idle-visible 'the coalesced final visible marker state'

# Revoke Shibumi from the host-injected bar identity before enabling the stock
# handler. This models the opposite handoff direction and catches a retained
# outgoing endpoint, not only delayed admission of the incoming one.
takeover_result=$(env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
  /usr/bin/quickshell ipc --pid "$ipc_pid" call \
    bar-visibility-test beginStockTakeover 2>/dev/null || true)
[[ $takeover_result == ok ]] || fail 'visibility fixture refused stock takeover'
wait_visibility_state stock-owner 'the stock visibility owner takeover'

visibility_finish=$(env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
  /usr/bin/quickshell ipc --pid "$ipc_pid" call \
    bar-visibility-test finish 2>/dev/null || true)
[[ $visibility_finish == ok ]] || fail 'visibility fixture refused clean completion'
set +e
wait "$ipc_pid"
visibility_rc=$?
set -e
ipc_pid=""
visibility_output=$(<"$visibility_log")
printf '%s\n' "$visibility_output"
[[ $visibility_rc -eq 0 ]] || fail "bar visibility IPC smoke exited $visibility_rc"
grep -q 'bar visibility IPC observed hidden marker' <<<"$visibility_output" \
  || fail 'bar visibility IPC smoke did not observe the handoff marker'
grep -q 'bar visibility IPC smoke passed' <<<"$visibility_output" \
  || fail 'bar visibility IPC smoke did not restore the visible marker'
if grep -Eq 'another handler is registered for target omarchy.bar|Binding loop|TypeError|ReferenceError' \
    <<<"$visibility_output"; then
  fail 'bar visibility IPC smoke log contains an ownership or binding error'
fi

# Calibrated negative control: with the watcher still disabled, a no-op Bar
# method must leave the marker invisible to the test despite successful IPC
# dispatch. This catches the exact false-positive path this regression guards.
python3 - "$visibility_bar" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
working = '''  function syncHidden() {
    return visibilityIpcReady && requestBarHiddenProbe()
  }'''
control = '''  function syncHidden() {
    return false // calibrated no-op control
  }'''
if source.count(working) != 1:
    raise SystemExit("visibility no-op control anchor drifted")
path.write_text(source.replace(working, control))
PY
visibility_control_log="$tmpdir/bar-visibility-noop-control.log"
rm -f "$toggle_dir/bar-off" "$tmpdir/home/probe-sampled"
env HOME="$tmpdir/home" WAYLAND_DISPLAY= QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" --no-color >"$visibility_control_log" 2>&1 &
ipc_pid=$!
visibility_log=$visibility_control_log
wait_visibility_state idle-visible 'the no-op control baseline'
touch "$toggle_dir/bar-off"
env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
  /usr/bin/quickshell ipc --pid "$ipc_pid" call \
    omarchy.bar syncHidden >/dev/null \
  || fail 'no-op visibility control endpoint was unavailable'
sleep 0.4
visibility_state=$(env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
  /usr/bin/quickshell ipc --pid "$ipc_pid" call \
    bar-visibility-test state 2>/dev/null || true)
[[ $visibility_state == idle-visible ]] \
  || fail 'no-op visibility control unexpectedly observed the hidden marker'
kill "$ipc_pid" 2>/dev/null || true
wait "$ipc_pid" 2>/dev/null || true
ipc_pid=""
visibility_control_output=$(<"$visibility_control_log")
printf '%s\n' "$visibility_control_output"
if grep -Eq 'another handler is registered for target omarchy.bar|Binding loop|TypeError|ReferenceError' \
    <<<"$visibility_control_output"; then
  fail 'bar visibility no-op control log contains an ownership or binding error'
fi
rm -f "$toggle_dir/bar-off" "$tmpdir/home/probe-sampled"
mv "$tmpdir/Bar.qml.before-visibility" "$visibility_bar"

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

OMARCHY_PATH="$omarchy_path" \
  "$repo_root/tests/scoped-loader-admission-regression.sh"

printf 'bar host registry regression passed\n'
