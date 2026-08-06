#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export SHIBUMI_OMARCHY_BASELINE_PROFILE=installed-package
export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}

exec "$repo_root/tests/contract-regression.sh"
