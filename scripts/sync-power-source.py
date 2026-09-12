"""Exact Power import-depth transform; no symlink traversal or in-place writes."""
import os
from pathlib import Path
import secrets
import stat
import sys

TARGETS = {
    'services/PowerService.qml': 'shared/power-state/Service.qml',
    'hancore.shibumi.power-state/Service.qml': 'shared/power-state/Service.qml',
    'services/PowerCommand.qml': 'shared/power-state/PowerCommand.qml',
    'hancore.shibumi.power-state/PowerCommand.qml': 'shared/power-state/PowerCommand.qml',
}
OLD = b'import "../../hancore.shibumi.state/runtime" as SuiteRuntime\n'
NEW = b'import "../hancore.shibumi.state/runtime" as SuiteRuntime\n'
FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def identity(value):
    return (value.st_dev, value.st_ino, value.st_mode, value.st_size,
            value.st_mtime_ns, value.st_ctime_ns)


def parent(path):
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('noncanonical sync path')
    fd = os.open('/', FLAGS)
    try:
        for name in path.parts[1:-1]:
            child = os.open(name, FLAGS, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def leaf(fd, name):
    try:
        value = os.stat(name, dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(value.st_mode):
        raise ValueError('sync leaf is not a regular file: ' + name)
    return identity(value)


def read(fd, name):
    opened = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=fd)
    try:
        before = os.fstat(opened)
        if not stat.S_ISREG(before.st_mode) or before.st_size > 256 * 1024:
            raise ValueError('invalid sync input')
        data = bytearray()
        while len(data) <= 256 * 1024:
            block = os.read(opened, min(65536, 256 * 1024 + 1 - len(data)))
            if not block:
                break
            data.extend(block)
        if len(data) > 256 * 1024 or identity(before) != identity(os.fstat(opened)):
            raise ValueError('changed or oversized sync input')
        if leaf(fd, name) != identity(before):
            raise ValueError('sync input replaced')
        return bytes(data)
    finally:
        os.close(opened)


def run(mode, root, target_name):
    if mode not in ('--paths', '--check', '--write') or target_name not in TARGETS:
        raise ValueError('invalid Power sync invocation')
    source = root / TARGETS[target_name]
    target = root / target_name
    source_fd = parent(source)
    try:
        data = read(source_fd, source.name)
    finally:
        os.close(source_fd)
    expected = data
    if source.name == 'Service.qml':
        if data.count(OLD) != 1:
            raise ValueError('Power canonical runtime import must be unique and exact')
        expected = data.replace(OLD, NEW)
    target_fd = parent(target)
    temporary = None
    try:
        previous = leaf(target_fd, target.name)
        if mode == '--paths':
            return
        if mode == '--check':
            if previous is None or read(target_fd, target.name) != expected:
                raise ValueError('Vendored Power service drift: ' + target_name)
            return
        temporary = '.' + target.name + '.sync-' + secrets.token_hex(12)
        output = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                         0o644, dir_fd=target_fd)
        try:
            remaining = memoryview(expected)
            while remaining:
                count = os.write(output, remaining)
                if count <= 0:
                    raise OSError('short sync write')
                remaining = remaining[count:]
            os.fchmod(output, 0o644)
            created = identity(os.fstat(output))
        finally:
            os.close(output)
        if leaf(target_fd, target.name) != previous:
            raise ValueError('sync destination replaced')
        if leaf(target_fd, temporary) != created:
            raise ValueError('sync temporary replaced')
        # Replace the directory entry, never truncate or chmod its referent.
        os.replace(temporary, target.name, src_dir_fd=target_fd, dst_dir_fd=target_fd)
        temporary = None
        published = leaf(target_fd, target.name)
        # rename can change ctime, but must preserve the held file identity/data.
        if published is None or published[:5] != created[:5]:
            raise ValueError('sync publication replaced')
    finally:
        if temporary is not None:
            os.unlink(temporary, dir_fd=target_fd)
        os.close(target_fd)


if __name__ == '__main__':
    try:
        run(sys.argv[1], Path(sys.argv[2]), sys.argv[3])
    except (OSError, ValueError, IndexError) as error:
        raise SystemExit(str(error))
