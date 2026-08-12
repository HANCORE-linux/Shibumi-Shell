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
[[ $source_path == /* ]] \
  || fail "SHIBUMI_AGENTS_OMARCHY_PATH must be an absolute checkout path"
[[ -d $source_path/.git ]] || fail "source is not a Git checkout"
command -v jq >/dev/null 2>&1 || fail "jq is required"
expected_revision=$(jq -r '.sourceRevision' "$manifest")
actual_revision=$(git -C "$source_path" rev-parse HEAD 2>/dev/null) \
  || fail "cannot read source revision"
[[ $actual_revision == "$expected_revision" ]] \
  || fail "revision drift: expected $expected_revision, got $actual_revision"

while IFS=$'\t' read -r path expected_hash; do
  file="$source_path/$path"
  [[ -f $file ]] || fail "contract file is missing: $path"
  actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
  [[ $actual_hash == "$expected_hash" ]] \
    || fail "content drift: $path"
done < <(jq -r '.files | to_entries[] | [.key, .value] | @tsv' "$manifest")

agents_manifest="$source_path/shell/plugins/agents/manifest.json"
jq -e '
  .id == "omarchy.agents" and
  .kinds == ["bar-widget"] and
  .entryPoints.barWidget == "Panel.qml" and
  (.barWidget.aliases | index("model-usage")) != null and
  .barWidget.defaults.providers.claude.enabled == true and
  .barWidget.defaults.providers.codex.enabled == true and
  .barWidget.defaults.refreshIntervalSec == 900
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

for collector in claude codex; do
  file="$source_path/bin/omarchy-agent-usage-$collector"
  [[ -x $file ]] || fail "$collector collector is not executable"
  for key in schemaVersion id name ready limits todayTotalTokens; do
    rg -Fq "\"${key}\"" "$file" \
      || rg -Fq "'${key}'" "$file" \
      || fail "$collector record key is missing: $key"
  done
done

printf 'Omarchy agents contract regression passed (%s)\n' "$expected_revision"
