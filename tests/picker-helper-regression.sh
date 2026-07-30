#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper=${PICKER_HELPER:-$repo_root/scripts/shibumi-picker}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME=$tmp/home
export XDG_CACHE_HOME=$tmp/cache
export XDG_PICTURES_DIR=$HOME/Pictures
export XDG_VIDEOS_DIR=$HOME/Videos
export PATH=$tmp/bin:/usr/bin:/bin
omarchy_path=$tmp/omarchy

mkdir -p "$HOME/.config/omarchy/themes/shared/backgrounds" \
  "$HOME/.config/omarchy/themes/user-only/backgrounds" \
  "$HOME/.config/omarchy/themes/no-preview" \
  "$HOME/.config/omarchy/themes/invalid theme/backgrounds" \
  "$omarchy_path/themes/shared/backgrounds" \
  "$omarchy_path/themes/official/backgrounds" \
  "$HOME/.local/state/omarchy/current/theme/backgrounds" \
  "$HOME/.config/omarchy/backgrounds/current" \
  "$HOME/.local/state/omarchy/current" \
  "$HOME/Pictures" "$HOME/Videos" "$tmp/bin"

printf 'current\n' >"$HOME/.local/state/omarchy/current/theme.name"
printf 'user shared' >"$HOME/.config/omarchy/themes/shared/preview.png"
printf 'user only' >"$HOME/.config/omarchy/themes/user-only/preview.png"
printf 'invalid theme' >"$HOME/.config/omarchy/themes/invalid theme/preview.png"
printf 'official shared' >"$omarchy_path/themes/shared/preview.png"
printf 'official only' >"$omarchy_path/themes/official/preview.png"
printf 'stock wallpaper' >"$HOME/.local/state/omarchy/current/theme/backgrounds/stock.png"
printf 'user wallpaper' >"$HOME/.config/omarchy/backgrounds/current/user.webp"
printf 'shot' >"$HOME/Pictures/screenshot-2026-07-17_01-00-00.png"
printf 'video' >"$HOME/Videos/capture.mp4"

cat >"$tmp/bin/magick" <<'EOF'
#!/usr/bin/env bash
if [[ ${SHIBUMI_TEST_SLOW:-0} == 1 ]]; then
  printf '%s\n' "$$" >"$SHIBUMI_TEST_PID_FILE"
  trap 'exit 143' TERM INT
  sleep 30
