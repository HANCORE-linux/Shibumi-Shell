#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import io
import re
import shutil
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
from shibumi_suite.transaction import (  # noqa: E402
    PluginTransaction,
    TransactionError,
    recover_transactions,
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
        self.stops = 0
        self.payload_reloads = 0
        self.fail_payload_reload = False
        self.fail_deactivation_verify = False
        self.menu_refreshes = 0

    def validate_plugin(self, directory: Path) -> None:
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        if manifest.get("id") == self.fail_validation_plugin:
            raise RuntimeFailure("injected plugin validation failure")
        if manifest.get("id") != directory.name and not directory.name.endswith(
            "." + str(manifest.get("id"))
        ):
            raise RuntimeFailure(f"invalid staged plugin {directory}")

    def rescan(self) -> None:
        self.rescans += 1
        if self.rescans in self.fail_rescan_calls:
            raise RuntimeFailure("injected rescan failure")
        if self.fail_rescan_count:
            self.fail_rescan_count -= 1
            raise RuntimeFailure("injected rescan failure")

    def reload_config(self) -> None:
        self.reloads += 1

    def restart_shell(self) -> None:
        self.restarts += 1

    def stop_shell(self) -> None:
        self.stops += 1

    def reload_payload(self) -> None:
        self.payload_reloads += 1
        if self.fail_payload_reload:
            raise RuntimeFailure("injected payload reload failure")

    def refresh_menu(self) -> None:
        self.menu_refreshes += 1

    def ping(self) -> None:
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
        self.assertEqual(state["packageVersion"], "0.1.1-beta.2")
        self.assertEqual(state["sourceRevision"], "package:0.1.1-beta.2")
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
        self.assertEqual(package_state["packageVersion"], "0.1.1-beta.2")
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
        self.assertEqual(rolled_back["suiteVersion"], "0.1.1-beta.2")
        self.assertEqual(rolled_back["packageVersion"], "0.1.1-beta.2")
        self.assertEqual(rolled_back["sourceRevision"], "package:0.1.1-beta.2")

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
        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )
        self.assertEqual(self.runtime.payload_reloads, 1)
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
        self.assertEqual(
            command_update(
                self.args(), self.suite, self.paths, self.runtime
            ),
            0,
        )
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
        self.runtime.fail_payload_reload = True

        with self.assertRaises(RuntimeFailure):
            command_repair(self.args(), self.suite, self.paths, self.runtime)

        self.assertFalse(target.exists())
        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(),
            original_state,
        )
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
        self.runtime.fail_payload_reload = True
        with self.assertRaises(RuntimeFailure):
            command_update(self.args(), self.suite, self.paths, self.runtime)
        self.assertEqual(target_file.read_bytes(), old_payload)
        self.assertEqual(self.paths.config_file.read_bytes(), old_config)
        self.assertEqual((self.paths.state_dir / "install.json").read_bytes(), old_state)
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
