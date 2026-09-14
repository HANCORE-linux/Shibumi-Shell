#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/shibumi-widget-pipeline.XXXXXX")
qs_pid=""

fail() {
  printf 'widget pipeline diagnostics regression failed: %s\n' "$*" >&2
  exit 1
}

stop_group() {
  local pid=$1
  kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in {1..30}; do
    pgrep -g "$pid" >/dev/null 2>&1 || break
    sleep 0.05
  done
  if pgrep -g "$pid" >/dev/null 2>&1; then
    kill -KILL -- "-$pid" 2>/dev/null || true
    for _ in {1..30}; do
      pgrep -g "$pid" >/dev/null 2>&1 || break
      sleep 0.05
    done
  fi
  wait "$pid" 2>/dev/null || true
  ! pgrep -g "$pid" >/dev/null 2>&1
}

cleanup() {
  if [[ -n $qs_pid ]]; then
    stop_group "$qs_pid" || true
  fi
  rm -rf -- "$tmpdir"
}
trap cleanup EXIT

[[ -x $quickshell_bin ]] || fail "Quickshell executable is missing: $quickshell_bin"
command -v pgrep >/dev/null 2>&1 || fail 'pgrep is required'
[[ -d $omarchy_path/shell/Commons ]] \
  || fail "pinned Omarchy Commons tree is missing: $omarchy_path/shell/Commons"

mkdir -p "$tmpdir"/{home,config,cache,data,state,runtime}
chmod 700 "$tmpdir/runtime"
cp -a "$repo_root/hancore.shibumi.bar" "$tmpdir/"
# The focused IPC test creates no output surface; keep platform windows out of
# this fixture while retaining the production Bar/WidgetSlot diagnostic path.
cp "$repo_root/tests/fixtures/BarPanelStub.qml" \
  "$tmpdir/hancore.shibumi.bar/core/BarPanel.qml"
cp -a "$repo_root/hancore.shibumi.state" "$tmpdir/"
cp -a "$omarchy_path/shell/Commons" "$tmpdir/"
cp "$repo_root/tests/widget-pipeline-diagnostics-smoke.qml" "$tmpdir/shell.qml"
printf '%s\n' \
  '{"suiteId":"hancore.shibumi","suitePayloadDigest":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}' \
  > "$tmpdir/.shibumi-managed.json"
cp "$tmpdir/.shibumi-managed.json" \
  "$tmpdir/hancore.shibumi.state/.shibumi-managed.json"
cp "$tmpdir/.shibumi-managed.json" \
  "$tmpdir/hancore.shibumi.bar/.shibumi-managed.json"

setsid env \
  HOME="$tmpdir/home" \
  XDG_CONFIG_HOME="$tmpdir/config" \
  XDG_CACHE_HOME="$tmpdir/cache" \
  XDG_DATA_HOME="$tmpdir/data" \
  XDG_STATE_HOME="$tmpdir/state" \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  WAYLAND_DISPLAY= \
  DBUS_SESSION_BUS_ADDRESS=unix:path="$tmpdir/runtime/no-session-bus" \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  "$quickshell_bin" -p "$tmpdir" --no-color \
  >"$tmpdir/quickshell.log" 2>&1 &
qs_pid=$!

for _ in {1..160}; do
  if grep -q 'WIDGET_PIPELINE_DIAGNOSTICS_READY' "$tmpdir/quickshell.log"; then
    break
  fi
  if ! kill -0 "$qs_pid" 2>/dev/null; then
    cat "$tmpdir/quickshell.log" >&2
    fail 'QML fixture exited before its ready marker'
  fi
  sleep 0.05
done
grep -q 'WIDGET_PIPELINE_DIAGNOSTICS_READY' "$tmpdir/quickshell.log" || {
  cat "$tmpdir/quickshell.log" >&2
  fail 'QML fixture did not reach its ready marker'
}

