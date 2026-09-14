#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-reactor-plugin.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'reactor plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.reactor" "$tmpdir/reactor"
mkdir -p "$tmpdir/audio"
cp -- "$repo_root/hancore.shibumi.audio/Service.qml" "$tmpdir/audio/"
cp "$repo_root/tests/fixtures/AudioPeakTestMonitor.qml" "$tmpdir/audio/AudioPeakMonitor.qml"
mkdir -p "$tmpdir/hancore.shibumi.state"
cp -a "$repo_root/hancore.shibumi.state/runtime" "$tmpdir/hancore.shibumi.state/"
printf '{"suiteId":"hancore.shibumi","suitePayloadDigest":"%064d"}\n' 0 \
  > "$tmpdir/hancore.shibumi.state/.shibumi-managed.json"
install -m 0644 "$repo_root/tests/reactor-plugin-smoke.qml" "$tmpdir/shell.qml"

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
grep -F 'reactor plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error|Cannot assign' <<<"$output"; then
  fail "QML runtime error"
fi

mkdir -p "$tmpdir/styles"
cp "$repo_root/hancore.shibumi.bar/styles/shibumi/ReactorEventLayer.qml" \
  "$tmpdir/styles/"
cp "$repo_root/tests/reactor-runtime-smoke.qml" "$tmpdir/scoped.qml"
set +e
scoped_output=$(timeout 8 env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$tmpdir/runtime" \
  "$quickshell_bin" -p "$tmpdir/scoped.qml" 2>&1)
scoped_rc=$?
set -e
printf '%s\n' "$scoped_output"
[[ $scoped_rc -eq 0 ]] || fail "scoped smoke exited $scoped_rc"
grep -Fq 'reactor runtime smoke passed' <<<"$scoped_output" || fail "scoped marker missing"
if grep -Eq 'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error|Cannot assign' <<<"$scoped_output"; then
  fail "scoped QML runtime error"
fi

python3 "$repo_root/tests/reactor-text-source-regression.py"

plugin="$repo_root/hancore.shibumi.reactor"
facade="$plugin/Service.qml"
events="$plugin/ReactorService.qml"
quotes="$plugin/QuoteService.qml"
audio="$repo_root/hancore.shibumi.audio"

rg -q 'serviceFor\("hancore\.shibumi\.state"\)' "$facade" \
  || fail "facade does not resolve the state owner"
rg -q 'root\.loadedBackendMode === 7 \? eventBackendComponent : quoteBackendComponent' "$facade" \
  || fail "facade does not exclusively select the active backend"
rg -Fq 'desiredBackendMode: ready && (mode === 7 || mode === 8) ? mode : 0' "$facade" \
  || fail "mode zero can instantiate a backend"
rg -Fq 'const next = desiredBackendMode' "$facade" \
  || fail "deferred backend sync does not read current admission"
rg -Fq 'backendLoader.active = next !== 0' "$facade" \
  || fail "backend activation does not follow current mode"
if rg -q 'Process \{|Timer \{|FileView \{' "$facade"; then
  fail "mode facade owns runtime workers"
fi
if rg -q '\bbar\.|moduleSlots|moduleItem\(' "$events"; then
  fail "event backend retains a concrete bar or slot reference"
fi
for dependency in workspaces status power-state ai network audio; do
  rg -q "suiteService\(\"hancore\\.shibumi\\.${dependency}\"\)" "$events" \
    || fail "event backend bypasses $dependency service"
done
rg -q 'firstPartyService\("omarchy\.media"\)' "$events" \
  || fail "event backend bypasses official media service"
rg -q 'suiteService\("hancore\.shibumi\.update-center"\)' "$events" \
  || fail "event backend bypasses Shibumi update owner"
rg -q 'running: root\.runtimeProbesEnabled && root\.active' "$events" \
  || fail "pacman watcher is not mode/lifecycle bounded"
[[ $(rg -c 'active: root\.runtimeProbesEnabled && root\.active' "$events") -eq 2 ]] \
  || fail "bounded event readers cannot be disabled"
rg -q 'active: root\.runtimeProbesEnabled && root\.active' "$quotes" \
  || fail "bounded quote reader cannot be disabled"
rg -q 'preload: false' "$plugin/BoundedTextSource.qml" \
  || fail "file watcher can buffer unbounded content"

if rg -q 'Process \{|Timer \{|FileView \{' "$audio/Service.qml"; then
  fail "audio snapshot service owns a backend worker"
fi
rg -q 'leasedReportService\.report\(root, audioReady, muted\)' "$audio/BarWidget.qml" \
  || fail "audio widget does not publish its existing snapshot"
rg -q 'leasedReportService\.release\(root\)' "$audio/BarWidget.qml" \
  || fail "audio widget does not release its snapshot"

printf 'reactor plugin regression passed\n'
