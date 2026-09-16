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
      SHIBUMI_TEST_CLEANUP_LOG="$cleanup_log" \
      SHIBUMI_TEST_SERVICE_PREFIX="$service_prefix" "$stop_shells" \
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
command -v git >/dev/null 2>&1 || fail 'git is required'
command -v tar >/dev/null 2>&1 || fail 'tar is required'
command -v systemctl >/dev/null 2>&1 || fail 'systemctl is required'
command -v systemd-run >/dev/null 2>&1 || fail 'systemd-run is required'
[[ -n ${WAYLAND_DISPLAY:-} && -n ${XDG_RUNTIME_DIR:-} ]] \
  || fail 'a running Wayland user session is required'

tmpdir=$(mktemp -d /tmp/shibumi-suite-runtime.XXXXXX)
update_home="$tmpdir/update-home"
update_config_home="$update_home/.config"
update_state_home="$update_home/.local/state"
update_cache_home="$update_home/.cache"
fresh_home="$tmpdir/fresh-home"
fresh_config_home="$fresh_home/.config"
fresh_state_home="$fresh_home/.local/state"
fresh_cache_home="$fresh_home/.cache"
predecessor_root="$tmpdir/predecessor-package"
candidate_root="$tmpdir/candidate-package"
source_root=""
stub_bin="$tmpdir/bin"
fixture_omarchy="$tmpdir/omarchy"
mkdir -p "$update_home" "$fresh_home" "$predecessor_root" \
  "$candidate_root" "$stub_bin" "$fixture_omarchy"
predecessor_revision=2760cdb8272255790d5e4613fed8a48cb63c3555
# Only committed payload is tested; uncommitted plugin changes are invisible to this gate.
candidate_revision=$(git --no-replace-objects -C "$repo_root" rev-parse HEAD)
[[ $candidate_revision =~ ^[0-9a-f]{40}$ ]] \
  || fail 'candidate HEAD did not resolve to a full commit identity'

# Both arms install package-projected payloads (PACKAGE-METADATA.json at root, mirrors PKGBUILD:62). Source-checkout → source-checkout transitions are not exercised here.
git --no-replace-objects -C "$repo_root" archive "$predecessor_revision" \
  | tar -x -C "$predecessor_root"
git --no-replace-objects -C "$repo_root" archive "$candidate_revision" \
  | tar -x -C "$candidate_root"
for package_root in "$predecessor_root" "$candidate_root"; do
  [[ -d $package_root && ! -L $package_root ]] \
    || fail "package fixture root is not an isolated real directory: $package_root"
  [[ -f $package_root/packaging/package-metadata.json \
      && ! -L $package_root/packaging/package-metadata.json ]] \
    || fail "package metadata source is not a regular file: $package_root"
  cp -a "$package_root/packaging/package-metadata.json" \
    "$package_root/PACKAGE-METADATA.json"
done

validate_package_identity() {
  local package_root=$1
  local expected_version=$2
  [[ -f $package_root/PACKAGE-METADATA.json \
      && ! -L $package_root/PACKAGE-METADATA.json ]] \
    || fail "projected package metadata is not a regular file: $package_root"
  jq -e --arg version "$expected_version" '
    type == "object" and
    keys == ["packageName", "schemaVersion", "version"] and
    .schemaVersion == 1 and
    .packageName == "shibumi-shell" and
    .version == $version
  ' "$package_root/PACKAGE-METADATA.json" >/dev/null \
    || fail "projected package identity is invalid: $package_root"
  jq -e --arg version "$expected_version" '.suiteVersion == $version' \
    "$package_root/contracts/plugin-suite-v1.json" >/dev/null \
    || fail "package suite identity is invalid: $package_root"
  [[ $(<"$package_root/VERSION") == "$expected_version" ]] \
    || fail "package VERSION is invalid: $package_root"
}

validate_package_identity "$predecessor_root" '0.1.1-beta.13'
validate_package_identity "$candidate_root" '0.1.1-beta.14.1'

cp -a "$omarchy_path/shell" "$fixture_omarchy/shell"
cp -a "$omarchy_path/bin" "$fixture_omarchy/bin"
cp -a "$omarchy_path/config" "$fixture_omarchy/config"
for fixture_directory in shell bin config; do
  [[ -d $fixture_omarchy/$fixture_directory \
      && ! -L $fixture_omarchy/$fixture_directory ]] \
    || fail "fixture Omarchy $fixture_directory is not an isolated real directory"
