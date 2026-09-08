#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
fixture=$(mktemp -d /tmp/sb-ghost.XXXXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -m 700 "$fixture/home" "$fixture/run" "$fixture/core"
cp "$repo_root/core/DragSession.qml" "$repo_root/core/DragGhostVisual.qml" "$fixture/core/"
cp -a "$OMARCHY_PATH/shell/Commons" "$OMARCHY_PATH/shell/Ui" "$fixture/"
python3 - "$repo_root/tests/drag-ghost-render-regression.qml" "$fixture" <<'PY'
from pathlib import Path
import sys
source, fixture = map(Path, sys.argv[1:])
(fixture / 'shell.qml').write_text(source.read_text().replace('testOutput/', str(fixture) + '/'))
PY
for scale in 1 1.5; do
  timeout --kill-after=2 15 env -i PATH=/usr/bin:/bin LANG=C.UTF-8 \
    HOME="$fixture/home" XDG_RUNTIME_DIR="$fixture/run" \
    XDG_CONFIG_HOME="$fixture/home/config" XDG_CACHE_HOME="$fixture/home/cache" \
    XDG_STATE_HOME="$fixture/home/state" XDG_DATA_HOME="$fixture/home/data" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$fixture/no-session-bus" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$fixture/no-system-bus" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
    QT_SCALE_FACTOR="$scale" /usr/bin/quickshell -p "$fixture" > "$fixture/runtime.log" 2>&1 || {
      tail -60 "$fixture/runtime.log" >&2
      exit 1
    }
  grep -q 'drag ghost render regression passed' "$fixture/runtime.log"
  if grep -Eq 'Binding loop|TypeError|ReferenceError|WARN|ERROR' "$fixture/runtime.log"; then
    tail -60 "$fixture/runtime.log" >&2
    exit 1
  fi
  python3 - "$fixture" "$scale" <<'PY'
from pathlib import Path
import subprocess
import sys
root = Path(sys.argv[1])
for name, channel in [('capture-top.png', 0), ('capture-bottom.png', 2), ('visual-top.png', 0)]:
    # Only controlled Qt-generated PNGs from this private fixture, never a
    # desktop capture or external asset. Decode exactly one pixel with bounded
    # ImageMagick resources; no optional Python imaging dependency is needed.
    result = subprocess.run([
        '/usr/bin/magick', '-limit', 'memory', '64MiB', '-limit', 'map', '128MiB',
        'PNG:' + str(root / name), '-gravity', 'Center', '-crop', '1x1+0+0',
        '+repage', '-depth', '8', 'RGBA:-',
    ], capture_output=True, timeout=10, check=True)
    rgba = tuple(result.stdout)
    assert len(rgba) == 4 and rgba[channel] > 200 and rgba[1] < 100, (name, rgba)
    assert rgba[3] >= (250 if name.startswith('capture-') else 80), (name, rgba)
print(f'Ghost pixels and lifecycle passed (offscreen scale {sys.argv[2]})')
PY
done
printf 'drag ghost render regression passed (isolated offscreen, not Wayland acceptance)\n'
