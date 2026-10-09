#!/usr/bin/env python3
"""Print a revision-bound forward manifest; validate it with tests/lib/baselines.sh."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

root = Path(sys.argv[1])
revision = sys.argv[2]
if not root.is_absolute() or root.resolve(strict=True) != root:
    raise SystemExit("checkout must be absolute, canonical and unlinked")
if not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit("expected a full commit SHA")
env = dict(os.environ, LC_ALL="C", GIT_OPTIONAL_LOCKS="0")
if any(key.startswith("GIT_") for key in os.environ):
    raise SystemExit("ambient Git overrides are not accepted")
def git(*args):
    return subprocess.check_output(["git", "--no-optional-locks", "-C", str(root), *args], env=env)
def identity():
    if Path(os.fsdecode(git("rev-parse", "--show-toplevel")).strip()) != root:
        raise SystemExit("checkout root mismatch")
    if git("status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none", "--ignored"):
        raise SystemExit("checkout is not clean")
    if git("rev-parse", "HEAD").decode().strip() != revision:
        raise SystemExit("checkout revision mismatch")
    return git("rev-parse", "HEAD^{tree}")
def digest(data):
    return hashlib.sha256(data).hexdigest()
tree = identity()
subtrees = []
for name in ("shell", "bin", "config"):
    directory = root / name
    if directory.is_symlink() or not directory.is_dir():
        raise SystemExit("missing or linked subtree: " + name)
    paths = sorted(subprocess.check_output([
        "find", str(directory), "-mindepth", "1", "-printf", r"%P\0"
    ], env=env).split(b"\0")[:-1])
    if not paths:
        raise SystemExit("empty subtree: " + name)
    structure = bytearray()
    files = []
    for relative in paths:
        path = directory / os.fsdecode(relative)
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            kind = b"directory"
        elif stat.S_ISREG(mode):
            kind = b"file"
            files.append(os.fsdecode(relative))
        else:
            raise SystemExit("unsupported entry: " + str(path))
        executable = b"1" if os.access(path, os.X_OK) else b"0"
        structure.extend(relative + b"\0" + kind + b"\0" + executable + b"\0")
    if not files:
        raise SystemExit("subtree has no regular files: " + name)
    content = subprocess.check_output(["sha256sum", "--", *files], cwd=directory, env=env)
    subtrees.append(dict(path=name, entryPolicy="regular-files", entryCount=len(paths),
        inventorySha256=digest(b"\0".join(paths) + b"\0"),
        structureSha256=digest(structure), contentSha256=digest(content)))
if identity() != tree:
    raise SystemExit("checkout changed during generation")
print(json.dumps(dict(schemaVersion=2, id="forward-compat-" + revision[:8],
    profile="forward-compat", repository="https://github.com/basecamp/omarchy",
    sourceRevision=revision, provenance=dict(kind="git", revision=revision),
    quickshellPackage=dict(name="quickshell", version="0.3.1-1"), subtrees=subtrees), indent=2))
