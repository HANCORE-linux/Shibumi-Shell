#!/usr/bin/env python3
"""Classify bounded widget-pipeline census records and test fail-closed cases."""

import argparse
import json
import os
import sys
import unittest

MAX_REPORT_BYTES = 256 * 1024
MARKER_ID = "hancore.shibumi.cpu"
COMPONENT_KINDS = {"missing", "undefined", "number", "other", "unavailable"}
EXPECTED_KEYS = {
    "id", "configured", "selection", "componentPresent",
    "componentStatusKind", "componentStatus",
}
SLOT_KEYS = {
    "id", "screen", "moduleEnabled", "resolutionAttempts",
    "resolvedComponentPresent", "resolvedComponentStatusKind", "resolvedStatus",
    "currentLoadReady", "loaderActive", "loaderStatus", "loaderItem",
}
LIFECYCLE_KEYS = {
    "presenceObserved", "lossObserved", "returnObserved", "sequence",
    "previouslyReadyWidgetCount", "lossReadyWidgetCount", "warningEmitted",
}


def component_projection_valid(present, kind, status):
    if type(present) is not bool or kind not in COMPONENT_KINDS or type(status) is not int:
        return False
    if not present:
        return kind in {"missing", "unavailable"} and status == -1
    if kind == "number":
        return 0 <= status <= 3
    return status == -1 and kind != "missing"


