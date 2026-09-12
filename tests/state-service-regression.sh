#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# Actual State service and public setters, explicit inert palette/scoped writer,
# owned HOME/XDG/cgroup, no production bus or settings access.
python3 "$repo_root/tests/state-storage-regression.py"
python3 "$repo_root/tests/state-storage-regression.py" --service --transition-controls
printf 'state service regression passed\n'
