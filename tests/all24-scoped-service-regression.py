#!/usr/bin/env python3
"""Pinned 4.0.3 all-suite scoped service publication regression.

This is an isolated no-output construction and lifecycle gate. Platform owners
are withheld; it is not physical desktop, backend, or multi-output acceptance.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from lib.isolated_files import read_regular
from lib.isolated_process import run_bounded
from lib.owned_cgroup import OwnedCgroup

NATIVE_RUNNER = ROOT / "tests/native-runtime-regression.py"
PROBE = ROOT / "tests/fixtures/native-runtime/all24-service-probe.py"
EXPECTED_SCOPED_SERVICE_IDS = frozenset({
    "hancore.shibumi.state", "hancore.shibumi.control-center",
    "hancore.shibumi.reactor", "hancore.shibumi.telemetry",
    "hancore.shibumi.power-state", "hancore.shibumi.workspaces",
    "hancore.shibumi.update-center", "hancore.shibumi.status",
    "hancore.shibumi.cpu", "hancore.shibumi.audio", "hancore.shibumi.ai",
    "hancore.shibumi.center", "hancore.shibumi.media",
    "hancore.shibumi.quick-access", "hancore.shibumi.network",
    "hancore.shibumi.brightness", "hancore.shibumi.bluetooth",
    "hancore.shibumi.storage",
})


def load_native_runner():
    spec = importlib.util.spec_from_file_location("shibumi_native_fixture", NATIVE_RUNNER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-shell", required=True, type=Path)
    args = parser.parse_args()

    native = load_native_runner()
    admitted = native.admitted_native(args.native_shell)
    contract_raw = read_regular(ROOT / "contracts/plugin-suite-v1.json", 65536)
    contract = json.loads(contract_raw)
    rows = contract["plugins"]
    plugin_ids = [row["id"] for row in rows]
    service_ids = [row["id"] for row in rows if "service" in row["kinds"]]
    if (len(plugin_ids) != 24 or len(set(plugin_ids)) != 24
            or set(service_ids) != EXPECTED_SCOPED_SERVICE_IDS):
        raise ValueError("unexpected all-suite or scoped-service roster")

    probe = read_regular(PROBE, 65536)
    with tempfile.TemporaryDirectory(prefix="shibumi-all24-services-", dir="/tmp") as temporary:
        base = Path(temporary)
        native.stage(base, admitted)
        plugins = base / "home/.config/omarchy/plugins"
        for plugin_id in plugin_ids:
            if plugin_id in native.PLUGINS:
                continue
            destination = plugins / plugin_id
            if destination.exists():
                shutil.rmtree(destination)
            native.materialize(native.snapshot(ROOT / plugin_id), destination)
            (destination / ".shibumi-managed.json").write_text(json.dumps({
                "suiteId": "hancore.shibumi", "suitePayloadDigest": "a" * 64,
            }), encoding="utf-8")
        config_path = base / "home/.config/omarchy/shell.json"
        config = json.loads(config_path.read_text(encoding="utf-8"))
        config["bar"]["id"] = "hancore.shibumi.bar"
        config["bar"]["layout"] = {"left": [], "center": [], "right": []}
        for row in rows:
            plugin_id = row["id"]
            if "bar-widget" in row["kinds"]:
                config["bar"]["layout"]["left"].append({"id": plugin_id})
            elif "service" in row["kinds"] and plugin_id != "hancore.shibumi.state":
                config["plugins"].append({"id": plugin_id})
        for target in ("home/.config/omarchy/shell.json",
                       "omarchy/config/omarchy/shell.json"):
            (base / target).write_text(json.dumps(config), encoding="utf-8")
        (base / "run.py").write_bytes(probe)
        (base / "all24-roster.json").write_text(json.dumps({
            "plugins": plugin_ids, "services": service_ids,
        }), encoding="utf-8")
        print(json.dumps({
            "kind": "all24-scoped-service-regression-not-desktop-acceptance",
            "probeSha256": hashlib.sha256(probe).hexdigest(),
            "contractSha256": hashlib.sha256(contract_raw).hexdigest(),
            "nativeCommit": native.COMMIT,
            "noOutputSurfaces": True,
            "platformOwnersWithheld": True,
        }), flush=True)

        command = [
            "/usr/bin/bwrap", "--die-with-parent", "--new-session",
            "--unshare-user", "--unshare-pid", "--unshare-ipc", "--unshare-net",
            "--ro-bind", "/usr", "/usr", "--symlink", "usr/bin", "/bin",
            "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
            "--ro-bind", "/etc/fonts", "/etc/fonts", "--proc", "/proc",
            "--dev", "/dev", "--size", str(32 * 1024 * 1024), "--tmpfs", "/tmp",
            "--dir", "/run", "--ro-bind", str(base), "/input",
            "--size", str(64 * 1024 * 1024), "--tmpfs", "/fixture",
            "--disable-userns",
        ]
        environment = {
            "HOME": "/fixture/home", "XDG_CONFIG_HOME": "/fixture/home/.config",
            "XDG_STATE_HOME": "/fixture/state", "XDG_CACHE_HOME": "/fixture/cache",
            "XDG_DATA_HOME": "/fixture/data", "XDG_DATA_DIRS": "/fixture/data",
            "XDG_RUNTIME_DIR": "/fixture/run", "OMARCHY_PATH": "/fixture/omarchy",
            "PATH": "/fixture/bin", "QT_QPA_PLATFORM": "offscreen",
            "QT_QUICK_BACKEND": "software", "QT_QPA_PLATFORMTHEME": "",
            "QT_FORCE_STDERR_LOGGING": "1", "QML_DISABLE_DISK_CACHE": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/fixture/no-session-bus",
            "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=/fixture/no-system-bus",
        }
        for key, value in environment.items():
            command.extend(["--setenv", key, value])
        command.extend(["--chdir", "/fixture", "/usr/bin/python3", "/input/run.py"])
        with OwnedCgroup() as group:
            print("Owned all-suite resource group: "
                  + str(group.parent_path / group.name), flush=True)
            reply = run_bounded([
                "/usr/bin/python3", str(base / "cgroup_exec.py"), str(group.procs),
                *command,
            ], env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
                timeout=50, maximum=1024 * 1024, pass_fds=(group.procs,))
        print((reply.stdout + reply.stderr).decode(errors="replace"), end="", flush=True)
    print("Owned all-suite namespace and staging removed", flush=True)
    if reply.returncode != 0:
        raise RuntimeError("isolated all-suite service fixture failed")
    marker = b"ALL24 SCOPED SERVICE PUBLICATION/RETIREMENT PASSED"
    if marker not in reply.stdout:
        raise RuntimeError("all-suite scoped-service marker absent")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        raise SystemExit("all24-scoped-service-regression: " + str(error)) from error
