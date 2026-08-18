#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LINTER = ROOT / "scripts/check-production-boundary"


class ProductionBoundaryRegressionTests(unittest.TestCase):
    def run_linter(self, root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(LINTER), "--root", str(root)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

    def fixture_result(
        self, source: str, name: str = "Service.qml"
    ) -> subprocess.CompletedProcess[str]:
        temporary = tempfile.TemporaryDirectory(prefix="shibumi-boundary-test.")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        plugin = root / "hancore.shibumi.fixture"
        plugin.mkdir()
        (plugin / name).write_text(source, encoding="utf-8")
        return self.run_linter(root)

    def test_shipped_source_passes(self) -> None:
        result = self.run_linter(ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("production boundary check passed", result.stdout)

    def test_direct_forbidden_boundaries_fail_closed(self) -> None:
        cases = {
            "absolute-component": (
                'property string source: "/usr/share/omarchy/shell/plugins/'
                'services/example/Service.qml"\n',
                "private component path",
            ),
            "relative-component": (
                'property string source: "shell/plugins/services/example.qml"\n',
                "private component path",
            ),
            "registry-provider": (
                'property var backend: bar.registeredWidgetSource('
                '"omarchy.example")\n',
                "private provider QML",
            ),
            "first-party-service": (
                'property var backend: shell.firstPartyServiceFor('
                '"omarchy.example")\n',
                "undeclared first-party service",
            ),
            "helper-state": (
                'property var command: ["omarchy-example-status"]\n',
                "helper-backed state polling",
            ),
            "root-escape": (
                'import "../services" as Services\n',
                "package escape",
            ),
        }
        for name, (source, expected) in cases.items():
            with self.subTest(name=name):
                result = self.fixture_result(source)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(expected, result.stderr)

    def test_all_executables_are_scanned_and_invalid_utf8_fails(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="shibumi-boundary-test."
        ) as temporary:
            root = Path(temporary)
            plugin = root / "hancore.shibumi.fixture"
            plugin.mkdir()
            executable = plugin / "probe.bin"
            executable.write_text("omarchy-example-status\n", encoding="utf-8")
            executable.chmod(0o755)
            result = self.run_linter(root)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("helper-backed state polling", result.stderr)

            executable.write_text("#!/bin/sh\npgrep example\n", encoding="utf-8")
            result = self.run_linter(root)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("helper-backed state polling", result.stderr)

            executable.write_bytes(b"#!/bin/sh\n\xff\n")
            result = self.run_linter(root)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("undecodable production source", result.stderr)

    def test_production_symlinks_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="shibumi-boundary-test."
        ) as temporary:
            root = Path(temporary)
            payload = root / "payload"
            payload.mkdir()
            (payload / "Service.qml").write_text(
                "property bool safe: true\n", encoding="utf-8"
            )
            plugin = root / "hancore.shibumi.fixture"
            plugin.symlink_to(payload.name, target_is_directory=True)
            result = self.run_linter(root)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("production symlink", result.stderr)

        with tempfile.TemporaryDirectory(
            prefix="shibumi-boundary-test."
        ) as temporary:
            root = Path(temporary)
            plugin = root / "hancore.shibumi.fixture"
            plugin.mkdir()
            target = plugin / "payload.bin"
            target.write_text("property bool safe: true\n", encoding="utf-8")
            (plugin / "Service.qml").symlink_to(target.name)
            result = self.run_linter(root)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("production symlink", result.stderr)

    def test_removed_debt_requires_allowance_cleanup(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="shibumi-boundary-test."
        ) as temporary:
            root = Path(temporary)
            plugin = root / "hancore.shibumi.status"
            plugin.mkdir()
            source = (
                ROOT / "hancore.shibumi.status/Service.qml"
            ).read_text(encoding="utf-8")
            (plugin / "Service.qml").write_text(
                source.replace("omarchy-voxtype-status", "voxtype-status"),
                encoding="utf-8",
            )
            result = self.run_linter(root)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("approved omarchy-voxtype-status", result.stderr)

    def test_missing_allowlisted_file_fails_when_plugin_is_present(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="shibumi-boundary-test."
        ) as temporary:
            root = Path(temporary)
            plugin = root / "hancore.shibumi.media"
            plugin.mkdir()
            (plugin / "manifest.json").write_text("{}\n", encoding="utf-8")
            result = self.run_linter(root)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(
                "hancore.shibumi.media/Service.qml: stale boundary allowance",
                result.stderr,
            )

    def test_complete_suite_rejects_allowance_for_missing_plugin(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="shibumi-boundary-test."
        ) as temporary:
            root = Path(temporary)
            contracts = root / "contracts"
            contracts.mkdir()
            (contracts / "plugin-suite-v1.json").write_text(
                "{}\n", encoding="utf-8"
            )
            result = self.run_linter(root)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(
                "hancore.shibumi.audio/BarWidget.qml: stale boundary allowance",
                result.stderr,
            )

    def test_package_job_runs_boundary_regression_directly(self) -> None:
        workflow = (
            ROOT / ".github/workflows/package-release.yml"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "python3 tests/production-boundary-regression.py",
            workflow,
        )


if __name__ == "__main__":
    unittest.main()