def classify_report(state, phase, mode, output, build, home="", cycle=1):
    if type(cycle) is not int or not 1 <= cycle <= 3:
        return "output-cycle"
    if not isinstance(state, dict) or state.get("version") != 2:
        return "diagnostic-version"
    if set(state) != {
            "version", "facades", "outputs", "outputLifecycle", "registry",
            "expected", "widgetSlots"}:
        return "diagnostic-shape"
    try:
        serialized = json.dumps(state, separators=(",", ":"))
    except (TypeError, ValueError):
        return "diagnostic-shape"
    for forbidden in ("authorization", "sourceUrl", "backendMetadata", "metadata", home):
        if forbidden and forbidden in serialized:
            return "diagnostic-redaction"
    if state.get("facades") != {
            "shellScoped": True, "pluginRegistryScoped": True,
            "widgetRegistryPresent": True}:
        return "public-registry-api"

    expected_group = state.get("expected", {})
    slots_group = state.get("widgetSlots", {})
    outputs = state.get("outputs", {})
    registry = state.get("registry", {})
    lifecycle = state.get("outputLifecycle", {})
    if (expected_group.get("truncated") is not False
            or slots_group.get("truncated") is not False
            or outputs.get("truncated") is not False
            or registry.get("snapshotKeyCountTruncated") is not False):
        return "diagnostic-bound"

    expected = expected_group.get("entries")
    if (not isinstance(expected, list) or len(expected) != 1
            or not isinstance(expected[0], dict)
            or set(expected[0]) != EXPECTED_KEYS):
        return "registry-selection-shape"
    entry = expected[0]
    if (entry.get("id") != MARKER_ID
            or entry.get("configured") is not True
            or type(entry.get("selection")) is not bool
            or not component_projection_valid(
                entry.get("componentPresent"), entry.get("componentStatusKind"),
                entry.get("componentStatus"))):
        return "registry-selection-shape"

    registry_count = registry.get("snapshotKeyCount")
    if type(registry_count) is not int:
        return "registry-snapshot"
    if set(lifecycle) != LIFECYCLE_KEYS:
        return "output-lifecycle-shape"
    if (type(lifecycle.get("presenceObserved")) is not bool
            or type(lifecycle.get("lossObserved")) is not bool
            or type(lifecycle.get("returnObserved")) is not bool
            or type(lifecycle.get("previouslyReadyWidgetCount")) is not int
            or type(lifecycle.get("lossReadyWidgetCount")) is not int
            or type(lifecycle.get("warningEmitted")) is not bool):
        return "output-lifecycle-shape"

    historical_beta13 = build in ("beta13", "beta13-negative-control")
    if historical_beta13:
        if lifecycle != {
                "presenceObserved": False, "lossObserved": False,
                "returnObserved": False, "sequence": "unavailable",
                "previouslyReadyWidgetCount": 0, "lossReadyWidgetCount": 0,
                "warningEmitted": False}:
            return "output-lifecycle-unavailable"
    else:
        lifecycle_expected = {
            "initial": (True, False, False, "positive", 1, 0),
            # Chronology is latched for this Bar owner, not reset per flap.
            "absent": (True, True, cycle > 1,
                       "positive-zero-positive" if cycle > 1 else "positive-zero", 1, 1),
            "returned": (True, True, True, "positive-zero-positive", 1, 1),
        }.get(phase)
        if lifecycle_expected is None:
            return "output-lifecycle-phase"
        actual = (
            lifecycle.get("presenceObserved"), lifecycle.get("lossObserved"),
            lifecycle.get("returnObserved"), lifecycle.get("sequence"),
            lifecycle.get("previouslyReadyWidgetCount"),
            lifecycle.get("lossReadyWidgetCount"),
        )
        if actual != lifecycle_expected:
            return "output-lifecycle"
        if build == "candidate" and lifecycle.get("warningEmitted") is not False:
            return "passive-warning"

    valid_outputs = outputs.get("validOutputCount")
    if type(valid_outputs) is not int:
        return "output-return"
    sessions = outputs.get("sessions")
    if not isinstance(sessions, list):
        return "bar-panel"
    if phase == "absent" and mode != "negative":
        if valid_outputs != 0:
            return "output-drain"
        if (any(isinstance(row, dict) and row.get("screen") == output for row in sessions)
                or outputs.get("barPanelCount") != len(sessions)
                or outputs.get("layoutSessionCount") != len(sessions)
                or slots_group.get("count") != 0):
            return "output-drain"
        if entry.get("selection") is not True:
            return "registry-selection"
        if registry_count != 1:
            return "registry-snapshot"
        if not entry.get("componentPresent"):
            return "component-observation"
        return "ok"

    if valid_outputs != 1:
        return "output-return"
    if (len(sessions) != 1 or not isinstance(sessions[0], dict)
            or sessions[0].get("screen") != output
            or sessions[0].get("barPanel") is not True
            or sessions[0].get("layoutSession") is not True
            or outputs.get("barPanelCount") != 1
            or outputs.get("layoutSessionCount") != 1):
        return "bar-panel"

    slots = slots_group.get("entries")
    if not isinstance(slots, list):
        return "widget-slot"
    marker_slots = [row for row in slots
                    if isinstance(row, dict) and row.get("id") == MARKER_ID]
    if (len(marker_slots) != 1 or marker_slots[0].get("screen") != output
            or set(marker_slots[0]) != SLOT_KEYS):
        return "widget-slot"
    slot = marker_slots[0]
    if (type(slot.get("moduleEnabled")) is not bool
            or type(slot.get("resolutionAttempts")) is not int
            or type(slot.get("currentLoadReady")) is not bool
            or type(slot.get("loaderActive")) is not bool
            or type(slot.get("loaderStatus")) is not int
            or type(slot.get("loaderItem")) is not bool
            or not component_projection_valid(
                slot.get("resolvedComponentPresent"),
                slot.get("resolvedComponentStatusKind"),
                slot.get("resolvedStatus"))):
        return "widget-slot-shape"

    # The negative control is accepted only after the nested output owns a
    # real BarPanel and an unresolved WidgetSlot. Selection failure alone is
    # never enough to turn the arm green.
    if mode == "negative":
        if entry.get("selection") is not False:
            return "negative-selection"
        if registry_count != 0:
            return "registry-snapshot"
        if (entry.get("componentPresent") is not False
                or entry.get("componentStatusKind") != "missing"
                or slot.get("moduleEnabled") is not True
                or slot.get("resolvedComponentPresent") is not False
                or slot.get("resolvedComponentStatusKind") != "missing"
                or slot.get("resolvedStatus") != -1
                or slot.get("currentLoadReady") is not False
                or slot.get("loaderActive") is not False
                or slot.get("loaderStatus") != 0
                or slot.get("loaderItem") is not False):
            return "negative-unresolved-slot"
        return "registry-selection"

    if entry.get("selection") is not True:
        return "registry-selection"
    if registry_count != 1:
        return "registry-snapshot"
    if entry.get("componentPresent") is not True:
        return "component-observation"
    if slot.get("moduleEnabled") is not True:
        return "group-slot"
    if slot.get("resolvedComponentPresent") is not True:
        return "component-resolution"
    if slot.get("loaderActive") is not True:
        return "loader-inactive"
    if slot.get("loaderStatus") == 3:
        return "loader-error"
    if slot.get("loaderStatus") != 1:
        return "loader-not-ready"
    if slot.get("loaderItem") is not True:
        return "loader-missing-item"
    if not historical_beta13 and slot.get("currentLoadReady") is not True:
        return "loader-not-current"

    return "ok"


def fixture_report():
    return {
        "version": 2,
        "facades": {"shellScoped": True, "pluginRegistryScoped": True,
                    "widgetRegistryPresent": True},
        "outputs": {"validOutputCount": 1, "barPanelCount": 1,
                    "layoutSessionCount": 1, "truncated": False,
                    "sessions": [{"screen": "HEADLESS-1", "barPanel": True,
                                  "layoutSession": True}]},
        "outputLifecycle": {
            "presenceObserved": True, "lossObserved": True,
            "returnObserved": True, "sequence": "positive-zero-positive",
            "previouslyReadyWidgetCount": 1, "lossReadyWidgetCount": 1,
            "warningEmitted": False},
        "registry": {"snapshotKeyCount": 1,
                     "snapshotKeyCountTruncated": False, "revision": 7},
        "expected": {"truncated": False, "entries": [{
            "id": MARKER_ID, "configured": True, "selection": True,
            "componentPresent": True, "componentStatusKind": "undefined",
            "componentStatus": -1}]},
        "widgetSlots": {"count": 1, "truncated": False, "entries": [{
            "id": MARKER_ID, "screen": "HEADLESS-1", "moduleEnabled": True,
            "resolutionAttempts": 0, "resolvedComponentPresent": True,
            "resolvedComponentStatusKind": "undefined", "resolvedStatus": -1,
            "currentLoadReady": True, "loaderActive": True, "loaderStatus": 1,
            "loaderItem": True}]},
    }


