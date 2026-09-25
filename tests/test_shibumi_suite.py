#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import io
import os
import re
import runpy
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from typing import Callable
from unittest.mock import Mock, patch


REPO_ROOT = Path(__file__).resolve().parents[1]
PUBLISHED_BETA141_REVISION = "7a6c853b1947d303bad9a5b640c224c01b669106"
PUBLISHED_BETA15_REVISION = "4e91c26ebf4da07476d4be6176f29d7662fed9c1"
PUBLISHED_BETA151_REVISION = "36e4b9f0de428c17248d40592461a9e3f3f750f8"
PUBLISHED_BETA152_REVISION = "c45af77c8333b691ac36522247b6e5b5481a3666"
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from shibumi_suite.admission import (  # noqa: E402
    AdmissionError,
    JOURNAL_SCHEMA_VERSION,
    MAX_STATE_BYTES,
    _bounded_plugin_payload_digest,
    preflight_lifecycle_state,
    require_current_payload_identity,
    supported_install_identities,
)
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
    state_entry,
    migrate_state_settings,
    validate_state_settings,
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
import shibumi_suite.config as config_module  # noqa: E402
import shibumi_suite.transaction as transaction_module  # noqa: E402
from shibumi_suite.transaction import (  # noqa: E402
    PluginTransaction,
    TransactionError,
    recover_transactions,
)


QUICKSHELL_EMPTY_REGISTRY = "No running instances.\n"
SESSION_LOCK_FIELDS = (
    "locked",
    "requested",
    "pending",
    "sessionLocked",
    "secure",
)


def unlocked_session_status() -> dict[str, bool]:
    return dict.fromkeys(SESSION_LOCK_FIELDS, False)


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


BUG049_REACTIVATION_GUARD = """    return !!(row && row.id === id
      && (row.enabled === false || (row.enabled === true
        && !layoutStateController.v2Mode
        && isV1AdditionalSuiteWidget(id) && !layoutContains(id)
        && registeredWidgetComponent(id) !== null))
      && Array.isArray(row.kinds) && row.kinds.indexOf("bar-widget") >= 0)
"""


def validate_bug049_static_contract(
    bar_source: str, panel_source: str, resolver_source: str
) -> None:
    helper = """  function isV1AdditionalSuiteWidget(widgetId) {
    return [
      "hancore.shibumi.temperature",
      "hancore.shibumi.gpu",
      "hancore.shibumi.storage"
    ].indexOf(String(widgetId || "")) >= 0
  }
"""
    admission = """    if (!mutationAdmissionReady) return false
    const id = String(widgetId || "")
    if (!suiteHostShell.scoped || !layoutTransitionsSupported
        || layoutTransitionBusy || providerSnapshotTransitionBusy
        || stateTransitionBusy || !catalogObservation
        || !LayoutModel.validPluginId(id)) return false
    if (installed !== true) return layoutContains(id)
"""
    row_identity = """    const row = snapshot && snapshot.byId
      && Object.prototype.hasOwnProperty.call(snapshot.byId, id)
      ? snapshot.byId[id] : null
"""
    resolver = """  function registeredWidgetComponent(widgetId) {
    return hostWidgetResolverService.componentFor(widgetId)
  }
"""
    stale_observation = """    if (!canSetBarWidgetInstalled(id, installed)
        || observationValue !== catalogObservation) return false
"""
    keep_configured = """      removeIds: removeIds, keepConfigured: installed !== true
        && isV1AdditionalSuiteWidget(id),
"""
    for label, fragment in (
        ("exact G16-G18 identity set", helper),
        ("admission, busy, and disabled-path checks", admission),
        ("catalog row identity", row_identity),
        ("registered component resolver", resolver),
        ("narrow enabled-row exception", BUG049_REACTIVATION_GUARD),
        ("stale observation refusal", stale_observation),
        ("neutral-entry retention", keep_configured),
    ):
        if bar_source.count(fragment) != 1:
            raise AssertionError(f"Bug 049 static contract lost {label}")
    if resolver_source.count("entry.metadata.pluginId === key") != 1:
        raise AssertionError("Bug 049 component authority lost exact metadata identity")

    branch_start = panel_source.index(
        "        if (!v2LayoutActive\n"
        "            && [\"G16\", \"G17\", \"G18\"].indexOf(group) >= 0) {"
    )
    branch_end = panel_source.index(
        "        const alternativesInstalled", branch_start
    )
    branch = panel_source[branch_start:branch_end]
    neutral_error = "The widget could not be added to the V1 layout."
    capacity_error = (
        "V1 has no free extension slot. Remove an active added plugin or free "
        "a V1 extension slot under Bars."
    )
    if branch.count(neutral_error) != 1 or capacity_error in branch:
        raise AssertionError("Bug 049 G16-G18 failure text is not neutral")
    if panel_source.count(neutral_error) != 1 or panel_source.count(capacity_error) != 1:
        raise AssertionError("Bug 049 changed failure text outside G16-G18")


