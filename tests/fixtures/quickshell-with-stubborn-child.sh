#!/usr/bin/env bash

set -euo pipefail

real_quickshell_bin=${REAL_QUICKSHELL_BIN:-/usr/bin/quickshell}
child_state_file=${SHIBUMI_BT_STUBBORN_CHILD_FILE:?missing stubborn child state file}

(
  trap '' INT TERM HUP
  while true; do sleep 1; done
) &
child_pid=$!
child_pgid=$(ps -o pgid= -p "$child_pid" | tr -d ' ')
printf '%s:%s\n' "$child_pid" "$child_pgid" >"$child_state_file"

exec "$real_quickshell_bin" "$@"
