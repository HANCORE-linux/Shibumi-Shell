#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH

fail() {
  printf 'Shibumi suite Quattro dry-run failed: %s\n' "$*" >&2
  exit 1
}

[[ -n $omarchy_path && -x $omarchy_path/bin/omarchy ]] \
  || fail 'OMARCHY_PATH must reference a Quattro checkout'

tmpdir=$(mktemp -d /tmp/shibumi-suite-quattro.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT
mkdir -p "$tmpdir/config" "$tmpdir/state" "$tmpdir/runtime"
chmod 700 "$tmpdir/runtime"

output=$(env \
  HOME="$tmpdir/home" \
  XDG_CONFIG_HOME="$tmpdir/config" \
  XDG_STATE_HOME="$tmpdir/state" \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  OMARCHY_PATH="$omarchy_path" \
  PATH="$omarchy_path/bin:$PATH" \
  "$repo_root/scripts/shibumi-suite" install --dry-run)

printf '%s\n' "$output"
grep -q 'plugins:[[:space:]]*24' <<<"$output" \
  || fail 'dry-run did not validate the complete suite'
grep -q 'Dry run complete; no files changed.' <<<"$output" \
  || fail 'dry-run completion marker is missing'
[[ ! -e $tmpdir/config/omarchy/plugins ]] \
  || fail 'dry-run created a plugin directory'
[[ ! -e $tmpdir/config/omarchy/shell.json ]] \
  || fail 'dry-run created a shell config'
[[ ! -e $tmpdir/state/shibumi ]] \
  || fail 'dry-run created suite state'

printf 'Shibumi suite Quattro dry-run passed\n'
