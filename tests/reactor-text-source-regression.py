#!/usr/bin/python3
"""Owned Reactor reader/Qt controller fixtures, disconnected from production."""
import json
import os
import runpy
from unittest.mock import patch
from pathlib import Path
import sys
import tempfile
sys.dont_write_bytecode = True
from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.owned_cgroup import OwnedCgroup
from lib.source_snapshot import materialize

REPO = Path(__file__).resolve().parents[1]
PLUGIN = REPO / 'hancore.shibumi.reactor'
HELPER = PLUGIN / 'scripts/read-reactor-text.py'
SOURCES = {'event': ('.cache/qs-reactor-event', 4096),
           'quotes': ('.config/shibumi/quotes.txt', 65536),
           'theme': ('.local/state/omarchy/current/theme.name', 512)}


def check(value, message):
    if not value:
        raise RuntimeError(message)


def cli(home, kind, accepted, env=None):
    result = run_bounded(['/usr/bin/python3', '-I', '-S', str(HELPER), kind, str(home)],
                         env=env, timeout=3, maximum=524288)
    data = json.loads(result.stdout)
    check(result.returncode == (0 if accepted else 1), 'reader exit')
    check(data['ok'] is accepted, 'reader acceptance')
    check(not result.stderr, 'unexpected reader stderr')
    if not accepted:
        check(data == {'ok': False, 'text': ''}, 'failure leaked content')
    return data['text']


def helper_checks():
    with tempfile.TemporaryDirectory(prefix='reactor-files-') as temp:
        base = Path(temp)
        home = base / 'home % # space'
        home.mkdir()
        for kind, (relative, maximum) in SOURCES.items():
            path = home / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            for size in (maximum - 1, maximum, maximum + 1):
                path.write_bytes(b'x' * size)
                text = cli(home, kind, size <= maximum)
                if size <= maximum:
                    check(len(text) == size, 'boundary text changed')
            path.write_bytes(b'\xff')
            cli(home, kind, False)
            path.unlink()
            os.mkfifo(path)
            cli(home, kind, False)
            path.unlink()
            target = base / ('target-' + kind)
            target.write_text('controlled')
            path.symlink_to(target)
            cli(home, kind, False)
            path.unlink()
            path.mkdir()
            cli(home, kind, False)
            path.rmdir()
            path.write_text('valid')
            check(cli(home, kind, True) == 'valid', 'restored regular read')
        quotes = home / SOURCES['quotes'][0]
        quotes.write_bytes(b'\0' * 65536)
        check(len(cli(home, 'quotes', True)) == 65536, 'JSON escaping bound')
        for data in (b'', b'x' * 8191, b'x' * 8192, b'x' * 8193,
                     '\ufeffGrüße'.encode(), b'x' * 8191 + '€'.encode(),
                     b'x' * 65533 + '€'.encode()):
            quotes.write_bytes(data)
            check(cli(home, 'quotes', True).encode() == data, 'UTF8/chunk boundary changed')
        for data in (b'x' * 8191 + b'\xe2\x82', b'x' * 65534 + b'\xe2\x82',
                     b'x' * 65534 + '€'.encode()):
            quotes.write_bytes(data)
            cli(home, 'quotes', False)
        api = runpy.run_path(str(HELPER), run_name='controlled_reader_definition')
        quotes.write_bytes(b'x' * 8193)
        original_read = os.read
        changed = False
        def change_after_read(fd, size):
            nonlocal changed
            block = original_read(fd, size)
            if not changed:
                changed = True
                with quotes.open('ab') as writer:
                    writer.write(b'changed')
            return block
        with patch.object(os, 'read', side_effect=change_after_read):
            try:
                api['read_source'](str(home), 'quotes')
            except ValueError:
                pass
            else:
                raise RuntimeError('concurrent content change admitted')
        event = home / SOURCES['event'][0]
        event.write_text('startup-ok')
        poison = base / 'poison'
        poison.mkdir()
        (poison / 'sitecustomize.py').write_text('print("UNBOUNDED-STARTUP" * 100000)\n')
        env = dict(os.environ, PYTHONPATH=str(poison))
        check(cli(home, 'event', True, env) == 'startup-ok', 'Python startup was not isolated')
        cache = home / '.cache'
        cache.rename(home / 'real-cache')
        cache.symlink_to(home / 'real-cache', target_is_directory=True)
        cli(home, 'event', False)
        cli(home, 'unknown', False)
        cli(home / '..' / home.name, 'quotes', False)
    print('REACTOR READER BOUNDS / TYPES / UTF8 / STARTUP PASSED', flush=True)


