#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-}
tmpdir=""
shell_pid=""
failed=0

fail() {
  failed=1
  printf 'Shibumi suite Quattro runtime failed: %s\n' "$*" >&2
  if [[ -n $tmpdir && -f $tmpdir/quickshell.log ]]; then
    sed -n '1,260p' "$tmpdir/quickshell.log" >&2
  fi
  exit 1
}

cleanup() {
  if [[ -n $shell_pid ]] && kill -0 "$shell_pid" 2>/dev/null; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
  fi
  if [[ $failed -eq 1 && ${SHIBUMI_KEEP_TEST_TMP:-0} == 1 ]]; then
    printf 'Retained failed runtime fixture: %s\n' "$tmpdir" >&2
  elif [[ -n $tmpdir && -d $tmpdir ]]; then
    rm -rf -- "$tmpdir"
  fi
}
trap cleanup EXIT

[[ -n $omarchy_path && -x $omarchy_path/bin/omarchy ]] \
  || fail 'OMARCHY_PATH must reference a Quattro checkout'
[[ -x $omarchy_path/bin/omarchy-shell ]] \
  || fail 'Quattro omarchy-shell is missing'
command -v quickshell >/dev/null 2>&1 || fail 'quickshell is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'
[[ -n ${WAYLAND_DISPLAY:-} && -n ${XDG_RUNTIME_DIR:-} ]] \
  || fail 'a running Wayland user session is required'

tmpdir=$(mktemp -d /tmp/shibumi-suite-runtime.XXXXXX)
home="$tmpdir/home"
source_root="$tmpdir/source"
stub_bin="$tmpdir/bin"
fixture_omarchy="$tmpdir/omarchy"
mkdir -p "$home/.config" "$home/.local/state" "$home/.cache" "$source_root" "$stub_bin" \
  "$fixture_omarchy"
cp -a "$repo_root/." "$source_root/"
cp -a "$omarchy_path/shell" "$fixture_omarchy/shell"
ln -s "$omarchy_path/bin" "$fixture_omarchy/bin"
ln -s "$omarchy_path/config" "$fixture_omarchy/config"

printf '#!/usr/bin/env bash\nexit 1\n' >"$stub_bin/omarchy-update-available"
chmod +x "$stub_bin/omarchy-update-available"

common_env=(
  HOME="$home"
  XDG_CONFIG_HOME="$home/.config"
  XDG_STATE_HOME="$home/.local/state"
  XDG_CACHE_HOME="$home/.cache"
  SHIBUMI_LOCK_FILE="$tmpdir/shibumi-suite.lock"
  OMARCHY_PATH="$fixture_omarchy"
  PATH="$stub_bin:$fixture_omarchy/bin:$PATH"
)

shell_ipc() {
  env "${common_env[@]}" "$fixture_omarchy/bin/omarchy-shell" "$@"
}

suite_cli() {
  env "${common_env[@]}" "$source_root/scripts/shibumi-suite" "$@"
}

env "${common_env[@]}" \
  quickshell -p "$fixture_omarchy/shell" --no-color \
  >"$tmpdir/quickshell.log" 2>&1 &
shell_pid=$!

for _ in {1..100}; do
  shell_ipc -q shell ping >/dev/null 2>&1 && break
  kill -0 "$shell_pid" 2>/dev/null \
    || fail 'stock Quattro shell exited before IPC became ready'
  sleep 0.1
done
[[ $(shell_ipc shell ping 2>/dev/null || true) == ok ]] \
  || fail 'stock Quattro shell did not become ready'

suite_cli install --yes || fail 'suite install command failed'
state_file="$home/.local/state/shibumi/install.json"
[[ -f $state_file ]] || fail 'install state is missing'
first_digest=$(jq -r '.payloadDigest // empty' "$state_file")
[[ $first_digest =~ ^[0-9a-f]{64}$ ]] || fail 'install payload digest is invalid'
[[ $(shell_ipc shibumi-suite verifyPayload "$first_digest") == ok ]] \
  || fail 'installed bar did not confirm the first payload digest'
suite_cli status >/dev/null || fail 'installed suite status is not clean'

printf '\n// isolated runtime update generation\n' \
  >>"$source_root/hancore.shibumi.center/BarWidget.qml"
suite_cli update --yes || fail 'suite update command failed'
second_digest=$(jq -r '.payloadDigest // empty' "$state_file")
[[ $second_digest =~ ^[0-9a-f]{64}$ && $second_digest != "$first_digest" ]] \
  || fail 'updated payload digest did not change'
[[ $(shell_ipc shibumi-suite verifyPayload "$second_digest") == ok ]] \
  || fail 'updated bar did not confirm the new payload digest'

suite_cli uninstall --yes || fail 'suite uninstall command failed'
[[ ! -e $home/.local/state/shibumi ]] || fail 'suite state remains after uninstall'
[[ ! -e $home/.cache/shibumi ]] || fail 'suite cache remains after uninstall'
[[ ! -e $home/.config/omarchy/plugins/hancore.shibumi.bar ]] \
  || fail 'Shibumi bar remains after uninstall'
config="$home/.config/omarchy/shell.json"
jq -e '
  (.bar.id // "omarchy.bar") == "omarchy.bar" and
  all(.plugins[]?; (.id // "") | startswith("hancore.shibumi.") | not) and
  all((.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?);
      ((.id // .) | startswith("hancore.shibumi.") | not))
' "$config" >/dev/null || fail 'uninstall did not restore a Shibumi-free config'
[[ $(shell_ipc shell ping) == ok ]] || fail 'stock shell did not survive uninstall'

if find "$home/.config/omarchy/plugins" -mindepth 1 -maxdepth 1 \
    -name '.shibumi-*' -print -quit 2>/dev/null | grep -q .; then
  fail 'hidden lifecycle artifacts remain after uninstall'
fi
if grep -Eq \
    'hancore\.shibumi[^ ]*.*(Binding loop|TypeError|ReferenceError|is not a type|failed to load)|plugin hancore\.shibumi.*failed|bar option hancore\.shibumi.*failed' \
    "$tmpdir/quickshell.log"; then
  fail 'runtime log contains a QML or plugin-load failure'
fi

printf 'Shibumi suite Quattro runtime passed\n'
