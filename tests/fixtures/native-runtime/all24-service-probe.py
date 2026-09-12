"""Private pinned-native all-suite scoped service publication probe."""
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import time

from lib.isolated_files import read_regular
from lib.isolated_process import finish_owned_group, run_bounded

BASE = Path("/fixture")
shutil.copytree("/input", BASE, dirs_exist_ok=True, symlinks=True)
LIMIT = 1024 * 1024
DEADLINE = time.monotonic() + 35
resource.setrlimit(resource.RLIMIT_FSIZE, (16 * LIMIT, 16 * LIMIT))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
roster = json.loads(read_regular(BASE / "all24-roster.json", 65536))
plugin_ids = roster["plugins"]
service_ids = roster["services"]


def ipc(target, method):
    remaining = DEADLINE - time.monotonic()
    if remaining <= 0:
        raise RuntimeError("all-suite service deadline")
    reply = run_bounded([
        "/usr/bin/quickshell", "ipc", "-p", "/fixture/omarchy/shell",
        "call", "--", target, method,
    ], timeout=min(5, remaining), maximum=65536)
    if reply.returncode != 0:
        return None
    try:
        return json.loads(reply.stdout)
    except (ValueError, UnicodeError):
        return None


def exact_services(rows, published):
    if not isinstance(rows, list) or len(rows) != len(service_ids):
        return False
    by_id = {row.get("id"): row for row in rows if isinstance(row, dict)}
    if set(by_id) != set(service_ids):
        return False
    for plugin_id in service_ids:
        row = by_id[plugin_id]
        if row.get("published") is not published:
            return False
        if published and not all(row.get(key) is True for key in (
                "exactOwner", "manifestBound", "scopedHostBound")):
            return False
    return True


with (BASE / "native.log").open("xb") as log:
    process = subprocess.Popen([
        "/usr/bin/quickshell", "-p", "/fixture/omarchy/shell", "--no-color",
    ], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        final = None
        stable_since = None
        while time.monotonic() < DEADLINE:
            if os.waitid(os.P_PID, process.pid,
                         os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None:
                raise RuntimeError("all-suite native root exited")
            if (BASE / "native.log").stat().st_size > LIMIT:
                raise RuntimeError("all-suite native log limit")
            status = ipc("native-runtime-probe", "status")
            catalog = ipc("shell", "listPlugins")
            services = ipc("native-runtime-probe", "scopedServiceRoster")
            if isinstance(catalog, list) and isinstance(status, dict):
                catalog_rows = [entry for entry in catalog
                                if isinstance(entry, dict)
                                and entry.get("id") in plugin_ids]
                by_id = {entry["id"]: entry for entry in catalog_rows}
                ready = (len(by_id) == len(catalog_rows) == 24
                         and status.get("barRegistered")
                         and status.get("stateReady")
                         and exact_services(services, True))
                if ready:
                    if stable_since is None:
                        stable_since = time.monotonic()
                    final = {"plugins": catalog_rows, "status": status,
                             "services": services}
                    if time.monotonic() - stable_since >= 1.5:
                        break
                else:
                    stable_since = None
            time.sleep(0.1)
        if final is None or stable_since is None:
            raise RuntimeError("all-suite scoped services never became ready")
        print("ALL24_SCOPED_SERVICES " + json.dumps(final, sort_keys=True), flush=True)
        missing = [entry["id"] for entry in final["plugins"]
                   if not entry.get("enabled")]
        if missing:
            raise RuntimeError("all-suite configured roots not enabled: " + repr(missing))

        marker = (BASE / "home/.config/omarchy/plugins"
                  / "hancore.shibumi.state/.shibumi-managed.json")
        marker.write_text(json.dumps({
            "suiteId": "hancore.shibumi", "suitePayloadDigest": "d" * 64,
        }), encoding="utf-8")
        for _ in range(30):
            services = ipc("native-runtime-probe", "scopedServiceRoster")
            if exact_services(services, False):
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("runtime retirement retained scoped service publication")
        print("ALL24 SCOPED SERVICE PUBLICATION/RETIREMENT PASSED", flush=True)
    finally:
        finish_owned_group(process)
        log.flush()
        runtime_log = read_regular(BASE / "native.log", LIMIT).decode(errors="replace")
        print("ALL24_LOG_BEGIN\n" + runtime_log + "\nALL24_LOG_END", flush=True)

    checked_log = runtime_log.replace(
        " ERROR quickshell.service.pipewire.loop: Failed to connect pipewire context. Errno: 112", "")
    if any(token in checked_log for token in (
            " ERROR ", "TypeError", "ReferenceError", "Binding loop",
            "Cannot assign", "Unable to assign", "Internal error")):
        raise RuntimeError("all-suite construction found runtime errors")
