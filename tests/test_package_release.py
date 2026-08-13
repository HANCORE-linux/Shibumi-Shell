#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import importlib.machinery
import importlib.util
import json
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


class PackageReleaseTests(unittest.TestCase):
    def test_versions_and_all_plugin_manifests_agree(self) -> None:
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        suite = json.loads(
            (ROOT / "contracts/plugin-suite-v1.json").read_text(encoding="utf-8")
        )
        marker = json.loads(
            (ROOT / "packaging/package-metadata.json").read_text(encoding="utf-8")
        )
        self.assertEqual(version, "0.1.1-beta.8")
        self.assertEqual(suite["suiteVersion"], version)
        self.assertEqual(marker["version"], version)
        for plugin in suite["plugins"]:
            manifest = json.loads(
                (ROOT / plugin["id"] / "manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(manifest["version"], version, plugin["id"])

    def test_user_visible_plugin_count_matches_suite_contract(self) -> None:
        suite = json.loads(
            (ROOT / "contracts/plugin-suite-v1.json").read_text(encoding="utf-8")
        )
        preview = (
            ROOT
            / "hancore.shibumi.control-center"
            / "SemanticPreviewImage.qml"
        ).read_text(encoding="utf-8")
        count = len(suite["plugins"])
        self.assertEqual(count, 24)
        self.assertIn(f'value: "{count} / {count}"', preview)
        self.assertNotIn('value: "25 / 25"', preview)

    def test_package_boundary_has_no_user_mutation_hook(self) -> None:
        pkgbuild = (ROOT / "packaging/aur/PKGBUILD").read_text(encoding="utf-8")
        self.assertIn('/usr/share/$pkgname', pkgbuild)
        self.assertIn('"$pkgdir/usr/bin/shibumi-shell"', pkgbuild)
        self.assertNotIn("$HOME", pkgbuild)
        self.assertNotIn(".config/omarchy", pkgbuild)
        hooks = list((ROOT / "packaging").rglob("*.install"))
        hooks += list((ROOT / "packaging").rglob("*.hook"))
        self.assertEqual(hooks, [])

    def test_release_workflow_uses_curated_notes(self) -> None:
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        workflow = (ROOT / ".github/workflows/package-release.yml").read_text(
            encoding="utf-8"
        )
        notes = ROOT / f".github/release-notes/v{version}.md"
        self.assertTrue(notes.is_file())
        self.assertIn('--notes-file "$notes_file"', workflow)
        self.assertNotIn("--generate-notes", workflow)

    def test_release_channel_distinguishes_prerelease_and_stable_versions(self) -> None:
        selector = ROOT / "scripts/release-channel-flag"
        for version, expected in (
            ("0.1.1-beta.8", "--prerelease"),
            ("0.1.1-rc.1+build.7", "--prerelease"),
            ("0.1.1", "--latest"),
            ("1.0.0+build.7", "--latest"),
        ):
            with self.subTest(version=version):
                result = subprocess.run(
                    [str(selector), version],
                    check=True,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.stdout.strip(), expected)

        for version in (
            "",
            "stable",
            "1.2",
            "01.2.3",
            "1.2.3-",
            "1.2.3-alpha..1",
            "1.2.3-01",
            "1.2.3+",
        ):
            with self.subTest(invalid_version=version):
                result = subprocess.run(
                    [str(selector), version],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")

        workflow = (ROOT / ".github/workflows/package-release.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            'release_channel=$(scripts/release-channel-flag "$version")',
            workflow,
        )
        self.assertIn('            "$release_channel" \\', workflow)
        self.assertNotIn("            --prerelease \\", workflow)

    def test_release_workflow_pins_checkout_v7_without_persisted_tokens(self) -> None:
        workflow = (ROOT / ".github/workflows/package-release.yml").read_text(
            encoding="utf-8"
        )
        checkout_uses = [
            line.strip()
            for line in workflow.splitlines()
            if "uses: actions/checkout@" in line
        ]
        expected = (
            "uses: actions/checkout@"
            "3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1"
        )
        self.assertEqual(checkout_uses, [expected, expected])
        self.assertEqual(workflow.count("persist-credentials: false"), 2)
        self.assertNotIn("persist-credentials: true", workflow)

    def test_release_workflow_requires_revision_bound_lifecycle_evidence(self) -> None:
        workflow = (ROOT / ".github/workflows/package-release.yml").read_text(
            encoding="utf-8"
        )
        collector = (ROOT / "scripts/collect-release-evidence").read_text(
            encoding="utf-8"
        )
        for contract in (
            "python3 tests/test_shibumi_manager.py",
            "python3 tests/test_inc013_drain_contract.py",
            "scripts/collect-release-evidence",
            '"dist/shibumi-shell-$version.release-evidence.json"',
        ):
            self.assertIn(contract, workflow)
        for gate in (
            "tests/shibumi-suite-quattro-dry-run.sh",
            "tests/shibumi-suite-quattro-runtime.sh",
            "omarchy-installed-package-contract-regression.sh",
            "omarchy-installed-source-parity-contract-regression.sh",
            "omarchy-forward-compat-contract-regression.sh",
        ):
            self.assertIn(gate, collector)
        self.assertIn(
            "needs: package-contract", workflow
        )
        self.assertIn(
            "runs-on: [self-hosted, linux, shibumi-validation]", workflow
        )

    def test_quattro_runtime_isolates_shell_generations_and_cleanup(self) -> None:
        runtime = (ROOT / "tests/shibumi-suite-quattro-runtime.sh").read_text(
            encoding="utf-8"
        )
        readiness = runtime.split("shell_ready=0", 1)[1].split(
            "suite_cli install --yes", 1
        )[0]
        self.assertNotIn("shell_ipc -q", readiness)
        self.assertIn("shell_ipc shell ping", readiness)
        self.assertIn("[[ $shell_ready -eq 1 ]]", readiness)
        self.assertIn('cp -a "$omarchy_path/bin" "$fixture_omarchy/bin"', runtime)
        self.assertNotIn('ln -s "$omarchy_path/bin"', runtime)
        self.assertIn('rm -f "$fixture_omarchy/bin/omarchy-restart-shell"', runtime)
        self.assertIn('"$fixture_omarchy/bin/omarchy-update-available"', runtime)
        self.assertIn("command -v omarchy-update-available", runtime)
        self.assertIn("systemd-run --user --quiet --collect", runtime)
        self.assertEqual(runtime.count("systemd-run --user"), 2)
        self.assertEqual(
            runtime.count("timeout --kill-after=1s 8s systemd-run --user"), 2
        )
        self.assertNotIn("$(systemctl --user show", runtime)
        self.assertIn("--property=KillMode=control-group", runtime)
        self.assertIn("SHIBUMI_TEST_SERVICE_FILE", runtime)
        self.assertIn("--kill-whom=all --signal=TERM", runtime)
        self.assertIn("--kill-whom=all --signal=KILL", runtime)
        self.assertIn("timeout --kill-after=1s 8s", runtime)
        self.assertNotIn("while timeout", runtime)
        self.assertNotIn("/proc/[0-9]*", runtime)
        self.assertNotIn("fixture_process_ids", runtime)
        self.assertIn('>>"$SHIBUMI_TEST_SHELL_LOG"', runtime)
        self.assertIn('"$tmpdir/quickshell.log"', runtime)
        final_drain = runtime.index("final fixture shell service drain failed")
        log_scan = runtime.index("runtime log contains a QML or plugin-load failure")
        self.assertLess(final_drain, log_scan)
        self.assertIn("TERM-resistant cleanup probe", runtime)
        self.assertIn("cleanup_probe_armed=1", runtime)
        self.assertIn("(( cleanup_probe_armed == 1 ))", runtime)
        self.assertIn('printf \'KILL %s\\n\'', runtime)
        self.assertIn("did not exercise the cleanup KILL fallback", runtime)
        self.assertIn("cleanup exceeded its wall-clock budget", runtime)
        self.assertIn('>"$stub_bin/hyprctl"', runtime)

    def test_release_evidence_collector_declares_unique_complete_gates(self) -> None:
        result = subprocess.run(
            [str(ROOT / "scripts/collect-release-evidence"), "--output", "unused", "--list"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        rows = [line.split("\t", 1) for line in result.stdout.splitlines()]
        ids = [row[0] for row in rows]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(
            set(ids),
            {
                "package-tests",
                "manager-tests",
                "suite-tests",
                "health-tests",
                "inc013-tests",
                "registry-mutations",
                "quattro-dry-run",
                "installed-package-contract",
                "installed-source-parity-contract",
                "forward-compat-contract",
                "quattro-runtime",
            },
        )

    def test_release_evidence_host_probes_fail_closed_and_logs_are_redacted(self) -> None:
        path = ROOT / "scripts/collect-release-evidence"
        loader = importlib.machinery.SourceFileLoader("release_evidence", str(path))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)

        for name, command, prefix in module.HOST_PROBES:
            with self.subTest(probe=name, failure="missing"):
                with patch.object(
                    module.subprocess, "run", side_effect=FileNotFoundError("missing")
                ):
                    self.assertFalse(
                        module.probe_host_identity(name, command, prefix)["valid"]
                    )
            with self.subTest(probe=name, failure="nonzero"):
                result = subprocess.CompletedProcess(command, 1, "", "failed")
                with patch.object(module.subprocess, "run", return_value=result):
                    self.assertFalse(
                        module.probe_host_identity(name, command, prefix)["valid"]
                    )
            with self.subTest(probe=name, failure="unparsable"):
                result = subprocess.CompletedProcess(command, 0, "unexpected\n", "")
                with patch.object(module.subprocess, "run", return_value=result):
                    self.assertFalse(
                        module.probe_host_identity(name, command, prefix)["valid"]
                    )
            with self.subTest(probe=name, result="valid"):
                result = subprocess.CompletedProcess(
                    command, 0, prefix + "test-version\n", ""
                )
                with patch.object(module.subprocess, "run", return_value=result):
                    self.assertTrue(
                        module.probe_host_identity(name, command, prefix)["valid"]
                    )

        private_root = "/srv/private/omarchy-source"
        redacted = module.redact_log(
            f"{ROOT} {Path.home()} {private_root}".encode(), [private_root]
        ).decode()
        self.assertNotIn(str(ROOT), redacted)
        self.assertNotIn(str(Path.home()), redacted)
        self.assertNotIn(private_root, redacted)

    def test_dependency_contract_matches_pkgbuild(self) -> None:
        contract = json.loads(
            (ROOT / "contracts/package-runtime-v1.json").read_text(encoding="utf-8")
        )
        srcinfo = (ROOT / "packaging/aur/.SRCINFO").read_text(encoding="utf-8")
        for package in contract["requiredPackages"]:
            self.assertIn(f"\tdepends = {package}", srcinfo)
        for package, purpose in contract["optionalPackages"].items():
            self.assertIn(f"\toptdepends = {package}: {purpose}", srcinfo)

    def test_release_archive_is_reproducible_and_complete(self) -> None:
        with tempfile.TemporaryDirectory(prefix="shibumi-release-test.") as temporary:
            result = subprocess.run(
                [
                    str(ROOT / "scripts/build-release-archive"),
                    "--allow-dirty",
                    "--check-reproducible",
                    "--output-dir",
                    temporary,
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            output = Path(temporary)
            archive = next(output.glob("*.tar.gz"))
            inventory = json.loads(
                next(output.glob("*.inventory.json")).read_text(encoding="utf-8")
            )
            archive_bytes = archive.read_bytes()
            self.assertEqual(
                hashlib.sha256(archive_bytes).hexdigest(), inventory["sha256"]
            )
            self.assertEqual(archive_bytes[:3], b"\x1f\x8b\x08")
            self.assertEqual(
                archive_bytes[9],
                255,
                "gzip OS header must be independent of the Python host",
            )
            with tarfile.open(archive, "r:gz") as payload:
                names = payload.getnames()
                private_home = b"/home/" + b"hancore/"
                for member in payload.getmembers():
                    if not member.isfile():
                        continue
                    stream = payload.extractfile(member)
                    self.assertIsNotNone(stream)
                    self.assertNotIn(
                        private_home,
                        stream.read(),
                        f"release payload exposes a private path: {member.name}",
                    )
            roots = {name.split("/", 1)[0] for name in names}
            self.assertEqual(roots, {f"shibumi-shell-{inventory['version']}"})
            self.assertFalse(
                any(
                    "__pycache__" in name
                    or "docs/audits/" in name
                    or "docs/mockups/" in name
                    or "docs/project-state-" in name
                    or "packaging/aur/" in name
                    for name in names
                )
            )
            manifests = [name for name in names if name.endswith("/manifest.json")]
            self.assertEqual(len(manifests), 24)


if __name__ == "__main__":
    unittest.main()
