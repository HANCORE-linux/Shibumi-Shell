#!/usr/bin/env python3
"""Pinned native missed-hint fallback control in the maintained isolated runner.

This instruments only a private materialization of the admitted Omarchy 4.0.3
root. It is fixture evidence, not a production patch or desktop acceptance.
"""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from lib.isolated_files import read_regular
from lib.source_snapshot import open_directory

ROOT = Path(__file__).resolve().parents[1]
NATIVE_RUNNER = ROOT / "tests/native-runtime-regression.py"
EXPECTED_COMMIT = "0534987009061cbe2dacdde4ad564092ab698d12"
EXPECTED_NATIVE_FINGERPRINT = "2cd0ffb0c38f31868e28c3556f0efc530f4fcd04765856ec157bc070eac748a0"
SUCCESS_MARKER = b"ACTUAL NATIVE FALLBACK CHANGED DTO WITHOUT PUBLIC HINT PASSED"
EXPECTED_COUNTEREXAMPLE = "RuntimeError: last public hint did not capture selected failed bar"
FAILED_BAR_ASSIGNMENT = b"        shell.failedBarId = shell.activeBarId\n"
FAILED_BAR_HINT_MUTANT = FAILED_BAR_ASSIGNMENT + b"        shell.syncPluginApis()\n"
SHELL_IPC_ANCHOR = b'  IpcHandler {\n    target: "shell"'
SHELL_IPC_INSTRUMENTED = b'  IpcHandler {\n    id: fixtureShellIpc\n    target: "shell"'
FAILURE_MANIFEST = (json.dumps({
    "entryPoints": {"bar": "Bar.qml"},
    "id": "fixture.catalog-failure",
    "kinds": ["bar"],
    "name": "Catalog failing bar fixture",
    "schemaVersion": 1,
    "version": "1.0.0",
}, sort_keys=True, separators=(",", ":")) + "\n").encode()
FAILURE_BAR = b"import QtQuick\nItem { required property string fixtureCatalogFailure }\n"


def load_native_runner():
    spec = importlib.util.spec_from_file_location("shibumi_native_fixture", NATIVE_RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError("maintained native runner cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if (module.COMMIT != EXPECTED_COMMIT
            or module.SHELL_FINGERPRINT != EXPECTED_NATIVE_FINGERPRINT):
        raise RuntimeError("maintained native runner pin drift")
    return module


def write_private_regular(path, data, maximum=1024 * 1024):
    """Replace one already-materialized private regular file without following it."""
    if not isinstance(data, bytes) or len(data) > maximum:
        raise ValueError("invalid private staged replacement")
    parent = open_directory(path.parent)
    try:
        descriptor = os.open(path.name, os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
            dir_fd=parent)
    finally:
        os.close(parent)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise ValueError("private staged replacement is not unique regular file")
        os.ftruncate(descriptor, 0)
        offset = 0
        while offset < len(data):
            written = os.write(descriptor, data[offset:])
            if written <= 0:
                raise OSError("short private staged write")
            offset += written
    finally:
        os.close(descriptor)
    if read_regular(path, maximum) != data:
        raise RuntimeError("private staged replacement verification failed")


def create_private_regular(path, data, mode=0o600):
    if not isinstance(data, bytes) or len(data) > 65536:
        raise ValueError("invalid fallback fixture body")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
        mode)
    try:
        offset = 0
        while offset < len(data):
            written = os.write(descriptor, data[offset:])
            if written <= 0:
                raise OSError("short fallback fixture write")
            offset += written
    finally:
        os.close(descriptor)
    if read_regular(path, 65536) != data:
        raise RuntimeError("fallback fixture creation verification failed")


def replace_exact(path, old, new):
    raw = read_regular(path, 1024 * 1024)
    if raw.count(old) != 1:
        raise RuntimeError("private native mutation anchor drift")
    updated = raw.replace(old, new)
    write_private_regular(path, updated)
    return updated


