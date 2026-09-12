#!/usr/bin/env python3
"""Prove changed QML assertions fail the process, not just log an error."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="sb-qml-exit-") as name:
        root = Path(name)
        for part in ("core", "tests", "home", "run"):
            (root / part).mkdir(mode=0o700)
        # Only the backend-free model/controller dependencies, no host plugins.
        for name in ("GroupRegistry.js", "LayoutModel.js", "ShibumiConfig.js",
                     "WidgetFamilies.js", "V2LayoutModel.js",
                     "LayoutController.qml", "DragSession.qml"):
            shutil.copyfile(REPO / "core" / name, root / "core" / name)
        for name in ("group-registry-regression.qml", "layout-controller-regression.qml"):
            shutil.copyfile(REPO / "tests" / name, root / "tests" / name)
        home = root / "home"
        env = {
            "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "HOME": str(home),
            "XDG_RUNTIME_DIR": str(root / "run"),
            "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
            "QT_QUICK_BACKEND": "software", "QML_DISABLE_DISK_CACHE": "1",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(root / "no-session-bus"),
            "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(root / "no-system-bus"),
        }
        for kind in ("config", "cache", "state", "data"):
            env["XDG_" + kind.upper() + "_HOME"] = str(home / kind)

        def run(fixture, expected, label):
            # A timeout, crash or load error is not a successful negative control.
            with tempfile.TemporaryFile() as log:
                result = subprocess.run([
                    "/usr/lib/qt6/bin/qml", str(root / "tests" / fixture)
                ], env=env, cwd=root, stdout=log, stderr=subprocess.STDOUT, timeout=15)
                if result.returncode != expected:
                    log.seek(0, os.SEEK_END)
                    log.seek(max(0, log.tell() - 8192))
                    raise AssertionError((label, result.returncode,
                                          log.read(8192).decode(errors="replace")))
            print(f"QML assertion exit control passed: {label} (exit {expected})")

        registry = "group-registry-regression.qml"
        controller = "layout-controller-regression.qml"
        run(registry, 0, "registry positive")
        run(controller, 0, "controller positive")
        model = root / "core/LayoutModel.js"
        original = model.read_text()
        old = "var ExtraLimits = { left: 2, center: 1, right: 2 }"
        assert original.count(old) == 1, "center-limit mutation anchor drifted"
        model.write_text(original.replace(old, old.replace("center: 1", "center: 0")))
        run(registry, 1, "center limit restored to one must fail")
        model.write_text(original)
        fixture = root / "tests" / controller
        original = fixture.read_text()
        old = "if (root.writes !== 13)"
        assert original.count(old) == 1, "controller mutation anchor drifted"
        fixture.write_text(original.replace(old, "if (root.writes !== 12)"))
        run(controller, 1, "wrong persistence count must fail")
        fixture.write_text(original)
        run(registry, 0, "registry restored positive")
        run(controller, 0, "controller restored positive")
    print("QML assertion exit regression passed (isolated offscreen)")


if __name__ == "__main__":
    main()
