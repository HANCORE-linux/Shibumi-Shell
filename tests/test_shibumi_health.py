#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import runpy
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


REPO_ROOT = Path(__file__).resolve().parents[1]
HEALTH = (
    REPO_ROOT
    / "hancore.shibumi.control-center"
    / "manager"
    / "shibumi-health"
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
        self.remote = self.root / "remote.git"
        self.git("init", "--bare", str(self.remote))
        self.git("init", "-b", "main", str(self.source))
        self.git("config", "user.name", "Health Test", cwd=self.source)
        self.git("config", "user.email", "health@example.invalid", cwd=self.source)
        (self.source / "README.md").write_text("fixture\n", encoding="utf-8")
        self.git("add", "README.md", cwd=self.source)
        self.git("commit", "-m", "fixture", cwd=self.source)
        self.git("remote", "add", "origin", str(self.remote), cwd=self.source)
        self.git("push", "-u", "origin", "main", cwd=self.source)

    def commit_source(self, content: str, message: str = "fixture change") -> None:
        (self.source / "README.md").write_text(content, encoding="utf-8")
        self.git("add", "README.md", cwd=self.source)
        self.git("commit", "-m", message, cwd=self.source)

    def push_remote_commit(self, content: str) -> None:
        writer = self.root / "writer"
        self.git("clone", "--branch", "main", str(self.remote), str(writer))
        self.git("config", "user.name", "Health Remote Test", cwd=writer)
        self.git("config", "user.email", "health-remote@example.invalid", cwd=writer)
        (writer / "README.md").write_text(content, encoding="utf-8")
        self.git("add", "README.md", cwd=writer)
        self.git("commit", "-m", "remote fixture change", cwd=writer)
        self.git("push", "origin", "main", cwd=writer)

    def write_json(self, path: Path, value: object) -> None:
        path.write_text(json.dumps(value) + "\n", encoding="utf-8")

    def write_config(self, value: dict[str, object]) -> None:
        self.write_json(self.config_path, value)

    def write_state(self, value: dict[str, object]) -> None:
        self.write_json(self.state_dir / "install.json", value)

    def use_package_install(
        self,
        *,
        installed_version: str | None = "0.1.1beta.8-1",
        available_version: str | None = None,
        fetch_error: str = "",
    ) -> Path:
        self.state.pop("sourceRoot", None)
        self.state.update(
            {
                "suiteVersion": "0.1.1-beta.8",
                "installOrigin": "package",
                "payloadRoot": "/usr/share/shibumi-shell",
                "sourceRevision": "package:0.1.1-beta.8",
                "packageName": "shibumi-shell",
                "packageVersion": "0.1.1-beta.8",
            }
        )
        self.write_state(self.state)
        fixture: dict[str, object] = {}
        if installed_version is not None:
            fixture["installedVersion"] = installed_version
        if available_version is not None:
            fixture["availableVersion"] = available_version
        if fetch_error:
            fixture["fetchError"] = fetch_error
        path = self.root / "package.json"
        self.write_json(path, fixture)
        self.environment["SHIBUMI_HEALTH_PACKAGE_FILE"] = str(path)
        return path

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

    def git_output(self, *arguments: str) -> str:
        return subprocess.run(
            ["git", "-C", str(self.source), *arguments],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def by_id(self, payload: dict[str, object]) -> dict[str, dict[str, object]]:
        return {item["id"]: item for item in payload["checks"]}

    def process_probe_from_result(
        self,
        *,
        stdout: str = "",
        stderr: str = "",
        returncode: int = 0,
        side_effect: BaseException | None = None,
    ):
        environment = dict(self.environment)
        environment.pop("SHIBUMI_HEALTH_PROCESS_FILE", None)
        environment.pop("SHIBUMI_HEALTH_PROCESS_LIVE", None)
        completed = Mock(returncode=returncode, stdout=stdout, stderr=stderr)
        runner = Mock(return_value=completed, side_effect=side_effect)
        probe_class = self.module["Probe"]
        globals_map = probe_class.load_processes.__globals__
        with patch.dict(os.environ, environment, clear=True):
            probe = probe_class(fetch=False)
            with patch.dict(globals_map, {"run": runner}):
                probe.load_processes()
        probe.check_processes()
        return probe

    def process_probe_from_stdout(self, stdout: str):
        return self.process_probe_from_result(stdout=stdout)

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
        self.assertEqual(payload["installOrigin"], "checkout")

    def test_package_health_uses_pacman_metadata_and_skips_git(self) -> None:
        self.use_package_install()

        payload = self.run_health()
        checks = self.by_id(payload)

        self.assertEqual(payload["overall"], "healthy")
        self.assertEqual(payload["installOrigin"], "package")
        self.assertEqual(payload["packageName"], "shibumi-shell")
        self.assertEqual(payload["packageVersion"], "0.1.1-beta.8")
        self.assertEqual(checks["package-status"]["status"], "ok")
        self.assertEqual(checks["package-status"]["value"], "0.1.1beta.8-1")
        self.assertEqual(checks["package-update"]["value"], "Not checked")
        self.assertNotIn("source-status", checks)
        self.assertNotIn("source-update", checks)

    def test_package_health_reports_unstaged_package_upgrade(self) -> None:
        self.use_package_install(installed_version="0.1.2beta.1-1")

        payload = self.run_health()
        check = self.by_id(payload)["package-status"]

        self.assertEqual(payload["overall"], "warning")
        self.assertEqual(check["status"], "warning")
        self.assertIn("0.1.2beta.1-1 installed", check["value"])
        self.assertIn("shibumi-shell update --yes", check["action"])

    def test_package_fetch_reports_unpublished_aur_candidate(self) -> None:
        self.use_package_install()

        payload = self.run_health("--fetch")
        check = self.by_id(payload)["package-update"]

        self.assertEqual(check["status"], "info")
        self.assertEqual(check["value"], "Not published")

    def test_package_fetch_reports_available_aur_version(self) -> None:
        self.use_package_install(available_version="0.1.2beta.1-1")

        payload = self.run_health("--fetch")
        check = self.by_id(payload)["package-update"]

        self.assertEqual(check["status"], "warning")
        self.assertIn("0.1.2beta.1-1", check["value"])

    def test_package_fetch_failure_is_bounded_without_git_fallback(self) -> None:
        self.use_package_install(fetch_error="fixture offline")

        payload = self.run_health("--fetch")
        checks = self.by_id(payload)

        self.assertEqual(checks["package-update"]["status"], "warning")
        self.assertEqual(checks["package-update"]["value"], "Check failed")
        self.assertIn("fixture offline", checks["package-update"]["detail"])
        self.assertNotIn("source-status", checks)

    def test_package_origin_without_installed_package_is_an_error(self) -> None:
        self.use_package_install(installed_version=None)

        payload = self.run_health()
        check = self.by_id(payload)["package-status"]

        self.assertEqual(payload["overall"], "error")
        self.assertEqual(check["value"], "Not installed")

    def test_dirty_checkout_is_a_warning(self) -> None:
        (self.source / "README.md").write_text("dirty\n", encoding="utf-8")
        payload = self.run_health()
        check = self.by_id(payload)["source-status"]
        self.assertEqual(payload["overall"], "warning")
        self.assertEqual(check["status"], "warning")
        self.assertEqual(check["value"], "Current · dirty")

    def test_ahead_checkout_is_a_warning(self) -> None:
        self.commit_source("ahead\n")
        payload = self.run_health()
        check = self.by_id(payload)["source-status"]
        self.assertEqual(check["status"], "warning")
        self.assertEqual(check["value"], "Ahead 1 · clean")
        self.assertIn("ahead 1, behind 0", check["detail"])

    def test_fetch_detects_behind_checkout_without_changing_head(self) -> None:
        self.push_remote_commit("behind\n")
        before = self.git_output("rev-parse", "HEAD")
        payload = self.run_health("--fetch")
        after = self.git_output("rev-parse", "HEAD")
        checks = self.by_id(payload)
        self.assertEqual(before, after)
        self.assertEqual(checks["source-update"]["status"], "ok")
        self.assertEqual(
            checks["source-status"]["value"], "Update available · clean"
        )
        self.assertIn("ahead 0, behind 1", checks["source-status"]["detail"])

    def test_fetch_detects_diverged_checkout(self) -> None:
        self.commit_source("ahead\n")
        self.push_remote_commit("behind\n")
        payload = self.run_health("--fetch")
        check = self.by_id(payload)["source-status"]
        self.assertEqual(check["status"], "error")
        self.assertEqual(check["value"], "Diverged · clean")
        self.assertIn("ahead 1, behind 1", check["detail"])

    def test_missing_upstream_fails_closed(self) -> None:
        self.git("branch", "--unset-upstream", cwd=self.source)
        payload = self.run_health()
        check = self.by_id(payload)["source-status"]
        self.assertEqual(check["status"], "warning")
        self.assertEqual(check["value"], "Check failed")
        self.assertIn("upstream", check["action"].lower())

    def test_offline_fetch_preserves_cached_source_status(self) -> None:
        self.git(
            "remote",
            "set-url",
            "origin",
            str(self.root / "offline.git"),
            cwd=self.source,
        )
        payload = self.run_health("--fetch")
        checks = self.by_id(payload)
        self.assertEqual(checks["source-update"]["status"], "warning")
        self.assertEqual(checks["source-update"]["value"], "Check failed")
        self.assertEqual(checks["source-status"]["value"], "Current · clean")

    def test_hard_fetch_timeout_is_bounded_and_reported(self) -> None:
        real_git = shutil.which("git")
        self.assertIsNotNone(real_git)
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        fake_git = fake_bin / "git"
        fake_git.write_text(
            "#!/usr/bin/env python3\n"
            "import os, sys, time\n"
            "if 'fetch' in sys.argv:\n"
            "    time.sleep(10)\n"
            f"os.execv({real_git!r}, [{real_git!r}, *sys.argv[1:]])\n",
            encoding="utf-8",
        )
        fake_git.chmod(0o755)
        self.environment["PATH"] = (
            str(fake_bin) + os.pathsep + self.environment["PATH"]
        )
        self.environment["SHIBUMI_HEALTH_FETCH_TIMEOUT"] = "0.05"

        payload = self.run_health("--fetch")
        check = self.by_id(payload)["source-update"]
        self.assertEqual(check["status"], "warning")
        self.assertEqual(check["value"], "Check failed")
        self.assertIn("timed out", check["detail"])

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

    def test_empty_quickshell_registry_sentinel_reports_zero_processes(self) -> None:
        probe = self.process_probe_from_stdout(QUICKSHELL_EMPTY_REGISTRY)
        checks = [check for check in probe.checks if check.id == "quickshell-process"]
        self.assertFalse(probe.process_probe_failed)
        self.assertEqual(probe.processes, [])
        self.assertEqual(probe.production_pids, [])
        self.assertEqual(len(checks), 1)
        self.assertEqual(checks[0].value, "0 production processes")

    def test_empty_registry_sentinel_with_nonzero_exit_fails_closed(self) -> None:
        probe = self.process_probe_from_result(
            stdout=QUICKSHELL_EMPTY_REGISTRY,
            stderr="registry unavailable",
            returncode=23,
        )
        checks = [check for check in probe.checks if check.id == "quickshell-process"]
        self.assertTrue(probe.process_probe_failed)
        self.assertEqual(probe.processes, [])
        self.assertEqual(len(checks), 1)
        self.assertEqual(checks[0].value, "Check failed")
        self.assertIn("registry unavailable", checks[0].detail)

    def test_empty_registry_sentinel_timeout_fails_closed(self) -> None:
        timeout = subprocess.TimeoutExpired(
            ["qs", "list", "--all", "--json"],
            0.01,
            output=QUICKSHELL_EMPTY_REGISTRY,
        )
        probe = self.process_probe_from_result(side_effect=timeout)
        checks = [check for check in probe.checks if check.id == "quickshell-process"]
        self.assertTrue(probe.process_probe_failed)
        self.assertEqual(probe.processes, [])
        self.assertEqual(len(checks), 1)
        self.assertEqual(checks[0].value, "Check failed")
        self.assertIn("timed out", checks[0].detail)

    def test_quickshell_registry_json_arrays_remain_supported(self) -> None:
        probe = self.process_probe_from_stdout("[]")
        self.assertFalse(probe.process_probe_failed)
        self.assertEqual(probe.processes, [])

        instance = {
            "id": "target-1",
            "config_path": str(self.omarchy / "shell/shell.qml"),
            "pid": 4242,
        }
        probe = self.process_probe_from_stdout(json.dumps([instance]))
        self.assertFalse(probe.process_probe_failed)
        self.assertEqual(probe.processes, [instance])
        self.assertEqual(probe.production_pids, [4242])

    def test_empty_registry_sentinel_variants_fail_closed(self) -> None:
        for stdout in INVALID_EMPTY_REGISTRY_OUTPUTS:
            with self.subTest(stdout=stdout):
                probe = self.process_probe_from_stdout(stdout)
                checks = [
                    check
                    for check in probe.checks
                    if check.id == "quickshell-process"
                ]
                self.assertTrue(probe.process_probe_failed)
                self.assertEqual(len(checks), 1)
                self.assertEqual(checks[0].value, "Check failed")

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

    def test_failed_runtime_log_query_never_reports_clean(self) -> None:
        environment = dict(self.environment)
        environment.pop("SHIBUMI_HEALTH_LOG_FILE", None)
        probe_class = self.module["Probe"]
        globals_map = probe_class.check_logs.__globals__
        failed = Mock(
            returncode=23,
            stdout="",
            stderr=f"registry unavailable at {self.home}/private.log",
        )
        with patch.dict(os.environ, environment, clear=True):
            probe = probe_class(fetch=False)
            probe.production_pids = [4242]
            with patch.dict(globals_map, {"run": Mock(return_value=failed)}):
                probe.check_logs()
        checks = [
            check for check in probe.checks if check.id == "runtime-errors"
        ]
        self.assertEqual(len(checks), 1)
        self.assertEqual(checks[0].status, "warning")
        self.assertEqual(checks[0].value, "Log unavailable")
        self.assertIn("registry unavailable", checks[0].detail)
        self.assertNotIn(str(self.home), checks[0].detail)
        self.assertNotEqual(checks[0].value, "None detected")

    def test_failed_runtime_log_query_redacts_sensitive_output(self) -> None:
        environment = dict(self.environment)
        environment.pop("SHIBUMI_HEALTH_LOG_FILE", None)
        probe_class = self.module["Probe"]
        globals_map = probe_class.check_logs.__globals__
        failed = Mock(
            returncode=9,
            stdout="",
            stderr="password token private-value",
        )
        with patch.dict(os.environ, environment, clear=True):
            probe = probe_class(fetch=False)
            probe.production_pids = [4242]
            with patch.dict(globals_map, {"run": Mock(return_value=failed)}):
                probe.check_logs()
        check = next(
            check for check in probe.checks if check.id == "runtime-errors"
        )
        self.assertEqual(check.status, "warning")
        self.assertEqual(check.detail, "qs log exited with 9")
        self.assertNotIn("private-value", check.detail)

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
