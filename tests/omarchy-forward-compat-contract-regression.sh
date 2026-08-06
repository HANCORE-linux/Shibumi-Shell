#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
forward_path=${SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH:-}

if [[ $forward_path != /* || ! -d $forward_path ]]; then
  printf '%s\n' \
    'forward-compat contract regression failed: SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH must be an absolute checkout path' >&2
  exit 1
fi

export SHIBUMI_OMARCHY_BASELINE_PROFILE=forward-compat
export OMARCHY_PATH=$forward_path

exec "$repo_root/tests/contract-regression.sh"
