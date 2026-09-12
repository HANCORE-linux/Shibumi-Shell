#!/usr/bin/env python3
"""Owned local-file State storage test; no native host, buses or production files."""
import argparse
import json
from pathlib import Path
import tempfile
from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.owned_cgroup import OwnedCgroup
from lib.source_snapshot import materialize

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service", action="store_true", help="exercise the actual public State setters")
    parser.add_argument("--transition-controls", action="store_true", help="calibrate atomic layout/family and compensation assertions")
    args = parser.parse_args()
    if args.transition_controls and not args.service:
        parser.error("--transition-controls requires --service")
    fixture = "state-service-smoke.qml" if args.service else "state-storage-smoke.qml"
    marker = "state service smoke passed" if args.service else "state storage debounce/readback/refusal/convergence/revocation passed"
    sources = {"shell.qml": (read_regular(ROOT / "tests" / fixture, 65536), False),
        "cgroup_exec.py": (read_regular(ROOT / "tests/lib/cgroup_exec.py", 65536), False)}
    for name in ("StateStorage.qml", "StateStorageModel.js", "ShibumiConfig.js"):
        sources["state/" + name] = (read_regular(ROOT / "hancore.shibumi.state" / name, 65536), False)
    if args.service:
        for name in ("Service.qml", "ThemePalette.qml", "ThemePaletteModel.js", "runtime/qmldir",
                     "runtime/Runtime.qml", "runtime/Provider.qml", "runtime/HostShell.qml"):
            sources["state/" + name] = (read_regular(ROOT / "hancore.shibumi.state" / name, 65536), False)
        sources["state/.shibumi-managed.json"] = (json.dumps({
            "suiteId": "hancore.shibumi", "suitePayloadDigest": "a" * 64}).encode(), False)
        sources["Commons/qmldir"] = (b"singleton Color 1.0 Color.qml\n", False)
        sources["Commons/Color.qml"] = (b'pragma Singleton\nimport QtQuick\nQtObject {\n'
            b'property color urgent: "red"; property color accent: "blue";\n'
            b'property color foreground: "white"; property color background: "black";\n'
            b'property color muted: "gray"\n}\n', False)
    run_case(sources, args.service, marker)
    if args.service:
        # Calibrate the preservation assertion against the previous implementation.
        mutated = dict(sources)
        path = "state/StateStorageModel.js"
        old = b"result.shibumi = mergeSettings(entry.shibumi, before, settings)"
        raw = mutated[path][0]
        if raw.count(old) != 1:
            raise RuntimeError("unknown-settings control anchor changed")
        mutated[path] = (raw.replace(old, b"result.shibumi = copy(settings)"), False)
        run_case(mutated, True, marker, "unknown nested settings lost")
    if args.transition_controls:
        controls = (
            ([(b"return same(layoutFamilyProjection(ShibumiConfig.normalize(next), patch), patch)", b"return true")],
             "normalization admitted a partial transition"),
            ([(b"next.order = value.order", b"next.order = Object.keys(patch).length > 1 ? next.order : value.order")],
             "atomic transition refused"),
            ([(b"|| expectedSerial !== writeSerial", b""),
              (b"writePending || writeSerial !== expectedSerial", b"writePending")],
             "compensation ignored newer serial"),
            ([(b"|| !same(layoutFamilyProjection(config, expected), expected)", b""),
              (b"|| !same(layoutFamilyProjection(next, expected), expected)", b"")],
             "compensation overwrote intervening file publication"),
        )
        for edits, diagnostic in controls:
            mutated = dict(sources)
            path = "state/Service.qml"
            raw = mutated[path][0]
            for old, new in edits:
                if raw.count(old) != 1:
                    raise RuntimeError("transition control anchor changed: " + old.decode())
                raw = raw.replace(old, new)
            mutated[path] = (raw, False)
            run_case(mutated, True, marker, diagnostic)
        run_case(sources, True, marker)


def run_case(sources, service, marker, expected_failure=""):
    with tempfile.TemporaryDirectory(prefix="shibumi-state-storage-") as temporary:
        base = Path(temporary)
        materialize(sources, base)
        for name in ("home", "config/omarchy", "state-home", "cache", "data", "run", "omarchy/config/omarchy"):
            (base / name).mkdir(parents=True, exist_ok=True)
        (base / "run").chmod(0o700)
        config = {"version": 1, "bar": {"layout": {"left": [], "center": [], "right": []}},
            "plugins": [{"id": "hancore.shibumi.state", "shibumiStateSchemaVersion": 1,
                "shibumi": {"version": 1}, "foreign": {"deep": [False, 0]}},
                {"id": "local.other", "opaque": {"value": 42}}]}
        deep = {"leaf": [False, 0, "Malmö"]}
        for _ in range(70):
            deep = {"nested": deep}
        config["plugins"][0]["deepFuture"] = deep
        config["plugins"][0]["shibumi"]["widgets"] = {"G4": {"futureDeep": deep}}
        if service:
            config["plugins"][0]["shibumi"].update({
                "futureState": {"nested": [False, "Malmö", {"n": 0}]},
                "presentation": {"accent": "color02", "futurePresentation": {"v": [1, 2]}},
                "layoutProtection": {"futureVariant": True},
            })
        (base / "config/omarchy/shell.json").write_text(json.dumps(config))
        config["plugins"][0]["defaultsSentinel"] = True
        (base / "omarchy/config/omarchy/shell.json").write_text(json.dumps(config))
        env = {"HOME": str(base / "home"), "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_STATE_HOME": str(base / "state-home"), "XDG_CACHE_HOME": str(base / "cache"),
            "XDG_DATA_HOME": str(base / "data"), "XDG_DATA_DIRS": str(base / "data"),
            "XDG_RUNTIME_DIR": str(base / "run"), "OMARCHY_PATH": str(base / "omarchy"),
            "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "QT_QPA_PLATFORM": "offscreen",
            "QT_QUICK_BACKEND": "software", "QT_FORCE_STDERR_LOGGING": "1", "QML_DISABLE_DISK_CACHE": "1",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(base / "absent-session"),
            "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(base / "absent-system")}
        with OwnedCgroup() as group:
            result = run_bounded(["/usr/bin/python3", str(base / "cgroup_exec.py"), str(group.procs),
                "/usr/bin/quickshell", "-p", str(base)], env=env,
                timeout=12, maximum=65536, pass_fds=(group.procs,))
        output = (result.stdout + result.stderr).decode(errors="replace")
        print(output)
        if any(token in output for token in ("TypeError", "ReferenceError", "Binding loop", "Unable to assign",
                                            "Cannot assign", "Internal error")):
            raise RuntimeError("state storage fixture runtime error")
        if expected_failure:
            if result.returncode == 0 or expected_failure not in output or marker in output:
                raise RuntimeError("state storage negative control missed its intended assertion")
            print("Calibrated negative control: " + expected_failure)
        elif result.returncode != 0 or marker not in output or "ERROR" in output:
            raise RuntimeError("state storage fixture failed")
    print("Owned State storage fixture removed; not complete host/lifecycle acceptance")


if __name__ == "__main__":
    main()