class ClassifierRegression(unittest.TestCase):
    def classify(self, state):
        return classify_report(state, "returned", "positive", "HEADLESS-1", "candidate")

    def test_unknown_component_projection_with_current_loaded_item_is_success(self):
        self.assertEqual(self.classify(fixture_report()), "ok")

    def test_ready_loader_without_item_is_distinct_failure(self):
        state = fixture_report()
        state["widgetSlots"]["entries"][0]["loaderItem"] = False
        self.assertEqual(self.classify(state), "loader-missing-item")

    def test_loader_error_is_distinct_failure(self):
        state = fixture_report()
        state["widgetSlots"]["entries"][0]["loaderStatus"] = 3
        state["widgetSlots"]["entries"][0]["loaderItem"] = False
        self.assertEqual(self.classify(state), "loader-error")

    def test_loaded_item_without_current_provenance_is_distinct_failure(self):
        state = fixture_report()
        state["widgetSlots"]["entries"][0]["currentLoadReady"] = False
        self.assertEqual(self.classify(state), "loader-not-current")

    def test_unknown_projection_cannot_override_missing_selection(self):
        state = fixture_report()
        state["expected"]["entries"][0]["selection"] = False
        state["registry"]["snapshotKeyCount"] = 0
        self.assertEqual(self.classify(state), "registry-selection")

    def test_missing_slot_component_is_not_a_loader_failure(self):
        state = fixture_report()
        slot = state["widgetSlots"]["entries"][0]
        slot.update({"resolvedComponentPresent": False,
                     "resolvedComponentStatusKind": "missing",
                     "resolvedStatus": -1, "currentLoadReady": False,
                     "loaderActive": False, "loaderStatus": 0,
                     "loaderItem": False})
        self.assertEqual(self.classify(state), "component-resolution")

    def test_later_absence_preserves_but_first_absence_rejects_return_history(self):
        state = fixture_report()
        state["outputs"].update(validOutputCount=0, barPanelCount=0,
                                layoutSessionCount=0, sessions=[])
        state["widgetSlots"].update(count=0, entries=[])
        self.assertEqual(classify_report(state, "absent", "positive",
            "HEADLESS-1", "candidate", cycle=2), "ok")
        self.assertEqual(classify_report(state, "absent", "positive",
            "HEADLESS-1", "candidate", cycle=1), "output-lifecycle")
        state["outputLifecycle"].update(returnObserved=False, sequence="positive-zero")
        self.assertEqual(classify_report(state, "absent", "positive",
            "HEADLESS-1", "candidate", cycle=1), "ok")
        self.assertEqual(classify_report(state, "absent", "positive",
            "HEADLESS-1", "candidate", cycle=2), "output-lifecycle")

    def test_beta13_negative_requires_unavailable_lifecycle_and_real_slot(self):
        state = fixture_report()
        state["outputLifecycle"] = {
            "presenceObserved": False, "lossObserved": False,
            "returnObserved": False, "sequence": "unavailable",
            "previouslyReadyWidgetCount": 0, "lossReadyWidgetCount": 0,
            "warningEmitted": False}
        entry = state["expected"]["entries"][0]
        entry.update({"selection": False, "componentPresent": False,
                      "componentStatusKind": "missing", "componentStatus": -1})
        state["registry"]["snapshotKeyCount"] = 0
        slot = state["widgetSlots"]["entries"][0]
        slot.update({"resolvedComponentPresent": False,
                     "resolvedComponentStatusKind": "missing",
                     "resolvedStatus": -1, "currentLoadReady": False,
                     "loaderActive": False, "loaderStatus": 0,
                     "loaderItem": False})
        self.assertEqual(classify_report(
            state, "initial", "negative", "HEADLESS-1",
            "beta13-negative-control"), "registry-selection")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--classify", action="store_true")
    parser.add_argument("--phase", choices=("initial", "absent", "returned"))
    parser.add_argument("--mode", choices=("positive", "negative"))
    parser.add_argument("--output")
    parser.add_argument("--build")
    parser.add_argument("--cycle", type=int, choices=(1, 2, 3), default=1)
    args, unittest_args = parser.parse_known_args()
    if args.classify:
        if unittest_args or not all((args.phase, args.mode, args.output, args.build)):
            raise SystemExit("classifier arguments are incomplete")
        payload = sys.stdin.buffer.read(MAX_REPORT_BYTES + 1)
        if len(payload) > MAX_REPORT_BYTES:
            print("diagnostic-bound")
            raise SystemExit
        try:
            report = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            print("invalid-report")
            raise SystemExit
        print(classify_report(report, args.phase, args.mode, args.output,
                              args.build, os.path.expanduser("~"), args.cycle))
    else:
        unittest.main(argv=[sys.argv[0], *unittest_args])
