#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
NAYUKI_NOTICE = """Third-party notice: QR Code generator library

Copyright (c) Project Nayuki. (MIT License)
https://www.nayuki.io/page/qr-code-generator-library

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:
- The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.
- The Software is provided "as is", without warranty of any kind, express or
  implied, including but not limited to the warranties of merchantability,
  fitness for a particular purpose and noninfringement. In no event shall the
  authors or copyright holders be liable for any claim, damages or other
  liability, whether in an action of contract, tort or otherwise, arising from,
  out of or in connection with the Software or the use or other dealings in the
  Software."""


def has_complete_nayuki_notice(text: str) -> bool:
    marker = "Third-party notice: QR Code generator library"
    return marker in text and text.split(marker, 1)[1].strip() == (
        NAYUKI_NOTICE.split(marker, 1)[1].strip()
    )


class PackageReleaseTests(unittest.TestCase):
    def test_nayuki_notice_is_complete_and_truncation_fails(self) -> None:
        license_text = (ROOT / "LICENSE").read_text(encoding="utf-8")
        self.assertTrue(has_complete_nayuki_notice(license_text))
        truncated = license_text.split(
            "Permission is hereby granted", 1
        )[0].rstrip()
        self.assertFalse(has_complete_nayuki_notice(truncated))

    def test_versions_and_all_plugin_manifests_agree(self) -> None:
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        suite = json.loads(
            (ROOT / "contracts/plugin-suite-v1.json").read_text(encoding="utf-8")
        )
        marker = json.loads(
            (ROOT / "packaging/package-metadata.json").read_text(encoding="utf-8")
        )
        self.assertEqual(version, "0.1.1-beta.12")
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
        self.assertIn(
            'contracts/backend-boundary-v1.json',
            pkgbuild,
        )
        self.assertIn("contracts/lifecycle-predecessors-v1.json", pkgbuild)
        aur_check = (ROOT / "scripts/check-aur-package").read_text(
            encoding="utf-8"
        )
        self.assertIn("scripts/check-production-boundary", aur_check)
        self.assertIn('"refs/tags/$tag^{}"', aur_check)
        self.assertIn('remote_commit == "$head_commit"', aur_check)
        self.assertIn('remote_tag_output=$(git ls-remote', aur_check)
        self.assertIn('cannot resolve remote v%s', aur_check)
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

    def test_release_workflow_rehearses_the_installed_aur_package(self) -> None:
        workflow = (ROOT / ".github/workflows/package-release.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("archlinux:base-devel", workflow)
        self.assertIn('"$GITHUB_WORKSPACE:/src:ro"', workflow)
        self.assertIn("scripts/rehearse-aur-package", workflow)
        rehearsal = (ROOT / "scripts/rehearse-aur-package").read_text(encoding="utf-8")
        self.assertIn("usr/share/shibumi-shell/contracts/backend-boundary-v1.json", rehearsal)
        self.assertIn("usr/share/shibumi-shell/contracts/lifecycle-predecessors-v1.json", rehearsal)
        self.assertIn("verify_package_inventory(extract)", rehearsal)
        self.assertIn("check-production-boundary", rehearsal)
        self.assertIn("Suite.load(payload)", rehearsal)
        self.assertIn('"--root"', rehearsal)
        self.assertNotIn("chown -R builder:builder /src", workflow)

    def test_release_workflow_requires_revision_bound_lifecycle_evidence(self) -> None:
        workflow = (ROOT / ".github/workflows/package-release.yml").read_text(
            encoding="utf-8"
        )
        collector = (ROOT / "scripts/collect-release-evidence").read_text(
            encoding="utf-8"
        )
        for contract in (
            "python3 tests/test_shibumi_manager.py",
            "python3 tests/test_lifecycle_admission.py",
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
            "omarchy-agents-contract-regression.sh",
            "omarchy-forward-compat-contract-regression.sh",
        ):
            self.assertIn(gate, collector)
        self.assertIn(
            "needs: package-contract", workflow
        )
        self.assertIn(
            "runs-on: [self-hosted, linux, shibumi-validation]", workflow
        )
        self.assertIn('--expected-commit "$GITHUB_SHA"', workflow)
        self.assertEqual(workflow.count('tag_output=$(git ls-remote --tags origin'), 2)
        self.assertIn('gh release create "$tag"', workflow)
        self.assertIn('gh release view "$tag" --json isDraft,tagName', workflow)
        self.assertIn('gh release upload "$tag" "${assets[@]}" --clobber', workflow)
        self.assertIn('--draft \\', workflow)
        self.assertIn('gh release download "$tag"', workflow)
        self.assertEqual(workflow.count('gh release download "$tag" --dir'), 2)
        self.assertIn('gh release edit "$tag" --draft=false', workflow)
        self.assertLess(
            workflow.rindex('gh release download "$tag"'),
            workflow.index('gh release edit "$tag" --draft=false'),
        )

    def test_quattro_cleanup_rejects_foreign_units_without_systemctl(self) -> None:
        runtime = (ROOT / "tests/shibumi-suite-quattro-runtime.sh").read_text(
            encoding="utf-8"
        )
        stop_script = runtime.split(
            "cat >\"$stop_shells\" <<'STOP_SHELLS'\n", 1
        )[1].split("\nSTOP_SHELLS", 1)[0]
        with tempfile.TemporaryDirectory(prefix="shibumi-cleanup-boundary.") as temporary:
            root = Path(temporary)
            script = root / "stop-shells"
            script.write_text(stop_script, encoding="utf-8")
            script.chmod(0o755)
            service_file = root / "services"
            service_file.write_text("production-user.service\n", encoding="utf-8")
            systemctl_log = root / "systemctl.log"
            stub_bin = root / "bin"
            stub_bin.mkdir()
            systemctl = stub_bin / "systemctl"
            systemctl.write_text(
                "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$SYSTEMCTL_LOG\"\n",
                encoding="utf-8",
            )
            systemctl.chmod(0o755)
            environment = os.environ.copy()
            environment.update({
                "PATH": f"{stub_bin}:{environment['PATH']}",
                "SYSTEMCTL_LOG": str(systemctl_log),
                "SHIBUMI_TEST_SERVICE_FILE": str(service_file),
                "SHIBUMI_TEST_CLEANUP_LOG": str(root / "cleanup.log"),
                "SHIBUMI_TEST_SERVICE_PREFIX": "shibumi-runtime-Ab12Cd",
            })
            result = subprocess.run(
                [str(script)],
                text=True,
                capture_output=True,
                env=environment,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("refusing foreign fixture service", result.stderr)
            self.assertFalse(systemctl_log.exists())

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
        self.assertIn("SHIBUMI_TEST_SERVICE_PREFIX", runtime)
        self.assertIn("refusing foreign fixture service", runtime)
        self.assertIn("^${SHIBUMI_TEST_SERVICE_PREFIX}-([1-9]|1[0-2])", runtime)
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
                "lifecycle-admission",
                "health-tests",
                "inc013-tests",
                "registry-mutations",
                "quattro-dry-run",
                "installed-package-contract",
                "installed-source-parity-contract",
                "agents-contract",
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

    def test_release_evidence_accepts_omarchy_dev_as_diagnostic_fallback(self) -> None:
        path = ROOT / "scripts/collect-release-evidence"
        loader = importlib.machinery.SourceFileLoader(
            "release_evidence_fallback", str(path)
        )
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)

        stable = {
            "name": "omarchyPackage",
            "command": ["pacman", "-Q", "omarchy"],
            "exitCode": 1,
            "output": "",
            "valid": False,
        }
        development = {
            "name": "omarchyDevPackage",
            "command": ["pacman", "-Q", "omarchy-dev"],
            "exitCode": 0,
            "output": "omarchy-dev 4.0.0.r1-1",
            "valid": True,
        }
        with patch.object(
            module, "probe_host_identity", side_effect=[stable, development]
        ):
            result = module.probe_omarchy_package()

        self.assertTrue(result["valid"])
        self.assertEqual(result["name"], "omarchyDevPackage")
        self.assertEqual(result["fallbackFor"], "omarchyPackage")
        self.assertFalse(module.release_host_probes_pass([result]))

    def test_dependency_contract_matches_pkgbuild(self) -> None:
        contract = json.loads(
            (ROOT / "contracts/package-runtime-v1.json").read_text(encoding="utf-8")
        )
        srcinfo = (ROOT / "packaging/aur/.SRCINFO").read_text(encoding="utf-8")
        for package in contract["requiredPackages"]:
            self.assertIn(f"\tdepends = {package}", srcinfo)
        for package, purpose in contract["optionalPackages"].items():
            self.assertIn(f"\toptdepends = {package}: {purpose}", srcinfo)
        self.assertEqual(
            set(contract["requiredHostCommands"]),
            {"omarchy-bluetooth-device", "omarchy-audio-output-set-default"},
        )
        runtime = (ROOT / "scripts/shibumi_suite/runtime.py").read_text(
            encoding="utf-8"
        )
        for command in contract["requiredHostCommands"]:
            self.assertIn(f'"{command}"', runtime)

    def test_release_archive_rejects_invalid_commit_binding(self) -> None:
        with tempfile.TemporaryDirectory(prefix="shibumi-release-binding.") as temporary:
            for expected, message in (
                ("short", "full lowercase commit id"),
                ("0" * 40, "HEAD mismatch"),
            ):
                with self.subTest(expected=expected):
                    result = subprocess.run(
                        [
                            str(ROOT / "scripts/build-release-archive"),
                            "--expected-commit",
                            expected,
                            "--output-dir",
                            temporary,
                        ],
                        cwd=ROOT,
                        text=True,
                        capture_output=True,
                    )
                    self.assertEqual(result.returncode, 2)
                    self.assertIn(message, result.stderr)

    def test_rehearsal_inventory_rejects_unexpected_paths_and_mode_drift(self) -> None:
        path = ROOT / "scripts/rehearse-aur-package"
        loader = importlib.machinery.SourceFileLoader("aur_rehearsal", str(path))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        files, directories = module.expected_package_inventory()
        with tempfile.TemporaryDirectory(prefix="shibumi-package-inventory.") as temporary:
            extracted = Path(temporary)
            for directory in sorted(directories):
                (extracted / directory).mkdir(parents=True, exist_ok=True)
            for relative, (mode, payload) in files.items():
                target = extracted / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(payload)
                target.chmod(mode)
            module.verify_package_inventory(extracted)

            extra = extracted / "usr/share/shibumi-shell/foreign"
            extra.write_text("foreign\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "file inventory drift"):
                module.verify_package_inventory(extracted)
            extra.unlink()

            target = extracted / "usr/bin/shibumi-shell"
            target.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "mode/content drift"):
                module.verify_package_inventory(extracted)

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
            extracted = output / "archive-root"
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
                payload.extractall(extracted, filter="data")
            roots = {name.split("/", 1)[0] for name in names}
            self.assertEqual(roots, {f"shibumi-shell-{inventory['version']}"})
            archive_root = extracted / next(iter(roots))
            shipped_license = (archive_root / "LICENSE").read_text(
                encoding="utf-8"
            )
            self.assertTrue(has_complete_nayuki_notice(shipped_license))
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
            lifecycle_contract = (
                archive_root / "contracts/lifecycle-predecessors-v1.json"
            )
            self.assertTrue(lifecycle_contract.is_file())
            boundary = subprocess.run(
                [
                    str(ROOT / "scripts/check-production-boundary"),
                    "--root",
                    str(archive_root),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(boundary.returncode, 0, boundary.stderr)


if __name__ == "__main__":
    unittest.main()
