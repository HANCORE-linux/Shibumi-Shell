"""Runs only inside native-runtime-regression.py's private Bubblewrap namespace."""
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import time
from lib.isolated_process import run_bounded, finish_owned_group
from lib.isolated_files import read_regular

BASE = Path("/fixture")
# /input is admitted read-only staging. All runtime writes stay on quota-sized
# tmpfs inside the resource-limited namespace, not in the host staging tree.
shutil.copytree("/input", BASE, dirs_exist_ok=True, symlinks=True)
LIMIT = 1024 * 1024
# The Icons coalescing negative control adds one complete native State
# settlement before the existing provider/catalog matrix. The measured total
# was 59.97 s versus 59.47 s before cleanup (about 0.5 s inclusive overhead),
# so 85 s leaves 10 s below the unchanged 95 s runner timeout.
DEADLINE = time.monotonic() + 85
PROBE_STARTED = DEADLINE - 85
print("NATIVE_TIMING " + json.dumps({"endpoint": "probe-start", "monotonic": PROBE_STARTED, "probeElapsed": 0.0}), flush=True)
# Qt/Quickshell startup uses larger temporary file allocations than its text
# output. A 1 MiB FSIZE cap reproduced SIGXFSZ before QML startup. Keep the
# text/IPC caps below separate from this bounded per-file allocation ceiling.
resource.setrlimit(resource.RLIMIT_FSIZE, (16 * LIMIT, 16 * LIMIT))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def check(value, message):
    if not value:
        raise RuntimeError(message)


def ipc(target, method, *args):
    remaining = DEADLINE - time.monotonic()
    check(remaining > 0, "native fixture deadline")
    reply = run_bounded(["/usr/bin/quickshell", "ipc", "-p", "/fixture/omarchy/shell",
        "call", "--", target, method, *args], timeout=min(8, remaining), maximum=65536)
    return reply.returncode, reply.stdout.decode().strip()


def wait_status(target, predicate, timeout=5):
    deadline = min(DEADLINE, time.monotonic() + timeout)
    last = None
    while time.monotonic() < deadline:
        ended = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        check(ended is None, "native host exited: " + repr(ended))
        check((BASE / "native.log").stat().st_size < LIMIT, "native log limit")
        code, text = ipc(target, "status")
        if code == 0 and text.startswith("{"):
            value = json.loads(text)
            last = value
            if predicate(value):
                return value
        else:
            last = {"code": code, "text": text[:512]}
        time.sleep(.05)
    raise RuntimeError("native status deadline: " + target
                       + " last=" + json.dumps(last, sort_keys=True))


def persisted(predicate):
    deadline = min(DEADLINE, time.monotonic() + 2)
    while time.monotonic() < deadline:
        path = BASE / "home/.config/omarchy/shell.json"
        value = json.loads(read_regular(path, LIMIT))
        if predicate(value):
            return value
        time.sleep(.05)
    raise RuntimeError("native disk publication missing")


def state_settings(value):
    return next(entry["shibumi"] for entry in value["plugins"]
                if isinstance(entry, dict) and entry.get("id") == "hancore.shibumi.state")


def host_config():
    code, text = ipc("shell", "listShellConfig")
    check(code == 0, "native config readback failed")
    value = json.loads(text)
    check(isinstance(value, dict), "native config readback shape")
    return value


def own_entry_write(label, previous=None):
    before = host_config()
    entries = [entry for entry in before["plugins"]
               if isinstance(entry, dict) and entry.get("id") == "hancore.shibumi.state"]
    check(len(entries) == 1, "State service entry is not unique")
    check(entries[0].get("unrelated") == {"deep": [1, {"keep": True}]},
          "State entry lost unrelated fields")
    if previous is not None:
        check({key: value for key, value in entries[0].items() if key != "shibumi"}
              == {key: value for key, value in previous.items() if key != "shibumi"},
              "bar transition/rescan lost service envelope")
    next_entry = json.loads(json.dumps(entries[0]))
    next_entry["fixtureSettings"] = {"version": 1, "fixtureLabel": label,
        "widgets": {"G8": {"omarchy.clock": {"nested": {"values": [0, False, "Malmö"]}}}}}
    expected = json.loads(json.dumps(before))
    expected["plugins"] = [next_entry if isinstance(entry, dict) and entry.get("id") == "hancore.shibumi.state" else entry
                           for entry in expected["plugins"]]
    encoded = json.dumps(next_entry, ensure_ascii=False)
    check(ipc("native-state-probe", "inlineEntry", "hancore.shibumi.state", encoded)
          == (0, "changed"), "native own-entry write refused: " + label)
    check(host_config() == expected, "own-entry write altered unrelated config: " + label)
    persisted(lambda value: value == expected)
    check(ipc("native-state-probe", "inlineEntry", "hancore.shibumi.state", encoded)
          == (0, "unchanged"), "identical own-entry write reported changed")
    check(ipc("native-state-probe", "inlineEntry", "hancore.shibumi.control-center", encoded)
          == (0, "unchanged"), "service acquired foreign entry authority")
    check(host_config() == expected, "no-op/foreign refusal changed config")
    return next_entry


def catalog_probe():
    idle = wait_status("native-catalog-probe", lambda value: value["admitted"])
    check(not idle["ready"] and not idle["nativeConstructed"] and idle["requestSerial"] == 0,
          "undemanded catalog constructed native work")
    original = host_config()
    check(ipc("native-catalog-probe", "acquire") == (0, "requested"), "catalog demand refused")
    ready = wait_status("native-catalog-probe", lambda value: value["ready"] and not value["refreshing"])
    code, text = ipc("shell", "listPlugins")
    native_rows = json.loads(text)
    public_rows = ready["snapshot"]["entries"]
    native_fields = ("id", "name", "kinds", "enabled", "active", "canDisable", "firstParty", "clonedFrom")
    check(code == 0 and ready["nativeConstructed"]
          and ready["snapshot"]["catalogKind"] == "native-listPlugins"
          and [{key: row[key] for key in native_fields} for row in public_rows] == native_rows,
          "actual native catalog identity DTO mismatch")
    control = ready["snapshot"]["byId"]["hancore.shibumi.control-center"]
    check(control["description"] and control["author"] == "HANCORE"
          and control["version"] == "0.1.1-beta.15.2"
          and control["barWidget"]["defaultSection"] == "left",
          "package-bound catalog presentation metadata was lost")
    check(host_config() == original, "read-only catalog changed native config")
    check(ready["snapshot"]["byId"]["fixture.catalog-service"]["enabled"] is False,
          "inert service initially enabled")
    started = time.monotonic()
    check(ipc("shell", "setPluginEnabled", "fixture.catalog-service", "true") == (0, "ok"),
          "external inert service enable failed")
    changed = wait_status("native-catalog-probe", lambda value: value["ready"]
        and value["readSerial"] > ready["readSerial"]
        and value["snapshot"]["byId"]["fixture.catalog-service"]["enabled"] is True, timeout=7)
    # Native pluginsChanged also re-registers existing widget metadata, so this
    # change does not isolate a missing widget signal or establish polling need.
    print("DEMANDED CATALOG RECONCILED EXTERNAL SERVICE CHANGE " + json.dumps({
        "seconds": round(time.monotonic() - started, 3),
        "widgetRevisionBefore": ready["widgetRevision"], "widgetRevisionAfter": changed["widgetRevision"],
        "readSerialBefore": ready["readSerial"], "readSerialAfter": changed["readSerial"]}), flush=True)
    check(ipc("native-catalog-probe", "release") == (0, "released"), "catalog release failed")
    released = wait_status("native-catalog-probe", lambda value: not value["ready"]
        and not value["nativeConstructed"] and not value["refreshing"] and value["snapshot"] is None)
    # Span a complete 5s interval; this is not inferred merely from Loader state.
    time.sleep(5.2)
    quiet = wait_status("native-catalog-probe", lambda value: not value["refreshing"])
    check(quiet["requestSerial"] == released["requestSerial"] and not quiet["nativeConstructed"],
          "released catalog kept its reconcile worker")
    check(ipc("shell", "setPluginEnabled", "fixture.catalog-service", "false") == (0, "ok"),
          "external inert service disable failed")
    check(host_config() == original, "inert service control did not restore native config")
    print("ACTUAL CATALOG QPROCESS/HELPER/PINNED NATIVE IPC AND DEMAND RELEASE PASSED", flush=True)


