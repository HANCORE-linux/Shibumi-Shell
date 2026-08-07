#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
tmpdir=""
shell_unit=""
service_file=""
service_prefix=""
cleanup_log=""
stop_shells=""
cleanup_probe_armed=0
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
  local status=$?
  local cleanup_error=0
  local cleanup_started=$SECONDS
  trap - EXIT
  set +e
  (( status == 0 )) || failed=1

  if [[ -n $stop_shells && -x $stop_shells ]]; then
    timeout --kill-after=1s 8s env \
      SHIBUMI_TEST_SERVICE_FILE="$service_file" \
      SHIBUMI_TEST_CLEANUP_LOG="$cleanup_log" "$stop_shells" \
      >/dev/null 2>&1 || cleanup_error=1
  fi
  if (( cleanup_probe_armed == 1 )) \
      && ! grep -Fxq "KILL $service_prefix-cleanup-probe.service" \
        "$cleanup_log" 2>/dev/null; then
    printf 'Runtime fixture did not exercise the cleanup KILL fallback\n' >&2
    cleanup_error=1
  fi
  if (( SECONDS - cleanup_started > 9 )); then
    printf 'Runtime fixture cleanup exceeded its wall-clock budget\n' >&2
    cleanup_error=1
  fi
  if (( cleanup_error != 0 )); then
    printf 'Runtime fixture service cleanup did not settle\n' >&2
    failed=1
    status=1
  fi

  if [[ $failed -eq 1 && ${SHIBUMI_KEEP_TEST_TMP:-0} == 1 ]]; then
    printf 'Retained failed runtime fixture: %s\n' "$tmpdir" >&2
  elif [[ -n $tmpdir && -d $tmpdir ]]; then
    rm -rf -- "$tmpdir"
  fi
  exit "$status"
}
trap cleanup EXIT

[[ -n $omarchy_path && -x $omarchy_path/bin/omarchy ]] \
  || fail 'OMARCHY_PATH must reference a Quattro checkout'
[[ -x $omarchy_path/bin/omarchy-shell ]] \
  || fail 'Quattro omarchy-shell is missing'
command -v quickshell >/dev/null 2>&1 || fail 'quickshell is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'
command -v systemctl >/dev/null 2>&1 || fail 'systemctl is required'
command -v systemd-run >/dev/null 2>&1 || fail 'systemd-run is required'
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
cp -a "$omarchy_path/bin" "$fixture_omarchy/bin"
ln -s "$omarchy_path/config" "$fixture_omarchy/config"
service_file="$tmpdir/shell-services"
cleanup_log="$tmpdir/service-cleanup.log"
service_prefix="shibumi-runtime-${tmpdir##*.}"
stop_shells="$stub_bin/shibumi-test-stop-shells"
start_shell="$stub_bin/shibumi-test-start-shell"
: >"$service_file"
: >"$cleanup_log"
: >"$tmpdir/quickshell.log"

cat >"$stop_shells" <<'STOP_SHELLS'
#!/usr/bin/env bash
set -euo pipefail

mapfile -t units < <(awk 'NF && !seen[$0]++' "$SHIBUMI_TEST_SERVICE_FILE")
unit_state() {
  timeout --kill-after=0.2s 0.8s systemctl --user show "$1" \
    -p LoadState -p ActiveState --value 2>/dev/null
}
unit_active() {
  local state
  state=$(unit_state "$1") || return 2
  [[ $state == *$'\nactive' || $state == *$'\nactivating' \
      || $state == *$'\ndeactivating' || $state == *$'\nreloading' ]]
}
all_inactive() {
  local unit result
  for unit in "${units[@]}"; do
    if unit_active "$unit"; then
      return 1
    else
      result=$?
      (( result == 1 )) || return 2
    fi
  done
  return 0
}

for unit in "${units[@]}"; do
  timeout --kill-after=0.2s 0.8s systemctl --user kill \
    --kill-whom=all --signal=TERM "$unit" >/dev/null 2>&1 || true
  timeout --kill-after=0.2s 0.8s systemctl --user stop "$unit" \
    >/dev/null 2>&1 || true
done
for _ in {1..20}; do
  all_inactive && exit 0
  result=$?
  (( result == 1 )) || exit 1
  sleep 0.05
done
for unit in "${units[@]}"; do
  if unit_active "$unit"; then
    printf 'KILL %s\n' "$unit" >>"$SHIBUMI_TEST_CLEANUP_LOG"
    timeout --kill-after=0.2s 0.8s systemctl --user kill \
      --kill-whom=all --signal=KILL "$unit" >/dev/null 2>&1 || true
  else
    result=$?
    (( result == 1 )) || exit 1
  fi
