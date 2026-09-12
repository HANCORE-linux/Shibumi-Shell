"""Resource ceilings for owned fixture descendants; never move the caller."""
import os
from pathlib import Path
import time
import uuid
from .source_snapshot import open_directory


class OwnedCgroup:
    def __init__(self, memory=512 * 1024 * 1024, tasks=64):
        if type(memory) is not int or not 16 * 1024 * 1024 <= memory <= 1024 * 1024 * 1024:
            raise ValueError("invalid fixture memory ceiling")
        if type(tasks) is not int or not 2 <= tasks <= 128:
            raise ValueError("invalid fixture task ceiling")
        self.parent_path = Path(f"/sys/fs/cgroup/user.slice/user-{os.getuid()}.slice/user@{os.getuid()}.service/app.slice")
        self.name = "shibumi-fixture-" + uuid.uuid4().hex
        self.memory, self.tasks = memory, tasks
        self.parent = self.directory = self.procs = None
        self.created = False

    def read(self, name):
        descriptor = os.open(name, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=self.directory)
        try:
            data = os.read(descriptor, 4097)
            if len(data) > 4096:
                raise RuntimeError("owned cgroup status limit")
            return data.decode().strip()
        finally:
            os.close(descriptor)

    def write(self, name, value):
        descriptor = os.open(name, os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
            dir_fd=self.directory)
        try:
            data = str(value).encode()
            if os.write(descriptor, data) != len(data):
                raise RuntimeError("owned cgroup short write")
        finally:
            os.close(descriptor)

    def __enter__(self):
        self.parent = open_directory(self.parent_path)
        try:
            if os.fstat(self.parent).st_uid != os.geteuid():
                raise RuntimeError("fixture cgroup parent is not delegated to this user")
            os.mkdir(self.name, mode=0o700, dir_fd=self.parent)
            self.created = True
            self.directory = os.open(self.name, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
                dir_fd=self.parent)
            self.inode = (os.fstat(self.directory).st_dev, os.fstat(self.directory).st_ino)
            for name, value in (("memory.max", self.memory), ("memory.swap.max", 0),
                                ("memory.oom.group", 1), ("pids.max", self.tasks)):
                self.write(name, value)
                if self.read(name) != str(value):
                    raise RuntimeError("fixture cgroup ceiling was not applied: " + name)
            self.procs = os.open("cgroup.procs", os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
                dir_fd=self.directory)
            return self
        except BaseException:
            self.close()
            raise

    def close(self):
        try:
            if self.directory is not None:
                kill_error = None
                try:
                    self.write("cgroup.kill", 1)
                except Exception as error:
                    kill_error = error
                deadline = time.monotonic() + 3
                while "populated 0" not in self.read("cgroup.events").splitlines():
                    if kill_error is not None:
                        raise RuntimeError("owned cgroup still populated after kill failure: " + self.name) from kill_error
                    if time.monotonic() >= deadline:
                        raise RuntimeError("owned fixture cgroup remained populated")
                    time.sleep(.02)
                current = os.stat(self.name, dir_fd=self.parent, follow_symlinks=False)
                if (current.st_dev, current.st_ino) != self.inode:
                    raise RuntimeError("owned fixture cgroup path was replaced")
                os.rmdir(self.name, dir_fd=self.parent)
                self.created = False
                if kill_error is not None:
                    raise kill_error
            elif self.created:
                # No process is ever launched before the directory is opened.
                os.rmdir(self.name, dir_fd=self.parent)
                self.created = False
        finally:
            for name in ("procs", "directory", "parent"):
                descriptor = getattr(self, name)
                if descriptor is not None:
                    os.close(descriptor)
                    setattr(self, name, None)

    def __exit__(self, *_):
        self.close()
