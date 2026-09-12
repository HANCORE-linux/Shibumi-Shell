#!/usr/bin/python3
"""Read one exact Reactor input, bounded before buffering; no shell or writes."""
import json
import os
import stat
import sys

SOURCES = {
    "theme": (".local/state/omarchy/current/theme.name", 512),
    "event": (".cache/qs-reactor-event", 4096),
    "quotes": (".config/shibumi/quotes.txt", 65536),
}


def identity(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def read_source(home, kind):
    relative, limit = SOURCES[kind]
    if not home.startswith("/"):
        raise ValueError("home")
    parts = (home.rstrip("/") + "/" + relative).split("/")[1:]
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError("path")
    directory = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in parts[:-1]:
            following = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
                                | os.O_CLOEXEC, dir_fd=directory)
            os.close(directory)
            directory = following
        descriptor = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
                             | os.O_CLOEXEC, dir_fd=directory)
        try:
            before = os.fstat(descriptor)
            if not stat.S_ISREG(before.st_mode) or before.st_size > limit:
                raise ValueError("type-or-size")
            data = bytearray()
            while len(data) <= limit:
                block = os.read(descriptor, min(8192, limit + 1 - len(data)))
                if not block:
                    break
                data.extend(block)
            if len(data) > limit or identity(before) != identity(os.fstat(descriptor)):
                raise ValueError("size-or-change")
            return bytes(data).decode("utf-8", errors="strict")
        finally:
            os.close(descriptor)
    finally:
        os.close(directory)


def main():
    try:
        if len(sys.argv) != 3 or sys.argv[1] not in SOURCES:
            raise ValueError("arguments")
        result = {"ok": True, "text": read_source(sys.argv[2], sys.argv[1])}
        code = 0
    except (OSError, ValueError, KeyError):
        # No paths, file contents or exception messages cross the failure seam.
        result, code = {"ok": False, "text": ""}, 1
    # Even all-control-byte input produces at most 6*limit + fixed JSON bytes.
    payload = (json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    sys.stdout.buffer.write(payload)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