fi
for value in "$@"; do output=$value; done
printf 'thumb' >"$output"
EOF
cat >"$tmp/bin/ffmpegthumbnailer" <<'EOF'
#!/usr/bin/env bash
while (( $# > 0 )); do
  if [[ $1 == -o ]]; then output=$2; shift 2; else shift; fi
done
printf 'poster' >"$output"
EOF
cat >"$tmp/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
if [[ ${SHIBUMI_TEST_SLOW_HASH:-0} == 1 ]]; then
  printf '%s\n' "$$" >"$SHIBUMI_TEST_HASH_PID_FILE"
  trap 'exit 143' TERM INT
  sleep 30
fi
exec /usr/bin/sha256sum "$@"
EOF
chmod +x "$tmp/bin/magick" "$tmp/bin/ffmpegthumbnailer" \
  "$tmp/bin/sha256sum"

fail() {
  printf 'picker helper regression failed: %s\n' "$*" >&2
  exit 1
}

theme_rows=$($helper scan theme "$omarchy_path")
[[ $(printf '%s\n' "$theme_rows" | wc -l) -eq 3 ]] \
  || fail "theme scan did not de-duplicate user override"
if printf '%s\n' "$theme_rows" | grep -Fq 'no-preview'; then
  fail "theme without displayable preview leaked into rows"
fi
printf '%s\n' "$theme_rows" | grep -Fq "$HOME/.config/omarchy/themes/shared/preview.png" \
  || fail "user theme did not override official theme"
if printf '%s\n' "$theme_rows" | grep -Fq "$omarchy_path/themes/shared/preview.png"; then
  fail "shadowed official theme leaked into rows"
fi
if printf '%s\n' "$theme_rows" | grep -Fq 'invalid theme'; then
  fail "invalid theme name leaked into action rows"
fi

wallpaper_rows=$($helper scan wallpaper "$omarchy_path")
[[ $(printf '%s\n' "$wallpaper_rows" | wc -l) -eq 2 ]] \
  || fail "wallpaper scan did not combine stock and user roots"
[[ $(printf '%s\n' "$wallpaper_rows" | awk -F '\t' '$5 == 0 { count++ } END { print count + 0 }') -eq 2 ]] \
  || fail "cold wallpaper rows were reported ready"

mapfile -t wallpaper_sources < <(printf '%s\n' "$wallpaper_rows" | cut -f1)
warm_output=$($helper warm wallpaper 10 "${wallpaper_sources[@]}")
[[ $(printf '%s\n' "$warm_output" | sed '/^$/d' | wc -l) -eq 2 ]] \
  || fail "bounded wallpaper warmup did not generate both thumbnails"
cached_rows=$($helper cached wallpaper)
[[ $(printf '%s\n' "$cached_rows" | awk -F '\t' '$5 == 1 { count++ } END { print count + 0 }') -eq 2 ]] \
  || fail "warm thumbnails were not reflected in cached rows"

screenshot_rows=$($helper scan screenshots "$omarchy_path")
[[ $(printf '%s\n' "$screenshot_rows" | wc -l) -eq 1 ]] \
  || fail "screenshot scan contract"

video_rows=$($helper scan videos "$omarchy_path")
video_source=$(printf '%s\n' "$video_rows" | cut -f1)
[[ $video_source == "$HOME/Videos/capture.mp4" ]] || fail "video scan contract"
video_warm=$($helper warm videos 19 "$video_source")
[[ -s $video_warm ]] || fail "video poster was not generated"

printf 'cancel me' >"$HOME/.local/state/omarchy/current/theme/backgrounds/cancel.png"
cancel_pid_file=$tmp/slow-worker.pid
SHIBUMI_TEST_SLOW=1 SHIBUMI_TEST_PID_FILE=$cancel_pid_file \
  $helper warm wallpaper 19 \
  "$HOME/.local/state/omarchy/current/theme/backgrounds/cancel.png" >/dev/null &
warm_pid=$!
for _ in {1..100}; do
  [[ -s $cancel_pid_file ]] && break
  sleep 0.02
done
[[ -s $cancel_pid_file ]] || fail "slow thumbnail worker did not start"
worker_pid=$(<"$cancel_pid_file")
kill "$warm_pid"
wait "$warm_pid" 2>/dev/null || true
for _ in {1..100}; do
  kill -0 "$worker_pid" 2>/dev/null || break
  sleep 0.02
done
if kill -0 "$worker_pid" 2>/dev/null; then
  kill "$worker_pid" 2>/dev/null || true
  fail "thumbnail worker survived controller cancellation"
fi

if find "$tmp" -type d -name '*.lock' -o -type f -name '*.tmp.jpg' | grep -q .; then
  fail "worker artifacts remained"
fi

cp "$XDG_CACHE_HOME/shibumi/picker/wallpaper.tsv" "$tmp/wallpaper.before.tsv"
printf 'cancel scan' >"$HOME/.local/state/omarchy/current/theme/backgrounds/cancel-scan.png"
scan_pid_file=$tmp/slow-hash.pid
SHIBUMI_TEST_SLOW_HASH=1 SHIBUMI_TEST_HASH_PID_FILE=$scan_pid_file \
  python3 - "$helper" "$omarchy_path" <<'PY'
import os
import signal
import subprocess
import sys
import time

helper, omarchy_path = sys.argv[1:]
process = subprocess.Popen(
    ["bash", helper, "scan", "wallpaper", omarchy_path],
    env=os.environ.copy(),
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
)
pid_file = os.environ["SHIBUMI_TEST_HASH_PID_FILE"]
for _ in range(100):
    if os.path.exists(pid_file) and os.path.getsize(pid_file) > 0:
        break
    time.sleep(0.02)
else:
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    raise SystemExit("slow scan hash did not start")
os.killpg(process.pid, signal.SIGKILL)
if process.wait() != -signal.SIGKILL:
    raise SystemExit("slow scan was not hard-cancelled")
PY
[[ -s $scan_pid_file ]] || fail "slow scan hash did not start"
cmp -s "$tmp/wallpaper.before.tsv" \
  "$XDG_CACHE_HOME/shibumi/picker/wallpaper.tsv" \
  || fail "cancelled scan replaced the stable wallpaper cache"
mapfile -t scan_artifacts < <(find "$XDG_CACHE_HOME/shibumi/picker" -maxdepth 1 \
  -type f \( -name 'wallpaper.raw.*' -o -name 'wallpaper.??????' \) -print)
(( ${#scan_artifacts[@]} > 0 )) \
  || fail "hard-cancel fixture did not leave recoverable scan artifacts"
$helper cleanup
mapfile -t scan_artifacts < <(find "$XDG_CACHE_HOME/shibumi/picker" -maxdepth 1 \
  -type f \( -name 'wallpaper.raw.*' -o -name 'wallpaper.??????' \) -print)
if (( ${#scan_artifacts[@]} > 0 )); then
  fail "cancelled scan left temporary cache artifacts: ${scan_artifacts[*]}"
fi

printf 'picker helper regression passed\n'
