#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
source_path=${SHIBUMI_AGENTS_OMARCHY_PATH:-}
export SHIBUMI_OMARCHY_BASELINE_PROFILE=agents-current
export OMARCHY_PATH=$source_path

fail() {
  printf 'Omarchy agents contract regression failed: %s\n' "$*" >&2
  exit 1
}

shibumi_load_omarchy_baseline
source_path=$OMARCHY_PATH
manifest=$SHIBUMI_OMARCHY_BASELINE
command -v jq >/dev/null 2>&1 || fail "jq is required"
expected_revision=$(jq -r '.sourceRevision' "$manifest")

while IFS=$'\t' read -r path expected_hash; do
  file="$source_path/$path"
  [[ -f $file ]] || fail "contract file is missing: $path"
  actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
  [[ $actual_hash == "$expected_hash" ]] \
    || fail "content drift: $path"
done < <(jq -r '.files | to_entries[] | [.key, .value] | @tsv' "$manifest")

agents_manifest="$source_path/shell/plugins/agents/manifest.json"
jq -e '
  .schemaVersion == 1 and
  .id == "omarchy.agents" and
  .version == "1.0.0" and
  .kinds == ["bar-widget"] and
  .activation == "on-demand" and
  .entryPoints.barWidget == "Panel.qml" and
  .barWidget.aliases == ["agents", "model-usage"] and
  .barWidget.allowMultiple == false and
  (.barWidget.defaults.providers | keys | sort) == [
    "agy", "claude", "codex", "copilot", "cursor", "deepseek", "devin",
    "fireworks", "grok", "grokbot", "hermes", "kimchi", "kimi", "local",
    "minimax", "muse", "ollama", "opencode", "openrouter", "qwen",
    "synthetic", "vibe", "zai"
  ] and
  all(.barWidget.defaults.providers[]; .enabled == true) and
  .barWidget.defaults.refreshIntervalSec == 900 and
  .barWidget.defaults.syncMode == "Off" and
  .barWidget.defaults.syncDir == "" and
  .barWidget.defaults.syncFileName == "" and
  .barWidget.defaults.syncDeviceId == ""
' "$agents_manifest" >/dev/null \
  || fail "agents manifest contract drifted"

main="$source_path/shell/plugins/agents/Main.qml"
for contract in \
  '/omarchy/agents/usage' \
  'omarchy-agent-usage-update' \
  'record.id' \
  'record.limits' \
  'record.todayTotalTokens' \
  'record.modelUsage'; do
  rg -Fq "$contract" "$main" || fail "agents record contract drifted: $contract"
done

updater="$source_path/bin/omarchy-agent-usage-update"
[[ -x $updater ]] || fail "agents updater is not executable"
# shellcheck disable=SC2016 # These are literal contracts searched in source.
for contract in \
  'USAGE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage"' \
  '--force | --limits-only' \
  'omarchy-agent-usage-' \
  'jq -e .' \
  'mv "$tmp" "$USAGE_DIR/$agent.json"'; do
  rg -Fq -- "$contract" "$updater" \
    || fail "agents updater contract drifted: $contract"
done

collectors="$source_path/shell/plugins/agents/collectors.py"
for contract in \
  'def base_record(' \
  '"schemaVersion": 1' \
  '"id": agent_id' \
  '"name": name' \
  '"ready": False' \
  '"limits": []' \
  '"todayTotalTokens": 0' \
  'record.update(empty_stats())' \
  'record.update(overrides)'; do
  rg -Fq "$contract" "$collectors" \
    || fail "shared collector record contract drifted: $contract"
done
for collector in claude codex; do
  file="$source_path/bin/omarchy-agent-usage-$collector"
  [[ -x $file ]] || fail "$collector collector is not executable"
  for contract in 'from collectors import (' '  base_record,' \
    "AGENT_ID = \"$collector\"" 'record = base_record(' \
    '    AGENT_ID,' '    AGENT_NAME,' '    ready=' 'record.update(stats)' 'emit(record'; do
    rg -Fq "$contract" "$file" \
      || fail "$collector shared record contract drifted: $contract"
  done
done

printf 'Omarchy agents contract regression passed (%s)\n' "$expected_revision"
