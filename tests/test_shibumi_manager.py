#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import runpy
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


REPO_ROOT = Path(__file__).resolve().parents[1]
MANAGER = (
    REPO_ROOT
    / "hancore.shibumi.control-center"
    / "manager"
    / "shibumi-manager"
)

QUICKSHELL_EMPTY_REGISTRY = "No running instances.\n"
INVALID_EMPTY_REGISTRY_OUTPUTS = (
    "",
    "No running instances.",
    " No running instances.\n",
    "No running instances. \n",
    "No running instances.\r\n",
    "No running instances.\nextra",
    "prefix No running instances.\n",
    "{}",
    "null",
    "not-json\n",
)


def settings(config):
    return next(entry for entry in config["plugins"]
                if entry["id"] == "hancore.shibumi.state")["shibumi"]


class ContinuityManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="shibumi-manager-test.")
        self.root = Path(self.temporary.name)
        self.module = runpy.run_path(str(MANAGER))
        self.state = {
            "suiteId": "hancore.shibumi",
            "plugins": [
                "hancore.shibumi.bar",
                "hancore.shibumi.state",
                "hancore.shibumi.control-center",
                "hancore.shibumi.widget",
            ],
            "activation": {
                "activeBar": "hancore.shibumi.bar",
                "layout": {
                    "left": ["hancore.shibumi.control-center"],
                    "center": [],
                    "right": ["hancore.shibumi.widget"],
                },
                "enableServices": ["hancore.shibumi.state"],
                "continuityPlugins": [
                    "hancore.shibumi.control-center",
                    "hancore.shibumi.state",
                ],
            },
        }
        self.defaults = {
            "version": 1,
            "bar": {
                "centerAnchor": "omarchy.clock",
                "layout": {
                    "left": [{"id": "omarchy.menu"}],
                    "center": [{"id": "omarchy.clock"}],
                    "right": [],
                },
            },
            "plugins": [],
        }
        self.active = {
            "version": 1,
            "bar": {
                "id": "hancore.shibumi.bar",
                "centerAnchor": "hancore.shibumi.center",
                "style": "shibumi",
                "layout": {
                    "left": [
                        {"id": "hancore.shibumi.control-center"},
                        {"id": "user.widget", "position": 4},
                    ],
                    "center": [{"id": "omarchy.weather", "units": "metric"}],
                    "right": [{"id": "hancore.shibumi.widget"}],
                },
            },
            "plugins": [
                {"id": "user.service", "interval": 9},
                {"id": "hancore.shibumi.state", "shibumiStateSchemaVersion": 1,
                 "future": {"preserve": [0, False, "Malmö"]},
                 "shibumi": {"version": 1, "scale": 1.25, "picker": {
                     "style": "hearthstone", "imageStyle": "hearthstone",
                     "mediaStyle": "hearthstone"}}},
            ],
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_profile_round_trip_keeps_shell_layouts_separate(self) -> None:
        shibumi_layout = self.module["copy_layout"](
            self.active["bar"]["layout"]
        )
        inactive = self.module["deactivate_config"](
            self.active,
            self.defaults,
            self.state,
            self.defaults["bar"]["layout"],
        )
        self.assertEqual(inactive["bar"].get("id", "omarchy.bar"), "omarchy.bar")
        self.assertEqual(inactive["bar"]["centerAnchor"], "omarchy.clock")
        self.assertEqual(settings(inactive)["scale"], 1.25)
        self.assertEqual(inactive["plugins"], self.active["plugins"])
        self.assertEqual(
            settings(inactive)["picker"],
            {
                "style": "hearthstone",
                "imageStyle": "hearthstone",
                "mediaStyle": "hearthstone",
            },
        )
        self.assertEqual(
            {
                self.module["entry_id"](entry)
                for region in ("left", "center", "right")
                for entry in inactive["bar"]["layout"][region]
            },
            {
                "omarchy.menu",
                "omarchy.clock",
                "hancore.shibumi.control-center",
            },
        )
        self.assertEqual(
            [
                self.module["entry_id"](entry)
                for entry in inactive["bar"]["layout"]["right"]
            ],
            ["hancore.shibumi.control-center"],
        )
        self.assertEqual(
            {self.module["entry_id"](entry) for entry in inactive["plugins"]},
            {"hancore.shibumi.state", "user.service"},
        )

        active = self.module["activate_config"](
            inactive, self.state, shibumi_layout
        )
        self.assertEqual(active["bar"]["id"], "hancore.shibumi.bar")
        self.assertEqual(settings(active)["scale"], 1.25)
        self.assertEqual(active["plugins"], self.active["plugins"])
        self.assertEqual(
            settings(active)["picker"]["imageStyle"], "hearthstone"
        )
        user_widget = next(
            entry
            for entry in active["bar"]["layout"]["left"]
            if self.module["entry_id"](entry) == "user.widget"
        )
        self.assertEqual(user_widget["position"], 4)
        user_service = next(
            entry
            for entry in active["plugins"]
            if self.module["entry_id"](entry) == "user.service"
        )
        self.assertEqual(user_service["interval"], 9)
        weather = next(
            entry
            for entry in active["bar"]["layout"]["center"]
            if self.module["entry_id"](entry) == "omarchy.weather"
        )
        self.assertEqual(weather["units"], "metric")
        self.assertNotIn(
            "omarchy.menu",
            {
                self.module["entry_id"](entry)
                for region in ("left", "center", "right")
                for entry in active["bar"]["layout"][region]
            },
        )

    def _saved_profile_switch_evidence(
        self,
        plugin_id: str,
        *,
        installed: bool,
        initial_snapshot: str = "valid",
        initial_omit: bool = False,
        later_active: bool = True,
        plugin_enabled: bool = False,
        target: str = "shibumi",
        missing_target_profile: bool = False,
        fail_after_profile: bool = False,
        restore_profile_on_rollback: bool = False,
        target_contains_plugin: bool = True,
        configured_entry: dict[str, object] | None = None,
        source_entry: dict[str, object] | None = None,
        plugin_kinds: list[str] | None = None,
        plugin_first_party: bool = False,
    ) -> dict[str, object]:
        case_root = self.root / "-".join(
            (
                target,
                plugin_id,
                initial_snapshot,
                str(initial_omit),
                str(later_active),
                str(missing_target_profile),
                str(fail_after_profile),
                str(restore_profile_on_rollback),
                str(target_contains_plugin),
                str(configured_entry is not None),
                str(source_entry is not None),
            )
        )
        omarchy_root = case_root / "omarchy"
        config = case_root / "config/omarchy/shell.json"
        defaults = omarchy_root / "config/omarchy/shell.json"
        state_dir = case_root / "state/shibumi"
        runtime = case_root / "runtime"
        config.parent.mkdir(parents=True)
        defaults.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)

        inactive = self.module["deactivate_config"](
            self.active,
            self.defaults,
            self.state,
            self.defaults["bar"]["layout"],
        )
        current = copy.deepcopy(inactive if target == "shibumi" else self.active)
        if configured_entry is not None:
            current["plugins"].append(copy.deepcopy(configured_entry))
        if source_entry is not None:
            current["bar"]["layout"]["right"].append(copy.deepcopy(source_entry))
        state = copy.deepcopy(self.state)
        target_layout = self.module["initial_layout"](
            target, self.defaults, state
        )
        if target_contains_plugin:
            target_layout["left"].append({"id": plugin_id, "position": 7})
        if missing_target_profile:
            self.assertEqual(target, "omarchy")
            state["previousBar"] = {
                "layout": copy.deepcopy(target_layout),
                "centerAnchor": "omarchy.clock",
            }
        config.write_text(json.dumps(current) + "\n", encoding="utf-8")
        defaults.write_text(json.dumps(self.defaults) + "\n", encoding="utf-8")
        state_path = state_dir / "install.json"
        state_path.write_text(json.dumps(state) + "\n", encoding="utf-8")
        saved_profiles = {
            "schemaVersion": 1,
            "layouts": {
                "shibumi": target_layout
                if target == "shibumi"
                else self.active["bar"]["layout"],
                "omarchy": target_layout
                if target == "omarchy"
                else inactive["bar"]["layout"],
            },
            "centerAnchors": {
                "shibumi": "hancore.shibumi.center",
                "omarchy": "omarchy.clock",
            },
        }
        if missing_target_profile:
            del saved_profiles["layouts"][target]
        profile = state_dir / "shell-layout-profiles.json"
        profile.write_text(
            json.dumps(saved_profiles) + "\n",
            encoding="utf-8",
        )
        original_config = config.read_bytes()
        original_state = state_path.read_bytes()
        original_profile = profile.read_bytes()
        environment = {
            "OMARCHY_PATH": str(omarchy_root),
            "SHIBUMI_CONFIG_FILE": str(config),
            "SHIBUMI_DEFAULT_CONFIG": str(defaults),
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }

        reloads = 0
        clock = 0.0
        failure_injected = False
        profile_restored = False
        stop = Mock()

        def registry(active_bar: str) -> list[dict[str, object]]:
            allowed_stock = {
                *self.state["activation"]["enableServices"],
                "hancore.shibumi.control-center",
            }
            values = [
                {
                    "id": managed_id,
                    "kinds": ["bar"] if managed_id.endswith(".bar") else ["service"],
                    "firstParty": False,
                    "enabled": active_bar != "omarchy.bar"
                    or managed_id in allowed_stock,
                    "active": managed_id == active_bar,
                }
                for managed_id in self.state["plugins"]
            ]
            values.append(
                {
                    "id": "omarchy.bar",
                    "kinds": ["bar"],
                    "firstParty": True,
                    "enabled": True,
                    "active": active_bar == "omarchy.bar",
                }
            )
            if installed and plugin_id not in self.state["plugins"]:
                values.append(
                    {
                        "id": plugin_id,
                        "kinds": ["bar-widget"] if plugin_kinds is None else plugin_kinds,
                        "firstParty": plugin_first_party,
                        "enabled": plugin_enabled,
                        "active": False,
                    }
                )
            return values

        def fake_shell_call(
            _runtime_paths: dict[str, Path],
            arguments: list[str],
            *,
            check: bool = False,
        ) -> Mock:
            del check
            if arguments == ["shell", "listPlugins"]:
                active_bar = (
                    ("omarchy.bar" if target == "shibumi" else "hancore.shibumi.bar")
                    if reloads == 0
                    else ("hancore.shibumi.bar" if target == "shibumi" else "omarchy.bar")
                )
                if reloads and not later_active:
                    active_bar = ""
                values: list[object] = registry(active_bar)
                if reloads == 0:
                    if initial_omit:
                        values = [value for value in values if value["id"] != plugin_id]
                    if initial_snapshot == "unavailable":
                        return Mock(returncode=1, stdout="", stderr="unavailable")
                    if initial_snapshot == "empty":
                        values = []
                    elif initial_snapshot == "malformed-row":
                        values.append("malformed")
                    elif initial_snapshot == "non-string-id":
                        values.append({"id": 7, "enabled": True})
                    elif initial_snapshot == "duplicate":
                        values.append(copy.deepcopy(values[0]))
                    elif initial_snapshot == "empty-id":
                        values.append({"id": "", "enabled": True})
                    elif initial_snapshot == "incomplete-managed":
                        values = [
                            value
                            for value in values
                            if value["id"] != self.state["plugins"][0]
                        ]
                    elif initial_snapshot in ("missing-enabled", "nonbool-enabled", "empty-kinds"):
                        row = values[0]
                        if initial_snapshot == "missing-enabled":
                            row.pop("enabled")
                        elif initial_snapshot == "nonbool-enabled":
                            row["enabled"] = 1
                        else:
                            row["kinds"] = []
                stdout = json.dumps(values)
                if reloads == 0 and initial_snapshot == "duplicate-id-key":
                    stdout = stdout[:-1] + (
                        f',{{"id":{json.dumps(plugin_id)},'
                        '"id":"last-wins.decoy","enabled":true}]'
                    )
                return Mock(returncode=0, stdout=stdout, stderr="")
            if arguments == ["shell", "ping"]:
                return Mock(returncode=0, stdout="ok\n", stderr="")
            raise AssertionError(f"unexpected fake IPC call: {arguments}")

        def fake_reload(*_args: object, **_kwargs: object) -> None:
            nonlocal reloads, profile_restored
            if (
                restore_profile_on_rollback
                and failure_injected
                and not profile_restored
            ):
                profile.write_bytes(original_profile)
                profile_restored = True
            reloads += 1

        def monotonic() -> float:
            return clock

        def sleep(seconds: float) -> None:
            nonlocal clock
            clock += seconds

        globals_map = self.module["perform"].__globals__
        original_verify = globals_map["verify"]
        original_atomic_write = globals_map["atomic_write"]
        original_retire = globals_map["retire_switch_transaction"]
        retired_journal_phases: list[str] = []

        def faulting_atomic_write(path: Path, payload: bytes) -> None:
            nonlocal failure_injected
            original_atomic_write(path, payload)
            if fail_after_profile and path == profile and not failure_injected:
                failure_injected = True
                raise self.module["ManagerError"](
                    "injected failure after profile rename"
                )

        def observing_retire(
            runtime_paths: dict[str, Path], transaction: Path
        ) -> None:
            journal = json.loads(
                (transaction / "journal.json").read_text(encoding="utf-8")
            )
            retired_journal_phases.append(journal["phase"])
            original_retire(runtime_paths, transaction)

        def bounded_verify(
            runtime_paths: dict[str, Path],
            state: dict[str, object],
            target: str,
        ) -> None:
            original_verify(runtime_paths, state, target, timeout=0.3)

        error = ""
        with patch.dict("os.environ", environment, clear=False), patch.dict(
            globals_map,
            {
                "stop_shell": stop,
                "reload_shell": fake_reload,
                "shell_call": fake_shell_call,
                "verify": bounded_verify,
                "atomic_write": faulting_atomic_write,
                "retire_switch_transaction": observing_retire,
            },
        ), patch.object(globals_map["time"], "monotonic", monotonic), patch.object(
            globals_map["time"], "sleep", sleep
        ):
            try:
                self.module["perform"](target)
            except self.module["ManagerError"] as caught:
                error = str(caught)

            failure_evidence = None
            retry_error = ""
            retry_return = None
            if fail_after_profile:
                failure_evidence = {
                    "error": error,
                    "status": json.loads(
                        (state_dir / "switch-status.json").read_text(
                            encoding="utf-8"
                        )
                    ),
                    "configRestored": config.read_bytes() == original_config,
                    "stateRestored": state_path.read_bytes() == original_state,
                    "profileChanged": profile.read_bytes() != original_profile,
                    "savedProfiles": json.loads(
                        profile.read_text(encoding="utf-8")
                    ),
                    "transactionRetained": (
                        state_dir / "switch-transaction"
                    ).exists(),
                }
                try:
                    retry_return = self.module["perform"](target)
                except self.module["ManagerError"] as caught:
                    retry_error = str(caught)

        final_config = json.loads(config.read_text(encoding="utf-8"))
        final_profile = json.loads(profile.read_text(encoding="utf-8"))
        status = json.loads(
            (state_dir / "switch-status.json").read_text(encoding="utf-8")
        )

        def layout_ids(layout: dict[str, list[object]]) -> list[str]:
            return sorted(
                self.module["entry_id"](entry)
                for region in ("left", "center", "right")
                for entry in layout[region]
            )

        evidence = {
            "error": error,
            "phase": status["phase"],
            "detail": status["detail"],
            "activeBar": final_config["bar"].get("id", "omarchy.bar"),
            "layout": layout_ids(final_config["bar"]["layout"]),
            "savedLayout": layout_ids(
                final_profile["layouts"][target]
            ),
            "savedProfiles": final_profile,
            "configRestored": config.read_bytes() == original_config,
            "profileChanged": profile.read_bytes() != original_profile,
            "transactionRetained": (state_dir / "switch-transaction").exists(),
            "stopCalls": stop.call_count,
            "reloadCalls": reloads,
        }
        if configured_entry is not None:
            evidence["configuredEntry"] = next(
                entry for entry in final_config["plugins"] if entry.get("id") == plugin_id
            )
        if failure_evidence is not None:
            evidence.update({
                "failure": failure_evidence,
                "retiredJournalPhases": retired_journal_phases,
                "retry": {
                    "error": retry_error,
                    "return": retry_return,
                    "phase": status["phase"],
                    "detail": status["detail"],
                },
            })
        return evidence

    def test_failed_post_profile_write_keeps_healed_cache_for_retry(self) -> None:
        plugin_id = "thirdparty.removed"
        evidence = self._saved_profile_switch_evidence(
            plugin_id, installed=False, fail_after_profile=True
        )
        failure = evidence["failure"]
        expected_target = self.module["initial_layout"](
            "shibumi", self.defaults, self.state
        )
        expected_current = self.module["deactivate_config"](
            self.active,
            self.defaults,
            self.state,
            self.defaults["bar"]["layout"],
        )
        expected_profiles = {
            "schemaVersion": 1,
            "layouts": {
                "shibumi": expected_target,
                "omarchy": expected_current["bar"]["layout"],
            },
            "centerAnchors": {
                "shibumi": "hancore.shibumi.center",
                "omarchy": "omarchy.clock",
            },
        }

        self.assertEqual(failure["error"], "injected failure after profile rename")
        self.assertEqual(failure["status"]["phase"], "error")
        self.assertEqual(
            failure["status"]["detail"],
            "injected failure after profile rename",
        )
        self.assertTrue(failure["configRestored"])
        self.assertTrue(failure["stateRestored"])
        self.assertTrue(failure["profileChanged"])
        self.assertFalse(failure["transactionRetained"])
        self.assertEqual(failure["savedProfiles"], expected_profiles)
        self.assertNotIn(
            plugin_id,
            {
                self.module["entry_id"](entry)
                for region in ("left", "center", "right")
                for entry in failure["savedProfiles"]["layouts"]["shibumi"][region]
            },
        )
        self.assertEqual(
            evidence["retiredJournalPhases"], ["rolled-back", "committed"]
        )
        self.assertEqual(
            evidence["retry"],
            {"error": "", "return": 0, "phase": "complete", "detail": ""},
        )
        self.assertEqual(evidence["savedProfiles"], expected_profiles)
        self.assertFalse(evidence["transactionRetained"])

        negative = self._saved_profile_switch_evidence(
            plugin_id,
            installed=False,
            fail_after_profile=True,
            restore_profile_on_rollback=True,
        )
        self.assertIn(
            plugin_id,
            {
                self.module["entry_id"](entry)
                for region in ("left", "center", "right")
                for entry in negative["failure"]["savedProfiles"]["layouts"][
                    "shibumi"
                ][region]
            },
        )
        self.assertEqual(
            negative["retry"]["detail"], f"pruned=['{plugin_id}']"
        )

    def test_switch_drops_absent_third_party_from_saved_shibumi_profile(self) -> None:
        evidence = self._saved_profile_switch_evidence(
            "thirdparty.removed", installed=False
        )
        profiles = evidence.pop("savedProfiles")
        expected_target = self.module["initial_layout"](
            "shibumi", self.defaults, self.state
        )
        expected_layout = sorted(
            plugin_id
            for region in ("left", "center", "right")
            for plugin_id in self.state["activation"]["layout"][region]
        )

        expected_inactive = self.module["deactivate_config"](
            self.active,
            self.defaults,
            self.state,
            self.defaults["bar"]["layout"],
        )
        self.assertEqual(profiles, {
            "schemaVersion": 1,
            "layouts": {
                "shibumi": expected_target,
                "omarchy": expected_inactive["bar"]["layout"],
            },
            "centerAnchors": {
                "shibumi": "hancore.shibumi.center",
                "omarchy": "omarchy.clock",
            },
        })
        self.assertEqual(
            evidence,
            {
                "error": "",
                "phase": "complete",
                "detail": "pruned=['thirdparty.removed']",
                "activeBar": "hancore.shibumi.bar",
                "layout": expected_layout,
                "savedLayout": expected_layout,
                "configRestored": False,
                "profileChanged": True,
                "transactionRetained": False,
                "stopCalls": 1,
                "reloadCalls": 1,
            },
        )

    def test_switch_drops_absent_third_party_from_saved_omarchy_profile(self) -> None:
        plugin_id = "thirdparty.removed"
        evidence = self._saved_profile_switch_evidence(
            plugin_id, installed=False, target="omarchy"
        )
        profiles = evidence.pop("savedProfiles")

        self.assertEqual(profiles, {
            "schemaVersion": 1,
            "layouts": {
                "shibumi": self.active["bar"]["layout"],
                "omarchy": self.defaults["bar"]["layout"],
            },
            "centerAnchors": {
                "shibumi": "hancore.shibumi.center",
                "omarchy": "omarchy.clock",
            },
        })
        self.assertEqual(evidence["phase"], "complete")
        self.assertEqual(evidence["detail"], f"pruned=['{plugin_id}']")
        self.assertEqual(evidence["activeBar"], "omarchy.bar")
        self.assertFalse(evidence["transactionRetained"])

    def test_switch_persists_pruned_synthesized_omarchy_profile(self) -> None:
        plugin_id = "thirdparty.removed"
        evidence = self._saved_profile_switch_evidence(
            plugin_id,
            installed=False,
            target="omarchy",
            missing_target_profile=True,
        )

        self.assertEqual(evidence["error"], "")
        self.assertEqual(evidence["phase"], "complete")
        self.assertNotIn(plugin_id, evidence["layout"])
        self.assertNotIn(plugin_id, evidence["savedLayout"])
        self.assertTrue(evidence["profileChanged"])

    def test_switch_appends_configured_installed_widget_to_target_profile(self) -> None:
        plugin_id = "thirdparty.hey"
        source_entry = {
            "id": plugin_id,
            "shibumiModule": True,
            "inlineSettings": {"greeting": "Hej", "nested": [1, False]},
        }
        evidence = self._saved_profile_switch_evidence(
            plugin_id,
            installed=True,
            plugin_enabled=True,
            target="omarchy",
            target_contains_plugin=False,
            source_entry=source_entry,
            plugin_kinds=["bar-widget", "service"],
        )

        saved = evidence["savedProfiles"]["layouts"]
        self.assertEqual(saved["shibumi"]["right"][-1], source_entry)
        self.assertEqual(saved["omarchy"]["right"][-1], source_entry)
        self.assertEqual(evidence["layout"].count(plugin_id), 1)
        self.assertEqual(evidence["savedLayout"].count(plugin_id), 1)
        self.assertNotIn("configuredEntry", evidence)
        self.assertEqual(evidence["phase"], "complete")

        service_id = "thirdparty.plugins-only-service"
        service_entry = {"id": service_id, "serviceSettings": {"interval": 9}}
        plugins_only = self._saved_profile_switch_evidence(
            service_id,
            installed=True,
            plugin_enabled=True,
            target="omarchy",
            target_contains_plugin=False,
            configured_entry=service_entry,
            plugin_kinds=["bar-widget", "service"],
        )
        self.assertNotIn(service_id, plugins_only["layout"])
        self.assertNotIn(service_id, plugins_only["savedLayout"])
        self.assertEqual(plugins_only["configuredEntry"], service_entry)

        rollback_id = "thirdparty.rollback-widget"
        rollback = self._saved_profile_switch_evidence(
            rollback_id,
            installed=True,
            plugin_enabled=True,
            target="omarchy",
            target_contains_plugin=False,
            source_entry={"id": rollback_id},
            fail_after_profile=True,
        )
        self.assertEqual(
            rollback["failure"]["savedProfiles"]["layouts"]["shibumi"]["right"][-1],
            {"id": rollback_id},
        )
        self.assertTrue(rollback["failure"]["profileChanged"])
        self.assertEqual(rollback["retry"]["phase"], "complete")

    def test_switch_does_not_append_disabled_mixed_kind_plugin(self) -> None:
        plugin_id = "thirdparty.disabled-service-widget"
        source_entry = {"id": plugin_id, "inlineSettings": {"interval": 9}}
        evidence = self._saved_profile_switch_evidence(
            plugin_id,
            installed=True,
            plugin_enabled=False,
            target="omarchy",
            target_contains_plugin=False,
            source_entry=source_entry,
            plugin_kinds=["bar-widget", "service"],
        )

        self.assertEqual(evidence["error"], "")
        self.assertEqual(evidence["phase"], "complete")
        self.assertNotIn(plugin_id, evidence["layout"])
        self.assertNotIn(plugin_id, evidence["savedLayout"])

    def test_layout_reconcile_is_capability_scoped_atomic_and_alias_free(self) -> None:
        managed = set(self.state["plugins"])
        source = {
            "left": [
                {"id": "thirdparty.hey", "inlineSettings": {"nested": ["Hej"]}},
                {"id": "thirdparty.service", "serviceSettings": {"interval": 9}},
            ],
            "center": [
                {"id": "thirdparty.existing", "inlineSettings": {"ignored": True}},
                {"id": "hancore.shibumi.widget"},
            ],
            "right": [{"id": "omarchy.weather"}, {"id": "unknown.source"}],
        }
        plugins = {
            plugin_id: {
                "id": plugin_id, "kinds": ["service"], "firstParty": False, "enabled": True
            }
            for plugin_id in managed
        }
        plugins.update({
            "thirdparty.hey": {"id": "thirdparty.hey", "kinds": ["bar-widget", "service"], "firstParty": False, "enabled": True},
            "thirdparty.service": {"id": "thirdparty.service", "kinds": ["service"], "firstParty": False, "enabled": True},
            "thirdparty.existing": {"id": "thirdparty.existing", "kinds": ["bar-widget"], "firstParty": False, "enabled": False},
            "keep": {"id": "keep", "kinds": ["bar-widget"], "firstParty": False, "enabled": False},
            "omarchy.weather": {"id": "omarchy.weather", "kinds": ["bar-widget"], "firstParty": True, "enabled": True},
        })
        layout = {
            "left": [{"id": "thirdparty.removed"}, {"id": "omarchy.unknown"}],
            "center": [{"id": "thirdparty.existing", "position": 7}],
            "right": [{"id": "keep", "native": {"field": 1}}],
        }

        pruned = self.module["prune_uninstalled_layout_plugins"](
            layout, plugins, managed, source
        )
        self.assertEqual(pruned, ["thirdparty.removed"])
        self.assertEqual(layout["left"], [{"id": "omarchy.unknown"}])
        self.assertEqual(layout["center"], [{"id": "thirdparty.existing", "position": 7}])
        self.assertEqual(layout["right"], [
            {"id": "keep", "native": {"field": 1}}, source["left"][0]
        ])
        self.assertNotIn("hancore.shibumi.widget", str(layout))
        self.assertNotIn("omarchy.weather", str(layout))
        source["left"][0]["inlineSettings"]["nested"].append("mutated")
        self.assertEqual(layout["right"][-1]["inlineSettings"]["nested"], ["Hej"])

        malformed_plugins = []
        for field, value in (
            ("kinds", "bar-widget"), ("kinds", [7]), ("kinds", []),
            ("firstParty", 0), ("enabled", 1), ("enabled", None),
        ):
            malformed = copy.deepcopy(plugins)
            if value is None:
                malformed["thirdparty.hey"].pop(field)
            else:
                malformed["thirdparty.hey"][field] = value
            malformed_plugins.append(malformed)
        duplicate_source = copy.deepcopy(source)
        duplicate_source["right"].append({"id": "thirdparty.hey"})
        malformed_source = copy.deepcopy(source)
        malformed_source["right"].append({"id": 7})
        for bad_plugins, bad_source in (
            ({}, source),
            ({key: value for key, value in plugins.items() if key not in managed}, source),
            *((malformed, source) for malformed in malformed_plugins),
            (plugins, duplicate_source),
            (plugins, malformed_source),
        ):
            with self.subTest(plugins=len(bad_plugins), source=bad_source["right"][-1]):
                unchanged = {"left": [{"id": "thirdparty.removed"}], "center": [], "right": []}
                before = copy.deepcopy(unchanged)
                self.assertEqual(self.module["prune_uninstalled_layout_plugins"](
                    unchanged, bad_plugins, managed, bad_source
                ), [])
                self.assertEqual(unchanged, before)

    def test_switch_keeps_installed_but_disabled_saved_plugin_as_failure(self) -> None:
        plugin_id = "thirdparty.disabled"
        evidence = self._saved_profile_switch_evidence(
            plugin_id, installed=True
        )
        profiles = evidence.pop("savedProfiles")
        failure = (
            "shibumi verification failed: missing=[], missing-from-registry=[], "
            f"disabled=['{plugin_id}'], services=[], active=True"
        )

        saved_entry = next(
            entry
            for entry in profiles["layouts"]["shibumi"]["left"]
            if self.module["entry_id"](entry) == plugin_id
        )
        self.assertEqual(saved_entry, {"id": plugin_id, "position": 7})
        self.assertEqual(
            evidence,
            {
                "error": failure,
                "phase": "error",
                "detail": failure,
                "activeBar": "omarchy.bar",
                "layout": [
                    "hancore.shibumi.control-center",
                    "omarchy.clock",
                    "omarchy.menu",
                ],
                "savedLayout": sorted(
                    [
                        "hancore.shibumi.control-center",
                        "hancore.shibumi.widget",
                        plugin_id,
                    ]
                ),
                "configRestored": True,
                "profileChanged": False,
                "transactionRetained": False,
                "stopCalls": 2,
                "reloadCalls": 2,
            },
        )

    def test_switch_does_not_prune_without_a_complete_valid_snapshot(self) -> None:
        plugin_id = "thirdparty.removed"
        failure = (
            "shibumi verification failed: missing=[], "
            f"missing-from-registry=['{plugin_id}'], disabled=[], services=[], active=True"
        )
        for snapshot in (
            "unavailable",
            "empty",
            "malformed-row",
            "non-string-id",
            "duplicate",
            "duplicate-id-key",
            "empty-id",
            "incomplete-managed",
            "missing-enabled",
            "nonbool-enabled",
            "empty-kinds",
        ):
            with self.subTest(snapshot=snapshot):
                evidence = self._saved_profile_switch_evidence(
                    plugin_id, installed=False, initial_snapshot=snapshot
                )
                profiles = evidence.pop("savedProfiles")
                saved_entry = next(
                    entry
                    for entry in profiles["layouts"]["shibumi"]["left"]
                    if self.module["entry_id"](entry) == plugin_id
                )
                self.assertEqual(saved_entry, {"id": plugin_id, "position": 7})
                self.assertEqual(evidence["error"], failure)
                self.assertEqual(evidence["phase"], "error")
                self.assertEqual(evidence["detail"], failure)
                self.assertTrue(evidence["configRestored"])
                self.assertFalse(evidence["profileChanged"])

    def test_switch_never_prunes_managed_or_omarchy_layout_ids(self) -> None:
        for plugin_id in ("hancore.shibumi.widget", "omarchy.weather"):
            with self.subTest(plugin_id=plugin_id):
                evidence = self._saved_profile_switch_evidence(
                    plugin_id,
                    installed=True,
                    initial_omit=True,
                    plugin_enabled=True,
                )
                profiles = evidence.pop("savedProfiles")
                self.assertIn(plugin_id, evidence["savedLayout"])
                self.assertEqual(evidence["phase"], "complete")
                self.assertEqual(evidence["detail"], "")
                self.assertTrue(
                    any(
                        self.module["entry_id"](entry) == plugin_id
                        and entry.get("position") == 7
                        for region in ("left", "center", "right")
                        for entry in profiles["layouts"]["shibumi"][region]
                    )
                )

    def test_later_verification_failure_does_not_persist_pruned_profile(self) -> None:
        plugin_id = "thirdparty.removed"
        evidence = self._saved_profile_switch_evidence(
            plugin_id, installed=False, later_active=False
        )
        profiles = evidence.pop("savedProfiles")

        self.assertIn(plugin_id, evidence["savedLayout"])
        self.assertEqual(evidence["phase"], "error")
        self.assertIn("active=False", evidence["error"])
        self.assertFalse(evidence["profileChanged"])
        self.assertTrue(
            any(
                self.module["entry_id"](entry) == plugin_id
                for region in ("left", "center", "right")
                for entry in profiles["layouts"]["shibumi"][region]
            )
        )

    def test_canonical_versions_match_native_json_number_semantics(self) -> None:
        for key in ("shibumiStateSchemaVersion", "version"):
            for value in (1, 1.0):
                config = copy.deepcopy(self.active)
                entry = config["plugins"][1]
                (entry if key == "shibumiStateSchemaVersion" else entry["shibumi"])[key] = value
                self.assertIs(self.module["state_settings"](config), entry["shibumi"])
            for value in (True, "1", None, 2):
                with self.subTest(key=key, value=repr(value)):
                    config = copy.deepcopy(self.active)
                    entry = config["plugins"][1]
                    (entry if key == "shibumiStateSchemaVersion" else entry["shibumi"])[key] = value
                    with self.assertRaises(self.module["ManagerError"]):
                        self.module["state_settings"](config)
        for mutation in ("duplicate", "layout", "missing"):
            config = copy.deepcopy(self.active)
            if mutation == "duplicate":
                config["plugins"].append(copy.deepcopy(config["plugins"][1]))
            elif mutation == "layout":
                config["bar"]["layout"]["left"].append({"id": "hancore.shibumi.state"})
            else:
                config["plugins"][1].pop("shibumi")
            with self.subTest(mutation=mutation), self.assertRaises(self.module["ManagerError"]):
                self.module["state_settings"](config)

    def test_public_paths_refuse_raw_state_document_before_switch_or_status(self) -> None:
        state_dir = self.root / "state"
        state_dir.mkdir()
        runtime_paths = {"state": state_dir, "config": self.root / "shell.json",
                         "defaults": self.root / "defaults.json", "lock": self.root / "switch.lock"}
        (state_dir / "install.json").write_text(json.dumps(self.state))
        runtime_paths["defaults"].write_text(json.dumps(self.defaults))
        globals_map = self.module["perform"].__globals__
        stop, reload_shell, write = Mock(), Mock(), Mock()
        with patch.dict(globals_map, {"paths": lambda: runtime_paths, "stop_shell": stop,
                                    "reload_shell": reload_shell, "atomic_write": write}), \
                patch.object(subprocess, "Popen", side_effect=AssertionError("unexpected switch worker")) as launch:
            for case in ("root-version", "root-bool", "root-string", "root-missing", "bar", "layout",
                         "missing-region", "bad-region", "plugins-limit", "nan", "infinity",
                         "negative-infinity", "parser-limit", "overflow-root", "overflow-entry", "overflow-settings",
                         "integer-overflow-root", "integer-overflow-entry", "integer-overflow-settings"):
                config = copy.deepcopy(self.active)
                if case.startswith("root-"):
                    config["version"] = {"root-version": 2, "root-bool": True, "root-string": "1", "root-missing": None}[case]
                    if case == "root-missing": config.pop("version")
                elif case == "bar": config.pop("bar")
                elif case == "layout": config["bar"]["layout"] = []
                elif case == "missing-region": config["bar"]["layout"].pop("center")
                elif case == "bad-region": config["bar"]["layout"]["center"] = {}
                elif case == "plugins-limit":
                    config["plugins"] += [{"id": f"foreign.{i}"} for i in range(513 - len(config["plugins"]))]
                elif case in ("nan", "infinity", "negative-infinity"):
                    config["foreign"] = float({"nan": "nan", "infinity": "inf", "negative-infinity": "-inf"}[case])
                elif "overflow-" in case:
                    target = config if case.endswith("root") else config["plugins"][1] if case.endswith("entry") else settings(config)
                    target["foreign"] = "__fixture_overflow__"
                else: config["foreign"] = "x" * 1048576
                token = "9" * 400 if case.startswith("integer-") else "1e309"
                raw = json.dumps(config).replace('"__fixture_overflow__"', token).encode()
                runtime_paths["config"].write_bytes(raw)
                for action in ("perform", "show_status", "request"):
                    with self.subTest(case=case, action=action), self.assertRaises(self.module["ManagerError"]):
                        self.module[action](*(["v2"] if action != "show_status" else []))
                    self.assertEqual(runtime_paths["config"].read_bytes(), raw)
                    self.assertEqual(sorted(p.name for p in state_dir.iterdir()), ["install.json"])
            stop.assert_not_called()
            reload_shell.assert_not_called()
            write.assert_not_called()
            launch.assert_not_called()
            config = copy.deepcopy(self.active)
            config["version"] = 1.0
            config["plugins"] += [{"id": f"foreign.{i}"} for i in range(512 - len(config["plugins"]))]
            runtime_paths["config"].write_text(json.dumps(config))
            self.assertEqual(self.module["current_config"](runtime_paths), config)

    def test_variant_round_trip_changes_only_shell_style(self) -> None:
        original = copy.deepcopy(self.active)
        settings(original)["presentation"] = {
            "shellStyle": "shibumi",
            "accent": "color06",
            "radius": "small",
        }
        settings(original)["groups"] = {
            "G4": {
                "displayMode": "text",
                "color": "color05",
                "widgetPadding": "roomy",
            }
        }

        v2 = self.module["apply_shibumi_variant"](original, "v2")
        inactive = self.module["deactivate_config"](
            v2,
            self.defaults,
            self.state,
            self.defaults["bar"]["layout"],
        )
        restored = self.module["activate_config"](
            inactive,
            self.state,
            self.module["copy_layout"](original["bar"]["layout"]),
        )
        v1 = self.module["apply_shibumi_variant"](restored, "v1")

        expected_shibumi = copy.deepcopy(settings(original))
        expected_shibumi["presentation"]["v2ShellStyle"] = "full"
        self.assertEqual(
            settings(v2)["presentation"]["shellStyle"], "full"
        )
        self.assertEqual(
            settings(v1)["presentation"]["shellStyle"], "shibumi"
        )
        self.assertEqual(settings(v1), expected_shibumi)
        self.assertEqual(
            v1["bar"]["layout"], original["bar"]["layout"]
        )

    def test_v2_return_keeps_the_saved_shell_form(self) -> None:
        for shell_style in ("full", "fit", "dock", "notch"):
            with self.subTest(shell_style=shell_style):
                configured = copy.deepcopy(self.active)
                settings(configured)["presentation"] = {
                    "shellStyle": shell_style,
                    "v2ShellStyle": shell_style,
                    "accent": "color06",
                }
                inactive = self.module["deactivate_config"](
                    configured,
                    self.defaults,
                    self.state,
                    self.defaults["bar"]["layout"],
                )
                restored = self.module["activate_config"](
                    inactive,
                    self.state,
                    self.module["copy_layout"](
                        configured["bar"]["layout"]
                    ),
                )
                returned = self.module["apply_shibumi_variant"](
                    restored, "v2"
                )
                self.assertEqual(
                    settings(returned)["presentation"],
                    settings(configured)["presentation"],
                )

    def test_hybrid_service_does_not_need_direct_bar_placement(self) -> None:
        state = copy.deepcopy(self.state)
        state["plugins"].append("hancore.shibumi.update-center")
        state["activation"]["enableServices"].append(
            "hancore.shibumi.update-center"
        )
        config = self.module["activate_config"](self.active, state)
        plugins = {
            plugin_id: {
                "enabled": plugin_id != "hancore.shibumi.update-center",
                "active": plugin_id == "hancore.shibumi.bar",
            }
            for plugin_id in state["plugins"]
        }

        ready, detail = self.module["activation_verification"](
            config, plugins, state
        )

        self.assertTrue(ready, detail)

    def test_activation_requires_every_configured_service(self) -> None:
        config = self.module["activate_config"](self.active, self.state)
        config["plugins"] = []
        plugins = {
            plugin_id: {
                "enabled": True,
                "active": plugin_id == "hancore.shibumi.bar",
            }
            for plugin_id in self.state["plugins"]
        }

        ready, detail = self.module["activation_verification"](
            config, plugins, self.state
        )

        self.assertFalse(ready)
        self.assertIn("hancore.shibumi.state", detail)

    def test_activation_reports_missing_managed_plugin_only_as_managed(self) -> None:
        config = self.module["activate_config"](self.active, self.state)
        plugins = {
            plugin_id: {
                "enabled": True,
                "active": plugin_id == "hancore.shibumi.bar",
            }
            for plugin_id in self.state["plugins"]
            if plugin_id != "hancore.shibumi.widget"
        }

        ready, detail = self.module["activation_verification"](
            config, plugins, self.state
        )

        self.assertFalse(ready)
        self.assertIn("missing=['hancore.shibumi.widget']", detail)
        self.assertIn("missing-from-registry=[]", detail)
        self.assertIn("disabled=[]", detail)

    def test_legacy_shibumi_snapshot_removes_merged_stock_layout(self) -> None:
        snapshot = self.module["snapshot_layout"](
            self.active, "shibumi", self.state, legacy=True
        )
        ids = {
            self.module["entry_id"](entry)
            for region in ("left", "center", "right")
            for entry in snapshot[region]
        }
        self.assertIn("hancore.shibumi.control-center", ids)
        self.assertIn("hancore.shibumi.widget", ids)
        self.assertIn("user.widget", ids)
        self.assertNotIn("omarchy.weather", ids)

    def test_saved_shibumi_profile_rejects_new_stock_contamination(self) -> None:
        config = self.root / "config/omarchy/shell.json"
        defaults = self.root / "omarchy/config/omarchy/shell.json"
        state_dir = self.root / "state/shibumi"
        runtime = self.root / "runtime"
        config.parent.mkdir(parents=True)
        defaults.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)

        trusted_layout = self.module["copy_layout"](
            self.active["bar"]["layout"]
        )
        contaminated = copy.deepcopy(self.active)
        contaminated["bar"]["layout"]["left"].append(
            {"id": "omarchy.menu"}
        )
        contaminated["bar"]["layout"]["center"].append(
            {"id": "omarchy.clock"}
        )
        config.write_text(json.dumps(contaminated) + "\n", encoding="utf-8")
        defaults.write_text(json.dumps(self.defaults) + "\n", encoding="utf-8")
        (state_dir / "install.json").write_text(
            json.dumps(self.state) + "\n", encoding="utf-8"
        )
        profile = state_dir / "shell-layout-profiles.json"
        profile.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "layouts": {
                        "shibumi": trusted_layout,
                        "omarchy": self.defaults["bar"]["layout"],
                    },
                }
            )
            + "\n",
            encoding="utf-8",
        )

        environment = {
            "SHIBUMI_CONFIG_FILE": str(config),
            "SHIBUMI_DEFAULT_CONFIG": str(defaults),
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }
        globals_map = self.module["perform"].__globals__
        original_reload = globals_map["reload_shell"]
        original_stop = globals_map["stop_shell"]
        original_verify = globals_map["verify"]
        globals_map["reload_shell"] = lambda *_args, **_kwargs: None
        globals_map["stop_shell"] = lambda *_args, **_kwargs: None
        globals_map["verify"] = lambda *_args, **_kwargs: None
        try:
            with patch.dict("os.environ", environment, clear=False):
                self.assertEqual(self.module["perform"]("omarchy"), 0)
        finally:
            globals_map["reload_shell"] = original_reload
            globals_map["stop_shell"] = original_stop
            globals_map["verify"] = original_verify

        saved = json.loads(profile.read_text(encoding="utf-8"))
        self.assertEqual(saved["layouts"]["shibumi"], trusted_layout)

    def test_failed_worker_restores_exact_shell_config(self) -> None:
        config = self.root / "config/omarchy/shell.json"
        defaults = self.root / "omarchy/config/omarchy/shell.json"
        state_dir = self.root / "state/shibumi"
        runtime = self.root / "runtime"
        config.parent.mkdir(parents=True)
        defaults.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)
        config.write_text(json.dumps(self.active) + "\n", encoding="utf-8")
        defaults.write_text(json.dumps(self.defaults) + "\n", encoding="utf-8")
        (state_dir / "install.json").write_text(
            json.dumps(self.state) + "\n", encoding="utf-8"
        )
        original = config.read_bytes()
        original_state = (state_dir / "install.json").read_bytes()

        environment = {
            "SHIBUMI_CONFIG_FILE": str(config),
            "SHIBUMI_DEFAULT_CONFIG": str(defaults),
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }
        globals_map = self.module["perform"].__globals__
        original_reload = globals_map["reload_shell"]
        original_stop = globals_map["stop_shell"]
        original_verify = globals_map["verify"]
        globals_map["reload_shell"] = lambda *_args, **_kwargs: None
        globals_map["stop_shell"] = lambda *_args, **_kwargs: None

        def reject(*_args: object, **_kwargs: object) -> None:
            raise self.module["ManagerError"]("injected verification failure")

        globals_map["verify"] = reject
        try:
            with patch.dict("os.environ", environment, clear=False):
                with self.assertRaisesRegex(
                    self.module["ManagerError"], "injected verification failure"
                ):
                    self.module["perform"]("omarchy")
        finally:
            globals_map["reload_shell"] = original_reload
            globals_map["stop_shell"] = original_stop
            globals_map["verify"] = original_verify

        self.assertEqual(config.read_bytes(), original)
        self.assertEqual(
            (state_dir / "install.json").read_bytes(), original_state
        )
        self.assertFalse((state_dir / "switch-transaction").exists())

    def test_failed_switch_rollback_retains_journal_for_later_recovery(self) -> None:
        for boundary in ("config", "state", "reload"):
            with self.subTest(boundary=boundary):
                case_root = self.root / boundary
                config = case_root / "config/omarchy/shell.json"
                defaults = case_root / "omarchy/config/omarchy/shell.json"
                state_dir = case_root / "state/shibumi"
                runtime = case_root / "runtime"
                config.parent.mkdir(parents=True)
                defaults.parent.mkdir(parents=True)
                state_dir.mkdir(parents=True)
                runtime.mkdir(parents=True)
                config.write_text(json.dumps(self.active) + "\n", encoding="utf-8")
                defaults.write_text(
                    json.dumps(self.defaults) + "\n", encoding="utf-8"
                )
                state_path = state_dir / "install.json"
                state_path.write_text(
                    json.dumps(self.state) + "\n", encoding="utf-8"
                )
                original_config = config.read_bytes()
                original_state = state_path.read_bytes()

                environment = {
                    "SHIBUMI_CONFIG_FILE": str(config),
                    "SHIBUMI_DEFAULT_CONFIG": str(defaults),
                    "SHIBUMI_STATE_DIR": str(state_dir),
                    "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
                }
                globals_map = self.module["perform"].__globals__
                original_atomic_write = globals_map["atomic_write"]
                original_reload = globals_map["reload_shell"]
                original_stop = globals_map["stop_shell"]
                original_verify = globals_map["verify"]
                rollback_started = False

                def reject(*_args: object, **_kwargs: object) -> None:
                    nonlocal rollback_started
                    rollback_started = True
                    raise self.module["ManagerError"](
                        "injected verification failure"
                    )

                def faulting_atomic_write(path: Path, payload: bytes) -> None:
                    if rollback_started and (
                        (boundary == "config" and path == config)
                        or (boundary == "state" and path == state_path)
                    ):
                        raise OSError(f"injected {boundary} restore failure")
                    original_atomic_write(path, payload)

                def faulting_reload(*_args: object, **_kwargs: object) -> None:
                    if rollback_started and boundary == "reload":
                        raise self.module["ManagerError"](
                            "injected reload restore failure"
                        )

                globals_map["atomic_write"] = faulting_atomic_write
                globals_map["reload_shell"] = faulting_reload
                globals_map["stop_shell"] = lambda *_args, **_kwargs: None
                globals_map["verify"] = reject
                try:
                    with patch.dict("os.environ", environment, clear=False):
                        with self.assertRaises(Exception):
                            self.module["perform"]("omarchy")
                finally:
                    globals_map["atomic_write"] = original_atomic_write
                    globals_map["reload_shell"] = original_reload
                    globals_map["stop_shell"] = original_stop
                    globals_map["verify"] = original_verify

                transaction = state_dir / "switch-transaction"
                self.assertTrue(transaction.is_dir())
                journal = json.loads(
                    (transaction / "journal.json").read_text(encoding="utf-8")
                )
                self.assertEqual(journal["phase"], "recovery-required")

                globals_map["reload_shell"] = lambda *_args, **_kwargs: None
                globals_map["stop_shell"] = lambda *_args, **_kwargs: None
                try:
                    with patch.dict("os.environ", environment, clear=False):
                        self.assertEqual(self.module["recover"](), 0)
                finally:
                    globals_map["reload_shell"] = original_reload
                    globals_map["stop_shell"] = original_stop

                self.assertFalse(transaction.exists())
                self.assertEqual(config.read_bytes(), original_config)
                self.assertEqual(state_path.read_bytes(), original_state)

    def test_switch_transaction_preparation_is_private_until_complete(self) -> None:
        state_dir = self.root / "state/shibumi"
        config = self.root / "config/omarchy/shell.json"
        state_path = state_dir / "install.json"
        config.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        config.write_text(json.dumps(self.active) + "\n", encoding="utf-8")
        state_path.write_text(json.dumps(self.state) + "\n", encoding="utf-8")
        runtime_paths = {"state": state_dir}
        prepare = self.module["prepare_switch_transaction"]
        globals_map = prepare.__globals__
        original_atomic_write = globals_map["atomic_write"]

        for boundary, fail_after_write in (
            ("directory", 0),
            ("config snapshot", 1),
            ("state snapshot", 2),
            ("journal", 3),
        ):
            with self.subTest(boundary=boundary):
                calls = 0

                def faulting_atomic_write(path: Path, payload: bytes) -> None:
                    nonlocal calls
                    calls += 1
                    if fail_after_write == 0 and calls == 1:
                        raise OSError("injected preparation failure")
                    original_atomic_write(path, payload)
                    if calls == fail_after_write:
                        raise OSError("injected preparation failure")

                globals_map["atomic_write"] = faulting_atomic_write
                try:
                    with self.assertRaisesRegex(
                        OSError, "injected preparation failure"
                    ):
                        prepare(
                            runtime_paths,
                            "omarchy",
                            config,
                            state_path,
                            True,
                        )
                finally:
                    globals_map["atomic_write"] = original_atomic_write

                self.assertFalse((state_dir / "switch-transaction").exists())
                self.assertFalse(
                    (state_dir / ".switch-transaction.preparing").exists()
                )
                self.assertEqual(
                    json.loads(config.read_text(encoding="utf-8")), self.active
                )
                self.assertEqual(
                    json.loads(state_path.read_text(encoding="utf-8")), self.state
                )

        transaction, snapshot, state_snapshot, _journal, journal_path = prepare(
            runtime_paths,
            "omarchy",
            config,
            state_path,
            True,
        )
        self.assertTrue(transaction.is_dir())
        self.assertTrue(snapshot.is_file())
        self.assertTrue(state_snapshot.is_file())
        self.assertTrue(journal_path.is_file())
        self.assertFalse(
            (state_dir / ".switch-transaction.preparing").exists()
        )

    def test_recovery_discards_interrupted_private_switch_directories(self) -> None:
        state_dir = self.root / "state/shibumi"
        runtime = self.root / "runtime"
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)
        environment = {
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }
        globals_map = self.module["recover"].__globals__
        original_reload = globals_map["reload_shell"]
        original_stop = globals_map["stop_shell"]
        stop = Mock()
        reload_shell = Mock()
        globals_map["stop_shell"] = stop
        globals_map["reload_shell"] = reload_shell
        try:
            for private_name in (
                ".switch-transaction.preparing",
                ".switch-transaction.cleanup",
            ):
                for boundary in range(4):
                    with self.subTest(
                        private_name=private_name, boundary=boundary
                    ):
                        private = state_dir / private_name
                        private.mkdir()
                        for name in (
                            "shell.json.before",
                            "install.json.before",
                            "journal.json",
                        )[:boundary]:
                            (private / name).write_text(
                                "partial\n", encoding="utf-8"
                            )
                        with patch.dict("os.environ", environment, clear=False):
                            self.assertEqual(self.module["recover"](), 0)
                        self.assertFalse(private.exists())
        finally:
            globals_map["reload_shell"] = original_reload
            globals_map["stop_shell"] = original_stop
        stop.assert_not_called()
        reload_shell.assert_not_called()

    def test_recovery_refuses_while_lifecycle_lock_is_held(self) -> None:
        state_dir = self.root / "state/shibumi"
        runtime = self.root / "runtime"
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)
        preparation = state_dir / ".switch-transaction.preparing"
        preparation.mkdir()
        marker = preparation / "shell.json.before"
        marker.write_text("do not mutate\n", encoding="utf-8")
        lock_path = runtime / "switch.lock"
        environment = {
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(lock_path),
        }

        with lock_path.open("a+") as held:
            self.module["fcntl"].flock(
                held.fileno(),
                self.module["fcntl"].LOCK_EX
                | self.module["fcntl"].LOCK_NB,
            )
            with patch.dict("os.environ", environment, clear=False):
                with self.assertRaisesRegex(
                    self.module["ManagerError"],
                    "another Shibumi lifecycle operation",
                ):
                    self.module["recover"]()

        self.assertEqual(marker.read_text(encoding="utf-8"), "do not mutate\n")
        with patch.dict("os.environ", environment, clear=False):
            self.assertEqual(self.module["recover"](), 0)
        self.assertFalse(preparation.exists())

    def test_recovery_validates_complete_transaction_before_shell_stop(self) -> None:
        scenarios = (
            "symlink transaction",
            "unknown schema",
            "boolean schema",
            "float schema",
            "invalid target",
            "unhashable target",
            "unhashable phase",
            "invalid config flag",
            "missing config snapshot",
            "missing state snapshot",
            "foreign state snapshot",
            "incomplete state snapshot",
        )
        for scenario in scenarios:
            with self.subTest(scenario=scenario):
                case_root = self.root / scenario.replace(" ", "-")
                state_dir = case_root / "state/shibumi"
                config = case_root / "config/omarchy/shell.json"
                runtime = case_root / "runtime"
                config.parent.mkdir(parents=True)
                state_dir.mkdir(parents=True)
                runtime.mkdir(parents=True)
                config.write_text(
                    json.dumps(self.active) + "\n", encoding="utf-8"
                )
                state_path = state_dir / "install.json"
                state_path.write_text(
                    json.dumps(self.state) + "\n", encoding="utf-8"
                )
                expected_config = config.read_bytes()
                expected_state = state_path.read_bytes()
                transaction = state_dir / "switch-transaction"
                if scenario == "symlink transaction":
                    external = case_root / "external"
                    external.mkdir()
                    transaction.symlink_to(external, target_is_directory=True)
                else:
                    transaction.mkdir()
                    journal = {
                        "schemaVersion": 1,
                        "target": "omarchy",
                        "configExisted": True,
                        "phase": "prepared",
                    }
                    if scenario == "unknown schema":
                        journal["schemaVersion"] = 2
                    elif scenario == "boolean schema":
                        journal["schemaVersion"] = True
                    elif scenario == "float schema":
                        journal["schemaVersion"] = 1.0
                    elif scenario == "invalid target":
                        journal["target"] = "external"
                    elif scenario == "unhashable target":
                        journal["target"] = ["omarchy"]
                    elif scenario == "unhashable phase":
                        journal["phase"] = {"name": "prepared"}
                    elif scenario == "invalid config flag":
                        journal["configExisted"] = "yes"
                    (transaction / "journal.json").write_text(
                        json.dumps(journal) + "\n", encoding="utf-8"
                    )
                    if scenario != "missing config snapshot":
                        (transaction / "shell.json.before").write_bytes(
                            expected_config
                        )
                    if scenario != "missing state snapshot":
                        if scenario == "foreign state snapshot":
                            saved_state = {"suiteId": "foreign"}
                        elif scenario == "incomplete state snapshot":
                            saved_state = {"suiteId": "hancore.shibumi"}
                        else:
                            saved_state = self.state
                        (transaction / "install.json.before").write_text(
                            json.dumps(saved_state) + "\n", encoding="utf-8"
                        )

                environment = {
                    "SHIBUMI_CONFIG_FILE": str(config),
                    "SHIBUMI_STATE_DIR": str(state_dir),
                    "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
                }
                globals_map = self.module["recover"].__globals__
                original_reload = globals_map["reload_shell"]
                original_stop = globals_map["stop_shell"]
                stop = Mock()
                reload_shell = Mock()
                globals_map["stop_shell"] = stop
                globals_map["reload_shell"] = reload_shell
                try:
                    with patch.dict("os.environ", environment, clear=False):
                        with self.assertRaises(self.module["ManagerError"]):
                            self.module["recover"]()
                finally:
                    globals_map["reload_shell"] = original_reload
                    globals_map["stop_shell"] = original_stop

                stop.assert_not_called()
                reload_shell.assert_not_called()
                self.assertEqual(config.read_bytes(), expected_config)
                self.assertEqual(state_path.read_bytes(), expected_state)

    def test_recovery_restores_supported_zero_byte_config(self) -> None:
        state_dir = self.root / "zero-config/state/shibumi"
        config = self.root / "zero-config/config/omarchy/shell.json"
        runtime = self.root / "zero-config/runtime"
        config.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)
        config.write_bytes(b"live config changed\n")
        state_path = state_dir / "install.json"
        state_path.write_text(json.dumps(self.state) + "\n", encoding="utf-8")
        transaction = state_dir / "switch-transaction"
        transaction.mkdir()
        (transaction / "journal.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "target": "omarchy",
                    "configExisted": True,
                    "phase": "prepared",
                }
            )
            + "\n",
            encoding="utf-8",
        )
        (transaction / "shell.json.before").write_bytes(b"")
        (transaction / "install.json.before").write_text(
            json.dumps(self.state) + "\n", encoding="utf-8"
        )
        environment = {
            "SHIBUMI_CONFIG_FILE": str(config),
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }
        globals_map = self.module["recover"].__globals__
        original_reload = globals_map["reload_shell"]
        original_stop = globals_map["stop_shell"]
        original_retire = globals_map["retire_switch_transaction"]
        stop = Mock()
        reload_shell = Mock()
        globals_map["stop_shell"] = stop
        globals_map["reload_shell"] = reload_shell
        globals_map["retire_switch_transaction"] = Mock(
            side_effect=OSError("injected recovery retirement interruption")
        )
        try:
            with patch.dict("os.environ", environment, clear=False):
                with self.assertRaisesRegex(
                    OSError, "injected recovery retirement interruption"
                ):
                    self.module["recover"]()
            self.assertTrue(transaction.is_dir())
            interrupted_status = json.loads(
                (state_dir / "switch-status.json").read_text(encoding="utf-8")
            )
            self.assertEqual(interrupted_status["phase"], "recovered")

            globals_map["retire_switch_transaction"] = original_retire
            with patch.dict("os.environ", environment, clear=False):
                self.assertEqual(self.module["recover"](), 0)
        finally:
            globals_map["retire_switch_transaction"] = original_retire
            globals_map["reload_shell"] = original_reload
            globals_map["stop_shell"] = original_stop

        self.assertEqual(config.read_bytes(), b"")
        self.assertEqual(
            json.loads(state_path.read_text(encoding="utf-8")), self.state
        )
        self.assertFalse(transaction.exists())
        self.assertEqual(stop.call_count, 2)
        self.assertEqual(reload_shell.call_count, 2)

    def test_recovery_restores_prevalidated_snapshot_buffers(self) -> None:
        state_dir = self.root / "snapshot-race/state/shibumi"
        config = self.root / "snapshot-race/config/omarchy/shell.json"
        runtime = self.root / "snapshot-race/runtime"
        config.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)
        config.write_text('{"version":1,"live":"changed"}\n', encoding="utf-8")
        state_path = state_dir / "install.json"
        state_path.write_text(json.dumps(self.state) + "\n", encoding="utf-8")
        transaction = state_dir / "switch-transaction"
        transaction.mkdir()
        snapshot_payload = (json.dumps(self.active) + "\n").encode()
        state_payload = (json.dumps(self.state) + "\n").encode()
        snapshot = transaction / "shell.json.before"
        state_snapshot = transaction / "install.json.before"
        snapshot.write_bytes(snapshot_payload)
        state_snapshot.write_bytes(state_payload)
        (transaction / "journal.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "target": "omarchy",
                    "configExisted": True,
                    "phase": "prepared",
                }
            )
            + "\n",
            encoding="utf-8",
        )
        environment = {
            "SHIBUMI_CONFIG_FILE": str(config),
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }
        globals_map = self.module["recover"].__globals__
        original_reload = globals_map["reload_shell"]
        original_stop = globals_map["stop_shell"]

        def mutate_snapshots_after_validation(*_args: object, **_kwargs: object) -> None:
            snapshot.write_text('{"version":999}\n', encoding="utf-8")
            state_snapshot.write_text(
                '{"suiteId":"foreign"}\n', encoding="utf-8"
            )

        globals_map["stop_shell"] = mutate_snapshots_after_validation
        globals_map["reload_shell"] = lambda *_args, **_kwargs: None
        try:
            with patch.dict("os.environ", environment, clear=False):
                self.assertEqual(self.module["recover"](), 0)
        finally:
            globals_map["reload_shell"] = original_reload
            globals_map["stop_shell"] = original_stop

        self.assertEqual(config.read_bytes(), snapshot_payload)
        self.assertEqual(state_path.read_bytes(), state_payload)
        self.assertFalse(transaction.exists())

    def test_first_omarchy_return_uses_preinstall_layout_with_options(self) -> None:
        config = self.root / "config/omarchy/shell.json"
        defaults = self.root / "omarchy/config/omarchy/shell.json"
        state_dir = self.root / "state/shibumi"
        runtime = self.root / "runtime"
        config.parent.mkdir(parents=True)
        defaults.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)
        config.write_text(json.dumps(self.active) + "\n", encoding="utf-8")
        defaults.write_text(json.dumps(self.defaults) + "\n", encoding="utf-8")
        state = copy.deepcopy(self.state)
        previous_layout = {
            "left": [{"id": "omarchy.menu", "compact": False}],
            "center": [{"id": "user.clock", "timezone": "UTC"}],
            "right": [{"id": "user.stock-widget", "interval": 17}],
        }
        state["previousBar"] = {
            "centerAnchor": "user.clock",
            "layout": previous_layout,
        }
        (state_dir / "install.json").write_text(
            json.dumps(state) + "\n", encoding="utf-8"
        )
        environment = {
            "SHIBUMI_CONFIG_FILE": str(config),
            "SHIBUMI_DEFAULT_CONFIG": str(defaults),
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }
        globals_map = self.module["perform"].__globals__
        original_reload = globals_map["reload_shell"]
        original_stop = globals_map["stop_shell"]
        original_verify = globals_map["verify"]
        globals_map["reload_shell"] = lambda *_args, **_kwargs: None
        globals_map["stop_shell"] = lambda *_args, **_kwargs: None
        globals_map["verify"] = lambda *_args, **_kwargs: None
        try:
            with patch.dict("os.environ", environment, clear=False):
                self.assertEqual(self.module["perform"]("omarchy"), 0)
        finally:
            globals_map["reload_shell"] = original_reload
            globals_map["stop_shell"] = original_stop
            globals_map["verify"] = original_verify

        profiles = json.loads(
            (state_dir / "shell-layout-profiles.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(profiles["layouts"]["omarchy"], previous_layout)
        self.assertEqual(profiles["centerAnchors"]["omarchy"], "user.clock")
        switched = json.loads(config.read_text(encoding="utf-8"))
        self.assertEqual(switched["bar"]["centerAnchor"], "user.clock")
        self.assertEqual(switched["bar"]["layout"]["left"], previous_layout["left"])
        self.assertEqual(
            switched["bar"]["layout"]["center"], previous_layout["center"]
        )
        self.assertEqual(
            switched["bar"]["layout"]["right"][:-1], previous_layout["right"]
        )
        self.assertEqual(
            switched["bar"]["layout"]["right"][-1],
            {"id": "hancore.shibumi.control-center"},
        )

    def test_absent_omarchy_center_anchor_overwrites_stale_profile(self) -> None:
        config = self.root / "anchorless/config/omarchy/shell.json"
        defaults = self.root / "anchorless/omarchy/config/omarchy/shell.json"
        state_dir = self.root / "anchorless/state/shibumi"
        runtime = self.root / "anchorless/runtime"
        config.parent.mkdir(parents=True)
        defaults.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)
        stock = copy.deepcopy(self.defaults)
        stock["plugins"] = copy.deepcopy(self.active["plugins"])
        stock["bar"].pop("centerAnchor", None)
        config.write_text(json.dumps(stock) + "\n", encoding="utf-8")
        defaults.write_text(json.dumps(self.defaults) + "\n", encoding="utf-8")
        state = copy.deepcopy(self.state)
        state["previousBar"] = {"layout": stock["bar"]["layout"]}
        (state_dir / "install.json").write_text(
            json.dumps(state) + "\n", encoding="utf-8"
        )
        profile = state_dir / "shell-layout-profiles.json"
        profile.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "layouts": {"omarchy": stock["bar"]["layout"]},
                    "centerAnchors": {"omarchy": "stale.clock"},
                }
            )
            + "\n",
            encoding="utf-8",
        )
        self.assertEqual(
            self.module["initial_center_anchor"](
                "omarchy", self.defaults, state
            ),
            "",
        )
        environment = {
            "SHIBUMI_CONFIG_FILE": str(config),
            "SHIBUMI_DEFAULT_CONFIG": str(defaults),
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }
        globals_map = self.module["perform"].__globals__
        original_reload = globals_map["reload_shell"]
        original_stop = globals_map["stop_shell"]
        original_verify = globals_map["verify"]
        globals_map["reload_shell"] = lambda *_args, **_kwargs: None
        globals_map["stop_shell"] = lambda *_args, **_kwargs: None
        globals_map["verify"] = lambda *_args, **_kwargs: None
        try:
            with patch.dict("os.environ", environment, clear=False):
                self.assertEqual(self.module["perform"]("shibumi"), 0)
                self.assertEqual(self.module["perform"]("omarchy"), 0)
        finally:
            globals_map["reload_shell"] = original_reload
            globals_map["stop_shell"] = original_stop
            globals_map["verify"] = original_verify

        switched = json.loads(config.read_text(encoding="utf-8"))
        profiles = json.loads(profile.read_text(encoding="utf-8"))
        self.assertNotIn("centerAnchor", switched["bar"])
        self.assertEqual(profiles["centerAnchors"]["omarchy"], "")

    def test_terminal_switch_status_precedes_transaction_retirement(self) -> None:
        config = self.root / "terminal/config/omarchy/shell.json"
        defaults = self.root / "terminal/omarchy/config/omarchy/shell.json"
        state_dir = self.root / "terminal/state/shibumi"
        runtime = self.root / "terminal/runtime"
        config.parent.mkdir(parents=True)
        defaults.parent.mkdir(parents=True)
        state_dir.mkdir(parents=True)
        runtime.mkdir(parents=True)
        config.write_text(json.dumps(self.active) + "\n", encoding="utf-8")
        defaults.write_text(json.dumps(self.defaults) + "\n", encoding="utf-8")
        (state_dir / "install.json").write_text(
            json.dumps(self.state) + "\n", encoding="utf-8"
        )
        environment = {
            "SHIBUMI_CONFIG_FILE": str(config),
            "SHIBUMI_DEFAULT_CONFIG": str(defaults),
            "SHIBUMI_STATE_DIR": str(state_dir),
            "SHIBUMI_LOCK_FILE": str(runtime / "switch.lock"),
        }
        globals_map = self.module["perform"].__globals__
        original_reload = globals_map["reload_shell"]
        original_stop = globals_map["stop_shell"]
        original_verify = globals_map["verify"]
        original_retire = globals_map["retire_switch_transaction"]
        stop = Mock()
        reload_shell = Mock()
        globals_map["stop_shell"] = stop
        globals_map["reload_shell"] = reload_shell
        globals_map["verify"] = lambda *_args, **_kwargs: None
        globals_map["retire_switch_transaction"] = Mock(
            side_effect=OSError("injected retirement interruption")
        )
        try:
            with patch.dict("os.environ", environment, clear=False):
                with self.assertRaisesRegex(
                    OSError, "injected retirement interruption"
                ):
                    self.module["perform"]("omarchy")
            transaction = state_dir / "switch-transaction"
            journal = json.loads(
                (transaction / "journal.json").read_text(encoding="utf-8")
            )
            status = json.loads(
                (state_dir / "switch-status.json").read_text(encoding="utf-8")
            )
            self.assertEqual(journal["phase"], "committed")
            self.assertEqual(status["phase"], "complete")

            stop.reset_mock()
            reload_shell.reset_mock()
            globals_map["retire_switch_transaction"] = original_retire
            with patch.dict("os.environ", environment, clear=False):
                self.assertEqual(self.module["recover"](), 0)
            stop.assert_not_called()
            reload_shell.assert_not_called()
            self.assertFalse(transaction.exists())
            recovered_status = json.loads(
                (state_dir / "switch-status.json").read_text(encoding="utf-8")
            )
            self.assertEqual(recovered_status["phase"], "complete")
        finally:
            globals_map["retire_switch_transaction"] = original_retire
            globals_map["reload_shell"] = original_reload
            globals_map["stop_shell"] = original_stop
            globals_map["verify"] = original_verify

    def test_request_rejects_overlapping_switch_without_spawning(self) -> None:
        state_dir = self.root / "state/shibumi"
        state_dir.mkdir(parents=True)
        (state_dir / "install.json").write_text(
            json.dumps(self.state) + "\n", encoding="utf-8"
        )
        (state_dir / "switch-status.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "target": "omarchy",
                    "phase": "verify",
                    "detail": "",
                    "updatedEpoch": int(time.time()),
                }
            )
            + "\n",
            encoding="utf-8",
        )
        config = self.root / "request-shell.json"
        config.write_text(json.dumps(self.active))
        environment = {"SHIBUMI_STATE_DIR": str(state_dir), "SHIBUMI_CONFIG_FILE": str(config)}
        globals_map = self.module["request"].__globals__
        with patch.dict("os.environ", environment, clear=False):
            with patch.object(globals_map["subprocess"], "Popen") as popen:
                with self.assertRaisesRegex(
                    self.module["ManagerError"], "another Shibumi lifecycle"
                ):
                    self.module["request"]("v1")
        popen.assert_not_called()

    def test_reload_uses_full_shell_restart_when_available(self) -> None:
        restart = self.root / "omarchy/bin/omarchy-restart-shell"
        restart.parent.mkdir(parents=True)
        restart.touch()
        runtime_paths = {
            "restart_shell": restart,
            "shell": self.root / "omarchy/bin/omarchy-shell",
        }
        completed = Mock(returncode=0, stdout="", stderr="")
        globals_map = self.module["reload_shell"].__globals__
        with patch.object(
            globals_map["subprocess"], "run", return_value=completed
        ) as run:
            self.module["reload_shell"](runtime_paths, timeout=12)
        run.assert_called_once_with(
            [str(restart)],
            check=False,
            capture_output=True,
            text=True,
            timeout=12,
            env=self.module["runtime_environment"](runtime_paths),
        )

    def test_stop_drains_shell_instances_before_config_handoff(self) -> None:
        omarchy_root = self.root / "omarchy"
        runtime_paths = {
            "omarchy_root": omarchy_root,
            "shell": omarchy_root / "bin/omarchy-shell",
        }
        registered = Mock(
            returncode=0,
            stdout=json.dumps([
                {
                    "id": "target-1",
                    "config_path": str(omarchy_root / "shell/shell.qml"),
                    "pid": 41001,
                }
            ]),
            stderr="",
        )
        not_prepared = Mock(
            returncode=1, stdout="", stderr="target unavailable"
        )
        killed = Mock(returncode=0, stdout="", stderr="")
        drained = Mock(returncode=0, stdout="[]", stderr="")
        globals_map = self.module["stop_shell"].__globals__
        with patch.object(
            globals_map["subprocess"],
            "run",
            side_effect=[registered, not_prepared, killed, drained],
        ) as run:
            self.module["stop_shell"](runtime_paths, quiet_period=0)
        kill = ["quickshell", "kill", "--pid", "41001"]
        registry = ["quickshell", "list", "--all", "--json"]
        prepare = [
            "quickshell",
            "ipc",
            "--pid",
            "41001",
            "call",
            "shibumi-suite",
            "prepareShutdown",
        ]
        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [registry, prepare, kill, registry],
        )

    def test_empty_quickshell_registry_sentinel_is_an_empty_array(self) -> None:
        runtime_paths = {"omarchy_root": self.root / "omarchy"}
        completed = Mock(
            returncode=0,
            stdout=QUICKSHELL_EMPTY_REGISTRY,
            stderr="",
        )
        globals_map = self.module["matching_shell_instances"].__globals__
        with patch.object(
            globals_map["subprocess"], "run", return_value=completed
        ):
            instances = self.module["matching_shell_instances"](runtime_paths)
        self.assertEqual(instances, [])

    def test_empty_registry_sentinel_with_nonzero_exit_fails_closed(self) -> None:
        runtime_paths = {"omarchy_root": self.root / "omarchy"}
        completed = Mock(
            returncode=23,
            stdout=QUICKSHELL_EMPTY_REGISTRY,
            stderr="registry unavailable",
        )
        globals_map = self.module["matching_shell_instances"].__globals__
        with patch.object(
            globals_map["subprocess"], "run", return_value=completed
        ):
            with self.assertRaisesRegex(
                self.module["ManagerError"], "registry unavailable"
            ):
                self.module["matching_shell_instances"](runtime_paths)

    def test_empty_registry_sentinel_timeout_fails_closed(self) -> None:
        runtime_paths = {"omarchy_root": self.root / "omarchy"}
        command = ["quickshell", "list", "--all", "--json"]
        timeout = subprocess.TimeoutExpired(
            command,
            0.01,
            output=QUICKSHELL_EMPTY_REGISTRY,
        )
        globals_map = self.module["matching_shell_instances"].__globals__
        with patch.object(
            globals_map["subprocess"], "run", side_effect=timeout
        ):
            with self.assertRaisesRegex(
                self.module["ManagerError"], "cannot inspect Quickshell registry"
            ):
                self.module["matching_shell_instances"](runtime_paths, timeout=0.01)

    def test_quickshell_registry_json_arrays_remain_supported(self) -> None:
        omarchy_root = self.root / "omarchy"
        runtime_paths = {"omarchy_root": omarchy_root}
        matching = {
            "id": "target-1",
            "config_path": str(omarchy_root / "shell/shell.qml"),
            "pid": 41001,
        }
        globals_map = self.module["matching_shell_instances"].__globals__
        for stdout, expected in (
            ("[]", []),
            (json.dumps([matching]), [matching]),
        ):
            with self.subTest(stdout=stdout):
                completed = Mock(returncode=0, stdout=stdout, stderr="")
                with patch.object(
                    globals_map["subprocess"], "run", return_value=completed
                ):
                    self.assertEqual(
                        self.module["matching_shell_instances"](runtime_paths),
                        expected,
                    )

    def test_empty_registry_sentinel_variants_fail_closed(self) -> None:
        runtime_paths = {"omarchy_root": self.root / "omarchy"}
        globals_map = self.module["matching_shell_instances"].__globals__
        for stdout in INVALID_EMPTY_REGISTRY_OUTPUTS:
            with self.subTest(stdout=stdout):
                completed = Mock(returncode=0, stdout=stdout, stderr="")
                with patch.object(
                    globals_map["subprocess"], "run", return_value=completed
                ):
                    with self.assertRaisesRegex(
                        self.module["ManagerError"],
                        "malformed JSON|not an array",
                    ):
                        self.module["matching_shell_instances"](runtime_paths)

    def test_reload_falls_back_for_older_omarchy(self) -> None:
        runtime_paths = {
            "restart_shell": self.root / "missing-restart",
            "shell": self.root / "omarchy/bin/omarchy-shell",
        }
        runtime_paths["shell"].parent.mkdir(parents=True)
        runtime_paths["shell"].touch()
        completed = Mock(returncode=0, stdout="ok\n", stderr="")
        globals_map = self.module["reload_shell"].__globals__
        with patch.object(
            globals_map["subprocess"], "run", return_value=completed
        ) as run:
            self.module["reload_shell"](runtime_paths, timeout=1)
        run.assert_called_once_with(
            [str(runtime_paths["shell"]), "shell", "reloadConfig"],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
            env=self.module["runtime_environment"](runtime_paths),
        )

    def test_omarchy_root_prefers_current_system_install(self) -> None:
        system_root = self.root / "usr/share/omarchy"
        user_root = self.root / "home/.local/share/omarchy"
        for root in (system_root, user_root):
            defaults = root / "config/omarchy/shell.json"
            defaults.parent.mkdir(parents=True)
            defaults.write_text("{}\n", encoding="utf-8")
        with patch.dict("os.environ", {}, clear=True):
            self.assertEqual(
                self.module["discover_omarchy_root"](
                    self.root / "home", system_root
                ),
                system_root,
            )

    def test_omarchy_root_honors_explicit_override(self) -> None:
        override = self.root / "override"
        defaults = override / "config/omarchy/shell.json"
        defaults.parent.mkdir(parents=True)
        defaults.write_text("{}\n", encoding="utf-8")
        with patch.dict(
            "os.environ", {"OMARCHY_PATH": str(override)}, clear=True
        ):
            self.assertEqual(
                self.module["discover_omarchy_root"](
                    self.root / "home", self.root / "system"
                ),
                override,
            )


if __name__ == "__main__":
    unittest.main()
