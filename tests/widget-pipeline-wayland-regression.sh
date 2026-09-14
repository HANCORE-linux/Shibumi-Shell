#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
stage_root=${SHIBUMI_WIDGET_PIPELINE_STAGE_ROOT:-}
if [[ -z $stage_root ]]; then
  native_shell=${SHIBUMI_NATIVE_SHELL_PATH:-}
  [[ -n $native_shell ]] || {
    printf 'widget pipeline Wayland regression failed: SHIBUMI_NATIVE_SHELL_PATH is required\n' >&2
    exit 1
  }
  exec /usr/bin/python3 "$repo_root/tests/widget-pipeline-native-regression.py" \
    --native-shell "$native_shell"
fi

if [[ ${SHIBUMI_WIDGET_PIPELINE_WAYLAND_DEADLINE_ACTIVE:-0} != 1 ]]; then
  exec env SHIBUMI_WIDGET_PIPELINE_WAYLAND_DEADLINE_ACTIVE=1 \
    timeout --foreground --signal=TERM --kill-after=10 \
      "${SHIBUMI_WIDGET_PIPELINE_WAYLAND_DEADLINE:-120}" "$0" "$@"
fi

quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
build_label=${SHIBUMI_WIDGET_PIPELINE_BUILD_LABEL:-unknown}
mode=${SHIBUMI_WIDGET_PIPELINE_MODE:-measure}
parent_runtime=${XDG_RUNTIME_DIR:-}
parent_display=${WAYLAND_DISPLAY:-}
lab_root=""
hypr_pid=""
qs_pid=""
nested_signature=""
nested_socket=""
output_name=""
report_count=0
first_loss=""
first_absent_registry_gap=""
harness_rescans=0
cycle_results='[]'

fail() {
  printf 'widget pipeline Wayland regression failed (%s): %s\n' "$build_label" "$*" >&2
  if [[ -n $lab_root ]]; then
    for log in "$lab_root/quickshell.log" "$lab_root/hyprland.log"; do
      if [[ -f $log ]]; then
        printf '%s tail:\n' "$log" >&2
        tail -c 131072 "$log" >&2 || true
      fi
    done
  fi
  exit 1
}

stop_group() {
  local pid=$1
  kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in {1..50}; do
    pgrep -g "$pid" >/dev/null 2>&1 || break
    sleep 0.05
  done
  if pgrep -g "$pid" >/dev/null 2>&1; then
    kill -KILL -- "-$pid" 2>/dev/null || true
    for _ in {1..50}; do
      pgrep -g "$pid" >/dev/null 2>&1 || break
      sleep 0.05
    done
  fi
  wait "$pid" 2>/dev/null || true
  ! pgrep -g "$pid" >/dev/null 2>&1
}

cleanup() {
  if [[ -n $qs_pid ]]; then stop_group "$qs_pid" || true; fi
  if [[ -n $hypr_pid ]]; then stop_group "$hypr_pid" || true; fi
  [[ -z $lab_root ]] || rm -rf -- "$lab_root"
}
trap cleanup EXIT

[[ $mode == measure || $mode == negative || $mode == mutant ]] \
  || fail "invalid fixture mode: $mode"
[[ -x $quickshell_bin ]] || fail "Quickshell executable is missing: $quickshell_bin"
[[ -f $stage_root/omarchy/shell/shell.qml ]] || fail 'staged native ShellRoot is missing'
[[ -d $stage_root/omarchy/shell/services ]] || fail 'staged native services are missing'
[[ -n $parent_runtime && -n $parent_display ]] \
  || fail 'a parent Wayland session is required only to host the nested compositor'
[[ -S $parent_runtime/$parent_display ]] \
  || fail "parent Wayland socket is missing: $parent_runtime/$parent_display"
for command in Hyprland bwrap hyprctl jq pgrep python3 setsid tail timeout unshare; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done

lab_root=$(mktemp -d "${TMPDIR:-/tmp}/swpw.XXXXXX")
mkdir -p "$lab_root"/{home,config,cache,data,state,runtime}
chmod 700 "$lab_root/runtime"
cat >"$lab_root/hyprland.conf" <<'EOF'
monitor = , 800x600@60, 0x0, 1
misc {
  disable_hyprland_logo = true
  disable_splash_rendering = true
}
EOF

