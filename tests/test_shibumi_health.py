#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HEALTH = (
    REPO_ROOT
    / "hancore.shibumi.control-center"
    / "manager"
    / "shibumi-health"
)


class HealthDiagnosticsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="shibumi-health-test.")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.config_home = self.home / ".config"
        self.state_home = self.home / ".local/state"
        self.plugin_dir = self.config_home / "omarchy/plugins"
        self.state_dir = self.state_home / "shibumi"
        self.omarchy = self.root / "omarchy"
        self.source = self.root / "source"
        for path in (
            self.plugin_dir,
            self.state_dir,
            self.omarchy / "config/omarchy",
            self.omarchy / "bin",
            self.config_home / "omarchy",
        ):
            path.mkdir(parents=True, exist_ok=True)

        self.module = runpy.run_path(str(HEALTH))
        self.plugin_ids = ["hancore.shibumi.bar", "hancore.shibumi.state"]
        digests = {}
        for plugin_id in self.plugin_ids:
            target = self.plugin_dir / plugin_id
            target.mkdir()
            (target / "manifest.json").write_text(
                json.dumps({"id": plugin_id}) + "\n", encoding="utf-8"
            )
            digest = self.module["payload_digest"](target)
            digests[plugin_id] = digest
            (target / ".shibumi-managed.json").write_text(
                json.dumps(
                    {
                        "suiteId": "hancore.shibumi",
                        "pluginId": plugin_id,
                        "payloadDigest": digest,
                    }
                )
                + "\n",
                encoding="utf-8",
            )

        self.config = {
            "version": 1,
            "bar": {
                "id": "hancore.shibumi.bar",
                "position": "top",
                "shibumi": {"presentation": {"shellStyle": "full"}},
            },
        }
        self.config_path = self.config_home / "omarchy/shell.json"
        self.write_config(self.config)
        (self.omarchy / "config/omarchy/shell.json").write_text(
            json.dumps(self.config) + "\n", encoding="utf-8"
        )

        self.make_git_source()
        self.state = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": "0.1.0",
            "sourceRoot": str(self.source),
            "plugins": self.plugin_ids,
            "pluginDigests": digests,
            "activation": {
                "activeBar": "hancore.shibumi.bar",
                "layout": {"left": [], "center": [], "right": []},
                "enableServices": ["hancore.shibumi.state"],
            },
        }
        self.write_state(self.state)

        self.registry_file = self.root / "registry.json"
        self.registry = [
            {
                "id": "hancore.shibumi.bar",
                "kinds": ["bar"],
                "enabled": True,
                "active": True,
            },
            {
                "id": "hancore.shibumi.state",
                "kinds": ["service"],
                "enabled": True,
                "active": False,
            },
            {
                "id": "omarchy.bar",
                "kinds": ["bar"],
                "enabled": False,
                "active": False,
            },
        ]
        self.write_json(self.registry_file, self.registry)
        self.process_file = self.root / "processes.json"
        self.write_json(
            self.process_file,
            [
                {
                    "pid": 4242,
                    "command": "quickshell -n -p /usr/share/omarchy/shell",
                    "config_path": str(self.omarchy / "shell/shell.qml"),
                }
            ],
        )
        self.output_file = self.root / "outputs.json"
        self.write_json(
            self.output_file,
            [{"name": "eDP-1", "scale": 1.0, "width": 1920, "height": 1080}],
        )
        self.log_file = self.root / "quickshell.log"
        self.log_file.write_text("INFO Configuration Loaded\n", encoding="utf-8")

        self.environment = os.environ.copy()
        self.environment.update(
            {
                "SHIBUMI_HEALTH_HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.state_home),
                "SHIBUMI_PLUGIN_DIR": str(self.plugin_dir),
                "SHIBUMI_STATE_DIR": str(self.state_dir),
                "SHIBUMI_CONFIG_FILE": str(self.config_path),
                "OMARCHY_PATH": str(self.omarchy),
                "SHIBUMI_HEALTH_SOURCE_ROOT": str(self.source),
                "SHIBUMI_HEALTH_REGISTRY_FILE": str(self.registry_file),
                "SHIBUMI_HEALTH_PROCESS_FILE": str(self.process_file),
                "SHIBUMI_HEALTH_PROCESS_LIVE": "true",
                "SHIBUMI_HEALTH_OUTPUT_FILE": str(self.output_file),
                "SHIBUMI_HEALTH_LOG_FILE": str(self.log_file),
            }
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def git(self, *arguments: str, cwd: Path | None = None) -> None:
        subprocess.run(
            ["git", *(arguments)],
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True,
        )

    def make_git_source(self) -> None:
        remote = self.root / "remote.git"
        self.git("init", "--bare", str(remote))
        self.git("init", "-b", "main", str(self.source))
        self.git("config", "user.name", "Health Test", cwd=self.source)
        self.git("config", "user.email", "health@example.invalid", cwd=self.source)
        (self.source / "README.md").write_text("fixture\n", encoding="utf-8")
        self.git("add", "README.md", cwd=self.source)
        self.git("commit", "-m", "fixture", cwd=self.source)
        self.git("remote", "add", "origin", str(remote), cwd=self.source)
        self.git("push", "-u", "origin", "main", cwd=self.source)

    def write_json(self, path: Path, value: object) -> None:
        path.write_text(json.dumps(value) + "\n", encoding="utf-8")

    def write_config(self, value: dict[str, object]) -> None:
        self.write_json(self.config_path, value)

    def write_state(self, value: dict[str, object]) -> None:
        self.write_json(self.state_dir / "install.json", value)

    def run_health(self, *arguments: str) -> dict[str, object]:
        result = subprocess.run(
            [str(HEALTH), *arguments],
            env=self.environment,
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
        return json.loads(result.stdout)

    def by_id(self, payload: dict[str, object]) -> dict[str, dict[str, object]]:
        return {item["id"]: item for item in payload["checks"]}

    def test_healthy_runtime_is_structured_and_read_only(self) -> None:
        payload = self.run_health()
        checks = self.by_id(payload)
        self.assertEqual(payload["schemaVersion"], 1)
        self.assertEqual(payload["overall"], "healthy")
        self.assertEqual(checks["bar-runtime"]["status"], "ok")
        self.assertEqual(checks["bar-runtime"]["label"], "Active bar")
        self.assertEqual(checks["bar-runtime"]["value"], "Shibumi V2")
        self.assertEqual(checks["managed-plugins"]["label"], "Shibumi plugins")
        self.assertEqual(checks["managed-plugins"]["value"], "2/2 installed")
        self.assertEqual(checks["source-status"]["value"], "Current · clean")
        self.assertEqual(checks["source-update"]["value"], "Not checked")

    def test_dirty_checkout_is_a_warning(self) -> None:
        (self.source / "README.md").write_text("dirty\n", encoding="utf-8")
        payload = self.run_health()
        check = self.by_id(payload)["source-status"]
        self.assertEqual(payload["overall"], "warning")
        self.assertEqual(check["status"], "warning")
        self.assertEqual(check["value"], "Current · dirty")

    def test_inactive_managed_widget_is_not_a_runtime_failure(self) -> None:
        self.state["activation"]["enableServices"] = []
        self.write_state(self.state)
        self.registry[1]["kinds"] = ["bar-widget", "service"]
        self.registry[1]["enabled"] = False
        self.write_json(self.registry_file, self.registry)

        payload = self.run_health()
        check = self.by_id(payload)["plugin-activation"]
        self.assertEqual(payload["overall"], "healthy")
        self.assertEqual(check["status"], "ok")
        self.assertEqual(check["value"], "1/1 required enabled")

    def test_duplicate_process_and_stale_payload_are_errors(self) -> None:
        production_config = str(self.omarchy / "shell/shell.qml")
        self.write_json(
            self.process_file,
            [
                {
                    "pid": 1,
                    "command": "quickshell -p /usr/share/omarchy/shell",
                    "config_path": production_config,
                },
                {
                    "pid": 2,
                    "command": "quickshell -p /usr/share/omarchy/shell",
                    "config_path": production_config,
                },
            ],
        )
        target = self.plugin_dir / "hancore.shibumi.state/Service.qml"
        target.write_text("changed\n", encoding="utf-8")
        payload = self.run_health()
        checks = self.by_id(payload)
        self.assertEqual(payload["overall"], "error")
        self.assertEqual(checks["quickshell-process"]["status"], "error")
        self.assertEqual(checks["managed-plugins"]["status"], "error")
        self.assertIn("modified/stale", checks["managed-plugins"]["detail"])

    def test_argumentless_crash_relaunch_uses_registered_config(self) -> None:
        self.write_json(
            self.process_file,
            [
                {
                    "pid": 4242,
                    "command": "/usr/bin/quickshell",
                    "config_path": str(self.omarchy / "shell/shell.qml"),
                    "shell_id": "crash-relaunch-fixture",
                }
            ],
        )
        payload = self.run_health()
        check = self.by_id(payload)["quickshell-process"]
        self.assertEqual(payload["overall"], "healthy")
        self.assertEqual(check["status"], "ok")
        self.assertEqual(check["value"], "1 production process")

    def test_foreign_instance_does_not_count_as_production(self) -> None:
        self.write_json(
            self.process_file,
            [
                {
                    "pid": 4242,
                    "command": "/usr/bin/quickshell",
                    "config_path": "/tmp/another-shell/shell.qml",
                }
            ],
        )
        payload = self.run_health()
        check = self.by_id(payload)["quickshell-process"]
        self.assertEqual(payload["overall"], "error")
        self.assertEqual(check["status"], "error")
        self.assertEqual(check["value"], "0 production processes")

    def test_registered_but_unresponsive_instance_is_an_error(self) -> None:
        self.environment["SHIBUMI_HEALTH_PROCESS_LIVE"] = "false"
        payload = self.run_health()
        check = self.by_id(payload)["quickshell-process"]
        self.assertEqual(payload["overall"], "error")
        self.assertEqual(check["status"], "error")
        self.assertEqual(check["value"], "Production process unresponsive")

    def test_malformed_instance_registry_reports_one_process_error(self) -> None:
        self.write_json(self.process_file, {"pid": 4242})
        payload = self.run_health()
        process_checks = [
            item for item in payload["checks"]
            if item["id"] == "quickshell-process"
        ]
        self.assertEqual(len(process_checks), 1)
        self.assertEqual(process_checks[0]["value"], "Check failed")

    def test_bar_mismatch_and_failed_lifecycle_are_errors(self) -> None:
        self.registry[0]["active"] = False
        self.registry[2]["active"] = True
        self.write_json(self.registry_file, self.registry)
        self.write_json(
            self.state_dir / "switch-status.json",
            {
                "phase": "error",
                "detail": "verification did not settle",
                "updatedEpoch": int(__import__("time").time()),
            },
        )
        payload = self.run_health()
        checks = self.by_id(payload)
        self.assertEqual(checks["bar-runtime"]["status"], "error")
        self.assertEqual(checks["lifecycle"]["value"], "Last switch failed")

    def test_logs_are_filtered_redacted_and_bounded(self) -> None:
        self.log_file.write_text(
            "TypeError from the previous configuration\n"
            "INFO Configuration Loaded\n"
            "TypeError in /home/test/Widget.qml\n"
            "TypeError password token SSID private-value\n",
            encoding="utf-8",
        )
        payload = self.run_health()
        check = self.by_id(payload)["runtime-errors"]
        self.assertEqual(check["status"], "error")
        self.assertIn("~/Widget.qml", check["detail"])
        self.assertNotIn("previous configuration", check["detail"])
        self.assertNotIn("private-value", check["detail"])

    def test_resolved_log_errors_do_not_leak_across_reload(self) -> None:
        self.log_file.write_text(
            "ReferenceError from old payload\n"
            "INFO Configuration Loaded\n"
            "INFO current payload settled\n",
            encoding="utf-8",
        )
        payload = self.run_health()
        check = self.by_id(payload)["runtime-errors"]
        self.assertEqual(check["status"], "ok")
        self.assertEqual(check["value"], "None detected")

    def test_manual_fetch_refreshes_only_remote_refs(self) -> None:
        before = subprocess.run(
            ["git", "-C", str(self.source), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        payload = self.run_health("--fetch")
        after = subprocess.run(
            ["git", "-C", str(self.source), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        self.assertEqual(before, after)
        self.assertEqual(self.by_id(payload)["source-update"]["status"], "ok")


if __name__ == "__main__":
    unittest.main()
