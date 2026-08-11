#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${SHIBUMI_WAYLAND_DEADLINE_ACTIVE:-0} != 1 ]]; then
  command -v timeout >/dev/null 2>&1 || {
    printf 'GroupSection Wayland lifecycle regression failed: timeout is required\n' >&2
    exit 1
  }
  exec env SHIBUMI_WAYLAND_DEADLINE_ACTIVE=1 \
    timeout --foreground --signal=TERM --kill-after=10 \
      "${SHIBUMI_WAYLAND_DEADLINE:-300}" "$0" "$@"
fi
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
cycles=${SHIBUMI_WAYLAND_CYCLES:-6}
lab_root=""
hypr_pid=""
qs_pid=""
nested_signature=""
parent_runtime=${XDG_RUNTIME_DIR:-}
parent_display=${WAYLAND_DISPLAY:-}

fail() {
  printf 'GroupSection Wayland lifecycle regression failed: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n $qs_pid ]]; then
    kill -TERM -- "-$qs_pid" 2>/dev/null || true
    for _ in {1..30}; do
      pgrep -g "$qs_pid" >/dev/null 2>&1 || break
      sleep 0.1
    done
    if pgrep -g "$qs_pid" >/dev/null 2>&1; then
      kill -KILL -- "-$qs_pid" 2>/dev/null || true
      for _ in {1..30}; do
        pgrep -g "$qs_pid" >/dev/null 2>&1 || break
        sleep 0.1
      done
    fi
    if ! kill -0 "$qs_pid" 2>/dev/null; then
      wait "$qs_pid" 2>/dev/null || true
    fi
  fi
  if [[ -n $hypr_pid ]]; then
    kill -TERM -- "-$hypr_pid" 2>/dev/null || true
    for _ in {1..30}; do
      pgrep -g "$hypr_pid" >/dev/null 2>&1 || break
      sleep 0.1
    done
    if pgrep -g "$hypr_pid" >/dev/null 2>&1; then
      kill -KILL -- "-$hypr_pid" 2>/dev/null || true
      for _ in {1..30}; do
        pgrep -g "$hypr_pid" >/dev/null 2>&1 || break
        sleep 0.1
      done
    fi
    if ! kill -0 "$hypr_pid" 2>/dev/null; then
      wait "$hypr_pid" 2>/dev/null || true
    fi
  fi
  [[ -z $lab_root ]] || rm -rf -- "$lab_root"
}
trap cleanup EXIT

[[ -x $quickshell_bin ]] || fail "Quickshell executable is missing: $quickshell_bin"
[[ -d $omarchy_path/shell/Commons ]] \
  || fail "Omarchy Commons tree is missing: $omarchy_path/shell/Commons"
[[ -n $parent_display ]] || fail "a parent Wayland session is required"
[[ -n $parent_runtime ]] || fail "XDG_RUNTIME_DIR is required"
[[ -S $parent_runtime/$parent_display ]] \
  || fail "parent Wayland socket is missing: $parent_runtime/$parent_display"
for command in Hyprland hyprctl jq pgrep python3 setsid timeout; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done
[[ $cycles =~ ^[1-9][0-9]*$ ]] || fail "SHIBUMI_WAYLAND_CYCLES must be positive"

lab_root=$(mktemp -d "${TMPDIR:-/tmp}/shibumi-wayland-lifecycle.XXXXXX")
mkdir -p "$lab_root"/{home,config,cache,data,state,runtime,fixture}
chmod 700 "$lab_root/runtime"
cat >"$lab_root/hyprland.conf" <<'EOF'
monitor = , 800x600@60, 0x0, 1
misc {
  disable_hyprland_logo = true
  disable_splash_rendering = true
}
EOF

# Give the nested backend a connected fd for the parent compositor. Hyprland
# then creates its own wl_socket, keeping all output mutation inside the nested
# compositor instead of touching the physical session.
python3 - "$parent_runtime" "$parent_display" "$lab_root/runtime" \
    "$lab_root/home" "$lab_root/config" "$lab_root/cache" \
    "$lab_root/data" "$lab_root/state" "$lab_root/hyprland.conf" <<'PY' \
    >"$lab_root/hyprland.log" 2>&1 &
import os
import socket
import sys

(
    parent_runtime,
    parent_display,
    runtime,
    home,
    config_home,
    cache_home,
    data_home,
    state_home,
    config,
) = sys.argv[1:]
connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
connection.connect(os.path.join(parent_runtime, parent_display))
connection.set_inheritable(True)
environment = os.environ.copy()
environment.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
environment.pop("WAYLAND_DISPLAY", None)
environment["HOME"] = home
environment["XDG_CONFIG_HOME"] = config_home
environment["XDG_CACHE_HOME"] = cache_home
environment["XDG_DATA_HOME"] = data_home
environment["XDG_STATE_HOME"] = state_home
environment["XDG_RUNTIME_DIR"] = runtime
environment["WAYLAND_SOCKET"] = str(connection.fileno())
environment["WLR_BACKENDS"] = "wayland"
os.setsid()
os.execvpe("Hyprland", ["Hyprland", "--config", config], environment)
PY
hypr_pid=$!