# Connect only one inherited Wayland fd to the parent, then enter a private
# user/network namespace before Hyprland starts. All compositor commands below
# remain bound to the private runtime and exact nested signature.
python3 - "$parent_runtime" "$parent_display" "$lab_root/runtime" \
    "$lab_root/home" "$lab_root/config" "$lab_root/cache" \
    "$lab_root/data" "$lab_root/state" "$lab_root/hyprland.conf" <<'PY' \
    >"$lab_root/hyprland.log" 2>&1 &
import os
import socket
import sys

(parent_runtime, parent_display, runtime, home, config_home, cache_home,
 data_home, state_home, config) = sys.argv[1:]
connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
connection.connect(os.path.join(parent_runtime, parent_display))
connection.set_inheritable(True)
environment = {
    "HOME": home,
    "XDG_CONFIG_HOME": config_home,
    "XDG_CACHE_HOME": cache_home,
    "XDG_DATA_HOME": data_home,
    "XDG_STATE_HOME": state_home,
    "XDG_RUNTIME_DIR": runtime,
    "WAYLAND_SOCKET": str(connection.fileno()),
    "WLR_BACKENDS": "wayland",
    "WLR_RENDERER": "pixman",
    "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + runtime + "/no-session-bus",
    "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + runtime + "/no-system-bus",
    "PATH": "/usr/bin:/bin",
    "LANG": "C.UTF-8",
}
os.setsid()
os.execve("/usr/bin/unshare", ["unshare", "--user", "--map-current-user",
    "--net", "--", "/usr/bin/Hyprland", "--config", config], environment)
PY
hypr_pid=$!

instance=""
for _ in {1..120}; do
  kill -0 "$hypr_pid" 2>/dev/null || fail 'nested Hyprland exited during startup'
  instances=$(XDG_RUNTIME_DIR="$lab_root/runtime" \
    timeout 2 hyprctl instances -j 2>/dev/null || true)
  instance=$(jq -c 'if length == 1 then .[0] else empty end' \
    <<<"$instances" 2>/dev/null || true)
  [[ -n $instance ]] && break
  sleep 0.1
done
[[ -n $instance ]] || fail 'nested Hyprland did not register'
nested_signature=$(jq -r '.instance' <<<"$instance")
nested_socket=$(jq -r '.wl_socket' <<<"$instance")
[[ -S $lab_root/runtime/$nested_socket ]] \
  || fail "nested Wayland socket is missing: $nested_socket"

nested_hyprctl() {
  local registered
  registered=$(XDG_RUNTIME_DIR="$lab_root/runtime" timeout 2 hyprctl instances -j \
    | jq -r --arg signature "$nested_signature" \
      '.[] | select(.instance == $signature) | .instance')
  [[ $registered == "$nested_signature" ]] || fail 'nested compositor identity changed'
  XDG_RUNTIME_DIR="$lab_root/runtime" \
    HYPRLAND_INSTANCE_SIGNATURE="$nested_signature" timeout 5 hyprctl "$@"
}

for _ in {1..80}; do
  monitors=$(nested_hyprctl monitors -j 2>/dev/null || true)
  output_name=$(jq -r '.[0].name // empty' <<<"$monitors" 2>/dev/null || true)
  [[ -n $output_name ]] && break
  sleep 0.05
done
[[ -n $output_name ]] || fail 'nested output did not appear'

write_nested_monitor_config() {
  local state=$1 monitor_line
  if [[ $state == disabled ]]; then
    monitor_line="monitor = $output_name,disable"
  else
    monitor_line="monitor = , 800x600@60, 0x0, 1"
  fi
  printf '%s\n%s\n%s\n%s\n' "$monitor_line" 'misc {' \
    '  disable_hyprland_logo = true' '  disable_splash_rendering = true' \
    >"$lab_root/hyprland.conf"
  printf '%s\n' '}' >>"$lab_root/hyprland.conf"
}

disable_nested_output() {
  write_nested_monitor_config disabled
  nested_hyprctl reload >/dev/null
  local current
  for _ in {1..120}; do
    current=$(nested_hyprctl monitors -j 2>/dev/null \
      | jq -r --arg output "$output_name" \
        '[.[] | select(.name == $output)] | length' \
        2>/dev/null || printf 1)
    [[ $current == 0 ]] && return 0
    sleep 0.05
  done
  return 1
}

