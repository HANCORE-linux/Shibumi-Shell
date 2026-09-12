#!/usr/bin/env python3
"""Owned native catalog model/lifetime and bounded inert-IPC acquisition checks."""
import argparse
from pathlib import Path
import tempfile

from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.owned_cgroup import OwnedCgroup
from lib.source_snapshot import materialize

ROOT = Path(__file__).resolve().parents[1]
QML_MARKER = 'native catalog parsing/lifetime passed; no family or desktop acceptance'
IO_MARKER = 'bounded native catalog transport passed; inert IPC only'
COMMAND_MARKER = 'actual catalog QProcess cancellation/drain passed; inert IPC replacement'
DRAIN_MARKER = 'actual command process trees drained before cgroup cleanup'
START_FAILURE_MARKER = 'actual catalog QProcess start failure refused'
CADENCE_MARKER = 'catalog post-drain cooldown and inactive silence passed'


def run_case(sources, transport=False, diagnostic='', command_mode=False, start_failure=False, masked_signals=False, cadence=False):
    with tempfile.TemporaryDirectory(prefix='shibumi-native-catalog-') as temporary:
        base = Path(temporary)
        staged = dict(sources)
        if cadence:
            staged['shell.qml'] = staged['cadence.qml']
        if command_mode:
            staged['shell.qml'] = staged['command.qml']
            key = 'catalog/manager/shibumi-native-catalog'
            raw, executable = staged[key]
            anchor = b'if __name__ == "__main__":'
            replacement = b'''# Complete inert IPC seam; the actual launcher/custodian/collector remain.
if os.environ.get("CATALOG_MASKED_SIGNALS") == "1":
    signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGHUP})
_real_collect = collect
_fixture_directory = ""
def shell_process_identity(pid, directory):
    global _fixture_directory
    if (not isinstance(pid, int) or pid <= 1 or not directory.startswith("/fixture/")
            or not directory.endswith("/shell")):
        raise Refused("fixture-process-identity")
    _fixture_directory = directory
    return 99

def collect(argv, *, group_owner=False):
    if (len(argv) != 8 or argv[:3] != ["/usr/bin/quickshell", "ipc", "--pid"]
            or not argv[3].isascii() or not argv[3].isdecimal()
            or int(argv[3]) <= 1
            or argv[4:] != ["call", "--", "shell", "listPlugins"]
            or not _fixture_directory):
        raise Refused("fixture-command")
    mode = _fixture_directory.split("/")[-2]
    return _real_collect(["/usr/bin/python3", "-I", "-S", os.environ["CATALOG_IPC_FIXTURE"], mode],
        group_owner=group_owner)

'''
            if raw.count(anchor) != 1:
                raise RuntimeError('actual command inert seam anchor drifted')
            staged[key] = (raw.replace(anchor, replacement + anchor), executable)
        if start_failure:
            key = 'catalog/NativeCatalogCommand.qml'
            raw, executable = staged[key]
            old = b'worker.command = ["/usr/bin/python3",'
            if raw.count(old) != 1:
                raise RuntimeError('start failure anchor drifted')
            staged[key] = (raw.replace(old, b'worker.command = ["/fixture/no-python",'), executable)
        materialize(staged, base)
        for name in ('home', 'config', 'state', 'cache', 'data', 'run', 'pids'):
            (base / name).mkdir()
        (base / 'run').chmod(0o700)
        (base / 'pids/ready').write_text('')
        env = {'HOME': str(base / 'home'), 'XDG_CONFIG_HOME': str(base / 'config'),
            'XDG_STATE_HOME': str(base / 'state'), 'XDG_CACHE_HOME': str(base / 'cache'),
            'XDG_DATA_HOME': str(base / 'data'), 'XDG_DATA_DIRS': str(base / 'data'),
            'XDG_RUNTIME_DIR': str(base / 'run'), 'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8',
            'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(base / 'absent-session'),
            'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=' + str(base / 'absent-system'),
            'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
            'QT_FORCE_STDERR_LOGGING': '1', 'QML_DISABLE_DISK_CACHE': '1', 'PYTHONDONTWRITEBYTECODE': '1',
            'CATALOG_PID_DIR': str(base / 'pids'), 'CATALOG_IPC_FIXTURE': str(base / 'ipc.py'),
            'CATALOG_START_FAILURE': '1' if start_failure else '0',
            'CATALOG_MASKED_SIGNALS': '1' if masked_signals else '0'}
        command = ['/usr/bin/python3', '-I', '-S', str(base / 'transport.py')] if transport else [
            '/usr/bin/quickshell', '-p', str(base)]
        with OwnedCgroup() as group:
            prefix = ['/usr/bin/python3', str(base / 'cgroup_exec.py'), str(group.procs)]
            result = run_bounded([*prefix, *command], env=env, cwd=base, timeout=25 if cadence else 12,
                maximum=65536, pass_fds=(group.procs,))
            output = (result.stdout + result.stderr).decode(errors='replace')
            exit_code = result.returncode
            if command_mode and exit_code == 0 and COMMAND_MARKER in output:
                # Do not let the cgroup's cleanup hide a failed QProcess teardown.
                drained = run_bounded([*prefix, '/usr/bin/python3', '-I', '-S', str(base / 'drain.py')],
                    env=env, cwd=base, timeout=2, maximum=16384, pass_fds=(group.procs,))
                output += (drained.stdout + drained.stderr).decode(errors='replace')
                exit_code = drained.returncode
        print(output, flush=True)
        marker = (CADENCE_MARKER if cadence else START_FAILURE_MARKER if start_failure else DRAIN_MARKER if command_mode
            else IO_MARKER if transport else QML_MARKER)
        if start_failure and list((base / 'pids').glob('*.json')):
            raise RuntimeError('failed start constructed IPC fixture')
        if any(word in output for word in ('TypeError', 'ReferenceError', 'Binding loop', 'Unable to assign',
            'Cannot assign', 'Internal error')):
            raise RuntimeError('catalog fixture runtime error')
        if diagnostic:
            if exit_code == 0 or diagnostic not in output or marker in output:
                raise RuntimeError('catalog control missed intended assertion')
            print('Calibrated catalog control: ' + diagnostic, flush=True)
        elif exit_code != 0 or marker not in output or 'ERROR' in output:
            raise RuntimeError('catalog fixture failed')
    print('Owned catalog fixture removed; no live IPC or desktop', flush=True)


