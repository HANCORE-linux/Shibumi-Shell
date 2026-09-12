"""No-follow, descriptor-bound reads of regular owned fixture files."""
import os
from pathlib import Path
import stat
from .source_snapshot import open_directory, identity


def read_regular(path, maximum=1024 * 1024, *, tail=False):
    if type(maximum) is not int or not 0 <= maximum <= 16 * 1024 * 1024:
        raise ValueError("invalid owned-file read bound")
    path = Path(path)
    parent = open_directory(path.parent)
    try:
        descriptor = os.open(path.name, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=parent)
    finally:
        os.close(parent)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise ValueError("owned fixture file is not regular")
        if not tail and before.st_size > maximum:
            raise ValueError("owned fixture file limit")
        if tail:
            os.lseek(descriptor, max(0, before.st_size - maximum), os.SEEK_SET)
        data = bytearray()
        while True:
            chunk = os.read(descriptor, min(65536, maximum - len(data) + 1))
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > maximum:
                raise ValueError("owned fixture file limit")
        if identity(os.fstat(descriptor)) != identity(before):
            raise ValueError("owned fixture file changed during read")
        return bytes(data)
    finally:
        os.close(descriptor)
