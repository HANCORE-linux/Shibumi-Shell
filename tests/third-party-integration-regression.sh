#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
fixture_root="$repo_root/tests/fixtures/third-party-integration"
validator="$OMARCHY_PATH/bin/omarchy-plugin-validate"
gate="$repo_root/scripts/check-plugin-integration"
tmpdir=""
shell_pid=""

fail() {
  printf 'third-party integration regression failed: %s\n' "$*" >&2
  [[ -n $tmpdir && -f $tmpdir/quickshell.log ]] \
    && sed -n '1,220p' "$tmpdir/quickshell.log" >&2
  exit 1
}
cleanup() {
  if [[ -n $shell_pid ]] && kill -0 "$shell_pid" 2>/dev/null; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
  fi
  [[ -z $tmpdir || ! -d $tmpdir ]] || rm -rf -- "$tmpdir"
}
trap cleanup EXIT

[[ -x $validator ]] || fail 'authoritative Omarchy plugin validator is missing'
[[ -x $gate ]] || fail 'Shibumi integration gate is missing'
for fixture in conforming duplicate-ipc duplicate-service duplicate-network \
    competing-layer single-quoted-ipc aliased-ipc escaped-ipc \
    line-continuation-ipc template-ipc template-comment-ipc \
    dynamic-template-ipc concatenated-ipc multiline-concatenated-ipc \
    regex-prefix-ipc arrow-regex-ipc grouped-layer spaced-layer \
    commented-resources; do
  "$validator" "$fixture_root/$fixture" \
    || fail "$fixture did not pass the authoritative structural validator"
done

"$gate" --reserved-root "$repo_root" "$fixture_root/conforming" >/dev/null \
  || fail 'conforming fixture was rejected by the Shibumi integration gate'
"$gate" --reserved-root "$repo_root" \
  "$fixture_root/commented-resources" >/dev/null \
  || fail 'comment-only reserved resources caused a false rejection'
assert_rejected() {
  local fixture=$1 kind=$2 resource=$3 output rc
  set +e
  output=$("$gate" --reserved-root "$repo_root" "$fixture_root/$fixture")
  rc=$?
  set -e
  [[ $rc -eq 1 ]] || fail "$fixture did not fail closed at the integration gate"
  jq -e --arg kind "$kind" --arg resource "$resource" \
    '.passed == false and any(.conflicts[];
      .kind == $kind and .resource == $resource)' \
    <<<"$output" >/dev/null \
    || fail "$fixture rejection did not identify $kind:$resource"
}
assert_rejected duplicate-ipc ipc omarchy.audio
assert_rejected duplicate-service ipc shibumi-suite-runtime
assert_rejected duplicate-network ipc omarchy.network
assert_rejected single-quoted-ipc ipc omarchy.audio
assert_rejected aliased-ipc ipc omarchy.audio
assert_rejected escaped-ipc ipc omarchy.audio
assert_rejected line-continuation-ipc ipc omarchy.audio
assert_rejected template-ipc ipc omarchy.audio
assert_rejected template-comment-ipc ipc omarchy.audio
assert_rejected dynamic-template-ipc unsupported 'IPC target'
assert_rejected concatenated-ipc unsupported 'IPC target'
assert_rejected multiline-concatenated-ipc unsupported 'IPC target'
assert_rejected regex-prefix-ipc ipc omarchy.audio
assert_rejected arrow-regex-ipc ipc omarchy.audio
assert_rejected grouped-layer layer shibumi-bar
assert_rejected spaced-layer layer shibumi-bar
assert_rejected competing-layer ipc shibumi-suite
assert_rejected competing-layer layer shibumi-bar

tmpdir=$(mktemp -d /tmp/shibumi-third-party-integration.XXXXXX)
mkdir -p "$tmpdir/home" "$tmpdir/runtime" "$tmpdir/fixtures" \
  "$tmpdir/owners/audio" "$tmpdir/owners/state"
chmod 700 "$tmpdir/runtime"
cp -a "$fixture_root" "$tmpdir/fixtures/"
cp -a "$OMARCHY_PATH/shell/Commons" "$tmpdir/"
cp "$repo_root/hancore.shibumi.audio/Service.qml" "$tmpdir/owners/audio/"
cp -a "$repo_root/hancore.shibumi.state/." "$tmpdir/owners/state/"
cp "$repo_root/tests/third-party-integration-smoke.qml" "$tmpdir/shell.qml"

QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY='' \
HOME="$tmpdir/home" XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" --no-color \
  >"$tmpdir/quickshell.log" 2>&1 &
shell_pid=$!

ipc() {
  timeout 2 env WAYLAND_DISPLAY= XDG_RUNTIME_DIR="$tmpdir/runtime" \
    /usr/bin/qs ipc -p "$tmpdir" "$@"
}
state=""
for _ in {1..100}; do
  kill -0 "$shell_pid" 2>/dev/null \
    || fail 'runtime exited before host lifecycle completed'
  state=$(ipc call third-party-integration-test state 2>/dev/null || true)
  [[ $state == complete:3:0 ]] && break
  sleep 0.03
done
[[ $state == complete:3:0 ]] \
  || fail "conforming host lifecycle did not complete: $state"

ipc_show=$(ipc show)
for target in omarchy.audio shibumi-suite-runtime; do
  [[ $(grep -c "^target $target$" <<<"$ipc_show") -eq 1 ]] \
    || fail "real Shibumi service owner is missing: $target"
done
if grep -q '^target example\.conforming\.' <<<"$ipc_show"; then
  fail 'conforming owner survived final host unload'
fi
ipc call omarchy.audio open >/dev/null
[[ $(ipc call third-party-integration-test state) == complete:3:1 ]] \
  || fail 'real Audio owner did not survive conforming plugin reloads'

for marker in \
  'third-party conforming host load 3' \
  'third-party integration host lifecycle ready'; do
  grep -Fq "$marker" "$tmpdir/quickshell.log" \
    || fail "runtime marker is missing: $marker"
done
if grep -Eq 'another handler is registered for target|TypeError|ReferenceError|is not a type|failed to load|Binding loop|No PanelWindow backend' \
    "$tmpdir/quickshell.log"; then
  fail 'rejected fixture reached runtime or host lifecycle emitted an error'
fi

printf 'third-party integration regression passed\n'