restore_nested_output() {
  write_nested_monitor_config enabled
  nested_hyprctl reload >/dev/null
  local current
  for _ in {1..120}; do
    current=$(nested_hyprctl monitors -j 2>/dev/null \
      | jq -r --arg output "$output_name" \
        '[.[] | select(.name == $output and .disabled != true
          and .width > 0 and .height > 0)] | length' \
        2>/dev/null || printf 0)
    [[ $current == 1 ]] && return 0
    sleep 0.05
  done
  return 1
}

# The production shell gets only the admitted fixture trees, private XDG
# state, the nested Wayland socket and an empty network namespace. /dev is a
# private minimal devtmpfs and both D-Bus addresses are deliberately absent.
setsid /usr/bin/bwrap \
  --die-with-parent --unshare-net --clearenv \
  --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/lib /lib \
  --symlink usr/lib /lib64 --dir /etc --ro-bind /etc/fonts /etc/fonts \
  --proc /proc --dev /dev --tmpfs /tmp \
  --bind "$stage_root" "$stage_root" --bind "$lab_root" "$lab_root" \
  --setenv HOME "$stage_root/home" \
  --setenv XDG_CONFIG_HOME "$stage_root/home/.config" \
  --setenv XDG_CACHE_HOME "$stage_root/cache" \
  --setenv XDG_DATA_HOME "$stage_root/data" \
  --setenv XDG_DATA_DIRS "$stage_root/data" \
  --setenv XDG_STATE_HOME "$stage_root/state" \
  --setenv XDG_RUNTIME_DIR "$lab_root/runtime" \
  --setenv WAYLAND_DISPLAY "$nested_socket" \
  --setenv HYPRLAND_INSTANCE_SIGNATURE "$nested_signature" \
  --setenv OMARCHY_PATH "$stage_root/omarchy" \
  --setenv PATH "$stage_root/bin" \
  --setenv LANG C.UTF-8 \
  --setenv QT_QUICK_BACKEND software \
  --setenv QT_QPA_PLATFORM wayland \
  --setenv QT_QPA_PLATFORMTHEME '' \
  --setenv QT_FORCE_STDERR_LOGGING 1 \
  --setenv QML_DISABLE_DISK_CACHE 1 \
  --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$lab_root/runtime/no-session-bus" \
  --setenv DBUS_SYSTEM_BUS_ADDRESS "unix:path=$lab_root/runtime/no-system-bus" \
  --chdir "$stage_root/omarchy/shell" \
  "$quickshell_bin" -p "$stage_root/omarchy/shell" --no-color \
  >"$lab_root/quickshell.log" 2>&1 &
qs_pid=$!

check_log_bound() {
  local size hypr_size
  size=$(stat -c %s "$lab_root/quickshell.log" 2>/dev/null || printf 0)
  hypr_size=$(stat -c %s "$lab_root/hyprland.log" 2>/dev/null || printf 0)
  (( size <= 2 * 1024 * 1024 )) || fail 'Quickshell log exceeded 2 MiB'
  (( hypr_size <= 2 * 1024 * 1024 )) || fail 'Hyprland log exceeded 2 MiB'
  kill -0 "$qs_pid" 2>/dev/null || fail 'native Quickshell process group exited'
  kill -0 "$hypr_pid" 2>/dev/null || fail 'nested Hyprland process group exited'
}

debug_report() {
  env XDG_RUNTIME_DIR="$lab_root/runtime" WAYLAND_DISPLAY="$nested_socket" \
    "$quickshell_bin" ipc -p "$stage_root/omarchy/shell" call -- \
      shibumi-suite debugWidgetPipeline 2>/dev/null
}

native_rescan_count() {
  env XDG_RUNTIME_DIR="$lab_root/runtime" WAYLAND_DISPLAY="$nested_socket" \
    "$quickshell_bin" ipc -p "$stage_root/omarchy/shell" call -- \
      shell widgetPipelineRescanCount 2>/dev/null
}

classify_report() {
  local phase=$1 expected=$2 report=$3
  printf '%s' "$report" | python3 \
    "$repo_root/tests/widget-pipeline-classifier-regression.py" \
    --classify --phase "$phase" --mode "$expected" \
    --output "$output_name" --build "$build_label" --cycle "${cycle:-1}"
}