with (BASE / "native.log").open("xb") as log:
    process = subprocess.Popen(["/usr/bin/quickshell", "-p", "/fixture/omarchy/shell", "--no-color"],
        stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        wait_status("native-stock-probe", lambda value: value["ready"] and value["publishedOwner"], timeout=12)
        wait_status("native-state-probe", lambda value: value["registered"] and value["ready"]
                    and not value["hasBar"], timeout=12)
        state_entry = own_entry_write("cold-stock")
        catalog_probe()
        legacy = host_config()["bar"].get("shibumi")
        check(ipc("native-state-probe", "burst") == (0, "queued-without-optimism"), "rapid setters rejected/optimistic")
        wait_status("native-state-probe", lambda value: not value["pending"] and value["writeStatus"] == "confirmed"
                    and value["config"]["widgets"]["G8"].get("omarchy.clock", {}).get("calendar") is True)
        saved = persisted(lambda value: state_settings(value).get("widgets", {}).get("G8", {})
                          .get("omarchy.clock", {}).get("calendar") is True)
        check(state_settings(saved)["widgets"]["G8"]["omarchy.clock"]["format"] == "HH:mm", "rapid setter lost key")
        check(saved["bar"].get("shibumi") == legacy, "State wrote legacy bar settings")
        before_family = host_config()["bar"]
        check(ipc("native-state-probe", "layoutFamily") == (0, "queued-without-optimism"),
              "combined layout/family patch refused or published optimistically")
        wait_status("native-state-probe", lambda value: not value["pending"] and value["writeStatus"] == "confirmed"
                    and value["config"]["order"]["left"][0] == "G2"
                    and value["config"]["v2Boundaries"] == [True, False]
                    and value["config"]["widgets"]["G6"]["enabledV1"] is False
                    and value["config"]["widgets"]["G6"]["enabledV2"] is True
                    and value["transitionProjection"] == value["transitionTarget"])
        family_saved = persisted(lambda value: state_settings(value).get("order", {}).get("left", [None])[0] == "G2")
        check(family_saved["bar"] == before_family, "State-only transition mutated native Bar")
        check(ipc("native-state-probe", "compensateLayoutFamily") == (0, "queued"), "conditional compensation refused")
        wait_status("native-state-probe", lambda value: not value["pending"] and value["writeStatus"] == "confirmed"
                    and value["config"]["order"]["left"][0] == "G1"
                    and value["config"]["v2Boundaries"] == [False, False]
                    and "enabledV1" not in value["config"]["widgets"].get("G6", {})
                    and value["transitionProjection"] == value["transitionBefore"])
        persisted(lambda value: state_settings(value)["order"]["left"][0] == "G1")
        check(host_config()["bar"] == before_family, "State compensation mutated native Bar")
        check(ipc("shell", "enablePlugin", "hancore.shibumi.bar", "{}") == (0, "ok"),
              "suite selection after cold-stock entry write failed")
        initial = wait_status("native-runtime-probe", lambda value:
            value["runtimeReady"] and value["stateReady"] and value["barRegistered"]
            and value["hostRegistryPrimePhase"] == "ready"
            and value["hostRegistryPrimeAttempts"] == 1
            and value["hostReady"] and value["mutationAdmissionReady"], timeout=12)
        check(ipc("native-runtime-probe", "checkSynchronousScopeLoss")
              == (0, "scope-loss-refused"),
              "synchronous scoped-Bar ambiguity admitted mutation")
        state_entry = own_entry_write("suite-bar", state_entry)
        check(ipc("native-runtime-probe", "compact", "true") == (0, "queued"), "native State request refused")
        current = wait_status("native-runtime-probe", lambda value:
            value["config"]["widgets"].get("G4", {}).get("compact") is True)
        check(current["stateSerial"] == initial["stateSerial"], "equivalent refresh churned State")
        check(current["hostBar"]["unrelated"] == {"nested": [1, 2]}, "State changed unrelated bar config")
        persisted(lambda value: state_settings(value)["widgets"].get("G4", {}).get("compact") is True)
        for target in ("shibumi-suite", "shibumi-suite-runtime"):
            check(ipc(target, "verifyPayload", "a" * 64) == (0, "ok"), "payload linkage failed: " + target)
        check(ipc("native-runtime-probe", "rememberState", "native-kept-state") == (0, "ok"), "identity marker failed")
        check(ipc("shell", "rescanPlugins")[0] == 0, "native rescan dispatch failed")
        time.sleep(.6)
        kept = wait_status("native-runtime-probe", lambda value: value["barRegistered"] and value["stateReady"])
        check(kept["stateObjectName"] == "native-kept-state", "rescan replaced keepLoaded State")
        check(kept["config"]["widgets"]["G4"]["compact"] is True, "rescan lost State config")
        check(ipc("native-runtime-probe", "compact", "false") == (0, "queued"), "post-rescan request refused")
        check(ipc("native-runtime-probe", "openControl") == (0, "ok"), "host-registered widget did not load")
        wait_status("native-runtime-probe", lambda value:
            value["panelLoaded"] and value["panelStateMatches"] and value["panelUpdatesMatch"]
            and value["controlObjectCount"] == 1)
        check(ipc("native-runtime-probe", "panelSetting", "true") == (0, "queued"), "actual panel State request refused")
        config = persisted(lambda value: state_settings(value)["widgets"]["G4"]
            .get("appearance", {}).get("v1", {}).get("compact") is True)
        check(config["bar"]["transparent"] is True and config["bar"]["unrelated"] == {"nested": [1, 2]},
            "panel changed unrelated bar settings")
        check((BASE / "run/shibumi-health-fixture-started").is_file(), "inert Health helper did not start")
        wait_status("native-runtime-probe", lambda value: not value["stateWritePending"])
        check(ipc("native-runtime-probe", "panelSettingWithRestore", "false")
              == (0, "queued-awaiting-settlement"), "actual panel did not hold restore for State settlement")
        wait_status("native-runtime-probe", lambda value: not value["stateWritePending"]
                    and not value["restoreWaiting"] and value["restoreCount"] == 1
                    and value["config"]["widgets"]["G4"]["appearance"]["v1"]["compact"] is False)
        persisted(lambda value: state_settings(value)["widgets"]["G4"]["appearance"]["v1"]["compact"] is False)
        check(ipc("native-runtime-probe", "revokeBarDuringRestore", "true")
              == (0, "revoked-with-ready-state"), "Bar revocation retained a pending restore")
        wait_status("native-runtime-probe", lambda value: value["barRegistered"]
                    and not value["stateWritePending"] and value["restoreCount"] == 0
                    and value["config"]["widgets"]["G4"]["appearance"]["v1"]["compact"] is True)

        # Reproduce the Beta.14 Icons regression through the actual panel,
        # BarFunctionsPage and WidgetAppearanceWorkbench. Outside Plugins the
        # durable Bar consumer is the only catalog authority.
        check(ipc("native-runtime-probe", "setCpuVisible", "false") == (0, "queued"),
              "inactive CPU setup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["cpuV1Enabled"])
        check(ipc("native-runtime-probe", "openIcons") == (0, "ok"),
              "actual Control Center Icons page refused")
        wait_status("native-runtime-probe", lambda value:
                    value["panelPage"] == "functions" and value["panelPageReady"]
                    and value["catalogConsumerCount"] == 1
                    and value["panelCatalog"] is not None
                    and "hancore.shibumi.cpu" in value["panelCatalog"]["byId"])
        check(ipc("native-runtime-probe", "malformedCatalogObservationsRefused")
              == (0, "malformed-no-mutation"),
              "malformed immutable catalog shapes reached an Icons mutation")
        icons_state = wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["stateTransitionBusy"]
                    and not value["cpuV1Requested"] and not value["cpuV1Enabled"])
        icons_transition_serial = icons_state["stateTransitionSerial"]
        check(ipc("native-runtime-probe", "activateCpuFromIcons")
              == (0, "queued-without-native-mutation"),
              "V1 Icons CPU activation did not use requested presentation")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["stateTransitionBusy"]
                    and value["stateTransitionSerial"] == icons_transition_serial
                    and value["cpuV1Enabled"] and value["cpuV2Enabled"])

        check(ipc("native-runtime-probe", "setShellStyle", "full") == (0, "queued"),
              "V2 Icons setup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and value["v2Mode"]
                    and value["panelPage"] == "functions" and value["panelPageReady"]
                    and value["catalogConsumerCount"] == 1)
        check(ipc("native-runtime-probe", "setCpuVisible", "false") == (0, "queued"),
              "V2 inactive CPU setup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and value["cpuV1Enabled"]
                    and not value["cpuV2Enabled"])
        check(ipc("native-runtime-probe", "activateCpuFromIcons")
              == (0, "queued-without-native-mutation"),
              "V2 Icons CPU activation did not use its visible action")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["stateTransitionBusy"]
                    and value["stateTransitionSerial"]
                      == icons_transition_serial
                    and value["cpuV1Enabled"] and value["cpuV2Enabled"]
                    and value["cpuV2Requested"])

        check(ipc("native-runtime-probe", "setCpuVisible", "false") == (0, "queued"),
              "missing-authority CPU setup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["cpuV2Enabled"])
        check(ipc("native-runtime-probe", "releaseBarCatalogAndRefuseCpu")
              == (0, "catalog-not-ready-no-mutation"),
              "missing Bar catalog authority mutated CPU or reported a suite-service error")
        check(ipc("native-runtime-probe", "rebindBarCatalog") == (0, "requested"),
              "Bar catalog authority did not rebind")
        wait_status("native-runtime-probe", lambda value:
                    value["catalogConsumerCount"] == 1
                    and value["panelCatalog"] is not None)
        check(ipc("native-runtime-probe", "setCpuVisible", "true") == (0, "queued"),
              "V2 CPU cleanup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and value["cpuV2Enabled"])
        a_started = time.monotonic()
        print("NATIVE_TIMING " + json.dumps({"endpoint": "a-start", "monotonic": a_started, "probeElapsed": a_started - PROBE_STARTED}), flush=True)
        check(ipc("native-runtime-probe", "setShellStyle", "shibumi") == (0, "queued"),
              "V1 restoration after Icons action refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["v2Mode"]
                    and value["panelPage"] == "functions" and value["panelPageReady"]
                    and value["catalogConsumerCount"] == 1)

        check(ipc("native-runtime-probe", "openPlugins") == (0, "ok"),
              "actual Control Center Plugins page refused")
        catalog_page = wait_status("native-runtime-probe", lambda value:
            value["panelPage"] == "plugins" and value["panelPageReady"]
            and value["catalogConsumerCount"] == 2 and value["panelCatalog"] is not None
            and "fixture.native-widget" in value["panelCatalog"]["byId"])
        native_widget = catalog_page["panelCatalog"]["byId"]["fixture.native-widget"]
        check(native_widget["description"] == "Searchable native fixture metadata"
              and native_widget["author"] == "Fixture Author"
              and native_widget["version"] == "1.2.3"
              and native_widget["tags"] == ["native", "searchable"]
              and native_widget["barWidget"]["category"] == "Fixture"
              and native_widget["barWidget"]["defaultSection"] == "left",
              "scoped Plugins UI lost package metadata/search/defaultSection")
        check(ipc("native-runtime-probe", "releasePluginPageCatalogAndRefuseCpu")
              == (0, "page-authoritative-no-fallback"),
              "Plugins page lost authority to the Bar consumer during lease loss")
        catalog_page = wait_status("native-runtime-probe", lambda value:
            value["panelPage"] == "plugins" and value["panelPageReady"]
            and value["catalogConsumerCount"] == 2
            and value["panelCatalog"] is not None)
        check(ipc("native-runtime-probe", "catalogDefaultCannotAuthorize")
              == (0, "refused"),
              "display catalog defaultSection fabricated activation authority")
        check(ipc("native-runtime-probe", "captureCatalog") == (0, "captured"),
              "current page observation capture failed")
        captured_serial = catalog_page["catalogReadSerial"]
        check(ipc("shell", "setPluginEnabled", "fixture.catalog-service", "true") == (0, "ok"),
              "stale-observation setup failed")
        wait_status("native-runtime-probe", lambda value:
                    value["catalogReadSerial"] > captured_serial
                    and value["panelCatalog"]["byId"]["fixture.catalog-service"]["enabled"] is True,
                    timeout=7)
        before_stale = host_config()["bar"]
        check(ipc("native-runtime-probe", "staleCatalogToggle") == (0, "stale-refused")
              and host_config()["bar"] == before_stale,
              "stale catalog observation authorized a layout mutation")
        check(ipc("shell", "setPluginEnabled", "fixture.catalog-service", "false") == (0, "ok"),
              "stale-observation fixture restore failed")
        toggle_code, toggle_result = ipc(
            "native-runtime-probe", "toggleCatalogWidget")
        check((toggle_code, toggle_result)
              == (0, "queued-without-native-mutation"),
              "Plugins UI toggle bypassed serialized State/native transition: "
              + toggle_result)
        check(ipc("native-runtime-probe", "activePluginRemovalRefused",
                  "fixture.native-widget") == (0, "refused-before-process"),
              "pending scoped widget activation started removal")
        enabled_widget = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and value["layoutResult"] == "confirmed"
            and not value["pageTransitionPending"]
            and value["pageFeedbackTitle"] == "Native Fixture Widget activated"
            and value["pageUndoMode"] == "plugin-value"
            and "G:fixture.native-widget" in value["config"]["order"]["left"]
            and any((entry == "fixture.native-widget" or isinstance(entry, dict)
                     and entry.get("id") == "fixture.native-widget")
                    for entry in value["injectedBar"]["layout"]["left"]))
        enabled_entries = [entry for entry in enabled_widget["injectedBar"]["layout"]["left"]
                           if (entry == "fixture.native-widget" or isinstance(entry, dict)
                               and entry.get("id") == "fixture.native-widget")]
        check(len(enabled_entries) == 1 and isinstance(enabled_entries[0], dict)
              and enabled_entries[0].get("shibumiModule") is True,
              "native widget entry lost exact shibumiModule marker")
        a_ended = time.monotonic()
        print("NATIVE_TIMING " + json.dumps({"endpoint": "a-end", "monotonic": a_ended, "probeElapsed": a_ended - PROBE_STARTED, "phaseElapsed": a_ended - a_started}), flush=True)
        enabled_serial = enabled_widget["catalogReadSerial"]
        wait_status("native-runtime-probe", lambda value:
                    value["catalogReadSerial"] > enabled_serial
                    and value["panelCatalog"]["byId"]["fixture.native-widget"]["enabled"] is True,
                    timeout=7)
        check(ipc("native-runtime-probe", "activePluginRemovalRefused",
                  "fixture.native-widget") == (0, "refused-before-process"),
              "active scoped widget without replacement started removal")
        check(ipc("native-runtime-probe", "toggleCatalogWidget")
              == (0, "queued-without-native-mutation"),
              "Plugins UI disable bypassed serialized State/native transition")
        disabled_widget = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and value["layoutResult"] == "confirmed"
            and not value["pageTransitionPending"]
            and value["pageFeedbackTitle"] == "Native Fixture Widget deactivated"
            and value["pageUndoMode"] == "plugin-value"
            and all("G:fixture.native-widget" not in value["config"]["order"][region]
                    for region in ("left", "center", "right"))
            and all(not any((entry == "fixture.native-widget" or isinstance(entry, dict)
                            and entry.get("id") == "fixture.native-widget") for entry in
                           value["injectedBar"]["layout"][region])
                    for region in ("left", "center", "right")))
        disabled_serial = disabled_widget["catalogReadSerial"]
        wait_status("native-runtime-probe", lambda value:
                    value["catalogReadSerial"] > disabled_serial
                    and value["panelCatalog"]["byId"]["fixture.native-widget"]["enabled"] is False,
                    timeout=7)

        # Native B(b): fill all five V1 extension slots with fixed groups,
        # add the real catalog widget in V2, observe the full V1 background
        # reconcile, then free one slot and retry through V2 -> V1.
        b_started = time.monotonic()
        print("NATIVE_TIMING " + json.dumps({"endpoint": "b-start", "monotonic": b_started,
              "probeElapsed": b_started - PROBE_STARTED}), flush=True)
        bb_baseline = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["v2Mode"]
            and all("G:fixture.native-widget" not in value["config"]["order"][region]
                    for region in ("left", "center", "right")))
        baseline_order = json.loads(json.dumps(bb_baseline["config"]["order"]))
        baseline_splits = json.loads(json.dumps(bb_baseline["config"]["splits"]))
        full_order = {
            "left": ["", "", "G3", "G4", "G5", "G6", "G7", "G1", "G2"],
            "center": ["", "G8"],
            "right": ["", "", "G11", "G14", "G12", "G13", "G15", "G9", "G10"],
        }
        check(ipc("native-runtime-probe", "prepareFullV1Capacity") == (0, "queued"),
              "full V1 capacity setup refused")
        full_v1 = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and value["config"]["order"] == full_order)
        full_splits = full_v1["config"]["splits"]
        fixed_ids = ["G" + str(index) for index in range(1, 16)]
        full_values = [group for region in ("left", "center", "right")
                       for group in full_order[region] if group]
        check(sorted(full_values) == sorted(fixed_ids) and len(full_values) == 15,
              "full V1 setup did not preserve each fixed group exactly once")
        check(full_order["left"][:2] == ["", ""]
              and full_order["right"][:2] == ["", ""]
              and full_order["center"][0] == ""
              and full_order["left"][7:] == ["G1", "G2"]
              and full_order["right"][7:] == ["G9", "G10"]
              and full_order["center"][1] == "G8"
              and len(full_splits["left"]) == 8
              and len(full_splits["right"]) == 8
              and len(full_splits["boundaries"]) == 2,
              "full V1 setup did not leave valid base holes and five busy extras")
        persisted(lambda value: state_settings(value)["order"] == full_order
                  and state_settings(value)["splits"] == full_splits)

        check(ipc("native-runtime-probe", "setShellStyle", "full") == (0, "queued"),
              "B(b) V2 setup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["layoutBusy"]
                    and value["v2Mode"] and value["config"]["order"] == full_order)
        check(ipc("native-runtime-probe", "toggleCatalogWidget")
              == (0, "queued-without-native-mutation"),
              "B(b) real V2 catalog add was not serialized")
        v2_added = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and value["layoutResult"] == "confirmed"
            and not value["pageTransitionPending"]
            and "G:fixture.native-widget" in value["config"]["v2Layout"]["left"]
            and any(isinstance(entry, dict)
                    and entry.get("id") == "fixture.native-widget"
                    and entry.get("shibumiModule") is True
                    for entry in value["injectedBar"]["layout"]["left"]))
        persisted(lambda value:
                  state_settings(value)["order"] == full_order
                  and "G:fixture.native-widget" in state_settings(value)["v2Layout"]["left"]
                  and any(isinstance(entry, dict)
                          and entry.get("id") == "fixture.native-widget"
                          and entry.get("shibumiModule") is True
                          for entry in value["bar"]["layout"]["left"]))
        native_added_entries = [entry for entry in host_config()["bar"]["layout"]["left"]
                                if isinstance(entry, dict)
                                and entry.get("id") == "fixture.native-widget"]
        check(len(native_added_entries) == 1
              and native_added_entries[0].get("shibumiModule") is True,
              "B(b) native file readback lost the exact marker")

        check(ipc("native-runtime-probe", "setShellStyle", "shibumi") == (0, "queued"),
              "B(b) full V1 switch refused")
        full_observation = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["v2Mode"] and value["config"]["order"] == full_order
            and all("G:fixture.native-widget" not in value["config"]["order"][region]
                    for region in ("left", "center", "right"))
            and any(isinstance(entry, dict)
                    and entry.get("id") == "fixture.native-widget"
                    and entry.get("shibumiModule") is True
                    for entry in value["injectedBar"]["layout"]["left"])
            and ((not value["unplacedPluginIdsPropertyExists"]
                  and not value["capacityMessagePropertyExists"])
                 or (value["unplacedPluginIds"] == ["fixture.native-widget"]
                     and value["capacityMessage"] != "")))
        persisted(lambda value:
                  state_settings(value)["presentation"]["shellStyle"] == "shibumi"
                  and state_settings(value)["order"] == full_order
                  and all("G:fixture.native-widget" not in state_settings(value)["order"][region]
                          for region in ("left", "center", "right"))
                  and any(isinstance(entry, dict)
                          and entry.get("id") == "fixture.native-widget"
                          and entry.get("shibumiModule") is True
                          for entry in value["bar"]["layout"]["left"]))
        capacity_evidence = {
            "markerIsDict": any(isinstance(entry, dict)
                                and entry.get("id") == "fixture.native-widget"
                                and entry.get("shibumiModule") is True
                                for entry in full_observation["injectedBar"]["layout"]["left"]),
            "hasV1Position": any("G:fixture.native-widget" in full_observation["config"]["order"][region]
                                 for region in ("left", "center", "right")),
            "unplacedPluginIdsPropertyExists": full_observation["unplacedPluginIdsPropertyExists"],
            "unplacedPluginIds": full_observation["unplacedPluginIds"],
            "capacityMessagePropertyExists": full_observation["capacityMessagePropertyExists"],
            "capacityMessage": full_observation["capacityMessage"],
            "pageFeedbackVisible": full_observation["pageFeedbackVisible"],
            "pageFeedbackTitle": full_observation["pageFeedbackTitle"],
            "pageFeedbackDetail": full_observation["pageFeedbackDetail"],
        }
        check(capacity_evidence["markerIsDict"]
              and not capacity_evidence["hasV1Position"],
              "B(b) full V1 observation did not retain the marker without a position")
        print("NATIVE_BB_FULL_V1_EVIDENCE "
              + json.dumps(capacity_evidence, sort_keys=True), flush=True)
        bb_capacity_warning = (
            capacity_evidence["unplacedPluginIds"] == ["fixture.native-widget"]
            and capacity_evidence["capacityMessage"] != "")
        check(ipc("native-runtime-probe", "expirePageFeedback") == (0, "true"),
              "explicit page feedback expiry failed")
        if bb_capacity_warning:
            warning_after_feedback = wait_status("native-runtime-probe", lambda value:
                not value["pageFeedbackVisible"]
                and value["unplacedPluginIds"] == ["fixture.native-widget"]
                and value["capacityMessage"] != "")
            check(warning_after_feedback["capacityMessage"]
                  == capacity_evidence["capacityMessage"],
                  "capacity warning disappeared when action feedback expired")

        check(ipc("native-runtime-probe", "freeFullV1Slot") == (0, "queued"),
              "B(b) fixed-group move-back refused")
        freed_order = json.loads(json.dumps(full_order))
        freed_order["left"][0], freed_order["left"][7] = (
            freed_order["left"][7], freed_order["left"][0])
        freed = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and value["config"]["order"] == freed_order)
        freed_fixed = [group for region in ("left", "center", "right")
                       for group in freed["config"]["order"][region]
                       if group in fixed_ids]
        check(sorted(freed_fixed) == sorted(fixed_ids) and len(freed_fixed) == 15
              and freed["config"]["order"]["left"][7] == "",
              "B(b) slot release did not preserve all fixed groups")
        persisted(lambda value: state_settings(value)["order"] == freed_order)
        if bb_capacity_warning:
            check(freed["unplacedPluginIds"] == ["fixture.native-widget"]
                  and not freed["pageFeedbackVisible"]
                  and freed["capacityMessage"] == "Some widgets currently have no bar slot.",
                  "free V1 slot with pending placement must show a cause-neutral page status")
            print("NATIVE_BB_FREE_SLOT_STATUS " + json.dumps({
                "slotEmpty": freed["config"]["order"]["left"][7] == "",
                "unplacedPluginIds": freed["unplacedPluginIds"],
                "capacityMessage": freed["capacityMessage"],
            }, sort_keys=True), flush=True)

        check(ipc("native-runtime-probe", "setShellStyle", "full") == (0, "queued"),
              "B(b) retry V2 switch refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["layoutBusy"]
                    and value["v2Mode"]
                    and "G:fixture.native-widget" in value["config"]["v2Layout"]["left"])
        check(ipc("native-runtime-probe", "setShellStyle", "shibumi") == (0, "queued"),
              "B(b) retry V1 switch refused")
        retry_placed = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["v2Mode"]
            and value["config"]["order"]["left"][7] == "G:fixture.native-widget"
            and any(isinstance(entry, dict)
                    and entry.get("id") == "fixture.native-widget"
                    and entry.get("shibumiModule") is True
                    for entry in value["injectedBar"]["layout"]["left"])
            and (not value["unplacedPluginIdsPropertyExists"]
                 or value["unplacedPluginIds"] == [])
            and (not value["capacityMessagePropertyExists"]
                 or value["capacityMessage"] == ""))
        check((not retry_placed["unplacedPluginIdsPropertyExists"]
               or retry_placed["unplacedPluginIds"] == [])
              and (not retry_placed["capacityMessagePropertyExists"]
                   or retry_placed["capacityMessage"] == ""),
              "B(b) successful retry retained stale capacity feedback")
        persisted(lambda value:
                  state_settings(value)["order"]["left"][7]
                    == "G:fixture.native-widget"
                  and any(isinstance(entry, dict)
                          and entry.get("id") == "fixture.native-widget"
                          and entry.get("shibumiModule") is True
                          for entry in value["bar"]["layout"]["left"]))

        cleanup_code, cleanup_text = ipc(
            "native-runtime-probe", "removeCapacityWidget")
        check(cleanup_code == 0 and cleanup_text.startswith("{"),
              "B(b) explicit cleanup did not return bounded evidence: "
              + cleanup_text[:512])
        cleanup_evidence = json.loads(cleanup_text)
        print("NATIVE_BB_CLEANUP_REQUEST_EVIDENCE "
              + json.dumps(cleanup_evidence, sort_keys=True), flush=True)
        check(cleanup_evidence.get("accepted") is True
              and cleanup_evidence.get("pageEntryPresent") is True
              and cleanup_evidence.get("stateWritePending") is True
              and cleanup_evidence.get("layoutBusy") is True
              and cleanup_evidence.get("layoutSerialAdvanced") is True
              and cleanup_evidence.get("nativeUnchangedBeforeSettlement") is True,
              "B(b) explicit production cleanup was not serialized: "
              + json.dumps(cleanup_evidence, sort_keys=True))
        bb_disabled = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and value["layoutResult"] == "confirmed"
            and not value["pageTransitionPending"]
            and all("G:fixture.native-widget" not in value["config"]["order"][region]
                    for region in ("left", "center", "right"))
            and all(not any(isinstance(entry, dict)
                            and entry.get("id") == "fixture.native-widget"
                            for entry in value["injectedBar"]["layout"][region])
                    for region in ("left", "center", "right")))
        catalog_disabled = wait_status("native-runtime-probe", lambda value:
                    value["catalogReadSerial"] > bb_disabled["catalogReadSerial"]
                    and value["panelCatalog"]["byId"]
                      ["fixture.native-widget"]["enabled"] is False,
                    timeout=7)
        disabled_file = persisted(lambda value:
                  all("G:fixture.native-widget" not in
                      state_settings(value)["order"][region]
                      for region in ("left", "center", "right"))
                  and all(not any(isinstance(entry, dict)
                                  and entry.get("id") == "fixture.native-widget"
                                  for entry in value["bar"]["layout"][region])
                          for region in ("left", "center", "right")))
        native_file_entry_count = sum(
            1 for region in ("left", "center", "right")
            for entry in disabled_file["bar"]["layout"][region]
            if isinstance(entry, dict)
            and entry.get("id") == "fixture.native-widget")
        check(native_file_entry_count == 0,
              "B(b) explicit cleanup retained the native widget entry")
        print("NATIVE_BB_CLEANUP_SETTLED_EVIDENCE " + json.dumps({
            "catalogEnabled": catalog_disabled["panelCatalog"]["byId"]
              ["fixture.native-widget"]["enabled"],
            "layoutResult": bb_disabled["layoutResult"],
            "nativeFileEntryCount": native_file_entry_count,
        }, sort_keys=True), flush=True)
        check(ipc("native-runtime-probe", "restoreCapacityBaseline") == (0, "queued"),
              "B(b) baseline restoration refused")
        restored_capacity = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["v2Mode"]
            and value["config"]["order"] == baseline_order
            and value["config"]["splits"] == baseline_splits)
        persisted(lambda value:
                  state_settings(value)["order"] == baseline_order
                  and state_settings(value)["splits"] == baseline_splits
                  and all(not any(isinstance(entry, dict)
                                  and entry.get("id") == "fixture.native-widget"
                                  for entry in value["bar"]["layout"][region])
                          for region in ("left", "center", "right")))
        check(restored_capacity["config"]["order"] == baseline_order,
              "B(b) cleanup did not restore the prior V1 state")
        b_ended = time.monotonic()
        print("NATIVE_TIMING " + json.dumps({"endpoint": "b-end", "monotonic": b_ended,
              "probeElapsed": b_ended - PROBE_STARTED,
              "phaseElapsed": b_ended - b_started}), flush=True)

        # A suite plugin remains enabled in the native DTO while its fixed
        # group is hidden. The page must derive active placement from the
        # current variant and wait for State settlement in both directions.
        check(ipc("native-runtime-probe", "setControlGroupVisible", "false")
              == (0, "queued"), "fixed-group hidden-state setup refused")
        hidden_fixed = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"]
            and value["panelCatalog"]["byId"]["hancore.shibumi.control-center"]["enabled"] is True
            and value["controlCatalogInstalled"] is False)
        fixed_bar = hidden_fixed["injectedBar"]
        check(ipc("native-runtime-probe", "toggleFixedControlGroup")
              == (0, "queued-without-native-mutation"),
              "fixed native group toggle bypassed State settlement")
        fixed_enabled = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["stateTransitionBusy"]
            and value["stateTransitionResult"] == "confirmed"
            and not value["pageTransitionPending"]
            and value["pageFeedbackTitle"] == "Shibumi Control Center activated"
            and value["pageUndoMode"] == "plugin-value"
            and value["controlCatalogInstalled"] is True)
        check(fixed_enabled["injectedBar"] == fixed_bar,
              "state-only fixed group changed native Bar")
        check(ipc("native-runtime-probe", "undoFixedControlGroup") == (0, "queued"),
              "fixed-group State Undo was not queued")
        fixed_undone = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["stateTransitionBusy"]
            and not value["pageTransitionPending"] and value["pageUndoMode"] == ""
            and value["controlCatalogInstalled"] is False)
        check(fixed_undone["injectedBar"] == fixed_bar,
              "state-only fixed group Undo changed native Bar")
        check(ipc("native-runtime-probe", "setControlGroupVisible", "true")
              == (0, "queued"), "fixed-group cleanup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"]
                    and value["controlCatalogInstalled"] is True)
        print("NATIVE ICONS CPU AUTHORITY AND FIXED-GROUP STATE SETTLEMENT PASSED",
              flush=True)

        # The actual Bar writer must retain a confirmed provider preimage and
        # restore it only after State and native shell.json settle. Exercise
        # both layout generations; in V1 also prove a concurrent opaque edit
        # makes exact Undo fail closed rather than overwrite unrelated data.
        provider_baseline = host_config()["bar"]
        check(not wait_status("native-runtime-probe", lambda value:
                              not value["stateWritePending"])["v2Mode"],
              "provider Undo fixture did not start in V1")
        check(ipc("native-runtime-probe", "toggleAudioProvider")
              == (0, "queued-without-native-mutation"),
              "V1 provider activation bypassed serialized transition")
        check(ipc("native-runtime-probe", "activePluginRemovalRefused",
                  "fixture.audio-provider") == (0, "refused-before-process"),
              "pending scoped replacement activation started removal")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["layoutBusy"]
                    and value["layoutResult"] == "confirmed"
                    and not value["pageTransitionPending"]
                    and value["pageUndoMode"] == "provider-snapshot"
                    and not value["audioV1Enabled"] and not value["audioV2Enabled"]
                    and value["unplacedPluginIdsPropertyExists"]
                    and value["unplacedPluginIds"] == []
                    and value["capacityMessage"] == ""
                    and any(any((entry == "fixture.audio-provider" or isinstance(entry, dict)
                                 and entry.get("id") == "fixture.audio-provider") for entry in
                                value["injectedBar"]["layout"][region])
                            for region in ("left", "center", "right")))
        check(ipc("native-runtime-probe", "activePluginRemovalRefused",
                  "fixture.audio-provider") == (0, "refused-before-process"),
              "active scoped replacement provider started removal")
        check(ipc("native-runtime-probe", "setUndoConflict", "true") == (0, "queued"),
              "provider Undo concurrent-edit setup failed")
        conflicted = wait_status("native-runtime-probe", lambda value:
            any(isinstance(entry, dict)
                and entry.get("id") == "hancore.shibumi.control-center"
                and entry.get("fixtureConcurrent", {}).get("opaque") == [31]
                for entry in value["injectedBar"]["layout"]["left"]))
        check(ipc("native-runtime-probe", "undoPluginChange")
              == (0, "refused-retained"),
              "stale exact provider Undo did not fail closed")
        refused = wait_status("native-runtime-probe", lambda value:
            value["pageUndoMode"] == "provider-snapshot"
            and value["pageFeedbackTitle"] == "Undo could not be completed"
            and not value["providerSnapshotBusy"])
        check(refused["injectedBar"] == conflicted["injectedBar"]
              and not refused["audioV1Enabled"] and not refused["audioV2Enabled"],
              "refused provider Undo lost current bar or family state")
        check(ipc("native-runtime-probe", "setUndoConflict", "false") == (0, "queued"),
              "provider Undo conflict cleanup failed")
        wait_status("native-runtime-probe", lambda value:
            any(entry == "hancore.shibumi.control-center"
                for entry in value["injectedBar"]["layout"]["left"]))
        undo_reply = ipc("native-runtime-probe", "undoPluginChange")
        check(undo_reply == (0, "queued"),
              "V1 exact provider Undo was not queued: " + repr(undo_reply))
        v1_restored = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["providerSnapshotBusy"]
            and value["providerSnapshotResult"] == "confirmed"
            and not value["pageTransitionPending"] and value["pageUndoMode"] == ""
            and value["audioV1Enabled"] and value["audioV2Enabled"]
            and all(not any((entry == "fixture.audio-provider" or isinstance(entry, dict)
                            and entry.get("id") == "fixture.audio-provider") for entry in
                           value["injectedBar"]["layout"][region])
                    for region in ("left", "center", "right")))
        check(v1_restored["injectedBar"] == provider_baseline,
              "V1 provider Undo did not restore exact Bar state")
        wait_status("native-runtime-probe", lambda value:
            value["panelCatalog"] is not None
            and value["panelCatalog"]["byId"]["fixture.audio-provider"]["enabled"] is False,
            timeout=7)

        check(ipc("native-runtime-probe", "toggleAudioProvider")
              == (0, "queued-without-native-mutation"),
              "V1 return-to-Shibumi setup refused")
        v1_alternative = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["audioV1Enabled"] and not value["audioV2Enabled"])["injectedBar"]
        wait_status("native-runtime-probe", lambda value:
            value["panelCatalog"] is not None
            and value["panelCatalog"]["byId"]["fixture.audio-provider"]["enabled"] is True,
            timeout=7)
        check(ipc("native-runtime-probe", "restoreShibumiAudio") == (0, "queued"),
              "V1 return-to-Shibumi was not serialized")
        v1_shibumi = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["pageTransitionPending"]
            and value["pageUndoMode"] == "provider-snapshot"
            and value["pageUndoSnapshotValid"]
            and value["audioV1Enabled"] and value["audioV2Enabled"])
        check(v1_shibumi["injectedBar"] == provider_baseline,
              "V1 return-to-Shibumi lost exact Bar state")
        check(ipc("native-runtime-probe", "undoPluginChange") == (0, "queued"),
              "V1 return-to-Shibumi Undo was not queued")
        v1_return_undone = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["providerSnapshotBusy"]
            and not value["pageTransitionPending"] and value["pageUndoMode"] == ""
            and not value["audioV1Enabled"] and not value["audioV2Enabled"])
        check(v1_return_undone["injectedBar"] == v1_alternative,
              "V1 return-to-Shibumi Undo lost exact alternative state")
        wait_status("native-runtime-probe", lambda value:
            value["panelCatalog"] is not None
            and value["panelCatalog"]["byId"]["fixture.audio-provider"]["enabled"] is True,
            timeout=7)
        check(ipc("native-runtime-probe", "restoreShibumiAudio") == (0, "queued"),
              "V1 return-to-Shibumi cleanup refused")
        wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["providerSnapshotBusy"]
            and not value["pageTransitionPending"]
            and value["audioV1Enabled"] and value["audioV2Enabled"]
            and value["panelCatalog"] is not None
            and value["panelCatalog"]["byId"]
              ["fixture.audio-provider"]["enabled"] is False,
            timeout=7)

        check(ipc("native-runtime-probe", "setShellStyle", "full") == (0, "queued"),
              "V2 provider Undo setup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and value["v2Mode"])
        v2_baseline = host_config()["bar"]
        check(ipc("native-runtime-probe", "toggleAudioProvider")
              == (0, "queued-without-native-mutation"),
              "V2 provider activation bypassed serialized transition")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["layoutBusy"]
                    and value["layoutResult"] == "confirmed"
                    and value["pageUndoMode"] == "provider-snapshot"
                    and value["panelCatalog"]["byId"]["fixture.audio-provider"]["enabled"] is True
                    and any("G:fixture.audio-provider" in value["config"]["v2Layout"][region]
                            for region in ("left", "center", "right"))
                    and not value["audioV1Enabled"] and not value["audioV2Enabled"])
        v2_undo_reply = ipc("native-runtime-probe", "undoPluginChange")
        if v2_undo_reply != (0, "queued"):
            raise RuntimeError("V2 exact provider Undo was not queued: "
                               + repr(v2_undo_reply) + " status="
                               + repr(wait_status("native-runtime-probe", lambda value: True)))
        v2_restored = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["providerSnapshotBusy"]
            and value["providerSnapshotResult"] == "confirmed"
            and not value["pageTransitionPending"] and value["pageUndoMode"] == ""
            and value["audioV1Enabled"] and value["audioV2Enabled"])
        check(v2_restored["injectedBar"] == v2_baseline,
              "V2 provider Undo did not restore exact Bar state")
        wait_status("native-runtime-probe", lambda value:
            value["panelCatalog"] is not None
            and value["panelCatalog"]["byId"]["fixture.audio-provider"]["enabled"] is False,
            timeout=7)

        check(ipc("native-runtime-probe", "toggleAudioProvider")
              == (0, "queued-without-native-mutation"),
              "V2 return-to-Shibumi setup refused")
        v2_alternative = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["audioV1Enabled"] and not value["audioV2Enabled"])["injectedBar"]
        wait_status("native-runtime-probe", lambda value:
            value["panelCatalog"] is not None
            and value["panelCatalog"]["byId"]["fixture.audio-provider"]["enabled"] is True,
            timeout=7)
        check(ipc("native-runtime-probe", "restoreShibumiAudio") == (0, "queued"),
              "V2 return-to-Shibumi was not serialized")
        v2_shibumi = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and not value["pageTransitionPending"]
            and value["pageUndoMode"] == "provider-snapshot"
            and value["pageUndoSnapshotValid"]
            and value["audioV1Enabled"] and value["audioV2Enabled"])
        check(v2_shibumi["injectedBar"] == v2_baseline,
              "V2 return-to-Shibumi lost exact Bar state")
        check(ipc("native-runtime-probe", "undoPluginChange") == (0, "queued"),
              "V2 return-to-Shibumi Undo was not queued")
        v2_return_undone = wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["providerSnapshotBusy"]
            and not value["pageTransitionPending"] and value["pageUndoMode"] == ""
            and not value["audioV1Enabled"] and not value["audioV2Enabled"])
        check(v2_return_undone["injectedBar"] == v2_alternative,
              "V2 return-to-Shibumi Undo lost exact alternative state")
        wait_status("native-runtime-probe", lambda value:
            value["panelCatalog"] is not None
            and value["panelCatalog"]["byId"]["fixture.audio-provider"]["enabled"] is True,
            timeout=7)
        check(ipc("native-runtime-probe", "restoreShibumiAudio") == (0, "queued"),
              "V2 return-to-Shibumi cleanup refused")
        wait_status("native-runtime-probe", lambda value:
            not value["stateWritePending"] and not value["layoutBusy"]
            and value["audioV1Enabled"] and value["audioV2Enabled"])
        check(ipc("native-runtime-probe", "setShellStyle", "shibumi") == (0, "queued"),
              "V1 fixture restoration after V2 Undo refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["v2Mode"])
        print("ACTUAL V1/V2 PROVIDER UNDO SETTLEMENT AND STALE-SNAPSHOT REFUSAL PASSED",
              flush=True)

        # Run the additional rapid Icons reversal after the provider/catalog
        # matrix so its deliberate extra State settlement cannot perturb the
        # five-second catalog reconciliation phase used above.
        check(ipc("native-runtime-probe", "setCpuVisible", "false") == (0, "queued"),
              "coalesced Icons setup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["cpuV1Enabled"])
        check(ipc("native-runtime-probe", "openIcons") == (0, "ok"),
              "coalesced Icons page refused")
        wait_status("native-runtime-probe", lambda value:
                    value["panelPage"] == "functions" and value["panelPageReady"])
        check(ipc("native-runtime-probe", "coalesceCpuFromIcons")
              == (0, "coalesced-without-native-mutation"),
              "Icons rapid reversal did not coalesce requested presentation")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and not value["stateTransitionBusy"]
                    and not value["cpuV1Requested"] and not value["cpuV1Enabled"])
        check(ipc("native-runtime-probe", "setCpuVisible", "true") == (0, "queued"),
              "coalesced Icons cleanup refused")
        wait_status("native-runtime-probe", lambda value:
                    not value["stateWritePending"] and value["cpuV1Enabled"])
        check(ipc("native-runtime-probe", "openPlugins") == (0, "ok"),
              "Plugins page restoration after Icons coalescing refused")
        wait_status("native-runtime-probe", lambda value:
                    value["panelPage"] == "plugins" and value["panelPageReady"])

        check(ipc("native-runtime-probe", "toggleCatalogWidget")
              == (0, "queued-without-native-mutation"),
              "destroyed-page transition setup bypassed serialized mutation")
        check(ipc("native-runtime-probe", "closeControl") == (0, "ok"),
              "pending page owner close refused")
        wait_status("native-runtime-probe", lambda value:
            not value["layoutBusy"] and not value["stateWritePending"]
            and not value["panelLoaded"] and not value["controlLoaded"]
            and value["controlObjectCount"] == 0 and value["restoreCount"] == 0)
        print("ACTUAL NONEMPTY NATIVE DTO, PAGE LEASE/STALE REBIND AND TOGGLE SETTLEMENT PASSED",
              flush=True)
        check(ipc("native-runtime-probe", "checkIncompleteState") == (0, "scoped-incomplete-no-writes"),
              "scoped incomplete State fell back to legacy writes")
        check(ipc("native-runtime-probe", "prepareTransition") == (0, "queued"), "native layout setup refused")
        wait_status("native-runtime-probe", lambda value: not value["stateWritePending"] and not value["layoutBusy"]
                    and "G:fixture.layout-probe" in value["config"]["v2Layout"]["left"])
        before_native_transition = host_config()["bar"]
        check(ipc("native-runtime-probe", "runTransition") == (0, "queued-without-native-mutation"),
              "native layout changed before State readback")
        transitioned = wait_status("native-runtime-probe", lambda value: not value["stateWritePending"]
                    and not value["layoutBusy"] and value["layoutResult"] == "confirmed"
                    and "G:fixture.layout-probe" in value["config"]["v2Layout"]["right"]
                    and any(isinstance(entry, dict) and entry.get("id") == "fixture.layout-probe"
                            for entry in value["injectedBar"]["layout"]["right"]))
        moved_bar = transitioned["injectedBar"]
        expected_bar = json.loads(json.dumps(before_native_transition))
        moved_entry = next(entry for entry in expected_bar["layout"]["left"]
                           if isinstance(entry, dict) and entry.get("id") == "fixture.layout-probe")
        expected_bar["layout"]["left"].remove(moved_entry)
        expected_bar["layout"]["right"].append(moved_entry)
        check(moved_bar == expected_bar and moved_entry["opaque"]["deep"] == [17],
              "native transition lost unrelated Bar/entry data")
        persisted(lambda value: value["bar"] == expected_bar
                  and "G:fixture.layout-probe" in state_settings(value)["v2Layout"]["right"])
        # Remove the explicitly fixture-created widget before its API owner.
        # Closed-widget revocation in this headless engine. Production bar-owner
        # transitions still require the separate transactional restart boundary.
        check(ipc("shell", "enablePlugin", "omarchy.bar", "{}") == (0, "ok"), "stock switch refused")
        stock_context = wait_status("native-stock-probe", lambda value: value["ready"])
        print("SAME_ENGINE_STOCK_STUB " + json.dumps(stock_context), flush=True)
        stock = wait_status("native-state-probe", lambda value: value["registered"] and not value["hasBar"])
        check(stock["objectName"] == "native-kept-state", "bar switch replaced retained State")
        state_entry = own_entry_write("returned-stock", state_entry)
        check(ipc("native-state-probe", "compact", "true") == (0, "queued"), "stock State request refused")
        wait_status("native-state-probe", lambda value: not value["hasBar"] and not value["pending"]
                    and value["writeStatus"] == "confirmed" and value["config"]["widgets"]["G4"]["compact"] is True)
        persisted(lambda value: state_settings(value)["widgets"]["G4"]["compact"] is True)
        check(ipc("shell", "enablePlugin", "hancore.shibumi.bar", "{}") == (0, "ok"), "suite re-selection refused")
        restored = wait_status("native-runtime-probe", lambda value: value["barRegistered"] and value["stateReady"])
        check(restored["stateObjectName"] == "native-kept-state", "suite re-selection replaced State")
        check(ipc("native-runtime-probe", "compact", "false") == (0, "queued"), "writer failed after re-selection")
        persisted(lambda value: state_settings(value)["widgets"]["G4"]["compact"] is False)
        check(host_config()["bar"].get("shibumi") == legacy, "legacy settings were rewritten")
        probe_ended = time.monotonic()
        probe_remaining = DEADLINE - probe_ended
        print("NATIVE_TIMING " + json.dumps({"endpoint": "probe-end", "monotonic": probe_ended, "probeElapsed": probe_ended - PROBE_STARTED, "endRemaining": probe_remaining}), flush=True)
        check(probe_remaining >= 8,
              "native B(b) probe exceeded the authorized 77 s action budget")
        check(bb_capacity_warning,
              "full V1 background reconcile did not publish the unplaced widget capacity warning")
    finally:
        finish_owned_group(process)
        log.flush()
        try:
            runtime_log = read_regular(BASE / "native.log", LIMIT).decode(errors="replace")
        except ValueError:
            tail = read_regular(BASE / "native.log", 24000, tail=True).decode(errors="replace")
            print("NATIVE_LOG_BOUNDED_TAIL\n" + tail, flush=True)
            raise
        print("NATIVE_LOG_BEGIN\n" + runtime_log[-24000:] + "\nNATIVE_LOG_END", flush=True)
        check(not any(token in runtime_log for token in (
            "ERROR", "TypeError", "ReferenceError", "Binding loop", "Cannot assign", "Unable to assign",
            "Internal error")),
            "unexpected native/QML runtime failure")
print("NATIVE STATE/BAR/WIDGET/PANEL, KEEPLOADED AND REVOCATION PASSED", flush=True)
print("COLD-STOCK AND SUITE SERVICE-ENTRY WRITES PASSED", flush=True)
print("PRODUCTION STATE OWN-ENTRY WRITES, FILE READBACK AND RAPID SETTERS PASSED", flush=True)
print("ACTUAL CONTROL CENTER/BAR RESTORE HELD UNTIL FILE-BACKED STATE SETTLEMENT PASSED", flush=True)
print("ATOMIC LAYOUT/FAMILY STATE PATCH AND CONDITIONAL COMPENSATION PASSED", flush=True)
print("ACTUAL STATE READBACK THEN NATIVE LAYOUT/INJECTED BAR CONFIRMATION PASSED; CATALOG TOGGLE COVERED", flush=True)
print("WINDOW/HEALTH STUBS; NOT COMPLETE-HOST OR DESKTOP ACCEPTANCE", flush=True)