instance=""
for _ in {1..120}; do
  kill -0 "$hypr_pid" 2>/dev/null || {
    cat "$lab_root/hyprland.log" >&2
    fail "nested Hyprland exited during startup"
  }
  instances=$(XDG_RUNTIME_DIR="$lab_root/runtime" \
    timeout 2 hyprctl instances -j 2>/dev/null || true)
  instance=$(jq -c --argjson pid "$hypr_pid" \
    '.[] | select(.pid == $pid)' <<<"$instances" 2>/dev/null \
    | head -1 || true)
  [[ -n $instance ]] && break
  sleep 0.1
done
[[ -n $instance ]] || fail "nested Hyprland did not register"
nested_signature=$(jq -r '.instance' <<<"$instance")
nested_socket=$(jq -r '.wl_socket' <<<"$instance")
[[ -S $lab_root/runtime/$nested_socket ]] \
  || fail "nested Wayland socket is missing: $nested_socket"

cp -a "$repo_root/core" "$repo_root/styles" "$lab_root/fixture/"
cp -a "$omarchy_path/shell/Commons" "$lab_root/fixture/"
cp "$repo_root/tests/incidents/inc012/SectionHost.qml" "$lab_root/fixture/"
cp "$repo_root/tests/group-section-wayland-shell.qml" \
  "$lab_root/fixture/shell.qml"

nested_hyprctl() {
  XDG_RUNTIME_DIR="$lab_root/runtime" \
    HYPRLAND_INSTANCE_SIGNATURE="$nested_signature" timeout 5 hyprctl "$@"
}