def cadence_cases(sources, controls):
    run_case(sources, cadence=True)
    if controls:
        changed = dict(sources)
        key = 'catalog/NativeCatalog.qml'
        raw, executable = sources[key]
        if raw.count(b'    reconcile.stop()') != 2 or raw.count(b'    repeat: false') != 1:
            raise RuntimeError('cadence control anchor drifted')
        raw = raw.replace(b'    reconcile.stop()', b'    // Old continuously ticking policy')
        raw = raw.replace(b'    repeat: false', b'    repeat: true\n    running: root.active')
        changed[key] = (raw, executable)
        run_case(changed, cadence=True, diagnostic='slow failure bypassed reconcile cooldown')
        run_case(sources, cadence=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--controls', action='store_true')
    parser.add_argument('--cadence-only', action='store_true')
    args = parser.parse_args()
    sources = {}
    for name in ('NativeCatalog.qml', 'NativeCatalogCommand.qml', 'NativeCatalogModel.js',
        'manager/shibumi-native-catalog'):
        sources['catalog/' + name] = (read_regular(ROOT / 'hancore.shibumi.control-center' / name, 65536), False)
    sources['shell.qml'] = (read_regular(ROOT / 'tests/native-catalog-smoke.qml', 65536), False)
    sources['transport.py'] = (read_regular(ROOT / 'tests/fixtures/native-catalog-transport.py', 65536), False)
    sources['cgroup_exec.py'] = (read_regular(ROOT / 'tests/lib/cgroup_exec.py', 65536), False)
    sources['command.qml'] = (read_regular(ROOT / 'tests/native-catalog-command-smoke.qml', 65536), False)
    sources['ipc.py'] = (read_regular(ROOT / 'tests/fixtures/native-catalog-ipc.py', 65536), False)
    sources['drain.py'] = (read_regular(ROOT / 'tests/fixtures/native-catalog-drain.py', 65536), False)
    sources['cadence.qml'] = (read_regular(ROOT / 'tests/native-catalog-cadence-smoke.qml', 65536), False)
    if args.cadence_only:
        cadence_cases(sources, args.controls)
        return
    run_case(sources, transport=True)
    run_case(sources)
    run_case(sources, command_mode=True)
    run_case(sources, command_mode=True, start_failure=True)
    run_case(sources, command_mode=True, masked_signals=True)
    if args.controls:
        controls = [
            ('NativeCatalogModel.js', [(b'Object.prototype.hasOwnProperty.call(byId, row.id)', b'false')],
                'duplicate catalog admitted', False),
            ('NativeCatalogModel.js', [(b'typeof row.enabled !== "boolean"', b'false')],
                'numeric Boolean admitted', False),
            ('NativeCatalog.qml', [(b'serial !== op.serial', b'serial < op.serial')],
                'future result became ready', False),
            ('NativeCatalog.qml', [(b'root._nativeActive = root.active && root.backendOverride === null',
                b'root._nativeActive = root.active')],
                'incomplete fake fell through', False),
            ('NativeCatalog.qml', [(b'    _epoch++\n    _deferred++\n    _ready = false', b'    _epoch++\n    _deferred++')],
                'loss retained readiness', False),
            ('NativeCatalog.qml', [(b'if (_operation || requestSerial !== op.serial || !sourceCurrent(op) || backend.busy) return false',
                b'if (!sourceCurrent(op)) return false')],
                'nested request did not settle', False),
            ('NativeCatalogModel.js', [(b'if (!uniqueKeys(raw)) return null', b'if (false) return null')],
                'malformed override became ready', False),
            ('NativeCatalog.qml', [(b'if (op.accepted && !op.drained) return',
                b'if (op.accepted && !op.event && !op.drained) return')],
                'completion bypassed drain', False),
            ('NativeCatalog.qml', [(b'(op.accepted ? !op.drained : op.backend.busy === true)', b'(op.backend.busy === true)')],
                'revocation bypassed drain', False),
            ('NativeCatalog.qml', [(b'if (Qt.isQtObject(op.backend)\n',
                b'if (Qt.isQtObject(op.backend) && op.backend === backend\n')],
                'replacement bypassed prior drain', False),
            ('NativeCatalog.qml', [(b'if (!active || !backendSupported || requestSerial >= 2147483647) return false',
                b'if (!active || !backendSupported || _operation || requestSerial >= 2147483647) return false')],
                'busy refresh intent lost', False),
            ('NativeCatalog.qml', [(b'if (!backendSupported) invalidate()', b'if (!backendSupported) {}')],
                'incomplete backend retained authority', False),
            ('NativeCatalog.qml', [(b'on_DrainBackendChanged: Qt.callLater(evaluate)', b'on_DrainBackendChanged: {}')],
                'destroyed backend blocked replacement', False),
            ('NativeCatalog.qml', [(b'(op.accepted ? !op.drained : op.backend.busy === true)',
                b'(op.backend.busy || (op.accepted && !op.drained))')],
                'drained malformed backend blocked replacement', False),
            ('NativeCatalog.qml', [(b'} catch (_) {\n      // Publication',
                b'} catch (_) { throw new Error("fixture cancel failure")\n      // Publication')],
                'throwing cancellation escaped invalidation', False),
            ('manager/shibumi-native-catalog', [(b'if sizes[key.data] > maximum:', b'if False:')],
                'stdout acquisition overbound accepted', True),
            ('manager/shibumi-native-catalog', [(b'if key in value:', b'if False:')],
                'duplicate JSON key accepted', True),
        ]
        for name, changes, diagnostic, transport in controls:
            mutated = dict(sources)
            key = 'catalog/' + name
            raw, executable = sources[key]
            for old, new in changes:
                if raw.count(old) != 1:
                    raise RuntimeError('catalog control anchor drifted: ' + repr(old))
                raw = raw.replace(old, new)
            mutated[key] = (raw, executable)
            run_case(mutated, transport=transport, diagnostic=diagnostic)
        mutated = dict(sources)
        key = 'catalog/manager/shibumi-native-catalog'
        raw, executable = sources[key]
        old = b'if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0 or os.getppid() != parent:'
        if raw.count(old) != 1:
            raise RuntimeError('custodian control anchor drifted')
        mutated[key] = (raw.replace(old, b'if os.getppid() != parent:'), executable)
        run_case(mutated, command_mode=True, diagnostic='custodian descendant survived cancellation')
        old = b'signal.pthread_sigmask(signal.SIG_SETMASK, mask - signals)'
        if raw.count(old) != 2:
            raise RuntimeError('inherited mask control anchor drifted')
        mutated[key] = (raw.replace(old, b'signal.pthread_sigmask(signal.SIG_SETMASK, mask)'), executable)
        run_case(mutated, command_mode=True, masked_signals=True,
            diagnostic='custodian descendant survived cancellation')
        run_case(sources, transport=True)
        run_case(sources)
        run_case(sources, command_mode=True)
        run_case(sources, command_mode=True, start_failure=True)
        run_case(sources, command_mode=True, masked_signals=True)
        cadence_cases(sources, True)


if __name__ == '__main__':
    main()
