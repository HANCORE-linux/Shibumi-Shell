#!/usr/bin/env python3
"""Pinned-native NativeCatalog cadence, cleanup, CPU and warm-PSS regression.

The maintained native-runtime runner supplies exact 4.0.3 admission, private
staging, Bubblewrap namespaces and the owned cgroup. Measurements are isolated
fixture evidence only; they are not physical desktop or real-consumer acceptance.
"""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import re
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
SUCCESS_MARKER = b"PINNED NATIVE CATALOG RESOURCE POSITIVE PASSED"
CLEANUP_MARKER = b"PINNED NATIVE CATALOG RESOURCE INNER CLEANUP/LOG PASSED"
STOP_ANCHOR = b"    reconcile.stop()"
TIMER_ANCHOR = b"    repeat: false"
OLD_TIMER = b"    repeat: true\n    running: root.active"
MUTANTS = (
    ("OLD CONTINUOUS TIMER", "catalog request started before five-second post-drain cadence",
     "catalog", ((STOP_ANCHOR, b"    // Resource control: old timer was not stopped"),
                 (TIMER_ANCHOR, OLD_TIMER))),
    ("NO CUSTODIAN", "catalog IPC bypassed setsid custodian", "helper",
     ((b"raise SystemExit(guarded(lambda: main(group_owner=True)))",
       b"raise SystemExit(main(group_owner=False))"),)),
    ("NO SETSID", "catalog custodian did not create an owned session", "helper",
     ((b"            os.setsid()", b"            os.setpgid(0, 0)"),)),
    ("EXTRA WORKER", "catalog acquisition exceeded three processes", "helper",
     ((b"            status = 1\n            try:\n                job()",
       b"            if os.fork() == 0:\n"
       b"                while True:\n"
       b"                    signal.pause()\n"
       b"            status = 1\n            try:\n                job()"),)),
    ("HOST CPU BURN", "warm catalog cycle exceeded CPU ceiling", "catalog",
     ((b"    op.event = { output: output, ok: ok === true }",
       b"    var fixtureBurnUntil = Date.now() + 1000\n"
       b"    while (Date.now() < fixtureBurnUntil) {}\n"
       b"    op.event = { output: output, ok: ok === true }"),)),
    ("HELPER CPU BURN", "warm catalog cycle exceeded CPU ceiling", "helper",
     ((b"    text = raw.decode(\"utf-8\", errors=\"strict\")",
       b"    fixture_burn_until = time.process_time() + 0.6\n"
       b"    while time.process_time() < fixture_burn_until:\n"
       b"        pass\n"
       b"    text = raw.decode(\"utf-8\", errors=\"strict\")"),)),
    ("PSS RETENTION", "warm catalog cycles exceeded retained PSS ceiling", "catalog",
     ((b"  property var _publication: null",
       b"  property var _publication: null\n  property var _fixtureRetention: []"),
      (b"    op.event = { output: output, ok: ok === true }",
       b"    var fixtureRetained = new Uint8Array(2 * 1024 * 1024)\n"
       b"    for (var offset = 0; offset < fixtureRetained.length; offset += 4096)\n"
       b"      fixtureRetained[offset] = (serial + offset) & 255\n"
       b"    _fixtureRetention.push(fixtureRetained)\n"
       b"    op.event = { output: output, ok: ok === true }"))),
)


