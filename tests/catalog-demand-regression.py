#!/usr/bin/env python3
"""Actual local read-interest and service facade; inert backend, no live IPC."""
import argparse
from pathlib import Path
import tempfile
from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.owned_cgroup import OwnedCgroup
from lib.source_snapshot import snapshot, materialize

ROOT = Path(__file__).resolve().parents[1]
MARKER = 'catalog demand ownership/reentry/capacity passed'
SERVICE_MARKER = 'production catalog service leases/admission/reconcile passed; inert backend'


def run_case(sources, service=False, diagnostic=''):
    with tempfile.TemporaryDirectory(prefix='shibumi-catalog-demand-') as temporary:
        base = Path(temporary)
        staged = dict(sources)
        staged['shell.qml'] = staged['service.qml' if service else 'demand.qml']
        materialize(staged, base)
        for name in ('home', 'config', 'state', 'cache', 'data', 'run'):
            (base / name).mkdir(exist_ok=True)
        (base / 'run').chmod(0o700)
        env = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'HOME': str(base / 'home'),
            'XDG_CONFIG_HOME': str(base / 'config'), 'XDG_STATE_HOME': str(base / 'state'),
            'XDG_CACHE_HOME': str(base / 'cache'), 'XDG_DATA_HOME': str(base / 'data'),
            'XDG_DATA_DIRS': str(base / 'data'), 'XDG_RUNTIME_DIR': str(base / 'run'),
            'DBUS_SESSION_BUS_ADDRESS': 'unix:path=' + str(base / 'absent-session'),
            'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=' + str(base / 'absent-system'),
            'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
            'QT_QPA_PLATFORMTHEME': '', 'QT_FORCE_STDERR_LOGGING': '1',
            'QML_DISABLE_DISK_CACHE': '1', 'PYTHONDONTWRITEBYTECODE': '1'}
        with OwnedCgroup() as group:
            result = run_bounded(['/usr/bin/python3', str(base / 'cgroup_exec.py'), str(group.procs),
                '/usr/bin/quickshell', '-p', str(base)], env=env, cwd=base,
                timeout=12, maximum=65536, pass_fds=(group.procs,))
        output = (result.stdout + result.stderr).decode(errors='replace')
        print(output, flush=True)
        marker = SERVICE_MARKER if service else MARKER
        if any(word in output for word in ('TypeError', 'ReferenceError', 'Binding loop',
                'Unable to assign', 'Cannot assign', 'Internal error')):
            raise RuntimeError('demand fixture runtime error')
        if diagnostic:
            if result.returncode == 0 or diagnostic not in output or marker in output:
                raise RuntimeError('demand control missed intended assertion')
            print('Calibrated demand control: ' + diagnostic, flush=True)
        elif result.returncode != 0 or marker not in output or 'ERROR' in output:
            raise RuntimeError('demand fixture failed')
    print('Owned demand fixture removed; no production services', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--controls', action='store_true')
    parser.add_argument('--demand-only', action='store_true')
    args = parser.parse_args()
    sources = {}
    for name in ('CatalogDemand.qml', 'CatalogDemandRecord.qml', 'PluginUpdateService.qml', 'NativeCatalog.qml',
                 'NativeCatalogCommand.qml', 'NativeCatalogModel.js', 'manager/shibumi-native-catalog'):
        sources['catalog/' + name] = (read_regular(ROOT / 'hancore.shibumi.control-center' / name, 65536), False)
    for name, value in snapshot(ROOT / 'hancore.shibumi.state/runtime').items():
        sources['hancore.shibumi.state/runtime/' + name] = value
    sources['hancore.shibumi.state/.shibumi-managed.json'] = (
        b'{"suiteId":"hancore.shibumi","suitePayloadDigest":"' + b'a' * 64 + b'"}', False)
    sources['cgroup_exec.py'] = (read_regular(ROOT / 'tests/lib/cgroup_exec.py', 65536), False)
    sources['demand.qml'] = (read_regular(ROOT / 'tests/catalog-demand-smoke.qml', 65536), False)
    if not args.demand_only:
        sources['service.qml'] = (read_regular(ROOT / 'tests/catalog-service-smoke.qml', 65536), False)
        sources['home/.config/omarchy/plugins/hancore.shibumi.control-center/manager/shibumi-plugin-updates'] = (
            read_regular(ROOT / 'tests/fixtures/catalog-update-scan.sh', 4096), True)
    run_case(sources)
    if not args.demand_only:
        run_case(sources, service=True)
    if args.controls:
        controls = [
            ('CatalogDemand.qml', b'return tokenFor(holder)', b'return null',
             'reentrant acquire lost replacement token', False),
            ('CatalogDemandRecord.qml', b'if (owner) owner.recordDestroyed(record, retiringHolder)',
             b'if (false) owner.recordDestroyed(record, retiringHolder)', 'destroyed holder retained demand', False),
            ('CatalogDemand.qml', b'if (_records.length >= 64)', b'if (_records.length > 64)',
             '65th holder admitted', False),
        ]
        if not args.demand_only:
            controls += [
                ('PluginUpdateService.qml', b'admitted: root.available && root.scopedHost',
                 b'admitted: root.scopedHost', 'provider loss retained read authority', True),
                ('PluginUpdateService.qml', b'  readonly property string command:',
                 b'  Connections {\n    target: root.shell\n    ignoreUnknownSignals: true\n    function onBarConfigChanged() { nativeCatalog.requestRefresh() }\n  }\n  readonly property string command:',
                 'State/config signal started or invalidated the catalog', True),
                ('PluginUpdateService.qml', b'  readonly property string command:',
                 b'  Connections {\n    target: root.barWidgetRegistry\n    ignoreUnknownSignals: true\n    function onRevisionChanged() { nativeCatalog.requestRefresh() }\n  }\n  readonly property string command:',
                 'widget-registry signal started or invalidated the catalog', True),
                ('PluginUpdateService.qml', b'demand: catalogDemand.count > 0',
                 b'demand: root.available', 'last explicit release retained catalog authority', True),
            ]
        for name, old, new, diagnostic, service in controls:
            key = 'catalog/' + name
            raw, executable = sources[key]
            if raw.count(old) != 1:
                raise RuntimeError('demand control anchor drifted: ' + repr(old))
            mutant = dict(sources)
            mutant[key] = (raw.replace(old, new), executable)
            run_case(mutant, service=service, diagnostic=diagnostic)
        run_case(sources)
        if not args.demand_only:
            run_case(sources, service=True)


if __name__ == '__main__':
    main()
