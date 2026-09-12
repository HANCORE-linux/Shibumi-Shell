#!/usr/bin/env python3
"""Owned inert filesystem probes; never execute the captured source bytes."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
from lib.source_snapshot import snapshot, fingerprint, materialize
from lib.isolated_process import run_bounded


class SourceSnapshots(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="native-source-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "one.qml").write_bytes(b"inert source\n")

    def test_exact_copy_and_identity(self):
        first = snapshot(self.source)
        materialize(first, self.root / "copy")
        self.assertEqual(fingerprint(snapshot(self.root / "copy")), fingerprint(first))
        (self.source / "one.qml").chmod(0o755)
        self.assertNotEqual(fingerprint(snapshot(self.source)), fingerprint(first))
        (self.source / "one.qml").chmod(0o644)
        self.assertEqual(fingerprint(snapshot(self.source)), fingerprint(first))

    def test_symlink_nodes_and_ancestors_refuse(self):
        (self.source / "link").symlink_to(self.root / "sentinel")
        with self.assertRaisesRegex(ValueError, "nonregular"):
            snapshot(self.source)
        (self.source / "link").unlink()
        alias = self.root / "alias"
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(OSError):
            snapshot(alias)
        with self.assertRaises(OSError):
            snapshot(alias / "child")
        self.assertEqual(len(snapshot(self.source)), 1)

    def test_empty_directories_fifo_and_large_file_refuse(self):
        (self.source / "empty").mkdir()
        with self.assertRaisesRegex(ValueError, "empty directory"):
            snapshot(self.source)
        (self.source / "empty").rmdir()
        os.mkfifo(self.source / "fifo", 0o600)
        with self.assertRaisesRegex(ValueError, "nonregular"):
            snapshot(self.source)
        (self.source / "fifo").unlink()
        with (self.source / "large").open("wb") as stream:
            stream.truncate(1024 * 1024 + 1)
        with self.assertRaisesRegex(ValueError, "file limit"):
            snapshot(self.source)

    def test_aggregate_boundary(self):
        aggregate = self.root / "aggregate"
        aggregate.mkdir()
        for index in range(16):
            with (aggregate / str(index)).open("wb") as stream:
                stream.truncate(1024 * 1024)
        self.assertEqual(len(snapshot(aggregate)), 16)
        (aggregate / "over").write_bytes(b"x")
        with self.assertRaisesRegex(ValueError, "aggregate limit"):
            snapshot(aggregate)

    def test_changed_file_refuses_captured_bytes(self):
        original_read = os.read
        changed = False
        def mutate_after_read(descriptor, length):
            nonlocal changed
            data = original_read(descriptor, length)
            if not changed:
                changed = True
                (self.source / "one.qml").write_bytes(b"changed source\n")
            return data
        with mock.patch("lib.source_snapshot.os.read", side_effect=mutate_after_read):
            with self.assertRaisesRegex(ValueError, "source (grew|changed)"):
                snapshot(self.source)
        self.assertTrue(changed)
        self.assertEqual(snapshot(self.source)["one.qml"][0], b"changed source\n")

    def test_entry_and_nesting_bounds(self):
        for index in range(2048):
            (self.source / str(index)).touch()
        with self.assertRaisesRegex(ValueError, "entry limit"):
            snapshot(self.source)
        deep = self.root / "deep"
        leaf = deep.joinpath(*(["child"] * 17))
        leaf.mkdir(parents=True)
        (leaf / "inert").touch()
        with self.assertRaisesRegex(ValueError, "nesting limit"):
            snapshot(deep)

    def test_public_native_admission_refuses_unpinned_source(self):
        checker = Path(__file__).with_name("native-runtime-regression.py")
        result = run_bounded([sys.executable, str(checker), "--native-shell", str(self.source), "--admit-only"],
            timeout=4, maximum=8192)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"does not match pinned", result.stderr)
        self.assertNotIn(b"namespace", result.stdout)


if __name__ == "__main__":
    unittest.main()
