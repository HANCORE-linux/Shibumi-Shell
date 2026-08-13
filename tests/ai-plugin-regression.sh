#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-ai-plugin.XXXXXX)
lifecycle_group=""
lifecycle_wrapper=""

cleanup() {
  [[ -z $lifecycle_group ]] \
    || kill -KILL -- "-$lifecycle_group" 2>/dev/null || true
  [[ -z $lifecycle_wrapper ]] \
    || kill -KILL "$lifecycle_wrapper" 2>/dev/null || true
  rm -rf -- "$tmpdir"
}
trap cleanup EXIT

fail() {
  printf 'AI plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures" "$tmpdir/home/.claude" \
  "$tmpdir/home/.codex" "$tmpdir/state/omarchy/agents/usage" \
  "$tmpdir/omarchy/bin"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.ai" "$tmpdir/ai"
install -m 0644 "$repo_root/tests/fixtures/AiPanelHost.qml" \
  "$tmpdir/ai/ShibumiPanel.qml"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/ai-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/AiTestPanel.qml" "$tmpdir/fixtures/"
printf '{}\n' >"$tmpdir/home/.claude/.credentials.json"
: >"$tmpdir/home/.claude/history.jsonl"
printf '{}\n' >"$tmpdir/home/.codex/auth.json"
record_now=$(date --utc --iso-8601=seconds)
jq --arg updatedAt "$record_now" '.updatedAt = $updatedAt' \
  "$repo_root/tests/fixtures/ai-agents/claude-ready-empty.json" \
  >"$tmpdir/state/omarchy/agents/usage/claude.json"
jq --arg updatedAt "$record_now" '.updatedAt = $updatedAt' \
  "$repo_root/tests/fixtures/ai-agents/codex.json" \
  >"$tmpdir/state/omarchy/agents/usage/codex.json"
chmod 0644 "$tmpdir/state/omarchy/agents/usage/claude.json" \
  "$tmpdir/state/omarchy/agents/usage/codex.json"
install -m 0755 \
  "$repo_root/tests/fixtures/ai-agents/omarchy-agent-usage-update" \
  "$tmpdir/omarchy/bin/omarchy-agent-usage-update"
for collector in claude codex; do
  install -m 0755 /usr/bin/true \
    "$tmpdir/omarchy/bin/omarchy-agent-usage-$collector"
done

set +e
output=$(timeout 8 env \
  HOME="$tmpdir/home" \
  XDG_STATE_HOME="$tmpdir/state" \
  SHIBUMI_TEST_OMARCHY_PATH="$tmpdir/omarchy" \
  SHIBUMI_TEST_AGENT_USAGE_DIR="$tmpdir/state/omarchy/agents/usage" \
  SHIBUMI_TEST_MODEL_USAGE_SOURCE="file://$repo_root/tests/fixtures/ai-model-usage/Main.qml" \
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
if grep -Eq ' WARN| ERROR|CRITICAL|TypeError|ReferenceError|Unable to assign' \
    <<<"$output"; then
  fail "component smoke emitted a QML/runtime warning or error"
fi

legacy_claude="$omarchy_path/shell/plugins/model-usage/providers/Claude.qml"
legacy_codex="$omarchy_path/shell/plugins/model-usage/providers/Codex.qml"
agents_manifest="$omarchy_path/shell/plugins/agents/manifest.json"
if [[ -f $legacy_claude && -f $legacy_codex ]]; then
  set +e
  legacy_output=$(timeout 8 env \
    HOME="$tmpdir/home" \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY= \
    XDG_RUNTIME_DIR="$tmpdir/runtime" \
    SHIBUMI_TEST_LEGACY_CLAUDE_SOURCE="file://$legacy_claude" \
    SHIBUMI_TEST_LEGACY_CODEX_SOURCE="file://$legacy_codex" \
    "$quickshell_bin" -p "$repo_root/tests/ai-legacy-provider-contract.qml" \
    2>&1)
  legacy_rc=$?
  set -e
  printf '%s\n' "$legacy_output"
  [[ $legacy_rc -eq 0 ]] \
    || fail "pinned legacy provider contract exited $legacy_rc"
  grep -F 'AI legacy provider contract passed' <<<"$legacy_output" >/dev/null \
    || fail "pinned legacy provider contract marker missing"
elif [[ -e $legacy_claude || -e $legacy_codex ]]; then
  fail "host exposes only part of the legacy model-usage provider contract"
else
  [[ -f $agents_manifest ]] \
    || fail "host exposes neither legacy model-usage nor current agents"
  jq -e '
    .id == "omarchy.agents"
    and .kinds == ["bar-widget"]
    and .entryPoints.barWidget == "Panel.qml"
    and (.barWidget.aliases | index("model-usage")) != null
  ' "$agents_manifest" >/dev/null \
    || fail "current agents replacement contract drifted"
  printf 'AI legacy provider contract absent; current agents replacement selected\n'
fi
python3 "$repo_root/tests/opencode-usage-regression.py" \
  || fail "OpenCode current-model scope regression failed"
[[ -s $tmpdir/state/shibumi-ai-agent-update.log ]] \
  || fail "agents update owner did not run"
grep -Fx 'claude codex' "$tmpdir/state/shibumi-ai-agent-update.log" >/dev/null \
  || fail "agents owner did not perform its bounded initial update"
grep -Fx -- '--force claude codex' \
  "$tmpdir/state/shibumi-ai-agent-update.log" >/dev/null \
  || fail "agents owner did not forward a forced refresh"

wrapper="$repo_root/hancore.shibumi.ai/scripts/agents-update"
SHIBUMI_TEST_STUBBORN=1 SHIBUMI_AI_UPDATE_TIMEOUT=30 \
  HOME="$tmpdir/home" XDG_STATE_HOME="$tmpdir/state" \
  "$wrapper" "$tmpdir/omarchy" claude >/dev/null 2>&1 &
lifecycle_wrapper=$!
for _ in {1..100}; do
  [[ -s $tmpdir/state/shibumi-ai-agent-processes ]] && break
  kill -0 "$lifecycle_wrapper" 2>/dev/null \
    || fail "agents lifecycle wrapper exited before its child registered"
  sleep 0.05
done
[[ -s $tmpdir/state/shibumi-ai-agent-processes ]] \
  || fail "agents lifecycle child did not register"
read -r lifecycle_group lifecycle_descendant \
  <"$tmpdir/state/shibumi-ai-agent-processes"
kill -TERM "$lifecycle_wrapper"
for _ in {1..100}; do
  kill -0 "$lifecycle_wrapper" 2>/dev/null || break
  sleep 0.05
done
if kill -0 "$lifecycle_wrapper" 2>/dev/null; then
  fail "agents lifecycle wrapper ignored teardown"
fi
wait "$lifecycle_wrapper" 2>/dev/null || true
lifecycle_wrapper=""
if kill -0 -- "-$lifecycle_group" 2>/dev/null \
    || kill -0 "$lifecycle_descendant" 2>/dev/null; then
  fail "agents collector process group survived teardown"
fi
lifecycle_group=""

rm -f -- "$tmpdir/state/shibumi-ai-agent-processes"
SHIBUMI_TEST_STUBBORN=1 SHIBUMI_AI_UPDATE_TIMEOUT=30 \
  HOME="$tmpdir/home" XDG_STATE_HOME="$tmpdir/state" \
  "$wrapper" "$tmpdir/omarchy" claude >/dev/null 2>&1 &
lifecycle_wrapper=$!
for _ in {1..100}; do
  [[ -s $tmpdir/state/shibumi-ai-agent-processes ]] && break
  kill -0 "$lifecycle_wrapper" 2>/dev/null \
    || fail "agents abrupt-cleanup wrapper exited before registration"
  sleep 0.05
done
[[ -s $tmpdir/state/shibumi-ai-agent-processes ]] \
  || fail "agents abrupt-cleanup child did not register"
read -r lifecycle_group lifecycle_descendant \
  <"$tmpdir/state/shibumi-ai-agent-processes"
kill -KILL "$lifecycle_wrapper"
wait "$lifecycle_wrapper" 2>/dev/null || true
lifecycle_wrapper=""
for _ in {1..100}; do
  if ! kill -0 -- "-$lifecycle_group" 2>/dev/null \
      && ! kill -0 "$lifecycle_descendant" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if kill -0 -- "-$lifecycle_group" 2>/dev/null \
    || kill -0 "$lifecycle_descendant" 2>/dev/null; then
  fail "agents collector process group survived abrupt wrapper death"
fi
lifecycle_group=""

rm -f -- "$tmpdir/state/shibumi-ai-agent-processes"
set +e
SHIBUMI_TEST_STUBBORN=1 SHIBUMI_AI_UPDATE_TIMEOUT=1 \
  HOME="$tmpdir/home" XDG_STATE_HOME="$tmpdir/state" \
  timeout 10 "$wrapper" "$tmpdir/omarchy" codex >/dev/null 2>&1
watchdog_rc=$?
set -e
[[ $watchdog_rc -ne 0 && $watchdog_rc -ne 124 ]] \
  || fail "agents update watchdog did not enforce its own deadline"
[[ -s $tmpdir/state/shibumi-ai-agent-processes ]] \
  || fail "agents watchdog child did not register"
read -r lifecycle_group lifecycle_descendant \
  <"$tmpdir/state/shibumi-ai-agent-processes"
if kill -0 -- "-$lifecycle_group" 2>/dev/null \
    || kill -0 "$lifecycle_descendant" 2>/dev/null; then
  fail "agents collector process group survived watchdog cleanup"
fi
lifecycle_group=""

missing_root="$tmpdir/missing-collector-omarchy"
mkdir -p "$missing_root/bin"
install -m 0755 "$tmpdir/omarchy/bin/omarchy-agent-usage-update" \
  "$missing_root/bin/omarchy-agent-usage-update"
set +e
HOME="$tmpdir/home" XDG_STATE_HOME="$tmpdir/state" \
  "$wrapper" "$missing_root" claude >/dev/null 2>&1
missing_collector_rc=$?
set -e
[[ $missing_collector_rc -ne 0 ]] \
  || fail "missing requested agent collector was accepted"

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
rg -q 'standardWidgetSource\("omarchy\.agents"\)' "$service" \
  || fail "AI service does not prefer the current Omarchy agents contract"
rg -q 'registeredWidgetSource\("omarchy\.model-usage"\)' "$service" \
  || fail "AI service does not retain the pinned model-usage fallback"
rg -q 'AgentUsageModel\.parseRecord' "$service" \
  || fail "AI service does not normalize primitive agents records"
rg -q 'providerCurrentDataMessage' "$service" \
  || fail "AI service does not expose the ready-without-current-data state"
rg -q 'onTriggered: root\.expireAgentRecords\(Date\.now\(\)\)' "$service" \
  || fail "AI service does not expire already loaded stale agent records"
if rg -q 'source:.*agents/(Main|Panel)\.qml|setSource\([^\n]*agents' "$service"; then
  fail "AI service embeds the host agents presentation"
fi
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
rg -q 'providerEmptyStateText' "$panel" \
  || fail "AI panel does not render the provider no-current-data/auth state"
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
  || fail "AI providers do not have exactly one process owner"
[[ $(rg -c 'FileView \{' "$service") -eq 2 ]] \
  || fail "AI agents records do not have exactly two bounded readers"
rg -q 'running: root\.runtimeProbesEnabled' "$service" \
  || fail "AI polling cannot be disabled for lifecycle validation"
rg -q 'Component\.onDestruction:' "$service" \
  || fail "AI process owner does not define teardown cleanup"
rg -Uq 'Component\.onDestruction: \{(.|\n)*stopScanner\(\)(.|\n)*\}' \
  "$repo_root/hancore.shibumi.ai/OpenCodeProvider.qml" \
  || fail "OpenCode scanner does not stop on teardown"
if ! rg -q 'readonly property bool serviceActive:' "$service" \
    || ! rg -q 'stateService\.groupEnabled\("G7"\)' "$service"; then
  fail "AI provider lifecycle is not gated by G7 activation"
fi
if rg -q 'CACHE_FILE|stale_last' "$repo_root/hancore.shibumi.ai/scripts/opencode-usage"; then
  fail "OpenCode provider persists a usage cache"
fi
cmp -s "$repo_root/scripts/opencode-usage" \
  "$repo_root/hancore.shibumi.ai/scripts/opencode-usage" \
  || fail "canonical and vendored OpenCode scanners drifted"
diff -u \
  <(sed 's#\.\./scripts/opencode-usage#scripts/opencode-usage#' \
    "$repo_root/services/OpenCodeProvider.qml") \
  "$repo_root/hancore.shibumi.ai/OpenCodeProvider.qml" >/dev/null \
  || fail "canonical and vendored OpenCode providers drifted"
rg -q 'con\.execute\("begin"\)' \
  "$repo_root/hancore.shibumi.ai/scripts/opencode-usage" \
  || fail "OpenCode aggregates do not share one SQLite read snapshot"
rg -q 'handleLocalMidnight' \
  "$repo_root/hancore.shibumi.ai/OpenCodeProvider.qml" \
  || fail "OpenCode provider does not invalidate today at local midnight"
rg -q 'clearScannerData\(\)' \
  "$repo_root/hancore.shibumi.ai/OpenCodeProvider.qml" \
  || fail "OpenCode provider does not clear stale data on scanner failure"
rg -q 'model_rows\(messages, today_ms, tomorrow_ms\)' \
  "$repo_root/hancore.shibumi.ai/scripts/opencode-usage" \
  || fail "OpenCode model rows are not scoped to today"
rg -q 'newest_model\(messages, today_ms, tomorrow_ms\)' \
  "$repo_root/hancore.shibumi.ai/scripts/opencode-usage" \
  || fail "OpenCode latest model does not share the today scope"
[[ -x $repo_root/hancore.shibumi.ai/scripts/opencode-usage \
  && -x $repo_root/hancore.shibumi.ai/scripts/agents-update ]] \
  || fail "AI provider scripts are not executable"
[[ -s $repo_root/hancore.shibumi.ai/assets/codex.svg \
  && -s $repo_root/hancore.shibumi.ai/assets/opencode-mark.svg ]] \
  || fail "AI provider assets are missing"

printf 'AI plugin regression passed\n'
