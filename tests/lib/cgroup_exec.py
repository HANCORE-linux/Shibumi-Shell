"""Migrate only this owned launcher, close its capability FD, then exec."""
import os
import sys

if len(sys.argv) < 3:
    raise SystemExit("owned cgroup launcher arguments missing")
descriptor = int(sys.argv[1])
try:
    if os.write(descriptor, b"0") != 1:
        raise RuntimeError("owned cgroup migration failed")
finally:
    os.close(descriptor)
os.execv(sys.argv[2], sys.argv[2:])
