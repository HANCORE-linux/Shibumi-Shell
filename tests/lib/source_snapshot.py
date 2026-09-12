"""Bounded regular-file snapshots for explicitly selected fixture sources."""
import hashlib
import json
import os
from pathlib import Path
import stat

DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK


def identity(value):
    return (value.st_dev, value.st_ino, value.st_mode, value.st_size,
            value.st_mtime_ns, value.st_ctime_ns)


def open_directory(path):
    """Resolve every absolute component through no-follow directory handles."""
    absolute = Path(path).absolute()
    if ".." in absolute.parts:
        raise ValueError("noncanonical source directory")
    descriptor = os.open("/", DIR_FLAGS)
    try:
        for part in absolute.parts[1:]:
            child = os.open(part, DIR_FLAGS, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def snapshot(path):
    """At most 2048 nodes, 16 MiB aggregate, 1 MiB/file and depth16.

    Source bodies are retained only in memory; callers copy those admitted
    bytes, never reopen the original paths for execution. This is not a Git
    commit claim for an uncommitted suite worktree.
    """
    files = {}
    directories = set()
    count = 0
    total = 0

    def visit(descriptor, prefix, depth):
        nonlocal count, total
        if depth > 16:
            raise ValueError("source nesting limit")
        before_directory = identity(os.fstat(descriptor))
        # scandir streams entries; do not allocate an unbounded directory list.
        with os.scandir(descriptor) as entries:
            for entry in entries:
                count += 1
                if count > 2048:
                    raise ValueError("source entry limit")
                name = entry.name
                relative = prefix + name
                metadata = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
                if stat.S_ISDIR(metadata.st_mode):
                    child = os.open(name, DIR_FLAGS, dir_fd=descriptor)
                    try:
                        if identity(os.fstat(child)) != identity(metadata):
                            raise ValueError("source directory changed before open")
                        directories.add(relative)
                        visit(child, relative + "/", depth + 1)
                    finally:
                        os.close(child)
                elif stat.S_ISREG(metadata.st_mode):
                    if metadata.st_size > 1024 * 1024:
                        raise ValueError("source file limit")
                    total += metadata.st_size
                    if total > 16 * 1024 * 1024:
                        raise ValueError("source aggregate limit")
                    child = os.open(name, FILE_FLAGS, dir_fd=descriptor)
                    try:
                        if identity(os.fstat(child)) != identity(metadata):
                            raise ValueError("source file changed before open")
                        data = bytearray()
                        while True:
                            chunk = os.read(child, min(65536, metadata.st_size - len(data) + 1))
                            if not chunk:
                                break
                            data.extend(chunk)
                            if len(data) > metadata.st_size:
                                raise ValueError("source grew during read")
                        if len(data) != metadata.st_size or identity(os.fstat(child)) != identity(metadata):
                            raise ValueError("source changed during read")
                        files[relative] = (bytes(data), bool(metadata.st_mode & 0o111))
                    finally:
                        os.close(child)
                else:
                    raise ValueError("nonregular source entry: " + relative)
        if identity(os.fstat(descriptor)) != before_directory:
            raise ValueError("source directory changed during scan")

    descriptor = open_directory(path)
    try:
        visit(descriptor, "", 0)
    finally:
        os.close(descriptor)
    expected_directories = {parent.as_posix() for name in files
        for parent in Path(name).parents if parent != Path(".")}
    if directories != expected_directories:
        raise ValueError("source contains an unbound empty directory")
    return files


def inventory(files):
    return [{"path": name, "sha256": hashlib.sha256(data).hexdigest(),
             "size": len(data), "executable": executable}
            for name, (data, executable) in sorted(files.items())]


def fingerprint(files):
    raw = json.dumps(inventory(files), sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def materialize(files, destination):
    destination = Path(destination)
    for name, (data, executable) in files.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)
        target.chmod(0o755 if executable else 0o644)
