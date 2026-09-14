#!/usr/bin/env python3
"""Stage and compare the full native-host V2 widget pipeline on nested Wayland."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from lib.isolated_process import run_bounded
from lib.source_snapshot import fingerprint, materialize, snapshot

ROOT = Path(__file__).resolve().parents[1]
NATIVE_RUNTIME = runpy.run_path(str(ROOT / "tests/native-runtime-regression.py"),
                                run_name="shibumi_native_runtime_library")
BETA13_COMMIT = "2760cdb8272255790d5e4613fed8a48cb63c3555"
PLUGIN_ROOTS = ("hancore.shibumi.bar", "hancore.shibumi.state")
MARKER_ID = "hancore.shibumi.cpu"
MARKER_DIGEST = "0123456789abcdef" * 4
MAX_GIT_TREE = 256 * 1024
MAX_GIT_BLOB = 1024 * 1024
MAX_GIT_FILES = 256
MUTANT_SLOT = "core/WidgetSlot.qml"


def copied_payloads(payloads):
    return {root: dict(files) for root, files in payloads.items()}


def instrument_native_rescan_census(native):
    """Count only shell IPC rescans in the already-admitted native snapshot."""
    files = dict(native)
    path = "shell.qml"
    source, executable = files[path]
    text = source.decode("utf-8")
    property_anchor = "  property bool pluginReloadPending: false\n"
    endpoint_anchor = "    function rescanPlugins(): void {\n      shell.reloadPlugins()\n    }\n"
    if text.count(property_anchor) != 1 or text.count(endpoint_anchor) != 1:
        raise ValueError("native rescan census anchor is missing or ambiguous")
    property_overlay = (
        property_anchor
        + "  // Observation-only fixture counter; it grants no rescan authority.\n"
        + "  property int widgetPipelineRescanCalls: 0\n"
    )
    endpoint_overlay = (
        "    function widgetPipelineRescanCount(): int {\n"
        "      return shell.widgetPipelineRescanCalls\n"
        "    }\n\n"
        "    function rescanPlugins(): void {\n"
        "      shell.widgetPipelineRescanCalls++\n"
        "      shell.reloadPlugins()\n"
        "    }\n"
    )
    text = text.replace(property_anchor, property_overlay)
    text = text.replace(endpoint_anchor, endpoint_overlay)
    files[path] = (text.encode(), executable)
    overlay = property_overlay[len(property_anchor):] + endpoint_overlay
    return files, hashlib.sha256(overlay.encode()).hexdigest()


def candidate_status_guard_mutant(candidate):
    """Restore only the retired scoped status guard in a staged candidate."""
    files = copied_payloads(candidate)
    bar_files = files["hancore.shibumi.bar"]

    slot_source, slot_executable = bar_files[MUTANT_SLOT]
    slot = slot_source.decode("utf-8")
    direct = ("    try { return candidate && candidate instanceof Component "
              "? candidate : null }\n")
    guarded = ("    try { return candidate && candidate instanceof Component\n"
               "        && candidate.status === Component.Ready "
               "? candidate : null }\n")
    if slot.count(direct) != 1 or "candidate.status" in slot:
        raise ValueError("candidate direct scoped binding anchor is missing")
    slot = slot.replace(direct, guarded)
    bar_files[MUTANT_SLOT] = (slot.encode(), slot_executable)
    return files, {
        "scopedStatusGuardSha256": hashlib.sha256(guarded.encode()).hexdigest(),
    }


def git_output(arguments, maximum=MAX_GIT_TREE):
    reply = run_bounded(["/usr/bin/git", "-C", str(ROOT), *arguments],
                        timeout=8, maximum=maximum)
    if reply.returncode != 0:
        raise RuntimeError("Git object read failed: " + " ".join(arguments))
    return reply.stdout


def git_snapshot(commit):
    resolved = git_output(["rev-parse", "--verify", commit + "^{commit}"]).decode().strip()
    if resolved != commit:
        raise ValueError("Beta.13 commit object is unavailable or ambiguous")
    raw = git_output(["ls-tree", "-r", "-z", "--full-tree", commit, "--", *PLUGIN_ROOTS])
    records = [record for record in raw.split(b"\0") if record]
    if not 1 <= len(records) <= MAX_GIT_FILES:
        raise ValueError("Beta.13 Git tree count is outside the fixture bound")
    files = {}
    total = 0
    for record in records:
        try:
            header, encoded_path = record.split(b"\t", 1)
            mode, kind, object_id = header.decode("ascii").split(" ")
            path = encoded_path.decode("utf-8", "strict")
        except (UnicodeDecodeError, ValueError) as error:
            raise ValueError("malformed Beta.13 Git tree record") from error
        if kind != "blob" or mode not in ("100644", "100755"):
            raise ValueError("unsupported Beta.13 Git entry: " + path)
        if (path.startswith("/") or ".." in Path(path).parts
                or not any(path == root or path.startswith(root + "/")
                           for root in PLUGIN_ROOTS)):
            raise ValueError("out-of-scope Beta.13 Git path: " + path)
        relative_root, relative_name = path.split("/", 1)
        data = git_output(["cat-file", "blob", object_id], maximum=MAX_GIT_BLOB)
        total += len(data)
        if total > 4 * 1024 * 1024:
            raise ValueError("Beta.13 Git payload exceeds fixture bound")
        files.setdefault(relative_root, {})[relative_name] = (
            data, mode == "100755")
    if set(files) != set(PLUGIN_ROOTS):
        raise ValueError("Beta.13 Git payload is incomplete")
    return files


def between(text, start, end):
    first = text.find(start)
    if first < 0:
        raise ValueError("diagnostic source start anchor is missing")
    last = text.find(end, first)
    if last < 0:
        raise ValueError("diagnostic source end anchor is missing")
    return text[first:last]


def instrument_beta13(files, candidate):
    """Add only the current read-only census surface absent at Beta.13.

    The production Beta.13 implementation remains otherwise byte-for-byte from
    the named commit. This overlay is necessary because that commit predates
    debugWidgetPipeline and its three scalar WidgetSlot aliases.
    """
    bar_path = "Bar.qml"
    slot_path = "core/WidgetSlot.qml"
    beta_bar = files["hancore.shibumi.bar"][bar_path][0].decode("utf-8")
    current_bar = candidate["hancore.shibumi.bar"][bar_path][0].decode("utf-8")
    beta_slot = files["hancore.shibumi.bar"][slot_path][0].decode("utf-8")
    current_slot = candidate["hancore.shibumi.bar"][slot_path][0].decode("utf-8")

    census = between(current_bar, "  function debugWidgetPipeline() {\n",
                     "  function debugBarGeometry() {\n")
    # Beta.13 predates the output chronology and exact-load provenance fields.
    # Keep those diagnostics explicitly unavailable in the copied census rather
    # than reading absent properties or manufacturing historical readiness.
    sequence_function = (
        "    function outputSequence() {\n"
        "      if (hostOutputReturnObserved) return \"positive-zero-positive\"\n"
        "      if (hostOutputLossObserved) return \"positive-zero\"\n"
        "      if (hostOutputPresenceObserved) return \"positive\"\n"
        "      return \"none\"\n"
        "    }\n"
    )
    legacy_sequence_function = (
        "    function outputSequence() { return \"unavailable\" }\n"
    )
    load_ready_block = (
        "      let currentLoadReady = false\n"
        "      try {\n"
        "        currentLoadReady = typeof slot.currentLoadReady === \"function\"\n"
        "          && slot.currentLoadReady() === true\n"
        "      } catch (error) { currentLoadReady = false }\n"
    )
    legacy_load_ready_block = "      const currentLoadReady = false\n"
    replacements = {
        sequence_function: legacy_sequence_function,
        load_ready_block: legacy_load_ready_block,
        "        presenceObserved: hostOutputPresenceObserved === true,\n":
            "        presenceObserved: false,\n",
        "        lossObserved: hostOutputLossObserved === true,\n":
            "        lossObserved: false,\n",
        "        returnObserved: hostOutputReturnObserved === true,\n":
            "        returnObserved: false,\n",
        "        previouslyReadyWidgetCount: boundedInt(Object.keys(\n"
        "          hostOutputPreviouslyReadyWidgetIds || {}).length, 0, 256, 0),\n":
            "        previouslyReadyWidgetCount: 0,\n",
        "        lossReadyWidgetCount: boundedInt(Object.keys(\n"
        "          hostOutputLossReadyWidgetIds || {}).length, 0, 256, 0),\n":
            "        lossReadyWidgetCount: 0,\n",
        "        warningEmitted: SuiteRuntime.Runtime.hostWidgetResolutionWarningEmitted\n"
        "          === true\n":
            "        warningEmitted: false\n",
    }
    for original, overlay in replacements.items():
        if census.count(original) != 1:
            raise ValueError("current census legacy overlay anchor is ambiguous")
        census = census.replace(original, overlay)
    endpoint = between(current_bar,
        "    function debugWidgetPipeline(): string {\n",
        "    function connectedPanelState(): string {\n")
    aliases = between(current_slot,
        "  // Read-only scalar diagnostics for the bounded Bar IPC census. Keep the\n",
        "  readonly property var containingWindow:")
    if "function debugWidgetPipeline" in beta_bar or "loaderActive" in beta_slot:
        raise ValueError("Beta.13 unexpectedly already contains census instrumentation")
    if beta_bar.count("  function debugBarGeometry() {\n") != 1:
        raise ValueError("Beta.13 Bar diagnostic anchor is ambiguous")
    if beta_bar.count("    function connectedPanelState(): string {\n") != 1:
        raise ValueError("Beta.13 Bar IPC anchor is ambiguous")
    slot_anchor = "  readonly property var containingWindow:"
    if beta_slot.count(slot_anchor) != 1:
        raise ValueError("Beta.13 WidgetSlot diagnostic anchor is ambiguous")

    beta_bar = beta_bar.replace("  function debugBarGeometry() {\n",
                                census + "  function debugBarGeometry() {\n")
    beta_bar = beta_bar.replace("    function connectedPanelState(): string {\n",
                                endpoint + "    function connectedPanelState(): string {\n")
    beta_slot = beta_slot.replace(slot_anchor, aliases + slot_anchor)
    files["hancore.shibumi.bar"][bar_path] = (beta_bar.encode(), False)
    files["hancore.shibumi.bar"][slot_path] = (beta_slot.encode(), False)
    return hashlib.sha256((census + endpoint + aliases).encode()).hexdigest()


def state_config():
    disabled = {group: {"enabledV2": False} for group in (
        "G1", "G2", "G3", "G4", "G6", "G7", "G8", "G9", "G10",
        "G11", "G12", "G13", "G14", "G15", "G16", "G17", "G18")}
    disabled["G5"] = {"enabledV2": True}
    return {
        "version": 1,
        "identityVersion": 3,
        "v2Layout": {
            "left": ["G1", "G2", "G3", "", "G5", "G6", "G4", "G7", "", ""],
            "center": ["G8"],
            "right": ["G9", "G10", "G11", "G14", "G12", "G13", "G16",
                      "G18", "G17", "G15", "", "", ""],
        },
        "v2Boundaries": [False, False],
        "widgets": disabled,
        "presentation": {
            "border": True, "v1Border": True, "v2Border": True,
            "panelBorder": True, "shadow": False, "frost": False,
            "radius": "large", "accent": "color04",
            "shellStyle": "notch", "v2ShellStyle": "notch",
        },
    }


def stage(base, native, plugins, marker_source, negative=False):
    materialize(native, base / "omarchy/shell")
    for name in ("omarchy/config/omarchy", "home/.config/omarchy/plugins",
                 "home/.local/state/omarchy/toggles", "cache", "data", "state",
                 "runtime", "bin"):
        (base / name).mkdir(parents=True, exist_ok=True)
    (base / "runtime").chmod(0o700)

    # Discovery is intentionally narrower than the materialized, fingerprinted
    # native tree. ShellRoot and every registry/API implementation remain exact;
    # unrelated native manifests are merely withheld from this isolated run.
    withheld = []
    for name in native:
        path = Path(name)
        if (path.parts[0] == "plugins" and (path.name == "manifest.json"
                or path.name.endswith(".manifest.json"))):
            manifest = base / "omarchy/shell" / name
            manifest.rename(manifest.with_name(manifest.name + ".fixture-withheld"))
            withheld.append(name)

    plugin_dir = base / "home/.config/omarchy/plugins"
    for root_name, payload in plugins.items():
        materialize(payload, plugin_dir / root_name)
        (plugin_dir / root_name / ".shibumi-managed.json").write_text(
            json.dumps({"suiteId": "hancore.shibumi",
                        "suitePayloadDigest": MARKER_DIGEST}))

    marker = plugin_dir / MARKER_ID
    marker.mkdir()
    (marker / ".shibumi-managed.json").write_text(json.dumps({
        "suiteId": "hancore.shibumi", "suitePayloadDigest": MARKER_DIGEST}))
    (marker / "manifest.json").write_text(json.dumps({
        "schemaVersion": 1, "id": MARKER_ID, "name": "Pipeline marker",
        "version": "1.0.0", "kinds": ["bar-widget"],
        "entryPoints": {"barWidget": "Missing.qml" if negative else "Widget.qml"},
        "barWidget": {"displayName": "Pipeline marker", "category": "Fixture",
                      "semanticCapabilities": [], "defaultSection": "left",
                      "allowMultiple": False},
    }))
    if not negative:
        (marker / "Widget.qml").write_bytes(marker_source)

    config = {
        "version": 1,
        "bar": {
            "id": "hancore.shibumi.bar", "position": "top", "style": "shibumi",
            "transparent": False,
            "layout": {"left": [{"id": MARKER_ID}], "center": [], "right": []},
        },
        "plugins": [{
            "id": "hancore.shibumi.state", "shibumiStateSchemaVersion": 1,
            "shibumi": state_config(),
        }],
        "disabledPlugins": [],
    }
    encoded = json.dumps(config, sort_keys=True, indent=2) + "\n"
    (base / "omarchy/config/omarchy/shell.json").write_text(encoded)
    (base / "home/.config/omarchy/shell.json").write_text(encoded)

    for name in ("bash", "cat", "dirname", "fc-match", "find", "grep",
                 "inotifywait", "mkdir", "sleep", "sort", "timeout"):
        source = Path("/usr/bin") / name
        if not source.is_file():
            raise ValueError("missing fixture dependency: " + name)
        (base / "bin" / name).symlink_to(source)
    # Commons asks only for these two visual options during construction. Keep
    # that query local and deterministic rather than exposing compositor IPC to
    # a plugin-side helper process.
    hyprctl = base / "bin/hyprctl"
    hyprctl.write_text(
        "#!/usr/bin/bash\n"
        "case \"$*\" in\n"
        "  '-j getoption decoration:rounding') printf '%s\\n' '{\"int\":0}' ;;\n"
        "  '-j getoption general:gaps_out') printf '%s\\n' '{\"custom\":\"0\"}' ;;\n"
        "  *) exit 64 ;;\n"
        "esac\n")
    hyprctl.chmod(0o755)
    return withheld


def run_wayland(stage_root, label, mode):
    environment = {
        "PATH": "/usr/bin:/bin",
        "LANG": "C.UTF-8",
        "SHIBUMI_WIDGET_PIPELINE_STAGE_ROOT": str(stage_root),
        "SHIBUMI_WIDGET_PIPELINE_BUILD_LABEL": label,
        "SHIBUMI_WIDGET_PIPELINE_MODE": mode,
        "SHIBUMI_WIDGET_PIPELINE_WAYLAND_DEADLINE": "120",
    }
    for name in ("XDG_RUNTIME_DIR", "WAYLAND_DISPLAY"):
        value = os.environ.get(name)
        if value:
            environment[name] = value
    reply = run_bounded([str(ROOT / "tests/widget-pipeline-wayland-regression.sh")],
                        env=environment, cwd=ROOT, timeout=120,
                        maximum=2 * 1024 * 1024)
    combined = reply.stdout + reply.stderr
    sys.stdout.buffer.write(combined)
    sys.stdout.flush()
    if reply.returncode != 0:
        raise RuntimeError(label + " nested-Wayland run failed")
    results = []
    for line in reply.stdout.decode("utf-8", "replace").splitlines():
        if line.startswith("WIDGET_PIPELINE_RESULT "):
            results.append(json.loads(line.split(" ", 1)[1]))
    if len(results) != 1 or results[0].get("build") != label:
        raise RuntimeError(label + " result record missing or ambiguous")
    return results[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-shell", required=True, type=Path)
    args = parser.parse_args()

    native = NATIVE_RUNTIME["admitted_native"](args.native_shell)
    staged_native, native_census_overlay = instrument_native_rescan_census(native)
    candidate = {name: snapshot(ROOT / name) for name in PLUGIN_ROOTS}
    mutant, mutant_overlays = candidate_status_guard_mutant(candidate)
    beta13 = git_snapshot(BETA13_COMMIT)
    beta13_clean_fingerprint = {name: fingerprint(payload)
                                for name, payload in beta13.items()}
    diagnostic_overlay = instrument_beta13(beta13, candidate)
    marker_source = (ROOT / "tests/widget-pipeline-wayland-shell.qml").read_bytes()
    if len(marker_source) > 64 * 1024:
        raise ValueError("marker widget exceeds fixture bound")

    candidate_fingerprints = {name: fingerprint(payload)
                              for name, payload in candidate.items()}
    mutant_fingerprints = {name: fingerprint(payload)
                           for name, payload in mutant.items()}
    print("WIDGET_PIPELINE_INPUT " + json.dumps({
        "nativeCommit": NATIVE_RUNTIME["COMMIT"],
        "nativeFingerprint": NATIVE_RUNTIME["SHELL_FINGERPRINT"],
        "nativeObservationOverlay": native_census_overlay,
        "stagedNativeFingerprint": fingerprint(staged_native),
        "beta13Commit": BETA13_COMMIT,
        "beta13SourceFingerprints": beta13_clean_fingerprint,
        "beta13ReadOnlyDiagnosticOverlay": diagnostic_overlay,
        "candidateWorktreeFingerprints": candidate_fingerprints,
        "candidateStatusGuardMutantFingerprints": mutant_fingerprints,
        "candidateStatusGuardMutantOverlays": mutant_overlays,
        "markerSha256": hashlib.sha256(marker_source).hexdigest(),
    }, sort_keys=True), flush=True)

    with tempfile.TemporaryDirectory(prefix="shibumi-full-native-widget-",
                                     dir="/tmp") as temporary:
        root = Path(temporary)
        try:
            negative_root = root / "negative"
            withheld = stage(negative_root, staged_native, beta13, marker_source, negative=True)
            negative = run_wayland(negative_root, "beta13-negative-control", "negative")
            negative_observation = negative.get("initialObservation", {})
            negative_expected = negative_observation.get("expected", {})
            negative_slot = negative_observation.get("slot", {})
            if negative.get("outcome") != "expected-failure" \
                    or negative.get("stage") != "registry-selection" \
                    or negative.get("startupPrimeRetained") is not True \
                    or negative.get("nativeRescanCountInitial") != 1 \
                    or negative.get("nativeRescanCountFinal") != 1 \
                    or negative.get("passiveWarnings") != 0 \
                    or negative_observation.get("validOutputs") != 1 \
                    or negative_observation.get("barPanelCount") != 1 \
                    or negative_expected.get("selection") is not False \
                    or negative_expected.get("componentPresent") is not False \
                    or negative_expected.get("componentStatusKind") != "missing" \
                    or negative_expected.get("componentStatus") != -1 \
                    or negative_slot.get("resolvedComponentPresent") is not False \
                    or negative_slot.get("resolvedComponentStatusKind") != "missing" \
                    or negative_slot.get("currentLoadReady") is not False \
                    or negative_slot.get("loaderActive") is not False \
                    or negative_slot.get("loaderItem") is not False:
                raise RuntimeError(
                    "negative control did not prove a Bar-owned unresolved slot")

            beta_root = root / "beta13"
            stage(beta_root, staged_native, beta13, marker_source)
            beta = run_wayland(beta_root, "beta13", "measure")
            if beta.get("harnessProved") is not True:
                raise RuntimeError("Beta.13 did not prove the full native harness path")

            mutant_root = root / "candidate-status-guard-mutant"
            stage(mutant_root, staged_native, mutant, marker_source)
            staged_mutant = run_wayland(mutant_root,
                "candidate-status-guard-mutant", "mutant")
            if staged_mutant.get("harnessProved") is not True:
                raise RuntimeError("status-guard mutant did not prove the native path")

            candidate_root = root / "candidate"
            stage(candidate_root, staged_native, candidate, marker_source)
            current = run_wayland(candidate_root, "candidate", "measure")
            if current.get("harnessProved") is not True:
                raise RuntimeError("candidate did not prove the full native harness path")

            beta_loss = beta.get("firstPersistentLoss")
            current_loss = current.get("firstPersistentLoss")
            if beta_loss != {
                    "transition": "restore", "cycle": 1,
                    "stage": "component-resolution", "validOutputs": 1}:
                raise RuntimeError(
                    "Beta.13 did not reproduce scoped component-admission loss")
            beta_cycles = beta.get("actualTransitions")
            if beta.get("cycles") != 3 \
                    or not isinstance(beta_cycles, list) or len(beta_cycles) != 3 \
                    or beta.get("harnessRescans") != 3 \
                    or beta.get("nativeRescanCountInitial") != 1 \
                    or beta.get("nativeRescanCountFinal") != 4 \
                    or beta.get("passiveWarnings") != 0 \
                    or beta.get("markerCreations") != 4 \
                    or beta.get("markerDestructions") != 3:
                raise RuntimeError(
                    "Beta.13 controls did not repair all three real cycles")
            for index, cycle in enumerate(beta_cycles, 1):
                returned = cycle.get("returned", {}) if isinstance(cycle, dict) else {}
                settled = cycle.get("settledLoader", {}) if isinstance(cycle, dict) else {}
                if cycle.get("cycle") != index \
                        or returned.get("classification") != "component-resolution" \
                        or returned.get("componentPresent") is not True \
                        or returned.get("componentStatusKind") != "undefined" \
                        or returned.get("componentStatus") != -1 \
                        or returned.get("resolvedComponentPresent") is not False \
                        or returned.get("resolvedComponentStatusKind") != "missing" \
                        or returned.get("currentLoadReady") is not False \
                        or returned.get("loaderActive") is not False \
                        or returned.get("loaderItem") is not False \
                        or returned.get("lifecycle", {}).get("sequence") != "unavailable" \
                        or settled.get("currentLoadReady") is not False \
                        or settled.get("active") is not True \
                        or settled.get("status") != 1 \
                        or settled.get("item") is not True:
                    raise RuntimeError(
                        "Beta.13 cycle did not preserve observed loss and legacy control")

            mutant_loss = staged_mutant.get("firstPersistentLoss")
            mutant_cycles = staged_mutant.get("actualTransitions")
            mutant_cycle = mutant_cycles[0] if isinstance(mutant_cycles, list) \
                and len(mutant_cycles) == 1 else {}
            mutant_returned = mutant_cycle.get("returned", {})
            mutant_settled = mutant_cycle.get("settledLoader", {})
            if staged_mutant.get("outcome") != "expected-failure" \
                    or mutant_loss != {
                        "transition": "restore", "cycle": 1,
                        "stage": "component-resolution", "validOutputs": 1} \
                    or staged_mutant.get("cycles") != 1 \
                    or staged_mutant.get("harnessRescans") != 0 \
                    or staged_mutant.get("nativeRescanCountInitial") != 1 \
                    or staged_mutant.get("nativeRescanCountFinal") != 1 \
                    or staged_mutant.get("passiveWarnings") != 1 \
                    or staged_mutant.get("markerCreations") != 1 \
                    or staged_mutant.get("markerDestructions") != 1 \
                    or mutant_returned.get("componentPresent") is not True \
                    or mutant_returned.get("componentStatusKind") != "undefined" \
                    or mutant_returned.get("componentStatus") != -1 \
                    or mutant_returned.get("resolvedComponentPresent") is not False \
                    or mutant_returned.get("resolvedComponentStatusKind") != "missing" \
                    or mutant_returned.get("currentLoadReady") is not False \
                    or mutant_returned.get("loaderActive") is not False \
                    or mutant_returned.get("loaderStatus") != 0 \
                    or mutant_returned.get("loaderItem") is not False \
                    or mutant_settled.get("lifecycle", {}).get("warningEmitted") is not True:
                raise RuntimeError(
                    "scoped-status mutant did not fail once with one passive warning")

            candidate_cycles = current.get("actualTransitions")
            if not isinstance(candidate_cycles, list) or len(candidate_cycles) != 3:
                raise RuntimeError("candidate transition census is missing or unbounded")
            for index, cycle in enumerate(candidate_cycles, 1):
                if not isinstance(cycle, dict):
                    raise RuntimeError("candidate transition record is malformed")
                returned = cycle.get("returned", {})
                if cycle.get("cycle") != index or cycle.get("transition") != [1, 0, 1] \
                        or cycle.get("identity") != {
                            "id": MARKER_ID, "configured": True, "selected": True} \
                        or returned.get("classification") != "ok" \
                        or returned.get("componentPresent") is not True \
                        or returned.get("componentStatusKind") != "undefined" \
                        or returned.get("componentStatus") != -1 \
                        or returned.get("resolvedComponentPresent") is not True \
                        or returned.get("resolvedComponentStatusKind") != "undefined" \
                        or returned.get("resolvedStatus") != -1 \
                        or returned.get("currentLoadReady") is not True \
                        or returned.get("loaderActive") is not True \
                        or returned.get("loaderStatus") != 1 \
                        or returned.get("loaderItem") is not True \
                        or returned.get("lifecycle") != {
                            "presenceObserved": True, "lossObserved": True,
                            "returnObserved": True,
                            "sequence": "positive-zero-positive",
                            "previouslyReadyWidgetCount": 1,
                            "lossReadyWidgetCount": 1,
                            "warningEmitted": False}:
                    raise RuntimeError(
                        "candidate cycle did not prove unknown-status Loader success")

            if current_loss is not None \
                    or current.get("cycles") != 3 \
                    or current.get("harnessRescans") != 0 \
                    or current.get("nativeRescanCountInitial") != 1 \
                    or current.get("nativeRescanCountFinal") != 1 \
                    or current.get("startupPrimeRetained") is not True \
                    or current.get("registryIdentityStable") is not True \
                    or current.get("passiveWarnings") != 0 \
                    or current.get("markerCreations") != 4 \
                    or current.get("markerDestructions") != 3:
                raise RuntimeError(
                    "candidate did not return through current Loader provenance")
            beta_absent = beta.get("firstAbsentRegistryGap")
            current_absent = current.get("firstAbsentRegistryGap")
            if beta_loss != current_loss:
                comparison = {"firstMeasuredDivergence": {
                    "beta13": beta_loss, "candidate": current_loss}}
            elif beta_absent != current_absent:
                comparison = {"firstMeasuredDivergence": {
                    "beta13": beta_absent, "candidate": current_absent}}
            elif not beta_loss:
                comparison = {"remainingGap":
                    "neither build reproduced persistent widget loss in the bounded run"}
            else:
                comparison = {"remainingGap":
                    "both builds failed current component admission after output return"}
            print("WIDGET_PIPELINE_COMPARISON " + json.dumps({
                "beta13": beta, "candidateStatusGuardMutant": staged_mutant,
                "candidate": current, "candidateFingerprints": candidate_fingerprints,
                "candidateStatusGuardMutantFingerprints": mutant_fingerprints,
                "nativeManifestsWithheld": len(withheld), **comparison,
            }, sort_keys=True), flush=True)
        finally:
            print("Removing full-native widget fixture " + str(root), flush=True)
    if root.exists():
        raise RuntimeError("full-native widget fixture cleanup failed")
    print("Full-native widget fixture removed", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired,
            json.JSONDecodeError) as error:
        raise SystemExit("widget-pipeline-native-regression: " + str(error)) from error
