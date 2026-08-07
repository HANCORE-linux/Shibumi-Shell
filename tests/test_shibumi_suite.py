#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import io
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from shibumi_suite.cli import (  # noqa: E402
    CliError,
    command_activate,
    command_deactivate,
    command_install,
    command_migrate,
    command_repair,
    command_status,
    command_uninstall,
    command_update,
    load_install_state,
    version_key,
)
from shibumi_suite.config import (  # noqa: E402
    ConfigError,
    apply_identity_contract,
    apply_profile,
    atomic_write,
    encode_config,
    entry_id,
)
from shibumi_suite.model import (  # noqa: E402
    ContractError,
    Suite,
    plugin_payload_digest,
    suite_payload_digest,
)
from shibumi_suite.menu_extension import (  # noqa: E402
    END_MARKER,
    START_MARKER,
    install_picker_routing,
    remove_picker_routing,
)
from shibumi_suite.runtime import OmarchyRuntime, RuntimeFailure, RuntimePaths  # noqa: E402
import shibumi_suite.transaction as transaction_module  # noqa: E402
from shibumi_suite.transaction import (  # noqa: E402
    PluginTransaction,
    TransactionError,
    recover_transactions,
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


class FakeOmarchyRuntime(OmarchyRuntime):
    def __init__(self, paths: RuntimePaths) -> None:
        super().__init__()
        self.paths = paths
        self.fail_rescan_count = 0
        self.fail_rescan_calls: set[int] = set()
        self.fail_validation_plugin = ""
        self.rescans = 0
        self.reloads = 0
        self.restarts = 0
        self.fail_restart_count = 0
        self.stops = 0
        self.payload_reloads = 0
        self.fail_payload_reload = False
        self.fail_deactivation_verify = False
        self.menu_refreshes = 0
        self.shell_running = True
        self.restart_failure_stops_shell = False
        self.events: list[str] = []

    def validate_plugin(self, directory: Path) -> None:
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        if manifest.get("id") == self.fail_validation_plugin:
            raise RuntimeFailure("injected plugin validation failure")
        if manifest.get("id") != directory.name and not directory.name.endswith(
            "." + str(manifest.get("id"))
        ):
            raise RuntimeFailure(f"invalid staged plugin {directory}")

    def rescan(self) -> None:
        self.events.append("rescan")
        self.rescans += 1
        if self.rescans in self.fail_rescan_calls:
            raise RuntimeFailure("injected rescan failure")
        if self.fail_rescan_count:
            self.fail_rescan_count -= 1
            raise RuntimeFailure("injected rescan failure")

    def reload_config(self) -> None:
        self.events.append("reload-config")
        self.reloads += 1

    def restart_shell(self) -> None:
        self.events.append("restart")
        self.restarts += 1
        if self.fail_restart_count:
            self.fail_restart_count -= 1
            if self.restart_failure_stops_shell:
                self.shell_running = False
            raise RuntimeFailure("injected shell restart failure")
        self.shell_running = True

    def stop_shell(self) -> None:
        self.events.append("stop")
        self.stops += 1
        self.shell_running = False

    def reload_payload(self) -> None:
        self.events.append("reload-payload")
        self.payload_reloads += 1
        if self.fail_payload_reload:
            raise RuntimeFailure("injected payload reload failure")

    def refresh_menu(self) -> None:
        self.menu_refreshes += 1

    def ping(self) -> None:
        if not self.shell_running:
            raise RuntimeFailure("injected shell is not running")

    def verify_single_shell_instance(self) -> None:
        if not self.shell_running:
            raise RuntimeFailure("injected shell is not running")

    def verify_bar_layer_ownership(self, expected_namespace: str) -> None:
        return

    def payload_ready(self, payload_digest: str) -> bool:
        target = self.paths.plugin_dir / "hancore.shibumi.state"
        try:
            marker = json.loads(
                (target / ".shibumi-managed.json").read_text(encoding="utf-8")
            )
        except (OSError, json.JSONDecodeError):
            return False
        return marker.get("suitePayloadDigest") == payload_digest

    def verify_deactivation(
        self,
        plugin_ids: set[str],
        shibumi_bar: str,
        *,
        allowed_enabled: set[str] | None = None,
        timeout: float = 20,
    ) -> None:
        if self.fail_deactivation_verify:
            raise RuntimeFailure("injected deactivation verification failure")
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        bar = config.get("bar") if isinstance(config.get("bar"), dict) else {}
        layout = bar.get("layout") if isinstance(bar.get("layout"), dict) else {}
        enabled = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in layout.get(region, [])
        }
        enabled.update(entry_id(entry) for entry in config.get("plugins", []))
        if str(bar.get("id") or "omarchy.bar") != "omarchy.bar":
            raise RuntimeFailure("stock bar is not active")
        if (enabled & plugin_ids) - (allowed_enabled or set()):
            raise RuntimeFailure("Shibumi plugins remain enabled")

    def list_plugins(self) -> dict[str, dict[str, object]]:
        config_path = (
            self.paths.config_file
            if self.paths.config_file.is_file()
            else self.paths.defaults_file
        )
        config = json.loads(config_path.read_text(encoding="utf-8"))
        bar = config.get("bar") if isinstance(config.get("bar"), dict) else {}
        layout = bar.get("layout") if isinstance(bar.get("layout"), dict) else {}
        layout_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in layout.get(region, [])
        }
        service_ids = {entry_id(entry) for entry in config.get("plugins", [])}
        active_bar = str(bar.get("id") or "omarchy.bar")

        result: dict[str, dict[str, object]] = {}
        if not self.paths.plugin_dir.is_dir():
            return result
        for directory in self.paths.plugin_dir.iterdir():
            if not directory.is_dir() or directory.name.startswith("."):
                continue
            manifest_path = directory / "manifest.json"
            if not manifest_path.is_file():
                continue
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            plugin_id = str(manifest["id"])
            kinds = list(manifest.get("kinds") or [])
            is_bar = "bar" in kinds
            is_bar_widget = "bar-widget" in kinds
            enabled = (
                active_bar == plugin_id
                if is_bar
                else plugin_id in layout_ids
                if is_bar_widget
                else plugin_id in service_ids
            )
            result[plugin_id] = {
                "id": plugin_id,
                "kinds": kinds,
                "enabled": enabled,
                "active": is_bar and active_bar == plugin_id,
            }
        return result


class RuntimeProcessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="shibumi-runtime-test.")
        self.omarchy_root = Path(self.temporary.name) / "omarchy"
        bin_dir = self.omarchy_root / "bin"
        bin_dir.mkdir(parents=True)
        (bin_dir / "omarchy-restart-shell").write_text(
            "#!/bin/sh\n", encoding="utf-8"
        )
        self.runtime = OmarchyRuntime(self.omarchy_root)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def result(
        stdout: str = "", returncode: int = 0, stderr: str = ""
    ) -> SimpleNamespace:
        return SimpleNamespace(returncode=returncode, stdout=stdout, stderr=stderr)

    def instance_json(self, *paths: Path) -> str:
        return json.dumps([
            {"config_path": str(path), "pid": index + 100}
            for index, path in enumerate(paths)
        ])

    def test_restart_waits_for_instance_without_redundant_ping(self) -> None:
        config = self.omarchy_root / "shell/shell.qml"
        self.runtime.run = Mock(side_effect=[
            self.result(),
            self.result(self.instance_json(config)),
        ])

        self.runtime.restart_shell(timeout=1)

        calls = [call.args[0] for call in self.runtime.run.call_args_list]
        self.assertEqual(calls[0], [str(
            self.omarchy_root / "bin/omarchy-restart-shell"
        )])
        self.assertEqual(
            calls[1],
            ["quickshell", "list", "--all", "--json"],
        )
        self.assertNotIn([str(
            self.omarchy_root / "bin/omarchy-shell"
        ), "shell", "ping"], calls)

    def test_instance_guard_ignores_foreign_config_but_rejects_duplicates(self) -> None:
        config = self.omarchy_root / "shell/shell.qml"
        foreign = Path(self.temporary.name) / "foreign/shell.qml"
        self.runtime.run = Mock(return_value=self.result(
            self.instance_json(config, foreign)
        ))
        self.runtime.verify_single_shell_instance()

        self.runtime.run = Mock(return_value=self.result(
            self.instance_json(config, config, foreign)
        ))
        with self.assertRaisesRegex(RuntimeFailure, "found 2"):
            self.runtime.verify_single_shell_instance()

    def test_stop_drains_matching_instances_without_killing_foreign_config(
        self,
    ) -> None:
        config = self.omarchy_root / "shell/shell.qml"
        foreign = Path(self.temporary.name) / "foreign/shell.qml"
        self.runtime.run = Mock(side_effect=[
            self.result(self.instance_json(config, foreign)),
            self.result(),
            self.result(self.instance_json(foreign)),
        ])

        self.runtime.stop_shell(quiet_period=0)

        commands = [call.args[0] for call in self.runtime.run.call_args_list]
        kill = [
            "quickshell",
            "kill",
            "-p",
            str(self.omarchy_root / "shell"),
            "--any-display",
        ]
        registry = ["quickshell", "list", "--all", "--json"]
        self.assertEqual(commands, [registry, kill, registry])

    def test_empty_quickshell_registry_sentinel_is_an_empty_array(self) -> None:
        self.runtime.run = Mock(return_value=self.result(
            QUICKSHELL_EMPTY_REGISTRY
        ))
        self.assertEqual(self.runtime.quickshell_instances(), [])

    def test_empty_registry_sentinel_with_nonzero_exit_fails_closed(self) -> None:
        command = ["quickshell", "list", "--all", "--json"]
        completed = subprocess.CompletedProcess(
            command,
            23,
            stdout=QUICKSHELL_EMPTY_REGISTRY,
            stderr="registry unavailable",
        )
        globals_map = OmarchyRuntime.run.__globals__
        with patch.object(
            globals_map["subprocess"], "run", return_value=completed
        ):
            with self.assertRaisesRegex(RuntimeFailure, r"failed \(23\)"):
                self.runtime.quickshell_instances()

    def test_empty_registry_sentinel_timeout_fails_closed(self) -> None:
        command = ["quickshell", "list", "--all", "--json"]
        timeout = subprocess.TimeoutExpired(
            command,
            0.01,
            output=QUICKSHELL_EMPTY_REGISTRY,
        )
        globals_map = OmarchyRuntime.run.__globals__
        with patch.object(
            globals_map["subprocess"], "run", side_effect=timeout
        ):
            with self.assertRaisesRegex(RuntimeFailure, "cannot run quickshell list"):
                self.runtime.quickshell_instances(timeout=0.01)

    def test_quickshell_registry_json_arrays_remain_supported(self) -> None:
        instance = {"config_path": "/tmp/shell.qml", "pid": 4242}
        for stdout, expected in (
            ("[]", []),
            (json.dumps([instance]), [instance]),
        ):
            with self.subTest(stdout=stdout):
                self.runtime.run = Mock(return_value=self.result(stdout))
                self.assertEqual(self.runtime.quickshell_instances(), expected)

    def test_empty_registry_sentinel_variants_fail_closed(self) -> None:
        for stdout in INVALID_EMPTY_REGISTRY_OUTPUTS:
            with self.subTest(stdout=stdout):
                self.runtime.run = Mock(return_value=self.result(stdout))
                with self.assertRaisesRegex(
                    RuntimeFailure,
                    "malformed instance JSON|not an array",
                ):
                    self.runtime.quickshell_instances()

    def test_layer_guard_rejects_stock_and_shibumi_bars_together(self) -> None:
        layers = {
            "DP-1": {
                "levels": {
                    "2": [
                        {"namespace": "shibumi-bar", "pid": 100},
                        {"namespace": "omarchy-bar", "pid": 200},
                    ]
                }
            }
        }
        self.runtime.run = Mock(return_value=self.result(json.dumps(layers)))

        with self.assertRaisesRegex(RuntimeFailure, "conflicting"):
            self.runtime.verify_bar_layer_ownership("shibumi-bar")

    def test_layer_guard_accepts_only_the_expected_bar(self) -> None:
        layers = {
            "DP-1": {
                "levels": {
                    "2": [{"namespace": "shibumi-bar", "pid": 100}]
                }
            }
        }
        config = self.omarchy_root / "shell/shell.qml"
        self.runtime.run = Mock(side_effect=[
            self.result(json.dumps(layers)),
            self.result(self.instance_json(config)),
        ])

        self.runtime.verify_bar_layer_ownership("shibumi-bar")

    def test_layer_guard_rejects_managed_bar_owned_by_foreign_config(self) -> None:
        layers = {
            "DP-1": {
                "levels": {
                    "2": [{"namespace": "shibumi-bar", "pid": 200}]
                }
            }
        }
        config = self.omarchy_root / "shell/shell.qml"
        foreign = Path(self.temporary.name) / "foreign/shell.qml"
        instances = json.dumps([
            {"config_path": str(config), "pid": 100},
            {"config_path": str(foreign), "pid": 200},
        ])
        self.runtime.run = Mock(side_effect=[
            self.result(json.dumps(layers)),
            self.result(instances),
        ])

        with self.assertRaisesRegex(RuntimeFailure, "foreign Quickshell"):
            self.runtime.verify_bar_layer_ownership("shibumi-bar")


class SuiteLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="shibumi-suite-test.")
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        (self.source / "contracts").mkdir(parents=True)
        shutil.copy2(
            REPO_ROOT / "contracts/plugin-suite-v1.json",
            self.source / "contracts/plugin-suite-v1.json",
        )
        contract = json.loads(
            (self.source / "contracts/plugin-suite-v1.json").read_text(encoding="utf-8")
        )
        for plugin_id in (item["id"] for item in contract["plugins"]):
            shutil.copytree(REPO_ROOT / plugin_id, self.source / plugin_id)

        self.defaults = self.root / "omarchy/config/omarchy/shell.json"
        self.defaults.parent.mkdir(parents=True)
        self.defaults.write_text(
            json.dumps(
                {
                    "version": 1,
                    "bar": {
                        "position": "top",
                        "centerAnchor": "omarchy.clock",
                        "layout": {
                            "left": [{"id": "omarchy.menu"}],
                            "center": [{"id": "omarchy.clock"}],
                            "right": [{"id": "local.extra", "custom": 7}],
                        },
                    },
                    "plugins": [{"id": "local.service"}],
                    "customRoot": {"preserve": True},
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        self.paths = RuntimePaths(
            omarchy_root=self.root / "omarchy",
            plugin_dir=self.root / "config/omarchy/plugins",
            config_file=self.root / "config/omarchy/shell.json",
            defaults_file=self.defaults,
            state_dir=self.root / "state/shibumi",
            cache_dir=self.root / "cache/shibumi",
            lock_file=self.root / "runtime/shibumi.lock",
        )
        self.suite = Suite.load(self.source)
        self.runtime = FakeOmarchyRuntime(self.paths)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def args(**values: object) -> SimpleNamespace:
        defaults = {
            "profile": "default",
            "dry_run": False,
            "yes": True,
            "keep_settings": False,
            "no_activate": False,
            "keep_layout": False,
        }
        defaults.update(values)
        return SimpleNamespace(**defaults)

    def install(self) -> None:
        self.assertEqual(
            command_install(self.args(), self.suite, self.paths, self.runtime), 0
        )

    def test_lifecycle_never_mutates_hyprland_appearance_config(self) -> None:
        hypr_root = self.root / "config/hypr"
        hypr_root.mkdir(parents=True)
        looknfeel_lua = hypr_root / "looknfeel.lua"
        looknfeel_conf = hypr_root / "looknfeel.conf"
        looknfeel_lua.write_text(
            "hl.config({ general = { gaps_in = 3, gaps_out = 7, "
            "border_size = 2 } })\n",
            encoding="utf-8",
        )
        looknfeel_conf.write_text(
            "general { gaps_in = 3; gaps_out = 7; border_size = 2 }\n",
            encoding="utf-8",
        )
        expected = {
            path.name: (path.read_bytes(), path.stat().st_mtime_ns)
            for path in (looknfeel_lua, looknfeel_conf)
        }

        def assert_appearance_unchanged(operation: str) -> None:
            self.assertEqual(
                sorted(path.name for path in hypr_root.iterdir()),
                sorted(expected),
                f"{operation} changed the Hyprland file set",
            )
            for name, (content, mtime_ns) in expected.items():
                path = hypr_root / name
                self.assertEqual(
                    path.read_bytes(), content,
                    f"{operation} rewrote {name}",
                )
                self.assertEqual(
                    path.stat().st_mtime_ns, mtime_ns,
                    f"{operation} touched {name}",
                )

        self.install()
        assert_appearance_unchanged("install")
        command_update(self.args(), self.suite, self.paths, self.runtime)
        assert_appearance_unchanged("update")
        command_deactivate(self.args(), self.suite, self.paths, self.runtime)
        assert_appearance_unchanged("deactivate")
        command_activate(self.args(), self.suite, self.paths, self.runtime)
        assert_appearance_unchanged("activate")
        command_uninstall(self.args(), self.suite, self.paths, self.runtime)
        assert_appearance_unchanged("uninstall")

    def inject_retired_app_menu(self) -> None:
        """Recreate the managed 0.1.0 menu state an upgrade must retire."""
        plugin_id = "hancore.shibumi.menu"
        target = self.paths.plugin_dir / plugin_id
        target.mkdir()
        (target / "manifest.json").write_text(
            json.dumps({
                "schemaVersion": 1,
                "id": plugin_id,
                "name": "Shibumi App Menu",
                "kinds": ["menu", "service"],
                "entryPoints": {
                    "menu": "Menu.qml",
                    "service": "AppMenuService.qml",
                },
            }) + "\n",
            encoding="utf-8",
        )
        (target / "Menu.qml").write_text("import QtQuick\nItem {}\n", encoding="utf-8")
        (target / "AppMenuService.qml").write_text(
            "import QtQuick\nQtObject {}\n", encoding="utf-8"
        )
        digest = plugin_payload_digest(target)
        state_path = self.paths.state_dir / "install.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["plugins"].append(plugin_id)
        state["pluginDigests"][plugin_id] = digest
        state["payloadDigest"] = suite_payload_digest(state["pluginDigests"])
        atomic_write(state_path, (json.dumps(state, indent=2) + "\n").encode())
        atomic_write(
            target / ".shibumi-managed.json",
            (json.dumps({
                "schemaVersion": 1,
                "suiteId": "hancore.shibumi",
                "pluginId": plugin_id,
            }, indent=2) + "\n").encode(),
        )
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["plugins"].append({"id": plugin_id, "custom": "old"})
        atomic_write(self.paths.config_file, encode_config(config))

    def packaged_suite(self) -> Suite:
        shutil.copy2(
            REPO_ROOT / "packaging/package-metadata.json",
            self.source / "PACKAGE-METADATA.json",
        )
        return Suite.load(self.source)

    def create_quattro_host_contract(self) -> None:
        bin_dir = self.paths.omarchy_root / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        for command in ("omarchy", "omarchy-shell", "omarchy-plugin-validate"):
            (bin_dir / command).write_text("#!/bin/sh\n", encoding="utf-8")
        sources = {
            "shell/services/PluginRegistry.qml": (
                "function entryPointUrl() {}\nfunction isEnabled() {}\n"
            ),
            "shell/shell.qml": (
                "function configureBar() {}\n"
                "target.pluginRegistry = shell.pluginRegistry\n"
            ),
            "shell/Ui/KeyboardPanel.qml": (
                "property var borderSpec: null\nBorderSurface {}\n"
            ),
        }
        for relative, content in sources.items():
            path = self.paths.omarchy_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")

    def prepare_legacy_install(self) -> dict[str, object]:
        self.paths.plugin_dir.mkdir(parents=True, exist_ok=True)
        old_ids: list[str] = []
        for new_id, spec in self.suite.plugins.items():
            old_id = new_id.replace("hancore.shibumi", "hancore.qsrise", 1)
            old_ids.append(old_id)
            target = self.paths.plugin_dir / old_id
            shutil.copytree(spec.source, target)
            manifest_path = target / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["id"] = old_id
            manifest_path.write_text(
                json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
            )
            marker = {
                "schemaVersion": 1,
                "suiteId": "hancore.qsrise",
                "suiteVersion": "0.1.0",
                "pluginId": old_id,
                "sourceRevision": "legacy-test",
                "payloadDigest": "0" * 64,
                "suitePayloadDigest": "1" * 64,
            }
            (target / ".qsrise-managed.json").write_text(
                json.dumps(marker, indent=2) + "\n", encoding="utf-8"
            )

        legacy_state = {
            "schemaVersion": 1,
            "suiteId": "hancore.qsrise",
            "suiteVersion": "0.1.0",
            "profile": "default",
            "activeBar": "hancore.qsrise.bar",
            "plugins": old_ids,
            "sourceRevision": "legacy-test",
            "payloadDigest": "1" * 64,
            "pluginDigests": {plugin_id: "0" * 64 for plugin_id in old_ids},
        }
        legacy_state_dir = self.paths.state_dir.parent / "qsrise"
        legacy_state_dir.mkdir(parents=True)
        (legacy_state_dir / "install.json").write_text(
            json.dumps(legacy_state, indent=2) + "\n", encoding="utf-8"
        )
        legacy_cache = self.paths.cache_dir.parent / "qsrise" / "update-center"
        legacy_cache.mkdir(parents=True)
        (legacy_cache / "themes.json").write_text("{}\n", encoding="utf-8")

        config = json.loads(self.defaults.read_text(encoding="utf-8"))
        profile = self.suite.profile("default")
        legacy_layout: dict[str, list[dict[str, object]]] = {}
        for region in ("left", "center", "right"):
            legacy_layout[region] = [
                {
                    "id": plugin_id.replace(
                        "hancore.shibumi", "hancore.qsrise", 1
                    )
                }
                for plugin_id in profile.layout[region]
            ]
        legacy_layout["left"].reverse()
        legacy_layout["left"].insert(1, {"id": "local.extra", "custom": 7})
        config["bar"].update(
            {
                "id": "hancore.qsrise.bar",
                "centerAnchor": "hancore.qsrise.center",
                "style": "qsrise",
                "qsrise": {
                    "iconSize": 17,
                    "menu": {
                        "version": 1,
                        "launcher": {
                            "mode": "text",
                            "text": "omarchy",
                            "icon": "omarchy",
                        },
                    },
                    "hancore.qsrise.ai": {
                        "provider": "local",
                        "owner": "hancore.qsrise.ai",
                    },
                    "nested": ["hancore.qsrise.update-center", {"keep": True}],
                },
                "layout": legacy_layout,
            }
        )
        config["plugins"] = [
            {
                "id": plugin_id.replace("hancore.shibumi", "hancore.qsrise", 1),
                **(
                    {"custom": 9}
                    if plugin_id == "hancore.shibumi.state"
                    else {}
                ),
            }
            for plugin_id in profile.enable_services
        ]
        config["plugins"].insert(1, {"id": "local.service"})
        config["customRoot"] = {"preserve": True}
        atomic_write(self.paths.config_file, encode_config(config))
        return legacy_state

    def hidden_transaction_paths(self) -> list[Path]:
        if not self.paths.plugin_dir.is_dir():
            return []
        return sorted(self.paths.plugin_dir.glob(".shibumi-*"))

    def test_menu_extension_merge_is_idempotent_and_reversible(self) -> None:
        original = (
            "{\n"
            "  // user extension remains byte-identical\n"
            '  "style.theme-hooks": {"label":"Theme Hooks"}\n'
            "}\n"
        )
        installed = install_picker_routing(original)
        self.assertIn(START_MARKER, installed)
        self.assertIn(END_MARKER, installed)
        self.assertIn("shibumi-picker-route", installed)
        self.assertIn('"aliases":["theme","themes"]', installed)
        self.assertIn('"aliases":["background","wallpaper"]', installed)
        # Quattro accepts full-line comments and trailing commas, but not
        # inline comments. Parse the generated result with the same contract.
        quattro_json = re.sub(
            r",(\s*[}\]])",
            r"\1",
            re.sub(r"^\s*//[^\n]*(?:\n|$)", "", installed, flags=re.MULTILINE),
        )
        self.assertIsInstance(json.loads(quattro_json), dict)
        self.assertEqual(install_picker_routing(installed), installed)
        self.assertEqual(remove_picker_routing(installed), original)

    def test_menu_extension_supports_items_wrapper(self) -> None:
        original = (
            "{\n"
            '  "version": 1,\n'
            '  "items": {\n'
            '    "personal": {"label":"Personal"}\n'
            "  }\n"
            "}\n"
        )
        installed = install_picker_routing(original)
        self.assertIn('"style.background"', installed)
        self.assertEqual(remove_picker_routing(installed), original)

    def test_menu_refresh_retries_quattro_not_ready_response(self) -> None:
        runtime = OmarchyRuntime()
        runtime.run = Mock(side_effect=[
            SimpleNamespace(
                returncode=0,
                stdout="Not ready to accept queries yet.\n",
                stderr="",
            ),
            SimpleNamespace(returncode=0, stdout="ok\n", stderr=""),
        ])
        with patch("shibumi_suite.runtime.time.sleep"):
            runtime.refresh_menu(timeout=1)
        self.assertEqual(runtime.run.call_count, 2)

    def test_runtime_paths_accept_the_shibumi_quattro_contract(self) -> None:
        self.create_quattro_host_contract()

        self.paths.validate()

    def test_runtime_paths_reject_an_incompatible_quattro_host(self) -> None:
        self.create_quattro_host_contract()
        (self.paths.omarchy_root / "shell/shell.qml").write_text(
            "target.pluginRegistry = shell.pluginRegistry\n",
            encoding="utf-8",
        )

        with self.assertRaisesRegex(
            RuntimeFailure,
            "supports Omarchy Quattro only: incompatible host contract",
        ):
            self.paths.validate()

    def test_package_install_records_authoritative_package_origin(self) -> None:
        suite = self.packaged_suite()

        self.assertEqual(
            command_install(self.args(), suite, self.paths, self.runtime),
            0,
        )

        state = load_install_state(self.paths, suite)
        self.assertEqual(state["installOrigin"], "package")
        self.assertEqual(state["packageName"], "shibumi-shell")
        self.assertEqual(state["packageVersion"], "0.1.1-beta.6")
        self.assertEqual(state["sourceRevision"], "package:0.1.1-beta.6")
        self.assertNotIn("sourceRoot", state)
        self.assertEqual(state["payloadRoot"], str(self.source.resolve()))

    def test_update_migrates_checkout_install_to_package_origin(self) -> None:
        self.install()
        checkout_state = load_install_state(self.paths, self.suite)
        self.assertEqual(checkout_state["installOrigin"], "checkout")
        self.assertIn("sourceRoot", checkout_state)
        suite = self.packaged_suite()

        self.assertEqual(
            command_update(self.args(), suite, self.paths, self.runtime),
            0,
        )

        package_state = load_install_state(self.paths, suite)
        self.assertEqual(package_state["installOrigin"], "package")
        self.assertEqual(package_state["packageName"], "shibumi-shell")
        self.assertEqual(package_state["packageVersion"], "0.1.1-beta.6")
        self.assertNotIn("sourceRoot", package_state)

    def test_update_transactionally_retires_app_menu(self) -> None:
        self.install()
        self.inject_retired_app_menu()

        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )

        plugin_id = "hancore.shibumi.menu"
        self.assertFalse((self.paths.plugin_dir / plugin_id).exists())
        state = load_install_state(self.paths, self.suite)
        self.assertNotIn(plugin_id, state["plugins"])
        self.assertNotIn(plugin_id, state["pluginDigests"])
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertNotIn(
            plugin_id, {entry_id(entry) for entry in config["plugins"]}
        )
        archived = list(
            (self.paths.state_dir / "backups").glob(f"*/{plugin_id}")
        )
        self.assertEqual(len(archived), 1)

    def test_failed_update_restores_retired_app_menu_and_state(self) -> None:
        self.install()
        self.inject_retired_app_menu()
        plugin_id = "hancore.shibumi.menu"
        state_before = (self.paths.state_dir / "install.json").read_bytes()
        config_before = self.paths.config_file.read_bytes()
        self.runtime.fail_rescan_calls.add(self.runtime.rescans + 1)

        with self.assertRaisesRegex(RuntimeFailure, "injected rescan failure"):
            command_update(self.args(), self.suite, self.paths, self.runtime)

        self.assertTrue((self.paths.plugin_dir / plugin_id).is_dir())
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(), state_before
        )
        self.assertEqual(self.paths.config_file.read_bytes(), config_before)

    def test_update_and_repair_accept_semver_build_metadata(self) -> None:
        self.install()
        state_path = self.paths.state_dir / "install.json"
        for operation in (command_update, command_repair):
            with self.subTest(operation=operation.__name__):
                state = json.loads(state_path.read_text(encoding="utf-8"))
                state["suiteVersion"] = "0.1.1-beta.6+installed.7"
                state_path.write_text(
                    json.dumps(state, indent=2) + "\n", encoding="utf-8"
                )
                self.assertEqual(
                    operation(self.args(), self.suite, self.paths, self.runtime),
                    0,
                )
                updated = json.loads(state_path.read_text(encoding="utf-8"))
                self.assertEqual(updated["suiteVersion"], "0.1.1-beta.6")

        self.assertEqual(
            version_key("1.0.0+build.7"),
            version_key("1.0.0+build.8"),
        )
        self.assertLess(
            version_key("1.0.0-rc.1+build.9"),
            version_key("1.0.0"),
        )
        for invalid in (
            "1.2",
            "01.2.3",
            "1.2.3-alpha..1",
            "1.2.3-01",
            "1.2.3+",
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(CliError, "unsupported Shibumi version"):
                    version_key(invalid)

    def test_update_refuses_package_downgrade_without_mutation(self) -> None:
        suite = self.packaged_suite()
        self.assertEqual(
            command_install(self.args(), suite, self.paths, self.runtime),
            0,
        )
        state_path = self.paths.state_dir / "install.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["suiteVersion"] = "0.1.1"
        state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
        state_before = state_path.read_bytes()
        config_before = self.paths.config_file.read_bytes()

        with self.assertRaisesRegex(CliError, "refusing downgrade"):
            command_update(self.args(), suite, self.paths, self.runtime)

        self.assertEqual(state_path.read_bytes(), state_before)
        self.assertEqual(self.paths.config_file.read_bytes(), config_before)

    def test_explicit_package_rollback_stages_older_payload_transactionally(self) -> None:
        suite = self.packaged_suite()
        self.assertEqual(
            command_install(self.args(), suite, self.paths, self.runtime),
            0,
        )
        state_path = self.paths.state_dir / "install.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["suiteVersion"] = "0.1.1"
        state["packageVersion"] = "0.1.1"
        state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

        self.assertEqual(
            command_update(
                self.args(allow_downgrade=True),
                suite,
                self.paths,
                self.runtime,
            ),
            0,
        )

        rolled_back = load_install_state(self.paths, suite)
        self.assertEqual(rolled_back["suiteVersion"], "0.1.1-beta.6")
        self.assertEqual(rolled_back["packageVersion"], "0.1.1-beta.6")
        self.assertEqual(rolled_back["sourceRevision"], "package:0.1.1-beta.6")

    def test_rescan_uses_shell_ipc_contract(self) -> None:
        runtime = OmarchyRuntime()
        runtime.run = Mock()

        runtime.rescan()

        runtime.run.assert_called_once_with(
            ["omarchy-shell", "shell", "rescanPlugins"]
        )

    def test_install_and_uninstall_manage_picker_routes(self) -> None:
        self.install()
        extension = self.paths.menu_extension_file
        self.assertIn(START_MARKER, extension.read_text(encoding="utf-8"))
        state = load_install_state(self.paths, self.suite)
        self.assertTrue(state["menuExtension"]["createdFile"])
        self.assertEqual(command_update(
            self.args(), self.suite, self.paths, self.runtime
        ), 0)
        self.assertEqual(
            extension.read_text(encoding="utf-8").count(START_MARKER), 1
        )
        restarts_before = self.runtime.restarts
        self.assertEqual(command_uninstall(
            self.args(), self.suite, self.paths, self.runtime
        ), 0)
        self.assertEqual(self.runtime.restarts, restarts_before + 1)
        self.assertFalse(extension.exists())

    def test_uninstall_uses_full_restart_instead_of_hot_reload(self) -> None:
        self.install()
        reloads_before = self.runtime.reloads
        restarts_before = self.runtime.restarts

        self.assertEqual(
            command_uninstall(self.args(), self.suite, self.paths, self.runtime), 0
        )

        self.assertEqual(self.runtime.reloads, reloads_before)
        self.assertEqual(self.runtime.restarts, restarts_before + 1)

    def test_bar_host_transitions_restart_instead_of_hot_reload(self) -> None:
        reloads_before = self.runtime.reloads
        restarts_before = self.runtime.restarts
        stops_before = self.runtime.stops

        self.install()
        self.assertEqual(self.runtime.reloads, reloads_before)
        self.assertEqual(self.runtime.restarts, restarts_before + 1)
        self.assertEqual(self.runtime.stops, stops_before + 1)

        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        self.assertEqual(self.runtime.reloads, reloads_before)
        self.assertEqual(self.runtime.restarts, restarts_before + 2)
        self.assertEqual(self.runtime.stops, stops_before + 2)

        self.assertEqual(
            command_activate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        self.assertEqual(self.runtime.reloads, reloads_before)
        self.assertEqual(self.runtime.restarts, restarts_before + 3)
        self.assertEqual(self.runtime.stops, stops_before + 3)

    def test_activate_after_deactivate_keeps_host_layouts_separate(self) -> None:
        self.install()
        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        inactive = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        inactive_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in inactive["bar"]["layout"][region]
        }
        self.assertIn("omarchy.menu", inactive_ids)

        self.assertEqual(
            command_activate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        active = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        active_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in active["bar"]["layout"][region]
        }
        self.assertIn("local.extra", active_ids)
        self.assertFalse(
            any(plugin_id.startswith("omarchy.") for plugin_id in active_ids)
        )

    def test_uninstall_preserves_existing_menu_extension(self) -> None:
        extension = self.paths.menu_extension_file
        extension.parent.mkdir(parents=True)
        original = (
            "{\n"
            "  // thpm-menu-start\n"
            '  "style.theme-hooks": {"label":"Theme Hooks"},\n'
            "  // thpm-menu-end\n"
            "}\n"
        )
        extension.write_text(original, encoding="utf-8")
        self.install()
        state = load_install_state(self.paths, self.suite)
        self.assertFalse(state["menuExtension"]["createdFile"])
        self.assertEqual(command_uninstall(
            self.args(), self.suite, self.paths, self.runtime
        ), 0)
        self.assertEqual(extension.read_text(encoding="utf-8"), original)

    def test_profile_keeps_visually_disabled_plugins_registry_enabled(self) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["position"] = "left"
        profile = self.suite.profile("default")
        result = apply_profile(base, profile, self.suite.plugins)
        layout_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in result["bar"]["layout"][region]
        }
        self.assertTrue(set(profile.disabled_by_default).issubset(layout_ids))
        self.assertEqual(result["bar"]["position"], "top")
        self.assertIn("local.extra", layout_ids)

    def test_profile_excludes_stock_widgets_and_keeps_third_party_extras(self) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        profile = self.suite.profile("default")
        result = apply_profile(base, profile, self.suite.plugins)
        layout_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in result["bar"]["layout"][region]
        }

        self.assertIn("local.extra", layout_ids)
        self.assertFalse(
            any(plugin_id.startswith("omarchy.") for plugin_id in layout_ids)
        )

    def test_migrate_preserves_settings_and_retires_legacy_namespace(self) -> None:
        legacy_state = self.prepare_legacy_install()
        legacy_config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        expected_left = [
            entry_id(entry).replace("hancore.qsrise", "hancore.shibumi", 1)
            for entry in legacy_config["bar"]["layout"]["left"]
        ]

        self.assertEqual(
            command_migrate(self.args(), self.suite, self.paths, self.runtime), 0
        )

        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(config["bar"]["id"], "hancore.shibumi.bar")
        self.assertEqual(config["bar"]["centerAnchor"], "hancore.shibumi.center")
        self.assertEqual(config["bar"]["style"], "shibumi")
        self.assertNotIn("qsrise", config["bar"])
        settings = config["bar"]["shibumi"]
        self.assertEqual(settings["iconSize"], 17)
        self.assertEqual(settings["identityVersion"], 3)
        self.assertEqual(settings["launcher"]["text"], "shibumi")
        self.assertNotIn("menu", settings)
        self.assertEqual(
            settings["hancore.shibumi.ai"]["owner"], "hancore.shibumi.ai"
        )
        self.assertEqual(settings["nested"][0], "hancore.shibumi.update-center")
        self.assertTrue(config["customRoot"]["preserve"])
        layout_entries = {
            entry_id(entry): entry
            for region in ("left", "center", "right")
            for entry in config["bar"]["layout"][region]
        }
        self.assertEqual(layout_entries["local.extra"]["custom"], 7)
        self.assertEqual(
            [entry_id(entry) for entry in config["bar"]["layout"]["left"]],
            expected_left,
        )
        service_entries = {entry_id(entry): entry for entry in config["plugins"]}
        self.assertEqual(service_entries["hancore.shibumi.state"]["custom"], 9)
        self.assertIn("local.service", service_entries)

        new_state = load_install_state(self.paths, self.suite)
        self.assertEqual(new_state["migratedFrom"]["suiteId"], "hancore.qsrise")
        self.assertEqual(
            new_state["migratedFrom"]["sourceRevision"],
            legacy_state["sourceRevision"],
        )
        for new_id in self.suite.plugins:
            old_id = new_id.replace("hancore.shibumi", "hancore.qsrise", 1)
            self.assertTrue((self.paths.plugin_dir / new_id).is_dir())
            self.assertFalse((self.paths.plugin_dir / old_id).exists())
        self.assertFalse((self.paths.state_dir.parent / "qsrise").exists())
        self.assertFalse((self.paths.cache_dir.parent / "qsrise").exists())
        archived_legacy = list(
            (self.paths.state_dir / "backups").glob("*/hancore.qsrise.bar")
        )
        self.assertEqual(len(archived_legacy), 1)
        self.assertFalse(self.hidden_transaction_paths())

    def test_identity_contract_migrates_once_and_preserves_later_choice(self) -> None:
        config = json.loads(self.defaults.read_text(encoding="utf-8"))
        config["bar"]["shibumi"] = {
            "version": 1,
            "menu": {
                "version": 1,
                "launcher": {
                    "mode": "text",
                    "text": "omarchy",
                    "icon": "omarchy",
                },
            },
        }
        migrated = apply_identity_contract(config)
        settings = migrated["bar"]["shibumi"]
        self.assertEqual(settings["identityVersion"], 3)
        self.assertEqual(settings["launcher"]["text"], "shibumi")
        self.assertNotIn("menu", settings)

        settings["launcher"]["text"] = "omarchy"
        preserved = apply_identity_contract(migrated)
        self.assertEqual(
            preserved["bar"]["shibumi"]["launcher"]["text"],
            "omarchy",
        )

    def test_failed_migration_restores_legacy_payload_config_and_state(self) -> None:
        self.prepare_legacy_install()
        original_config = self.paths.config_file.read_bytes()
        self.runtime.fail_rescan_calls = {2}

        with self.assertRaises(RuntimeFailure):
            command_migrate(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        for new_id in self.suite.plugins:
            old_id = new_id.replace("hancore.shibumi", "hancore.qsrise", 1)
            self.assertFalse((self.paths.plugin_dir / new_id).exists())
            self.assertTrue((self.paths.plugin_dir / old_id).is_dir())
        self.assertTrue(
            (self.paths.state_dir.parent / "qsrise" / "install.json").is_file()
        )
        self.assertFalse((self.paths.state_dir / "install.json").exists())
        self.assertFalse(self.hidden_transaction_paths())

    def test_migration_refuses_ambiguous_settings_without_mutation(self) -> None:
        self.prepare_legacy_install()
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["bar"]["shibumi"] = {"already": "present"}
        atomic_write(self.paths.config_file, encode_config(config))
        original_config = self.paths.config_file.read_bytes()

        with self.assertRaises(ConfigError):
            command_migrate(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        self.assertFalse((self.paths.state_dir / "install.json").exists())
        self.assertFalse(self.hidden_transaction_paths())

    def test_migration_dry_run_is_a_strict_noop(self) -> None:
        self.prepare_legacy_install()
        original_config = self.paths.config_file.read_bytes()
        original_plugins = sorted(path.name for path in self.paths.plugin_dir.iterdir())

        self.assertEqual(
            command_migrate(
                self.args(dry_run=True), self.suite, self.paths, self.runtime
            ),
            0,
        )

        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        self.assertEqual(
            sorted(path.name for path in self.paths.plugin_dir.iterdir()),
            original_plugins,
        )
        self.assertTrue(
            (self.paths.state_dir.parent / "qsrise" / "install.json").is_file()
        )
        self.assertFalse((self.paths.state_dir / "install.json").exists())

    def test_install_update_and_uninstall_are_batch_transactional(self) -> None:
        self.install()
        update_cache = self.paths.cache_dir / "update-center/themes.json"
        update_cache.parent.mkdir(parents=True)
        update_cache.write_text("{}\n", encoding="utf-8")
        state = load_install_state(self.paths, self.suite)
        self.assertEqual(len(state["plugins"]), len(self.suite.plugins))
        defaults = json.loads(self.defaults.read_text(encoding="utf-8"))
        self.assertEqual(state["previousBar"], defaults["bar"])
        self.assertEqual(len(state["payloadDigest"]), 64)
        self.assertEqual(
            state["payloadDigest"], suite_payload_digest(state["pluginDigests"])
        )
        for plugin_id in state["plugins"]:
            target = self.paths.plugin_dir / plugin_id
            marker = json.loads(
                (target / ".shibumi-managed.json").read_text(encoding="utf-8")
            )
            self.assertEqual(
                marker["payloadDigest"],
                self.suite.plugins[plugin_id].payload_digest(target),
            )
            self.assertEqual(marker["suitePayloadDigest"], state["payloadDigest"])
        runtime_plugins = self.runtime.list_plugins()
        self.assertEqual(len(runtime_plugins), len(self.suite.plugins))
        self.assertFalse(
            runtime_plugins["hancore.shibumi.update-center"]["enabled"]
        )
        self.assertTrue(
            all(
                item["enabled"]
                for plugin_id, item in runtime_plugins.items()
                if plugin_id != "hancore.shibumi.update-center"
            )
        )
        self.assertFalse(self.hidden_transaction_paths())

        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(config["bar"]["id"], "hancore.shibumi.bar")
        config["customAfterInstall"] = "keep"
        atomic_write(self.paths.config_file, encode_config(config))

        plugin_id = "hancore.shibumi.control-center"
        target_file = self.paths.plugin_dir / plugin_id / "BarWidget.qml"
        source_file = self.source / plugin_id / "BarWidget.qml"
        target_file.write_text(
            target_file.read_text(encoding="utf-8") + "\n// local installed edit\n",
            encoding="utf-8",
        )
        source_file.write_text(
            source_file.read_text(encoding="utf-8") + "\n// next source revision\n",
            encoding="utf-8",
        )
        self.suite = Suite.load(self.source)
        reloads_before = self.runtime.reloads
        payload_reloads_before = self.runtime.payload_reloads
        restarts_before = self.runtime.restarts
        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )
        self.assertEqual(self.runtime.reloads, reloads_before)
        self.assertEqual(self.runtime.payload_reloads, payload_reloads_before)
        self.assertEqual(self.runtime.restarts, restarts_before + 1)
        self.assertIn("next source revision", target_file.read_text(encoding="utf-8"))
        updated_config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(updated_config["customAfterInstall"], "keep")
        backups = list(
            (self.paths.state_dir / "backups").glob(
                f"*/{plugin_id}/BarWidget.qml"
            )
        )
        self.assertEqual(len(backups), 1)
        self.assertIn("local installed edit", backups[0].read_text(encoding="utf-8"))

        self.assertEqual(
            command_uninstall(self.args(), self.suite, self.paths, self.runtime), 0
        )
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.cache_dir.exists())
        self.assertFalse(any((self.paths.plugin_dir / plugin_id).exists() for plugin_id in state["plugins"]))
        self.assertFalse(self.hidden_transaction_paths())
        final_config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(final_config["bar"], defaults["bar"])
        final_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in final_config["bar"]["layout"][region]
        }
        self.assertIn("local.extra", final_ids)
        self.assertEqual(final_config["customAfterInstall"], "keep")

    def test_update_backfills_stock_bar_for_older_install_state(self) -> None:
        self.install()
        state_path = self.paths.state_dir / "install.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state.pop("previousBar")
        atomic_write(
            state_path,
            (json.dumps(state, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        )

        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        for region in ("left", "center", "right"):
            config["bar"]["layout"][region] = [
                entry
                for entry in config["bar"]["layout"][region]
                if entry_id(entry).startswith("hancore.shibumi.")
            ]
        atomic_write(self.paths.config_file, encode_config(config))

        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )
        defaults = json.loads(self.defaults.read_text(encoding="utf-8"))
        updated = load_install_state(self.paths, self.suite)
        self.assertEqual(updated["previousBar"], defaults["bar"])

        self.assertEqual(
            command_uninstall(self.args(), self.suite, self.paths, self.runtime), 0
        )
        restored = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        self.assertEqual(restored["bar"], defaults["bar"])

    def test_failed_first_external_install_skips_absent_payload_provider(self) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["id"] = "third.party.bar"
        atomic_write(self.paths.config_file, encode_config(base))
        original_config = self.paths.config_file.read_bytes()
        reloads_before = self.runtime.payload_reloads
        with patch.object(
            self.runtime,
            "verify_update",
            side_effect=RuntimeFailure("injected first external verification failure"),
        ):
            with self.assertRaisesRegex(
                RuntimeFailure, "injected first external verification failure"
            ):
                command_install(
                    self.args(no_activate=True, keep_layout=True),
                    self.suite,
                    self.paths,
                    self.runtime,
                )

        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        self.assertEqual(self.runtime.payload_reloads, reloads_before)
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(
            (self.paths.plugin_dir / "hancore.shibumi.state").exists()
        )
        self.assertFalse(self.hidden_transaction_paths())

    def test_external_drift_rollback_skips_disabled_payload_provider(self) -> None:
        external_args = self.args(no_activate=True, keep_layout=True)
        self.assertEqual(
            command_install(external_args, self.suite, self.paths, self.runtime), 0
        )
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["plugins"] = [
            entry for entry in config.get("plugins", [])
            if entry_id(entry) != "hancore.shibumi.state"
        ]
        atomic_write(self.paths.config_file, encode_config(config))
        original_config = self.paths.config_file.read_bytes()
        reloads_before = self.runtime.payload_reloads

        with patch.object(
            self.runtime,
            "verify_update",
            side_effect=RuntimeFailure("injected external drift verification failure"),
        ):
            with self.assertRaisesRegex(
                RuntimeFailure, "injected external drift verification failure"
            ):
                command_repair(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        # The attempted external repair performs one payload reload while the
        # provider is enabled; rollback must not issue a second call after the
        # restored drift configuration unloads it.
        self.assertEqual(self.runtime.payload_reloads, reloads_before + 1)
        self.assertTrue(
            (self.paths.plugin_dir / "hancore.shibumi.state").is_dir()
        )
        self.assertFalse(self.hidden_transaction_paths())

    def test_external_install_update_repair_and_activate_preserve_host_layout(
        self,
    ) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["id"] = "third.party.bar"
        base["bar"]["position"] = "bottom"
        base["bar"]["layout"]["right"].append(
            {
                "id": "hancore.shibumi.bluetooth",
                "settings": {"displayMode": "icon"},
            }
        )
        atomic_write(self.paths.config_file, encode_config(base))
        expected_bar = copy.deepcopy(base["bar"])

        external_args = self.args(no_activate=True, keep_layout=True)
        self.assertEqual(
            command_install(
                external_args, self.suite, self.paths, self.runtime
            ),
            0,
        )

        installed = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        self.assertEqual(installed["bar"], expected_bar)
        profile = self.suite.profile("default")
        self.assertTrue(
            set(profile.enable_services)
            <= {entry_id(entry) for entry in installed["plugins"]}
        )
        state = load_install_state(self.paths, self.suite)
        self.assertEqual(state["activation"]["mode"], "external")
        self.assertEqual(state["activation"]["layoutPolicy"], "preserved")
        self.assertEqual(
            state["activation"]["configuredBar"], "third.party.bar"
        )
        self.assertEqual(command_status(self.suite, self.paths), 0)

        installed["bar"]["layout"]["left"].append(
            {"id": "hancore.shibumi.audio", "custom": 9}
        )
        installed["bar"]["customHostSetting"] = {"preserve": True}
        atomic_write(self.paths.config_file, encode_config(installed))
        expected_bar = copy.deepcopy(installed["bar"])
        reloads_before = self.runtime.reloads
        payload_reloads_before = self.runtime.payload_reloads
        restarts_before = self.runtime.restarts
        self.assertEqual(
            command_update(
                self.args(), self.suite, self.paths, self.runtime
            ),
            0,
        )
        self.assertEqual(self.runtime.reloads, reloads_before + 1)
        self.assertEqual(
            self.runtime.payload_reloads, payload_reloads_before + 1
        )
        self.assertEqual(self.runtime.restarts, restarts_before)
        updated = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        self.assertEqual(updated["bar"], expected_bar)

        shutil.rmtree(
            self.paths.plugin_dir / "hancore.shibumi.bluetooth"
        )
        self.assertEqual(
            command_repair(
                self.args(), self.suite, self.paths, self.runtime
            ),
            0,
        )
        repaired = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        self.assertEqual(repaired["bar"], expected_bar)
        self.assertTrue(
            (
                self.paths.plugin_dir / "hancore.shibumi.bluetooth"
            ).is_dir()
        )

        self.assertEqual(
            command_activate(
                self.args(), self.suite, self.paths, self.runtime
            ),
            0,
        )
        active = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        self.assertEqual(active["bar"]["id"], "hancore.shibumi.bar")
        active_state = load_install_state(self.paths, self.suite)
        self.assertEqual(active_state["activation"]["mode"], "managed")
        self.assertEqual(
            active_state["activation"]["layoutPolicy"], "managed"
        )

    def test_external_install_flags_must_be_used_together(self) -> None:
        with self.assertRaisesRegex(CliError, "must be used together"):
            command_install(
                self.args(no_activate=True),
                self.suite,
                self.paths,
                self.runtime,
            )
        with self.assertRaisesRegex(CliError, "must be used together"):
            command_install(
                self.args(keep_layout=True),
                self.suite,
                self.paths,
                self.runtime,
            )
        self.assertFalse((self.paths.state_dir / "install.json").exists())

    def test_update_adopts_markerless_owned_alpha_install(self) -> None:
        self.install()
        state = load_install_state(self.paths, self.suite)
        for plugin_id in state["plugins"]:
            (self.paths.plugin_dir / plugin_id / ".shibumi-managed.json").unlink()

        source_file = (
            self.source / "hancore.shibumi.control-center" / "BarWidget.qml"
        )
        source_file.write_text(
            source_file.read_text(encoding="utf-8")
            + "\n// markerless alpha adoption\n",
            encoding="utf-8",
        )
        self.suite = Suite.load(self.source)

        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )
        updated = load_install_state(self.paths, self.suite)
        for plugin_id in updated["plugins"]:
            marker = json.loads(
                (
                    self.paths.plugin_dir
                    / plugin_id
                    / ".shibumi-managed.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(marker["suiteId"], "hancore.shibumi")
            self.assertEqual(marker["pluginId"], plugin_id)

    def test_update_refuses_markerless_foreign_directory(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.control-center"
        target = self.paths.plugin_dir / plugin_id
        (target / ".shibumi-managed.json").unlink()
        manifest_path = target / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["x-shibumi"]["suiteId"] = "foreign.suite"
        manifest_path.write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )

        with self.assertRaises(TransactionError):
            command_update(self.args(), self.suite, self.paths, self.runtime)

    def test_status_reports_bar_reset_and_activate_repairs_it(self) -> None:
        self.install()
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["bar"].pop("id")
        config["bar"]["layout"] = {"left": [], "center": [], "right": []}
        config["bar"].pop("shibumi", None)
        atomic_write(self.paths.config_file, encode_config(config))

        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(command_status(self.suite, self.paths), 1)
        self.assertIn("Configuration drift:", output.getvalue())
        with self.assertRaisesRegex(CliError, "inactive"):
            command_update(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(
            command_activate(self.args(), self.suite, self.paths, self.runtime), 0
        )
        restored = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(restored["bar"]["id"], "hancore.shibumi.bar")
        restored_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in restored["bar"]["layout"][region]
        }
        profile = self.suite.profile("default")
        self.assertTrue(
            set(profile.layout["left"] + profile.layout["center"] + profile.layout["right"])
            <= restored_ids
        )
        self.assertEqual(command_status(self.suite, self.paths), 0)

    def test_managed_repair_stops_before_publish_and_restarts_once(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.bluetooth"
        shutil.rmtree(self.paths.plugin_dir / plugin_id)
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["bar"].pop("id", None)
        config["bar"]["layout"] = {
            "left": [{"id": "omarchy.menu"}],
            "center": [{"id": "omarchy.clock"}],
            "right": [],
        }
        atomic_write(self.paths.config_file, encode_config(config))

        original_expose = PluginTransaction.expose

        def recording_expose(transaction: PluginTransaction) -> None:
            self.runtime.events.append("expose")
            original_expose(transaction)

        self.runtime.events.clear()
        with patch.object(PluginTransaction, "expose", recording_expose):
            self.assertEqual(
                command_repair(self.args(), self.suite, self.paths, self.runtime),
                0,
            )

        self.assertIn("stop", self.runtime.events)
        self.assertIn("expose", self.runtime.events)
        self.assertLess(
            self.runtime.events.index("stop"), self.runtime.events.index("expose")
        )
        self.assertEqual(self.runtime.events.count("restart"), 1)
        self.assertNotIn("reload-config", self.runtime.events)
        self.assertNotIn("reload-payload", self.runtime.events)
        self.assertTrue((self.paths.plugin_dir / plugin_id).is_dir())
        self.assertEqual(command_status(self.suite, self.paths), 0)

    def test_repair_restores_plugin_removed_by_generic_plugin_manager(self) -> None:
        self.install()
        state_before = load_install_state(self.paths, self.suite)
        plugin_id = "hancore.shibumi.bluetooth"
        shutil.rmtree(self.paths.plugin_dir / plugin_id)

        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        for region in ("left", "center", "right"):
            config["bar"]["layout"][region] = [
                entry
                for entry in config["bar"]["layout"][region]
                if entry_id(entry) != plugin_id
            ]
        config["plugins"] = [
            entry for entry in config["plugins"] if entry_id(entry) != plugin_id
        ]
        atomic_write(self.paths.config_file, encode_config(config))

        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(command_status(self.suite, self.paths), 1)
        self.assertIn(f"Missing: {plugin_id}", output.getvalue())
        self.assertIn("Repair with: shibumi-suite repair", output.getvalue())
        with self.assertRaisesRegex(CliError, "inactive"):
            command_update(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(
            command_repair(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        self.assertTrue((self.paths.plugin_dir / plugin_id).is_dir())
        repaired = load_install_state(self.paths, self.suite)
        self.assertEqual(set(repaired["plugins"]), set(state_before["plugins"]))
        self.assertEqual(command_status(self.suite, self.paths), 0)

    def test_failed_repair_restores_the_pre_repair_partial_state(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.bluetooth"
        target = self.paths.plugin_dir / plugin_id
        shutil.rmtree(target)
        original_config = self.paths.config_file.read_bytes()
        original_state = (self.paths.state_dir / "install.json").read_bytes()
        self.runtime.fail_restart_count = 1

        with self.assertRaises(RuntimeFailure):
            command_repair(self.args(), self.suite, self.paths, self.runtime)

        self.assertFalse(target.exists())
        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(),
            original_state,
        )
        self.assertFalse(self.hidden_transaction_paths())

    def test_started_repair_uses_live_fallback_when_rollback_restart_is_blocked(self) -> None:
        self.install()
        original_config = self.paths.config_file.read_bytes()
        original_state = (self.paths.state_dir / "install.json").read_bytes()
        reloads_before = self.runtime.reloads
        original_restart = self.runtime.restart_shell
        restart_calls = 0

        def fail_second_restart() -> None:
            nonlocal restart_calls
            restart_calls += 1
            if restart_calls == 2:
                raise RuntimeFailure("injected rollback restart preflight failure")
            original_restart()

        with patch.object(
            self.runtime, "restart_shell", side_effect=fail_second_restart
        ), patch.object(
            self.runtime,
            "verify_install",
            side_effect=RuntimeFailure("injected post-restart verification failure"),
        ):
            with self.assertRaisesRegex(
                RuntimeFailure, "injected post-restart verification failure"
            ):
                command_repair(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(restart_calls, 2)
        self.assertTrue(self.runtime.shell_running)
        self.assertGreater(self.runtime.reloads, reloads_before)
        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(), original_state
        )
        self.assertFalse(self.hidden_transaction_paths())

    def test_stopped_repair_retains_recovery_when_restart_remains_blocked(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.bluetooth"
        target = self.paths.plugin_dir / plugin_id
        shutil.rmtree(target)
        original_config = self.paths.config_file.read_bytes()
        original_state = (self.paths.state_dir / "install.json").read_bytes()
        self.runtime.fail_restart_count = 2

        with self.assertRaisesRegex(RuntimeFailure, "injected shell restart failure"):
            command_repair(self.args(), self.suite, self.paths, self.runtime)

        self.assertFalse(self.runtime.shell_running)
        self.assertFalse(target.exists())
        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(), original_state
        )
        transactions = list(
            (self.paths.state_dir / "transactions").glob("*/journal.json")
        )
        self.assertEqual(len(transactions), 1)
        journal = json.loads(transactions[0].read_text(encoding="utf-8"))
        self.assertEqual(journal["phase"], "recovery-required")
        self.assertTrue(journal["shellStopped"])

        self.assertEqual(recover_transactions(self.paths, self.runtime), 1)
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(target.exists())
        self.assertFalse(self.hidden_transaction_paths())

    def test_repair_removes_suite_helper_enabled_as_a_generic_widget(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.update-center"
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["bar"]["layout"]["right"].append({"id": plugin_id})
        atomic_write(self.paths.config_file, encode_config(config))

        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(command_status(self.suite, self.paths), 1)
        self.assertIn(f"unexpected widgets: {plugin_id}", output.getvalue())

        self.assertEqual(
            command_repair(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        repaired = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        layout_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in repaired["bar"]["layout"][region]
        }
        service_ids = {entry_id(entry) for entry in repaired["plugins"]}
        self.assertNotIn(plugin_id, layout_ids)
        self.assertIn(plugin_id, service_ids)
        self.assertEqual(command_status(self.suite, self.paths), 0)

    def test_suite_contract_requires_quattro_widget_default_section(self) -> None:
        manifest_path = (
            self.source / "hancore.shibumi.bluetooth" / "manifest.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["barWidget"].pop("defaultSection")
        manifest_path.write_text(
            json.dumps(manifest, indent=2) + "\n",
            encoding="utf-8",
        )

        with self.assertRaisesRegex(ContractError, "placement"):
            Suite.load(self.source)

    def test_suite_contract_rejects_plugin_menu_control_characters(self) -> None:
        manifest_path = (
            self.source / "hancore.shibumi.bluetooth" / "manifest.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["name"] = "Bluetooth\tInjected row"
        manifest_path.write_text(
            json.dumps(manifest, indent=2) + "\n",
            encoding="utf-8",
        )

        with self.assertRaisesRegex(ContractError, "manifest drifts"):
            Suite.load(self.source)

    def test_deactivate_activate_round_trip_preserves_user_state_and_payload(self) -> None:
        self.install()
        state_before = (self.paths.state_dir / "install.json").read_bytes()
        payload_before = {
            plugin_id: self.suite.plugins[plugin_id].payload_digest(
                self.paths.plugin_dir / plugin_id
            )
            for plugin_id in self.suite.plugins
        }
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["bar"]["layout"]["right"].append(
            {"id": "user.weather", "custom": {"city": "Berlin"}}
        )
        config["plugins"].append({"id": "user.service", "interval": 17})
        config["bar"].setdefault("shibumi", {})["testSetting"] = "retained"
        atomic_write(self.paths.config_file, encode_config(config))

        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        inactive = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(inactive["bar"].get("id", "omarchy.bar"), "omarchy.bar")
        self.assertEqual(inactive["bar"]["shibumi"]["testSetting"], "retained")
        self.assertIn(
            "user.weather",
            {
                entry_id(entry)
                for region in ("left", "center", "right")
                for entry in inactive["bar"]["layout"][region]
            },
        )
        self.assertIn(
            "user.service", {entry_id(entry) for entry in inactive["plugins"]}
        )
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(), state_before
        )
        self.assertEqual(
            {
                plugin_id: self.suite.plugins[plugin_id].payload_digest(
                    self.paths.plugin_dir / plugin_id
                )
                for plugin_id in self.suite.plugins
            },
            payload_before,
        )

        self.assertEqual(
            command_activate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        active = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(active["bar"]["id"], "hancore.shibumi.bar")
        self.assertEqual(active["bar"]["shibumi"]["testSetting"], "retained")
        user_weather = next(
            entry
            for entry in active["bar"]["layout"]["right"]
            if entry_id(entry) == "user.weather"
        )
        self.assertEqual(user_weather["custom"], {"city": "Berlin"})
        user_service = next(
            entry
            for entry in active["plugins"]
            if entry_id(entry) == "user.service"
        )
        self.assertEqual(user_service["interval"], 17)

    def test_failed_deactivation_restores_config_and_install_state(self) -> None:
        self.install()
        config_before = self.paths.config_file.read_bytes()
        state_before = (self.paths.state_dir / "install.json").read_bytes()
        self.runtime.fail_deactivation_verify = True

        with self.assertRaisesRegex(
            RuntimeFailure, "injected deactivation verification failure"
        ):
            command_deactivate(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(self.paths.config_file.read_bytes(), config_before)
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(), state_before
        )
        self.assertFalse(self.hidden_transaction_paths())

    def test_failed_update_restores_payload_config_and_pending_state(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.center"
        target_file = self.paths.plugin_dir / plugin_id / "BarWidget.qml"
        source_file = self.source / plugin_id / "BarWidget.qml"
        old_payload = target_file.read_bytes()
        old_config = self.paths.config_file.read_bytes()
        old_state = (self.paths.state_dir / "install.json").read_bytes()
        source_file.write_text(
            source_file.read_text(encoding="utf-8") + "\n// rejected update\n",
            encoding="utf-8",
        )
        self.suite = Suite.load(self.source)
        stops_before = self.runtime.stops
        reloads_before = self.runtime.payload_reloads
        # The operational restart and rollback restart both fail their host
        # preflight before killing the still-running shell.
        self.runtime.fail_restart_count = 2
        with self.assertRaisesRegex(
            RuntimeFailure, "injected shell restart failure"
        ):
            command_update(self.args(), self.suite, self.paths, self.runtime)
        self.assertEqual(target_file.read_bytes(), old_payload)
        self.assertEqual(self.paths.config_file.read_bytes(), old_config)
        self.assertEqual((self.paths.state_dir / "install.json").read_bytes(), old_state)
        self.assertEqual(self.runtime.stops, stops_before)
        self.assertGreater(self.runtime.payload_reloads, reloads_before)
        self.assertFalse(self.hidden_transaction_paths())
        self.assertFalse((self.paths.state_dir / "transactions").exists())

    def test_update_adds_new_profile_plugin_without_rewriting_user_layout(self) -> None:
        self.install()
        new_id = "hancore.shibumi.update-center"
        shutil.rmtree(self.paths.plugin_dir / new_id)

        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["plugins"] = [
            entry for entry in config["plugins"] if entry_id(entry) != new_id
        ]
        config["bar"]["layout"]["left"].reverse()
        expected_layout = json.loads(json.dumps(config["bar"]["layout"]))
        atomic_write(self.paths.config_file, encode_config(config))

        state = load_install_state(self.paths, self.suite)
        state["plugins"] = [plugin_id for plugin_id in state["plugins"] if plugin_id != new_id]
        state["pluginDigests"].pop(new_id)
        state["payloadDigest"] = suite_payload_digest(state["pluginDigests"])
        atomic_write(
            self.paths.state_dir / "install.json",
            (json.dumps(state, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        )

        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )
        updated_state = load_install_state(self.paths, self.suite)
        self.assertIn(new_id, updated_state["plugins"])
        self.assertTrue((self.paths.plugin_dir / new_id).is_dir())
        updated_config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertIn(new_id, {entry_id(entry) for entry in updated_config["plugins"]})
        self.assertEqual(updated_config["bar"]["layout"], expected_layout)

    def test_update_adds_new_widget_at_profile_edge_without_reordering(self) -> None:
        self.install()
        new_id = "hancore.shibumi.temperature"
        shutil.rmtree(self.paths.plugin_dir / new_id)

        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        for region in ("left", "center", "right"):
            config["bar"]["layout"][region] = [
                entry
                for entry in config["bar"]["layout"][region]
                if entry_id(entry) != new_id
            ]
        config["bar"]["layout"]["left"].reverse()
        expected_left = json.loads(json.dumps(config["bar"]["layout"]["left"]))
        expected_right = json.loads(json.dumps(config["bar"]["layout"]["right"]))
        atomic_write(self.paths.config_file, encode_config(config))

        state = load_install_state(self.paths, self.suite)
        state["plugins"] = [
            plugin_id for plugin_id in state["plugins"] if plugin_id != new_id
        ]
        state["pluginDigests"].pop(new_id)
        state["payloadDigest"] = suite_payload_digest(state["pluginDigests"])
        atomic_write(
            self.paths.state_dir / "install.json",
            (json.dumps(state, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        )

        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )
        updated = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(updated["bar"]["layout"]["left"], expected_left)
        self.assertEqual(
            updated["bar"]["layout"]["right"][:-1], expected_right
        )
        self.assertEqual(
            entry_id(updated["bar"]["layout"]["right"][-1]), new_id
        )

    def test_interrupted_update_is_recovered_before_next_operation(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.memory"
        target_file = self.paths.plugin_dir / plugin_id / "BarWidget.qml"
        old_payload = target_file.read_bytes()
        source_file = self.source / plugin_id / "BarWidget.qml"
        source_file.write_text(
            source_file.read_text(encoding="utf-8") + "\n// interrupted\n",
            encoding="utf-8",
        )
        self.suite = Suite.load(self.source)
        transaction = PluginTransaction(self.paths, self.runtime)
        specs = self.suite.selected(tuple(load_install_state(self.paths, self.suite)["plugins"]))
        transaction.preflight_targets(specs)
        transaction.stage(specs, revision="archive", suite_version=self.suite.version)
        transaction.expose()
        transaction.write_config(b'{"version":1,"bar":{"id":"broken"}}\n')

        self.assertEqual(recover_transactions(self.paths, self.runtime), 1)
        self.assertEqual(target_file.read_bytes(), old_payload)
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(config["bar"]["id"], "hancore.shibumi.bar")
        self.assertFalse(self.hidden_transaction_paths())

    def test_first_transaction_durably_creates_recovery_namespace(self) -> None:
        plugin_id = "hancore.shibumi.memory"
        target = self.paths.plugin_dir / plugin_id
        target.mkdir(parents=True)
        (target / ".shibumi-managed.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "suiteId": "hancore.shibumi",
                    "pluginId": plugin_id,
                }
            )
            + "\n",
            encoding="utf-8",
        )
        transaction_root = self.paths.state_dir / "transactions"
        events: list[tuple[str, Path]] = []
        original_fsync_directory = transaction_module._fsync_directory
        original_replace = transaction_module.os.replace
        original_write_journal = PluginTransaction._write_journal

        def recording_fsync_directory(path: Path) -> None:
            original_fsync_directory(path)
            events.append(("fsync", path))

        def recording_replace(source: object, destination: object) -> None:
            original_replace(source, destination)
            source_path = Path(source)
            destination_path = Path(destination)
            if (
                source_path.name.startswith(transaction_module.PREPARATION_PREFIX)
                and destination_path.parent == transaction_root
            ):
                events.append(("publish", destination_path))
            elif destination_path.name.startswith(".shibumi-backup."):
                events.append(("mutation", destination_path))

        def recording_write_journal(
            transaction: PluginTransaction, *args: object, **kwargs: object
        ) -> None:
            original_write_journal(transaction, *args, **kwargs)
            phase = str(args[0] if args else kwargs.get("phase") or "")
            events.append((f"journal:{phase}", transaction.journal_file))

        with (
            patch.object(
                transaction_module,
                "_fsync_directory",
                side_effect=recording_fsync_directory,
            ),
            patch.object(
                transaction_module.os,
                "replace",
                side_effect=recording_replace,
            ),
            patch.object(
                PluginTransaction,
                "_write_journal",
                recording_write_journal,
            ),
        ):
            transaction = PluginTransaction(self.paths, self.runtime)
            transaction.stage_removal_ids((plugin_id,))

        first_journal = next(
            index
            for index, event in enumerate(events)
            if event[0] == "journal:prepared"
        )
        for required in (
            self.paths.state_dir.parent,
            self.paths.state_dir,
            transaction_root,
        ):
            sync_index = events.index(("fsync", required))
            self.assertLess(sync_index, first_journal)
        publish_index = next(
            index for index, event in enumerate(events) if event[0] == "publish"
        )
        self.assertGreater(publish_index, first_journal)
        durable_publication = next(
            index
            for index, event in enumerate(events)
            if index > publish_index and event == ("fsync", transaction_root)
        )
        record_journal = next(
            index
            for index, event in enumerate(events)
            if event[0] == "journal:prepared-removal"
        )
        durable_record = max(
            index
            for index, event in enumerate(events)
            if index < record_journal
            and event == ("fsync", transaction.transaction_dir)
        )
        mutation_index = next(
            index for index, event in enumerate(events) if event[0] == "mutation"
        )
        self.assertGreater(record_journal, durable_record)
        self.assertGreater(mutation_index, record_journal)
        self.assertGreater(mutation_index, durable_publication)
        self.assertTrue(transaction.journal_file.is_file())
        transaction.rollback()

    def test_staged_payload_is_durable_before_live_exposure(self) -> None:
        plugin_id = "hancore.shibumi.memory"
        spec = self.suite.plugins[plugin_id]
        events: list[tuple[str, Path]] = []
        original_fsync_tree = transaction_module._fsync_tree
        original_fsync_directory = transaction_module._fsync_directory
        original_replace = transaction_module.os.replace
        original_write_journal = PluginTransaction._write_journal

        def recording_fsync_tree(path: Path) -> None:
            original_fsync_tree(path)
            events.append(("tree", path))

        def recording_fsync_directory(path: Path) -> None:
            original_fsync_directory(path)
            events.append(("fsync", path))

        def recording_replace(source: object, destination: object) -> None:
            original_replace(source, destination)
            source_path = Path(source)
            destination_path = Path(destination)
            if source_path.name.startswith(".shibumi-stage.") \
                    and destination_path == self.paths.plugin_dir / plugin_id:
                events.append(("exposure", destination_path))

        def recording_write_journal(
            transaction: PluginTransaction, *args: object, **kwargs: object
        ) -> None:
            original_write_journal(transaction, *args, **kwargs)
            phase = str(args[0] if args else kwargs.get("phase") or "")
            events.append((f"journal:{phase}", transaction.journal_file))

        with (
            patch.object(
                transaction_module, "_fsync_tree", side_effect=recording_fsync_tree
            ),
            patch.object(
                transaction_module,
                "_fsync_directory",
                side_effect=recording_fsync_directory,
            ),
            patch.object(
                transaction_module.os, "replace", side_effect=recording_replace
            ),
            patch.object(
                PluginTransaction, "_write_journal", recording_write_journal
            ),
        ):
            transaction = PluginTransaction(self.paths, self.runtime)
            transaction.stage(
                (spec,), revision="durability", suite_version=self.suite.version
            )
            transaction.expose()

        tree_index = next(
            index for index, event in enumerate(events) if event[0] == "tree"
        )
        durable_plugin_directory = next(
            index
            for index, event in enumerate(events)
            if event == ("fsync", self.paths.plugin_dir.parent)
        )
        durable_stage_entry = next(
            index
            for index, event in enumerate(events)
            if index > tree_index and event == ("fsync", self.paths.plugin_dir)
        )
        staged_journal = next(
            index
            for index, event in enumerate(events)
            if event[0] == "journal:staged"
        )
        exposure_index = next(
            index for index, event in enumerate(events) if event[0] == "exposure"
        )
        durable_exposure = next(
            index
            for index, event in enumerate(events)
            if index > exposure_index
            and event == ("fsync", self.paths.plugin_dir)
        )
        exposed_journal = next(
            index
            for index, event in enumerate(events)
            if event[0] == "journal:exposed"
        )
        self.assertLess(durable_plugin_directory, tree_index)
        self.assertLess(tree_index, durable_stage_entry)
        self.assertLess(durable_stage_entry, staged_journal)
        self.assertLess(staged_journal, exposure_index)
        self.assertLess(exposure_index, durable_exposure)
        self.assertLess(durable_exposure, exposed_journal)
        transaction.rollback()

    def test_transaction_preparation_is_private_until_complete(self) -> None:
        self.paths.config_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.config_file.write_text('{"version":1}\n', encoding="utf-8")
        self.paths.menu_extension_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.menu_extension_file.write_text("{}\n", encoding="utf-8")
        original_atomic_write = transaction_module.atomic_write

        for boundary, fail_after_write in (
            ("directory", 0),
            ("config snapshot", 1),
            ("menu snapshot", 2),
            ("journal", 3),
        ):
            with self.subTest(boundary=boundary):
                calls = 0

                def faulting_atomic_write(
                    path: Path, payload: bytes, mode: int = 0o600
                ) -> None:
                    nonlocal calls
                    calls += 1
                    if fail_after_write == 0 and calls == 1:
                        raise OSError("injected preparation failure")
                    original_atomic_write(path, payload, mode)
                    if calls == fail_after_write:
                        raise OSError("injected preparation failure")

                with patch.object(
                    transaction_module,
                    "atomic_write",
                    side_effect=faulting_atomic_write,
                ):
                    with self.assertRaisesRegex(
                        OSError, "injected preparation failure"
                    ):
                        PluginTransaction(self.paths, self.runtime)

                transaction_root = self.paths.state_dir / "transactions"
                self.assertFalse(
                    transaction_root.is_dir() and any(transaction_root.iterdir())
                )
                self.assertEqual(
                    self.paths.config_file.read_text(encoding="utf-8"),
                    '{"version":1}\n',
                )
                self.assertEqual(
                    self.paths.menu_extension_file.read_text(encoding="utf-8"),
                    "{}\n",
                )

        transaction = PluginTransaction(self.paths, self.runtime)
        self.assertTrue(transaction.transaction_dir.is_dir())
        self.assertTrue(transaction.journal_file.is_file())
        self.assertTrue(transaction.snapshot_file.is_file())
        self.assertTrue(transaction.menu_extension_snapshot_file.is_file())
        self.assertFalse(
            any(
                path.name.startswith(transaction_module.PREPARATION_PREFIX)
                for path in transaction.transaction_dir.parent.iterdir()
            )
        )
        transaction.rollback()

    def test_recovery_discards_crash_interrupted_private_preparations(self) -> None:
        transaction_root = self.paths.state_dir / "transactions"
        transaction_root.mkdir(parents=True)
        for prefix in (
            transaction_module.PREPARATION_PREFIX,
            transaction_module.CLEANUP_PREFIX,
        ):
            for boundary in range(4):
                with self.subTest(prefix=prefix, boundary=boundary):
                    transaction_root.mkdir(parents=True, exist_ok=True)
                    private = transaction_root / f"{prefix}crash-{boundary}"
                    private.mkdir()
                    names = (
                        "shell.json.before",
                        "omarchy-menu.jsonc.before",
                        "journal.json",
                    )
                    for name in names[:boundary]:
                        (private / name).write_text(
                            "partial\n", encoding="utf-8"
                        )

                    events_before = list(self.runtime.events)
                    self.assertEqual(
                        recover_transactions(self.paths, self.runtime), 0
                    )
                    self.assertFalse(private.exists())
                    self.assertEqual(self.runtime.events, events_before)

    def test_recovery_rejects_symlinked_transaction_root_without_traversal(self) -> None:
        external = self.root / "external-transactions"
        private = external / f"{transaction_module.CLEANUP_PREFIX}foreign"
        private.mkdir(parents=True)
        marker = private / "journal.json"
        marker.write_text("do not remove\n", encoding="utf-8")
        transaction_root = self.paths.state_dir / "transactions"
        transaction_root.parent.mkdir(parents=True)
        transaction_root.symlink_to(external, target_is_directory=True)

        with self.assertRaisesRegex(TransactionError, "symlinked transaction root"):
            recover_transactions(self.paths, self.runtime)

        self.assertEqual(marker.read_text(encoding="utf-8"), "do not remove\n")

    def test_recovery_validates_complete_journal_before_any_mutation(self) -> None:
        self.install()
        config_before = self.paths.config_file.read_bytes()
        state_path = self.paths.state_dir / "install.json"
        state_before = state_path.read_bytes()
        plugin_ids = ("hancore.shibumi.memory", "hancore.shibumi.cpu")
        payloads_before = {
            plugin_id: (
                self.paths.plugin_dir / plugin_id / "BarWidget.qml"
            ).read_bytes()
            for plugin_id in plugin_ids
        }

        for scenario in (
            "missing snapshot",
            "malformed second record",
            "invalid late boolean",
            "boolean schema",
            "float schema",
            "array journal",
        ):
            with self.subTest(scenario=scenario):
                transaction_root = self.paths.state_dir / "transactions"
                transaction_root.mkdir(parents=True, exist_ok=True)
                token = f"validation-{scenario.replace(' ', '-')}"
                directory = transaction_root / token
                directory.mkdir()
                records = []
                for plugin_id in plugin_ids:
                    records.append(
                        {
                            "action": "replace",
                            "pluginId": plugin_id,
                            "target": str(self.paths.plugin_dir / plugin_id),
                            "stage": str(
                                self.paths.plugin_dir
                                / f".shibumi-stage.{token}.{plugin_id}"
                            ),
                            "backup": str(
                                self.paths.plugin_dir
                                / f".shibumi-backup.{token}.{plugin_id}"
                            ),
                            "hadTarget": True,
                        }
                    )
                journal: object = {
                    "schemaVersion": 1,
                    "suiteId": "hancore.shibumi",
                    "token": token,
                    "phase": "prepared",
                    "pluginRoot": str(self.paths.plugin_dir.resolve()),
                    "configPath": str(self.paths.config_file.resolve()),
                    "configExisted": True,
                    "restartOnReconcile": False,
                    "shellStopped": False,
                    "payloadReloadExpected": False,
                    "records": records,
                }
                if scenario == "malformed second record":
                    records[1]["target"] = str(self.root / "outside")
                elif scenario == "invalid late boolean":
                    assert isinstance(journal, dict)
                    journal["payloadReloadExpected"] = "false"
                elif scenario == "boolean schema":
                    assert isinstance(journal, dict)
                    journal["schemaVersion"] = True
                elif scenario == "float schema":
                    assert isinstance(journal, dict)
                    journal["schemaVersion"] = 1.0
                elif scenario == "array journal":
                    journal = []
                (directory / "journal.json").write_text(
                    json.dumps(journal) + "\n", encoding="utf-8"
                )
                if scenario != "missing snapshot":
                    (directory / "shell.json.before").write_bytes(config_before)

                events_before = list(self.runtime.events)
                with self.assertRaises(TransactionError):
                    recover_transactions(self.paths, self.runtime)

                self.assertEqual(self.paths.config_file.read_bytes(), config_before)
                self.assertEqual(state_path.read_bytes(), state_before)
                for plugin_id in plugin_ids:
                    self.assertEqual(
                        (
                            self.paths.plugin_dir
                            / plugin_id
                            / "BarWidget.qml"
                        ).read_bytes(),
                        payloads_before[plugin_id],
                    )
                self.assertEqual(self.runtime.events, events_before)
                shutil.rmtree(transaction_root)

    def test_post_state_commit_failures_roll_forward_without_payload_rollback(self) -> None:
        self.install()
        plugin_ids = ("hancore.shibumi.memory", "hancore.shibumi.cpu")

        for boundary in (
            "committed journal",
            "backup archival",
            "partial backup archival",
            "archive data flush",
            "partial archive copy",
        ):
            with self.subTest(boundary=boundary):
                old_payloads = {
                    plugin_id: (
                        self.paths.plugin_dir / plugin_id / "BarWidget.qml"
                    ).read_bytes()
                    for plugin_id in plugin_ids
                }
                for plugin_id in plugin_ids:
                    source_file = self.source / plugin_id / "BarWidget.qml"
                    source_file.write_text(
                        source_file.read_text(encoding="utf-8")
                        + f"\n// post-state {boundary}\n",
                        encoding="utf-8",
                    )
                suite = Suite.load(self.source)
                specs = tuple(suite.plugins[plugin_id] for plugin_id in plugin_ids)
                transaction = PluginTransaction(self.paths, self.runtime)
                transaction.preflight_targets(specs)
                transaction.stage(
                    specs, revision="commit-point", suite_version=suite.version
                )
                transaction.expose()
                expected_payloads = {
                    plugin_id: (
                        self.paths.plugin_dir / plugin_id / "BarWidget.qml"
                    ).read_bytes()
                    for plugin_id in plugin_ids
                }
                desired_state = {
                    "boundary": boundary,
                    "plugins": list(plugin_ids),
                }

                if boundary == "committed journal":
                    original_write_journal = transaction._write_journal

                    def fail_committed(
                        phase: str,
                        desired: object = "unchanged",
                        archive: object = "unchanged",
                    ) -> None:
                        if phase == "committed":
                            raise OSError("injected committed journal failure")
                        original_write_journal(phase, desired, archive)

                    fault = patch.object(
                        transaction, "_write_journal", side_effect=fail_committed
                    )
                    expected_phase = "committing"
                elif boundary == "backup archival":
                    fault = patch.object(
                        transaction,
                        "_archive_backups",
                        side_effect=OSError("injected backup archival failure"),
                    )
                    expected_phase = "committed"
                elif boundary == "partial backup archival":
                    def fail_after_first_archive() -> None:
                        first = transaction.records[0]
                        destination = (
                            self.paths.state_dir / "backups" / transaction.token
                        )
                        destination.mkdir(parents=True, exist_ok=True)
                        shutil.move(
                            first["backup"], destination / first["pluginId"]
                        )
                        raise OSError("injected partial backup archival failure")

                    fault = patch.object(
                        transaction,
                        "_archive_backups",
                        side_effect=fail_after_first_archive,
                    )
                    expected_phase = "committed"
                elif boundary == "archive data flush":
                    original_fsync_tree = transaction_module._fsync_tree

                    def fail_archive_data_flush(path: Path) -> None:
                        if path.name.startswith(".") and path.name.endswith(".partial"):
                            raise OSError("injected archive data flush failure")
                        original_fsync_tree(path)

                    fault = patch.object(
                        transaction_module,
                        "_fsync_tree",
                        side_effect=fail_archive_data_flush,
                    )
                    expected_phase = "committed"
                else:
                    def fail_during_archive_copy() -> None:
                        first = transaction.records[0]
                        destination = (
                            self.paths.state_dir / "backups" / transaction.token
                        )
                        partial = destination / f".{first['pluginId']}.partial"
                        partial.mkdir(parents=True)
                        shutil.copy2(
                            Path(first["backup"]) / "BarWidget.qml",
                            partial / "BarWidget.qml",
                        )
                        raise OSError("injected intra-record archive copy failure")

                    fault = patch.object(
                        transaction,
                        "_archive_backups",
                        side_effect=fail_during_archive_copy,
                    )
                    expected_phase = "committed"

                with fault:
                    with self.assertRaises(OSError):
                        with transaction:
                            transaction.finish(desired_state, archive_previous=True)

                journal = json.loads(
                    transaction.journal_file.read_text(encoding="utf-8")
                )
                self.assertTrue(transaction.commit_point_reached)
                self.assertFalse(transaction.finished)
                self.assertEqual(journal["phase"], expected_phase)
                self.assertTrue(journal["archivePrevious"])
                for plugin_id in plugin_ids:
                    self.assertEqual(
                        (self.paths.plugin_dir / plugin_id / "BarWidget.qml").read_bytes(),
                        expected_payloads[plugin_id],
                    )
                self.assertEqual(
                    json.loads(
                        (self.paths.state_dir / "install.json").read_text(
                            encoding="utf-8"
                        )
                    ),
                    desired_state,
                )

                self.assertEqual(recover_transactions(self.paths, self.runtime), 1)
                archive = self.paths.state_dir / "backups" / transaction.token
                for plugin_id in plugin_ids:
                    self.assertEqual(
                        (archive / plugin_id / "BarWidget.qml").read_bytes(),
                        old_payloads[plugin_id],
                    )
                    self.assertEqual(
                        (self.paths.plugin_dir / plugin_id / "BarWidget.qml").read_bytes(),
                        expected_payloads[plugin_id],
                    )
                self.assertFalse(self.hidden_transaction_paths())

    def test_legacy_journal_without_shell_state_requires_restart(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.memory"
        spec = self.suite.plugins[plugin_id]
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stage(
            (spec,), revision="legacy-journal", suite_version=self.suite.version
        )
        transaction.expose()
        transaction.write_config(b'{"version":1,"bar":{"id":"broken"}}\n')
        journal = json.loads(transaction.journal_file.read_text(encoding="utf-8"))
        journal.pop("shellStopped")
        transaction.journal_file.write_text(
            json.dumps(journal, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        reloads_before = self.runtime.payload_reloads
        self.runtime.fail_restart_count = 1

        with self.assertRaisesRegex(RuntimeFailure, "injected shell restart failure"):
            recover_transactions(self.paths, self.runtime)

        self.assertTrue(transaction.transaction_dir.is_dir())
        self.assertEqual(self.runtime.payload_reloads, reloads_before)
        self.assertEqual(recover_transactions(self.paths, self.runtime), 1)
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(self.hidden_transaction_paths())

    def test_failed_rollback_retains_journal_and_supports_later_recovery(self) -> None:
        self.install()
        original_config = self.paths.config_file.read_bytes()
        original_menu = self.paths.menu_extension_file.read_bytes()
        plugin_id = "hancore.shibumi.memory"
        specs = self.suite.selected((plugin_id,))

        def exposed_transaction() -> PluginTransaction:
            transaction = PluginTransaction(self.paths, self.runtime)
            transaction.preflight_targets(specs)
            transaction.stage(
                specs, revision="archive", suite_version=self.suite.version
            )
            transaction.expose()
            transaction.write_config(b'{"version":1,"bar":{"id":"broken"}}\n')
            transaction.write_menu_extension(b'{"broken":true}\n')
            return transaction

        original_atomic_write = transaction_module.atomic_write
        faults = (
            (
                "plugin restoration",
                lambda transaction: patch.object(
                    transaction_module,
                    "_restore_records",
                    side_effect=TransactionError("injected plugin restore failure"),
                ),
            ),
            (
                "configuration restoration",
                lambda transaction: patch.object(
                    transaction_module,
                    "atomic_write",
                    side_effect=lambda path, payload: (
                        (_ for _ in ()).throw(
                            OSError("injected configuration restore failure")
                        )
                        if Path(path) == self.paths.config_file
                        else original_atomic_write(path, payload)
                    ),
                ),
            ),
            (
                "menu restoration",
                lambda transaction: patch.object(
                    transaction,
                    "_restore_menu_extension",
                    side_effect=OSError("injected menu restore failure"),
                ),
            ),
            (
                "shell reconciliation",
                lambda transaction: patch.object(
                    self.runtime,
                    "reconcile_rollback",
                    side_effect=RuntimeFailure("injected reconciliation failure"),
                ),
            ),
        )

        for label, fault in faults:
            with self.subTest(boundary=label):
                transaction = exposed_transaction()
                with fault(transaction):
                    with self.assertRaises((OSError, RuntimeFailure, TransactionError)):
                        transaction.rollback()

                self.assertTrue(transaction.transaction_dir.is_dir())
                journal = json.loads(
                    transaction.journal_file.read_text(encoding="utf-8")
                )
                self.assertEqual(journal["phase"], "recovery-required")
                self.assertFalse(transaction.finished)

                self.assertEqual(
                    recover_transactions(self.paths, self.runtime), 1
                )
                self.assertFalse(transaction.transaction_dir.exists())
                self.assertEqual(self.paths.config_file.read_bytes(), original_config)
                self.assertEqual(
                    self.paths.menu_extension_file.read_bytes(), original_menu
                )
                self.assertFalse(self.hidden_transaction_paths())

    def test_nonmanaged_collision_fails_without_artifacts(self) -> None:
        collision = self.paths.plugin_dir / "hancore.shibumi.ai"
        collision.mkdir(parents=True)
        (collision / "user.txt").write_text("mine\n", encoding="utf-8")
        with self.assertRaises(TransactionError):
            command_install(self.args(), self.suite, self.paths, self.runtime)
        self.assertEqual((collision / "user.txt").read_text(encoding="utf-8"), "mine\n")
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.hidden_transaction_paths())

    def test_dry_run_reports_nonmanaged_collision_without_mutation(self) -> None:
        collision = self.paths.plugin_dir / "hancore.shibumi.ai"
        collision.mkdir(parents=True)
        (collision / "user.txt").write_text("mine\n", encoding="utf-8")
        with self.assertRaises(TransactionError):
            command_install(
                self.args(dry_run=True), self.suite, self.paths, self.runtime
            )
        self.assertEqual((collision / "user.txt").read_text(), "mine\n")
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.hidden_transaction_paths())

    def test_validation_failure_removes_every_staged_plugin(self) -> None:
        self.runtime.fail_validation_plugin = "hancore.shibumi.ai"
        with self.assertRaises(RuntimeFailure):
            command_install(self.args(), self.suite, self.paths, self.runtime)
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.hidden_transaction_paths())
        self.assertFalse(
            any(
                (self.paths.plugin_dir / plugin_id).exists()
                for plugin_id in self.suite.plugins
            )
        )

    def test_status_reports_retired_plugin_without_traceback(self) -> None:
        self.install()
        self.inject_retired_app_menu()
        output = io.StringIO()
        with redirect_stdout(output):
            result = command_status(self.suite, self.paths)
        self.assertEqual(result, 1)
        self.assertIn(
            "Pending retirement: hancore.shibumi.menu", output.getvalue()
        )

    def test_status_detects_locally_modified_installed_payload(self) -> None:
        self.install()
        target = self.paths.plugin_dir / "hancore.shibumi.ai" / "BarWidget.qml"
        target.write_text(
            target.read_text(encoding="utf-8") + "\n// local modification\n",
            encoding="utf-8",
        )
        output = io.StringIO()
        with redirect_stdout(output):
            result = command_status(self.suite, self.paths)
        self.assertEqual(result, 1)
        self.assertIn("Locally modified: hancore.shibumi.ai", output.getvalue())

    def test_source_revision_and_staging_share_one_payload_inventory(self) -> None:
        (self.source / ".gitignore").write_text(
            "__pycache__/\n*.py[cod]\n*.generated\n",
            encoding="utf-8",
        )
        subprocess.run(["git", "init", "-q", str(self.source)], check=True)
        subprocess.run(
            ["git", "-C", str(self.source), "config", "user.name", "Test"],
            check=True,
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(self.source),
                "config",
                "user.email",
                "test@example.invalid",
            ],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(self.source), "add", "."], check=True
        )
        subprocess.run(
            ["git", "-C", str(self.source), "commit", "-qm", "fixture"],
            check=True,
        )
        expected_revision = subprocess.run(
            ["git", "-C", str(self.source), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

        manager_root = (
            self.source / "hancore.shibumi.control-center" / "manager"
        )
        cache = manager_root / "__pycache__" / "manager.cpython-313.pyc"
        cache.parent.mkdir(exist_ok=True)
        cache.write_bytes(b"ignored cache bytes")
        self.suite = Suite.load(self.source)
        self.assertEqual(self.suite.revision(), expected_revision)

        self.install()
        installed_cache = (
            self.paths.plugin_dir
            / "hancore.shibumi.control-center"
            / "manager/__pycache__/manager.cpython-313.pyc"
        )
        self.assertFalse(installed_cache.exists())

        ignored_payload = manager_root / "runtime.generated"
        ignored_payload.write_text("included ignored payload\n", encoding="utf-8")
        self.assertEqual(
            self.suite.revision(), f"{expected_revision}-dirty"
        )
        ignored_payload.unlink()

        ordinary_untracked = manager_root / "runtime-extra.txt"
        ordinary_untracked.write_text("ordinary untracked payload\n", encoding="utf-8")
        self.assertEqual(
            self.suite.revision(), f"{expected_revision}-dirty"
        )

    def test_source_payload_symlink_is_rejected(self) -> None:
        link = self.source / "hancore.shibumi.ai" / "payload-link"
        link.symlink_to("BarWidget.qml")
        with self.assertRaises(ContractError):
            Suite.load(self.source)

    def test_dry_run_validates_without_mutation(self) -> None:
        self.assertEqual(
            command_install(
                self.args(dry_run=True), self.suite, self.paths, self.runtime
            ),
            0,
        )
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertFalse(self.paths.state_dir.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
