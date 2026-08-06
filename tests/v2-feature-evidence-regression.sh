#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
port_contract="$repo_root/contracts/v2-feature-port.json"
evidence_contract="$repo_root/contracts/v2-feature-evidence.json"

fail() {
  printf 'V2 feature evidence regression failed: %s\n' "$*" >&2
  exit 1
}

jq -e '
  .schemaVersion == 1
  and .referenceRootId == "v2"
  and (.referenceBaseline | type == "string" and length > 0)
  and (.features | length) == 36
  and (.features | all(
    (.implementation | type) == "array" and (.implementation | length) > 0
    and (.tests | type) == "array" and (.tests | length) > 0))
' "$evidence_contract" >/dev/null || fail "evidence schema is incomplete"

port_baseline=$(jq -r '.referenceBaseline' "$port_contract")
evidence_baseline=$(jq -r '.referenceBaseline' "$evidence_contract")
[[ $port_baseline == "$evidence_baseline" \
    && $(jq -r '.referenceRootId' "$port_contract") == v2 ]] \
  || fail "port and evidence contracts use different predecessor baselines"
[[ -r $repo_root/$evidence_baseline ]] \
  || fail "V2 predecessor baseline is missing"

port_ids=$(jq -c '[.features[].id] | sort' "$port_contract")
evidence_ids=$(jq -c '[.features[].id] | sort' "$evidence_contract")
[[ $port_ids == "$evidence_ids" ]] \
  || fail "port and evidence feature IDs differ"

while IFS= read -r relative_path; do
  [[ -f "$repo_root/$relative_path" ]] \
    || fail "evidence path does not exist: $relative_path"
done < <(jq -r '.features[] | .implementation[], .tests[]' "$evidence_contract" | sort -u)

printf 'V2 feature evidence regression passed\n'
