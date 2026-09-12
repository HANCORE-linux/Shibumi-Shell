#!/usr/bin/env python3
"""Actual report model and disabled Service parser, in captured private copies."""
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
    files = {}
    for name in ('WeatherReportModel.js', 'WeatherLocationModel.js', 'WeatherService.qml'):
        files['center/' + name] = (read_regular(REPO / 'hancore.shibumi.center' / name, 65536), False)
    files['shell.qml'] = (read_regular(REPO / 'tests/weather-report-boundary.qml', 65536), False)
    # Belt-and-braces inert PATH: even an accidental start cannot reach curl.
    files['bin/curl'] = (b'#!/usr/bin/python3\nraise SystemExit(99)\n', True)
    model = 'center/WeatherReportModel.js'
    variants = [
        ('positive', None, None, None, None),
        ('character-budget', model, 'raw.length > 131072', 'false', 'character budget 131073'),
        ('utf16-codepoints', model, 'raw.length > 131072', 'raw.match(/[\\uD800-\\uDBFF][\\uDC00-\\uDFFF]|[\\s\\S]/g).length > 131072',
         'UTF16 budget 131073'),
        ('utf16-bytes', model, 'raw.length > 131072', 'unescape(encodeURIComponent(raw)).length > 131072',
         'UTF16 budget 131071'),
        ('forecast-field', model, 'decimal(day.mintempF,', 'decimal(day.mintempC,',
         'forecast field projection'),
        ('forecast-minC', model, 'decimal(day.mintempC, -150, 150, false)',
         'decimal(day.mintempC, -1000, 150, false)', 'forecast numeric range minC -151'),
        ('forecast-maxC', model, 'decimal(day.maxtempC, -150, 150, false)',
         'decimal(day.maxtempC, -150, 1000, false)', 'forecast numeric range maxC 151'),
        ('forecast-minF', model, 'decimal(day.mintempF, -238, 302, false)',
         'decimal(day.mintempF, -1000, 302, false)', 'forecast numeric range minF -239'),
        ('forecast-maxF', model, 'decimal(day.maxtempF, -238, 302, false)',
         'decimal(day.maxtempF, -238, 1000, false)', 'forecast numeric range maxF 303'),
        ('forecast-orderC', model, 'Number(minC) > Number(maxC)', 'false', 'forecast min exceeds max C'),
        ('forecast-orderF', model, 'Number(minF) > Number(maxF)', 'false', 'forecast min exceeds max F'),
        ('day-budget', model, 'report.weather.length > 3', 'false', 'day budget 4'),
        ('hour-budget', model, 'hourly.length > 24', 'false', 'hour budget 25'),
        ('label-validation', model, 'return Location.boundedText(value[0].value, true)',
         'return value[0].value', 'label budget 161'),
        ('numeric-range', model, 'number > maximum', 'false', 'numeric range temp_C 151'),
        ('date-sequence', model, 'if (currentDate - previous !== 86400000) return null',
         'if (false) return null', 'nonconsecutive forecast dates'),
        ('partial-publication', 'center/WeatherService.qml',
         '    if (!candidate) {\n', '    if (!candidate) {\n      tempC = "partial"\n',
         'invalid report partially replaced publication'),
        ('restored', None, None, None, None),
    ]
    for label, filename, old, new, diagnostic in variants:
        staged = dict(files)
        if filename is not None:
            data = staged[filename][0]
            if data.count(old.encode()) != 1:
                raise RuntimeError('report mutation anchor: ' + label)
            staged[filename] = (data.replace(old.encode(), new.encode()), False)
        with tempfile.TemporaryDirectory(prefix='shibumi-weather-report-') as directory:
            root = Path(directory)
            materialize(staged, root)
            env = {'PATH': str(root / 'bin') + ':/usr/bin:/bin', 'LANG': 'C.UTF-8',
                   'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
                   'QT_QPA_PLATFORMTHEME': '', 'QT_FORCE_STDERR_LOGGING': '1',
                   'WAYLAND_DISPLAY': '', 'DISPLAY': '', 'HYPRLAND_INSTANCE_SIGNATURE': '',
                   'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(root / 'absent-session'),
                   'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=' + str(root / 'absent-system')}
            for key in ('HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME',
                        'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR'):
                path = root / key
                path.mkdir(mode=0o700)
                env[key] = str(path)
            result = run_bounded(['/usr/bin/timeout', '--signal=KILL', '3',
                                  '/usr/bin/quickshell', '-p', str(root)],
                                 env=env, cwd=root, timeout=4, maximum=32768)
            text = (result.stdout + result.stderr).decode(errors='replace')
            good = result.returncode == 0 and 'weather report boundary passed' in text
            if diagnostic is not None:
                good = result.returncode != 0 and diagnostic in text
            if not good or re.search(r'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error|Cannot assign', text):
                print(text)
                raise RuntimeError('weather report control failed: ' + label)
            print('weather report control passed:', label)
    print('weather report regression passed; parser publication only, not acquisition/lifecycle')


if __name__ == '__main__':
    main()
