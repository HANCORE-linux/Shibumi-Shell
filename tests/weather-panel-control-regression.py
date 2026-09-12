#!/usr/bin/env python3
"""Captured panel guard controls; caller's baseline gate admits host fragments."""
import argparse
from pathlib import Path
import re
import sys
import tempfile
sys.dont_write_bytecode = True
from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.owned_cgroup import OwnedCgroup
from lib.source_snapshot import materialize, snapshot

REPO = Path(__file__).resolve().parent.parent
ERROR = re.compile(r'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error|Cannot assign|Failed to load configuration')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host-shell', required=True, type=Path)
    args = parser.parse_args()
    files = {}
    for source, target in ((REPO / 'hancore.shibumi.center', 'center'),
                           (args.host_shell / 'Commons', 'Commons'),
                           (args.host_shell / 'Ui', 'Ui')):
        for name, record in snapshot(source).items():
            files[target + '/' + name] = record
    for source, target, executable in (
        ('tests/weather-panel-location-smoke.qml', 'shell.qml', False),
        ('tests/fixtures/ShibumiPanelTest.qml', 'center/ShibumiPanel.qml', False),
        ('tests/fixtures/weather-geocode-curl', 'bin/curl', True),
        ('tests/fixtures/weather-location-helper', 'bin/omarchy-weather-location', True),
        ('tests/lib/cgroup_exec.py', 'cgroup_exec.py', False),
    ):
        files[target] = (read_regular(REPO / source, 65536), executable)
    variants = [
        ('positive', None, None, None),
        ('input-bound', 'maximumLength: WeatherLocationModel.maximumQueryLength()',
         'maximumLength: 32767', 'location input length limit'),
        ('null-projection', '    if (!location) {\n      locationError = "No matching location"\n      return false\n    }\n',
         '', 'malformed selection crashed instead of refusal'),
        ('restored', None, None, None),
    ]
    for label, old, new, diagnostic in variants:
        staged = dict(files)
        if old is not None:
            data = staged['center/WeatherPanel.qml'][0]
            if data.count(old.encode()) != 1:
                raise RuntimeError('panel mutation anchor: ' + label)
            staged['center/WeatherPanel.qml'] = (data.replace(old.encode(), new.encode()), False)
        with tempfile.TemporaryDirectory(prefix='shibumi-weather-panel-') as directory:
            root = Path(directory)
            materialize(staged, root)
            env = {'PATH': str(root / 'bin') + ':/usr/bin:/bin', 'LANG': 'C.UTF-8',
                   'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
                   'QT_QPA_PLATFORMTHEME': '', 'QT_FORCE_STDERR_LOGGING': '1',
                   'WAYLAND_DISPLAY': '', 'DISPLAY': '', 'HYPRLAND_INSTANCE_SIGNATURE': '',
                   'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(root / 'absent-session'),
                   'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=' + str(root / 'absent-system'),
                   'WEATHER_LOCATION_LOG': str(root / 'location.log')}
            for key in ('HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME',
                        'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR'):
                path = root / key
                path.mkdir(mode=0o700)
                env[key] = str(path)
            with OwnedCgroup() as group:
                result = run_bounded(['/usr/bin/python3', '-I', '-S', str(root / 'cgroup_exec.py'),
                                      str(group.procs), '/usr/bin/quickshell', '-p', str(root)],
                                     env=env, cwd=root, timeout=5, maximum=65536,
                                     pass_fds=(group.procs,))
            text = (result.stdout + result.stderr).decode(errors='replace')
            good = result.returncode == 0 and 'weather panel location smoke passed' in text
            if diagnostic is not None:
                good = result.returncode != 0 and diagnostic in text
            if not good or ERROR.search(text):
                print(text)
                raise RuntimeError('weather panel control failed: ' + label)
            if diagnostic is None:
                helper_calls = read_regular(root / 'location.log', 4096)
                if helper_calls != b'--set|Berlin|52.52,13.405\n--clear\n':
                    raise RuntimeError(
                        'weather panel helper calls changed: ' + repr(helper_calls))
            print('weather panel control passed:', label)
    print('weather panel controls passed; window stub and inert helpers, not desktop acceptance')


if __name__ == '__main__':
    main()