def controller_check(scenario, mutation=None):
    qml = read_regular(PLUGIN / 'BoundedTextSource.qml').decode()
    helper = read_regular(HELPER).decode()
    if scenario == 'startfail':
        old = '["/usr/bin/python3", "-I", "-S", helperPath, kind, home]'
        new = '[kind === "theme" ? "/missing-controlled-interpreter" : "/usr/bin/python3", "-I", "-S", helperPath, kind, home]'
        check(qml.count(old) == 1, 'startfail variant anchor')
        qml = qml.replace(old, new)
    elif scenario == 'missing-helper':
        old = '"-S", helperPath, kind, home]'
        check(qml.count(old) == 1, 'missing helper anchor')
        qml = qml.replace(old, '"-S", kind === "theme" ? helperPath + "-missing" : helperPath, kind, home]')
    elif scenario == 'stale-success':
        old = '    sys.stdout.buffer.write(payload)'
        check(helper.count(old) == 1, 'stale success variant anchor')
        helper = helper.replace(old, old + '\n    sys.stdout.buffer.flush()\n    if sys.argv[1] == "theme":\n        from pathlib import Path\n        import time\n        (Path(sys.argv[2]) / "barrier").write_text("ready")\n        time.sleep(1)')
    elif scenario in ('timeout', 'cancel', 'destroy'):
        old = '    raise SystemExit(main())'
        check(helper.count(old) == 1, 'sleep variant anchor')
        delay = '        time.sleep(10)\n'
        if scenario == 'destroy':
            delay = '        time.sleep(1)\n        (Path(sys.argv[2]) / "barrier").write_text("survived")\n'
        helper = helper.replace(old, '    if sys.argv[1] == "theme":\n        from pathlib import Path\n        import time\n        (Path(sys.argv[2]) / "barrier").write_text("ready")\n' + delay + old)
    diagnostic = None
    if mutation == 'orphaned-helper':
        # Controlled negative only: an owned child outlives the reader and
        # writes solely the private barrier. The fixture cgroup is the backstop.
        old = '        time.sleep(1)\n'
        check(helper.count(old) == 1, 'orphan control anchor')
        helper = helper.replace(old, '        if os.fork() == 0:\n            time.sleep(1)\n            (Path(sys.argv[2]) / "barrier").write_text("survived")\n            os._exit(0)\n' + old)
        diagnostic = 'destroyed source left helper active'
    elif mutation is not None:
        variants = {
            'unbounded-watch': ('preload: false', 'preload: true', 'watcher buffered file contents'),
            'latched-busy': ('|| (!storage.exited && !storage.terminalRequested)',
                             '|| (!storage.exited || !storage.streamed)', 'source deadline'),
            'stale-success': ('storage.startedGeneration === storage.generation',
                              'true', 'stale successful read published'),
        }
        old, new, diagnostic = variants[mutation]
        check(qml.count(old) == 1, 'controller mutation anchor')
        qml = qml.replace(old, new)
    files = {
        'reactor/BoundedTextSource.qml': (qml.encode(), False),
        'reactor/scripts/read-reactor-text.py': (helper.encode(), False),
        'shell.qml': (read_regular(REPO / 'tests/reactor-text-source-smoke.qml'), False),
    }
    with tempfile.TemporaryDirectory(prefix='reactor-source-') as temp:
        root = Path(temp)
        materialize(files, root)
        env = dict(os.environ)
        for key, name in [('HOME', 'home'), ('XDG_RUNTIME_DIR', 'run'),
                          ('XDG_CONFIG_HOME', 'config'), ('XDG_STATE_HOME', 'state'),
                          ('XDG_DATA_HOME', 'data'), ('XDG_CACHE_HOME', 'cache')]:
            directory = root / name
            directory.mkdir(mode=0o700)
            env[key] = str(directory)
        theme_text = 'theme-old' if scenario == 'stale-success' else 'x' * 513
        for kind, text in [('event', 'event-ok'), ('quotes', 'quote-ok'), ('theme', theme_text)]:
            path = root / 'home' / SOURCES[kind][0]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        env.update(QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
                   WAYLAND_DISPLAY='', DISPLAY='', HYPRLAND_INSTANCE_SIGNATURE='',
                   DBUS_SESSION_BUS_ADDRESS='unix:path=' + str(root / 'no-session'),
                   DBUS_SYSTEM_BUS_ADDRESS='unix:path=' + str(root / 'no-system'),
                   QML_IMPORT_PATH=str(root), QML2_IMPORT_PATH=str(root), REACTOR_FIXTURE_SCENARIO=scenario)
        with OwnedCgroup() as group:
            fd = group.procs
            result = run_bounded(['/usr/bin/python3', str(REPO / 'tests/lib/cgroup_exec.py'),
                                  str(fd), '/usr/bin/quickshell', '-p', str(root)],
                                 env=env, timeout=9, maximum=65536, pass_fds=(fd,))
        text = (result.stdout + result.stderr).decode(errors='replace')
        print(scenario, mutation or 'positive', result.returncode, text, flush=True)
        if mutation:
            check(result.returncode != 0 and diagnostic in text, 'negative controller case did not detect defect')
        else:
            check(result.returncode == 0 and 'reactor text source smoke passed' in text, 'controller case failed')
        for forbidden in ('TypeError', 'ReferenceError', 'Binding loop', 'Unable to assign', 'Internal error', 'Cannot assign'):
            check(forbidden not in text, 'controller QML error: ' + forbidden)
    check(not root.exists(), 'owned controller fixture remained')


if __name__ == '__main__':
    helper_checks()
    for scenario in ('valid', 'startfail', 'missing-helper', 'timeout', 'cancel', 'destroy', 'stale-success'):
        controller_check(scenario)
    controller_check('valid', 'unbounded-watch')
    controller_check('startfail', 'latched-busy')
    controller_check('stale-success', 'stale-success')
    controller_check('destroy', 'orphaned-helper')
    controller_check('destroy')
    controller_check('valid')
    print('REACTOR BOUNDED TEXT SOURCE REGRESSION PASSED')