def load_native_runner():
    spec = importlib.util.spec_from_file_location("shibumi_native_resource_fixture",
                                                  NATIVE_RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError("maintained native runner cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if (module.COMMIT != EXPECTED_COMMIT
            or module.SHELL_FINGERPRINT != EXPECTED_NATIVE_FINGERPRINT):
        raise RuntimeError("maintained native runner pin drift")
    return module


def write_private_regular(path, data, maximum=1024 * 1024):
    """Replace one private staged regular file without following path leaves."""
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


def install_probe(base):
    path = ROOT / "tests/fixtures/native-runtime/catalog-resource-probe.py"
    probe = read_regular(path, 128 * 1024)
    write_private_regular(base / "run.py", probe, 128 * 1024)
    print("CATALOG_RESOURCE_PROBE " + hashlib.sha256(probe).hexdigest(), flush=True)


def mutate_private(path, replacements):
    raw = read_regular(path, 1024 * 1024)
    mutated = raw
    for old, new in replacements:
        if mutated.count(old) != 1 and old != STOP_ANCHOR:
            raise RuntimeError("catalog resource mutation anchor drift: " + repr(old))
        if old == STOP_ANCHOR and mutated.count(old) != 2:
            raise RuntimeError("catalog resource stop anchor drift")
        mutated = mutated.replace(old, new)
    write_private_regular(path, mutated)
    return raw, hashlib.sha256(raw).hexdigest()


def restore_private(path, original, digest):
    write_private_regular(path, original)
    if hashlib.sha256(read_regular(path, 1024 * 1024)).hexdigest() != digest:
        raise RuntimeError("private catalog resource source was not restored byte-for-byte")


def run_counterexample(native, base, label, expected):
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
        raise RuntimeError(label.lower() + " resource control unexpectedly passed")
    if str(error) != "isolated native fixture failed: 1":
        raise RuntimeError(label.lower() + " control failed outside intended assertion") from error
    diagnostic_prefix = "RuntimeError: " + expected
    diagnostic_lines = [
        line for line in output.splitlines()
        if line.startswith(diagnostic_prefix)
    ]
    cleanup = CLEANUP_MARKER.decode()
    intended_diagnostic = len(diagnostic_lines) == 1
    if intended_diagnostic and label == "PSS RETENTION":
        intended_diagnostic = re.fullmatch(
            re.escape(diagnostic_prefix)
            + r"(?:: baseline=\d+ KiB samples=\[\d+(?:, \d+)*\]"
              r" growth=\d+ KiB)?",
            diagnostic_lines[0],
        ) is not None
    elif intended_diagnostic:
        intended_diagnostic = diagnostic_lines[0] == diagnostic_prefix
    if (not intended_diagnostic
            or not output.rstrip().endswith(diagnostic_lines[0])
            or output.count(cleanup) != 1
            or SUCCESS_MARKER.decode() in output
            or "During handling of the above exception" in output
            or "The above exception was the direct cause" in output):
        raise RuntimeError(label.lower() + " control intended diagnostic/cleanup mismatch") from error
    print("CALIBRATED " + label + " FAILED AS INTENDED", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-shell", required=True, type=Path)
    args = parser.parse_args()

    native = load_native_runner()
    admitted = native.admitted_native(args.native_shell)
    with tempfile.TemporaryDirectory(prefix="shibumi-native-catalog-resource-",
                                     dir="/tmp") as temporary:
        base = Path(temporary)
        native.stage(base, admitted)
        install_probe(base)
        plugin = (base / "home/.config/omarchy/plugins"
                  / "hancore.shibumi.control-center")
        paths = {"catalog": plugin / "NativeCatalog.qml",
                 "helper": plugin / "manager/shibumi-native-catalog"}

        print("NATIVE CATALOG RESOURCE POSITIVE", flush=True)
        native.run(base, (SUCCESS_MARKER, CLEANUP_MARKER))

        cpu_anchor = b"    text = raw.decode(\"utf-8\", errors=\"strict\")"
        cpu_allowance = (b"    fixture_burn_until = time.process_time() + 0.15\n"
                         b"    while time.process_time() < fixture_burn_until:\n"
                         b"        pass\n" + cpu_anchor)
        original, original_hash = mutate_private(
            paths["helper"], ((cpu_anchor, cpu_allowance),))
        try:
            print("NATIVE CATALOG RESOURCE HELPER CPU BELOW-CEILING CONTROL",
                  flush=True)
            native.run(base, (SUCCESS_MARKER, CLEANUP_MARKER))
            print("CALIBRATED HELPER CPU BELOW CEILING PASSED", flush=True)
        finally:
            restore_private(paths["helper"], original, original_hash)

        for label, diagnostic, target, replacements in MUTANTS:
            original, original_hash = mutate_private(paths[target], replacements)
            try:
                print("NATIVE CATALOG RESOURCE " + label + " COUNTEREXAMPLE", flush=True)
                run_counterexample(native, base, label, diagnostic)
            finally:
                restore_private(paths[target], original, original_hash)

        print("NATIVE CATALOG RESOURCE RESTORED POSITIVE", flush=True)
        native.run(base, (SUCCESS_MARKER, CLEANUP_MARKER))
    if base.exists():
        raise RuntimeError("owned catalog resource fixture directory remains")
    print("PINNED NATIVE CATALOG RESOURCE POSITIVE/NEGATIVE/RESTORED PASSED; "
          "OWNED DIRECTORY REMOVED", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        raise SystemExit("native-catalog-resource-regression: " + str(error)) from error
