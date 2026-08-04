#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'core services regression failed: %s\n' "$*" >&2
  exit 1
}

command -v quickshell >/dev/null 2>&1 || fail "quickshell is required"

smoke_root=$(mktemp -d /tmp/shibumi-core-services.XXXXXX)
trap 'rm -rf -- "$smoke_root"' EXIT
mkdir -p "$smoke_root/runtime" "$smoke_root/home"
chmod 700 "$smoke_root/runtime"
cp -a "$repo_root/hancore.shibumi.telemetry" "$smoke_root/telemetry"
mkdir -p "$smoke_root/cpu"
cp "$repo_root/hancore.shibumi.cpu/Service.qml" \
  "$repo_root/hancore.shibumi.cpu/GpuTelemetry.qml" "$smoke_root/cpu/"
cp -a "$repo_root/hancore.shibumi.cpu/scripts" "$smoke_root/cpu/scripts"
cp -a "$repo_root/hancore.shibumi.power-state" "$smoke_root/powerstate"
cp "$repo_root/tests/core-services-smoke.qml" "$smoke_root/shell.qml"

set +e
output=$(timeout 8 env \
  HOME="$smoke_root/home" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$smoke_root/runtime" \
  quickshell -p "$smoke_root" 2>&1)
rc=$?
set -e

printf '%s\n' "$output"
[[ $rc -eq 0 ]] || fail "smoke exited $rc"
grep -q 'Configuration Loaded' <<<"$output" \
  || fail "configuration did not load"
grep -q 'core services smoke passed' <<<"$output" \
  || fail "runtime assertions did not complete"

printf 'core services regression passed\n'
