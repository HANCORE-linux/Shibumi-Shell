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
  elif [[ -n $tmpdir ]]; then
    if ! rm -rf -- "$tmpdir" \
        || [[ -e $tmpdir || -L $tmpdir ]]; then
      printf 'Runtime fixture temporary directory cleanup failed: %s\n' \
        "$tmpdir" >&2
      failed=1
      status=1
    fi
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
[[ -n ${WAYLAND_DISPLAY:-} && -n ${XDG_RUNTIME_DIR:-} \
    && -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] \
  || fail 'a running Wayland user session with a session bus is required'

fixture_wayland_display=$WAYLAND_DISPLAY
[[ $fixture_wayland_display == /* ]] \
  || fixture_wayland_display="$XDG_RUNTIME_DIR/$fixture_wayland_display"
tmpdir=$(mktemp -d /tmp/shibumi-suite-runtime.XXXXXX)
fixture_runtime_dir="$tmpdir/runtime"
mkdir -m 0700 "$fixture_runtime_dir"
fresh_home="$tmpdir/fresh-home"
fresh_config_home="$fresh_home/.config"
fresh_state_home="$fresh_home/.local/state"
fresh_cache_home="$fresh_home/.cache"
package_predecessor_root="$tmpdir/predecessor-package"
package_candidate_root="$tmpdir/candidate-package"
source_predecessor_root="$tmpdir/predecessor-source"
source_beta15_root="$tmpdir/beta15-source"
source_candidate_root="$tmpdir/candidate-source"
source_root=""
stub_bin="$tmpdir/bin"
fixture_omarchy="$tmpdir/omarchy"
mkdir -p "$fresh_home" "$package_predecessor_root" \
  "$package_candidate_root" "$stub_bin" "$fixture_omarchy"
package_predecessor_revision=2760cdb8272255790d5e4613fed8a48cb63c3555
# Published beta.14.1; lift to the next tag at release pin.
package_candidate_revision=7a6c853b1947d303bad9a5b640c224c01b669106
# Exercise the current installed checkout's published beta.15.2 tag.
source_predecessor_revision=c45af77c8333b691ac36522247b6e5b5481a3666
# Also cover the original documented update path that beta.15.2 rejected.
source_beta15_revision=4e91c26ebf4da07476d4be6176f29d7662fed9c1
# Only committed payload is tested; uncommitted plugin changes are invisible to this gate.
candidate_revision=$(git --no-replace-objects -C "$repo_root" rev-parse HEAD)
[[ $candidate_revision =~ ^[0-9a-f]{40}$ ]] \
  || fail 'candidate HEAD did not resolve to a full commit identity'
[[ $package_predecessor_revision != "$package_candidate_revision" ]] \
  || fail 'package predecessor and candidate revisions must differ'
[[ $source_predecessor_revision != "$candidate_revision" \
    && $source_beta15_revision != "$candidate_revision" ]] \
  || fail 'source predecessors and candidate revisions must differ'

for source_spec in \
    "$source_predecessor_root:$source_predecessor_revision" \
    "$source_beta15_root:$source_beta15_revision" \
    "$source_candidate_root:$candidate_revision"; do
  checkout_root=${source_spec%%:*}
  checkout_revision=${source_spec#*:}
  git -c core.hooksPath=/dev/null clone --quiet --shared --no-checkout -- \
    "$repo_root" "$checkout_root" \
    || fail "could not create isolated source checkout: $checkout_root"
  git -c core.hooksPath=/dev/null -C "$checkout_root" checkout --quiet \
    --detach "$checkout_revision" \
    || fail "could not detach isolated source checkout: $checkout_root"
  [[ -d $checkout_root && ! -L $checkout_root \
      && -d $checkout_root/.git && ! -L $checkout_root/.git ]] \
    || fail "source fixture root is not an isolated Git checkout: $checkout_root"
  [[ $(git --no-replace-objects -C "$checkout_root" rev-parse HEAD) \
      == "$checkout_revision" \
      && -z $(git -C "$checkout_root" status --porcelain=v1 \
        --untracked-files=all) ]] \
    || fail "source fixture checkout identity is invalid: $checkout_root"
  [[ ! -e $checkout_root/PACKAGE-METADATA.json \
      && ! -L $checkout_root/PACKAGE-METADATA.json ]] \
    || fail "source fixture exposes projected package identity: $checkout_root"
done

# Package fixtures mirror the root metadata projection performed by PKGBUILD:62.
git --no-replace-objects -C "$repo_root" archive "$package_predecessor_revision" \
  | tar -x -C "$package_predecessor_root"
git --no-replace-objects -C "$repo_root" archive "$package_candidate_revision" \
  | tar -x -C "$package_candidate_root"
for package_root in "$package_predecessor_root" "$package_candidate_root"; do
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

validate_package_identity "$package_predecessor_root" '0.1.1-beta.13'
validate_package_identity "$package_candidate_root" '0.1.1-beta.14.1'

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
  if [[ ! $unit =~ ^${SHIBUMI_TEST_SERVICE_PREFIX}-([1-9]|1[0-9]|2[0-5])\.service$ \
      && $unit != "$SHIBUMI_TEST_SERVICE_PREFIX-cleanup-probe.service" ]]; then
    printf 'refusing foreign fixture service: %s\n' "$unit" >&2
    exit 1
  fi
done
unit_state() {
  timeout --kill-after=0.2s 0.8s systemctl --user --machine=@.host show "$1" \
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
  timeout --kill-after=0.2s 0.8s systemctl --user --machine=@.host kill \
    --kill-whom=all --signal=TERM "$unit" >/dev/null 2>&1 || true
  timeout --kill-after=0.2s 0.8s systemctl --user --machine=@.host stop "$unit" \
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
    timeout --kill-after=0.2s 0.8s systemctl --user --machine=@.host kill \
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
  [[ $existing =~ ^${SHIBUMI_TEST_SERVICE_PREFIX}-([1-9]|1[0-9]|2[0-5])\.service$ ]] \
    || exit 1
done
# package update (5) + fresh round trip (6) + two source round trips (7 each) = 25 shells.
(( ${#units[@]} < 25 )) || {
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
  --setenv="DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
  --setenv="SHIBUMI_LOCK_FILE=$SHIBUMI_LOCK_FILE"
  --setenv="OMARCHY_PATH=$OMARCHY_PATH"
  --setenv="PATH=$PATH"
  --setenv="SHIBUMI_TEST_SHELL_LOG=$SHIBUMI_TEST_SHELL_LOG"
)
[[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
  || environment+=(--setenv="HYPRLAND_INSTANCE_SIGNATURE=$HYPRLAND_INSTANCE_SIGNATURE")
timeout --kill-after=1s 8s systemd-run --user --machine=@.host --quiet --collect \
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
    XDG_RUNTIME_DIR="$fixture_runtime_dir"
    WAYLAND_DISPLAY="$fixture_wayland_display"
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
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
    [[ $(timeout --kill-after=0.2s 0.8s systemctl --user --machine=@.host show \
        "$shell_unit" -p ActiveState --value 2>/dev/null) == active ]] \
      || fail 'stock Quattro shell exited before IPC became ready'
    sleep 0.1
  done
  [[ $shell_ready -eq 1 ]] || fail 'stock Quattro shell did not become ready'
}

assert_install_state() {
  local expected_root=$1
  local expected_version=$2
  local expected_origin=$3
  local expected_revision=$4
  local marker_count=0
  state_file="$state_home/shibumi/install.json"
  [[ -f $state_file && ! -L $state_file ]] || fail 'install state is missing'
  jq -e --arg root "$expected_root" --arg version "$expected_version" \
    --arg origin "$expected_origin" --arg revision "$expected_revision" '
      .suiteVersion == $version and
      .installOrigin == $origin and
      .payloadRoot == $root and
      .sourceRevision == $revision and
      (.plugins | length) == 24
    ' "$state_file" >/dev/null \
    || fail "installed $expected_origin authority is invalid for $expected_revision"
  case $expected_origin in
    package)
      jq -e --arg version "$expected_version" '
        .packageName == "shibumi-shell" and
        .packageVersion == $version and
        (has("sourceRoot") | not)
      ' "$state_file" >/dev/null \
        || fail "installed package identity is invalid for $expected_version"
      ;;
    checkout)
      jq -e --arg root "$expected_root" '
        .sourceRoot == $root and
        (has("packageName") | not) and
        (has("packageVersion") | not)
      ' "$state_file" >/dev/null \
        || fail "installed checkout identity is invalid for $expected_revision"
      ;;
    *) fail "unsupported fixture install origin: $expected_origin" ;;
  esac
  while IFS= read -r marker; do
    ((marker_count += 1))
    jq -e --arg version "$expected_version" --arg revision "$expected_revision" '
      .suiteVersion == $version and .sourceRevision == $revision
    ' "$marker" >/dev/null \
      || fail "managed marker $expected_origin authority is invalid: $marker"
  done < <(find "$config_home/omarchy/plugins" -mindepth 2 -maxdepth 2 \
    -name .shibumi-managed.json -type f -print)
  (( marker_count == 24 )) \
    || fail "installed $expected_origin has $marker_count managed markers instead of 24"
}

prepare_foreign_widget_fixture() {
  # Private fixture HOME only, before its first shell starts.
  local directory="$config_home/omarchy/plugins/fixture.kept-widget"
  mkdir -p "$directory"
  jq -n '{schemaVersion:1, id:"fixture.kept-widget", name:"Retention fixture", version:"1.0.0",
    kinds:["bar-widget"], entryPoints:{barWidget:"Widget.qml"},
    barWidget:{defaultSection:"left", allowMultiple:false}}' >"$directory/manifest.json"
  printf 'import QtQuick\nItem { implicitWidth: 1; implicitHeight: 1 }\n' >"$directory/Widget.qml"
  jq '.bar.layout.left += [{id:"fixture.kept-widget", opaque:{keep:[1,false]}}]' \
    "$fixture_omarchy/config/omarchy/shell.json" >"$config_home/omarchy/shell.json"
}

assert_host_layout_preserved() {
  local expected=$1 phase=$2 observed
  observed=$(jq -ceS '.bar.layout' "$config_home/omarchy/shell.json") \
    || fail "$phase host layout file is invalid"
  [[ $observed == "$expected" ]] || fail "$phase changed the complete host layout"
  observed=$(shell_ipc shell listShellConfig | jq -ceS '.bar.layout') \
    || fail "$phase live host layout is invalid"
  [[ $observed == "$expected" ]] || fail "$phase live host layout differs from snapshot"
}

state_settings_snapshot() {
  # Preserve the complete service-entry envelope, not only the changed setting.
  jq -ceS '
    [.plugins[]? | select(. == "hancore.shibumi.state" or
      (type == "object" and .id == "hancore.shibumi.state"))] |
    if length == 1 and (.[0] | type) == "object" and
        .[0].shibumiStateSchemaVersion == 1 and
        (.[0].shibumi | type) == "object" and .[0].shibumi.version == 1
    then .[0] else error("expected one canonical State settings entry") end
  ' "$@"
}

assert_settings_preserved() {
  local expected=$1 phase=$2 observed
  observed=$(state_settings_snapshot "$config_home/omarchy/shell.json" 2>/dev/null) \
    || fail "$phase canonical State settings are missing or invalid"
  [[ $observed == "$expected" ]] \
    || fail "$phase changed the complete State settings entry"
  observed=$(shell_ipc shell listShellConfig | state_settings_snapshot 2>/dev/null) \
    || fail "$phase live State settings are missing or invalid"
  [[ $observed == "$expected" ]] \
    || fail "$phase live State settings differ from file snapshot"
}

assert_uninstalled_arm() {
  local retained_settings=${1:-} keep_settings=false
  [[ -z $retained_settings ]] || keep_settings=true
  [[ ! -e $state_home/shibumi && ! -L $state_home/shibumi ]] \
    || fail 'suite state remains after uninstall'
  [[ ! -e $cache_home/shibumi && ! -L $cache_home/shibumi ]] \
    || fail 'suite cache remains after uninstall'
  if find "$config_home/omarchy/plugins" -mindepth 1 -maxdepth 1 \
      -name 'hancore.shibumi.*' -print -quit 2>/dev/null | grep -q .; then
    fail 'Shibumi plugin entry remains after uninstall'
  fi
  config="$config_home/omarchy/shell.json"
  jq -e --argjson keep_settings "$keep_settings" '
    def entry_id: if type == "string" then . else (.id // "") end;
    (.bar.id // "omarchy.bar") == "omarchy.bar" and
    all(.plugins[]?; entry_id as $id |
      ($keep_settings and $id == "hancore.shibumi.state") or
      ($id | startswith("hancore.shibumi.") | not)) and
    all((.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?);
        (entry_id | startswith("hancore.shibumi.") | not))
  ' "$config" >/dev/null || fail 'uninstall did not restore a Shibumi-free config'
  if find "$config_home/omarchy/plugins" -mindepth 1 -maxdepth 1 \
      -name '.shibumi-*' -print -quit 2>/dev/null | grep -q .; then
    fail 'hidden lifecycle artifacts remain after uninstall'
  fi
  [[ $(shell_ipc shell ping) == ok ]] || fail 'stock shell did not survive uninstall'
  shell_ipc shell listShellConfig \
    | jq -e '(.bar.id // "omarchy.bar") == "omarchy.bar"' >/dev/null \
    || fail 'live shell did not restore the stock bar'
  if [[ -n $retained_settings ]]; then
    assert_settings_preserved "$retained_settings" 'keep-settings uninstall'
  fi
}

run_keep_settings_cycle() {
  local arm=$1 version=$2 origin=$3 revision=$4 digest=$5
  local snapshot retained_snapshot live_snapshot reply settled=false settle_attempt layout_snapshot style
  case $arm in
    fresh) style=shibumi ;; # V1: foreign widget remains in the Extra-Deck, without a V1 slot.
    source-beta15) style=full ;;
    source-beta152) style=notch ;;
    *) fail "unexpected keep-settings arm: $arm" ;;
  esac
  # Supported native and State IPC only once the fixture shell is running.
  [[ $(shell_ipc shell moveBarWidget fixture.kept-widget '{"section":"right"}') == ok ]] \
    || fail "$arm foreign widget move failed"
  if [[ $(state_settings_snapshot "$config_home/omarchy/shell.json" |
      jq -r '.shibumi.presentation.shellStyle // "shibumi"') != "$style" ]]; then
    [[ $(shell_ipc shibumi-suite setBarAppearance shellStyle "\"$style\"") == ok ]] \
      || fail "$arm style setup failed"
  fi
  snapshot=$(state_settings_snapshot "$config_home/omarchy/shell.json") \
    || fail "$arm initial State settings are missing or invalid"
  [[ $(jq -r '.shibumi.presentation.accent // empty' <<<"$snapshot") != color06 ]] \
    || fail "$arm settings sentinel is already present before IPC"
  # Supported Bar -> State -> native own-entry write; no shell.json edits.
  # The default accent is color01; an IPC 'ok' only acknowledges a queued write.
  reply=$(shell_ipc shibumi-suite setBarAppearance accent '"color06"') \
    || fail "$arm settings IPC command failed"
  [[ $reply == ok ]] || fail "$arm settings IPC request was not accepted"
  for settle_attempt in {1..100}; do
    snapshot=$(state_settings_snapshot "$config_home/omarchy/shell.json") \
      || fail "$arm settings readback is invalid"
    if jq -e --arg style "$style" '
      .shibumi.presentation.accent == "color06" and
      (.shibumi.presentation.shellStyle // "shibumi") == $style and
      (if $style == "shibumi" then
        ([.shibumi.order.left[]?, .shibumi.order.center[]?, .shibumi.order.right[]?] |
         index("G:fixture.kept-widget")) == null
       else ((.shibumi.v2Layout.right // []) | index("G:fixture.kept-widget")) != null end)
    ' <<<"$snapshot" >/dev/null; then
      live_snapshot=$(shell_ipc shell listShellConfig | state_settings_snapshot) \
        || fail "$arm live settings readback is invalid"
      if [[ $live_snapshot == "$snapshot" ]]; then
        settled=true
        break
      fi
    fi
    sleep 0.1
  done
  [[ $settled == true ]] || fail "$arm settings IPC write did not settle on disk and in the live shell"

  jq -e 'any(.bar.layout.right[]; .id == "fixture.kept-widget")' \
    "$config_home/omarchy/shell.json" >/dev/null || fail "$arm foreign widget did not move right"
  layout_snapshot=$(jq -ceS '.bar.layout' "$config_home/omarchy/shell.json")
  retained_snapshot=$(jq -ceS --argjson layout "$layout_snapshot" \
    '. + {shibumiRetainedLayout:{schemaVersion:1, layout:$layout}}' <<<"$snapshot")
  suite_cli uninstall --keep-settings --yes \
    || fail "$arm keep-settings uninstall command failed"
  assert_uninstalled_arm "$retained_snapshot"
  suite_cli install --yes || fail "$arm candidate reinstall command failed"
  assert_install_state "$source_root" "$version" "$origin" "$revision"
  reply=$(shell_ipc shibumi-suite-runtime verifyPayload "$digest") \
    || fail "$arm reinstalled state service payload query failed"
  [[ $reply == ok ]] || fail "$arm reinstalled state service did not confirm its payload digest"
  assert_settings_preserved "$snapshot" "$arm reinstall"
  assert_host_layout_preserved "$layout_snapshot" "$arm reinstall"
  [[ $(shell_ipc shell reloadConfig) == ok ]] || fail "$arm config reload failed"
  sleep 5
  assert_settings_preserved "$snapshot" "$arm settled reinstall"
  assert_host_layout_preserved "$layout_snapshot" "$arm settled reinstall"
  printf '%s layout retention: host=identical State=identical style=%s settle-delay=5s\n' "$arm" "$style"
  suite_cli status >/dev/null || fail "$arm reinstalled candidate status is not clean"
  printf '%s keep-settings/reinstall: retained=entry+layout-record reinstalled=identical verifyPayload=%s settle-polls=%s/100 poll-interval=0.1s\n' \
    "$arm" "$reply" "$settle_attempt"
}

drain_fixture_shells() {
  timeout --kill-after=1s 8s env \
    SHIBUMI_TEST_SERVICE_FILE="$service_file" \
    SHIBUMI_TEST_CLEANUP_LOG="$cleanup_log" \
    SHIBUMI_TEST_SERVICE_PREFIX="$service_prefix" "$stop_shells"
}

declare -A arm_predecessor_reply arm_candidate_reply arm_deactivated_reply
declare -A arm_generations arm_elapsed

run_update_arm() {
  local predecessor_src=$1
  local candidate_src=$2
  local origin=$3
  local arm predecessor_version predecessor_identity candidate_version
  local candidate_identity arm_home arm_config_home arm_state_home arm_cache_home
  local predecessor_digest candidate_digest generation_start started expected_generations=5
  case $origin in
    package)
      arm=package
      predecessor_version=0.1.1-beta.13
      predecessor_identity="package:$predecessor_version"
      candidate_version=0.1.1-beta.14.1
      candidate_identity="package:$candidate_version"
      ;;
    checkout)
      arm=$4
      predecessor_version=$5
      predecessor_identity=$6
      candidate_version=$(<"$repo_root/VERSION")
      candidate_identity=$candidate_revision
      ;;
    *) fail "unsupported update-arm origin: $origin" ;;
  esac
  arm_home="$tmpdir/$arm-home"
  arm_config_home="$arm_home/.config"
  arm_state_home="$arm_home/.local/state"
  arm_cache_home="$arm_home/.cache"
  [[ ! -e $arm_home && ! -L $arm_home ]] \
    || fail "update fixture path already exists: $arm_home"
  mkdir -p "$arm_home"
  assert_empty_directory "$arm_home"
  mkdir -p "$arm_config_home" "$arm_state_home" "$arm_cache_home"
  for empty_path in "$arm_config_home" "$arm_state_home" "$arm_cache_home"; do
    assert_empty_directory "$empty_path"
  done

  started=$SECONDS
  generation_start=$(service_generation_count)
  set_arm_environment "$arm" "$arm_home" "$arm_config_home" \
    "$arm_state_home" "$arm_cache_home"
  source_root=$predecessor_src
  if [[ $origin == checkout ]]; then prepare_foreign_widget_fixture; fi
  printf 'Update arm %s: %s (%s) -> %s (%s)\n' \
    "$arm" "$predecessor_version" "$predecessor_identity" \
    "$candidate_version" "$candidate_identity"
  start_stock_shell

  suite_cli install --yes || fail "$arm predecessor install command failed"
  assert_install_state "$predecessor_src" "$predecessor_version" "$origin" \
    "$predecessor_identity"
  predecessor_digest=$(jq -r '.payloadDigest // empty' "$state_file")
  [[ $predecessor_digest =~ ^[0-9a-f]{64}$ ]] \
    || fail "$arm predecessor payload digest is invalid"
  arm_predecessor_reply[$arm]=$(shell_ipc shibumi-suite-runtime verifyPayload \
    "$predecessor_digest") \
    || fail "$arm predecessor state service payload query failed"
  [[ ${arm_predecessor_reply[$arm]} == ok ]] \
    || fail "$arm predecessor state service did not confirm its payload digest"
  suite_cli status >/dev/null || fail "$arm predecessor status is not clean"

  source_root=$candidate_src
  suite_cli update --yes || fail "$arm candidate update command failed"
  assert_install_state "$candidate_src" "$candidate_version" "$origin" \
    "$candidate_identity"
  candidate_digest=$(jq -r '.payloadDigest // empty' "$state_file")
  [[ $candidate_digest =~ ^[0-9a-f]{64}$ ]] \
    || fail "$arm candidate payload digest is invalid"
  if [[ $origin == package && $candidate_digest == "$predecessor_digest" ]]; then
    fail 'package update did not advance the payload identity'
  fi
  arm_candidate_reply[$arm]=$(shell_ipc shibumi-suite-runtime verifyPayload \
    "$candidate_digest") \
    || fail "$arm candidate state service payload query failed"
  [[ ${arm_candidate_reply[$arm]} == ok ]] \
    || fail "$arm candidate state service did not confirm its payload digest"
  suite_cli status >/dev/null || fail "$arm candidate status is not clean"

  # The historical package arm stays beta.13 -> beta.14.1, not the 15.3 candidate.
  if [[ $origin == checkout ]]; then
    run_keep_settings_cycle "$arm" "$candidate_version" "$origin" \
      "$candidate_identity" "$candidate_digest"
    expected_generations=7
  fi

  suite_cli deactivate --keep-layout --yes \
    || fail "$arm external-bar transition failed"
  config="$config_home/omarchy/shell.json"
  jq -e '(.bar.id // "omarchy.bar") == "omarchy.bar"' "$config" >/dev/null \
    || fail "$arm external-bar transition did not activate the stock bar"
  arm_deactivated_reply[$arm]=$(shell_ipc shibumi-suite-runtime verifyPayload \
    "$candidate_digest") \
    || fail "$arm deactivated state service payload query failed"
  [[ ${arm_deactivated_reply[$arm]} == ok ]] \
    || fail "$arm state service endpoint was lost under the stock bar"
  suite_cli status >/dev/null \
    || fail "$arm external candidate status is not clean"

  suite_cli uninstall --yes || fail "$arm suite uninstall command failed"
  assert_uninstalled_arm
  drain_fixture_shells || fail "$arm fixture shell service drain failed"
  [[ ! -s $cleanup_log ]] \
    || fail "normal $arm cleanup unexpectedly required KILL"
  arm_generations[$arm]=$(( $(service_generation_count) - generation_start ))
  [[ ${arm_generations[$arm]} -eq $expected_generations ]] \
    || fail "$arm arm used ${arm_generations[$arm]} shell generations instead of $expected_generations"
  arm_elapsed[$arm]=$(( SECONDS - started ))
}

gate_started=$SECONDS
# Arm 1: package update
run_update_arm "$package_predecessor_root" "$package_candidate_root" package

# Arm 2: fresh source checkout install
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
source_root="$source_candidate_root"
prepare_foreign_widget_fixture
start_stock_shell
suite_cli install --yes || fail 'fresh candidate source checkout install command failed'
assert_install_state "$source_candidate_root" "$(<"$repo_root/VERSION")" checkout \
  "$candidate_revision"
fresh_digest=$(jq -r '.payloadDigest // empty' "$state_file")
[[ $fresh_digest =~ ^[0-9a-f]{64}$ ]] \
  || fail 'fresh candidate source checkout payload digest is invalid'
fresh_reply=$(shell_ipc shibumi-suite-runtime verifyPayload "$fresh_digest") \
  || fail 'fresh candidate state service payload query failed'
[[ $fresh_reply == ok ]] \
  || fail 'fresh candidate state service did not confirm its payload digest'
suite_cli status >/dev/null \
  || fail 'fresh candidate source checkout status is not clean'
run_keep_settings_cycle fresh "$(<"$repo_root/VERSION")" checkout \
  "$candidate_revision" "$fresh_digest"
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
  || fail 'fresh external candidate source checkout status is not clean'
suite_cli uninstall --yes || fail 'fresh candidate suite uninstall command failed'
assert_uninstalled_arm
drain_fixture_shells || fail 'final fixture shell service drain failed'
[[ ! -s $cleanup_log ]] \
  || fail 'normal fresh-arm cleanup unexpectedly required KILL'
fresh_generations=$(( $(service_generation_count) - fresh_generation_start ))
[[ $fresh_generations -eq 6 ]] \
  || fail "fresh arm used $fresh_generations shell generations instead of 6"
fresh_elapsed=$(( SECONDS - fresh_started ))

# Arm 3: beta.15 source checkout update
run_update_arm "$source_beta15_root" "$source_candidate_root" checkout \
  source-beta15 0.1.1-beta.15 "$source_beta15_revision"
# Arm 4: beta.15.2 source checkout update
run_update_arm "$source_predecessor_root" "$source_candidate_root" checkout \
  source-beta152 0.1.1-beta.15.2 "$source_predecessor_revision"
[[ $(service_generation_count) -eq 25 ]] \
  || fail 'runtime arms did not use the exact 25-shell generation budget'

if grep -Eq \
    'hancore\.shibumi[^ ]*.*(Binding loop|TypeError|ReferenceError|is not a type|failed to load)|plugin hancore\.shibumi.*failed|bar option hancore\.shibumi.*failed' \
    "$tmpdir/quickshell.log"; then
  fail 'runtime log contains a QML or plugin-load failure'
fi
normal_cleanup_records=none

cleanup_probe="$service_prefix-cleanup-probe.service"
printf '%s\n' "$cleanup_probe" >>"$service_file"
timeout --kill-after=1s 8s systemd-run --user --machine=@.host --quiet --collect \
  --unit="$cleanup_probe" --service-type=exec \
  --property=KillMode=control-group \
  --property=TimeoutStopSec=30s /usr/bin/bash -c \
  'trap "" TERM; while :; do sleep 1; done' \
  || fail 'TERM-resistant cleanup probe did not start'
[[ $(timeout --kill-after=0.2s 0.8s systemctl --user --machine=@.host show \
    "$cleanup_probe" -p ActiveState --value 2>/dev/null) == active ]] \
  || fail 'TERM-resistant cleanup probe is not active'
cleanup_probe_armed=1
drain_fixture_shells || fail 'TERM-resistant cleanup probe drain failed'
probe_cleanup_record="KILL $cleanup_probe"
[[ $(wc -l <"$cleanup_log") -eq 1 \
    && $(<"$cleanup_log") == "$probe_cleanup_record" ]] \
  || fail 'cleanup probe did not produce exactly its owned KILL record'
total_elapsed=$(( SECONDS - gate_started ))

printf 'Package update arm verifyPayload: predecessor=%s candidate=%s deactivated=%s\n' \
  "${arm_predecessor_reply[package]}" "${arm_candidate_reply[package]}" \
  "${arm_deactivated_reply[package]}"
printf 'Package update arm timing/generations: %ss/%s\n' \
  "${arm_elapsed[package]}" "${arm_generations[package]}"
printf 'Fresh arm preflight/verifyPayload: %s/%s deactivated=%s\n' \
  "$fresh_preflight" "$fresh_reply" "$fresh_deactivated_reply"
printf 'Fresh arm timing/generations: %ss/%s\n' \
  "$fresh_elapsed" "$fresh_generations"
for arm in source-beta15 source-beta152; do
  printf '%s update arm verifyPayload: predecessor=%s candidate=%s deactivated=%s\n' \
    "$arm" "${arm_predecessor_reply[$arm]}" "${arm_candidate_reply[$arm]}" \
    "${arm_deactivated_reply[$arm]}"
  printf '%s update arm timing/generations: %ss/%s\n' \
    "$arm" "${arm_elapsed[$arm]}" "${arm_generations[$arm]}"
done
printf 'Cleanup evidence: normal=%s; deliberate-probe=%s; fixture-services=inactive\n' \
  "$normal_cleanup_records" "$probe_cleanup_record"
printf 'Package revisions: predecessor=%s candidate=%s\n' \
  "$package_predecessor_revision" "$package_candidate_revision"
printf 'Source revisions: beta.15=%s beta.15.2=%s candidate=%s; total elapsed: %ss\n' \
  "$source_beta15_revision" "$source_predecessor_revision" \
  "$candidate_revision" "$total_elapsed"
printf 'Shibumi suite Quattro runtime passed\n'
