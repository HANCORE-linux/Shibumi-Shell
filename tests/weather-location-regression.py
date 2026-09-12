#!/usr/bin/env python3
"""Pure captured weather-location model: no network, helpers or desktop views."""
from pathlib import Path
import re
import sys
import tempfile
sys.dont_write_bytecode = True
from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.source_snapshot import materialize

REPO = Path(__file__).resolve().parent.parent


def main():
    model = read_regular(REPO / 'hancore.shibumi.center/WeatherLocationModel.js', 65536)
    fixture = read_regular(REPO / 'tests/weather-location-boundary.qml', 65536)
    variants = [
        ('positive', None, None, None),
        ('row-budget', 'if (!Array.isArray(results) || results.length > 5) return []',
         'if (!Array.isArray(results)) return []', 'result count boundary 6'),
        ('coordinate', 'return typeof value === "number" && isFinite(value)',
         'return true || typeof value === "number" && isFinite(value)', 'latitude rejected 0'),
        ('character-budget', 'raw.length > 65536', 'false', 'parser character budget 65537'),
        ('surrogates', 'var i = 0; i < value.length; i++',
         'var i = value.length; i < value.length; i++', 'unsafe name 4'),
        ('commit-projection', 'return { name: selectedName, latitude: suggestion.latitude, longitude: suggestion.longitude }',
         'return suggestion', 'commit projection leaked metadata'),
        ('restored', None, None, None),
    ]
    for label, old, new, diagnostic in variants:
        data = model
        if old is not None:
            if model.count(old.encode()) != 1:
                raise RuntimeError('weather model mutation anchor: ' + label)
            data = model.replace(old.encode(), new.encode())
        with tempfile.TemporaryDirectory(prefix='shibumi-weather-model-') as temporary:
            root = Path(temporary)
            materialize({'hancore.shibumi.center/WeatherLocationModel.js': (data, False),
                         'tests/weather-location-boundary.qml': (fixture, False)}, root)
            env = {'PATH': '/usr/bin:/bin', 'QT_QPA_PLATFORM': 'offscreen',
                   'QT_QUICK_BACKEND': 'software', 'QT_QPA_PLATFORMTHEME': '',
                   'QT_FORCE_STDERR_LOGGING': '1', 'WAYLAND_DISPLAY': '', 'DISPLAY': '',
                   'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(root / 'absent-session'),
                   'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=' + str(root / 'absent-system')}
            for key in ('HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME',
                        'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR'):
                path = root / key
                path.mkdir(mode=0o700)
                env[key] = str(path)
            result = run_bounded(['/usr/lib/qt6/bin/qml', str(root / 'tests/weather-location-boundary.qml')],
                                 env=env, cwd=root, timeout=4, maximum=32768)
            text = (result.stdout + result.stderr).decode(errors='replace')
            good = result.returncode == 0 and 'weather location boundary passed' in text
            if diagnostic is not None:
                good = result.returncode != 0 and diagnostic in text
            if not good or re.search(r'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error|Cannot assign', text):
                print(text)
                raise RuntimeError('weather model control failed: ' + label)
            print('weather model control passed:', label)
    print('weather location regression passed; schema only, not acquisition bound')


if __name__ == '__main__':
    main()
