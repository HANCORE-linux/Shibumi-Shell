#!/usr/bin/env python3
"""Inert source-sync fixtures: no Qt, platform helpers or production files."""
from pathlib import Path
import os
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True
from lib.isolated_process import run_bounded
from lib.isolated_files import read_regular

REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / 'scripts/sync-power-source.py'
OLD = b'import "../../hancore.shibumi.state/runtime" as SuiteRuntime\n'
NEW = b'import "../hancore.shibumi.state/runtime" as SuiteRuntime\n'


class PowerSourceSync(unittest.TestCase):
    def fixture(self, directory, target='services/PowerService.qml'):
        root = directory / 'repo'
        source = root / 'shared/power-state/Service.qml'
        source.parent.mkdir(parents=True)
        source.write_bytes(OLD + b'// inert\n')
        (source.parent / 'PowerCommand.qml').write_bytes(b'// inert command\n')
        destination = root / target
        destination.parent.mkdir(parents=True)
        expected = b'// inert command\n' if destination.name == 'PowerCommand.qml' else NEW + b'// inert\n'
        destination.write_bytes(expected)
        external = directory / 'external'
        external.mkdir()
        sentinel = external / destination.name
        sentinel.write_bytes(expected)
        sentinel.chmod(0o600)
        return root, source, destination, sentinel

    def invoke(self, root, target, mode, allowed):
        result = run_bounded(['/usr/bin/python3', '-I', '-S', str(HELPER), mode, str(root), target], timeout=4)
        self.assertEqual(result.returncode == 0, allowed, result.stdout + result.stderr)

    def test_transform_and_regular_atomic_write(self):
        for target in ('services/PowerService.qml', 'hancore.shibumi.power-state/Service.qml',
                       'services/PowerCommand.qml', 'hancore.shibumi.power-state/PowerCommand.qml'):
            with self.subTest(target=target), tempfile.TemporaryDirectory(prefix='power-sync-') as value:
                root, source, destination, sentinel = self.fixture(Path(value), target)
                expected = destination.read_bytes()
                destination.unlink()
                os.link(sentinel, destination)
                for mode in ('--paths', '--check', '--write', '--check'):
                    self.invoke(root, target, mode, True)
                self.assertEqual(destination.read_bytes(), expected)
                self.assertEqual(sentinel.read_bytes(), expected)
                self.assertEqual(sentinel.stat().st_mode & 0o777, 0o600)
                self.assertEqual(destination.stat().st_mode & 0o777, 0o644)
                self.assertNotEqual(destination.stat().st_ino, sentinel.stat().st_ino)
                self.assertFalse(list(destination.parent.glob('.*.sync-*')))

    def test_refuse_links_and_nonregular_input(self):
        for variant in ('source', 'source-parent', 'target', 'target-parent', 'fifo', 'duplicate', 'oversized'):
            for mode in ('--paths', '--check', '--write'):
                with self.subTest(variant=variant, mode=mode), tempfile.TemporaryDirectory(prefix='power-sync-') as value:
                    base = Path(value)
                    root, source, destination, sentinel = self.fixture(base)
                    if variant == 'source':
                        (base / 'external/Source.qml').write_bytes(source.read_bytes())
                        source.unlink(); source.symlink_to(base / 'external/Source.qml')
                    elif variant == 'source-parent':
                        original = source.read_bytes()
                        source.unlink(); (source.parent / 'PowerCommand.qml').unlink()
                        source.parent.rmdir()
                        (base / 'external/Service.qml').write_bytes(original)
                        source.parent.symlink_to(base / 'external', target_is_directory=True)
                    elif variant == 'target':
                        destination.unlink(); destination.symlink_to(sentinel)
                    elif variant == 'target-parent':
                        destination.unlink(); destination.parent.rmdir()
                        destination.parent.symlink_to(base / 'external', target_is_directory=True)
                    elif variant == 'fifo':
                        source.unlink(); os.mkfifo(source)
                    elif variant == 'duplicate':
                        source.write_bytes(OLD * 2)
                    else:
                        source.write_bytes(OLD + b' ' * (256 * 1024))
                    before = sentinel.read_bytes(), sentinel.stat().st_mode
                    self.invoke(root, 'services/PowerService.qml', mode, False)
                    self.assertEqual((sentinel.read_bytes(), sentinel.stat().st_mode), before)

    def test_lifecycle_entrypoint_refuses_canonical_only_change(self):
        targets = ('services/PowerService.qml', 'hancore.shibumi.power-state/Service.qml',
                   'services/PowerCommand.qml', 'hancore.shibumi.power-state/PowerCommand.qml')
        for changed, expected in (('Service.qml', targets[0]), ('PowerCommand.qml', targets[2])):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory(prefix='power-sync-entry-') as value:
                root, source, destination, sentinel = self.fixture(Path(value))
                for target in targets:
                    path = root / target
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(b'// inert command\n' if path.name == 'PowerCommand.qml' else NEW + b'// inert\n')
                    self.invoke(root, target, '--check', True)
                for relative in ('scripts/sync-power-source.py', 'tests/power-deferred-regression.py',
                                 'tests/lib/isolated_files.py', 'tests/lib/isolated_process.py',
                                 'tests/lib/source_snapshot.py'):
                    path = root / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(read_regular(REPO / relative, 65536))
                changed_path = source.parent / changed
                changed_path.write_bytes(changed_path.read_bytes() + b'// canonical-only edit\n')
                result = run_bounded(['/usr/bin/python3', '-I', '-S',
                    str(root / 'tests/power-deferred-regression.py')], timeout=5, maximum=8192)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(('Power source parity failed: ' + expected).encode(), result.stderr)

    def test_missing_target_and_drift_refuse_check(self):
        with tempfile.TemporaryDirectory(prefix='power-sync-') as value:
            root, source, destination, sentinel = self.fixture(Path(value))
            destination.write_bytes(b'drift')
            self.invoke(root, 'services/PowerService.qml', '--check', False)
            destination.unlink()
            self.invoke(root, 'services/PowerService.qml', '--check', False)
            self.invoke(root, 'services/PowerService.qml', '--write', True)
            self.invoke(root, 'services/PowerService.qml', '--check', True)


if __name__ == '__main__':
    unittest.main()
