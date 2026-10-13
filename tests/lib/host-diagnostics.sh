#!/usr/bin/env bash
# Only identical policies are shared. Additional diagnostics remain caller-local.
while IFS=$'\t' read -r _host_name _host_pattern; do
  printf -v "HOST_DIAGNOSTICS_$_host_name" '%s' "$_host_pattern"
done < "$(dirname -- "${BASH_SOURCE[0]}")/host-diagnostics.txt"
unset _host_name _host_pattern

# Callers retain substring/whole-line matching and their own extra exceptions.
host_filter_startup_diagnostics() {
  grep -Fv -e "$HOST_DIAGNOSTICS_STARTUP_UNSET" "$@"
}