report=""
for _ in {1..80}; do
  set +e
  report=$(env XDG_RUNTIME_DIR="$tmpdir/runtime" WAYLAND_DISPLAY= \
    "$quickshell_bin" ipc --pid "$qs_pid" call \
      shibumi-suite debugWidgetPipeline 2>/dev/null)
  ipc_rc=$?
  set -e
  [[ $ipc_rc -eq 0 && $report == \{* ]] && break
  sleep 0.05
done
[[ $report == \{* ]] || fail 'debugWidgetPipeline IPC did not return JSON'

printf '%s' "$report" | python3 -c '
import json, sys
state = json.load(sys.stdin)
assert set(state) == {"version", "facades", "outputs", "outputLifecycle", "registry", "expected", "widgetSlots"}
assert state["version"] == 2
assert state["facades"] == {
    "shellScoped": True,
    "pluginRegistryScoped": True,
    "widgetRegistryPresent": True,
}
assert state["registry"] == {
    "snapshotKeyCount": 256,
    "snapshotKeyCountTruncated": True,
    "revision": 73,
}
assert state["expected"]["truncated"] is True
assert len(state["expected"]["entries"]) == 64
expected = state["expected"]["entries"][0]
assert expected == {
    "id": "fixture.widget-0",
    "configured": True,
    "selection": True,
    "componentPresent": False,
    "componentStatusKind": "missing",
    "componentStatus": -1,
}
expected_by_id = {row["id"]: row for row in state["expected"]["entries"]}
for row in state["expected"]["entries"]:
    assert set(row) == {"id", "configured", "selection", "componentPresent",
                        "componentStatusKind", "componentStatus"}
    assert type(row["componentPresent"]) is bool
    assert row["componentStatusKind"] in {
        "missing", "undefined", "number", "other", "unavailable"
    }
    assert type(row["componentStatus"]) is int
assert expected_by_id["fixture.widget-1"]["componentPresent"] is True
assert expected_by_id["fixture.widget-1"]["componentStatusKind"] == "undefined"
assert expected_by_id["fixture.widget-1"]["componentStatus"] == -1
assert expected_by_id["fixture.widget-2"]["componentPresent"] is True
assert expected_by_id["fixture.widget-2"]["componentStatusKind"] == "other"
assert expected_by_id["fixture.widget-2"]["componentStatus"] == -1
assert expected_by_id["fixture.widget-3"]["componentPresent"] is True
assert expected_by_id["fixture.widget-3"]["componentStatusKind"] == "number"
assert state["outputs"]["validOutputCount"] == 0
assert state["outputLifecycle"] == {
    "presenceObserved": True,
    "lossObserved": True,
    "returnObserved": True,
    "sequence": "positive-zero-positive",
    "previouslyReadyWidgetCount": 1,
    "lossReadyWidgetCount": 1,
    "warningEmitted": False,
}
assert state["outputs"]["barPanelCount"] == 20
assert state["outputs"]["layoutSessionCount"] == 20
assert state["outputs"]["truncated"] is True
assert len(state["outputs"]["sessions"]) == 16
assert state["outputs"]["sessions"][0]["screen"] == ""
assert state["widgetSlots"]["count"] == 141
assert state["widgetSlots"]["truncated"] is True
assert len(state["widgetSlots"]["entries"]) == 128
unresolved = [row for row in state["widgetSlots"]["entries"]
              if row["id"] == "fixture.widget-0"]
assert len(unresolved) == 1
assert unresolved[0]["resolvedComponentPresent"] is False
assert unresolved[0]["resolvedComponentStatusKind"] == "missing"
assert unresolved[0]["resolvedStatus"] == -1
assert unresolved[0]["currentLoadReady"] is False
assert unresolved[0]["loaderActive"] is False
assert unresolved[0]["loaderItem"] is False
slots_by_id = {row["id"]: row for row in state["widgetSlots"]["entries"]}
for row in state["widgetSlots"]["entries"]:
    assert set(row) == {"id", "screen", "moduleEnabled", "resolutionAttempts",
                        "resolvedComponentPresent", "resolvedComponentStatusKind",
                        "resolvedStatus", "currentLoadReady", "loaderActive",
                        "loaderStatus", "loaderItem"}
    assert type(row["resolvedComponentPresent"]) is bool
    assert row["resolvedComponentStatusKind"] in {
        "missing", "undefined", "number", "other", "unavailable"
    }
    assert type(row["resolvedStatus"]) is int
    assert type(row["currentLoadReady"]) is bool
assert slots_by_id["fixture.slot-0"]["resolvedComponentPresent"] is True
assert slots_by_id["fixture.slot-0"]["resolvedComponentStatusKind"] == "undefined"
assert slots_by_id["fixture.slot-0"]["resolvedStatus"] == -1
assert slots_by_id["fixture.slot-0"]["currentLoadReady"] is False
assert slots_by_id["fixture.slot-1"]["resolvedComponentPresent"] is True
assert slots_by_id["fixture.slot-1"]["resolvedComponentStatusKind"] == "other"
assert slots_by_id["fixture.slot-1"]["resolvedStatus"] == -1
assert slots_by_id["fixture.slot-1"]["currentLoadReady"] is False
serialized = json.dumps(state, separators=(",", ":"))
for forbidden in ("/home/private-user", "credential", "sourceUrl",
                  "privateMetadata", "backend", "metadata"):
    assert forbidden not in serialized
'

if grep -Eq 'WIDGET_PIPELINE_(DIAGNOSTICS_(ASSERTION_FAILED|TIMEOUT)|OUTPUT_LIFECYCLE_ASSERTION_FAILED)|Binding loop|TypeError|ReferenceError|is not a type|failed to load' \
    "$tmpdir/quickshell.log"; then
  cat "$tmpdir/quickshell.log" >&2
  fail 'QML fixture log contains a composition or assertion error'
fi

stop_group "$qs_pid" \
  || fail 'QML fixture process group survived bounded shutdown'
qs_pid=""

printf 'Widget pipeline diagnostics regression passed (bounded unresolved-slot IPC)\n'
