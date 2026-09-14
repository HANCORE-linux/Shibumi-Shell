#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/shibumi-host-registry-prime.XXXXXX")
cleanup() { rm -rf -- "$tmpdir"; }
trap cleanup EXIT

fail() {
  printf 'host registry prime regression failed: %s\n' "$*" >&2
  exit 1
}

runtime_source="$repo_root/hancore.shibumi.state/runtime/Runtime.qml"
bar_source="$repo_root/hancore.shibumi.bar/Bar.qml"
[[ $(grep -Ec '^  property Process ' "$runtime_source") -eq 1 ]] \
  || fail 'registry prime added or lost a production process'
[[ $(grep -Ec '^  property Timer ' "$runtime_source") -eq 1 ]] \
  || fail 'registry prime added or lost a production timer'
[[ $(grep -Ec '^  property WorkerScript |^  property .*Poll' "$runtime_source") -eq 0 ]] \
  || fail 'registry prime added a production worker or poller'
[[ $(grep -Fc '"shell", "rescanPlugins"' "$runtime_source") -eq 1 ]] \
  || fail 'runtime must contain exactly the startup-prime rescan dispatch'
if grep -Eq 'requestHostRegistryRecovery|hostRegistryRecovery|"lock", "isLocked"|StdioCollector' \
    "$runtime_source" "$bar_source"; then
  fail 'retired post-output recovery or lock-probe machinery remains'
fi

cp -a "$repo_root/hancore.shibumi.state" "$tmpdir/"
cp "$repo_root/tests/host-registry-prime-smoke.qml" "$tmpdir/shell.qml"
printf '%s\n' \
  '{"suiteId":"hancore.shibumi","suitePayloadDigest":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}' \
  > "$tmpdir/hancore.shibumi.state/.shibumi-managed.json"

mode_index=0
for mode in success refusal timeout owner-change process-change scope-loss diagnostic; do
  mode_index=$((mode_index + 1))
  # Keep Quickshell's derived Unix-domain IPC socket below sockaddr_un limits.
  runtime="$tmpdir/r$mode_index"
  mkdir -m 700 "$runtime"
  set +e
  output=$(timeout 8 env \
    HOME="$tmpdir/home" \
    SHIBUMI_PRIME_MODE="$mode" \
    WAYLAND_DISPLAY= \
    QT_QPA_PLATFORM=offscreen \
    QT_QPA_PLATFORMTHEME= \
    XDG_RUNTIME_DIR="$runtime" \
    /usr/bin/quickshell -p "$tmpdir" --no-color 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$output"
  [[ $rc -eq 0 ]] || fail "$mode smoke exited $rc"
  grep -q "host registry prime $mode passed" <<<"$output" \
    || fail "$mode smoke did not reach its marker"

  mapfile -t event_lines < <(grep -E 'qml: \{"processId":[0-9]+,"phase":' <<<"$output")
  phases=()
  event_pid=
  previous_elapsed=-1
  event_re='^\{"processId":([0-9]+),"phase":"([a-z-]+)","attemptNumber":([0-9]+),"elapsedMilliseconds":([0-9]+)\}$'
  for line in "${event_lines[@]}"; do
    payload="{${line#*\{}"
    [[ $payload =~ $event_re ]] \
      || fail "$mode emitted a registry-prime line with extra or malformed data"
    [[ ${BASH_REMATCH[3]} -eq 1 ]] \
      || fail "$mode emitted an invalid attempt number"
    [[ ${BASH_REMATCH[4]} -ge $previous_elapsed ]] \
      || fail "$mode elapsed milliseconds moved backwards"
    previous_elapsed=${BASH_REMATCH[4]}
    [[ ${BASH_REMATCH[1]} -gt 1 ]] \
      || fail "$mode emitted an invalid process ID"
    if [[ -z $event_pid ]]; then
      event_pid=${BASH_REMATCH[1]}
    elif [[ ${BASH_REMATCH[1]} != "$event_pid" ]]; then
      fail "$mode emitted events for more than one process"
    fi
    phases+=("${BASH_REMATCH[2]}")
  done

  phase_sequence="${phases[*]-}"
  case "$mode" in
    success|owner-change|process-change|diagnostic)
      [[ $phase_sequence == "request-accepted native-rescan-acknowledged replacement-bar-observed ready"
          || $phase_sequence == "request-accepted replacement-bar-observed native-rescan-acknowledged ready" ]] \
        || fail "$mode emitted the wrong bounded event sequence: $phase_sequence"
      ;;
    refusal)
      [[ $phase_sequence == "request-accepted native-rescan-refused failed" ]] \
        || fail "$mode emitted the wrong bounded event sequence: $phase_sequence"
      ;;
    timeout)
      [[ $phase_sequence == "request-accepted native-rescan-acknowledged timed-out" ]] \
        || fail "$mode emitted the wrong bounded event sequence: $phase_sequence"
      ;;
    scope-loss)
      [[ $phase_sequence == "request-accepted native-rescan-acknowledged failed" ]] \
        || fail "$mode emitted the wrong bounded event sequence: $phase_sequence"
      ;;
  esac

  warning_count=$(grep -c '"event":"shibumi-widget-resolution-exhausted"' \
    <<<"$output" || true)
  if [[ $mode == diagnostic ]]; then
    [[ $warning_count -eq 1 ]] \
      || fail "$mode emitted $warning_count resolution warnings instead of one"
    warning_payload=$(grep '"event":"shibumi-widget-resolution-exhausted"' \
      <<<"$output" | sed 's/^.*qml: //')
    python3 - "$event_pid" "$warning_payload" <<'PY'
import json
import sys

event_pid, raw = sys.argv[1:]
value = json.loads(raw)
assert value == {
    "event": "shibumi-widget-resolution-exhausted",
    "processId": int(event_pid),
    "pluginId": "fixture.widget",
    "screenLabel": "unknown",
    "retryCount": 10,
    "facadeScoped": True,
    "facadeRegistryPresent": True,
    "facadeConfigured": True,
    "facadeEnabled": True,
    "previouslyResolved": True,
    "outputSequence": "positive-zero-positive",
    "primePhase": "ready",
}
assert "registry-prime-private-path-user-data" not in raw
PY
  else
    [[ $warning_count -eq 0 ]] \
      || fail "$mode emitted an ineligible resolution warning"
  fi
  if grep -q 'registry-prime-private-path-user-data' <<<"$output"; then
    fail "$mode leaked private diagnostic data"
  fi
  if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load' \
      <<<"$output"; then
    fail "$mode runtime log contains a composition error"
  fi
done

printf 'host registry prime regression passed\n'
