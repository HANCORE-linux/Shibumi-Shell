#!/usr/bin/env python3
"""Bounded, backend-free State/marker checks against exact 4.0.3 shell facade.

This is NOT a complete Omarchy compatibility or production activation gate.
Supply shell/services/PluginShellApi.qml from Omarchy commit
0534987009061cbe2dacdde4ad564092ab698d12; no downloaded code is fetched here.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import stat
import subprocess
import tempfile
import time
from lib.isolated_process import run_bounded, observe_owned_exit, finish_owned_group

ROOT = Path(__file__).resolve().parents[1]
API_SHA = "ff0cb5ec5fcdda0b21af447b11f07a24e065a3557796639364109aaa2ce5c763"
DIGEST = "a" * 64


def bounded_read(path):
    maximum = 512 * 1024
    fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_size > maximum:
            raise ValueError("test source is not a bounded regular file")
        data = bytearray()
        while len(data) <= maximum:
            chunk = os.read(fd, min(65536, maximum + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        after = os.fstat(fd)
        identity = lambda value: (value.st_dev, value.st_ino, value.st_mode,
                                 value.st_size, value.st_mtime_ns, value.st_ctime_ns)
        if len(data) > maximum or identity(before) != identity(after):
            raise ValueError("test source changed or exceeds the bound")
        return bytes(data)
    finally:
        os.close(fd)


def section(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError("production probe anchors are no longer unique")
    return source.split(start, 1)[1].split(end, 1)[0]


def bar_probe(source):
    marker_properties = section(source,
        "  readonly property int shibumiHostContractVersion: 1\n",
        "  property bool hostReady: false\n")
    capture = "  function captureSuiteMarker(raw) {" + section(source,
        "  function captureSuiteMarker(raw) {", "  function registeredWidgetComponent(widgetId) {")
    marker = "  FileView {\n    id: suiteMarker" + section(source,
        "  FileView {\n    id: suiteMarker", "  Process {\n    id: barHiddenProbe")
    verify = "    function verifyPayload(expectedDigest: string): string {" + section(source,
        "    function verifyPayload(expectedDigest: string): string {", "    function reloadPayload(): string {")
    return ("import QtQuick\nimport Quickshell.Io\nItem {\n  id: root\n"
        "  property var manifest: null\n  property bool hostReady: true\n"
        # This extracted probe covers marker authority, not full Bar readiness.
        # The actual Bar/runtime hookup is tested separately with native shell.qml.
        "  property bool styleReady: true\n  property bool suiteRuntimeReady: true\n"
        + marker_properties + capture + marker
        + '\n  IpcHandler { target: "marker-bar"\n' + verify + "  }\n}\n")


def ipc(env, directory, deadline, target, method, *args):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RuntimeError("private fixture deadline")
    command = ["/usr/bin/quickshell", "ipc", "-p", str(directory), "call", "--", target, method, *args]
    reply = run_bounded(command, env=env, timeout=min(4, remaining), maximum=65536)
    if reply.returncode != 0:
        raise RuntimeError("private fixture IPC failed: " + str(reply.returncode)
            + " " + (reply.stdout + reply.stderr)[:2048].decode("utf-8", errors="replace"))
    return reply.stdout.decode("utf-8").strip()


def run_case(base, mode, api, state_source, probe, runtime_fixture=False, runtime_source=None):
    directory = base / mode
    directory.mkdir()
    env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "QT_QPA_PLATFORM": "offscreen",
        "QT_QUICK_BACKEND": "software", "QT_QPA_PLATFORMTHEME": "",
        "QT_FORCE_STDERR_LOGGING": "1", "QML_DISABLE_DISK_CACHE": "1",
        "WAYLAND_DISPLAY": "", "HYPRLAND_INSTANCE_SIGNATURE": "",
        "MARKER_CASE": mode}
    for name in ("HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME",
                 "XDG_DATA_HOME", "XDG_RUNTIME_DIR"):
        # Keep Unix socket paths below sockaddr_un's small platform limit;
        # the QML/marker paths deliberately retain spaces, percent and hash.
        index = ["valid", "missing", "malformed", "wrong-suite", "wrong-digest"].index(mode)
        path = base / ("r" + str(index)) if name == "XDG_RUNTIME_DIR" else directory / name
        path.mkdir(mode=0o700)
        env[name] = str(path)
    env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=" + str(directory / "no-session-bus")
    env["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=" + str(directory / "no-system-bus")
    for name in ("plugin", "host", "bar", "Commons", "decoy"):
        (directory / name).mkdir()
    env["DECOY_MARKER_DIR"] = str(directory / "decoy")
    env["OMARCHY_PATH"] = str(directory / "absent-native-defaults")
    config_dir = Path(env["XDG_CONFIG_HOME"]) / "omarchy"
    config_dir.mkdir()
    (config_dir / "shell.json").write_text(json.dumps({"version": 1,
        "bar": {"layout": {"left": [], "center": [], "right": []}},
        "plugins": [{"id": "hancore.shibumi.state", "shibumiStateSchemaVersion": 1,
            "foreign": {"retained": [1, False]}, "shibumi": {"version": 1,
            "presentation": {"accent": "color04"}, "widgets": {"G4": {"extra": {"first": 1, "second": 2}}}}}]}))
    fixture = "shared-runtime-regression.qml" if runtime_fixture else "scoped-state-regression.qml"
    (directory / "shell.qml").write_bytes(bounded_read(ROOT / "tests" / fixture))
    if runtime_fixture:
        for folder, relative in (("left", "../plugin/runtime"), ("right/deep", "../../plugin/runtime")):
            target = directory / folder
            target.mkdir(parents=True)
            (target / "Probe.qml").write_text('import QtQuick\nimport "' + relative
                + '" as Shared\nQtObject { readonly property var instance: Shared.Runtime;\n'
                'readonly property var state: Shared.Runtime.serviceFor("hancore.shibumi.state") }\n')
    (directory / "host/PluginShellApi.qml").write_bytes(api)
    (directory / "plugin/Service.qml").write_bytes(state_source)
    (directory / "plugin/runtime").mkdir()
    for name in ("qmldir", "Runtime.qml", "Provider.qml", "HostShell.qml"):
        data = runtime_source if name == "Runtime.qml" and runtime_source is not None else bounded_read(
            ROOT / "hancore.shibumi.state/runtime" / name)
        (directory / "plugin/runtime" / name).write_bytes(data)
    for name in ("ShibumiConfig.js", "ThemePalette.qml", "ThemePaletteModel.js", "StateStorage.qml", "StateStorageModel.js"):
        (directory / "plugin" / name).write_bytes(bounded_read(ROOT / "hancore.shibumi.state" / name))
    (directory / "bar/Marker.qml").write_text(probe)
    # A passive palette fixture: no native services, commands, or host bus.
    (directory / "Commons/qmldir").write_text("singleton Color 1.0 Color.qml\n")
    (directory / "Commons/Color.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject {\n'
        'property color urgent: "red"; property color accent: "blue";\n'
        'property color foreground: "white"; property color background: "black";\n'
        'property color muted: "gray"\n}\n')
    marker = {"suiteId": "hancore.shibumi", "suitePayloadDigest": DIGEST}
    if mode == "wrong-digest":
        marker["suitePayloadDigest"] = "b" * 64
    elif mode == "wrong-suite":
        marker["suiteId"] = "foreign.suite"
    raw = "{broken" if mode == "malformed" else json.dumps(marker)
    if mode != "missing":
        for name in ("plugin", "bar"):
            (directory / name / ".shibumi-managed.json").write_text(raw)
    # Even a valid-looking manifest path cannot substitute another location.
    (directory / "decoy/.shibumi-managed.json").write_text(json.dumps({
        "suiteId": "hancore.shibumi", "suitePayloadDigest": "c" * 64}))
    command = ["/usr/bin/quickshell", "-p", str(directory)]
    proc = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, start_new_session=True)
    output = bytearray()
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 10
    checked = False
    try:
        while selector.get_map():
            if time.monotonic() >= deadline:
                raise RuntimeError("private fixture deadline")
            for key, _ in selector.select(.1):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                output.extend(chunk)
                if len(output) > 1024 * 1024:
                    raise RuntimeError("private fixture output limit")
            if not checked and b"scoped state regression ready" in output:
                checked = True
                expected = "ok" if mode == "valid" else "not-ready"
                for target in ("marker-bar", "shibumi-suite-runtime"):
                    actual = ipc(env, directory, deadline, target, "verifyPayload", DIGEST)
                    if actual != expected:
                        raise RuntimeError(f"{mode}: {target} returned {actual!r}, expected {expected!r}")
                if runtime_fixture:
                    # Mutate only the owned fixture marker. A running engine
                    # must retire rather than adopt the newly published digest.
                    (directory / "plugin/.shibumi-managed.json").write_text(json.dumps({
                        "suiteId": "hancore.shibumi", "suitePayloadDigest": "d" * 64}))
                    for _ in range(20):
                        if ipc(env, directory, deadline, "shibumi-suite-runtime", "verifyPayload", DIGEST) == "not-ready":
                            break
                        time.sleep(.05)
                    else:
                        raise RuntimeError("runtime marker retirement was not admitted by State IPC")
                if ipc(env, directory, deadline, "scoped-state-test", "finish") != "ok":
                    raise RuntimeError("fixture completion request failed")
        rc = observe_owned_exit(proc, min(deadline, time.monotonic() + 1))
        if rc != 0 or not checked or b"scoped state regression passed" not in output:
            raise RuntimeError("fixture failed")
        if any(token in output for token in (b"TypeError", b"ReferenceError", b"Binding loop",
                                            b"Unable to assign", b"Cannot assign", b"Internal error", b"ERROR")):
            raise RuntimeError("fixture runtime error")
    finally:
        selector.close()
        proc.stdout.close()
        finish_owned_group(proc)
        print(output.decode("utf-8", errors="replace"), end="", flush=True)
        print(f"{mode}: fixture exit={proc.returncode}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-api", required=True, type=Path)
    parser.add_argument("--state-source", type=Path, default=ROOT / "hancore.shibumi.state/Service.qml")
    parser.add_argument("--bar-source", type=Path, default=ROOT / "Bar.qml")
    parser.add_argument("--runtime-source", type=Path, default=ROOT / "hancore.shibumi.state/runtime/Runtime.qml")
    parser.add_argument("--case", choices=("valid", "missing", "malformed", "wrong-suite", "wrong-digest"))
    parser.add_argument("--runtime", action="store_true", help="also test cooperative runtime and retirement")
    args = parser.parse_args()
    api = bounded_read(args.host_api)
    if hashlib.sha256(api).hexdigest() != API_SHA:
        raise ValueError("host facade does not match the pinned 4.0.3 source")
    state_source = bounded_read(args.state_source)
    runtime_source = bounded_read(args.runtime_source)
    probe = bar_probe(bounded_read(args.bar_source).decode("utf-8"))
    with tempfile.TemporaryDirectory(prefix="shibumi-scoped-state-", suffix=" % # space") as path:
        modes = ["valid"] if args.runtime else ([args.case] if args.case else [
            "valid", "missing", "malformed", "wrong-suite", "wrong-digest"])
        for mode in modes:
            run_case(Path(path), mode, api, state_source, probe, args.runtime, runtime_source)
    print("scoped host state/marker regressions passed (not full 4.0.3 compatibility)")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        raise SystemExit("scoped-state-regression: " + str(error)) from error
