"""Only inside the maintained private pinned-native Bubblewrap fixture."""
import json
import re
import resource
import shutil
import subprocess
import time
from pathlib import Path
from lib.isolated_process import run_bounded, finish_owned_group
from lib.isolated_files import read_regular

BASE = Path("/fixture")
shutil.copytree("/input", BASE, dirs_exist_ok=True, symlinks=True)
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024 * 1024, 16 * 1024 * 1024))
DEADLINE = time.monotonic() + 25

EXACT_LOG_LINES = {
    '  INFO: Launching config: "/fixture/omarchy/shell/shell.qml"': 1,
    '  INFO: Configuration Loaded': 1,
    '  WARN : Failed to create wl_display (No such file or directory)': 1,
    ' DEBUG qml: omarchy-shell paths omarchyPath=/fixture/omarchy shellDir=/fixture/omarchy/shell firstPartyPluginsDir=/fixture/omarchy/shell/plugins defaultsPath=/fixture/omarchy/config/omarchy/shell.json userConfigPath=/fixture/home/.config/omarchy/shell.json': 1,
    '  WARN: Process failed to start, likely because the binary could not be found. Command: QList("hyprctl", "-j", "getoption", "decoration:rounding")': 2,
    '  WARN: Process failed to start, likely because the binary could not be found. Command: QList("hyprctl", "-j", "getoption", "general:gaps_out")': 2,
    '  WARN scene: file:///fixture/home/.config/omarchy/plugins/fixture.catalog-failure/Bar.qml[2:8]: Required property fixtureCatalogFailure was not initialized': 1,
    '  WARN qml: bar option fixture.catalog-failure failed to load, falling back to omarchy.bar': 1,
}
DYNAMIC_LOG_LINES = (
    (re.compile(r'^  INFO: Shell ID: "([0-9a-f]{32})" Path ID "\1"$'), 1),
    (re.compile(r'^  INFO: Saving logs to "/fixture/run/quickshell/by-id/[a-z0-9]{1,64}/log\.qslog"$'), 1),
)


def check(value, message):
    if not value:
        raise RuntimeError(message)


def ipc(target, method, *args):
    left = DEADLINE - time.monotonic()
    check(left > 0, "fallback fixture deadline")
    result = run_bounded(["/usr/bin/quickshell", "ipc", "-p", "/fixture/omarchy/shell",
        "call", "--", target, method, *args], timeout=min(3, left), maximum=65536)
    return result.returncode, result.stdout.decode().strip()


def active(rows):
    return [row["id"] for row in rows if row["active"]]


def validate_native_log(text):
    lines = [line for line in text.splitlines() if line]
    allowed = set(EXACT_LOG_LINES)
    dynamic_counts = [0] * len(DYNAMIC_LOG_LINES)
    unexpected = []
    for line in lines:
        if line in allowed:
            continue
        matched = False
        for index, (pattern, _) in enumerate(DYNAMIC_LOG_LINES):
            if pattern.fullmatch(line):
                dynamic_counts[index] += 1
                matched = True
                break
        if not matched:
            unexpected.append(line)
    check(not unexpected, "unexpected native runtime diagnostic: " + repr(unexpected[:3]))
    for line, expected_count in EXACT_LOG_LINES.items():
        check(lines.count(line) == expected_count,
            "native log diagnostic count mismatch: " + repr(line))
    for index, (_, expected_count) in enumerate(DYNAMIC_LOG_LINES):
        check(dynamic_counts[index] == expected_count,
            "native dynamic log line count mismatch: " + str(index))


with (BASE / "native.log").open("xb") as log:
    process = subprocess.Popen(["/usr/bin/quickshell", "-p", "/fixture/omarchy/shell", "--no-color"],
        stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        while True:
            code, text = ipc("native-catalog-probe", "status")
            if code == 0 and text.startswith("{") and json.loads(text)["admitted"]:
                break
            time.sleep(.05)
        check(ipc("shell", "enablePlugin", "fixture.catalog-failure", "{}") == (0, "ok"),
            "fixture bar select failed")
        while True:
            code, text = ipc("fixture-catalog-fallback", "status")
            if code == 0 and text.startswith("{"):
                value = json.loads(text)
                if value["last"] and active(value["live"]) == ["omarchy.bar"]:
                    break
            time.sleep(.02)
        print("FALLBACK_OBSERVATION " + json.dumps(value), flush=True)
        check(value["sameApi"] and value["sameService"], "fallback replaced source identity")
        before = value
        for _ in range(5):
            time.sleep(.1)
            code, text = ipc("fixture-catalog-fallback", "status")
            check(code == 0, "fallback status lost")
            value = json.loads(text)
            check(value == before, "fallback observation not quiet")
        check(ipc("shell", "ping") == (0, "ok"), "native shell stopped responding")
        check(active(value["last"]["dto"]) == ["fixture.catalog-failure"],
            "last public hint did not capture selected failed bar")
        print("ACTUAL NATIVE FALLBACK CHANGED DTO WITHOUT PUBLIC HINT PASSED", flush=True)
    finally:
        finish_owned_group(process)
        log.flush()
        text = read_regular(BASE / "native.log", 1024 * 1024).decode()
        print("NATIVE_LOG_BEGIN\n" + text + "\nNATIVE_LOG_END", flush=True)
        validate_native_log(text)
