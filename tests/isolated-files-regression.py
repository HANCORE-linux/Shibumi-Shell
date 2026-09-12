#!/usr/bin/env python3
"""Bounded reads and pathname replacement use only owned inert files."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
from lib.isolated_files import read_regular


class IsolatedFiles(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="isolated-file-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.path = self.root / "value"

    def test_boundaries_and_tail(self):
        for length in (0, 63, 64):
            self.path.write_bytes(b"x" * length)
            self.assertEqual(len(read_regular(self.path, 64)), length)
        self.path.write_bytes(b"x" * 64 + b"y")
        with self.assertRaisesRegex(ValueError, "file limit"):
            read_regular(self.path, 64)
        self.assertEqual(read_regular(self.path, 4, tail=True), b"xxxy")

    def test_symlinks_and_nonregular_nodes_refuse(self):
        target = self.root / "target"
        target.write_bytes(b"inert")
        self.path.symlink_to(target)
        with self.assertRaises(OSError):
            read_regular(self.path)
        self.path.unlink()
        os.mkfifo(self.path, 0o600)
        with self.assertRaisesRegex(ValueError, "not regular"):
            read_regular(self.path)

    def test_replacement_after_open_does_not_reopen_path(self):
        self.path.write_bytes(b"original")
        replacement = self.root / "replacement"
        replacement.write_bytes(b"x" * 65)
        original_open = os.open
        replaced = False
        def replace_after_open(name, flags, *args, **kwargs):
            nonlocal replaced
            descriptor = original_open(name, flags, *args, **kwargs)
            if name == "value" and not replaced:
                replaced = True
                replacement.replace(self.path)
            return descriptor
        with mock.patch("lib.isolated_files.os.open", side_effect=replace_after_open):
            self.assertEqual(read_regular(self.path, 64), b"original")
        self.assertTrue(replaced)
        with self.assertRaisesRegex(ValueError, "file limit"):
            read_regular(self.path, 64)


if __name__ == "__main__":
    unittest.main()
