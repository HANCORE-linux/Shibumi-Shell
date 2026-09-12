#!/usr/bin/env python3
"""Owned actual coordinator/controller + captured Bar planner, explicit inert backends."""
import argparse
import os
from pathlib import Path
import tempfile

from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.owned_cgroup import OwnedCgroup
from lib.source_snapshot import materialize

ROOT = Path(__file__).resolve().parents[1]
MARKER = "serialized State/native layout sequencing passed; not desktop acceptance"


def run_case(sources, diagnostic=""):
    with tempfile.TemporaryDirectory(prefix="shibumi-layout-transition-") as temporary:
        base = Path(temporary)
        materialize(sources, base)
        for name in ("home", "config", "state", "cache", "data", "run"):
            (base / name).mkdir()
        (base / "run").chmod(0o700)
        env = {"HOME": str(base / "home"), "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_STATE_HOME": str(base / "state"), "XDG_CACHE_HOME": str(base / "cache"),
            "XDG_DATA_HOME": str(base / "data"), "XDG_DATA_DIRS": str(base / "data"),
            "XDG_RUNTIME_DIR": str(base / "run"), "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(base / "absent-session"),
            "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(base / "absent-system"),
            "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
            "QT_FORCE_STDERR_LOGGING": "1", "QML_DISABLE_DISK_CACHE": "1"}
        with OwnedCgroup() as group:
            result = run_bounded(["/usr/bin/python3", str(base / "cgroup_exec.py"), str(group.procs),
                "/usr/bin/quickshell", "-p", str(base)], env=env, timeout=12, maximum=65536,
                pass_fds=(group.procs,))
        output = (result.stdout + result.stderr).decode(errors="replace")
        print(output, flush=True)
        if any(token in output for token in ("TypeError", "ReferenceError", "Binding loop", "Unable to assign",
                                            "Cannot assign", "Internal error")):
            raise RuntimeError("layout transition fixture runtime error")
        if diagnostic:
            if result.returncode == 0 or diagnostic not in output or MARKER in output:
                raise RuntimeError("layout transition negative missed intended assertion")
            print("Calibrated layout control: " + diagnostic, flush=True)
        elif result.returncode != 0 or MARKER not in output or "ERROR" in output:
            raise RuntimeError("layout transition fixture failed")
    print("Owned layout fixture removed; no production writer or compositor", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--controls", action="store_true")
    args = parser.parse_args()
    sources = {}
    for name in ("LayoutTransition.qml", "LayoutController.qml", "LayoutModel.js", "V2LayoutModel.js", "GroupRegistry.js"):
        sources["core/" + name] = (read_regular(ROOT / "core" / name, 131072), False)
    sources["StateStorageModel.js"] = (read_regular(ROOT / "hancore.shibumi.state/StateStorageModel.js", 65536), False)
    sources["cgroup_exec.py"] = (read_regular(ROOT / "tests/lib/cgroup_exec.py", 65536), False)
    commons = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell/Commons"
    sources["Commons/Util.qml"] = (read_regular(commons / "Util.qml", 65536), False)
    sources["Commons/qmldir"] = (b"singleton Util 1.0 Util.qml\n", False)
    bar = read_regular(ROOT / "Bar.qml", 131072)
    fragments = []
    for start, end in ((b"  function planV2DynamicLayout(", b"  function requestV2LayoutTransition("),
                       (b"  function entryId(", b"  function entrySettings(")):
        if bar.count(start) != 1 or bar.count(end) != 1:
            raise RuntimeError("Bar planner extraction anchor drifted")
        fragments.append(bar[bar.index(start):bar.index(end)])
    fixture = read_regular(ROOT / "tests/layout-transition-smoke.qml", 65536)
    if fixture.count(b"    // INJECT_NATIVE_PLAN") != 1:
        raise RuntimeError("layout fixture anchor drifted")
    sources["shell.qml"] = (fixture.replace(b"    // INJECT_NATIVE_PLAN", b"\n".join(fragments)), False)
    run_case(sources)
    if args.controls:
        # Each control mutates only captured production bytes, never the repository.
        controls = [
            ([(b'&& same(op.writer.layoutFamilySnapshot(patch), patch)', b'&& true')],
             "mismatched State projection dispatched native"),
            ([(b'if (!current(op) || serial !== op.serial) return', b'if (!current(op) || serial < op.serial) return') ,
              (b'op.event.serial !== op.serial', b'op.event.serial < op.serial')],
             "future settlement authorized native"),
            ([(b'&& same(observedBarConfig, op.expected)', b'&& true')],
             "native acceptance counted as publication"),
            ([(b'else queueState(op, true)', b'else finish(op, "compensated")')],
             "native refusal skipped compensation"),
            ([(b'if (busy || requestSerial !== op.id || !admitted', b'if (busy || !admitted')],
             "older request replaced serial reentry"),
            ([(b'if (!planned) refusedBeforeNative(op)', b'if (false) refusedBeforeNative(op)')],
             "pre-callback throw not compensated"),
        ]
        for replacements, diagnostic in controls:
            mutated = dict(sources)
            raw, _ = sources["core/LayoutTransition.qml"]
            for old, new in replacements:
                if raw.count(old) != 1:
                    raise RuntimeError("layout control anchor drifted: " + repr(old))
                raw = raw.replace(old, new)
            mutated["core/LayoutTransition.qml"] = (raw, False)
            run_case(mutated, diagnostic)
        run_case(sources)


if __name__ == "__main__":
    main()
