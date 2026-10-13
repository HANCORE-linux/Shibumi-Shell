#!/usr/bin/env bash
# One synchronous launcher; ownership, bounded capture and cleanup stay in Python.
qs_run_fixture() {
  local fixture=$1 workdir=$2 deadline=${3:-8}
  local libdir host=${OMARCHY_PATH:?pinned Omarchy baseline required}
  libdir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  # Existing staged trees may contain deliberate platform stubs; never replace them.
  local module
  for module in Commons Ui; do
    [[ -d ${fixture%/*}/$module ]] || cp -a -- "$host/shell/$module" "${fixture%/*}/$module"
  done
  # Caller-local arrays preserve legacy env/env -i and optional CLI arguments.
  local -a environment=("${qs_fixture_env[@]:?explicit fixture environment required}")
  /usr/bin/python3 - "$libdir" "$fixture" "$workdir" "$deadline" \
    "${quickshell_bin:-${QUICKSHELL_BIN:-/usr/bin/quickshell}}" \
    "${#environment[@]}" "${environment[@]}" "${qs_fixture_args[@]}" <<'PY'
import os, signal, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from isolated_process import run_bounded
fixture, root = map(Path, sys.argv[2:4])
count = int(sys.argv[6]); entries = sys.argv[7:7 + count]
env = dict(os.environ)
if entries and entries[0] == '-i':
    env = {}; entries = entries[1:]
env.update(entry.split('=', 1) for entry in entries)
source = fixture.parent if fixture.name == 'shell.qml' else fixture
command = [sys.argv[5], '-p', str(source), *sys.argv[7 + count:]]
signal.signal(signal.SIGTERM, signal.default_int_handler)
try:
    # Redirection only, not a shell process manager: exec keeps the owned leader.
    result = run_bounded(['/bin/sh', '-c', 'exec "$@" 2>&1', 'qs-fixture', *command],
                         env=env, timeout=float(sys.argv[4]), maximum=4 * 1024 * 1024)
except RuntimeError as error:
    result = error
    (root / 'qs-runner-error.log').write_text(str(error) + '\n')
    print(error, file=sys.stderr)
    code = 124 if str(error).startswith('owned process deadline') else 125
else:
    code = result.returncode if result.returncode >= 0 else 128 - result.returncode
(root / 'qs-runner.log').write_bytes(result.stdout + result.stderr)
(root / 'qs-runner-survivors').write_text(str(result.survivorsBeforeKill) + '\n')
sys.stdout.buffer.write(result.stdout + result.stderr)
raise SystemExit(code)
PY
}
