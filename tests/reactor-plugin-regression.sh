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

plugin="$repo_root/hancore.shibumi.reactor"
facade="$plugin/Service.qml"
events="$plugin/ReactorService.qml"
quotes="$plugin/QuoteService.qml"
audio="$repo_root/hancore.shibumi.audio"

rg -q 'serviceFor\("hancore\.shibumi\.state"\)' "$facade" \
  || fail "facade does not resolve the state owner"
rg -q 'root\.mode === 7 \? eventBackendComponent : quoteBackendComponent' "$facade" \
  || fail "facade does not exclusively select the active backend"
rg -q 'active: root\.ready && \(root\.mode === 7 \|\| root\.mode === 8\)' "$facade" \
  || fail "mode zero can instantiate a backend"
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
rg -q 'path: root\.runtimeProbesEnabled' "$events" \
  || fail "event file watchers cannot be disabled"
rg -q 'path: root\.runtimeProbesEnabled \? root\.quotesPath : ""' "$quotes" \
  || fail "quote file watcher cannot be disabled"

if rg -q 'Process \{|Timer \{|FileView \{' "$audio/Service.qml"; then
  fail "audio snapshot service owns a backend worker"
fi
rg -q 'audioStateService\.report\(root, audioReady, muted\)' "$audio/BarWidget.qml" \
  || fail "audio widget does not publish its existing snapshot"
rg -q 'audioStateService\.release\(root\)' "$audio/BarWidget.qml" \
  || fail "audio widget does not release its snapshot"

cmp -s -- "$repo_root/shared/reactor/ReactorModel.js" \
  "$plugin/ReactorModel.js" || fail "vendored Reactor model drift"
cmp -s -- "$repo_root/shared/reactor/QuoteDefaults.js" \
  "$plugin/QuoteDefaults.js" || fail "vendored quote defaults drift"

printf 'reactor plugin regression passed\n'