done
for _ in {1..20}; do
  all_inactive && exit 0
  result=$?
  (( result == 1 )) || exit 1
  sleep 0.05
done
exit 1
STOP_SHELLS
chmod +x "$stop_shells"

cat >"$start_shell" <<'START_SHELL'
#!/usr/bin/env bash
set -euo pipefail

mapfile -t units < <(awk 'NF && !seen[$0]++' "$SHIBUMI_TEST_SERVICE_FILE")
(( ${#units[@]} < 12 )) || {
  printf 'isolated shell service generation limit exceeded\n' >&2
  exit 1
}
unit="$SHIBUMI_TEST_SERVICE_PREFIX-$(( ${#units[@]} + 1 )).service"
printf '%s\n' "$unit" >>"$SHIBUMI_TEST_SERVICE_FILE"
printf '\n--- shell generation %s ---\n' "$unit" >>"$SHIBUMI_TEST_SHELL_LOG"
environment=(
  --setenv="HOME=$HOME"
  --setenv="XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
  --setenv="XDG_STATE_HOME=$XDG_STATE_HOME"
  --setenv="XDG_CACHE_HOME=$XDG_CACHE_HOME"
  --setenv="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
  --setenv="WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
  --setenv="SHIBUMI_LOCK_FILE=$SHIBUMI_LOCK_FILE"
  --setenv="OMARCHY_PATH=$OMARCHY_PATH"
  --setenv="PATH=$PATH"
  --setenv="SHIBUMI_TEST_SHELL_LOG=$SHIBUMI_TEST_SHELL_LOG"
)
[[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
  || environment+=(--setenv="HYPRLAND_INSTANCE_SIGNATURE=$HYPRLAND_INSTANCE_SIGNATURE")
timeout --kill-after=1s 8s systemd-run --user --quiet --collect \
  --unit="$unit" --service-type=exec \
  --property=KillMode=control-group --property=TimeoutStopSec=0.2s \
  "${environment[@]}" /usr/bin/bash -c \
  'exec quickshell -n -p "$OMARCHY_PATH/shell" --no-color >>"$SHIBUMI_TEST_SHELL_LOG" 2>&1'
printf '%s\n' "$unit"
START_SHELL
chmod +x "$start_shell"

rm -f "$fixture_omarchy/bin/omarchy-restart-shell" \
  "$fixture_omarchy/bin/omarchy-update-available"
cat >"$fixture_omarchy/bin/omarchy-restart-shell" <<'RESTART'
#!/usr/bin/env bash
set -euo pipefail

timeout --kill-after=1s 8s "$SHIBUMI_TEST_STOP_SHELLS"
"$SHIBUMI_TEST_START_SHELL" >/dev/null
for _ in {1..100}; do
  if [[ $("$OMARCHY_PATH/bin/omarchy-shell" shell ping 2>/dev/null || true) == ok ]]; then
    exit 0
  fi
  sleep 0.1
done
printf 'isolated Omarchy shell did not become ready after restart\n' >&2
exit 1
RESTART
chmod +x "$fixture_omarchy/bin/omarchy-restart-shell"
printf '#!/usr/bin/env bash\nexit 1\n' \
  >"$fixture_omarchy/bin/omarchy-update-available"
chmod +x "$fixture_omarchy/bin/omarchy-update-available"
printf '#!/usr/bin/env bash\nexit 1\n' >"$stub_bin/hyprctl"
chmod +x "$stub_bin/hyprctl"

common_env=(
  HOME="$home"
  XDG_CONFIG_HOME="$home/.config"
  XDG_STATE_HOME="$home/.local/state"
  XDG_CACHE_HOME="$home/.cache"
  SHIBUMI_LOCK_FILE="$tmpdir/shibumi-suite.lock"
  SHIBUMI_TEST_SERVICE_FILE="$service_file"
  SHIBUMI_TEST_CLEANUP_LOG="$cleanup_log"
  SHIBUMI_TEST_SERVICE_PREFIX="$service_prefix"
  SHIBUMI_TEST_SHELL_LOG="$tmpdir/quickshell.log"
  SHIBUMI_TEST_START_SHELL="$start_shell"
  SHIBUMI_TEST_STOP_SHELLS="$stop_shells"
  OMARCHY_PATH="$fixture_omarchy"
  PATH="$stub_bin:$fixture_omarchy/bin:$PATH"
)

[[ $(env "${common_env[@]}" bash -c 'command -v omarchy-update-available') \
    == "$fixture_omarchy/bin/omarchy-update-available" ]] \
  || fail 'isolated update-available stub does not own command resolution'

shell_ipc() {
  env "${common_env[@]}" "$fixture_omarchy/bin/omarchy-shell" "$@"
}

suite_cli() {
  env "${common_env[@]}" "$source_root/scripts/shibumi-suite" "$@"
}

shell_unit=$(env "${common_env[@]}" "$start_shell") \
  || fail 'isolated stock Quattro shell service did not start'

shell_ready=0
for _ in {1..100}; do
  if [[ $(shell_ipc shell ping 2>/dev/null || true) == ok ]]; then
    shell_ready=1
    break
  fi
  [[ $(timeout --kill-after=0.2s 0.8s systemctl --user show \
      "$shell_unit" -p ActiveState --value 2>/dev/null) == active ]] \
    || fail 'stock Quattro shell exited before IPC became ready'
  sleep 0.1
done
[[ $shell_ready -eq 1 ]] || fail 'stock Quattro shell did not become ready'

suite_cli install --yes || fail 'suite install command failed'
state_file="$home/.local/state/shibumi/install.json"
[[ -f $state_file ]] || fail 'install state is missing'
first_digest=$(jq -r '.payloadDigest // empty' "$state_file")
[[ $first_digest =~ ^[0-9a-f]{64}$ ]] || fail 'install payload digest is invalid'
[[ $(shell_ipc shibumi-suite-runtime verifyPayload "$first_digest") == ok ]] \
  || fail 'installed state service did not confirm the first payload digest'
suite_cli status >/dev/null || fail 'installed suite status is not clean'

suite_cli deactivate --keep-layout --yes \
  || fail 'suite external-bar transition failed'
config="$home/.config/omarchy/shell.json"
jq -e '(.bar.id // "omarchy.bar") == "omarchy.bar"' "$config" >/dev/null \
  || fail 'external-bar transition did not activate the stock bar'
external_bar_snapshot=$(jq -Sc '.bar' "$config")
[[ $(shell_ipc shibumi-suite-runtime verifyPayload "$first_digest") == ok ]] \
  || fail 'state service endpoint was lost under the stock bar'

printf '\n// isolated runtime update generation\n' \
  >>"$source_root/hancore.shibumi.center/BarWidget.qml"
suite_cli update --yes || fail 'suite update command failed'
second_digest=$(jq -r '.payloadDigest // empty' "$state_file")
[[ $second_digest =~ ^[0-9a-f]{64}$ && $second_digest != "$first_digest" ]] \
  || fail 'updated payload digest did not change'
[[ $(shell_ipc shibumi-suite-runtime verifyPayload "$second_digest") == ok ]] \
  || fail 'updated state service did not confirm the new payload digest'
[[ $(jq -Sc '.bar' "$config") == "$external_bar_snapshot" ]] \
  || fail 'external update rewrote the stock bar or widget layout'
suite_cli status >/dev/null || fail 'external suite status is not clean'

suite_cli activate --yes || fail 'suite reactivation failed'
jq -e '.bar.id == "hancore.shibumi.bar"' "$config" >/dev/null \
  || fail 'reactivation did not restore the Shibumi bar'

suite_cli uninstall --yes || fail 'suite uninstall command failed'
[[ ! -e $home/.local/state/shibumi ]] || fail 'suite state remains after uninstall'
[[ ! -e $home/.cache/shibumi ]] || fail 'suite cache remains after uninstall'
[[ ! -e $home/.config/omarchy/plugins/hancore.shibumi.bar ]] \
  || fail 'Shibumi bar remains after uninstall'
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
timeout --kill-after=1s 8s env \
  SHIBUMI_TEST_SERVICE_FILE="$service_file" \
  SHIBUMI_TEST_CLEANUP_LOG="$cleanup_log" "$stop_shells" \
  || fail 'final fixture shell service drain failed'
if grep -Eq \
    'hancore\.shibumi[^ ]*.*(Binding loop|TypeError|ReferenceError|is not a type|failed to load)|plugin hancore\.shibumi.*failed|bar option hancore\.shibumi.*failed' \
    "$tmpdir/quickshell.log"; then
  fail 'runtime log contains a QML or plugin-load failure'
fi

cleanup_probe="$service_prefix-cleanup-probe.service"
printf '%s\n' "$cleanup_probe" >>"$service_file"
timeout --kill-after=1s 8s systemd-run --user --quiet --collect \
  --unit="$cleanup_probe" --service-type=exec \
  --property=KillMode=control-group \
  --property=TimeoutStopSec=30s /usr/bin/bash -c \
  'trap "" TERM; while :; do sleep 1; done' \
  || fail 'TERM-resistant cleanup probe did not start'
[[ $(timeout --kill-after=0.2s 0.8s systemctl --user show \
    "$cleanup_probe" -p ActiveState --value 2>/dev/null) == active ]] \
  || fail 'TERM-resistant cleanup probe is not active'
cleanup_probe_armed=1

printf 'Shibumi suite Quattro runtime passed\n'
