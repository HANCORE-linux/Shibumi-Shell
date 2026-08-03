#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


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
        self.assertEqual(version, "0.1.1-beta.3")
        self.assertEqual(suite["suiteVersion"], version)
        self.assertEqual(marker["version"], version)
        for plugin in suite["plugins"]:
            manifest = json.loads(
                (ROOT / plugin["id"] / "manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(manifest["version"], version, plugin["id"])

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
