#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-theme-palette.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'theme palette runtime regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

home="$tmpdir/home"
current="$home/.local/state/omarchy/current"
mkdir -p "$current/theme" "$tmpdir/runtime"
printf '%s\n' 'same-theme' >"$current/theme.name"
printf '%s\n' 'color1 = "#112233"' 'color2 = "#223344"' \
  'color3 = "#334455"' 'color4 = "#445566"' 'color5 = "#556677"' \
  'color6 = "#667788"' 'color7 = "#778899"' 'color8 = "#8899aa"' \
  >"$current/theme/colors.toml"

swap_script="$tmpdir/swap-theme"
cat >"$swap_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
current="$HOME/.local/state/omarchy/current"
rm -rf -- "$current/next-theme"
mkdir -p "$current/next-theme"
printf '%s\n' 'color1 = "#8899aa"' 'color2 = "#99aabb"' \
  'color3 = "#aabbcc"' 'color4 = "#bbccdd"' 'color5 = "#ccddee"' \
  'color6 = "#ddeeff"' 'color7 = "#eeffcc"' 'color8 = "#223344"' \
  >"$current/next-theme/colors.toml"
rm -rf -- "$current/theme"
mv -- "$current/next-theme" "$current/theme"
printf '%s\n' 'same-theme' >"$current/theme.name"
EOF
chmod 0700 "$swap_script"

install -Dm0644 "$repo_root/tests/theme-palette-runtime-smoke.qml" \
  "$tmpdir/shell.qml"
cp -a -- "$repo_root/hancore.shibumi.state" "$tmpdir/plugin"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"

set +e
output=$(timeout 8 env \
  HOME="$home" \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  SHIBUMI_THEME_SWAP_SCRIPT="$swap_script" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
rc=$?
set -e

printf '%s\n' "$output"
[[ $rc -eq 0 ]] || fail "Quickshell exited $rc"
grep -F 'theme palette runtime smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

printf 'theme palette runtime regression passed\n'