done
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
[[ $SHIBUMI_TEST_SERVICE_PREFIX =~ ^shibumi-runtime-[A-Za-z0-9]{6}$ ]] \
  || exit 1
for unit in "${units[@]}"; do
  if [[ ! $unit =~ ^${SHIBUMI_TEST_SERVICE_PREFIX}-([1-9]|1[0-2])\.service$ \
      && $unit != "$SHIBUMI_TEST_SERVICE_PREFIX-cleanup-probe.service" ]]; then
    printf 'refusing foreign fixture service: %s\n' "$unit" >&2
    exit 1
  fi
done
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
[[ $SHIBUMI_TEST_SERVICE_PREFIX =~ ^shibumi-runtime-[A-Za-z0-9]{6}$ ]] \
  || exit 1
for existing in "${units[@]}"; do
  [[ $existing =~ ^${SHIBUMI_TEST_SERVICE_PREFIX}-([1-9]|1[0-2])\.service$ ]] \
    || exit 1
done
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

common_env=()
home=""
config_home=""
state_home=""
cache_home=""
state_file=""
config=""

set_arm_environment() {
  local arm=$1
  home=$2
  config_home=$3
  state_home=$4
  cache_home=$5
  common_env=(
    HOME="$home"
    XDG_CONFIG_HOME="$config_home"
    XDG_STATE_HOME="$state_home"
    XDG_CACHE_HOME="$cache_home"
    SHIBUMI_LOCK_FILE="$tmpdir/$arm-shibumi-suite.lock"
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
}

shell_ipc() {
  env "${common_env[@]}" "$fixture_omarchy/bin/omarchy-shell" "$@"
}

suite_cli() {
  env "${common_env[@]}" "$source_root/scripts/shibumi-suite" "$@"
}

service_generation_count() {
  awk 'NF { count++ } END { print count + 0 }' "$service_file"
}

assert_empty_directory() {
  local directory=$1
  [[ -d $directory && ! -L $directory ]] \
    || fail "fresh fixture path is not a real directory: $directory"
  [[ -z $(find "$directory" -mindepth 1 -maxdepth 1 -print -quit) ]] \
    || fail "fresh fixture path is not empty: $directory"
}

start_stock_shell() {
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
}

assert_package_install_state() {
  local expected_root=$1
  local expected_version=$2
  local expected_revision="package:$expected_version"
  local marker_count=0
  state_file="$state_home/shibumi/install.json"
  [[ -f $state_file && ! -L $state_file ]] || fail 'install state is missing'
  jq -e --arg root "$expected_root" --arg version "$expected_version" \
    --arg revision "$expected_revision" '
      .suiteVersion == $version and
      .installOrigin == "package" and
      .payloadRoot == $root and
      .sourceRevision == $revision and
      .packageName == "shibumi-shell" and
      .packageVersion == $version and
      (.plugins | length) == 24
    ' "$state_file" >/dev/null \
    || fail "installed package authority is invalid for $expected_version"
  while IFS= read -r marker; do
    ((marker_count += 1))
    jq -e --arg version "$expected_version" --arg revision "$expected_revision" '
      .suiteVersion == $version and .sourceRevision == $revision
    ' "$marker" >/dev/null \
      || fail "managed marker package authority is invalid: $marker"
  done < <(find "$config_home/omarchy/plugins" -mindepth 2 -maxdepth 2 \
    -name .shibumi-managed.json -type f -print)
  (( marker_count == 24 )) \
    || fail "installed package has $marker_count managed markers instead of 24"
}

assert_uninstalled_arm() {
  [[ ! -e $state_home/shibumi && ! -L $state_home/shibumi ]] \
    || fail 'suite state remains after uninstall'
  [[ ! -e $cache_home/shibumi && ! -L $cache_home/shibumi ]] \
    || fail 'suite cache remains after uninstall'
  if find "$config_home/omarchy/plugins" -mindepth 1 -maxdepth 1 \
      -name 'hancore.shibumi.*' -print -quit 2>/dev/null | grep -q .; then
    fail 'Shibumi plugin entry remains after uninstall'
  fi
  config="$config_home/omarchy/shell.json"
  jq -e '
    (.bar.id // "omarchy.bar") == "omarchy.bar" and
    all(.plugins[]?; (.id // "") | startswith("hancore.shibumi.") | not) and
    all((.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?);
        ((.id // .) | startswith("hancore.shibumi.") | not))
  ' "$config" >/dev/null || fail 'uninstall did not restore a Shibumi-free config'
  if find "$config_home/omarchy/plugins" -mindepth 1 -maxdepth 1 \
      -name '.shibumi-*' -print -quit 2>/dev/null | grep -q .; then
    fail 'hidden lifecycle artifacts remain after uninstall'
  fi
  [[ $(shell_ipc shell ping) == ok ]] || fail 'stock shell did not survive uninstall'
}

drain_fixture_shells() {
  timeout --kill-after=1s 8s env \
    SHIBUMI_TEST_SERVICE_FILE="$service_file" \
    SHIBUMI_TEST_CLEANUP_LOG="$cleanup_log" \
    SHIBUMI_TEST_SERVICE_PREFIX="$service_prefix" "$stop_shells"
}

gate_started=$SECONDS
# Arm 1: package update
assert_empty_directory "$update_home"
mkdir -p "$update_config_home" "$update_state_home" "$update_cache_home"
for empty_path in "$update_config_home" "$update_state_home" \
    "$update_cache_home"; do
  assert_empty_directory "$empty_path"
done
update_started=$SECONDS
update_generation_start=$(service_generation_count)
set_arm_environment update "$update_home" "$update_config_home" \
  "$update_state_home" "$update_cache_home"
source_root="$predecessor_root"
start_stock_shell

suite_cli install --yes || fail 'Beta.13 package install command failed'
assert_package_install_state "$predecessor_root" '0.1.1-beta.13'
update_predecessor_digest=$(jq -r '.payloadDigest // empty' "$state_file")
[[ $update_predecessor_digest =~ ^[0-9a-f]{64}$ ]] \
  || fail 'Beta.13 package payload digest is invalid'
update_predecessor_reply=$(shell_ipc shibumi-suite-runtime verifyPayload \
  "$update_predecessor_digest") \
  || fail 'installed Beta.13 state service payload query failed'
[[ $update_predecessor_reply == ok ]] \
  || fail 'installed Beta.13 state service did not confirm its payload digest'
suite_cli status >/dev/null || fail 'installed Beta.13 package status is not clean'

source_root="$candidate_root"
suite_cli update --yes || fail 'candidate package update command failed'
assert_package_install_state "$candidate_root" '0.1.1-beta.14.1'
update_candidate_digest=$(jq -r '.payloadDigest // empty' "$state_file")
[[ $update_candidate_digest =~ ^[0-9a-f]{64}$ \
    && $update_candidate_digest != "$update_predecessor_digest" ]] \
  || fail 'package update did not advance the payload identity'
update_candidate_reply=$(shell_ipc shibumi-suite-runtime verifyPayload \
  "$update_candidate_digest") \
  || fail 'updated candidate state service payload query failed'
[[ $update_candidate_reply == ok ]] \
  || fail 'updated candidate state service did not confirm its payload digest'
suite_cli status >/dev/null || fail 'updated candidate package status is not clean'

suite_cli deactivate --keep-layout --yes \
  || fail 'updated suite external-bar transition failed'
config="$config_home/omarchy/shell.json"
jq -e '(.bar.id // "omarchy.bar") == "omarchy.bar"' "$config" >/dev/null \
  || fail 'external-bar transition did not activate the stock bar'
update_deactivated_reply=$(shell_ipc shibumi-suite-runtime verifyPayload \
  "$update_candidate_digest") \
  || fail 'deactivated candidate state service payload query failed'
[[ $update_deactivated_reply == ok ]] \
  || fail 'state service endpoint was lost under the stock bar'
suite_cli status >/dev/null || fail 'external candidate package status is not clean'

suite_cli uninstall --yes || fail 'updated suite uninstall command failed'
assert_uninstalled_arm
drain_fixture_shells || fail 'update-arm fixture shell service drain failed'
[[ ! -s $cleanup_log ]] \
  || fail 'normal update-arm cleanup unexpectedly required KILL'
update_generations=$(( $(service_generation_count) - update_generation_start ))
update_elapsed=$(( SECONDS - update_started ))

# Arm 2: fresh install
assert_empty_directory "$fresh_home"
mkdir -p "$fresh_config_home" "$fresh_state_home" "$fresh_cache_home"
for empty_path in "$fresh_config_home" "$fresh_state_home" \
    "$fresh_cache_home"; do
  assert_empty_directory "$empty_path"
done
[[ ! -e $fresh_config_home/omarchy/shell.json \
    && ! -e $fresh_config_home/omarchy/plugins \
    && ! -e $fresh_state_home/shibumi \
    && ! -e $fresh_cache_home/shibumi ]] \
  || fail 'fresh arm unexpectedly contains an active Shibumi host state'
fresh_preflight=empty

fresh_started=$SECONDS
fresh_generation_start=$(service_generation_count)
set_arm_environment fresh "$fresh_home" "$fresh_config_home" \
  "$fresh_state_home" "$fresh_cache_home"
source_root="$candidate_root"
start_stock_shell
suite_cli install --yes || fail 'fresh candidate package install command failed'
assert_package_install_state "$candidate_root" '0.1.1-beta.14.1'
fresh_digest=$(jq -r '.payloadDigest // empty' "$state_file")
[[ $fresh_digest =~ ^[0-9a-f]{64}$ ]] \
  || fail 'fresh candidate package payload digest is invalid'
fresh_reply=$(shell_ipc shibumi-suite-runtime verifyPayload "$fresh_digest") \
  || fail 'fresh candidate state service payload query failed'
[[ $fresh_reply == ok ]] \
  || fail 'fresh candidate state service did not confirm its payload digest'
suite_cli status >/dev/null || fail 'fresh candidate package status is not clean'
suite_cli deactivate --keep-layout --yes \
  || fail 'fresh suite external-bar transition failed'
config="$config_home/omarchy/shell.json"
jq -e '(.bar.id // "omarchy.bar") == "omarchy.bar"' "$config" >/dev/null \
  || fail 'fresh external-bar transition did not activate the stock bar'
fresh_deactivated_reply=$(shell_ipc shibumi-suite-runtime verifyPayload \
  "$fresh_digest") \
  || fail 'fresh deactivated candidate state service payload query failed'
[[ $fresh_deactivated_reply == ok ]] \
  || fail 'fresh state service endpoint was lost under the stock bar'
suite_cli status >/dev/null \
  || fail 'fresh external candidate package status is not clean'
suite_cli uninstall --yes || fail 'fresh candidate suite uninstall command failed'
assert_uninstalled_arm
drain_fixture_shells || fail 'final fixture shell service drain failed'
[[ ! -s $cleanup_log ]] \
  || fail 'normal fresh-arm cleanup unexpectedly required KILL'
fresh_generations=$(( $(service_generation_count) - fresh_generation_start ))
fresh_elapsed=$(( SECONDS - fresh_started ))

if grep -Eq \
    'hancore\.shibumi[^ ]*.*(Binding loop|TypeError|ReferenceError|is not a type|failed to load)|plugin hancore\.shibumi.*failed|bar option hancore\.shibumi.*failed' \
    "$tmpdir/quickshell.log"; then
  fail 'runtime log contains a QML or plugin-load failure'
fi
normal_cleanup_records=none

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
drain_fixture_shells || fail 'TERM-resistant cleanup probe drain failed'
probe_cleanup_record="KILL $cleanup_probe"
[[ $(wc -l <"$cleanup_log") -eq 1 \
    && $(<"$cleanup_log") == "$probe_cleanup_record" ]] \
  || fail 'cleanup probe did not produce exactly its owned KILL record'
total_elapsed=$(( SECONDS - gate_started ))

printf 'Update arm verifyPayload: beta13=%s candidate=%s deactivated=%s\n' \
  "$update_predecessor_reply" "$update_candidate_reply" "$update_deactivated_reply"
printf 'Update arm timing/generations: %ss/%s\n' \
  "$update_elapsed" "$update_generations"
printf 'Fresh arm preflight/verifyPayload: %s/%s deactivated=%s\n' \
  "$fresh_preflight" "$fresh_reply" "$fresh_deactivated_reply"
printf 'Fresh arm timing/generations: %ss/%s\n' \
  "$fresh_elapsed" "$fresh_generations"
printf 'Cleanup evidence: normal=%s; deliberate-probe=%s; fixture-services=inactive\n' \
  "$normal_cleanup_records" "$probe_cleanup_record"
printf 'Candidate revision: %s; total elapsed: %ss\n' \
  "$candidate_revision" "$total_elapsed"
printf 'Shibumi suite Quattro runtime passed\n'
