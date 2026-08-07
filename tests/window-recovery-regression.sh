#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d /tmp/shibumi-window-recovery.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT
mkdir -p "$tmpdir/home" "$tmpdir/runtime" "$tmpdir/core"
chmod 700 "$tmpdir/runtime"
cp "$repo_root/core/WindowRecovery.qml" "$tmpdir/core/"
sed 's#import "../core" as Core#import "core" as Core#' \
  "$repo_root/tests/window-recovery-regression.qml" >"$tmpdir/shell.qml"

set +e
output=$(timeout 4 env \
  HOME="$tmpdir/home" \
  QT_QPA_PLATFORM=offscreen \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" 2>&1)
rc=$?
set -e
printf '%s\n' "$output"

[[ $rc -eq 0 ]] || {
  printf 'window recovery regression failed: smoke exited %s\n' "$rc" >&2
  exit 1
}
grep -Fq 'window recovery regression passed' <<<"$output" \
  || { printf 'window recovery regression failed: success marker missing\n' >&2; exit 1; }
if grep -Eq 'TypeError|ReferenceError|is not a type|failed to load|Binding loop' \
    <<<"$output"; then
  printf 'window recovery regression failed: runtime error detected\n' >&2
  exit 1
fi
printf 'window recovery regression passed\n'
