#!/usr/bin/env python3
"""Controlled leaf/group probes; never signal an unrelated process."""
import ctypes
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from lib.isolated_process import run_bounded, observe_owned_exit, finish_owned_group


class BoundedProcess(unittest.TestCase):
    def run_python(self, code, **kwargs):
        return run_bounded([sys.executable, "-c", code], **kwargs)

    def test_output_boundary_and_return_code(self):
        for length in (0, 63, 64):
            result = self.run_python(f'import os; os.write(1, b"x"*{length})', maximum=64)
            self.assertEqual((result.returncode, len(result.stdout)), (0, length))
        with self.assertRaisesRegex(RuntimeError, "output limit"):
            self.run_python('import os; os.write(1,b"x"*65)', maximum=64)
        with self.assertRaisesRegex(RuntimeError, "output limit"):
            self.run_python('import os; os.write(1,b"x"*32); os.write(2,b"x"*33)', maximum=64)
        result = self.run_python('import sys; sys.exit(7)')
        self.assertEqual(result.returncode, 7)

    def test_invalid_limits_refuse_before_spawn(self):
        for value in (-1, 0, float("nan"), float("inf"), True):
            with self.subTest(timeout=value), self.assertRaises(ValueError):
                self.run_python('raise RuntimeError("must not execute")', timeout=value)
        for value in (-1, 1.5, True, 4 * 1024 * 1024 + 1):
            with self.subTest(maximum=value), self.assertRaises(ValueError):
                self.run_python('raise RuntimeError("must not execute")', maximum=value)

    def test_closed_pipes_do_not_bypass_deadline(self):
        with self.assertRaisesRegex(RuntimeError, "deadline"):
            self.run_python('import os,time; os.close(1); os.close(2); time.sleep(20)', timeout=.15)

    def test_exited_parent_does_not_leave_group_worker(self):
        self.check_group_worker(False)

    def test_closed_pipe_worker_is_removed_after_success(self):
        self.check_group_worker(True)

    def test_shared_lifecycle_keeps_exited_leader_reserved(self):
        self.check_group_worker(True, lifecycle_api=True)

    def check_group_worker(self, closed_pipes, lifecycle_api=False):
        # Adopt only this test's orphan so it can be reaped by its exact PID.
        libc = ctypes.CDLL(None, use_errno=True)
        old = ctypes.c_int()
        self.assertEqual(libc.prctl(37, ctypes.byref(old), 0, 0, 0), 0)
        self.assertEqual(libc.prctl(36, 1, 0, 0, 0), 0)
        child = None
        try:
            with tempfile.TemporaryDirectory(prefix="owned-process-test-") as temporary:
                pidfile = Path(temporary) / "worker.pid"
                streams = ',stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL' if closed_pipes else ''
                code = ('import subprocess,sys,pathlib\n'
                    'child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(20)"]'
                    + streams + ')\n'
                    + f'pathlib.Path({str(pidfile)!r}).write_text(str(child.pid))\n')
                try:
                    if lifecycle_api:
                        process = subprocess.Popen([sys.executable, '-c', code],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
                        try:
                            self.assertEqual(observe_owned_exit(process, time.monotonic() + 1), 0)
                            self.assertIsNone(process.returncode, 'leader was reaped before group cleanup')
                        finally:
                            finish_owned_group(process)
                        with self.assertRaisesRegex(RuntimeError, 'already reaped'):
                            finish_owned_group(process)
                    elif closed_pipes:
                        self.assertEqual(self.run_python(code, timeout=.3).returncode, 0)
                    else:
                        with self.assertRaisesRegex(RuntimeError, "deadline"):
                            self.run_python(code, timeout=.3)
                finally:
                    if pidfile.is_file():
                        child = int(pidfile.read_text())
                deadline = time.monotonic() + 1
                while time.monotonic() < deadline:
                    pid, status = os.waitpid(child, os.WNOHANG)
                    if pid:
                        child = None
                        self.assertTrue(os.WIFSIGNALED(status))
                        self.assertEqual(os.WTERMSIG(status), signal.SIGKILL)
                        break
                    time.sleep(.01)
                self.assertIsNone(child, "owned group worker survived cleanup")
        finally:
            if child is not None:
                # Establish current unreaped-child ownership before signaling.
                os.waitid(os.P_PID, child, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                os.kill(child, signal.SIGKILL)
                os.waitpid(child, 0)
            self.assertEqual(libc.prctl(36, old.value, 0, 0, 0), 0)


if __name__ == "__main__":
    unittest.main()