wait_for_public_output() {
  local attempts=${1:-160} report accepted
  for ((index=0; index<attempts; index++)); do
    check_log_bound
    report=$(debug_report || true)
    if [[ $report == \{* ]]; then
      accepted=$(REPORT="$report" OUTPUT_NAME="$output_name" python3 - <<'PY'
import json
import os
try:
    state = json.loads(os.environ["REPORT"])
except Exception:
    print("no")
    raise SystemExit
outputs = state.get("outputs", {})
sessions = outputs.get("sessions", [])
print("yes" if outputs.get("validOutputCount", 0) > 0
      and any(row.get("screen") == os.environ["OUTPUT_NAME"]
              and row.get("barPanel") is True
              and row.get("layoutSession") is True for row in sessions)
      else "no")
PY
)
      [[ $accepted == yes ]] && return 0
    fi
    sleep 0.05
  done
  return 1
}

wait_for_phase() {
  local phase=$1 expected=$2 attempts=${3:-160} report classification
  LAST_REPORT=""
  LAST_CLASSIFICATION="ipc-unavailable"
  for ((index=0; index<attempts; index++)); do
    check_log_bound
    report=$(debug_report || true)
    if [[ $report == \{* ]]; then
      report_count=$((report_count + 1))
      classification=$(classify_report "$phase" "$expected" "$report")
      LAST_REPORT=$report
      LAST_CLASSIFICATION=$classification
      [[ $classification == ok ]] && return 0
      if [[ $expected == negative && $classification == registry-selection ]]; then
        return 0
      fi
    fi
    sleep 0.05
  done
  return 1
}

record_census() {
  local phase=$1 report=$2
  printf 'WIDGET_PIPELINE_CENSUS %s\n' "$(jq -cn \
    --arg build "$build_label" --arg phase "$phase" --argjson state "$report" \
    '{build:$build,phase:$phase,state:$state}')"
}

marker_ready_count() {
  grep -F -c "PIPELINE_NATIVE_MARKER_READY id=hancore.shibumi.cpu screen=$output_name style=notch" \
    "$lab_root/quickshell.log" 2>/dev/null || true
}

marker_destruction_count() {
  grep -F -c "PIPELINE_NATIVE_MARKER_DESTROYED id=hancore.shibumi.cpu screen=$output_name" \
    "$lab_root/quickshell.log" 2>/dev/null || true
}

passive_warning_count() {
  grep -F -c '"event":"shibumi-widget-resolution-exhausted"' \
    "$lab_root/quickshell.log" 2>/dev/null || true
}

wait_for_marker_count() {
  local expected=$1
  for _ in {1..80}; do
    check_log_bound
    (( $(marker_ready_count) >= expected )) && return 0
    sleep 0.05
  done
  return 1
}

wait_for_destruction_count() {
  local expected=$1
  for _ in {1..80}; do
    check_log_bound
    (( $(marker_destruction_count) >= expected )) && return 0
    sleep 0.05
  done
  return 1
}

# Startup must prove the complete path and retain the one native registry prime
# before any real compositor-output lifecycle measurement.
if [[ $mode == negative ]]; then
  wait_for_phase initial negative 240 \
    || fail "negative control did not reach registry-selection (last=$LAST_CLASSIFICATION)"
  [[ $LAST_CLASSIFICATION == registry-selection ]] \
    || fail "negative control failed at $LAST_CLASSIFICATION instead of registry-selection"
  initial_native_rescans=$(native_rescan_count || true)
  [[ $initial_native_rescans == 1 ]] \
    || fail "negative control did not retain exactly one startup prime ($initial_native_rescans)"
  [[ $(passive_warning_count) == 0 ]] \
    || fail 'negative control emitted an unexpected passive warning'
  printf 'WIDGET_PIPELINE_RESULT %s\n' "$(jq -cn \
    --arg build "$build_label" --arg stage registry-selection \
    --argjson nativeRescans "$initial_native_rescans" \
    --argjson report "$LAST_REPORT" \
    '{build:$build,outcome:"expected-failure",stage:$stage,harnessProved:true,
      startupPrimeRetained:true,nativeRescanCountInitial:$nativeRescans,
      nativeRescanCountFinal:$nativeRescans,passiveWarnings:0,
      initialObservation:{validOutputs:$report.outputs.validOutputCount,
        barPanelCount:$report.outputs.barPanelCount,
        expected:$report.expected.entries[0],
        slot:$report.widgetSlots.entries[0]}}')"
else
  wait_for_phase initial positive 240 \
    || fail "initial full pipeline did not load (last=$LAST_CLASSIFICATION report=${LAST_REPORT:0:4096})"
  initial_report=$LAST_REPORT
  initial_native_rescans=$(native_rescan_count || true)
  [[ $initial_native_rescans == 1 ]] \
    || fail "startup prime census was not exactly one ($initial_native_rescans)"
  wait_for_marker_count 1 \
    || fail 'initial marker was not the real configured widget on the nested output'
  [[ $(marker_ready_count) == 1 ]] \
    || fail 'initial load created an ambiguous marker census'
  [[ $(marker_destruction_count) == 0 ]] \
    || fail 'initial marker was revoked before lifecycle measurement'

  record_census initial "$initial_report"
  initial_registry_revision=$(jq -r '.registry.revision' <<<"$initial_report")
  cycle_count=3
  [[ $mode == mutant ]] && cycle_count=1

  for ((cycle=1; cycle<=cycle_count; cycle++)); do
    creations_before=$(marker_ready_count)
    destructions_before=$(marker_destruction_count)
    disable_nested_output || fail "nested output did not disable in cycle $cycle"
    wait_for_phase absent positive 160 \
      || fail "output did not drain in cycle $cycle (last=$LAST_CLASSIFICATION report=${LAST_REPORT:0:4096})"
    absent_report=$LAST_REPORT
    record_census "cycle-$cycle-output-absent" "$absent_report"
    wait_for_destruction_count "$((destructions_before + 1))" \
      || fail "cycle $cycle did not revoke its loaded marker"
    destructions_after=$(marker_destruction_count)
    (( destructions_after == destructions_before + 1 )) \
      || fail "cycle $cycle produced an ambiguous marker revocation census"

    absent_selection=$(jq -r '.expected.entries[0].selection' <<<"$absent_report")
    absent_keys=$(jq -r '.registry.snapshotKeyCount' <<<"$absent_report")
    if [[ -z $first_absent_registry_gap \
          && ( $absent_selection != true || $absent_keys != 1 ) ]]; then
      absent_stage=registry-snapshot
      [[ $absent_selection == true ]] || absent_stage=registry-selection
      first_absent_registry_gap=$(jq -cn --arg stage "$absent_stage" \
        --argjson cycle "$cycle" \
        '{transition:"disable",cycle:$cycle,stage:$stage,validOutputs:0}')
    fi

    restore_nested_output || fail "nested output did not restore in cycle $cycle"
    wait_for_public_output 240 \
      || fail "cycle $cycle output returned in Hyprland but not in the Bar census"
    returned_census=$(debug_report || true)
    [[ $returned_census == \{* ]] \
      || fail "cycle $cycle returned-output census was unavailable"
    record_census "cycle-$cycle-output-returned" "$returned_census"

    loaded=true
    if ! wait_for_phase returned positive 160; then loaded=false; fi
    returned_report=$LAST_REPORT
    returned_classification=$LAST_CLASSIFICATION
    [[ $returned_report == \{* ]] \
      || fail "cycle $cycle returned-output classification had no census"
    if [[ $loaded == false && -z $first_loss ]]; then
      first_loss=$(jq -cn --arg stage "$returned_classification" \
        --argjson cycle "$cycle" \
        --argjson validOutputs "$(jq -r '.outputs.validOutputCount // -1' <<<"$returned_report")" \
        '{transition:"restore",cycle:$cycle,stage:$stage,
          validOutputs:$validOutputs}')
    fi

    control_applied=false
    if [[ $build_label == beta13 ]]; then
      [[ $loaded == false && $returned_classification == component-resolution ]] \
        || fail "Beta.13 did not reproduce component admission in cycle $cycle (last=$returned_classification)"
      control_applied=true
      env XDG_RUNTIME_DIR="$lab_root/runtime" WAYLAND_DISPLAY="$nested_socket" \
        "$quickshell_bin" ipc -p "$stage_root/omarchy/shell" call -- \
          shell rescanPlugins >/dev/null 2>&1 \
        || fail "Beta.13 recovery rescan failed in cycle $cycle"
      harness_rescans=$((harness_rescans + 1))
      wait_for_public_output 240 \
        || fail "Beta.13 output census disappeared after cycle $cycle control"
      wait_for_phase returned positive 240 \
        || fail "Beta.13 rescan did not repair cycle $cycle (last=$LAST_CLASSIFICATION report=${LAST_REPORT:0:4096})"
      wait_for_marker_count "$((creations_before + 1))" \
        || fail "Beta.13 control did not recreate the marker in cycle $cycle"
      (( $(marker_ready_count) == creations_before + 1 )) \
        || fail "Beta.13 control created an ambiguous marker census in cycle $cycle"
    elif [[ $mode == mutant ]]; then
      [[ $loaded == false && $returned_classification == component-resolution ]] \
        || fail "status-guard mutant did not fail at component-resolution ($returned_classification)"
      [[ $(marker_ready_count) == "$creations_before" ]] \
        || fail 'status-guard mutant unexpectedly recreated the marker'
    else
      [[ $loaded == true ]] \
        || fail "candidate did not return automatically in cycle $cycle (last=$returned_classification)"
      wait_for_marker_count "$((creations_before + 1))" \
        || fail "candidate cycle $cycle did not load its marker on $output_name"
      (( $(marker_ready_count) == creations_before + 1 )) \
        || fail "candidate cycle $cycle created an ambiguous marker census"
    fi

    settled_report=$LAST_REPORT
    cycle_results=$(jq -cn --argjson rows "$cycle_results" \
      --argjson cycle "$cycle" --arg classification "$returned_classification" \
      --argjson absent "$absent_report" --argjson returned "$returned_report" \
      --argjson settled "$settled_report" --argjson control "$control_applied" \
      --argjson markerReady "$(marker_ready_count)" \
      '$rows + [{cycle:$cycle,transition:[1,0,1],
        identity:{id:$returned.expected.entries[0].id,
          configured:$returned.expected.entries[0].configured,
          selected:$returned.expected.entries[0].selection},
        absent:{componentPresent:$absent.expected.entries[0].componentPresent,
          componentStatusKind:$absent.expected.entries[0].componentStatusKind,
          componentStatus:$absent.expected.entries[0].componentStatus,
          lifecycle:$absent.outputLifecycle,
          registryKeys:$absent.registry.snapshotKeyCount,
          registryRevision:$absent.registry.revision},
        returned:{classification:$classification,
          componentPresent:$returned.expected.entries[0].componentPresent,
          componentStatusKind:$returned.expected.entries[0].componentStatusKind,
          componentStatus:$returned.expected.entries[0].componentStatus,
          resolvedComponentPresent:$returned.widgetSlots.entries[0].resolvedComponentPresent,
          resolvedComponentStatusKind:$returned.widgetSlots.entries[0].resolvedComponentStatusKind,
          resolvedStatus:$returned.widgetSlots.entries[0].resolvedStatus,
          currentLoadReady:$returned.widgetSlots.entries[0].currentLoadReady,
          loaderActive:$returned.widgetSlots.entries[0].loaderActive,
          loaderStatus:$returned.widgetSlots.entries[0].loaderStatus,
          loaderItem:$returned.widgetSlots.entries[0].loaderItem,
          lifecycle:$returned.outputLifecycle,
          registryKeys:$returned.registry.snapshotKeyCount,
          registryRevision:$returned.registry.revision},
        settledLoader:{resolvedComponentPresent:$settled.widgetSlots.entries[0].resolvedComponentPresent,
          resolvedComponentStatusKind:$settled.widgetSlots.entries[0].resolvedComponentStatusKind,
          resolvedStatus:$settled.widgetSlots.entries[0].resolvedStatus,
          currentLoadReady:$settled.widgetSlots.entries[0].currentLoadReady,
          active:$settled.widgetSlots.entries[0].loaderActive,
          status:$settled.widgetSlots.entries[0].loaderStatus,
          item:$settled.widgetSlots.entries[0].loaderItem,
          lifecycle:$settled.outputLifecycle},
        harnessControlRescan:$control,markerReadyCount:$markerReady}]')
  done

  final_report=$LAST_REPORT
  final_native_rescans=$(native_rescan_count || true)
  [[ $final_native_rescans =~ ^[0-9]+$ ]] \
    || fail "final native rescan census was malformed ($final_native_rescans)"
  expected_native_rescans=$((initial_native_rescans + harness_rescans))
  (( final_native_rescans == expected_native_rescans )) \
    || fail "unexpected native rescan: expected $expected_native_rescans got $final_native_rescans"

  registry_identity_stable=$(jq -nr --argjson rows "$cycle_results" \
    --argjson revision "$initial_registry_revision" \
    '$rows | all(.identity == {id:"hancore.shibumi.cpu",configured:true,selected:true}
      and .absent.registryKeys == 1 and .returned.registryKeys == 1
      and .absent.registryRevision == $revision
      and .returned.registryRevision == $revision)')
  if [[ $build_label == candidate || $mode == mutant ]]; then
    [[ $registry_identity_stable == true ]] \
      || fail 'candidate registry identity/revision changed during output cycles'
  fi

  passive_warnings=$(passive_warning_count)
  if [[ $mode == mutant ]]; then
    [[ $passive_warnings == 1 ]] \
      || fail "status-guard mutant passive warning count was not one ($passive_warnings)"
    [[ $(jq -r '.outputLifecycle.warningEmitted' <<<"$final_report") == true ]] \
      || fail 'status-guard mutant did not expose its bounded passive warning'
  else
    [[ $passive_warnings == 0 ]] \
      || fail "normal arm emitted a passive warning ($passive_warnings)"
    [[ $(jq -r '.outputLifecycle.warningEmitted' <<<"$final_report") == false ]] \
      || fail 'normal arm reported a passive warning'
  fi

  record_census final "$final_report"
  grep -Eiq 'Binding loop|TypeError|ReferenceError|Cannot read propert(y|ies).*null|QQmlVMEMetaObject: Internal error' \
    "$lab_root/quickshell.log" \
    && fail 'native fixture emitted a composition/runtime error'
  marker_creations=$(marker_ready_count)
  marker_destructions=$(marker_destruction_count)
  (( marker_creations >= 1 )) || fail 'no real V2 notch marker creation was observed'
  loss_json=${first_loss:-null}
  absent_loss_json=${first_absent_registry_gap:-null}
  outcome=measured
  [[ $mode == mutant ]] && outcome="expected-failure"
  printf 'WIDGET_PIPELINE_RESULT %s\n' "$(jq -cn \
    --arg build "$build_label" --arg outcome "$outcome" --arg output "$output_name" \
    --argjson reports "$report_count" --argjson creations "$marker_creations" \
    --argjson destructions "$marker_destructions" --argjson loss "$loss_json" \
    --argjson absentLoss "$absent_loss_json" --argjson warnings "$passive_warnings" \
    --argjson harnessRescans "$harness_rescans" --argjson cycles "$cycle_count" \
    --argjson cycleResults "$cycle_results" --argjson initialRescans "$initial_native_rescans" \
    --argjson finalRescans "$final_native_rescans" \
    --argjson identityStable "$registry_identity_stable" \
    '{build:$build,outcome:$outcome,harnessProved:true,cycles:$cycles,
      actualTransitions:$cycleResults,output:$output,reports:$reports,
      startupPrimeRetained:($initialRescans == 1),
      nativeRescanCountInitial:$initialRescans,nativeRescanCountFinal:$finalRescans,
      harnessRescans:$harnessRescans,passiveWarnings:$warnings,
      registryIdentityStable:$identityStable,
      markerCreations:$creations,markerDestructions:$destructions,
      firstAbsentRegistryGap:$absentLoss,firstPersistentLoss:$loss}')"
fi

stop_group "$qs_pid" || fail 'Quickshell process group survived bounded shutdown'
qs_pid=""
stop_group "$hypr_pid" || fail 'nested Hyprland process group survived bounded shutdown'
hypr_pid=""
find "$lab_root/runtime" -type s -delete
if find "$lab_root/runtime" -type s -print -quit | grep -q .; then
  fail 'private nested runtime retained sockets after cleanup'
fi

printf 'Full native widget pipeline Wayland run completed (%s, mode=%s)\n' \
  "$build_label" "$mode"
