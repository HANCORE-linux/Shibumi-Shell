#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
suite="$repo_root/contracts/plugin-suite-v1.json"
host="$repo_root/contracts/host-facade-v1.json"

fail() {
  printf 'plugin suite contract regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

rg -Fq 'function reloadPayload(): string' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "bar host does not expose the post-update QML reload gate"
rg -Fq 'runtime.reload_payload()' \
  "$repo_root/scripts/shibumi_suite/cli.py" \
  || fail "suite update does not request the post-update QML reload gate"

jq -e '
  .schemaVersion == 1 and
  .suiteId == "hancore.shibumi" and
  .suiteVersion != "" and
  .hostContract == "contracts/host-facade-v1.json" and
  (.plugins | length) > 0 and
  (.profiles | length) > 0
' "$suite" >/dev/null || fail "invalid suite header"

jq -e '
  .schemaVersion == 1 and
  .id == "hancore.shibumi.host-facade" and
  .contractVersion == 1 and
  (.hostInjectedProperties | length) > 0 and
  (.requiredProperties | length) > 0 and
  (.requiredMethods | length) > 0
' "$host" >/dev/null || fail "invalid host facade header"

duplicate_ids=$(jq -r '.plugins[].id' "$suite" | sort | uniq -d)
[[ -z $duplicate_ids ]] || fail "duplicate plugin ids: $duplicate_ids"

duplicate_roles=$(jq -r '.plugins[] | select(.role | test("^G([1-9]|1[0-5])$")) | .role' \
  "$suite" | sort | uniq -d)
[[ -z $duplicate_roles ]] || fail "duplicate G1-G15 owners: $duplicate_roles"

for group in $(seq 1 15); do
  jq -e --arg role "G$group" \
    '[.plugins[] | select(.role == $role)] | length == 1' "$suite" >/dev/null \
    || fail "G$group must have exactly one owner"
done

while IFS=$'\t' read -r plugin_id dependency; do
  [[ $plugin_id != "$dependency" ]] || fail "$plugin_id depends on itself"
  jq -e --arg id "$dependency" '.plugins | any(.id == $id)' "$suite" >/dev/null \
    || fail "$plugin_id requires unknown plugin $dependency"
done < <(jq -r '.plugins[] | .id as $id | .requires[]? | [$id, .] | @tsv' "$suite")

declare -A visiting=()
declare -A visited=()

visit_plugin() {
  local id=$1 dependency
  [[ ${visited[$id]:-0} == 1 ]] && return 0
  [[ ${visiting[$id]:-0} != 1 ]] || fail "dependency cycle reaches $id"
  visiting[$id]=1
  while IFS= read -r dependency; do
    [[ -n $dependency ]] && visit_plugin "$dependency"
  done < <(jq -r --arg id "$id" '.plugins[] | select(.id == $id) | .requires[]?' "$suite")
  visiting[$id]=0
  visited[$id]=1
}

while IFS= read -r plugin_id; do
  visit_plugin "$plugin_id"
done < <(jq -r '.plugins[].id' "$suite")

while IFS= read -r plugin_id; do
  manifest="$repo_root/$plugin_id/manifest.json"
  [[ -f $manifest ]] || continue
  jq -e --arg id "$plugin_id" --slurpfile suite "$suite" '
    ($suite[0].plugins[] | select(.id == $id)) as $contract |
    .id == $contract.id and
    .kinds == $contract.kinds and
    .["x-shibumi"].suiteId == $suite[0].suiteId and
    .["x-shibumi"].bundle == $contract.bundle and
    .["x-shibumi"].role == $contract.role and
    .["x-shibumi"].requires == $contract.requires and
    .["x-shibumi"].recommends == $contract.recommends
  ' "$manifest" >/dev/null || fail "$plugin_id manifest drifts from suite contract"
done < <(jq -r '.plugins[].id' "$suite")

jq -e '
  [.plugins[] | select(.role == "bar-host" and .kinds == ["bar"])]
    | length == 1
' "$suite" >/dev/null || fail "suite must define exactly one default bar host"

profile_count=$(jq '[.profiles[] | select(.id == "default")] | length' "$suite")
[[ $profile_count -eq 1 ]] || fail "default profile must exist exactly once"

active_bar=$(jq -r '.profiles[] | select(.id == "default") | .activeBar' "$suite")
[[ $active_bar == hancore.shibumi.bar ]] || fail "default profile selects wrong bar"

mapfile -t plugin_ids < <(jq -r '.plugins[].id' "$suite" | sort)
mapfile -t installed_ids < <(jq -r '.profiles[] | select(.id == "default") | .install[]' \
  "$suite" | sort)
[[ ${plugin_ids[*]} == "${installed_ids[*]}" ]] \
  || fail "default profile does not install the complete declared suite"

mapfile -t enabled_ids < <(jq -r '
  .profiles[] | select(.id == "default") |
  (.enableServices + .layout.left + .layout.center + .layout.right)[]
' "$suite")

for plugin_id in "${enabled_ids[@]}"; do
  jq -e --arg id "$plugin_id" \
    '.profiles[] | select(.id == "default") | .install | index($id) != null' \
    "$suite" >/dev/null || fail "enabled plugin is not installed: $plugin_id"
done

duplicate_enabled=$(printf '%s\n' "${enabled_ids[@]}" | sort | uniq -d)
[[ -z $duplicate_enabled ]] || fail "default profile enables plugins twice: $duplicate_enabled"

while IFS= read -r plugin_id; do
  jq -e --arg id "$plugin_id" '
    .plugins[] | select(.id == $id) | .kinds | index("bar-widget") != null
  ' "$suite" >/dev/null || fail "layout contains non-widget plugin: $plugin_id"
done < <(jq -r '
  .profiles[] | select(.id == "default") |
  (.layout.left + .layout.center + .layout.right)[]
' "$suite")

while IFS= read -r plugin_id; do
  jq -e --arg id "$plugin_id" '
    .plugins[] | select(.id == $id) | .kinds | index("bar-widget") != null
  ' "$suite" >/dev/null || fail "disabledByDefault contains non-widget plugin: $plugin_id"
done < <(jq -r '.profiles[] | select(.id == "default") | .disabledByDefault[]' "$suite")

for array_name in hostInjectedProperties requiredProperties requiredMethods \
  omarchyCompatibilityMethods internalOnlyProperties forbiddenFeatureProperties; do
  duplicates=$(jq -r --arg name "$array_name" '.[$name][]' "$host" | sort | uniq -d)
  [[ -z $duplicates ]] || fail "duplicate $array_name members: $duplicates"
done

overlap=$(jq -r '
  [.requiredProperties[] as $required |
    .forbiddenFeatureProperties[] | select(. == $required)] | .[]?
' "$host")
[[ -z $overlap ]] || fail "required and forbidden host members overlap: $overlap"

jq -e '
  (.requiredProperties | index("shibumiHostContractVersion") != null) and
  (.requiredProperties | index("visualTokens") != null) and
  (.requiredMethods | index("widgetSettings") != null) and
  (.requiredMethods | index("requestPopout") != null) and
  (.requiredMethods | index("screenForName") != null) and
  (.forbiddenFeatureProperties | index("systemTelemetry") != null) and
  (.forbiddenFeatureProperties | index("pickerService") != null)
' "$host" >/dev/null || fail "host facade misses critical ownership boundaries"

printf 'plugin suite contract regression passed\n'
