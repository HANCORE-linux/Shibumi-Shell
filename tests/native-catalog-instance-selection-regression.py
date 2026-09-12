#!/usr/bin/env python3
"""Prove catalog IPC binds to its owning PID when one shell path overlaps."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from lib.isolated_process import finish_owned_group, run_bounded
from lib.owned_cgroup import OwnedCgroup

ROOT = Path(__file__).resolve().parents[1]
HELPER = (ROOT / "hancore.shibumi.control-center/manager"
          / "shibumi-native-catalog")
QML = b'''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  IpcHandler {
    target: "shell"
    function listPlugins(): string {
      return JSON.stringify([{id: Quickshell.env("CATALOG_SELECTION_ID"),
        name: Quickshell.env("CATALOG_SELECTION_ID"), kinds: ["bar-widget"],
        enabled: false, active: false, canDisable: true, firstParty: true,
        clonedFrom: ""}])
    }
  }
}
'''


def check(value, message):
    if not value:
        raise RuntimeError(message)


def invoke(command, environment, group, timeout=3):
    return run_bounded([
        "/usr/bin/python3", str(ROOT / "tests/lib/cgroup_exec.py"),
        str(group.procs), *command,
    ], env=environment, timeout=timeout, maximum=65536,
       pass_fds=(group.procs,))


def wait_for(command, environment, group, expected):
    end = time.monotonic() + 4
    latest = None
    while time.monotonic() < end:
        latest = invoke(command, environment, group)
        if latest.returncode == 0 and latest.stdout.strip() == expected:
            return
        time.sleep(.05)
    raise RuntimeError("overlapping shell IPC did not become ready: "
                       + repr(latest.stdout if latest else b""))


with tempfile.TemporaryDirectory(prefix="shibumi-catalog-selection-",
                                 dir="/tmp") as temporary:
    base = Path(temporary)
    shell = base / "shell"
    runtime = base / "runtime"
    shell.mkdir()
    runtime.mkdir(mode=0o700)
    (shell / "shell.qml").write_bytes(QML)
    for identity in ("older", "newer"):
        plugin = shell / "plugins" / identity
        plugin.mkdir(parents=True)
        (plugin / "manifest.json").write_text(json.dumps({
            "schemaVersion": 1, "id": identity, "name": identity,
            "version": "1.0.0", "description": identity + " metadata",
            "kinds": ["bar-widget"], "entryPoints": {"barWidget": "Widget.qml"},
            "barWidget": {"defaultSection": "right"},
        }))
    common = {
        "HOME": str(base / "home"),
        "XDG_CONFIG_HOME": str(base / "config"),
        "XDG_STATE_HOME": str(base / "state"),
        "XDG_CACHE_HOME": str(base / "cache"),
        "XDG_DATA_HOME": str(base / "data"),
        "XDG_DATA_DIRS": str(base / "data"),
        "XDG_RUNTIME_DIR": str(runtime),
        "PATH": "/usr/bin:/bin",
        "LANG": "C.UTF-8",
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QUICK_BACKEND": "software",
        "QT_FORCE_STDERR_LOGGING": "1",
        "QML_DISABLE_DISK_CACHE": "1",
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(base / "no-session"),
        "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(base / "no-system"),
    }
    for name in ("home", "config", "state", "cache", "data"):
        (base / name).mkdir()

    processes = []
    with OwnedCgroup() as group:
        prefix = ["/usr/bin/python3", str(ROOT / "tests/lib/cgroup_exec.py"),
                  str(group.procs), "/usr/bin/quickshell", "-p", str(shell),
                  "--no-color"]
        try:
            for identity in ("older", "newer"):
                environment = dict(common, CATALOG_SELECTION_ID=identity)
                process = subprocess.Popen(prefix, env=environment,
                                           stdin=subprocess.DEVNULL,
                                           stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL,
                                           start_new_session=True,
                                           pass_fds=(group.procs,))
                processes.append(process)
                exact = ["/usr/bin/python3", "-I", "-S", str(HELPER),
                         "--shell", str(shell), "--pid", str(process.pid)]
                expected = json.dumps([{"id": identity, "name": identity,
                    "kinds": ["bar-widget"], "enabled": False, "active": False,
                    "canDisable": True, "firstParty": True, "clonedFrom": "",
                    "description": identity + " metadata", "author": "", "version": "1.0.0",
                    "tags": [], "barWidget": {"displayName": "", "description": "",
                        "category": "", "semanticCapabilities": [], "defaultSection": "right",
                        "allowMultiple": False}}], ensure_ascii=False,
                    separators=(",", ":")).encode()
                wait_for(exact, common, group, expected)

            ambiguous = ["/usr/bin/quickshell", "ipc", "-p", str(shell),
                         "call", "--", "shell", "listPlugins"]
            wait_for(ambiguous, common, group,
                     b'[{"id":"older","name":"older","kinds":["bar-widget"],"enabled":false,"active":false,"canDisable":true,"firstParty":true,"clonedFrom":""}]')
            newer = ["/usr/bin/python3", "-I", "-S", str(HELPER),
                     "--shell", str(shell), "--pid", str(processes[1].pid)]
            reply = invoke(newer, common, group)
            check(reply.returncode == 0
                  and json.loads(reply.stdout)[0]["id"] == "newer"
                  and json.loads(reply.stdout)[0]["description"] == "newer metadata",
                  "catalog helper selected the older same-path shell")
            wrong_path = ["/usr/bin/python3", "-I", "-S", str(HELPER),
                          "--shell", str(base / "wrong/shell"), "--pid",
                          str(processes[1].pid)]
            refused = invoke(wrong_path, common, group)
            check(refused.returncode != 0 and not refused.stdout,
                  "exact PID was accepted under the wrong shell directory")
        finally:
            for process in reversed(processes):
                finish_owned_group(process)

print("native catalog exact-PID overlap selection passed; isolated shells removed")
