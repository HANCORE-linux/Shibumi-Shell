#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/home/hancore/Projects/omarchy-updates-pr}
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-ai-plugin.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'AI plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.ai" "$tmpdir/ai"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/ai-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/AiTestPanel.qml" "$tmpdir/fixtures/"

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
grep -F 'ai plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

widget="$repo_root/hancore.shibumi.ai/BarWidget.qml"
service="$repo_root/hancore.shibumi.ai/Service.qml"
rg -q 'serviceFor\("hancore\.shibumi\.ai"\)' "$widget" \
  || fail "AI widget does not resolve the shared service"
rg -q 'serviceFor\("hancore\.shibumi\.state"\)' "$service" \
  || fail "AI service does not resolve the state owner"
rg -q 'stateService\.setWidgetSetting' "$service" \
  || fail "AI provider selection bypasses the state owner"
if rg -q 'bar\.(aiUsageService|setWidgetSetting)' \
    "$repo_root/hancore.shibumi.ai" --glob '*.qml'; then
  fail "AI plugin consumes transitional bar-owned feature state"
fi
rg -q 'registeredWidgetSource\("omarchy\.model-usage"\)' "$service" \
  || fail "AI service does not retain official Claude/Codex providers"
rg -q 'providerReportsFiveHour' "$service" \
  || fail "AI tooltip lost dynamic Codex 5h reporting"
rg -q 'displayPercent' "$service" \
  || fail "AI service lost provider percentage normalization"
panel="$repo_root/hancore.shibumi.ai/AiUsagePanel.qml"
rg -q 'text: "AI USAGE"' "$panel" \
  || fail "AI panel lost the V1 heading"
rg -q 'font\.pixelSize: Commons\.Style\.font\.subtitle' "$panel" \
  || fail "AI panel heading does not retain the V1 13px role"
rg -q 'color: selected \? panel\.controlActiveFillColor' "$panel" \
  || fail "AI provider tabs bypass shared V1 active tokens"
rg -q 'component ModelUsageRow: Item' "$panel" \
  || fail "AI panel lost OpenCode model rows"
rg -q 'implicitWidth: Commons\.Style\.space\(28\)' "$panel" \
  || fail "AI header actions lost NetworkPanel geometry"
rg -q 'ShibumiPanelToolTip' "$panel" \
  || fail "AI header actions lost panel-local tooltips"
rg -q 'renderType: Text\.NativeRendering' "$panel" \
  || fail "AI panel text does not request native rendering"
if rg -q 'rgba\([^\n]*urgent[^\n]*0\.22' "$panel"; then
  fail "AI panel reintroduced an ad-hoc active fill"
fi
if rg -q 'Process \{|Timer \{|FileView \{' \
    "$widget" "$panel"; then
  fail "AI screen-local views own provider workers"
fi
[[ $(rg -c 'Process \{' "$service") -eq 1 ]] \
  || fail "AI detection does not have exactly one process owner"
rg -q 'running: root\.runtimeProbesEnabled' "$service" \
  || fail "AI detection polling cannot be disabled for lifecycle validation"
if rg -q 'CACHE_FILE|stale_last' "$repo_root/hancore.shibumi.ai/scripts/opencode-usage"; then
  fail "OpenCode provider persists a usage cache"
fi
[[ -x $repo_root/hancore.shibumi.ai/scripts/opencode-usage ]] \
  || fail "OpenCode scanner is not executable"
[[ -s $repo_root/hancore.shibumi.ai/assets/codex.svg \
  && -s $repo_root/hancore.shibumi.ai/assets/opencode-mark.svg ]] \
  || fail "AI provider assets are missing"

printf 'AI plugin regression passed\n'
