#!/usr/bin/env python3
"""Over-limit probes confined to new owned cgroups and bounded tmpfs."""
from pathlib import Path
import sys
import unittest
from unittest import mock

sys.dont_write_bytecode = True
from lib.owned_cgroup import OwnedCgroup
from lib.isolated_process import run_bounded

ROOT = Path(__file__).resolve().parent
LAUNCHER = ROOT / "lib/cgroup_exec.py"


def launch(group, command, timeout=6):
    return run_bounded([sys.executable, str(LAUNCHER), str(group.procs), *command],
        env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}, timeout=timeout,
        maximum=16384, pass_fds=(group.procs,))


class IsolatedResources(unittest.TestCase):
    def test_memory_limit_kills_only_owned_group(self):
        membership = Path("/proc/self/cgroup").read_bytes()
        with OwnedCgroup(memory=64 * 1024 * 1024, tasks=8) as group:
            path = group.parent_path / group.name
            result = launch(group, [sys.executable, "-c",
                'blocks=[]\nfor i in range(32): blocks.append(bytearray(16*1024*1024))'])
            self.assertNotEqual(result.returncode, 0)
            events = dict(line.split() for line in group.read("memory.events").splitlines())
            self.assertGreater(int(events["oom_kill"]), 0, "controlled allocation did not reach its cgroup ceiling")
        self.assertFalse(path.exists())
        self.assertEqual(Path("/proc/self/cgroup").read_bytes(), membership)

    def test_task_limit_and_worker_cleanup(self):
        with OwnedCgroup(memory=128 * 1024 * 1024, tasks=8) as group:
            path = group.parent_path / group.name
            code = ('import errno,subprocess\nworkers=[]\n'
                'try:\n'
                ' for i in range(32): workers.append(subprocess.Popen(["/usr/bin/sleep","10"],'
                'stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))\n'
                'except OSError as error:\n'
                ' if error.errno!=errno.EAGAIN or not workers: raise\n'
                ' print("owned task ceiling reached",flush=True)\n'
                'else: raise RuntimeError("task ceiling bypassed")\n')
            result = launch(group, [sys.executable, "-c", code])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b"owned task ceiling reached", result.stdout)
            events = dict(line.split() for line in group.read("pids.events").splitlines())
            self.assertGreater(int(events["max"]), 0)
        self.assertFalse(path.exists())

    def test_failed_kill_still_removes_empty_owned_group(self):
        membership = Path("/proc/self/cgroup").read_bytes()
        group = OwnedCgroup(memory=64 * 1024 * 1024, tasks=8)
        group.__enter__()
        path = group.parent_path / group.name
        original_write = group.write
        def fail_kill(name, value):
            if name == "cgroup.kill":
                raise PermissionError("controlled owned kill failure")
            original_write(name, value)
        try:
            with mock.patch.object(group, "write", side_effect=fail_kill):
                with self.assertRaisesRegex(PermissionError, "controlled owned kill failure"):
                    group.close()
            self.assertFalse(path.exists())
            self.assertEqual(Path("/proc/self/cgroup").read_bytes(), membership)
        finally:
            group.close()

    def test_tmpfs_ceiling_refuses_aggregate_writes(self):
        code = ('import errno\n'
            'try:\n'
            ' for i in range(16):\n'
            '  with open("/quota/"+str(i),"wb") as f: f.write(b"x"*1024*1024)\n'
            'except OSError as error:\n'
            ' if error.errno!=errno.ENOSPC: raise\n'
            ' print("owned tmpfs ceiling reached")\n'
            'else: raise RuntimeError("tmpfs ceiling bypassed")\n')
        command = ["/usr/bin/bwrap", "--die-with-parent", "--unshare-user", "--unshare-pid", "--unshare-ipc",
            "--unshare-net", "--new-session",
            "--ro-bind", "/usr", "/usr", "--symlink", "usr/bin", "/bin",
            "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
            "--proc", "/proc", "--dev", "/dev", "--size", str(4 * 1024 * 1024),
            "--tmpfs", "/quota", "--disable-userns", "/usr/bin/python3", "-c", code]
        with OwnedCgroup(memory=64 * 1024 * 1024, tasks=8) as group:
            path = group.parent_path / group.name
            result = launch(group, command)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b"owned tmpfs ceiling reached", result.stdout)
        self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