wait_for_count() {
  local pattern=$1 expected=$2 log_file=$3 count
  for _ in {1..120}; do
    count=$(grep -Ec "$pattern" "$log_file" 2>/dev/null || true)
    (( count >= expected )) && return 0
    [[ -n $qs_pid ]] && kill -0 "$qs_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

wait_for_real_output() {
  for _ in {1..120}; do
    if nested_hyprctl monitors -j 2>/dev/null \
        | jq -e 'any(.[]; .name == "WAYLAND-1" and .disabled != true
          and .width > 0 and .height > 0)' >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

run_mode() {
  local v2=$1 editing=$2 vertical=$3 label log_file created ready destroyed
  local placeholder_before created_before ready_before destroyed_before
  local current_created current_ready quickshell_rc
  label="v2-$v2-editing-$editing-vertical-$vertical"
  log_file="$lab_root/$label.log"

  : >"$log_file"
  setsid env \
    WAYLAND_DISPLAY="$nested_socket" \
    HYPRLAND_INSTANCE_SIGNATURE="$nested_signature" \
    XDG_RUNTIME_DIR="$lab_root/runtime" \
    HOME="$lab_root/home" \
    XDG_CONFIG_HOME="$lab_root/config" \
    XDG_CACHE_HOME="$lab_root/cache" \
    XDG_DATA_HOME="$lab_root/data" \
    XDG_STATE_HOME="$lab_root/state" \
    SHIBUMI_TEST_V2="$v2" \
    SHIBUMI_TEST_EDITING="$editing" \
    SHIBUMI_TEST_VERTICAL="$vertical" \
    "$quickshell_bin" -p "$lab_root/fixture" --no-color \
    >"$log_file" 2>&1 &
  qs_pid=$!

  if ! wait_for_count 'P0_WAYLAND_SURFACE_READY' 1 "$log_file"; then
    cat "$log_file" >&2
    fail "$label did not reach its initial registered steady state"
  fi

  for (( cycle = 1; cycle <= cycles; cycle++ )); do
    placeholder_before=$(grep -c \
      'There are no outputs - creating placeholder screen' "$log_file" || true)
    created_before=$(grep -c 'P0_WAYLAND_SURFACE_CREATED' "$log_file" || true)
    ready_before=$(grep -c 'P0_WAYLAND_SURFACE_READY' "$log_file" || true)
    destroyed_before=$(grep -c 'P0_WAYLAND_SURFACE_DESTROYED' "$log_file" || true)
    nested_hyprctl keyword monitor 'WAYLAND-1,disable' >/dev/null
    wait_for_count 'There are no outputs - creating placeholder screen' \
      "$(( placeholder_before + 1 ))" "$log_file" || {
        cat "$log_file" >&2
        fail "$label cycle $cycle did not reach the placeholder screen"
      }
    wait_for_count 'P0_WAYLAND_SURFACE_DESTROYED' \
      "$(( destroyed_before + 1 ))" "$log_file" || {
        cat "$log_file" >&2
        fail "$label cycle $cycle did not destroy the real-output surface"
      }
    current_created=$(grep -c 'P0_WAYLAND_SURFACE_CREATED' "$log_file" || true)
    current_ready=$(grep -c 'P0_WAYLAND_SURFACE_READY' "$log_file" || true)
    if (( current_created != created_before || current_ready != ready_before )); then
      cat "$log_file" >&2
      fail "$label cycle $cycle instantiated a placeholder surface"
    fi
    nested_hyprctl reload >/dev/null
    wait_for_real_output \
      || fail "$label cycle $cycle did not restore the real output"
    wait_for_count 'P0_WAYLAND_SURFACE_READY' "$(( ready_before + 1 ))" \
      "$log_file" || {
        cat "$log_file" >&2
        fail "$label cycle $cycle did not restore its registered steady state"
      }
  done

  created=$(grep -c 'P0_WAYLAND_SURFACE_CREATED' "$log_file" || true)
  ready=$(grep -c 'P0_WAYLAND_SURFACE_READY' "$log_file" || true)
  destroyed=$(grep -c 'P0_WAYLAND_SURFACE_DESTROYED' "$log_file" || true)
  if (( created != cycles + 1 || ready != cycles + 1
      || destroyed != cycles )); then
    cat "$log_file" >&2
    fail "$label lifecycle is unbalanced before shutdown: created=$created ready=$ready destroyed=$destroyed"
  fi

  if ! env XDG_RUNTIME_DIR="$lab_root/runtime" \
      WAYLAND_DISPLAY="$nested_socket" \
      timeout 10 "$quickshell_bin" kill -p "$lab_root/fixture" --any-display \
      >/dev/null 2>&1; then
    cat "$log_file" >&2
    fail "$label Quickshell IPC shutdown request failed"
  fi
  for _ in {1..120}; do
    kill -0 "$qs_pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$qs_pid" 2>/dev/null; then
    cat "$log_file" >&2
    fail "$label did not stop through Quickshell IPC"
  fi
  set +e
  wait "$qs_pid" 2>/dev/null
  quickshell_rc=$?
  set -e
  if (( quickshell_rc != 0 )); then
    cat "$log_file" >&2
    fail "$label Quickshell exited $quickshell_rc"
  fi
  if pgrep -g "$qs_pid" >/dev/null 2>&1; then
    pgrep -a -g "$qs_pid" >&2 || true
    fail "$label Quickshell process group survived shutdown"
  fi
  qs_pid=""

  created=$(grep -c 'P0_WAYLAND_SURFACE_CREATED' "$log_file" || true)
  ready=$(grep -c 'P0_WAYLAND_SURFACE_READY' "$log_file" || true)
  destroyed=$(grep -c 'P0_WAYLAND_SURFACE_DESTROYED' "$log_file" || true)
  if (( created != cycles + 1 || ready != cycles + 1
      || destroyed != cycles + 1 )); then
    cat "$log_file" >&2
    fail "$label shutdown lifecycle is unbalanced: created=$created ready=$ready destroyed=$destroyed"
  fi
  if grep -Eiq \
      'TypeError|ReferenceError|Cannot read propert(y|ies).*null|QQmlVMEMetaObject: Internal error|INC012_HARNESS_ERROR|P0_WAYLAND_HARNESS_ERROR' \
      "$log_file"; then
    cat "$log_file" >&2
    fail "$label emitted a Wayland teardown error"
  fi
}

for vertical in 0 1; do
  run_mode 0 0 "$vertical"
  run_mode 0 1 "$vertical"
  run_mode 1 0 "$vertical"
  run_mode 1 1 "$vertical"
done

kill -TERM -- "-$hypr_pid" 2>/dev/null || true
set +e
wait "$hypr_pid"
hyprland_rc=$?
set -e
if (( hyprland_rc != 0 )); then
  cat "$lab_root/hyprland.log" >&2
  fail "nested Hyprland exited $hyprland_rc"
fi
for _ in {1..50}; do
  pgrep -g "$hypr_pid" >/dev/null 2>&1 || break
  sleep 0.1
done
if pgrep -g "$hypr_pid" >/dev/null 2>&1; then
  pgrep -a -g "$hypr_pid" >&2 || true
  fail "nested Hyprland process group survived shutdown"
fi
hypr_pid=""
# Quickshell and Hyprland leave registry socket pathnames after a clean exit.
# They are confined to the private runtime; remove them and prove that the
# harness cannot leave a socket in the parent session.
find "$lab_root/runtime" -type s -delete
if find "$lab_root/runtime" -type s -print -quit | grep -q .; then
  find "$lab_root/runtime" -type s -print >&2
  fail "private nested runtime retained sockets after cleanup"
fi

printf 'GroupSection Wayland lifecycle regression passed: %s cycles (%s)\n' \
  "$(( cycles * 8 ))" \
  "$(timeout 5 "$quickshell_bin" --version 2>&1 | head -1)"
