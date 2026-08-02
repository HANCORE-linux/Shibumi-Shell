#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
matrix="$repo_root/contracts/v1-state-matrix.json"
v2="$repo_root/contracts/v2-feature-port.json"

fail() {
  printf 'state matrix contract regression failed: %s\n' "$*" >&2
  exit 1
}

jq -e '.schemaVersion == 1 and (.rows | length) >= 27' "$matrix" >/dev/null \
  || fail "V1 matrix is incomplete"
for group in G1 G2 G3 G4 G5 G6 G7 G8 G9 G10 G11 G12 G13 G14 G15; do
  jq -e --arg group "$group" '.rows | any(.group == $group)' "$matrix" >/dev/null \
    || fail "V1 matrix has no row for $group"
done
for state in closed open hover active empty populated error degraded; do
  jq -e --arg state "$state" \
    '.policy.requiredVisualStates | index($state) != null' "$matrix" >/dev/null \
    || fail "V1 matrix omits required state: $state"
done
jq -e '
  (.rows | all((.positions | index("top")) != null and
               (.positions | index("bottom")) != null)) and
  (.finalHardwareGates | map(.id) | sort ==
    ["hardware.bluetooth-device","hardware.enterprise-wifi","hardware.monitor"]) and
  (.finalHardwareGates | all(.phase == "final"))
' "$matrix" >/dev/null || fail "position or final hardware ordering contract"

jq -e '
  .schemaVersion == 1 and
  .policy.decision == "port-all-user-visible-outcomes" and
  .policy.copyLegacyBackends == false and
  .policy.retainOfficialOmarchyOwners == true and
  (.features | length) >= 35 and
  (.features | all(.decision == "port"))
' "$v2" >/dev/null || fail "V2 is not an all-port contract"
for feature in \
  bar-shell.full bar-shell.fit bar-shell.dock bar-shell.notch \
  workspace.kanji workspace.rings workspace.aurora \
  picker.tanzaku picker.hearthstone picker.carousel \
  widget.palette widget.separators temperature.widget thermals.panel \
  gpu.widget-panel storage.widget-panel media.artwork \
  panel.connected-silhouette panel.pointer control-center.v2-capabilities; do
  jq -e --arg feature "$feature" \
    '.features | any(.id == $feature and .decision == "port")' "$v2" >/dev/null \
    || fail "V2 port feature is missing: $feature"
done

printf 'state matrix contract regression passed\n'
