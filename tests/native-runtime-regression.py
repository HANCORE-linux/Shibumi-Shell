#!/usr/bin/env python3
"""Pinned 4.0.3 native-root integration in a private Bubblewrap namespace.

Only State/Bar/Control Center; explicit window/Health substitutions and no
native platform services. This is not complete-host or desktop acceptance.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from lib.isolated_process import run_bounded
from lib.source_snapshot import snapshot, fingerprint, materialize
from lib.owned_cgroup import OwnedCgroup

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "0534987009061cbe2dacdde4ad564092ab698d12"
# SHA256 of canonical JSON inventory records: path relative to shell/, sha256,
# size, executable; sort_keys=True, separators=(',', ':'), records sorted by path.
# Derived from all 183 Git-blob-verified files at the exact commit above.
SHELL_FINGERPRINT = "2cd0ffb0c38f31868e28c3556f0efc530f4fcd04765856ec157bc070eac748a0"
PLUGINS = ("hancore.shibumi.state", "hancore.shibumi.bar", "hancore.shibumi.control-center")


def admitted_native(path):
    files = snapshot(path)
    if len(files) != 183 or fingerprint(files) != SHELL_FINGERPRINT:
        raise ValueError("native shell does not match pinned 4.0.3 source")
    return files


def stage(base, native):
    materialize(native, base / "omarchy/shell")
    for name in ("home/.config/omarchy/plugins", "cache", "data", "state", "run", "bin"):
        (base / name).mkdir(parents=True, exist_ok=True)
    (base / "run").chmod(0o700)
    plugins = base / "home/.config/omarchy/plugins"
    identities = {}
    for name in PLUGINS:
        source = snapshot(ROOT / name)
        identities[name] = fingerprint(source)
        materialize(source, plugins / name)
        (plugins / name / ".shibumi-managed.json").write_text(json.dumps({
            "suiteId": "hancore.shibumi", "suitePayloadDigest": "a" * 64}))
    fixtures = snapshot(ROOT / "tests/fixtures")
    helpers = snapshot(ROOT / "tests/lib")
    substitutions = {
        "home/.config/omarchy/plugins/hancore.shibumi.bar/core/BarPanel.qml": "BarPanelStub.qml",
        "home/.config/omarchy/plugins/hancore.shibumi.control-center/ShibumiPanel.qml": "ShibumiPanelTest.qml",
        "home/.config/omarchy/plugins/hancore.shibumi.control-center/manager/shibumi-health": "slow-health-report",
        "omarchy/shell/plugins/bar/Bar.qml": "native-runtime/StockBar.qml",
    }
    for target, source in substitutions.items():
        (base / target).write_bytes(fixtures[source][0])
    for name, kind, entry in (("hancore.shibumi.bar", "bar", "FixtureBar.qml"),
                              ("hancore.shibumi.state", "service", "FixtureState.qml"),
                              ("hancore.shibumi.control-center", "service", "FixtureCatalogService.qml")):
        (plugins / name / entry).write_bytes(fixtures["native-runtime/" + entry][0])
        manifest_path = plugins / name / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["entryPoints"][kind] = entry
        manifest_path.write_text(json.dumps(manifest))
    # Constructed inert service, not a foreign manifest or production roster.
    # Its enabled state changes independently of placement; native metadata
    # re-registration can still increment the widget revision.
    catalog_fixture = plugins / "fixture.catalog-service"
    catalog_fixture.mkdir()
    (catalog_fixture / "manifest.json").write_text(json.dumps({
        "schemaVersion": 1, "id": "fixture.catalog-service", "name": "Catalog fixture service",
        "version": "1.0.0", "kinds": ["service"], "entryPoints": {"service": "Service.qml"}}))
    (catalog_fixture / "Service.qml").write_text('import QtQuick\nQtObject {}\n')
    # Host-scanned, initially disabled third-party widget for the complete
    # scoped UI toggle path. No preloaded Component can authorize the add;
    # the current native catalog identity and active-Bar writer must suffice.
    native_widget = plugins / "fixture.native-widget"
    native_widget.mkdir()
    (native_widget / "manifest.json").write_text(json.dumps({
        "schemaVersion": 1, "id": "fixture.native-widget", "name": "Native Fixture Widget",
        "version": "1.2.3", "author": "Fixture Author",
        "description": "Searchable native fixture metadata", "tags": ["native", "searchable"],
        "kinds": ["bar-widget"], "entryPoints": {"barWidget": "Widget.qml"},
        "barWidget": {"displayName": "Native Fixture Widget",
            "description": "Searchable widget description", "category": "Fixture",
            "semanticCapabilities": [], "defaultSection": "left", "allowMultiple": False}}))
    (native_widget / "Widget.qml").write_text('import QtQuick\nItem { implicitWidth: 1; implicitHeight: 1 }\n')
    # Inert suite-owned fixed-group row for the return-to-Shibumi path. It has
    # no service/backend entry point and renders only the one-pixel fixture.
    shibumi_audio = plugins / "hancore.shibumi.audio"
    shibumi_audio.mkdir()
    (shibumi_audio / ".shibumi-managed.json").write_text(json.dumps({
        "suiteId": "hancore.shibumi", "suitePayloadDigest": "a" * 64}))
    (shibumi_audio / "manifest.json").write_text(json.dumps({
        "schemaVersion": 1, "id": "hancore.shibumi.audio", "name": "Shibumi Audio",
        "version": "0.1.1-beta.12", "kinds": ["bar-widget"],
        "entryPoints": {"barWidget": "Widget.qml"},
        "x-shibumi": {"suiteId": "hancore.shibumi"},
        "barWidget": {"displayName": "Shibumi Audio", "category": "Audio",
            "semanticCapabilities": [], "defaultSection": "right", "allowMultiple": False}}))
    (shibumi_audio / "Widget.qml").write_text(
        'import QtQuick\nItem { implicitWidth: 1; implicitHeight: 1 }\n')
    # A catalog-only clone of the pinned native audio capability exercises
    # provider replacement and exact async Undo without loading the disabled
    # native audio implementation or any platform backend.
    audio_provider = plugins / "fixture.audio-provider"
    audio_provider.mkdir()
    (audio_provider / "manifest.json").write_text(json.dumps({
        "schemaVersion": 1, "id": "fixture.audio-provider", "name": "Fixture Audio Provider",
        "version": "1.0.0", "kinds": ["bar-widget"],
        "entryPoints": {"barWidget": "Widget.qml"},
        "omarchy": {"clonedFrom": "omarchy.audio"},
        "barWidget": {"displayName": "Fixture Audio Provider", "category": "Audio",
            "semanticCapabilities": [], "defaultSection": "right", "allowMultiple": False}}))
    (audio_provider / "Widget.qml").write_text(
        'import QtQuick\nItem { implicitWidth: 1; implicitHeight: 1 }\n')
    (base / "run.py").write_bytes(fixtures["native-runtime/probe.py"][0])
    (base / "lib").mkdir()
    for name in ("isolated_process.py", "source_snapshot.py", "isolated_files.py"):
        (base / "lib" / name).write_bytes(helpers[name][0])
    (base / "cgroup_exec.py").write_bytes(helpers["cgroup_exec.py"][0])
    native_ids = []
    withheld = []
    for name, (data, _) in native.items():
        path = Path(name)
        if path.parts[0] != "plugins" or not (path.name == "manifest.json" or path.name.endswith(".manifest.json")):
            continue
        plugin_id = json.loads(data)["id"]
        native_ids.append(plugin_id)
        if plugin_id not in ("omarchy.bar", "omarchy.audio"):
            manifest = base / "omarchy/shell" / name
            manifest.rename(manifest.with_name(manifest.name + ".fixture-disabled"))
            withheld.append(name)
    config = {"version": 1, "bar": {"id": "omarchy.bar", "style": "shibumi",
        "position": "top", "transparent": True,
        "layout": {"left": ["hancore.shibumi.control-center"], "center": [], "right": []},
        "unrelated": {"nested": [1, 2]},
        "shibumi": {"version": 1, "presentation": {"accent": "color04"}}},
        "plugins": ["fixture.before-state",
                    {"id": "hancore.shibumi.state", "unrelated": {"deep": [1, {"keep": True}]},
                     "shibumiStateSchemaVersion": 1,
                     "shibumi": {"version": 1, "presentation": {"accent": "color04"}}},
                    "fixture.after-state"],
        "disabledPlugins": sorted(native_ids)}
    (base / "omarchy/config/omarchy").mkdir(parents=True)
    for target in ("omarchy/config/omarchy/shell.json", "home/.config/omarchy/shell.json"):
        (base / target).write_text(json.dumps(config))
    # No production Omarchy helpers or compositor/system-device commands in PATH.
    for name in ("bash", "find", "sort", "cat", "dirname", "mkdir", "awk", "basename",
                 "grep", "sed", "tr", "inotifywait", "fc-match", "timeout", "sleep", "touch", "date"):
        target = Path("/usr/bin") / name
        if not target.is_file():
            raise ValueError("missing fixture dependency: " + name)
        (base / "bin" / name).symlink_to(target)
    print(json.dumps({"nativeCommit": COMMIT, "nativeFingerprint": SHELL_FINGERPRINT,
        "suiteWipFingerprints": identities, "fixtureFingerprint": fingerprint(fixtures),
        "helperFingerprint": fingerprint(helpers), "windowHealthSubstitutions": substitutions,
        "nativeManifestsWithheld": withheld,
        "catalogWrapper": "native-runtime/FixtureCatalogService.qml",
        "constructedCatalogFixture": "fixture.catalog-service"}), flush=True)


def run(base, required_markers=None):
    if required_markers is None:
        required_markers = (b"NATIVE STATE/BAR/WIDGET/PANEL, KEEPLOADED AND REVOCATION PASSED",
            b"COLD-STOCK AND SUITE SERVICE-ENTRY WRITES PASSED",
            b"ACTUAL CATALOG QPROCESS/HELPER/PINNED NATIVE IPC AND DEMAND RELEASE PASSED",
            b"DEMANDED CATALOG RECONCILED EXTERNAL SERVICE CHANGE",
            b"ACTUAL NONEMPTY NATIVE DTO, PAGE LEASE/STALE REBIND AND TOGGLE SETTLEMENT PASSED",
            b"NATIVE FIXED-GROUP VISIBILITY AND STATE-ONLY SETTLEMENT PASSED",
            b"ACTUAL V1/V2 PROVIDER UNDO SETTLEMENT AND STALE-SNAPSHOT REFUSAL PASSED",
            b"ACTUAL STATE READBACK THEN NATIVE LAYOUT/INJECTED BAR CONFIRMATION PASSED")
    if (not isinstance(required_markers, tuple) or not 1 <= len(required_markers) <= 8
            or any(not isinstance(value, bytes) or not 1 <= len(value) <= 256 for value in required_markers)):
        raise ValueError("invalid native fixture marker contract")
    command = ["/usr/bin/bwrap", "--die-with-parent", "--new-session", "--unshare-user",
        "--unshare-pid", "--unshare-ipc", "--unshare-net", "--ro-bind", "/usr", "/usr",
        "--symlink", "usr/bin", "/bin", "--symlink", "usr/lib", "/lib",
        "--symlink", "usr/lib", "/lib64", "--ro-bind", "/etc/fonts", "/etc/fonts",
        "--proc", "/proc", "--dev", "/dev", "--size", str(32 * 1024 * 1024), "--tmpfs", "/tmp",
        "--dir", "/run", "--ro-bind", str(base), "/input",
        "--size", str(64 * 1024 * 1024), "--tmpfs", "/fixture", "--disable-userns"]
    environment = {"HOME": "/fixture/home", "XDG_CONFIG_HOME": "/fixture/home/.config",
        "XDG_STATE_HOME": "/fixture/state", "XDG_CACHE_HOME": "/fixture/cache",
        "XDG_DATA_HOME": "/fixture/data", "XDG_DATA_DIRS": "/fixture/data",
        "XDG_RUNTIME_DIR": "/fixture/run", "OMARCHY_PATH": "/fixture/omarchy",
        "PATH": "/fixture/bin", "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
        "QT_QPA_PLATFORMTHEME": "", "QT_FORCE_STDERR_LOGGING": "1",
        "QML_DISABLE_DISK_CACHE": "1", "PYTHONDONTWRITEBYTECODE": "1",
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=/fixture/no-session-bus",
        "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=/fixture/no-system-bus"}
    for name, value in environment.items():
        command.extend(["--setenv", name, value])
    command.extend(["--chdir", "/fixture", "/usr/bin/python3", "/input/run.py"])
    with OwnedCgroup() as group:
        print("Owned native resource group: " + str(group.parent_path / group.name), flush=True)
        launcher = ["/usr/bin/python3", str(base / "cgroup_exec.py"), str(group.procs), *command]
        reply = run_bounded(launcher, env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
            timeout=42, maximum=1024 * 1024, pass_fds=(group.procs,))
    print((reply.stdout + reply.stderr).decode(errors="replace"), end="", flush=True)
    if reply.returncode != 0:
        raise RuntimeError("isolated native fixture failed: " + str(reply.returncode))
    combined = reply.stdout + reply.stderr
    if (b"attempted to evaluate a function in an invalid context" in combined
            or b"TypeError" in combined or b"ReferenceError" in combined):
        raise RuntimeError("native fixture reported a stale or invalid QML context")
    for marker in required_markers:
        if marker not in reply.stdout:
            raise RuntimeError("native fixture success marker missing: " + marker.decode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-shell", required=True, type=Path)
    parser.add_argument("--admit-only", action="store_true")
    args = parser.parse_args()
    native = admitted_native(args.native_shell)
    if args.admit_only:
        print("Pinned native 4.0.3 source admitted: " + SHELL_FINGERPRINT)
        return
    with tempfile.TemporaryDirectory(prefix="shibumi-native-runtime-", dir="/tmp") as temporary:
        base = Path(temporary)
        try:
            stage(base, native)
            run(base)
        finally:
            print("Owned native namespace run finished; removing " + str(base), flush=True)
    if base.exists():
        raise RuntimeError("owned native fixture cleanup failed")
    print("Owned native fixture directory removed", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        raise SystemExit("native-runtime-regression: " + str(error)) from error
