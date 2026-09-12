#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/shibumi-host-registry-prime.XXXXXX")
cleanup() { rm -rf -- "$tmpdir"; }
trap cleanup EXIT

fail() {
  printf 'host registry prime regression failed: %s\n' "$*" >&2
  exit 1
}

cp -a "$repo_root/hancore.shibumi.state" "$tmpdir/"
cp "$repo_root/tests/host-registry-prime-smoke.qml" "$tmpdir/shell.qml"
printf '%s\n' \
  '{"suiteId":"hancore.shibumi","suitePayloadDigest":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}' \
  > "$tmpdir/hancore.shibumi.state/.shibumi-managed.json"

for mode in success no-rebuild; do
  runtime="$tmpdir/runtime-$mode"
  mkdir -m 700 "$runtime"
  set +e
  output=$(timeout 8 env \
    HOME="$tmpdir/home" \
    SHIBUMI_PRIME_MODE="$mode" \
    WAYLAND_DISPLAY= \
    QT_QPA_PLATFORM=offscreen \
    QT_QPA_PLATFORMTHEME= \
    XDG_RUNTIME_DIR="$runtime" \
    /usr/bin/quickshell -p "$tmpdir" --no-color 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$output"
  [[ $rc -eq 0 ]] || fail "$mode smoke exited $rc"
  if [[ $mode == success ]]; then
    grep -q 'host registry prime success passed' <<<"$output" \
      || fail 'success smoke did not reach its marker'
  else
    grep -q 'host registry prime no-rebuild failure passed' <<<"$output" \
      || fail 'no-rebuild smoke did not fail closed'
  fi
  if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load' \
      <<<"$output"; then
    fail "$mode runtime log contains a composition error"
  fi
done

printf 'host registry prime regression passed\n'