class Bug049StaticRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bar_source = (
            REPO_ROOT / "hancore.shibumi.bar/Bar.qml"
        ).read_text(encoding="utf-8")
        cls.panel_source = (
            REPO_ROOT / "hancore.shibumi.control-center/ControlCenterPanel.qml"
        ).read_text(encoding="utf-8")
        cls.resolver_source = (
            REPO_ROOT
            / "hancore.shibumi.bar/services/HostWidgetResolver.qml"
        ).read_text(encoding="utf-8")

    def mutated_bar(self, old: str, new: str) -> str:
        self.assertEqual(self.bar_source.count(old), 1)
        return self.bar_source.replace(old, new, 1)

    def validate(self, bar_source: str, resolver_source: str | None = None) -> None:
        validate_bug049_static_contract(
            bar_source, self.panel_source, resolver_source or self.resolver_source
        )

    def test_product_sources_match_narrow_reactivation_contract(self) -> None:
        self.validate(self.bar_source)

    def test_reverted_enabled_guard_is_detected(self) -> None:
        reverted = self.mutated_bar(
            BUG049_REACTIVATION_GUARD,
            """    return !!(row && row.id === id && row.enabled === false
      && Array.isArray(row.kinds) && row.kinds.indexOf("bar-widget") >= 0)
""",
        )
        with self.assertRaisesRegex(AssertionError, "narrow enabled-row exception"):
            self.validate(reverted)

    def test_missing_component_authority_is_detected(self) -> None:
        weakened = self.mutated_bar(
            "        && registeredWidgetComponent(id) !== null))\n",
            "        && true))\n",
        )
        with self.assertRaisesRegex(AssertionError, "narrow enabled-row exception"):
            self.validate(weakened)

    def test_wrong_component_metadata_identity_is_detected(self) -> None:
        weakened = self.resolver_source.replace(
            "entry.metadata.pluginId === key", "true", 1
        )
        with self.assertRaisesRegex(AssertionError, "exact metadata identity"):
            self.validate(self.bar_source, weakened)

    def test_missing_busy_admission_is_detected(self) -> None:
        weakened = self.mutated_bar(
            "    if (!suiteHostShell.scoped || !layoutTransitionsSupported\n"
            "        || layoutTransitionBusy || providerSnapshotTransitionBusy\n",
            "    if (!suiteHostShell.scoped || !layoutTransitionsSupported\n"
            "        || providerSnapshotTransitionBusy\n",
        )
        with self.assertRaisesRegex(
            AssertionError, "admission, busy, and disabled-path checks"
        ):
            self.validate(weakened)

    def test_stale_observation_weakening_is_detected(self) -> None:
        weakened = self.mutated_bar(
            "        || observationValue !== catalogObservation) return false\n",
            ") return false\n",
        )
        with self.assertRaisesRegex(AssertionError, "stale observation refusal"):
            self.validate(weakened)

    def test_disabled_path_weakening_is_detected(self) -> None:
        weakened = self.mutated_bar(
            "    if (installed !== true) return layoutContains(id)\n",
            "    if (installed !== true) return true\n",
        )
        with self.assertRaisesRegex(
            AssertionError, "admission, busy, and disabled-path checks"
        ):
            self.validate(weakened)


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
        self.session_lock_status = unlocked_session_status()
        self.session_lock_failure = ""
        self.session_lock_preflights = 0
        self.events: list[str] = []

    def validate_plugin(self, directory: Path) -> None:
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        if manifest.get("id") == self.fail_validation_plugin:
            raise RuntimeFailure("injected plugin validation failure")
        if manifest.get("id") != directory.name and not directory.name.endswith(
            "." + str(manifest.get("id"))
        ):
            raise RuntimeFailure(f"invalid staged plugin {directory}")

    def require_session_unlocked(self, operation: str) -> None:
        self.session_lock_preflights += 1
        if self.session_lock_failure:
            raise RuntimeFailure(self.session_lock_failure)
        active = [
            name for name, value in self.session_lock_status.items() if value is True
        ]
        if active:
            raise RuntimeFailure(
                f"refusing {operation} while the Omarchy session lock is active "
                f"({', '.join(active)}); unlock the session and retry"
            )

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
        config_path = (
            self.paths.config_file
            if self.paths.config_file.is_file()
            else self.paths.defaults_file
        )
        config = json.loads(config_path.read_text(encoding="utf-8"))
        bar = config.get("bar") if isinstance(config.get("bar"), dict) else {}
        active_bar = str(bar.get("id") or "omarchy.bar")
        actual_namespace = (
            "shibumi-bar"
            if active_bar == "hancore.shibumi.bar"
            else "omarchy-bar"
        )
        if expected_namespace != actual_namespace:
            raise RuntimeFailure(
                f"expected bar layer {expected_namespace!r}, "
                f"found {actual_namespace!r}"
            )

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
        for command in ("omarchy-restart-shell", "omarchy-shell"):
            (bin_dir / command).write_text("#!/bin/sh\n", encoding="utf-8")
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

    def test_session_lock_preflight_accepts_only_explicitly_unlocked_status(
        self,
    ) -> None:
        status = unlocked_session_status()
        self.runtime.run = Mock(return_value=self.result(json.dumps(status)))

        self.runtime.require_session_unlocked("Shibumi update")

        self.runtime.run.assert_called_once_with(
            [str(self.omarchy_root / "bin/omarchy-shell"), "lock", "status"],
            timeout=4,
            check=False,
        )

    def test_session_lock_preflight_rejects_every_active_phase(self) -> None:
        idle = unlocked_session_status()
        for field in SESSION_LOCK_FIELDS:
            with self.subTest(field=field):
                status = dict(idle)
                status[field] = True
                self.runtime.run = Mock(
                    return_value=self.result(json.dumps(status))
                )

                with self.assertRaisesRegex(
                    RuntimeFailure,
                    rf"session lock is active \({field}\)",
                ):
                    self.runtime.require_session_unlocked("Shibumi update")

    def test_session_lock_preflight_fails_closed_for_unknown_status(self) -> None:
        idle = unlocked_session_status()
        cases = (
            self.result("not-json"),
            self.result("[]"),
            self.result(json.dumps({"locked": False})),
            self.result(json.dumps({**idle, "secure": 0})),
            self.result(
                '{"locked":true,"locked":false,"requested":false,'
                '"pending":false,"sessionLocked":false,"secure":false}'
            ),
            *(
                self.result(
                    '{"locked":false,"requested":false,"pending":false,'
                    '"sessionLocked":false,"secure":false,"extra":'
                    + constant
                    + "}"
                )
                for constant in ("NaN", "Infinity", "-Infinity")
            ),
            self.result(stderr="IPC unavailable", returncode=1),
        )
        for result in cases:
            with self.subTest(stdout=result.stdout, returncode=result.returncode):
                self.runtime.run = Mock(return_value=result)
                with self.assertRaisesRegex(
                    RuntimeFailure,
                    "cannot verify that the session is unlocked",
                ):
                    self.runtime.require_session_unlocked("Shibumi update")

        self.runtime.run = Mock(
            side_effect=RuntimeFailure("injected IPC timeout")
        )
        with self.assertRaisesRegex(
            RuntimeFailure,
            "cannot verify that the session is unlocked.*injected IPC timeout",
        ):
            self.runtime.require_session_unlocked("Shibumi update")

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
            self.result(returncode=1, stderr="target unavailable"),
            self.result(),
            self.result(self.instance_json(foreign)),
        ])

        self.runtime.stop_shell(quiet_period=0)

        commands = [call.args[0] for call in self.runtime.run.call_args_list]
        kill = ["quickshell", "kill", "--pid", "100"]
        registry = ["quickshell", "list", "--all", "--json"]
        prepare = [
            "quickshell",
            "ipc",
            "--pid",
            "100",
            "call",
            "shibumi-suite",
            "prepareShutdown",
        ]
        self.assertEqual(commands, [registry, prepare, kill, registry])

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
        shutil.copy2(
            REPO_ROOT / "contracts/lifecycle-predecessors-v1.json",
            self.source / "contracts/lifecycle-predecessors-v1.json",
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

    def close_transaction_descriptors(
        self, transaction: PluginTransaction
    ) -> None:
        descriptors = {
            descriptor
            for descriptor in (
                transaction._config_snapshot_fd,
                transaction._config_parent_fd,
            )
            if descriptor >= 0
        }
        transaction._close_config_parent()
        self.assertEqual(transaction._config_snapshot_fd, -1)
        self.assertEqual(transaction._config_parent_fd, -1)
        for descriptor in descriptors:
            with self.assertRaises(OSError):
                os.fstat(descriptor)

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
        (self.paths.plugin_dir / "local.extra").mkdir(parents=True, exist_ok=True)
        self.assertEqual(
            command_install(self.args(), self.suite, self.paths, self.runtime), 0
        )

    def write_orphan_shibumi_config(self) -> dict[str, object]:
        config = json.loads(self.defaults.read_text(encoding="utf-8"))
        config["bar"]["id"] = "hancore.shibumi.bar"
        config = migrate_state_settings(config)
        state_entry(config)["shibumi"]["orphanSetting"] = {
            "nested": [1, False, "retain"]
        }
        atomic_write(self.paths.config_file, encode_config(config))
        return config

    def test_runtime_paths_reject_symlinked_writable_root_before_mutation(
        self,
    ) -> None:
        for command in (
            "omarchy",
            "omarchy-shell",
            "omarchy-bluetooth-device",
            "omarchy-audio-output-set-default",
            "omarchy-plugin-validate",
        ):
            path = self.paths.omarchy_root / "bin" / command
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("#!/bin/sh\n", encoding="utf-8")
        required_sources = {
            "shell/services/PluginRegistry.qml": (
                "function entryPointUrl\nfunction isEnabled\n"
            ),
            "shell/shell.qml": (
                "function configureBar\ntarget.pluginRegistry = shell.pluginRegistry\n"
            ),
            "shell/Ui/KeyboardPanel.qml": (
                "property var borderSpec:\nBorderSurface {\n"
            ),
        }
        for relative, payload in required_sources.items():
            path = self.paths.omarchy_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(payload, encoding="utf-8")

        external = self.root / "external/omarchy"
        external.mkdir(parents=True)
        sentinel = external / "sentinel"
        sentinel.write_text("preserve\n", encoding="utf-8")
        self.paths.plugin_dir.parent.parent.mkdir(parents=True)
        self.paths.plugin_dir.parent.symlink_to(external, target_is_directory=True)

        with self.assertRaisesRegex(RuntimeFailure, "symlinked Omarchy plugin"):
            self.paths.validate()
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve\n")

    def test_transaction_rejects_unsafe_or_unbounded_live_config(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        external = self.root / "external-shell.json"
        external.write_text("{}\n", encoding="utf-8")
        cases = ("symlink", "fifo", "directory", "oversized")
        for case in cases:
            with self.subTest(case=case):
                if path.is_dir() and not path.is_symlink():
                    path.rmdir()
                elif path.exists() or path.is_symlink():
                    path.unlink()
                if case == "symlink":
                    path.symlink_to(external)
                elif case == "fifo":
                    os.mkfifo(path)
                elif case == "directory":
                    path.mkdir()
                else:
                    path.write_bytes(b"x" * (1024 * 1024 + 1))

                with self.assertRaisesRegex(
                    TransactionError,
                    "live shell config",
                ):
                    PluginTransaction(self.paths, self.runtime)
                self.assertFalse(self.paths.state_dir.exists())

    def test_transaction_fd_relative_config_replace_keeps_private_mode(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        original = b'{"version":1,"generation":"before"}\n'
        updated = b'{"version":1,"generation":"after"}\n'
        path.write_bytes(original)
        path.chmod(0o644)
        transaction = PluginTransaction(self.paths, self.runtime)
        snapshot_descriptor = transaction._config_snapshot_fd
        self.assertGreaterEqual(snapshot_descriptor, 0)

        transaction.write_config(updated)

        self.assertEqual(path.read_bytes(), updated)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        transaction.rollback()
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(transaction._config_snapshot_fd, -1)
        with self.assertRaises(OSError):
            os.fstat(snapshot_descriptor)

    def test_transaction_finish_closes_config_snapshot_binding(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        path.write_bytes(b'{"version":1}\n')
        transaction = PluginTransaction(self.paths, self.runtime)
        snapshot_descriptor = transaction._config_snapshot_fd
        self.assertGreaterEqual(snapshot_descriptor, 0)

        transaction.finish(None, archive_previous=False)

        self.assertTrue(transaction.finished)
        self.assertEqual(transaction._config_snapshot_fd, -1)
        with self.assertRaises(OSError):
            os.fstat(snapshot_descriptor)

    def test_transaction_binds_config_parent_across_rename_and_symlink_swap(
        self,
    ) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        original = b'{"version":1,"owner":"original"}\n'
        foreign = b'{"version":1,"owner":"foreign"}\n'
        path.write_bytes(original)
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        journal_before = transaction.journal_file.read_bytes()
        events_before = list(self.runtime.events)

        authorized_parent = path.parent.with_name("authorized-omarchy")
        path.parent.rename(authorized_parent)
        foreign_parent = self.root / "foreign/omarchy"
        foreign_parent.mkdir(parents=True)
        foreign_path = foreign_parent / path.name
        foreign_path.write_bytes(foreign)
        path.parent.symlink_to(foreign_parent, target_is_directory=True)

        with self.assertRaisesRegex(TransactionError, "config parent"):
            transaction.stop_shell()
        with self.assertRaisesRegex(TransactionError, "config parent"):
            transaction.write_config(b'{"version":1,"owner":"transaction"}\n')
        with self.assertRaisesRegex(TransactionError, "config parent"):
            transaction.rollback()

        original_path = authorized_parent / path.name
        self.assertEqual(original_path.read_bytes(), original)
        self.assertEqual(foreign_path.read_bytes(), foreign)
        self.assertEqual(self.runtime.events, events_before)
        self.assertNotEqual(transaction.journal_file.read_bytes(), journal_before)
        self.assertEqual(
            json.loads(transaction.journal_file.read_text(encoding="utf-8"))["phase"],
            "recovery-required",
        )

        self.close_transaction_descriptors(transaction)
        with self.assertRaisesRegex(TransactionError, "config parent"):
            recover_transactions(self.paths, self.runtime)
        self.assertEqual(original_path.read_bytes(), original)
        self.assertEqual(foreign_path.read_bytes(), foreign)
        self.assertEqual(self.runtime.events, events_before)
        self.assertTrue(transaction.journal_file.is_file())

    def test_admission_rejects_malformed_config_parent_identity(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        path.write_bytes(b'{"version":1}\n')
        transaction = PluginTransaction(self.paths, self.runtime)
        journal = json.loads(
            transaction.journal_file.read_text(encoding="utf-8")
        )
        journal["configParentIdentity"]["inode"] = True
        atomic_write(
            transaction.journal_file,
            (json.dumps(journal, sort_keys=True) + "\n").encode("utf-8"),
        )

        with self.assertRaisesRegex(AdmissionError, "parent identity is malformed"):
            preflight_lifecycle_state(
                self.paths, self.suite, allow_pending_recovery=True
            )

        self.assertTrue(transaction.journal_file.is_file())
        self.assertEqual(path.read_bytes(), b'{"version":1}\n')
        self.assertEqual(self.runtime.events, [])
        transaction._close_config_parent()

    def test_recovery_rejects_regular_config_parent_swap_before_mutation(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        original = b'{"version":1,"owner":"original"}\n'
        updated = b'{"version":1,"owner":"transaction"}\n'
        foreign = b'{"version":1,"owner":"foreign"}\n'
        path.write_bytes(original)
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stop_shell()
        transaction.write_config(updated)
        transaction._close_config_parent()

        admitted_parent = path.parent.with_name("admitted-omarchy")
        path.parent.rename(admitted_parent)
        path.parent.mkdir()
        path.write_bytes(foreign)
        events_before = list(self.runtime.events)

        with self.assertRaisesRegex(TransactionError, "config parent identity"):
            recover_transactions(self.paths, self.runtime)

        self.assertEqual((admitted_parent / path.name).read_bytes(), updated)
        self.assertEqual(path.read_bytes(), foreign)
        self.assertEqual(self.runtime.events, events_before)
        self.assertTrue(transaction.journal_file.is_file())
        self.assertEqual(list(path.parent.glob(f".{path.name}.*")), [])

    def test_config_write_limit_precedes_mutation_and_accepts_exact_boundary(
        self,
    ) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        original = b'{"version":1}\n'
        path.write_bytes(original)

        exact = PluginTransaction(self.paths, self.runtime)
        exact.write_config(b"x" * MAX_STATE_BYTES)
        self.assertEqual(path.stat().st_size, MAX_STATE_BYTES)
        exact.rollback()
        self.assertEqual(path.read_bytes(), original)

        compact = json.dumps(
            {
                "version": 1,
                "plugins": [],
                "bar": {"layout": {"left": [], "center": [], "right": []}},
                "foreign": [0] * 180000,
            },
            separators=(",", ":"),
        ).encode("utf-8")
        encoded = encode_config(json.loads(compact))
        self.assertLessEqual(len(compact), MAX_STATE_BYTES)
        self.assertGreater(len(encoded), MAX_STATE_BYTES)
        path.write_bytes(compact)
        transaction = PluginTransaction(self.paths, self.runtime)
        journal_before = transaction.journal_file.read_bytes()
        entries_before = sorted(item.name for item in path.parent.iterdir())
        events_before = list(self.runtime.events)

        with self.assertRaisesRegex(TransactionError, "payload exceeds"):
            transaction.write_config(encoded)

        self.assertEqual(path.read_bytes(), compact)
        self.assertEqual(transaction.journal_file.read_bytes(), journal_before)
        self.assertEqual(
            sorted(item.name for item in path.parent.iterdir()), entries_before
        )
        self.assertEqual(self.runtime.events, events_before)
        transaction.rollback()

    def test_atomic_config_replace_defensively_rejects_oversized_payload(
        self,
    ) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        original = b'{"version":1}\n'
        path.write_bytes(original)
        parent_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            with self.assertRaisesRegex(TransactionError, "payload exceeds"):
                transaction_module._atomic_replace_at(
                    parent_fd, path.name, b"x" * (MAX_STATE_BYTES + 1)
                )
        finally:
            os.close(parent_fd)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(list(path.parent.glob(f".{path.name}.*")), [])

    def test_transaction_rejects_live_config_changed_during_bounded_read(
        self,
    ) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        path.write_bytes(b"x" * 70000)
        original_read = transaction_module.os.read
        changed = False

        def read_then_change(descriptor: int, size: int) -> bytes:
            nonlocal changed
            block = original_read(descriptor, size)
            if not changed:
                with path.open("ab") as stream:
                    stream.write(b"foreign")
                changed = True
            return block

        with (
            patch.object(transaction_module.os, "read", side_effect=read_then_change),
            self.assertRaisesRegex(TransactionError, "changed or exceeded bounds"),
        ):
            PluginTransaction(self.paths, self.runtime)
        self.assertTrue(changed)
        self.assertFalse(self.paths.state_dir.exists())

    def test_payload_identity_uses_owner_execute_bit(self) -> None:
        published = self.packaged_suite(
            version="0.1.1-beta.15.2", source_revision=PUBLISHED_BETA152_REVISION
        )
        (self.source / "PACKAGE-METADATA.json").unlink()
        published.revision = Mock(return_value=PUBLISHED_BETA152_REVISION)
        identity = next(item for item in supported_install_identities(self.suite)
                        if item["id"] == "public-beta.15.2")
        health_digest = runpy.run_path(str(
            REPO_ROOT / "hancore.shibumi.control-center/manager/shibumi-health"
        ))["payload_digest"]
        for mode in (0o755, 0o700):
            for plugin_id, spec in published.plugins.items():
                for path in spec.source.rglob("*"):
                    if path.is_file() and path.stat().st_mode & 0o100:
                        path.chmod(mode)
                digests = (
                    plugin_payload_digest(spec.source),
                    _bounded_plugin_payload_digest(
                        spec.source, {"entries": 0, "bytes": 0}
                    ),
                    health_digest(spec.source),
                )
                for probe, actual in zip(("model", "admission", "health"), digests):
                    with self.subTest(mode=oct(mode), plugin=plugin_id, probe=probe):
                        self.assertEqual(actual, identity["pluginDigests"][plugin_id])
        self.assertEqual(
            command_install(self.args(), published, self.paths, self.runtime), 0
        )
        self.assertEqual(
            preflight_lifecycle_state(self.paths, self.suite), "public-beta.15.2"
        )

    def test_exact_beta141_package_identity_is_admitted(self) -> None:
        packaged_suite = self.packaged_suite(
            version="0.1.1-beta.14.1",
            source_revision=PUBLISHED_BETA141_REVISION,
        )
        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.14.1"
        )
        self.assertEqual(
            command_install(self.args(), packaged_suite, self.paths, self.runtime),
            0,
        )
        self.assertEqual(
            preflight_lifecycle_state(self.paths, packaged_suite),
            "public-beta.14.1",
        )

        contract = json.loads(
            (self.source / "contracts/lifecycle-predecessors-v1.json").read_text(
                encoding="utf-8"
            )
        )
        source_beta14 = next(
            item for item in contract["states"] if item["id"] == "source-beta.14"
        )
        old_revision = "11c9f63147ffea3265bdff442bb556f23700d209"
        self.assertIn(old_revision, source_beta14["sourceRevisions"])

        state_path = self.paths.state_dir / "install.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["suiteVersion"] = source_beta14["suiteVersion"]
        state["installOrigin"] = "checkout"
        state["sourceRoot"] = str(self.source.resolve())
        state.pop("packageName")
        state.pop("packageVersion")
        state["sourceRevision"] = old_revision
        state["payloadDigest"] = source_beta14["payloadDigest"]
        state["pluginDigests"] = dict(source_beta14["pluginDigests"])
        atomic_write(
            state_path,
            (json.dumps(state, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        )
        for plugin_id in state["plugins"]:
            marker_path = self.paths.plugin_dir / plugin_id / ".shibumi-managed.json"
            marker = json.loads(marker_path.read_text(encoding="utf-8"))
            marker["suiteVersion"] = source_beta14["suiteVersion"]
            marker["sourceRevision"] = old_revision
            marker["payloadDigest"] = source_beta14["pluginDigests"][plugin_id]
            marker["suitePayloadDigest"] = source_beta14["payloadDigest"]
            atomic_write(
                marker_path,
                (json.dumps(marker, indent=2, sort_keys=True) + "\n").encode(
                    "utf-8"
                ),
            )

        with self.assertRaisesRegex(AdmissionError, "live plugin marker or payload"):
            preflight_lifecycle_state(self.paths, packaged_suite)
        self.assertEqual(
            preflight_lifecycle_state(
                self.paths, packaged_suite, allow_payload_repair=True
            ),
            "source-beta.14",
        )
        self.assertEqual(
            command_repair(self.args(), packaged_suite, self.paths, self.runtime),
            0,
        )
        self.assertEqual(
            preflight_lifecycle_state(self.paths, packaged_suite),
            "public-beta.14.1",
        )

    def assert_published_checkout_can_update_from_tag(
        self, tag: str, revision: str, identity_id: str
    ) -> None:
        source_root = self.root / "published-tag-source"
        source_root.mkdir()
        resolved = subprocess.run(
            ["git", "--no-replace-objects", "rev-parse", f"refs/tags/{tag}^{{commit}}"],
            cwd=REPO_ROOT,
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        self.assertEqual(resolved, revision)
        archive = subprocess.run(
            [
                "git", "--no-replace-objects", "archive", "--format=tar",
                revision, "--", "contracts/plugin-suite-v1.json",
                *self.suite.plugins.keys(),
            ],
            cwd=REPO_ROOT,
            check=True,
            stdout=subprocess.PIPE,
        ).stdout
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
            stream.extractall(source_root, filter="data")
        published = Suite.load(source_root)
        published.revision = Mock(return_value=revision)  # type: ignore[method-assign]

        self.assertEqual(
            command_install(self.args(), published, self.paths, self.runtime), 0
        )
        installed = load_install_state(self.paths, published)
        self.assertEqual(installed["sourceRevision"], revision)
        self.assertEqual(installed["installOrigin"], "checkout")
        # Admit the old on-disk plugin markers before any mutation begins.
        self.assertEqual(
            preflight_lifecycle_state(self.paths, self.suite), identity_id
        )
        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )
        updated = load_install_state(self.paths, self.suite)
        self.assertEqual(updated["suiteVersion"], self.suite.version)
        self.assertEqual(updated["installOrigin"], "checkout")
        self.assertNotEqual(updated["sourceRevision"], revision)

    def test_published_beta15_checkout_can_update_from_its_tag(self) -> None:
        self.assert_published_checkout_can_update_from_tag(
            "v0.1.1-beta.15", PUBLISHED_BETA15_REVISION, "public-beta.15"
        )

    def test_published_beta151_checkout_can_update_from_its_tag(self) -> None:
        self.assert_published_checkout_can_update_from_tag(
            "v0.1.1-beta.15.1", PUBLISHED_BETA151_REVISION, "public-beta.15.1"
        )

    def test_published_beta152_checkout_can_update_from_its_tag(self) -> None:
        self.assert_published_checkout_can_update_from_tag(
            "v0.1.1-beta.15.2", PUBLISHED_BETA152_REVISION, "public-beta.15.2"
        )

    def test_admitted_beta15_merge_payloads_match_their_exact_tags(self) -> None:
        releases = (
            (PUBLISHED_BETA15_REVISION, (
                "91b2cd0f886c15962a2627aea3269f4c09cae828",
                "7c0499289c48b9f4b3dfd28687a23824e752f15d",
            )),
            (PUBLISHED_BETA151_REVISION, (
                "533110d7abda296b56369f304a618f9313e1f12f",
            )),
            (PUBLISHED_BETA152_REVISION, (
                "aaf7611d66ed5f99078fc5419bc3ba4db6164bed",
            )),
        )
        payload_paths = ["contracts/plugin-suite-v1.json", *self.suite.plugins]
        for tag_revision, merges in releases:
            for merge_revision in merges:
                with self.subTest(tag=tag_revision, merge=merge_revision):
                    result = subprocess.run(
                        [
                            "git", "--no-replace-objects", "diff", "--exit-code",
                            tag_revision, merge_revision, "--", *payload_paths,
                        ],
                        cwd=REPO_ROOT,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_exact_beta15_package_identity_is_admitted(self) -> None:
        packaged_suite = self.packaged_suite(
            version="0.1.1-beta.15",
            source_revision=PUBLISHED_BETA15_REVISION,
        )

        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.15"
        )
        beta15 = next(
            item
            for item in supported_install_identities(packaged_suite)
            if item["id"] == "public-beta.15"
        )
        self.assertEqual(
            suite_payload_digest({
                plugin_id: spec.payload_digest()
                for plugin_id, spec in packaged_suite.plugins.items()
            }),
            beta15["payloadDigest"],
        )
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertEqual(self.runtime.events, [])

    def test_exact_beta151_package_identity_is_admitted(self) -> None:
        packaged_suite = self.packaged_suite(
            version="0.1.1-beta.15.1",
            source_revision=PUBLISHED_BETA151_REVISION,
        )

        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.15.1"
        )
        beta151 = next(
            item
            for item in supported_install_identities(packaged_suite)
            if item["id"] == "public-beta.15.1"
        )
        self.assertEqual(
            suite_payload_digest({
                plugin_id: spec.payload_digest()
                for plugin_id, spec in packaged_suite.plugins.items()
            }),
            beta151["payloadDigest"],
        )
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertEqual(self.runtime.events, [])

    def test_exact_beta152_package_identity_is_admitted(self) -> None:
        packaged_suite = self.packaged_suite(
            version="0.1.1-beta.15.2",
            source_revision=PUBLISHED_BETA152_REVISION,
        )

        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.15.2"
        )
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertEqual(self.runtime.events, [])

    def test_exact_beta153_package_identity_is_admitted(self) -> None:
        packaged_suite = self.packaged_suite()
        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.15.3"
        )
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertEqual(self.runtime.events, [])

    def test_beta153_package_rejects_byte_and_mode_drift(self) -> None:
        packaged_suite = self.packaged_suite()
        drift_path = self.source / "hancore.shibumi.bar/Bar.qml"
        payload = drift_path.read_bytes()
        mode = stat.S_IMODE(drift_path.stat().st_mode)
        for mutation in ("bytes", "mode"):
            with self.subTest(mutation=mutation):
                self.assertEqual(
                    require_current_payload_identity(packaged_suite), "public-beta.15.3"
                )
                try:
                    if mutation == "bytes":
                        replacement = b" " if payload[-1:] != b" " else b"\n"
                        drift_path.write_bytes(payload[:-1] + replacement)
                    else:
                        drift_path.chmod(mode ^ stat.S_IXUSR)
                    with self.assertRaisesRegex(
                        AdmissionError, "exact declared revision identity"
                    ):
                        require_current_payload_identity(packaged_suite)
                    self.assertFalse(self.paths.state_dir.exists())
                    self.assertFalse(self.paths.plugin_dir.exists())
                    self.assertFalse(self.paths.config_file.exists())
                    self.assertEqual(self.runtime.events, [])
                finally:
                    drift_path.write_bytes(payload)
                    drift_path.chmod(mode)
        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.15.3"
        )

    def test_mutated_beta151_package_bytes_are_rejected(self) -> None:
        packaged_suite = self.packaged_suite(
            version="0.1.1-beta.15.1",
            source_revision=PUBLISHED_BETA151_REVISION,
        )
        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.15.1"
        )
        drift_path = self.source / "hancore.shibumi.bar/Bar.qml"
        payload = drift_path.read_bytes()
        replacement = b" " if payload[-1:] != b" " else b"\n"
        drift_path.write_bytes(payload[:-1] + replacement)

        with self.assertRaisesRegex(
            AdmissionError, "exact declared revision identity"
        ):
            require_current_payload_identity(packaged_suite)
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertEqual(self.runtime.events, [])

    def test_mutated_beta151_package_mode_is_rejected(self) -> None:
        packaged_suite = self.packaged_suite(
            version="0.1.1-beta.15.1",
            source_revision=PUBLISHED_BETA151_REVISION,
        )
        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.15.1"
        )
        drift_path = self.source / "hancore.shibumi.bar/Bar.qml"
        drift_path.chmod(drift_path.stat().st_mode | stat.S_IXUSR)

        with self.assertRaisesRegex(
            AdmissionError, "exact declared revision identity"
        ):
            require_current_payload_identity(packaged_suite)
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertEqual(self.runtime.events, [])

    def test_mutated_beta141_package_identity_is_rejected(self) -> None:
        packaged_suite = self.packaged_suite(
            version="0.1.1-beta.14.1",
            source_revision=PUBLISHED_BETA141_REVISION,
        )
        self.assertEqual(
            require_current_payload_identity(packaged_suite), "public-beta.14.1"
        )
        drift_path = self.source / "hancore.shibumi.bar/Bar.qml"
        payload = drift_path.read_bytes()
        replacement = b" " if payload[-1:] != b" " else b"\n"
        drift_path.write_bytes(payload[:-1] + replacement)

        with self.assertRaisesRegex(
            AdmissionError, "exact declared revision identity"
        ):
            require_current_payload_identity(packaged_suite)
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertEqual(self.runtime.events, [])

    def test_unknown_future_package_identity_is_rejected(self) -> None:
        packaged_suite = self.packaged_suite("0.1.1-beta.15.4")

        with self.assertRaisesRegex(
            AdmissionError, "exact declared revision identity"
        ):
            require_current_payload_identity(packaged_suite)
        self.assertFalse(self.paths.state_dir.exists())
        self.assertFalse(self.paths.plugin_dir.exists())
        self.assertFalse(self.paths.config_file.exists())
        self.assertEqual(self.runtime.events, [])

    def test_fresh_install_does_not_create_stock_transparency_preference(
        self,
    ) -> None:
        defaults = json.loads(self.defaults.read_text(encoding="utf-8"))
        defaults["bar"]["transparent"] = False
        self.defaults.write_text(
            json.dumps(defaults, indent=2) + "\n", encoding="utf-8"
        )
        self.assertFalse(self.paths.config_file.exists())

        self.install()
        installed = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        state = load_install_state(self.paths, self.suite)
        self.assertNotIn("transparent", installed["bar"])
        self.assertNotIn("transparent", state["previousBar"])

        self.assertEqual(
            command_uninstall(self.args(), self.suite, self.paths, self.runtime), 0
        )
        uninstalled = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        self.assertNotIn("transparent", uninstalled["bar"])

    def test_orphan_install_deactivate_restores_implicit_stock_bar_and_settings(
        self,
    ) -> None:
        self.write_orphan_shibumi_config()
        expected_bar = copy.deepcopy(
            json.loads(self.defaults.read_text(encoding="utf-8"))["bar"]
        )
        expected_bar["id"] = "omarchy.bar"

        self.install()
        self.assertEqual(
            load_install_state(self.paths, self.suite)["previousBar"], expected_bar
        )
        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime), 0
        )

        restored = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        expected_bar["layout"]["left"].append(
            {"id": "hancore.shibumi.control-center"}
        )
        self.assertEqual(restored["bar"], expected_bar)
        self.assertEqual(
            state_entry(restored)["shibumi"]["orphanSetting"],
            {"nested": [1, False, "retain"]},
        )

    def test_orphan_install_uninstall_restores_explicit_stock_bar_and_settings(
        self,
    ) -> None:
        defaults = json.loads(self.defaults.read_text(encoding="utf-8"))
        defaults["bar"]["id"] = "omarchy.bar"
        atomic_write(self.defaults, encode_config(defaults))
        self.write_orphan_shibumi_config()

        self.install()
        self.assertEqual(
            load_install_state(self.paths, self.suite)["previousBar"], defaults["bar"]
        )
        self.assertEqual(
            command_uninstall(
                self.args(keep_settings=True), self.suite, self.paths, self.runtime
            ),
            0,
        )

        restored = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(restored["bar"], defaults["bar"])
        self.assertEqual(
            state_entry(restored)["shibumi"]["orphanSetting"],
            {"nested": [1, False, "retain"]},
        )

    def test_orphan_install_rejects_invalid_host_defaults_before_mutation(
        self,
    ) -> None:
        self.write_orphan_shibumi_config()
        original_config = self.paths.config_file.read_bytes()
        valid = json.loads(self.defaults.read_text(encoding="utf-8"))
        cases = {
            "absent": None,
            "invalid-json": b"{",
            "no-bar": encode_config({"version": 1, "plugins": []}),
            "null-id": encode_config({**valid, "bar": {**valid["bar"], "id": None}}),
            "empty-id": encode_config({**valid, "bar": {**valid["bar"], "id": ""}}),
            "foreign-id": encode_config(
                {**valid, "bar": {**valid["bar"], "id": "third.party.bar"}}
            ),
        }

        for label, payload in cases.items():
            with self.subTest(case=label):
                if payload is None:
                    self.defaults.unlink(missing_ok=True)
                else:
                    self.defaults.write_bytes(payload)
                with self.assertRaises(ConfigError):
                    command_install(self.args(), self.suite, self.paths, self.runtime)
                self.assertEqual(self.paths.config_file.read_bytes(), original_config)
                self.assertEqual(self.runtime.events, [])
                self.assertFalse(self.paths.plugin_dir.exists())
                self.assertFalse(self.paths.state_dir.exists())

    def test_orphan_external_install_never_records_shibumi_as_previous_bar(
        self,
    ) -> None:
        self.write_orphan_shibumi_config()
        expected = copy.deepcopy(
            json.loads(self.defaults.read_text(encoding="utf-8"))["bar"]
        )
        expected["id"] = "omarchy.bar"

        self.assertEqual(
            command_install(
                self.args(no_activate=True, keep_layout=True),
                self.suite,
                self.paths,
                self.runtime,
            ),
            0,
        )

        state = load_install_state(self.paths, self.suite)
        self.assertEqual(state["previousBar"], expected)
        installed = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(installed["bar"]["id"], "hancore.shibumi.bar")
        self.assertEqual(state["activation"]["mode"], "external")

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

    def packaged_suite(
        self,
        version: str = "0.1.1-beta.15.3",
        source_revision: str | None = None,
    ) -> Suite:
        suite_contract_path = self.source / "contracts/plugin-suite-v1.json"
        suite_contract = json.loads(suite_contract_path.read_text(encoding="utf-8"))
        plugin_ids = [item["id"] for item in suite_contract["plugins"]]
        metadata_source = REPO_ROOT / "packaging/package-metadata.json"
        if source_revision is not None:
            for plugin_id in plugin_ids:
                shutil.rmtree(self.source / plugin_id)
            archive = subprocess.run(
                [
                    "git",
                    "--no-replace-objects",
                    "-C",
                    str(REPO_ROOT),
                    "archive",
                    source_revision,
                    "--",
                    *plugin_ids,
                    "contracts/plugin-suite-v1.json",
                    "packaging/package-metadata.json",
                ],
                check=True,
                stdout=subprocess.PIPE,
            ).stdout
            with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as bundle:
                bundle.extractall(self.source, filter="data")
            metadata_source = self.source / "packaging/package-metadata.json"
            suite_contract = json.loads(
                suite_contract_path.read_text(encoding="utf-8")
            )

        metadata_path = self.source / "PACKAGE-METADATA.json"
        shutil.copy2(metadata_source, metadata_path)
        suite_contract["suiteVersion"] = version
        suite_contract_path.write_text(
            json.dumps(suite_contract, indent=2) + "\n", encoding="utf-8"
        )
        package_metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        package_metadata["version"] = version
        metadata_path.write_text(
            json.dumps(package_metadata, indent=2) + "\n", encoding="utf-8"
        )
        return Suite.load(self.source)

    def create_quattro_host_contract(self) -> None:
        bin_dir = self.paths.omarchy_root / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        for command in (
            "omarchy",
            "omarchy-shell",
            "omarchy-plugin-validate",
            "omarchy-bluetooth-device",
            "omarchy-audio-output-set-default",
        ):
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

    @staticmethod
    def tree_snapshot(
        root: Path,
    ) -> tuple[tuple[str, str, bytes | str | None], ...]:
        entries: list[tuple[str, str, bytes | str | None]] = []

        def visit(path: Path, relative: str) -> None:
            if path.is_symlink():
                entries.append((relative, "symlink", str(path.readlink())))
            elif path.is_dir():
                entries.append((relative, "directory", None))
                for child in sorted(path.iterdir(), key=lambda item: item.name):
                    visit(child, str(child.relative_to(root)))
            elif path.is_file():
                entries.append((relative, "file", path.read_bytes()))
            elif path.exists():
                entries.append((relative, "other", None))

        visit(root, ".")
        return tuple(entries)

    def managed_state_snapshot(self) -> dict[str, object]:
        return {
            "plugins": self.tree_snapshot(self.paths.plugin_dir),
            "config": self.tree_snapshot(self.paths.config_file),
            "state": self.tree_snapshot(self.paths.state_dir),
            "menuExtension": self.tree_snapshot(
                self.paths.menu_extension_file
            ),
        }

    def runtime_activity_snapshot(self) -> dict[str, object]:
        return {
            "events": tuple(self.runtime.events),
            "rescans": self.runtime.rescans,
            "reloads": self.runtime.reloads,
            "restarts": self.runtime.restarts,
            "stops": self.runtime.stops,
            "payloadReloads": self.runtime.payload_reloads,
            "menuRefreshes": self.runtime.menu_refreshes,
            "shellRunning": self.runtime.shell_running,
        }

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
        self.assertEqual(state["packageVersion"], "0.1.1-beta.15.3")
        self.assertEqual(state["sourceRevision"], "package:0.1.1-beta.15.3")
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
        self.assertEqual(package_state["packageVersion"], "0.1.1-beta.15.3")
        self.assertNotIn("sourceRoot", package_state)

    def test_sandbox_update_advances_beta_7_to_beta_9(self) -> None:
        beta7_source = self.root / "beta7-source"
        beta7_source.mkdir()
        archive = subprocess.run(
            [
                "git",
                "archive",
                "--format=tar",
                "v0.1.1-beta.7",
                "contracts/plugin-suite-v1.json",
                *self.suite.plugins.keys(),
            ],
            cwd=REPO_ROOT,
            check=True,
            stdout=subprocess.PIPE,
        ).stdout
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
            stream.extractall(beta7_source, filter="data")
        beta7_suite = Suite.load(beta7_source)
        control_id = "hancore.shibumi.control-center"
        self.assertEqual(beta7_suite.version, "0.1.1-beta.7")
        self.assertNotIn("service", beta7_suite.plugins[control_id].kinds)
        self.assertIn("service", self.suite.plugins[control_id].kinds)
        self.assertNotEqual(
            beta7_suite.plugins[control_id].payload_digest(),
            self.suite.plugins[control_id].payload_digest(),
        )

        self.assertEqual(
            command_install(self.args(), beta7_suite, self.paths, self.runtime),
            0,
        )
        config = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        config["bar"].setdefault("shibumi", {})["layoutProtection"] = {
            "v1": True,
            "v2": False,
        }
        atomic_write(self.paths.config_file, encode_config(config))
        state_before = self.managed_state_snapshot()
        activity_before = self.runtime_activity_snapshot()
        self.assertEqual(self.hidden_transaction_paths(), [])

        self.assertEqual(
            command_update(
                self.args(dry_run=True),
                self.suite,
                self.paths,
                self.runtime,
            ),
            0,
        )
        self.assertEqual(self.managed_state_snapshot(), state_before)
        self.assertEqual(self.runtime_activity_snapshot(), activity_before)
        self.assertEqual(self.hidden_transaction_paths(), [])

        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        updated = load_install_state(self.paths, self.suite)
        updated_config = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        expected_digests = {
            plugin_id: spec.payload_digest()
            for plugin_id, spec in self.suite.plugins.items()
        }
        self.assertEqual(updated["suiteVersion"], "0.1.1-beta.15.3")
        self.assertEqual(updated["sourceRoot"], str(self.source.resolve()))
        self.assertEqual(updated["pluginDigests"], expected_digests)
        self.assertEqual(len(updated["plugins"]), 24)
        self.assertEqual(
            state_entry(updated_config)["shibumi"]["layoutProtection"],
            {"v1": True, "v2": False},
        )
        control_plugin = self.runtime.list_plugins()[control_id]
        self.assertTrue(control_plugin["enabled"])
        self.assertIn("service", control_plugin["kinds"])
        self.assertEqual(self.hidden_transaction_paths(), [])
        for plugin_id in updated["plugins"]:
            manifest = json.loads(
                (self.paths.plugin_dir / plugin_id / "manifest.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(manifest["version"], "0.1.1-beta.15.3")

    def test_locked_update_discards_staging_without_live_reconciliation(self) -> None:
        self.install()
        source_file = self.source / "hancore.shibumi.center" / "BarWidget.qml"
        source_file.write_text(
            source_file.read_text(encoding="utf-8")
            + "\n// update blocked by active lock\n",
            encoding="utf-8",
        )
        self.suite = Suite.load(self.source)
        state_before = self.managed_state_snapshot()
        activity_before = self.runtime_activity_snapshot()
        preflights_before = self.runtime.session_lock_preflights
        self.runtime.session_lock_status["pending"] = True
        original_preflight = self.runtime.require_session_unlocked
        staged_plugin_ids: set[str] = set()

        def reject_locked_update(operation: str) -> None:
            nonlocal staged_plugin_ids
            staged_plugin_ids = {
                str(json.loads(
                    (path / "manifest.json").read_text(encoding="utf-8")
                )["id"])
                for path in self.paths.plugin_dir.glob(".shibumi-stage.*")
                if path.is_dir()
            }
            original_preflight(operation)

        with patch.object(
            self.runtime,
            "require_session_unlocked",
            side_effect=reject_locked_update,
        ):
            with self.assertRaisesRegex(
                RuntimeFailure,
                r"session lock is active \(pending\)",
            ):
                command_update(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(staged_plugin_ids, set(self.suite.plugins))
        self.assertEqual(self.managed_state_snapshot(), state_before)
        self.assertEqual(self.runtime_activity_snapshot(), activity_before)
        self.assertEqual(
            self.runtime.session_lock_preflights, preflights_before + 1
        )

    def test_interrupted_locked_update_recovers_without_live_reconciliation(
        self,
    ) -> None:
        self.install()
        state_before = self.managed_state_snapshot()
        activity_before = self.runtime_activity_snapshot()
        self.runtime.session_lock_status["secure"] = True

        with patch.object(
            PluginTransaction,
            "_cleanup_transaction",
            side_effect=OSError("injected interrupted pre-exposure cleanup"),
        ):
            with self.assertRaisesRegex(
                OSError,
                "injected interrupted pre-exposure cleanup",
            ):
                command_update(self.args(), self.suite, self.paths, self.runtime)

        journals = list(
            (self.paths.state_dir / "transactions").glob("*/journal.json")
        )
        self.assertEqual(len(journals), 1)
        journal = json.loads(journals[0].read_text(encoding="utf-8"))
        self.assertEqual(journal["phase"], "recovery-required")
        self.assertIs(journal["liveMutationStarted"], False)
        self.assertTrue(self.hidden_transaction_paths())

        self.assertEqual(recover_transactions(self.paths, self.runtime), 1)

        self.assertEqual(self.managed_state_snapshot(), state_before)
        self.assertEqual(self.runtime_activity_snapshot(), activity_before)

    def test_failed_stop_intent_write_never_drains_shell(self) -> None:
        self.install()
        transaction = PluginTransaction(
            self.paths,
            self.runtime,
            restart_on_reconcile=True,
        )
        original_write = transaction._write_journal
        stops_before = self.runtime.stops

        def fail_stop_intent(
            phase: str,
            desired_state: object = "unchanged",
            archive_previous: object = "unchanged",
        ) -> None:
            if phase == "stopping-shell":
                raise OSError("injected stopping-shell journal failure")
            original_write(phase, desired_state, archive_previous)

        with patch.object(
            transaction, "_write_journal", side_effect=fail_stop_intent
        ):
            with self.assertRaisesRegex(
                OSError, "injected stopping-shell journal failure"
            ):
                with transaction:
                    transaction.stop_shell()

        self.assertEqual(self.runtime.stops, stops_before)
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(transaction.transaction_dir.exists())
        self.assertFalse(self.hidden_transaction_paths())

    def test_shell_stop_intent_is_durable_before_runtime_drain(self) -> None:
        self.install()
        state_before = self.managed_state_snapshot()
        activity_before = self.runtime_activity_snapshot()
        transaction = PluginTransaction(
            self.paths,
            self.runtime,
            restart_on_reconcile=True,
        )
        observed_journal: dict[str, object] = {}

        def interrupted_stop() -> None:
            nonlocal observed_journal
            observed_journal = json.loads(
                transaction.journal_file.read_text(encoding="utf-8")
            )
            self.runtime.events.append("stop")
            self.runtime.stops += 1
            self.runtime.shell_running = False
            raise RuntimeFailure("injected interruption after shell drain")

        with patch.object(
            self.runtime,
            "stop_shell",
            side_effect=interrupted_stop,
        ):
            with self.assertRaisesRegex(
                RuntimeFailure,
                "injected interruption after shell drain",
            ):
                transaction.stop_shell()

        self.assertEqual(observed_journal["phase"], "stopping-shell")
        self.assertIs(observed_journal["shellStopped"], True)
        self.assertIs(observed_journal["liveMutationStarted"], False)
        self.assertFalse(self.runtime.shell_running)

        self.close_transaction_descriptors(transaction)
        self.assertEqual(recover_transactions(self.paths, self.runtime), 1)

        expected_activity = dict(activity_before)
        expected_activity.update(
            events=(*activity_before["events"], "stop", "stop", "restart"),
            restarts=activity_before["restarts"] + 1,
            stops=activity_before["stops"] + 2,
        )
        self.assertEqual(self.managed_state_snapshot(), state_before)
        self.assertEqual(self.runtime_activity_snapshot(), expected_activity)

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
        self.runtime.fail_restart_count = 1

        with self.assertRaisesRegex(
            RuntimeFailure, "injected shell restart failure"
        ):
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
                state["suiteVersion"] = "0.1.1-beta.15.3+installed.9"
                state_path.write_text(
                    json.dumps(state, indent=2) + "\n", encoding="utf-8"
                )
                self.assertEqual(
                    operation(self.args(), self.suite, self.paths, self.runtime),
                    0,
                )
                updated = json.loads(state_path.read_text(encoding="utf-8"))
                self.assertEqual(updated["suiteVersion"], "0.1.1-beta.15.3")

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
        self.assertEqual(rolled_back["suiteVersion"], "0.1.1-beta.15.3")
        self.assertEqual(rolled_back["packageVersion"], "0.1.1-beta.15.3")
        self.assertEqual(rolled_back["sourceRevision"], "package:0.1.1-beta.15.3")

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

    def test_lifecycle_preserves_enabled_stock_bar_transparency(self) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["transparent"] = True
        atomic_write(self.paths.config_file, encode_config(base))

        self.install()
        installed = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertIs(installed["bar"]["transparent"], True)
        self.assertIs(
            load_install_state(self.paths, self.suite)["previousBar"]["transparent"],
            True,
        )

        self.assertEqual(
            command_update(self.args(), self.suite, self.paths, self.runtime), 0
        )
        updated = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertIs(updated["bar"]["transparent"], True)

        self.assertEqual(
            command_repair(self.args(), self.suite, self.paths, self.runtime), 0
        )
        repaired = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertIs(repaired["bar"]["transparent"], True)

        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        inactive = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(inactive["bar"].get("id", "omarchy.bar"), "omarchy.bar")
        self.assertIs(inactive["bar"]["transparent"], True)

        self.assertEqual(
            command_activate(self.args(), self.suite, self.paths, self.runtime), 0
        )
        active = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(active["bar"]["id"], "hancore.shibumi.bar")
        self.assertIs(active["bar"]["transparent"], True)

    def test_deactivate_uses_current_stock_bar_transparency_preference(
        self,
    ) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["transparent"] = True
        atomic_write(self.paths.config_file, encode_config(base))
        self.install()

        absent = object()
        for index, preference in enumerate((False, True, absent)):
            current = json.loads(
                self.paths.config_file.read_text(encoding="utf-8")
            )
            if preference is absent:
                current["bar"].pop("transparent", None)
            else:
                current["bar"]["transparent"] = preference
            atomic_write(self.paths.config_file, encode_config(current))

            self.assertEqual(
                command_deactivate(
                    self.args(), self.suite, self.paths, self.runtime
                ),
                0,
            )
            inactive = json.loads(
                self.paths.config_file.read_text(encoding="utf-8")
            )
            if preference is absent:
                self.assertNotIn("transparent", inactive["bar"])
            else:
                self.assertIs(inactive["bar"]["transparent"], preference)

            if index < 2:
                self.assertEqual(
                    command_activate(
                        self.args(), self.suite, self.paths, self.runtime
                    ),
                    0,
                )

    def test_deactivate_preserves_true_over_false_transparency_snapshot(
        self,
    ) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["transparent"] = False
        atomic_write(self.paths.config_file, encode_config(base))
        self.install()

        current = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        current["bar"]["transparent"] = True
        atomic_write(self.paths.config_file, encode_config(current))

        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        inactive = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertIs(inactive["bar"]["transparent"], True)

    def test_uninstall_uses_current_stock_bar_transparency_preference(
        self,
    ) -> None:
        absent = object()
        for snapshot, preference in (
            (True, False),
            (False, True),
            (True, absent),
        ):
            base = json.loads(self.defaults.read_text(encoding="utf-8"))
            base["bar"]["transparent"] = snapshot
            atomic_write(self.paths.config_file, encode_config(base))
            self.install()

            current = json.loads(
                self.paths.config_file.read_text(encoding="utf-8")
            )
            if preference is absent:
                current["bar"].pop("transparent", None)
            else:
                current["bar"]["transparent"] = preference
            atomic_write(self.paths.config_file, encode_config(current))

            self.assertEqual(
                command_uninstall(
                    self.args(), self.suite, self.paths, self.runtime
                ),
                0,
            )
            uninstalled = json.loads(
                self.paths.config_file.read_text(encoding="utf-8")
            )
            if preference is absent:
                self.assertNotIn("transparent", uninstalled["bar"])
            else:
                self.assertIs(uninstalled["bar"]["transparent"], preference)

    def test_lifecycle_preserves_disabled_stock_bar_transparency(self) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["transparent"] = False
        atomic_write(self.paths.config_file, encode_config(base))

        self.install()
        for operation in (
            lambda: command_update(
                self.args(), self.suite, self.paths, self.runtime
            ),
            lambda: command_repair(
                self.args(), self.suite, self.paths, self.runtime
            ),
            lambda: command_deactivate(
                self.args(), self.suite, self.paths, self.runtime
            ),
            lambda: command_activate(
                self.args(), self.suite, self.paths, self.runtime
            ),
        ):
            current = json.loads(
                self.paths.config_file.read_text(encoding="utf-8")
            )
            self.assertIs(current["bar"]["transparent"], False)
            self.assertEqual(operation(), 0)
        current = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertIs(current["bar"]["transparent"], False)

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
        result = apply_profile(
            base, profile, self.suite.plugins, self.paths.plugin_dir
        )
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
        result = apply_profile(
            base, profile, self.suite.plugins, self.paths.plugin_dir
        )
        layout_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in result["bar"]["layout"][region]
        }

        self.assertIn("local.extra", layout_ids)
        self.assertFalse(
            any(plugin_id.startswith("omarchy.") for plugin_id in layout_ids)
        )

    def test_install_prunes_only_foreign_layout_ids_without_plugin_directories(
        self,
    ) -> None:
        config = json.loads(self.defaults.read_text(encoding="utf-8"))
        config["bar"]["layout"]["right"].extend([
            {"id": "foreign.orphan"}, {"id": "foreign.installed"},
            {"id": "foreign.file"}, {"id": "foreign.link"},
            {"id": "foreign.dangling"},
            {"id": "hancore.shibumi.bluetooth", "custom": "managed"},
        ])
        atomic_write(self.paths.config_file, encode_config(config))
        self.paths.plugin_dir.mkdir(parents=True)
        (self.paths.plugin_dir / "foreign.installed").mkdir()
        (self.paths.plugin_dir / "foreign.file").write_text("not a plugin\n")
        (self.paths.plugin_dir / "foreign.link").symlink_to("foreign.installed")
        (self.paths.plugin_dir / "foreign.dangling").symlink_to("missing")

        self.assertEqual(
            command_install(self.args(), self.suite, self.paths, self.runtime), 0
        )
        written = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        entries = {
            entry_id(entry): entry
            for region in ("left", "center", "right")
            for entry in written["bar"]["layout"][region]
        }
        self.assertNotIn("foreign.orphan", entries)
        self.assertNotIn("foreign.file", entries)
        self.assertIn("foreign.installed", entries)
        self.assertIn("foreign.link", entries)
        self.assertIn("foreign.dangling", entries)
        self.assertEqual(entries["hancore.shibumi.bluetooth"]["custom"], "managed")

    def test_previous_bar_restore_prunes_orphans_but_unreadable_root_preserves_all(
        self,
    ) -> None:
        self.install()
        state_path = self.paths.state_dir / "install.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["previousBar"]["layout"]["right"].extend([
            {"id": "foreign.restore-orphan"},
            {"id": "omarchy.absent-official"},
        ])
        atomic_write(state_path, encode_config(state))

        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime), 0
        )
        restored = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        restored_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in restored["bar"]["layout"][region]
        }
        self.assertNotIn("foreign.restore-orphan", restored_ids)
        self.assertIn("omarchy.absent-official", restored_ids)

        restored["bar"]["layout"]["right"].append({"id": "foreign.unreadable"})
        atomic_write(self.paths.config_file, encode_config(restored))
        real_scandir = os.scandir
        failed_reads = 0

        def fail_two_catalog_reads(path: object) -> object:
            nonlocal failed_reads
            if path == self.paths.plugin_dir and failed_reads < 2:
                failed_reads += 1
                raise PermissionError("fixture plugin directory unreadable")
            return real_scandir(path)

        with patch.object(config_module.os, "scandir", side_effect=fail_two_catalog_reads):
            self.assertEqual(
                command_activate(self.args(), self.suite, self.paths, self.runtime), 0
            )
        self.assertEqual(failed_reads, 2)
        active = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertTrue(any(
            entry_id(entry) == "foreign.unreadable"
            for region in ("left", "center", "right")
            for entry in active["bar"]["layout"][region]
        ))

        self.assertEqual(
            command_uninstall(self.args(), self.suite, self.paths, self.runtime), 0
        )
        final = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        final_ids = {
            entry_id(entry)
            for region in ("left", "center", "right")
            for entry in final["bar"]["layout"][region]
        }
        self.assertNotIn("foreign.unreadable", final_ids)
        self.assertIn("omarchy.absent-official", final_ids)

    def test_locked_migration_preserves_legacy_state_before_shell_drain(
        self,
    ) -> None:
        self.prepare_legacy_install()
        original_config = self.paths.config_file.read_bytes()
        original_plugins = sorted(
            path.name for path in self.paths.plugin_dir.iterdir()
        )
        self.runtime.session_lock_status["pending"] = True

        with self.assertRaisesRegex(
            RuntimeFailure, r"session lock is active \(pending\)"
        ):
            command_migrate(
                self.args(), self.suite, self.paths, self.runtime
            )

        self.assertEqual(self.runtime.stops, 0)
        self.assertEqual(self.runtime.restarts, 0)
        self.assertEqual(self.runtime.rescans, 0)
        self.assertEqual(
            self.paths.config_file.read_bytes(), original_config
        )
        self.assertEqual(
            sorted(path.name for path in self.paths.plugin_dir.iterdir()),
            original_plugins,
        )
        self.assertFalse((self.paths.state_dir / "install.json").exists())
        self.assertTrue(
            (self.paths.state_dir.parent / "qsrise" / "install.json").is_file()
        )
        self.assertFalse(self.hidden_transaction_paths())

    def test_managed_migration_drains_before_publish_and_never_rescans_before_stop(
        self,
    ) -> None:
        self.prepare_legacy_install()
        original_expose = PluginTransaction.expose

        def recording_expose(transaction: PluginTransaction) -> None:
            self.runtime.events.append("expose")
            original_expose(transaction)

        self.runtime.events.clear()
        with patch.object(PluginTransaction, "expose", recording_expose):
            self.assertEqual(
                command_migrate(
                    self.args(), self.suite, self.paths, self.runtime
                ),
                0,
            )

        self.assertEqual(self.runtime.events, ["stop", "expose", "restart"])
        # Legacy roots are staged for removal while the shell is drained, so
        # migration never starts asynchronous plugin incubation.
        self.assertEqual(self.runtime.rescans, 0)
        self.assertEqual(self.runtime.session_lock_preflights, 1)

    def test_migration_does_not_create_transparency_preference(self) -> None:
        self.prepare_legacy_install()
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertNotIn("transparent", config["bar"])
        defaults = json.loads(self.defaults.read_text(encoding="utf-8"))
        defaults["bar"]["transparent"] = False
        self.defaults.write_text(
            json.dumps(defaults, indent=2) + "\n", encoding="utf-8"
        )

        self.assertEqual(
            command_migrate(self.args(), self.suite, self.paths, self.runtime), 0
        )

        migrated = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        state = load_install_state(self.paths, self.suite)
        self.assertNotIn("transparent", migrated["bar"])
        self.assertNotIn("transparent", state["previousBar"])

    def test_migration_preserves_false_transparency_preference(self) -> None:
        self.prepare_legacy_install()
        config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        config["bar"]["transparent"] = False
        atomic_write(self.paths.config_file, encode_config(config))

        self.assertEqual(
            command_migrate(self.args(), self.suite, self.paths, self.runtime), 0
        )

        migrated = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        state = load_install_state(self.paths, self.suite)
        self.assertIs(migrated["bar"]["transparent"], False)
        self.assertIs(state["previousBar"]["transparent"], False)

    def test_migrate_preserves_settings_and_retires_legacy_namespace(self) -> None:
        legacy_state = self.prepare_legacy_install()
        legacy_config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        legacy_config["bar"]["transparent"] = True
        atomic_write(self.paths.config_file, encode_config(legacy_config))
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
        self.assertIs(config["bar"]["transparent"], True)
        self.assertNotIn("qsrise", config["bar"])
        settings = state_entry(config)["shibumi"]
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
        self.assertIs(new_state["previousBar"]["transparent"], True)
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

    def test_status_refuses_invalid_canonical_storage_without_mutation(self) -> None:
        self.install()
        original = json.loads(self.paths.config_file.read_text())
        for case in ("absent", "bare", "duplicate", "layout", "schema", "payload", "version", "string-entry",
                     "root-version", "root-bool", "root-string", "missing-region", "bad-region", "plugins-limit",
                     "nan", "infinity", "negative-infinity", "parser-limit",
                     "overflow-root", "overflow-entry", "overflow-settings",
                     "integer-overflow-root", "integer-overflow-entry", "integer-overflow-settings"):
            config = copy.deepcopy(original)
            entry = state_entry(config)
            if case == "absent":
                config["plugins"].remove(entry)
            elif case == "bare":
                entry.pop("shibumi")
            elif case == "duplicate":
                config["plugins"].append(copy.deepcopy(entry))
            elif case == "layout":
                config["bar"]["layout"]["left"].append(copy.deepcopy(entry))
            elif case == "schema":
                entry["shibumiStateSchemaVersion"] = 2
            elif case == "payload":
                entry["shibumi"] = []
            elif case == "version":
                entry["shibumi"]["version"] = True
            elif case == "string-entry":
                config["plugins"][config["plugins"].index(entry)] = "hancore.shibumi.state"
            elif case.startswith("root-"):
                config["version"] = {"root-version": 2, "root-bool": True, "root-string": "1"}[case]
            elif case == "missing-region":
                config["bar"]["layout"].pop("center")
            elif case == "bad-region":
                config["bar"]["layout"]["center"] = {}
            elif case == "plugins-limit":
                config["plugins"] += [{"id": f"foreign.{i}"} for i in range(513 - len(config["plugins"]))]
            elif case in ("nan", "infinity", "negative-infinity"):
                config["foreign"] = float({"nan": "nan", "infinity": "inf", "negative-infinity": "-inf"}[case])
            elif "overflow-" in case:
                target = config if case.endswith("root") else entry if case.endswith("entry") else entry["shibumi"]
                target["foreign"] = "__fixture_overflow__"
            else:
                config["foreign"] = "x" * 1048576
            # Deliberately malformed raw input; production encoding refuses NaN.
            token = "9" * 400 if case.startswith("integer-") else "1e309"
            raw = json.dumps(config).replace('"__fixture_overflow__"', token).encode()
            atomic_write(self.paths.config_file, raw)
            before = self.paths.config_file.read_bytes()
            output = io.StringIO()
            with self.subTest(case=case), redirect_stdout(output):
                self.assertEqual(command_status(self.suite, self.paths), 1)
                self.assertIn("Config: invalid", output.getvalue())
                self.assertIn("shibumi-suite repair", output.getvalue())
                self.assertEqual(self.paths.config_file.read_bytes(), before)

    def test_canonical_migration_refuses_raw_envelope_before_normalizing(self) -> None:
        base = migrate_state_settings({"version": 1, "plugins": [], "bar": {}})
        for case in ("root-version", "root-bool", "root-string", "region", "missing-region", "plugins-limit"):
            config = copy.deepcopy(base)
            if case.startswith("root-"):
                config["version"] = {"root-version": 2, "root-bool": True, "root-string": "1"}[case]
            elif case == "region":
                config["bar"]["layout"]["right"] = None
            elif case == "missing-region":
                config["bar"]["layout"].pop("right")
            else:
                config["plugins"] += [{"id": f"foreign.{i}"} for i in range(512)]
            before = copy.deepcopy(config)
            with self.subTest(case=case), self.assertRaises(ConfigError):
                migrate_state_settings(config)
            self.assertEqual(config, before)
        base["version"] = 1.0
        base["plugins"] += [{"id": f"foreign.{i}"} for i in range(511)]
        self.assertEqual(migrate_state_settings(base), base)

    def test_state_schema_numbers_match_native_and_manager_semantics(self) -> None:
        base = {"version": 1, "bar": {"id": "hancore.shibumi.bar"}, "plugins": []}
        for value in (1, 1.0, True, "1", None, 2):
            for key in ("shibumiStateSchemaVersion", "version"):
                config = migrate_state_settings(base)
                entry = state_entry(config)
                (entry if key == "shibumiStateSchemaVersion" else entry["shibumi"])[key] = value
                with self.subTest(key=key, value=repr(value)):
                    if type(value) in (int, float) and value == 1:
                        self.assertEqual(validate_state_settings(config), entry["shibumi"])
                        self.assertEqual(migrate_state_settings(config), config)
                    else:
                        with self.assertRaises(ConfigError):
                            migrate_state_settings(config)
        for value in (1, 1.0, "1", True):
            config = copy.deepcopy(base)
            config["bar"]["shibumi"] = {"version": value}
            if value is True:
                with self.assertRaises(ConfigError):
                    migrate_state_settings(config)
            else:
                self.assertIs(type(state_entry(migrate_state_settings(config))["shibumi"]["version"]), int)

    def test_foreign_layout_keep_settings_round_trip(self) -> None:
        """Real lifecycle transforms: .140 stock duplicates, V1 extras and V2 slots."""
        foreign_ids = {"hancore.omaq", "basecamp", "hey"}
        stock = json.loads(self.defaults.read_text())
        stock["bar"]["layout"] = {
            "left": [{"id": "hancore.omaq", "side": "stock-left"}, {"id": "basecamp"}],
            "center": [], "right": [{"id": "hancore.omaq"}, {"id": "hey"}]}
        for plugin in foreign_ids:
            (self.paths.plugin_dir / plugin).mkdir(parents=True, exist_ok=True)
        for style in ("shibumi", "full", "fit", "dock", "notch"):
            atomic_write(self.paths.config_file, encode_config(stock))
            self.assertEqual(command_install(self.args(), self.suite, self.paths, self.runtime), 0)
            before = json.loads(self.paths.config_file.read_text())
            with self.subTest(style=style, phase="fresh-import"):
                foreign = {r: [e for e in entries if entry_id(e) in foreign_ids]
                           for r, entries in before["bar"]["layout"].items()}
                self.assertEqual(foreign, {"left": stock["bar"]["layout"]["left"],
                                          "center": [], "right": [{"id": "hey"}]})
            stale_record = {"schemaVersion": 1, "layout": copy.deepcopy(before["bar"]["layout"])}
            for region in ("left", "center", "right"):
                before["bar"]["layout"][region] = [e for e in before["bar"]["layout"][region]
                    if entry_id(e) not in foreign_ids]
            before["bar"]["layout"]["left"].reverse()
            before["bar"]["layout"]["right"] += [{"id": "hancore.omaq", "opaque": [False, "Malmö"]}, {"id": "hey"}]
            settings = state_entry(before)["shibumi"]
            settings["presentation"] = {"shellStyle": style}
            # V1 has no foreign group positions: these widgets use the Extra-Deck.
            settings["order"] = {"left": ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
                "center": ["G8"], "right": ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]}
            settings["v2Layout"] = {
                "left": ["G1", "G2", "G3", "", "G5", "G6", "G4", "G7", "", ""], "center": ["G8"],
                "right": ["G9", "G10", "G11", "G14", "G12", "G13", "G16", "G18", "G17", "G15", "G:hancore.omaq", "G:hey", ""]}
            entry_bytes = encode_config(state_entry(before))
            # An older release preserves this unknown sibling after reinstall.
            state_entry(before)["shibumiRetainedLayout"] = stale_record
            atomic_write(self.paths.config_file, encode_config(before))
            with self.subTest(style=style, phase="stale-repair"):
                self.assertEqual(command_repair(self.args(), self.suite, self.paths, self.runtime), 0)
                repaired = json.loads(self.paths.config_file.read_text())
                self.assertEqual(repaired["bar"]["layout"], before["bar"]["layout"])
                self.assertEqual(encode_config(state_entry(repaired)), entry_bytes)
            # Reintroduce the stale sibling: uninstall must replace it, not refuse.
            atomic_write(self.paths.config_file, encode_config(before))
            self.assertEqual(command_uninstall(self.args(keep_settings=True), self.suite, self.paths, self.runtime), 0)
            kept = json.loads(self.paths.config_file.read_text())
            with self.subTest(style=style, phase="kept"):
                self.assertEqual(kept["bar"]["layout"], stock["bar"]["layout"])
                expected = {**state_entry(before), "shibumiRetainedLayout": {
                    "schemaVersion": 1, "layout": before["bar"]["layout"]}}
                self.assertEqual(state_entry(kept), expected)
                self.assertNotIn("shibumiRetainedLayout", kept)
            kept["idle"] = {"enabled": False, "future": {"minutes": 17}}
            kept["plugins"].append({"id": "local.stock-service", "opaque": [False, "Malmö"]})
            kept["bar"]["layout"]["left"][1]["stockOption"] = "changed"
            atomic_write(self.paths.config_file, encode_config(kept))
            real_restart = self.runtime.restart_shell
            def inspect_before_load() -> None:
                current = json.loads(self.paths.config_file.read_text())
                self.assertEqual(encode_config(state_entry(current)), entry_bytes)
                real_restart()
            with patch.object(self.runtime, "restart_shell", side_effect=inspect_before_load):
                self.assertEqual(command_install(self.args(), self.suite, self.paths, self.runtime), 0)
            after = json.loads(self.paths.config_file.read_text())
            with self.subTest(style=style, phase="reinstalled"):
                self.assertEqual(after["bar"]["layout"], before["bar"]["layout"])
                self.assertEqual(encode_config(state_entry(after)), entry_bytes)
                self.assertEqual(after["idle"], kept["idle"])
                self.assertIn(kept["plugins"][-1], after["plugins"])
                self.assertEqual(load_install_state(self.paths, self.suite)["previousBar"], kept["bar"])
            self.assertEqual(command_uninstall(self.args(keep_settings=True), self.suite, self.paths, self.runtime), 0)
            external_bar = json.loads(self.paths.config_file.read_text())["bar"]
            self.assertEqual(command_install(self.args(no_activate=True, keep_layout=True), self.suite, self.paths, self.runtime), 0)
            external = json.loads(self.paths.config_file.read_text())
            self.assertEqual(external["bar"], external_bar)
            self.assertEqual(encode_config(state_entry(external)), entry_bytes)
            state_entry(external)["shibumiRetainedLayout"] = stale_record
            atomic_write(self.paths.config_file, encode_config(external))
            self.assertEqual(command_deactivate(self.args(), self.suite, self.paths, self.runtime), 0)
            self.assertNotIn("shibumiRetainedLayout", state_entry(json.loads(self.paths.config_file.read_text())))
            self.assertEqual(command_uninstall(self.args(), self.suite, self.paths, self.runtime), 0)
            self.assertIsNone(state_entry(json.loads(self.paths.config_file.read_text())))

    def test_state_storage_keeps_complete_entry_through_uninstall_reinstall(self) -> None:
        self.install()
        config = json.loads(self.paths.config_file.read_text())
        entry = state_entry(config)
        entry["foreignFuture"] = {"nested": [1, False, {"label": "Malmö"}]}
        entry["shibumi"]["picker"] = {"imageStyle": "tanzaku", "mediaStyle": "hearthstone"}
        entry["shibumi"]["widgets"] = {"G8": {"omarchy.clock": {"format": "HH:mm", "deep": [3, 2, 1]}}}
        retained = copy.deepcopy(entry)
        atomic_write(self.paths.config_file, encode_config(config))
        self.assertEqual(command_uninstall(self.args(keep_settings=True), self.suite, self.paths, self.runtime), 0)
        kept = json.loads(self.paths.config_file.read_text())
        self.assertEqual(state_entry(kept), {**retained, "shibumiRetainedLayout": {
            "schemaVersion": 1, "layout": config["bar"]["layout"]}})
        self.assertFalse((self.paths.plugin_dir / "hancore.shibumi.state").exists())
        self.assertEqual(command_install(self.args(), self.suite, self.paths, self.runtime), 0)
        self.assertEqual(state_entry(json.loads(self.paths.config_file.read_text())), retained)

    def test_state_migration_refuses_corruption_and_does_not_resurrect_legacy(self) -> None:
        config = {"version": 1, "bar": {"id": "omarchy.bar", "shibumi": {"version": 1, "legacy": True}},
                  "plugins": [{"id": "hancore.shibumi.state", "foreign": {"value": 7}}]}
        migrated = migrate_state_settings(config)
        self.assertEqual(state_entry(migrated)["foreign"], {"value": 7})
        self.assertEqual(migrate_state_settings(migrated), migrated)
        corrupt = copy.deepcopy(migrated)
        state_entry(corrupt)["shibumiStateSchemaVersion"] = 2
        with self.assertRaises(ConfigError):
            migrate_state_settings(corrupt)
        duplicate = copy.deepcopy(config)
        duplicate["plugins"].append(copy.deepcopy(duplicate["plugins"][0]))
        with self.assertRaises(ConfigError):
            migrate_state_settings(duplicate)
        # A current installation's migration stamp prohibits re-import after
        # raw native disable removed the canonical entry.
        reset = migrate_state_settings(config, import_legacy=False)
        self.assertNotIn("legacy", state_entry(reset)["shibumi"])
        self.assertEqual(reset["bar"]["shibumi"], config["bar"]["shibumi"])

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
        settings = state_entry(migrated)["shibumi"]
        self.assertEqual(settings["identityVersion"], 3)
        self.assertEqual(settings["launcher"]["text"], "shibumi")
        self.assertNotIn("menu", settings)

        settings["launcher"]["text"] = "omarchy"
        preserved = apply_identity_contract(migrated)
        self.assertEqual(
            state_entry(preserved)["shibumi"]["launcher"]["text"],
            "omarchy",
        )

    def test_failed_migration_restores_legacy_payload_config_and_state(self) -> None:
        self.prepare_legacy_install()
        original_config = self.paths.config_file.read_bytes()
        with patch.object(
            self.runtime,
            "verify_uninstall",
            side_effect=RuntimeFailure(
                "injected post-restart legacy verification failure"
            ),
        ):
            with self.assertRaisesRegex(
                RuntimeFailure,
                "post-restart legacy verification failure",
            ):
                command_migrate(
                    self.args(), self.suite, self.paths, self.runtime
                )

        self.assertNotIn("rescan", self.runtime.events)

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

    def test_external_drift_rollback_uses_drained_restart_without_payload_reload(self) -> None:
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
        # External repair now shares the drained full-restart path. Neither the
        # failed attempt nor rollback asks a potentially disabled provider to
        # hot-reload payload.
        self.assertEqual(self.runtime.payload_reloads, reloads_before)
        self.assertTrue(
            (self.paths.plugin_dir / "hancore.shibumi.state").is_dir()
        )
        self.assertFalse(self.hidden_transaction_paths())

    def test_external_update_transforms_the_post_stop_config_and_restarts(self) -> None:
        external_args = self.args(no_activate=True, keep_layout=True)
        self.assertEqual(
            command_install(external_args, self.suite, self.paths, self.runtime), 0
        )
        original_stop = self.runtime.stop_shell
        saved_bar: dict[str, object] = {}
        saved = False

        def stop_after_external_save() -> None:
            nonlocal saved_bar, saved
            original_stop()
            if not saved:
                config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
                config["bar"]["id"] = "third.party.after-stop"
                config["bar"]["layout"]["left"].append(
                    {"id": "user.after-stop", "options": {"size": 19}}
                )
                config["bar"]["design"] = {"radius": 13, "variant": "user"}
                saved_bar = copy.deepcopy(config["bar"])
                atomic_write(self.paths.config_file, encode_config(config))
                saved = True

        original_expose = PluginTransaction.expose

        def recording_expose(transaction: PluginTransaction) -> None:
            self.runtime.events.append("expose")
            original_expose(transaction)

        self.runtime.events.clear()
        with patch.object(
            self.runtime, "stop_shell", side_effect=stop_after_external_save
        ), patch.object(PluginTransaction, "expose", recording_expose):
            self.assertEqual(
                command_update(self.args(), self.suite, self.paths, self.runtime), 0
            )

        updated = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(updated["bar"], saved_bar)
        self.assertEqual(self.runtime.events, ["stop", "expose", "restart"])
        state = load_install_state(self.paths, self.suite)
        self.assertEqual(state["activation"]["configuredBar"], "third.party.after-stop")

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
        self.assertEqual(self.runtime.events, ["stop", "restart"])
        self.assertEqual(self.runtime.reloads, 0)
        self.assertEqual(self.runtime.payload_reloads, 0)

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
        stops_before = self.runtime.stops
        self.assertEqual(
            command_update(
                self.args(), self.suite, self.paths, self.runtime
            ),
            0,
        )
        self.assertEqual(self.runtime.reloads, reloads_before)
        self.assertEqual(
            self.runtime.payload_reloads, payload_reloads_before
        )
        self.assertEqual(self.runtime.restarts, restarts_before + 1)
        self.assertEqual(self.runtime.stops, stops_before + 1)
        updated = json.loads(
            self.paths.config_file.read_text(encoding="utf-8")
        )
        self.assertEqual(updated["bar"], expected_bar)

        shutil.rmtree(
            self.paths.plugin_dir / "hancore.shibumi.bluetooth"
        )
        reloads_before = self.runtime.reloads
        payload_reloads_before = self.runtime.payload_reloads
        restarts_before = self.runtime.restarts
        stops_before = self.runtime.stops
        self.assertEqual(
            command_repair(
                self.args(), self.suite, self.paths, self.runtime
            ),
            0,
        )
        self.assertEqual(self.runtime.reloads, reloads_before)
        self.assertEqual(self.runtime.payload_reloads, payload_reloads_before)
        self.assertEqual(self.runtime.restarts, restarts_before + 1)
        self.assertEqual(self.runtime.stops, stops_before + 1)
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
        self.assertEqual(active_state["previousBar"], expected_bar)

        # Activating an already managed bar must not replace the external
        # predecessor with a self-snapshot.
        self.assertEqual(
            command_activate(self.args(), self.suite, self.paths, self.runtime), 0
        )
        self.assertEqual(
            load_install_state(self.paths, self.suite)["previousBar"],
            expected_bar,
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

    def test_locked_managed_install_discards_staging_before_shell_drain(
        self,
    ) -> None:
        self.runtime.session_lock_status["pending"] = True

        with self.assertRaisesRegex(
            RuntimeFailure, r"session lock is active \(pending\)"
        ):
            command_install(
                self.args(), self.suite, self.paths, self.runtime
            )

        self.assertEqual(self.runtime.stops, 0)
        self.assertEqual(self.runtime.restarts, 0)
        self.assertEqual(self.runtime.rescans, 0)
        self.assertFalse(self.paths.config_file.exists())
        self.assertFalse((self.paths.state_dir / "install.json").exists())
        self.assertFalse(
            any(
                (self.paths.plugin_dir / plugin_id).exists()
                for plugin_id in self.suite.plugins
            )
        )
        self.assertFalse(self.hidden_transaction_paths())

    def test_managed_install_uses_post_stop_bar_metadata(self) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["id"] = "third.party.before-stop"
        atomic_write(self.paths.config_file, encode_config(base))
        original_stop = self.runtime.stop_shell
        final_bar: dict[str, object] = {}

        def stop_after_bar_save() -> None:
            nonlocal final_bar
            original_stop()
            config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
            config["bar"]["id"] = "third.party.after-stop"
            config["bar"]["foreignOwnerState"] = {"serial": 23}
            final_bar = copy.deepcopy(config["bar"])
            atomic_write(self.paths.config_file, encode_config(config))

        with patch.object(
            self.runtime, "stop_shell", side_effect=stop_after_bar_save
        ):
            self.assertEqual(
                command_install(self.args(), self.suite, self.paths, self.runtime),
                0,
            )

        installed = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        state = load_install_state(self.paths, self.suite)
        self.assertEqual(state["previousBar"], final_bar)
        self.assertEqual(
            state["activation"]["configuredBar"], installed["bar"]["id"]
        )
        self.assertEqual(installed["bar"]["foreignOwnerState"], {"serial": 23})

    def test_orphan_managed_install_preserves_changed_post_stop_bar(self) -> None:
        self.write_orphan_shibumi_config()
        original_stop = self.runtime.stop_shell
        final_bar: dict[str, object] = {}

        def stop_after_bar_save() -> None:
            nonlocal final_bar
            original_stop()
            config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
            config["bar"]["id"] = "third.party.after-stop"
            config["bar"]["foreignOwnerState"] = {"serial": 29}
            final_bar = copy.deepcopy(config["bar"])
            atomic_write(self.paths.config_file, encode_config(config))

        with patch.object(
            self.runtime, "stop_shell", side_effect=stop_after_bar_save
        ):
            self.assertEqual(
                command_install(self.args(), self.suite, self.paths, self.runtime),
                0,
            )

        self.assertEqual(
            load_install_state(self.paths, self.suite)["previousBar"], final_bar
        )

    def assert_post_stop_shibumi_transition_uses_stock(
        self, initial_bar_id: str | None
    ) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        if initial_bar_id is not None:
            base["bar"]["id"] = initial_bar_id
        atomic_write(self.paths.config_file, encode_config(base))
        expected_bar = copy.deepcopy(
            json.loads(self.defaults.read_text(encoding="utf-8"))["bar"]
        )
        expected_bar["id"] = "omarchy.bar"
        original_stop = self.runtime.stop_shell

        def stop_after_shibumi_save() -> None:
            original_stop()
            config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
            config["bar"]["id"] = "hancore.shibumi.bar"
            atomic_write(self.paths.config_file, encode_config(config))

        with patch.object(
            self.runtime, "stop_shell", side_effect=stop_after_shibumi_save
        ):
            self.assertEqual(
                command_install(self.args(), self.suite, self.paths, self.runtime),
                0,
            )

        self.assertEqual(
            load_install_state(self.paths, self.suite)["previousBar"], expected_bar
        )
        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime), 0
        )
        restored = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(restored["bar"]["id"], "omarchy.bar")

    def test_stock_to_shibumi_during_stop_records_stock_and_deactivates(
        self,
    ) -> None:
        self.assert_post_stop_shibumi_transition_uses_stock(None)

    def test_third_party_to_shibumi_during_stop_records_stock_and_deactivates(
        self,
    ) -> None:
        self.assert_post_stop_shibumi_transition_uses_stock("third.party.before-stop")

    def test_post_stop_shibumi_rejects_new_invalid_defaults_before_exposure(
        self,
    ) -> None:
        base = json.loads(self.defaults.read_text(encoding="utf-8"))
        base["bar"]["id"] = "third.party.before-stop"
        atomic_write(self.paths.config_file, encode_config(base))
        original_stop = self.runtime.stop_shell
        original_expose = PluginTransaction.expose
        transitioned = False

        def stop_after_invalid_default_save() -> None:
            nonlocal transitioned
            original_stop()
            if transitioned:
                return
            config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
            config["bar"]["id"] = "hancore.shibumi.bar"
            atomic_write(self.paths.config_file, encode_config(config))
            self.defaults.write_bytes(b"{")
            transitioned = True

        def recording_expose(transaction: PluginTransaction) -> None:
            self.runtime.events.append("expose")
            original_expose(transaction)

        with patch.object(
            self.runtime, "stop_shell", side_effect=stop_after_invalid_default_save
        ), patch.object(PluginTransaction, "expose", recording_expose):
            with self.assertRaises(ConfigError):
                command_install(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(self.runtime.events, ["stop", "stop", "restart"])
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(
            any(
                (self.paths.plugin_dir / plugin_id).exists()
                for plugin_id in self.suite.plugins
            )
        )
        self.assertTrue(self.paths.plugin_dir.is_dir())
        self.assertFalse(self.hidden_transaction_paths())
        self.assertFalse((self.paths.state_dir / "install.json").exists())

    def test_managed_install_drains_before_publish_without_rescan(self) -> None:
        original_expose = PluginTransaction.expose

        def recording_expose(transaction: PluginTransaction) -> None:
            self.runtime.events.append("expose")
            original_expose(transaction)

        with patch.object(PluginTransaction, "expose", recording_expose):
            self.assertEqual(
                command_install(
                    self.args(), self.suite, self.paths, self.runtime
                ),
                0,
            )

        self.assertEqual(self.runtime.events, ["stop", "expose", "restart"])
        self.assertEqual(self.runtime.session_lock_preflights, 1)
        self.assertEqual(command_status(self.suite, self.paths), 0)

    def test_managed_update_stops_before_publish_and_restarts_once(self) -> None:
        self.install()
        original_expose = PluginTransaction.expose

        def recording_expose(transaction: PluginTransaction) -> None:
            self.runtime.events.append("expose")
            original_expose(transaction)

        self.runtime.events.clear()
        with patch.object(PluginTransaction, "expose", recording_expose):
            self.assertEqual(
                command_update(self.args(), self.suite, self.paths, self.runtime),
                0,
            )

        self.assertEqual(self.runtime.events, ["stop", "expose", "restart"])
        self.assertNotIn("rescan", self.runtime.events)
        self.assertNotIn("reload-config", self.runtime.events)
        self.assertNotIn("reload-payload", self.runtime.events)
        self.assertEqual(command_status(self.suite, self.paths), 0)

    def test_managed_update_transforms_post_stop_state(self) -> None:
        self.install()
        original_stop = self.runtime.stop_shell
        saved = False

        def stop_after_state_save() -> None:
            nonlocal saved
            original_stop()
            if not saved:
                config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
                state_entry(config)["shibumi"]["lateManagedState"] = {
                    "serial": 17,
                    "enabled": True,
                }
                config["foreignPostStop"] = {"preserve": [1, 2, 3]}
                atomic_write(self.paths.config_file, encode_config(config))
                saved = True

        with patch.object(
            self.runtime, "stop_shell", side_effect=stop_after_state_save
        ):
            self.assertEqual(
                command_update(self.args(), self.suite, self.paths, self.runtime),
                0,
            )

        updated = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(
            state_entry(updated)["shibumi"]["lateManagedState"],
            {"serial": 17, "enabled": True},
        )
        self.assertEqual(updated["foreignPostStop"], {"preserve": [1, 2, 3]})
        install_state = load_install_state(self.paths, self.suite)
        self.assertEqual(
            install_state["activation"]["configuredBar"],
            updated["bar"]["id"],
        )

    def test_failed_managed_update_rolls_back_to_post_stop_baseline(self) -> None:
        self.install()
        original_stop = self.runtime.stop_shell
        post_stop_payload = b""
        saved = False

        def stop_after_foreign_save() -> None:
            nonlocal post_stop_payload, saved
            original_stop()
            if not saved:
                config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
                config["savedDuringDrain"] = {"generation": 29}
                post_stop_payload = encode_config(config)
                atomic_write(self.paths.config_file, post_stop_payload)
                saved = True

        self.runtime.fail_restart_count = 1
        with patch.object(
            self.runtime, "stop_shell", side_effect=stop_after_foreign_save
        ):
            with self.assertRaisesRegex(
                RuntimeFailure, "injected shell restart failure"
            ):
                command_update(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(self.paths.config_file.read_bytes(), post_stop_payload)
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(self.hidden_transaction_paths())

    def test_interrupted_drain_recovery_preserves_late_config_save(self) -> None:
        self.install()
        transaction = PluginTransaction(
            self.paths,
            self.runtime,
            restart_on_reconcile=True,
        )
        original_stop = self.runtime.stop_shell
        post_stop_payload = b""

        def interrupt_after_foreign_save() -> None:
            nonlocal post_stop_payload
            original_stop()
            config = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
            config["savedBeforeInterruptedDrain"] = {"generation": 31}
            post_stop_payload = encode_config(config)
            atomic_write(self.paths.config_file, post_stop_payload)
            raise RuntimeFailure("injected interruption after late config save")

        with patch.object(
            self.runtime, "stop_shell", side_effect=interrupt_after_foreign_save
        ):
            with self.assertRaisesRegex(
                RuntimeFailure, "injected interruption after late config save"
            ):
                transaction.stop_shell()

        self.close_transaction_descriptors(transaction)
        self.assertEqual(
            recover_transactions(
                self.paths, self.runtime, suite=self.suite
            ),
            1,
        )
        self.assertEqual(self.paths.config_file.read_bytes(), post_stop_payload)
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(self.hidden_transaction_paths())

    def _assert_bound_snapshot_parse_swap_rejected(self, kind: str) -> None:
        self.install()
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stop_shell()
        live_before = self.paths.config_file.read_bytes()
        events_before = list(self.runtime.events)
        original_replace = transaction._replace_config_baseline

        def replace_then_swap() -> None:
            original_replace()
            transaction.snapshot_file.unlink()
            if kind == "symlink":
                external = self.root / "foreign-snapshot.json"
                external.write_text(
                    '{"version":1,"owner":"foreign"}\n', encoding="utf-8"
                )
                transaction.snapshot_file.symlink_to(external)
            elif kind == "regular":
                transaction.snapshot_file.write_text(
                    '{"version":1,"owner":"foreign"}\n', encoding="utf-8"
                )
            elif kind == "oversize":
                transaction.snapshot_file.write_bytes(
                    b"x" * (MAX_STATE_BYTES + 1)
                )
            else:
                raise AssertionError(f"unknown snapshot swap: {kind}")

        with (
            patch.object(
                transaction,
                "_replace_config_baseline",
                side_effect=replace_then_swap,
            ),
            self.assertRaisesRegex(
                TransactionError,
                "snapshot (was replaced|is missing or unsafe|is malformed or exceeds)",
            ),
        ):
            transaction.refresh_config_after_stop()

        self.assertEqual(self.paths.config_file.read_bytes(), live_before)
        self.assertEqual(self.runtime.events, events_before)
        self.assertFalse(transaction.live_mutation_started)
        self.assertFalse(transaction.commit_point_reached)
        self.close_transaction_descriptors(transaction)

    def test_bound_snapshot_regular_swap_is_rejected_before_transform(self) -> None:
        self._assert_bound_snapshot_parse_swap_rejected("regular")

    def test_bound_snapshot_symlink_swap_is_rejected_before_transform(self) -> None:
        self._assert_bound_snapshot_parse_swap_rejected("symlink")

    def test_bound_snapshot_oversize_swap_is_rejected_before_transform(self) -> None:
        self._assert_bound_snapshot_parse_swap_rejected("oversize")

    def _assert_defaults_fallback_is_bounded(self, kind: str) -> None:
        self.paths.config_file.parent.mkdir(parents=True)
        self.paths.config_file.write_bytes(b"")
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stop_shell()
        events_before = list(self.runtime.events)
        original_replace = transaction._replace_config_baseline

        def replace_then_swap_defaults() -> None:
            original_replace()
            if kind == "symlink":
                external = self.root / "foreign-defaults.json"
                external.write_text(
                    '{"version":1,"owner":"foreign"}\n', encoding="utf-8"
                )
                self.defaults.unlink()
                self.defaults.symlink_to(external)
            elif kind == "oversize":
                self.defaults.write_bytes(b"x" * (MAX_STATE_BYTES + 1))
            else:
                raise AssertionError(f"unknown defaults swap: {kind}")

        with (
            patch.object(
                transaction,
                "_replace_config_baseline",
                side_effect=replace_then_swap_defaults,
            ),
            self.assertRaisesRegex(
                TransactionError,
                "shell config defaults.*(Too many levels|limit)",
            ),
        ):
            transaction.refresh_config_after_stop()

        self.assertEqual(self.paths.config_file.read_bytes(), b"")
        self.assertEqual(self.runtime.events, events_before)
        self.assertFalse(transaction.live_mutation_started)
        self.close_transaction_descriptors(transaction)

    def test_defaults_fallback_rejects_symlink_swap(self) -> None:
        self._assert_defaults_fallback_is_bounded("symlink")

    def test_defaults_fallback_rejects_oversize_swap(self) -> None:
        self._assert_defaults_fallback_is_bounded("oversize")

    def test_journal_publish_has_no_redundant_post_write_flush(self) -> None:
        transaction = PluginTransaction(self.paths, self.runtime)
        desired = {"marker": "desired"}
        with patch.object(
            transaction_module,
            "_fsync_directory",
            side_effect=AssertionError("redundant post-publish flush"),
        ):
            transaction._write_journal(
                "committing", desired_state=desired, archive_previous=True
            )

        journal = json.loads(
            transaction.journal_file.read_text(encoding="utf-8")
        )
        self.assertEqual(transaction.phase, "committing")
        self.assertEqual(journal["phase"], "committing")
        self.assertEqual(journal["desiredState"], desired)
        self.assertTrue(journal["archivePrevious"])
        self.close_transaction_descriptors(transaction)

    def test_post_durable_committing_error_preserves_roll_forward(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.memory"
        target_file = self.paths.plugin_dir / plugin_id / "BarWidget.qml"
        old_payload = target_file.read_bytes()
        source_file = self.source / plugin_id / "BarWidget.qml"
        source_file.write_text(
            source_file.read_text(encoding="utf-8")
            + "\n// post-durable committing fault\n",
            encoding="utf-8",
        )
        suite = Suite.load(self.source)
        expected_payload = source_file.read_bytes()
        install_state_before = (
            self.paths.state_dir / "install.json"
        ).read_bytes()
        observed: PluginTransaction | None = None
        durable_fault_injected = False
        original_fsync_directory = config_module._fsync_directory
        original_finish = PluginTransaction.finish

        def fail_after_committing_sync(
            path: Path,
            *,
            on_durable: Callable[[], None] | None = None,
        ) -> None:
            nonlocal durable_fault_injected
            original_fsync_directory(path, on_durable=on_durable)
            if on_durable is not None and not durable_fault_injected:
                durable_fault_injected = True
                raise OSError("injected post-durable committing failure")

        def recording_finish(
            transaction: PluginTransaction,
            desired_state: dict[str, object] | None,
            *,
            archive_previous: bool,
        ) -> None:
            nonlocal observed
            observed = transaction
            original_finish(
                transaction,
                desired_state,
                archive_previous=archive_previous,
            )

        with (
            patch.object(
                config_module,
                "_fsync_directory",
                side_effect=fail_after_committing_sync,
            ),
            patch.object(PluginTransaction, "finish", recording_finish),
            self.assertRaisesRegex(
                OSError, "injected post-durable committing failure"
            ),
        ):
            command_update(self.args(), suite, self.paths, self.runtime)

        self.assertTrue(durable_fault_injected)
        self.assertIsNotNone(observed)
        assert observed is not None
        self.assertTrue(observed.commit_point_reached)
        self.assertFalse(observed.finished)
        self.assertTrue(observed.journal_file.is_file())
        journal = json.loads(
            observed.journal_file.read_text(encoding="utf-8")
        )
        self.assertEqual(journal["phase"], "committing")
        self.assertEqual(target_file.read_bytes(), expected_payload)
        self.assertNotEqual(target_file.read_bytes(), old_payload)
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(),
            install_state_before,
        )

        self.assertEqual(
            recover_transactions(self.paths, self.runtime), 1
        )
        self.assertEqual(
            json.loads(
                (self.paths.state_dir / "install.json").read_text(
                    encoding="utf-8"
                )
            ),
            journal["desiredState"],
        )
        self.assertEqual(target_file.read_bytes(), expected_payload)
        self.assertFalse(self.hidden_transaction_paths())

    def test_recovery_preserves_config_created_before_baseline_publication(
        self,
    ) -> None:
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stop_shell()
        foreign = b'{"version":1,"foreign":"created-during-drain"}\n'
        atomic_write(self.paths.config_file, foreign)
        original_atomic_write = transaction_module.atomic_write

        def write_snapshot_then_crash(path: Path, payload: bytes) -> None:
            original_atomic_write(path, payload)
            if path == transaction.snapshot_file:
                raise OSError("injected crash after created baseline snapshot")

        with (
            patch.object(
                transaction_module,
                "atomic_write",
                side_effect=write_snapshot_then_crash,
            ),
            self.assertRaisesRegex(OSError, "created baseline snapshot"),
        ):
            transaction.refresh_config_after_stop()

        journal = json.loads(transaction.journal_file.read_text(encoding="utf-8"))
        self.assertIs(journal["configExisted"], False)
        self.assertIs(journal["liveMutationStarted"], False)
        self.close_transaction_descriptors(transaction)
        self.assertEqual(
            recover_transactions(self.paths, self.runtime, suite=self.suite), 1
        )
        self.assertEqual(self.paths.config_file.read_bytes(), foreign)
        self.assertTrue(self.runtime.shell_running)

    def test_recovery_preserves_config_removed_before_baseline_publication(
        self,
    ) -> None:
        original = b'{"version":1,"foreign":"removed-during-drain"}\n'
        self.paths.config_file.parent.mkdir(parents=True)
        self.paths.config_file.write_bytes(original)
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stop_shell()
        self.paths.config_file.unlink()
        original_unlink = transaction_module._durable_unlink

        def unlink_snapshot_then_crash(path: Path) -> None:
            original_unlink(path)
            if path == transaction.snapshot_file:
                raise OSError("injected crash after removed baseline snapshot")

        with (
            patch.object(
                transaction_module,
                "_durable_unlink",
                side_effect=unlink_snapshot_then_crash,
            ),
            self.assertRaisesRegex(OSError, "removed baseline snapshot"),
        ):
            transaction.refresh_config_after_stop()

        journal = json.loads(transaction.journal_file.read_text(encoding="utf-8"))
        self.assertIs(journal["configExisted"], False)
        self.assertIs(journal["liveMutationStarted"], False)
        self.close_transaction_descriptors(transaction)
        self.assertEqual(
            recover_transactions(self.paths, self.runtime, suite=self.suite), 1
        )
        self.assertFalse(self.paths.config_file.exists())
        self.assertTrue(self.runtime.shell_running)

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

    def test_started_repair_retains_recovery_when_rollback_restart_is_blocked(self) -> None:
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
                RuntimeFailure, "injected rollback restart preflight failure"
            ):
                command_repair(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(restart_calls, 2)
        self.assertFalse(self.runtime.shell_running)
        self.assertEqual(self.runtime.reloads, reloads_before)
        self.assertEqual(self.paths.config_file.read_bytes(), original_config)
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(), original_state
        )
        self.assertEqual(
            len(list(
                (self.paths.state_dir / "transactions").glob("*/journal.json")
            )),
            1,
        )

        self.assertEqual(recover_transactions(self.paths, self.runtime), 1)
        self.assertTrue(self.runtime.shell_running)
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
        (self.paths.plugin_dir / "user.weather").mkdir()
        config["plugins"].append({"id": "user.service", "interval": 17})
        state_entry(config)["shibumi"]["testSetting"] = "retained"
        atomic_write(self.paths.config_file, encode_config(config))

        self.assertEqual(
            command_deactivate(self.args(), self.suite, self.paths, self.runtime),
            0,
        )
        inactive = json.loads(self.paths.config_file.read_text(encoding="utf-8"))
        self.assertEqual(inactive["bar"].get("id", "omarchy.bar"), "omarchy.bar")
        self.assertEqual(state_entry(inactive)["shibumi"]["testSetting"], "retained")
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
        self.assertEqual(state_entry(active)["shibumi"]["testSetting"], "retained")
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
        restarts_before = self.runtime.restarts
        # Publishing occurs only after a controlled drain. If the operational
        # start fails, rollback restores the old bytes and starts them once.
        self.runtime.fail_restart_count = 1
        with self.assertRaisesRegex(
            RuntimeFailure, "injected shell restart failure"
        ):
            command_update(self.args(), self.suite, self.paths, self.runtime)
        self.assertEqual(target_file.read_bytes(), old_payload)
        self.assertEqual(self.paths.config_file.read_bytes(), old_config)
        self.assertEqual((self.paths.state_dir / "install.json").read_bytes(), old_state)
        self.assertEqual(self.runtime.stops, stops_before + 2)
        self.assertEqual(self.runtime.restarts, restarts_before + 2)
        self.assertEqual(self.runtime.payload_reloads, reloads_before)
        self.assertFalse(self.hidden_transaction_paths())
        self.assertFalse((self.paths.state_dir / "transactions").exists())

    def test_update_rollback_drains_a_shell_started_before_timeout(self) -> None:
        self.install()
        source_file = (
            self.source / "hancore.shibumi.center" / "BarWidget.qml"
        )
        source_file.write_text(
            source_file.read_text(encoding="utf-8")
            + "\n// post-launch rollback fixture\n",
            encoding="utf-8",
        )
        self.suite = Suite.load(self.source)
        original_restore = transaction_module._restore_records
        restart_calls = 0

        def start_then_report() -> None:
            nonlocal restart_calls
            restart_calls += 1
            self.runtime.events.append("restart")
            self.runtime.restarts += 1
            self.runtime.shell_running = True
            if restart_calls == 1:
                raise RuntimeFailure("injected post-launch timeout")

        def recording_restore(*args: object) -> None:
            self.runtime.events.append("restore")
            self.assertFalse(
                self.runtime.shell_running,
                "rollback restored plugin roots while the shell was running",
            )
            original_restore(*args)

        self.runtime.events.clear()
        with patch.object(
            self.runtime, "restart_shell", side_effect=start_then_report
        ), patch.object(
            transaction_module, "_restore_records", side_effect=recording_restore
        ):
            with self.assertRaisesRegex(
                RuntimeFailure, "injected post-launch timeout"
            ):
                command_update(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(restart_calls, 2)
        self.assertEqual(self.runtime.events.count("stop"), 2)
        self.assertLess(
            [
                index
                for index, event in enumerate(self.runtime.events)
                if event == "stop"
            ][1],
            self.runtime.events.index("restore"),
        )
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(self.hidden_transaction_paths())

    def test_update_verification_failure_drains_before_live_restore(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.center"
        target_file = self.paths.plugin_dir / plugin_id / "BarWidget.qml"
        source_file = self.source / plugin_id / "BarWidget.qml"
        old_payload = target_file.read_bytes()
        old_state = (self.paths.state_dir / "install.json").read_bytes()
        source_file.write_text(
            source_file.read_text(encoding="utf-8")
            + "\n// verification rollback fixture\n",
            encoding="utf-8",
        )
        self.suite = Suite.load(self.source)
        self.runtime.events.clear()

        with patch.object(
            self.runtime,
            "verify_update",
            side_effect=RuntimeFailure("injected update verification failure"),
        ):
            with self.assertRaisesRegex(
                RuntimeFailure, "injected update verification failure"
            ):
                command_update(self.args(), self.suite, self.paths, self.runtime)

        self.assertEqual(
            self.runtime.events, ["stop", "restart", "stop", "restart"]
        )
        self.assertEqual(target_file.read_bytes(), old_payload)
        self.assertEqual(
            (self.paths.state_dir / "install.json").read_bytes(), old_state
        )
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(self.hidden_transaction_paths())

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

        self.close_transaction_descriptors(transaction)
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
        original_atomic_write = transaction_module.atomic_write
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

        def recording_atomic_write(
            path: Path, payload: bytes, mode: int = 0o600
        ) -> None:
            original_atomic_write(path, payload, mode)
            if path.name == "journal.json":
                events.append(("journal-durable", path))

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
                transaction_module,
                "atomic_write",
                side_effect=recording_atomic_write,
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
            and event == ("journal-durable", transaction.journal_file)
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
        exposing_journal = next(
            index
            for index, event in enumerate(events)
            if event[0] == "journal:exposing"
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
        self.assertLess(staged_journal, exposing_journal)
        self.assertLess(exposing_journal, exposure_index)
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

                opened_snapshot_descriptors: list[int] = []
                original_open_snapshot = (
                    transaction_module._open_snapshot_descriptor
                )

                def recording_open_snapshot(*args: object) -> int:
                    descriptor = original_open_snapshot(*args)
                    opened_snapshot_descriptors.append(descriptor)
                    return descriptor

                with (
                    patch.object(
                        transaction_module,
                        "atomic_write",
                        side_effect=faulting_atomic_write,
                    ),
                    patch.object(
                        transaction_module,
                        "_open_snapshot_descriptor",
                        side_effect=recording_open_snapshot,
                    ),
                ):
                    with self.assertRaisesRegex(
                        OSError, "injected preparation failure"
                    ):
                        PluginTransaction(self.paths, self.runtime)

                for descriptor in opened_snapshot_descriptors:
                    with self.assertRaises(OSError):
                        os.fstat(descriptor)

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

    def test_private_transaction_is_retained_when_public_recovery_fails(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        path.write_bytes(b'{"version":1,"owner":"before"}\n')
        transaction = PluginTransaction(self.paths, self.runtime)
        transaction.write_config(b'{"version":1,"owner":"live"}\n')
        transaction._close_config_parent()
        transaction.snapshot_file.write_bytes(b"x" * (MAX_STATE_BYTES + 1))
        private = transaction.transaction_dir.parent / (
            f"{transaction_module.PREPARATION_PREFIX}1700000000-1-42424242"
        )
        private.mkdir()
        sentinel = private / "sentinel"
        sentinel.write_bytes(b"retain\n")

        with self.assertRaisesRegex(TransactionError, "snapshot.*byte limit"):
            recover_transactions(self.paths, self.runtime)

        self.assertEqual(sentinel.read_bytes(), b"retain\n")
        self.assertTrue(private.is_dir())
        self.assertTrue(transaction.transaction_dir.is_dir())

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

    def test_recovery_rejects_oversized_config_snapshot_without_mutation(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        path.write_bytes(b'{"version":1,"owner":"before"}\n')
        transaction = PluginTransaction(self.paths, self.runtime)
        transaction.write_config(b'{"version":1,"owner":"live"}\n')
        transaction._close_config_parent()
        transaction.snapshot_file.write_bytes(b"x" * (MAX_STATE_BYTES + 1))
        live_before = path.read_bytes()
        journal_before = transaction.journal_file.read_bytes()
        events_before = list(self.runtime.events)

        with self.assertRaisesRegex(TransactionError, "snapshot.*byte limit"):
            recover_transactions(self.paths, self.runtime)

        self.assertEqual(path.read_bytes(), live_before)
        self.assertEqual(transaction.journal_file.read_bytes(), journal_before)
        self.assertEqual(self.runtime.events, events_before)
        self.assertEqual(list(path.parent.glob(f".{path.name}.*")), [])

    def test_in_process_rollback_rejects_replaced_symlinked_or_oversized_snapshot(
        self,
    ) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        original = b'{"version":1,"owner":"before"}\n'
        live = b'{"version":1,"owner":"live"}\n'

        for scenario in ("replacement", "symlink", "oversize"):
            with self.subTest(scenario=scenario):
                atomic_write(path, original)
                transaction = PluginTransaction(self.paths, self.runtime)
                bound_descriptor = transaction._config_snapshot_fd
                bound_identity = transaction._config_snapshot_identity
                self.assertGreaterEqual(bound_descriptor, 0)
                self.assertIsNotNone(bound_identity)
                held = os.fstat(bound_descriptor)
                assert bound_identity is not None
                self.assertEqual(
                    (held.st_dev, held.st_ino), bound_identity[:2]
                )
                transaction.write_config(live)
                transaction.snapshot_file.unlink()
                if scenario == "replacement":
                    transaction.snapshot_file.write_bytes(original)
                    replacement = transaction.snapshot_file.stat()
                    self.assertNotEqual(
                        (replacement.st_dev, replacement.st_ino),
                        bound_identity[:2],
                    )
                elif scenario == "symlink":
                    external = self.root / f"{scenario}.json"
                    external.write_bytes(original)
                    transaction.snapshot_file.symlink_to(external)
                else:
                    transaction.snapshot_file.write_bytes(
                        b"x" * (MAX_STATE_BYTES + 1)
                    )

                events_before = list(self.runtime.events)
                with self.assertRaisesRegex(TransactionError, "snapshot"):
                    transaction.rollback()

                self.assertEqual(path.read_bytes(), live)
                self.assertEqual(self.runtime.events, events_before)
                self.assertTrue(transaction.transaction_dir.is_dir())
                transaction._close_config_parent()
                self.assertEqual(transaction._config_snapshot_fd, -1)
                with self.assertRaises(OSError):
                    os.fstat(bound_descriptor)
                shutil.rmtree(self.paths.state_dir / "transactions")

    def test_in_process_rollback_rejects_in_place_snapshot_change(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        original = b'{"version":1,"owner":"before"}\n'
        live = b'{"version":1,"owner":"live"}\n'
        atomic_write(path, original)
        transaction = PluginTransaction(self.paths, self.runtime)
        bound_identity = transaction._config_snapshot_identity
        assert bound_identity is not None
        transaction.write_config(live)

        transaction.snapshot_file.write_bytes(
            b'{"version":1,"owner":"foreign"}\n'
        )
        changed = transaction.snapshot_file.stat()
        self.assertEqual((changed.st_dev, changed.st_ino), bound_identity[:2])
        events_before = list(self.runtime.events)

        with self.assertRaisesRegex(TransactionError, "snapshot content changed"):
            transaction.rollback()

        self.assertEqual(path.read_bytes(), live)
        self.assertEqual(self.runtime.events, events_before)
        transaction._close_config_parent()
        shutil.rmtree(self.paths.state_dir / "transactions")

    def test_config_snapshot_rebinds_after_drained_baseline_refresh(self) -> None:
        path = self.paths.config_file
        path.parent.mkdir(parents=True)
        original = b'{"version":1,"owner":"before"}\n'
        post_stop = b'{"version":1,"owner":"post-stop"}\n'
        path.write_bytes(original)
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        first_descriptor = transaction._config_snapshot_fd
        first_identity = transaction._config_snapshot_identity
        assert first_identity is not None

        transaction.stop_shell()
        atomic_write(path, post_stop)
        refreshed = transaction.refresh_config_after_stop()

        second_descriptor = transaction._config_snapshot_fd
        second_identity = transaction._config_snapshot_identity
        assert second_identity is not None
        self.assertEqual(refreshed["owner"], "post-stop")
        self.assertEqual(transaction._config_snapshot_payload(), post_stop)
        self.assertNotEqual(second_descriptor, first_descriptor)
        self.assertNotEqual(second_identity[:2], first_identity[:2])
        with self.assertRaises(OSError):
            os.fstat(first_descriptor)

        transaction.snapshot_file.unlink()
        transaction.snapshot_file.write_bytes(post_stop)
        replacement = transaction.snapshot_file.stat()
        self.assertNotEqual(
            (replacement.st_dev, replacement.st_ino), second_identity[:2]
        )
        with self.assertRaisesRegex(TransactionError, "snapshot was replaced"):
            transaction.rollback()

        transaction._close_config_parent()
        with self.assertRaises(OSError):
            os.fstat(second_descriptor)
        shutil.rmtree(self.paths.state_dir / "transactions")

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
            "invalid live mutation boolean",
            "inconsistent pre-exposure phase",
            "missing parent identity",
            "boolean parent device",
            "extra parent identity field",
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
                    "schemaVersion": JOURNAL_SCHEMA_VERSION,
                    "suiteId": "hancore.shibumi",
                    "token": token,
                    "phase": "prepared",
                    "pluginRoot": str(self.paths.plugin_dir.resolve()),
                    "configPath": str(self.paths.config_file.resolve()),
                    "configParentIdentity": {
                        "device": self.paths.config_file.parent.stat().st_dev,
                        "inode": self.paths.config_file.parent.stat().st_ino,
                    },
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
                elif scenario == "invalid live mutation boolean":
                    assert isinstance(journal, dict)
                    journal["liveMutationStarted"] = "false"
                elif scenario == "inconsistent pre-exposure phase":
                    assert isinstance(journal, dict)
                    journal["phase"] = "exposed"
                    journal["liveMutationStarted"] = False
                elif scenario == "missing parent identity":
                    assert isinstance(journal, dict)
                    journal.pop("configParentIdentity")
                elif scenario == "boolean parent device":
                    assert isinstance(journal, dict)
                    journal["configParentIdentity"]["device"] = True
                elif scenario == "extra parent identity field":
                    assert isinstance(journal, dict)
                    journal["configParentIdentity"]["path"] = str(
                        self.paths.config_file.parent
                    )
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
            "install state post-write",
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

                if boundary == "install state post-write":
                    original_atomic_write = transaction_module.atomic_write

                    def fail_after_state_write(
                        path: Path,
                        payload: bytes,
                        mode: int = 0o600,
                        *,
                        on_durable: Callable[[], None] | None = None,
                    ) -> None:
                        original_atomic_write(
                            path, payload, mode, on_durable=on_durable
                        )
                        if path == self.paths.state_dir / "install.json":
                            raise OSError("injected post-write state failure")

                    fault = patch.object(
                        transaction_module,
                        "atomic_write",
                        side_effect=fail_after_state_write,
                    )
                    expected_phase = "committing"
                elif boundary == "committed journal":
                    original_write_journal = transaction._write_journal

                    def fail_committed(
                        phase: str,
                        desired: object = "unchanged",
                        archive: object = "unchanged",
                        *,
                        on_durable: Callable[[], None] | None = None,
                    ) -> None:
                        if phase == "committed":
                            raise OSError("injected committed journal failure")
                        original_write_journal(
                            phase, desired, archive, on_durable=on_durable
                        )

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

    def test_shell_started_recovery_drains_before_restoring_payload(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.memory"
        target_file = self.paths.plugin_dir / plugin_id / "BarWidget.qml"
        old_payload = target_file.read_bytes()
        old_config = self.paths.config_file.read_bytes()
        source_file = self.source / plugin_id / "BarWidget.qml"
        source_file.write_text(
            source_file.read_text(encoding="utf-8")
            + "\n// shell-started recovery fixture\n",
            encoding="utf-8",
        )
        suite = Suite.load(self.source)
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stage(
            (suite.plugins[plugin_id],),
            revision="shell-started",
            suite_version=suite.version,
        )
        transaction.stop_shell()
        transaction.expose()
        transaction.write_config(b'{"version":1,"bar":{"id":"broken"}}\n')
        self.runtime.restart_shell()
        transaction.mark_shell_started()
        journal = json.loads(
            transaction.journal_file.read_text(encoding="utf-8")
        )
        self.assertIs(journal["shellStopped"], False)
        self.assertIs(journal["restoreRequiresDrain"], True)
        stops_before = self.runtime.stops

        self.close_transaction_descriptors(transaction)
        self.assertEqual(recover_transactions(self.paths, self.runtime), 1)

        self.assertEqual(self.runtime.stops, stops_before + 1)
        self.assertEqual(target_file.read_bytes(), old_payload)
        self.assertEqual(self.paths.config_file.read_bytes(), old_config)
        self.assertTrue(self.runtime.shell_running)
        self.assertFalse(self.hidden_transaction_paths())

    def test_recovery_rejects_external_target_before_stopping_shell(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.memory"
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stage(
            (self.suite.plugins[plugin_id],),
            revision="external-target",
            suite_version=self.suite.version,
        )
        transaction.stop_shell()
        transaction.expose()
        self.runtime.restart_shell()

        target = self.paths.plugin_dir / plugin_id
        shutil.rmtree(target)
        target.mkdir()
        (target / "external.txt").write_text("foreign\n", encoding="utf-8")
        stops_before = self.runtime.stops

        self.close_transaction_descriptors(transaction)
        with self.assertRaisesRegex(
            TransactionError, "externally changed target"
        ):
            recover_transactions(self.paths, self.runtime)

        self.assertEqual(self.runtime.stops, stops_before)
        self.assertTrue(self.runtime.shell_running)
        self.assertTrue(transaction.transaction_dir.is_dir())
        self.assertEqual(
            (target / "external.txt").read_text(encoding="utf-8"), "foreign\n"
        )

    def test_recovery_rejects_external_new_target_before_stopping_shell(self) -> None:
        self.install()
        plugin_id = "hancore.shibumi.memory"
        target = self.paths.plugin_dir / plugin_id
        shutil.rmtree(target)
        transaction = PluginTransaction(
            self.paths, self.runtime, restart_on_reconcile=True
        )
        transaction.stage(
            (self.suite.plugins[plugin_id],),
            revision="external-new-target",
            suite_version=self.suite.version,
        )
        self.assertIs(transaction.records[0]["hadTarget"], False)
        transaction.stop_shell()
        transaction.expose()
        self.runtime.restart_shell()

        shutil.rmtree(target)
        target.mkdir()
        (target / "external.txt").write_text("foreign\n", encoding="utf-8")
        stops_before = self.runtime.stops

        self.close_transaction_descriptors(transaction)
        with self.assertRaisesRegex(
            TransactionError, "externally changed target"
        ):
            recover_transactions(self.paths, self.runtime)

        self.assertEqual(self.runtime.stops, stops_before)
        self.assertTrue(self.runtime.shell_running)
        self.assertTrue(transaction.transaction_dir.is_dir())
        self.assertEqual(
            (target / "external.txt").read_text(encoding="utf-8"), "foreign\n"
        )

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
        journal.pop("restoreRequiresDrain")
        transaction.journal_file.write_text(
            json.dumps(journal, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        reloads_before = self.runtime.payload_reloads
        self.runtime.fail_restart_count = 1

        self.close_transaction_descriptors(transaction)
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
                    "_atomic_replace_at",
                    side_effect=OSError("injected configuration restore failure"),
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

                self.close_transaction_descriptors(transaction)
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
