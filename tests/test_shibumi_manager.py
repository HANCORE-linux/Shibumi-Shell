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
                "shibumi": {
                    "scale": 1.25,
                    "picker": {
                        "style": "hearthstone",
                        "imageStyle": "hearthstone",
                        "mediaStyle": "hearthstone",
                    },
                },
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
                {"id": "hancore.shibumi.state"},
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
        self.assertEqual(inactive["bar"]["shibumi"]["scale"], 1.25)
        self.assertEqual(
            inactive["bar"]["shibumi"]["picker"],
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
        self.assertEqual(active["bar"]["shibumi"]["scale"], 1.25)
        self.assertEqual(
            active["bar"]["shibumi"]["picker"]["imageStyle"], "hearthstone"
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

    def test_variant_round_trip_changes_only_shell_style(self) -> None:
        original = copy.deepcopy(self.active)
        original["bar"]["shibumi"]["presentation"] = {
            "shellStyle": "shibumi",
            "accent": "color06",
            "radius": "small",
        }
        original["bar"]["shibumi"]["groups"] = {
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

        expected_shibumi = copy.deepcopy(original["bar"]["shibumi"])
        expected_shibumi["presentation"]["v2ShellStyle"] = "full"
        self.assertEqual(
            v2["bar"]["shibumi"]["presentation"]["shellStyle"], "full"
        )
        self.assertEqual(
            v1["bar"]["shibumi"]["presentation"]["shellStyle"], "shibumi"
        )
        self.assertEqual(v1["bar"]["shibumi"], expected_shibumi)
        self.assertEqual(
            v1["bar"]["layout"], original["bar"]["layout"]
        )

    def test_v2_return_keeps_the_saved_shell_form(self) -> None:
        for shell_style in ("full", "fit", "dock", "notch"):
            with self.subTest(shell_style=shell_style):
                configured = copy.deepcopy(self.active)
                configured["bar"]["shibumi"]["presentation"] = {
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
                    returned["bar"]["shibumi"]["presentation"],
                    configured["bar"]["shibumi"]["presentation"],
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
        environment = {"SHIBUMI_STATE_DIR": str(state_dir)}
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
        killed = Mock(returncode=0, stdout="", stderr="")
        drained = Mock(returncode=0, stdout="[]", stderr="")
        globals_map = self.module["stop_shell"].__globals__
        with patch.object(
            globals_map["subprocess"],
            "run",
            side_effect=[registered, killed, drained],
        ) as run:
            self.module["stop_shell"](runtime_paths, quiet_period=0)
        kill = [
            "quickshell",
            "kill",
            "-p",
            str(omarchy_root / "shell"),
            "--any-display",
        ]
        registry = ["quickshell", "list", "--all", "--json"]
        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [registry, kill, registry],
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
