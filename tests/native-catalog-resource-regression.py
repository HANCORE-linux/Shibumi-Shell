#!/usr/bin/env python3
"""Pinned-native NativeCatalog cadence, cleanup, CPU and warm-PSS regression.

The maintained native-runtime runner supplies exact 4.0.4 admission, private
staging, Bubblewrap namespaces and the owned cgroup. Measurements are isolated
fixture evidence only; they are not physical desktop or real-consumer acceptance.
"""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import select
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time

sys.dont_write_bytecode = True
from lib.isolated_files import read_regular
from lib.source_snapshot import open_directory

ROOT = Path(__file__).resolve().parents[1]
NATIVE_RUNNER = ROOT / "tests/native-runtime-regression.py"
EXPECTED_COMMIT = "c668141e9c42b13c80c9ca4ea108e11708c5e8a5"
EXPECTED_NATIVE_FINGERPRINT = "2cd0ffb0c38f31868e28c3556f0efc530f4fcd04765856ec157bc070eac748a0"
BETA13_COMMIT = "2760cdb8272255790d5e4613fed8a48cb63c3555"
BETA13_VERSION = "0.1.1-beta.13"
PSS_GROWTH_CEILING_KIB = 512
MAX_GIT_ARCHIVE_BYTES = 16 * 1024 * 1024
MAX_GIT_BLOB_BYTES = 1024 * 1024
MAX_GIT_DIAGNOSTIC_BYTES = 64 * 1024
GIT = "/usr/bin/git"
EXPECTED_PLUGIN_IDS = (
    "hancore.shibumi.bar",
    "hancore.shibumi.state",
    "hancore.shibumi.control-center",
    "hancore.shibumi.reactor",
    "hancore.shibumi.telemetry",
    "hancore.shibumi.power-state",
    "hancore.shibumi.workspaces",
    "hancore.shibumi.update-center",
    "hancore.shibumi.status",
    "hancore.shibumi.memory",
    "hancore.shibumi.cpu",
    "hancore.shibumi.audio",
    "hancore.shibumi.ai",
    "hancore.shibumi.center",
    "hancore.shibumi.media",
    "hancore.shibumi.quick-access",
    "hancore.shibumi.network",
    "hancore.shibumi.battery",
    "hancore.shibumi.brightness",
    "hancore.shibumi.power-profile",
    "hancore.shibumi.bluetooth",
    "hancore.shibumi.temperature",
    "hancore.shibumi.gpu",
    "hancore.shibumi.storage",
)
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
    ("HOST CPU BURN", "catalog cycle exceeded CPU ceiling", "catalog",
     ((b"    op.event = { output: output, ok: ok === true }",
       b"    var fixtureBurnUntil = Date.now() + 1000\n"
       b"    while (Date.now() < fixtureBurnUntil) {}\n"
       b"    op.event = { output: output, ok: ok === true }"),)),
    ("HELPER CPU BURN", "catalog cycle exceeded CPU ceiling", "helper",
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


def reject_duplicate_key(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate resource measurement key: " + key)
        value[key] = item
    return value


def reject_nonfinite(value):
    raise ValueError("non-finite resource measurement: " + value)


def parse_finite_float(value):
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError("non-finite resource measurement: " + value)
    return parsed


def measurement(output, marker):
    prefix = marker + " "
    rows = [line[len(prefix):] for line in output.splitlines()
            if line.startswith(prefix)]
    if len(rows) != 1:
        raise RuntimeError(marker + " must occur exactly once")
    try:
        value = json.loads(
            rows[0],
            object_pairs_hook=reject_duplicate_key,
            parse_constant=reject_nonfinite,
            parse_float=parse_finite_float,
        )
    except (json.JSONDecodeError, ValueError) as error:
        raise RuntimeError(marker + " is not strict JSON") from error
    if not isinstance(value, dict):
        raise RuntimeError(marker + " is not a JSON object")
    return value


def require_three_plus_three_measurement(output):
    cold = measurement(output, "NATIVE_CATALOG_RESOURCE_COLD_INITIALIZATION")
    warm = measurement(output, "NATIVE_CATALOG_RESOURCE_WARM_MEASUREMENT")
    shared_keys = {
        "baselinePssKiB",
        "cycleCpuSeconds",
        "cycles",
        "maximumPssOverBaselineKiB",
        "pssKiB",
        "requestSerials",
    }
    for label, value, expected_keys in (
            ("cold initialization", cold, shared_keys),
            ("warm", warm, shared_keys | {"unchangedCeilingKiB"})):
        cpu = value.get("cycleCpuSeconds")
        serials = value.get("requestSerials")
        if (set(value) != expected_keys
                or type(value.get("cycles")) is not int
                or value["cycles"] != 3
                or not isinstance(value.get("pssKiB"), list)
                or len(value["pssKiB"]) != 3
                or any(type(item) is not int or item <= 0 for item in value["pssKiB"])
                or not isinstance(cpu, list)
                or len(cpu) != 3
                or any(type(item) not in (int, float)
                       or not math.isfinite(item) or item < 0 for item in cpu)
                or not isinstance(serials, list)
                or len(serials) != 3
                or any(type(item) is not int or item <= 0 for item in serials)):
            raise RuntimeError(label + " measurement is not an exact three-cycle record")
    serials = cold["requestSerials"] + warm["requestSerials"]
    if serials != list(range(serials[0], serials[0] + 6)):
        raise RuntimeError("resource measurement request serials are not consecutive")
    if (type(cold.get("baselinePssKiB")) is not int
            or cold["baselinePssKiB"] <= 0
            or type(cold.get("maximumPssOverBaselineKiB")) is not int
            or cold["maximumPssOverBaselineKiB"]
            != max(0, max(cold["pssKiB"]) - cold["baselinePssKiB"])):
        raise RuntimeError("cold initialization PSS accounting mismatch")
    if (type(warm.get("baselinePssKiB")) is not int
            or warm["baselinePssKiB"] != cold["pssKiB"][-1]
            or type(warm.get("unchangedCeilingKiB")) is not int
            or warm["unchangedCeilingKiB"] != PSS_GROWTH_CEILING_KIB
            or type(warm.get("maximumPssOverBaselineKiB")) is not int
            or warm["maximumPssOverBaselineKiB"]
            != max(0, max(warm["pssKiB"]) - warm["baselinePssKiB"])):
        raise RuntimeError("warm PSS baseline, ceiling, or accounting mismatch")
    return {"coldInitialization": cold, "warm": warm}


def run_positive(native, base, label):
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        native.run(base, (SUCCESS_MARKER, CLEANUP_MARKER))
    output = captured.getvalue()
    print(output, end="", flush=True)
    result = require_three_plus_three_measurement(output)
    print(label + " EXACT 3+3 PSS MEASUREMENT PASSED " + json.dumps({
        "coldInitializationGrowthKiB":
            result["coldInitialization"]["maximumPssOverBaselineKiB"],
        "warmGrowthKiB": result["warm"]["maximumPssOverBaselineKiB"],
        "unchangedCeilingKiB": PSS_GROWTH_CEILING_KIB,
    }, sort_keys=True), flush=True)
    return result


def bounded_command(command, cwd, maximum, timeout, environment=None):
    if maximum < 1 or timeout <= 0:
        raise ValueError("invalid bounded command limits")
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    if process.stdout is None:
        process.kill()
        process.wait()
        raise RuntimeError("bounded command output pipe is unavailable")
    output = bytearray()
    deadline = time.monotonic() + timeout
    try:
        descriptor = process.stdout.fileno()
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("bounded command timed out")
            readable, _, _ = select.select((descriptor,), (), (), remaining)
            if not readable:
                raise RuntimeError("bounded command timed out")
            chunk = os.read(descriptor, min(65536, maximum + 1 - len(output)))
            if not chunk:
                break
            output.extend(chunk)
            if len(output) > maximum:
                raise RuntimeError("bounded command output exceeded limit")
        return_code = process.wait(timeout=max(0.01, deadline - time.monotonic()))
        if return_code != 0:
            diagnostic = bytes(output[-4096:]).decode("utf-8", errors="replace").strip()
            raise RuntimeError(
                "bounded command failed with status " + str(return_code)
                + (": " + diagnostic if diagnostic else "")
            )
        return bytes(output)
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        raise
    finally:
        process.stdout.close()


def git_environment():
    environment = {
        key: value for key, value in os.environ.items()
        if not key.startswith("GIT_")
    }
    environment.update({
        "GIT_NO_REPLACE_OBJECTS": "1",
        "LANG": "C",
        "LC_ALL": "C",
    })
    return environment


def run_git(arguments, maximum, timeout):
    return bounded_command(
        [GIT, "--no-replace-objects", "-c", "core.fsmonitor=false",
         "-c", "core.attributesfile=/dev/null", *arguments],
        ROOT,
        maximum,
        timeout,
        git_environment(),
    )


def require_current_plugin_roster(suite, native):
    plugins = suite.get("plugins")
    if not isinstance(plugins, list):
        raise RuntimeError("current 24-plugin roster is unavailable")
    plugin_ids = tuple(
        item.get("id") if isinstance(item, dict) else None
        for item in plugins
    )
    if (plugin_ids != EXPECTED_PLUGIN_IDS
            or not set(native.PLUGINS).issubset(plugin_ids)):
        raise RuntimeError("current 24-plugin roster is unavailable")
    return plugin_ids


def materialize_exact_beta13(native, target):
    if not Path(GIT).is_file():
        raise RuntimeError("pinned Git executable is unavailable")
    replacements = run_git(["replace", "--list"], MAX_GIT_DIAGNOSTIC_BYTES, 10)
    if replacements.strip():
        raise RuntimeError("Git replacement refs make exact Beta.13 ambiguous")
    resolved = run_git(
        ["rev-parse", "--verify", BETA13_COMMIT + "^{commit}"],
        128,
        10,
    ).decode("ascii", errors="strict").strip()
    if resolved != BETA13_COMMIT:
        raise RuntimeError("exact Beta.13 commit is unavailable")
    suite = json.loads(read_regular(ROOT / "contracts/plugin-suite-v1.json",
                                    1024 * 1024),
                       object_pairs_hook=reject_duplicate_key,
                       parse_constant=reject_nonfinite,
                       parse_float=parse_finite_float)
    plugin_ids = require_current_plugin_roster(suite, native)
    archived = run_git(
        ["archive", "--format=tar", BETA13_COMMIT, "--", *plugin_ids],
        MAX_GIT_ARCHIVE_BYTES,
        30,
    )
    if not archived:
        raise RuntimeError("exact Beta.13 plugin archive has an invalid size")

    target.mkdir(mode=0o700)
    total = 0
    plugin_id_set = set(plugin_ids)
    with tarfile.open(fileobj=io.BytesIO(archived), mode="r:") as archive:
        for member in archive:
            relative = PurePosixPath(member.name)
            if (relative.is_absolute() or not relative.parts
                    or ".." in relative.parts or relative.parts[0] not in plugin_id_set
                    or relative.as_posix() != member.name.rstrip("/")):
                raise RuntimeError("unsafe exact Beta.13 archive path")
            destination = target.joinpath(*relative.parts)
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            if not member.isfile() or member.size > MAX_GIT_BLOB_BYTES:
                raise RuntimeError("unsafe exact Beta.13 archive entry")
            total += member.size
            if total > MAX_GIT_ARCHIVE_BYTES:
                raise RuntimeError("exact Beta.13 materialized bytes exceed limit")
            source = archive.extractfile(member)
            if source is None:
                raise RuntimeError("exact Beta.13 archive file is unreadable")
            data = source.read(MAX_GIT_BLOB_BYTES + 1)
            if len(data) != member.size:
                raise RuntimeError("exact Beta.13 archive file size mismatch")
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open("xb") as output:
                output.write(data)
            destination.chmod(0o755 if member.mode & 0o111 else 0o644)

    for plugin_id in plugin_ids:
        manifest_path = target / plugin_id / "manifest.json"
        manifest = json.loads(read_regular(manifest_path, 128 * 1024),
                              object_pairs_hook=reject_duplicate_key)
        if manifest.get("id") != plugin_id or manifest.get("version") != BETA13_VERSION:
            raise RuntimeError("exact Beta.13 manifest identity mismatch: " + plugin_id)
    native.materialize(native.snapshot(ROOT / "tests/fixtures"),
                       target / "tests/fixtures")
    native.materialize(native.snapshot(ROOT / "tests/lib"), target / "tests/lib")


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
    parser.add_argument("--native-shell", type=Path)
    args = parser.parse_args()
    native_shell = args.native_shell
    if native_shell is None:
        installed_source = os.environ.get("SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH")
        if not installed_source:
            parser.error(
                "--native-shell or SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH is required"
            )
        native_shell = Path(installed_source) / "shell"

    native = load_native_runner()
    admitted = native.admitted_native(native_shell)
    with tempfile.TemporaryDirectory(prefix="shibumi-native-catalog-resource-",
                                     dir="/tmp") as temporary:
        owned = Path(temporary)
        beta13_source = owned / "exact-beta13-source"
        materialize_exact_beta13(native, beta13_source)
        beta13_base = owned / "exact-beta13"
        original_root = native.ROOT
        try:
            native.ROOT = beta13_source
            native.stage(beta13_base, admitted)
        finally:
            native.ROOT = original_root
        install_probe(beta13_base)
        print("NATIVE CATALOG RESOURCE EXACT BETA.13 POSITIVE " + BETA13_COMMIT,
              flush=True)
        run_positive(native, beta13_base, "EXACT BETA.13")

        base = owned / "candidate"
        native.stage(base, admitted)
        install_probe(base)
        plugin = (base / "home/.config/omarchy/plugins"
                  / "hancore.shibumi.control-center")
        paths = {"catalog": plugin / "NativeCatalog.qml",
                 "helper": plugin / "manager/shibumi-native-catalog"}

        print("NATIVE CATALOG RESOURCE CANDIDATE POSITIVE", flush=True)
        run_positive(native, base, "CANDIDATE")

        cpu_anchor = b"    text = raw.decode(\"utf-8\", errors=\"strict\")"
        cpu_allowance = (b"    fixture_burn_until = time.process_time() + 0.15\n"
                         b"    while time.process_time() < fixture_burn_until:\n"
                         b"        pass\n" + cpu_anchor)
        original, original_hash = mutate_private(
            paths["helper"], ((cpu_anchor, cpu_allowance),))
        try:
            print("NATIVE CATALOG RESOURCE HELPER CPU BELOW-CEILING CONTROL",
                  flush=True)
            run_positive(native, base, "HELPER CPU BELOW-CEILING CONTROL")
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
        run_positive(native, base, "RESTORED CANDIDATE")
    if owned.exists():
        raise RuntimeError("owned catalog resource fixture directory remains")
    print("PINNED NATIVE CATALOG RESOURCE POSITIVE/NEGATIVE/RESTORED PASSED; "
          "OWNED DIRECTORY REMOVED", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        raise SystemExit("native-catalog-resource-regression: " + str(error)) from error
