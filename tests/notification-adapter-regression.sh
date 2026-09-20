#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-notification-adapter.XXXXXX)
fixture_pid=

stop_fixture() {
  [[ -z ${fixture_pid:-} ]] && return 0
  if kill -0 -- "-$fixture_pid" 2>/dev/null; then
    kill -TERM -- "-$fixture_pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 -- "-$fixture_pid" 2>/dev/null || break
      sleep 0.05
    done
    kill -KILL -- "-$fixture_pid" 2>/dev/null || true
  fi
  wait "$fixture_pid" 2>/dev/null || true
  fixture_pid=
}
trap 'stop_fixture; rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'notification adapter regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell/Commons ]] || fail "Omarchy Commons not found"
[[ -d $omarchy_path/shell/Ui ]] || fail "Omarchy Ui not found"
[[ -x $quickshell_bin ]] || fail "Quickshell not found"
command -v setsid >/dev/null 2>&1 || fail "setsid not found"

mkdir -p "$tmpdir/status"
cp -a -- "$repo_root/hancore.shibumi.status/." "$tmpdir/status/"
shibumi_stage_suite_runtime "$repo_root" "$tmpdir"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
cp -- "$repo_root/tests/notification-adapter-smoke.qml" "$tmpdir/shell.qml"

run_case() {
  local name=$1 expected=$2 history_mode=$3
  local marker=${4:-notification adapter smoke passed}
  local race=${5:-} path=/usr/bin:/bin
  local root="$tmpdir/$name" output="$tmpdir/$name.log"
  mkdir -p "$root"/{home,config,cache,state,data,runtime,tmp,pipewire}
  chmod 700 "$root/runtime"
  if [[ -n $race ]]; then
    mkdir "$root/bin"
    if [[ $race == refresh || $race == same-refresh ]]; then
      cat >"$root/bin/awk" <<'EOF'
#!/bin/sh
if mkdir "$SHIBUMI_HELPER_STATE" 2>/dev/null; then
  sleep 0.25
  printf '%s\n' '{"summary":"Old host history","timestamp":1}'
else
  printf '%s\n' '{"summary":"New host history","timestamp":2}'
fi
EOF
    else
      printf '#!/bin/sh\nsleep 0.25\nexec /usr/bin/awk "$@"\n' >"$root/bin/awk"
    fi
    chmod 755 "$root/bin/awk"
    path="$root/bin:$path"
  fi
  if [[ $history_mode != missing ]]; then
    mkdir -p "$root/home/.local/state/omarchy/notifications/history"
  fi
  if [[ $history_mode == populated ]]; then
    local history="$root/home/.local/state/omarchy/notifications/history"
    printf '%s\n' '{malformed' >"$history/000-malformed.json"
    for index in {1..12}; do
      printf '{"id":%d,"originalId":%d,"app":"Fixture","summary":"History %d","body":"<b>plain</b>","timestamp":%d}\n' \
        "$index" "$index" "$index" "$index" >"$history/$index.json"
    done
    mkdir -p "$root/state/omarchy/notifications/history"
    printf '%s\n' '{"summary":"Wrong XDG path","timestamp":999}' \
      >"$root/state/omarchy/notifications/history/poison.json"
  fi

  setsid env -i \
    HOME="$root/home" \
    XDG_CONFIG_HOME="$root/config" \
    XDG_CACHE_HOME="$root/cache" \
    XDG_STATE_HOME="$root/state" \
    XDG_DATA_HOME="$root/data" \
    XDG_RUNTIME_DIR="$root/runtime" \
    TMPDIR="$root/tmp" \
    PIPEWIRE_RUNTIME_DIR="$root/pipewire" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$root/no-session-bus" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$root/no-system-bus" \
    WAYLAND_DISPLAY= \
    QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
    QSG_RHI_BACKEND=software \
    PATH="$path" \
    LANG=C.UTF-8 \
    SHIBUMI_EXPECTED_HISTORY_COUNT="$expected" \
    SHIBUMI_HISTORY_RACE="$race" \
    SHIBUMI_HELPER_STATE="$root/helper-state" \
    QML_IMPORT_PATH="$omarchy_path/shell" \
    QML2_IMPORT_PATH="$omarchy_path/shell" \
    "$quickshell_bin" -p "$tmpdir" --no-color >"$output" 2>&1 &
  fixture_pid=$!
  local ticks=0
  while kill -0 "$fixture_pid" 2>/dev/null && (( ticks < 160 )); do
    sleep 0.05
    ((ticks += 1))
  done
  if kill -0 "$fixture_pid" 2>/dev/null; then
    stop_fixture
    cat "$output"
    fail "$name timed out"
  fi
  set +e
  wait "$fixture_pid"
  local rc=$?
  set -e
  fixture_pid=
  cat "$output"
  [[ $rc -eq 0 ]] || fail "$name smoke exited $rc"
  grep -Fq "$marker" "$output" || fail "$name success marker missing"
  if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load' "$output"; then
    fail "$name runtime log contains a composition error"
  fi
}

run_case populated 10 populated
run_case empty 0 empty
run_case read-failure 0 missing
run_case detach-race 10 populated 'notification history detach race passed' detach
run_case replace-race 10 populated 'notification history replace race passed' replace
run_case replace-refresh 1 missing 'notification history refresh race passed' refresh
run_case same-host-refresh 1 missing \
  'notification history same-refresh race passed' same-refresh

# UI contract: history rows are read-only, close without invoking live actions,
# and sender-controlled labels are rendered as plain text.
grep -Fq 'onClicked: panel.selectTab("recent")' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail 'Recent click does not select the history tab'
grep -Fq 'if (recent && (!historyAvailable || !showHistory())) return false' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail 'Recent selection does not trigger the private read'
grep -Fq 'if (bucket === "pending" && entry' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail 'recent row click is not separated from the live action path'
[[ $(grep -Fc 'textFormat: Text.PlainText' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml") -ge 3 ]] \
  || fail 'app, summary, and body are not all plain text'

printf 'notification adapter regression passed\n'