def fixture_capture():
    fixture_root = ROOT / "tests/fixtures/native-runtime"
    observer = read_regular(fixture_root / "CatalogFallbackObserver.qmlpart", 65536)
    probe = read_regular(fixture_root / "catalog-fallback-probe.py", 65536)
    bodies = {
        "CatalogFallbackObserver.qmlpart": observer,
        "catalog-fallback-probe.py": probe,
        "fixture.catalog-failure/manifest.json": FAILURE_MANIFEST,
        "fixture.catalog-failure/Bar.qml": FAILURE_BAR,
    }
    records = [{"path": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
        for name, data in sorted(bodies.items())]
    fingerprint = hashlib.sha256(json.dumps(records, sort_keys=True,
        separators=(",", ":")).encode()).hexdigest()
    print(json.dumps({"fallbackFixtureFingerprint": fingerprint,
        "fallbackFixtureFiles": records}, sort_keys=True), flush=True)
    return observer, probe


def instrument(base, observer, probe):
    shell_path = base / "omarchy/shell/shell.qml"
    shell = read_regular(shell_path, 1024 * 1024)
    if shell.count(SHELL_IPC_ANCHOR) != 1 or shell.count(SHELL_IPC_INSTRUMENTED) != 0:
        raise RuntimeError("private observer IPC anchor drift")
    if not shell.endswith(b"}\n"):
        raise RuntimeError("private native root close drift")
    shell = shell.replace(SHELL_IPC_ANCHOR, SHELL_IPC_INSTRUMENTED)
    shell = shell[:-2] + observer + b"}\n"
    if shell.count(FAILED_BAR_ASSIGNMENT) != 1:
        raise RuntimeError("private failedBarId anchor drift")
    write_private_regular(shell_path, shell)
    write_private_regular(base / "run.py", probe, 65536)

    failure = base / "home/.config/omarchy/plugins/fixture.catalog-failure"
    failure.mkdir(mode=0o700)
    create_private_regular(failure / "manifest.json", FAILURE_MANIFEST)
    create_private_regular(failure / "Bar.qml", FAILURE_BAR)
    print(json.dumps({
        "instrumentedPrivateShellSha256": hashlib.sha256(shell).hexdigest(),
        "instrumentationRoute": "read-only observer and separate fixture IPC in private staging",
        "productionNativeSourceChanged": False,
    }, sort_keys=True), flush=True)
    return shell_path, hashlib.sha256(shell).hexdigest()


def run_counterexample(native, base):
    captured = io.StringIO()
    error = None
    with contextlib.redirect_stdout(captured):
        try:
            native.run(base, (SUCCESS_MARKER,))
        except RuntimeError as caught:
            error = caught
    output = captured.getvalue()
    print(output, end="", flush=True)
    if error is None:
        raise RuntimeError("fallback hint counterexample unexpectedly passed")
    if str(error) != "isolated native fixture failed: 1":
        raise RuntimeError("fallback hint counterexample failed outside intended assertion") from error
    if (output.count(EXPECTED_COUNTEREXAMPLE) != 1
            or not output.rstrip().endswith(EXPECTED_COUNTEREXAMPLE)):
        raise RuntimeError("fallback hint counterexample intended diagnostic mismatch") from error
    if SUCCESS_MARKER.decode() in output:
        raise RuntimeError("fallback hint counterexample emitted success marker")
    print("CALIBRATED LATER PUBLIC HINT COUNTEREXAMPLE FAILED AS INTENDED", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-shell", required=True, type=Path)
    args = parser.parse_args()

    native = load_native_runner()
    admitted = native.admitted_native(args.native_shell)
    observer, probe = fixture_capture()
    with tempfile.TemporaryDirectory(prefix="shibumi-native-catalog-fallback-", dir="/tmp") as temporary:
        base = Path(temporary)
        native.stage(base, admitted)
        shell_path, positive_hash = instrument(base, observer, probe)

        print("NATIVE CATALOG FALLBACK POSITIVE", flush=True)
        native.run(base, (SUCCESS_MARKER,))

        replace_exact(shell_path, FAILED_BAR_ASSIGNMENT, FAILED_BAR_HINT_MUTANT)
        print("NATIVE CATALOG FALLBACK LATER-HINT COUNTEREXAMPLE", flush=True)
        run_counterexample(native, base)

        restored = replace_exact(shell_path, FAILED_BAR_HINT_MUTANT, FAILED_BAR_ASSIGNMENT)
        if hashlib.sha256(restored).hexdigest() != positive_hash:
            raise RuntimeError("private native root was not restored byte-for-byte")
        print("NATIVE CATALOG FALLBACK RESTORED POSITIVE", flush=True)
        native.run(base, (SUCCESS_MARKER,))
    if base.exists():
        raise RuntimeError("owned fallback fixture directory remains")
    print("NATIVE CATALOG FALLBACK POSITIVE/NEGATIVE/RESTORED PASSED; OWNED DIRECTORY REMOVED", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        raise SystemExit("native-catalog-fallback-regression: " + str(error)) from error
