#!/usr/bin/env python3
"""Captured-source Power deferred-dispatch positives and calibrated negatives."""
import json
from pathlib import Path
import re
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.source_snapshot import materialize, snapshot

REPO = Path(__file__).resolve().parent.parent
RUNTIME_ERROR = re.compile(r'TypeError|ReferenceError|Binding loop|Unable to assign|Internal error|Cannot assign|Failed to load configuration')


def main():
    # Both standalone and aggregate runs must test the canonical implementation,
    # not silently accept stale vendored copies after a canonical-only edit.
    for target in ('services/PowerService.qml', 'hancore.shibumi.power-state/Service.qml',
                   'services/PowerCommand.qml', 'hancore.shibumi.power-state/PowerCommand.qml'):
        checked = run_bounded(['/usr/bin/python3', '-I', '-S',
            str(REPO / 'scripts/sync-power-source.py'), '--check', str(REPO), target],
            timeout=3, maximum=4096)
        if checked.returncode != 0:
            raise RuntimeError('Power source parity failed: ' + target)
    power = snapshot(REPO / 'hancore.shibumi.power-state')
    runtime = snapshot(REPO / 'hancore.shibumi.state/runtime')
    shell = read_regular(REPO / 'tests/power-deferred-smoke.qml', 65536)
    helper = read_regular(REPO / 'tests/fixtures/power-runtime-helper.py', 16384)
    source = power['Service.qml'][0].decode()
    variants = [('positive', None, None, None)]
    for key, flag, flush, refresh, diagnostic in (
        ('profiles', 'profileRefreshPending', 'flushProfileRefresh', 'refreshProfiles',
         'cancelled deferred profiles revived after release'),
        ('active', 'activeProfileRefreshPending', 'flushActiveProfileRefresh', 'refreshActiveProfile',
         'cancelled deferred activeProfile revived after release'),
        ('battery', 'detailRefreshPending', 'flushDetailRefresh', 'refreshBatteryDetails',
         'cancelled deferred battery revived after release'),
    ):
        old = f'onSettled: if (root.{flag}) Qt.callLater(root.{flush})'
        new = f'onSettled: {{ if (!root.{flag}) return; root.{flag} = false; Qt.callLater(root.{refresh}) }}'
        variants.append((key, old, new, diagnostic))
    variants.append(('action', 'root.profileRefreshPending = true\n      Qt.callLater(root.flushProfileRefresh)',
                     'Qt.callLater(root.refreshProfiles)', 'cancelled deferred profiles revived after scope'))
    variants.append(('restored', None, None, None))
    for label, old, new, diagnostic in variants:
        staged = dict(power)
        if old is not None:
            if source.count(old) != 1:
                raise RuntimeError('deferred mutation anchor: ' + label)
            staged['Service.qml'] = (source.replace(old, new).encode(), power['Service.qml'][1])
        with tempfile.TemporaryDirectory(prefix='shibumi-power-deferred-') as directory:
            root = Path(directory)
            materialize(staged, root / 'powerState')
            materialize(runtime, root / 'hancore.shibumi.state/runtime')
            materialize({
                'shell.qml': (shell, False),
                'fixtures/power-runtime-helper.py': (helper, False),
                'hancore.shibumi.state/.shibumi-managed.json': (json.dumps({
                    'suiteId': 'hancore.shibumi', 'suitePayloadDigest': '0' * 64}).encode(), False),
                'data/profile': (b'balanced\n', False),
                'data/trace': (b'', False),
                'data/barrier': (b'', False),
            }, root)
            env = {'PATH': '/usr/bin:/bin', 'QT_QPA_PLATFORM': 'offscreen',
                   'QT_QUICK_BACKEND': 'software', 'QT_QPA_PLATFORMTHEME': '',
                   'WAYLAND_DISPLAY': '', 'DISPLAY': '', 'HYPRLAND_INSTANCE_SIGNATURE': '',
                   'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(root / 'absent-session'),
                   'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=' + str(root / 'absent-system'),
                   'PYTHONDONTWRITEBYTECODE': '1', 'SHIBUMI_POWER_SCOPE_DIR': str(root / 'data')}
            for key in ('HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME',
                        'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR'):
                path = root / key
                path.mkdir(mode=0o700)
                env[key] = str(path)
            result = run_bounded(['/usr/bin/quickshell', '-p', str(root)], env=env,
                                 cwd=root, timeout=9, maximum=65536)
            text = (result.stdout + result.stderr).decode(errors='replace')
            errors = [line for line in text.splitlines() if 'ERROR' in line]
            good = result.returncode == 0 and 'power deferred smoke passed' in text and not errors
            if diagnostic is not None:
                good = result.returncode != 0 and diagnostic in text and all(diagnostic in line for line in errors)
            if not good or RUNTIME_ERROR.search(text):
                print(text)
                raise RuntimeError('power deferred control failed: ' + label)
            print('power deferred control passed:', label)
    print('power deferred regression passed; controlled callback ordering, not native scheduling')


if __name__ == '__main__':
    main()
