#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/contracts/host-facade-v1.json"
bar_source="$repo_root/Bar.qml"
strict_ownership=false

fail() {
  printf 'host facade contract regression failed: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'usage: %s [--strict-ownership] [bar-source]\n' "${0##*/}" >&2
}

while (($#)); do
  case $1 in
    --strict-ownership)
      strict_ownership=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      usage
      fail "unknown option: $1"
      ;;
    *)
      [[ $bar_source == "$repo_root/Bar.qml" ]] \
        || fail "only one bar source may be supplied"
      bar_source=$1
      ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v rg >/dev/null 2>&1 || fail "rg is required"
[[ -s $contract ]] || fail "missing contract: $contract"
[[ -s $bar_source ]] || fail "missing bar source: $bar_source"

contract_version=$(jq -er '.contractVersion | select(type == "number")' "$contract") \
  || fail "invalid contract version"

property_pattern() {
  local name=$1
  printf '^[[:space:]]*(readonly[[:space:]]+)?property[[:space:]]+[^[:space:]]+[[:space:]]+%s([[:space:]]*:|[[:space:]]*$)' "$name"
}

while IFS= read -r name; do
  rg -q "$(property_pattern "$name")" "$bar_source" \
    || fail "missing required property: $name"
done < <(jq -r '.requiredProperties[]' "$contract")

rg -q "^[[:space:]]*readonly property int shibumiHostContractVersion:[[:space:]]*$contract_version([[:space:]]|$)" \
  "$bar_source" || fail "host contract identity does not equal $contract_version"

while IFS=$'\t' read -r name value; do
  rg -q "^[[:space:]]*readonly property bool ${name}:[[:space:]]*${value}([[:space:]]|$)" \
    "$bar_source" || fail "fixed facade property drifted: $name"
done < <(jq -r '.fixedPropertyValues | to_entries[] | [.key, (.value | tostring)] | @tsv' "$contract")

while IFS= read -r name; do
  rg -q "^[[:space:]]*function[[:space:]]+${name}[[:space:]]*\(" "$bar_source" \
    || fail "missing required method: $name"
done < <(jq -r '.requiredMethods[], .omarchyCompatibilityMethods[]' "$contract")

while IFS= read -r name; do
  rg -q "$(property_pattern "$name")" "$bar_source" \
    || fail "missing host-injected property: $name"
  if rg -q "^[[:space:]]*required property[[:space:]]+[^[:space:]]+[[:space:]]+$name([[:space:]]|$)" \
      "$bar_source"; then
    fail "asynchronously injected property is required: $name"
  fi
done < <(jq -r '.hostInjectedProperties[]' "$contract")

mapfile -t forbidden_present < <(
  while IFS= read -r name; do
    if rg -q "$(property_pattern "$name")" "$bar_source"; then
      printf '%s\n' "$name"
    fi
  done < <(jq -r '.forbiddenFeatureProperties[]' "$contract")
)

if $strict_ownership && ((${#forbidden_present[@]})); then
  fail "bar still owns forbidden feature properties: ${forbidden_present[*]}"
fi

if ((${#forbidden_present[@]})); then
  printf 'host facade surface regression passed (transitional ownership debt: %d properties)\n' \
    "${#forbidden_present[@]}"
else
  printf 'host facade contract regression passed\n'
fi
