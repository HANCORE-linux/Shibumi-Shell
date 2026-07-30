#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import runpy
import tempfile
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
                "shibumi": {"scale": 1.25},
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
        self.assertEqual(inactive["bar"]["shibumi"], {"scale": 1.25})
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
        self.assertEqual(active["bar"]["shibumi"], {"scale": 1.25})
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
        original_verify = globals_map["verify"]
        globals_map["reload_shell"] = lambda *_args, **_kwargs: None

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
            globals_map["verify"] = original_verify

        self.assertEqual(config.read_bytes(), original)
        self.assertEqual(
            (state_dir / "install.json").read_bytes(), original_state
        )
        self.assertFalse((state_dir / "switch-transaction").exists())

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
