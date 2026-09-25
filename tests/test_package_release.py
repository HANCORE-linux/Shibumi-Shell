#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from shibumi_suite.config import remove_suite  # noqa: E402
from shibumi_suite.model import Suite, suite_payload_digest  # noqa: E402


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
        self.assertEqual(version, "0.1.1-beta.15.3")
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

    def test_lifecycle_contract_pins_exact_release_identities(self) -> None:
        contract = json.loads(
            (ROOT / "contracts/lifecycle-predecessors-v1.json").read_text(
                encoding="utf-8"
            )
        )
        states = {item["id"]: item for item in contract["states"]}
        expected = {
            "public-beta.11": {
                "suiteVersion": "0.1.1-beta.11",
                "sourceRevisions": [
                    "adbb11068e9c77561ff0c3d1b8fca5212653ae3c",
                    "package:0.1.1-beta.11",
                ],
                "settingsStorageVersion": 0,
                "payloadDigest": "27f092d27e772bb33ccddc79de28079759c3f666f293c346e6a974039529c032",
            },
            "step-5-tip": {
                "suiteVersion": "0.1.1-beta.11",
                "sourceRevisions": [
                    "5154c020a44d71139a6614a183ec91021b9772c1"
                ],
                "settingsStorageVersion": 0,
                "payloadDigest": "418544f59ac78c6dce84badf99c19931c586c2b441eb484a44b57556c8295226",
            },
            "public-beta.12": {
                "suiteVersion": "0.1.1-beta.12",
                "sourceRevisions": [
                    "3c6d0696f98f2953b2d7b434e3c0728bd6f86369"
                ],
                "settingsStorageVersion": 1,
                "payloadDigest": "3c5c59b359b2ef6afad7e8c898682e20b38c940ab7479bb04ca164d13cabbc6f",
            },
            "public-beta.13": {
                "suiteVersion": "0.1.1-beta.13",
                "sourceRevisions": [
                    "2760cdb8272255790d5e4613fed8a48cb63c3555",
                    "3cb7f6d26df47b0e2d697575e4b42ba48e405c1d",
                    "package:0.1.1-beta.13",
                ],
                "settingsStorageVersion": 1,
                "payloadDigest": "84f25408c8068c839884415a0a48c85922f54e22c782a6b19791e07903278c69",
            },
            "source-beta.14": {
                "suiteVersion": "0.1.1-beta.14",
                "sourceRevisions": [
                    "11c9f63147ffea3265bdff442bb556f23700d209",
                    "36ceb7ddcd58eb3a7d78485db3f0be53840e12e6",
                    "513b7ec4d05e9633070e10f7b42ea2335ee448e8",
                    "32a0044656d7c4910f3e424fdca7e5597c112066",
                    "87eb87d508e9f0dd5d6c46ce076fac1b05e1507e",
                ],
                "settingsStorageVersion": 1,
                "payloadDigest": "70a76ad6ba877381a2663c1ac76b6eaf7883bb724dfa0d2c017e113ec1946577",
            },
            "public-beta.14.1": {
                "suiteVersion": "0.1.1-beta.14.1",
                "sourceRevisions": [
                    "7a6c853b1947d303bad9a5b640c224c01b669106",
                    "b9bf65993bc04c1d49dc98a78b60d5594478a7bd",
                    "package:0.1.1-beta.14.1",
                ],
                "settingsStorageVersion": 1,
                "payloadDigest": "0350a8f66d81dc640b6d268ace149620ae78c40aea13ad2cd507ad6de93d8de3",
            },
            "public-beta.15": {
                "suiteVersion": "0.1.1-beta.15",
                "sourceRevisions": [
                    "4e91c26ebf4da07476d4be6176f29d7662fed9c1",
                    "91b2cd0f886c15962a2627aea3269f4c09cae828",
                    "7c0499289c48b9f4b3dfd28687a23824e752f15d",
                    "package:0.1.1-beta.15",
                ],
                "settingsStorageVersion": 1,
                "payloadDigest": "7eeb2a88e0920d2fe647f4ef88b8a00ad54a205c3b627234b402d50b4709b11d",
            },
            "public-beta.15.1": {
                "suiteVersion": "0.1.1-beta.15.1",
                "sourceRevisions": [
                    "36e4b9f0de428c17248d40592461a9e3f3f750f8",
                    "533110d7abda296b56369f304a618f9313e1f12f",
                    "package:0.1.1-beta.15.1",
                ],
                "settingsStorageVersion": 1,
                "payloadDigest": "31a2e133191264e2e63919eed7f43c5393ac5c5aadda23ea9199afd211f53274",
            },
            "public-beta.15.2": {
                "suiteVersion": "0.1.1-beta.15.2",
                "sourceRevisions": [
                    "c45af77c8333b691ac36522247b6e5b5481a3666",
                    "aaf7611d66ed5f99078fc5419bc3ba4db6164bed",
                    "package:0.1.1-beta.15.2",
                ],
                "settingsStorageVersion": 1,
                "payloadDigest": "5401b03f80a876f636d2635478cbe5af3da75c49022a614823a5c6586a3170d0",
            },
            "public-beta.15.3": {
                "suiteVersion": "0.1.1-beta.15.3",
                "sourceRevisions": ["package:0.1.1-beta.15.3"],
                "settingsStorageVersion": 1,
                "payloadDigest": "8e97c4b0bcbf1907eecf297cb300c4fd110e67b6b780187f4ddf5409f3d7c145",
            },
        }
        self.assertEqual(set(states), set(expected))
        for identity_id, pinned in expected.items():
            with self.subTest(identity=identity_id):
                state = states[identity_id]
                for field, value in pinned.items():
                    self.assertEqual(state[field], value)
                self.assertEqual(len(state["pluginIds"]), 24)
                self.assertEqual(
                    set(state["pluginDigests"]), set(state["pluginIds"])
                )
                digest = hashlib.sha256(b"shibumi-suite-payload-v1\0")
                for plugin_id, plugin_digest in sorted(
                    state["pluginDigests"].items()
                ):
                    digest.update(plugin_id.encode("utf-8"))
                    digest.update(b"\0")
                    digest.update(plugin_digest.encode("ascii"))
                    digest.update(b"\0")
                self.assertEqual(digest.hexdigest(), state["payloadDigest"])

        suite = Suite.load(ROOT)
        current_plugin_digests = {
            plugin_id: spec.payload_digest()
            for plugin_id, spec in suite.plugins.items()
        }
        self.assertEqual(
            states["public-beta.15.3"]["pluginDigests"],
            current_plugin_digests,
        )
        self.assertEqual(
            states["public-beta.15.3"]["payloadDigest"],
            suite_payload_digest(current_plugin_digests),
        )
        self.assertNotIn(
            "package:0.1.1-beta.12",
            states["public-beta.12"]["sourceRevisions"],
        )

        aur_check = (ROOT / "scripts/check-aur-package").read_text(
            encoding="utf-8"
        )
        state_list_marker = "and (.states | map(.id)) == ["
        self.assertEqual(aur_check.count(state_list_marker), 1)
        aur_state_list = aur_check.split(state_list_marker, 1)[1].split("]", 1)[0]
        self.assertEqual(
            json.loads(f"[{aur_state_list}]"),
            [item["id"] for item in contract["states"]],
        )

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
        self.assertEqual(checkout_uses, [expected, expected, expected])
        self.assertEqual(workflow.count("persist-credentials: false"), 3)
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
            "native-catalog-resource-regression.py",
            "omarchy-agents-contract-regression.sh",
            "omarchy-forward-compat-contract-regression.sh",
        ):
            self.assertIn(gate, collector)
        ruby_parser = """
require "json"
require "yaml"
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)
puts JSON.generate(workflow.fetch("jobs"))
"""
        parsed = subprocess.run(
            ["ruby", "-e", ruby_parser, str(ROOT / ".github/workflows/package-release.yml")],
            check=True,
            capture_output=True,
            text=True,
        )
        jobs = json.loads(parsed.stdout)
        self.assertEqual(set(jobs), {"package-contract", "release-validation", "github-release"})
        self.assertEqual(jobs["package-contract"]["timeout-minutes"], 60)
        self.assertEqual(jobs["package-contract"]["permissions"], {"contents": "read"})
        self.assertEqual(jobs["release-validation"]["needs"], "package-contract")
        self.assertEqual(jobs["release-validation"]["timeout-minutes"], 240)
        self.assertEqual(jobs["release-validation"]["permissions"], {"contents": "read"})
        self.assertEqual(
            jobs["release-validation"]["runs-on"],
            ["self-hosted", "linux", "shibumi-validation"],
        )
        self.assertEqual(jobs["github-release"]["needs"], "release-validation")
        self.assertEqual(jobs["github-release"]["timeout-minutes"], 30)
        self.assertEqual(jobs["github-release"]["permissions"], {"contents": "write"})
        self.assertEqual(jobs["github-release"]["runs-on"], "ubuntu-24.04")
        self.assertIn("cancel-in-progress: true", workflow)
        self.assertIn(
            "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
            workflow,
        )
        self.assertIn("--no-recursion --null --verbatim-files-from", workflow)
        self.assertIn('--files-from="$logs_manifest"', workflow)
        self.assertNotIn(
            '-C dist -cf - "shibumi-shell-$version.release-evidence.logs"',
            workflow,
        )
        self.assertIn("validate_log_inventory(log_dir, results)", collector)
        self.assertIn(
            "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093",
            workflow,
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

    def test_publication_admission_requires_the_resource_gate_to_pass(self) -> None:
        workflow_path = ROOT / ".github/workflows/package-release.yml"
        ruby_parser = """
require "json"
require "yaml"
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)
puts JSON.generate(workflow.fetch("jobs"))
"""
        parsed = subprocess.run(
            ["ruby", "-e", ruby_parser, str(workflow_path)],
            check=True,
            capture_output=True,
            text=True,
        )
        jobs = json.loads(parsed.stdout)
        validation_steps = jobs["release-validation"]["steps"]
        inventory_step = next(
            step for step in validation_steps
            if step.get("name") == "Verify version and exact local asset inventory"
        )
        run = inventory_step["run"]
        prefix = 'jq -e --arg commit "$GITHUB_SHA" --arg version "$version" \'\n'
        filter_start = run.index(prefix) + len(prefix)
        filter_end = run.index('\n\' "$evidence"', filter_start)
        admission_filter = run[filter_start:filter_end]
        self.assertIn('select(.id == "native-catalog-resource")', admission_filter)

        commit = "a" * 40
        base_evidence = {
            "passed": True,
            "candidate": {
                "kind": "clean-commit",
                "version": "0.1.1-beta.test",
                "baseCommit": commit,
            },
            "finalInputValidation": {"status": "passed"},
        }
        cases = (
            (
                "passed-control",
                [
                    {"id": "lifecycle-admission", "status": "passed"},
                    {"id": "native-catalog-resource", "status": "passed"},
                ],
                True,
            ),
            (
                "absent",
                [{"id": "lifecycle-admission", "status": "passed"}],
                False,
            ),
            (
                "failed",
                [
                    {"id": "lifecycle-admission", "status": "passed"},
                    {"id": "native-catalog-resource", "status": "failed"},
                ],
                False,
            ),
        )
        for name, commands, expected in cases:
            with self.subTest(case=name):
                evidence = {**base_evidence, "commands": commands}
                admitted = subprocess.run(
                    [
                        "jq",
                        "-e",
                        "--arg",
                        "commit",
                        commit,
                        "--arg",
                        "version",
                        "0.1.1-beta.test",
                        admission_filter,
                    ],
                    input=json.dumps(evidence),
                    text=True,
                    capture_output=True,
                )
                self.assertEqual(admitted.returncode == 0, expected, admitted.stderr)

    def test_quattro_runtime_pins_predecessors_and_all_four_arms(self) -> None:
        runtime_path = ROOT / "tests/shibumi-suite-quattro-runtime.sh"
        revision_pins = (
            "package_predecessor_revision="
            "2760cdb8272255790d5e4613fed8a48cb63c3555",
            "package_candidate_revision="
            "7a6c853b1947d303bad9a5b640c224c01b669106",
            "source_predecessor_revision="
            "c45af77c8333b691ac36522247b6e5b5481a3666",
            "source_beta15_revision="
            "4e91c26ebf4da07476d4be6176f29d7662fed9c1",
        )
        arm_markers = (
            "# Arm 1: package update",
            "# Arm 2: fresh source checkout install",
            "# Arm 3: beta.15 source checkout update",
            "# Arm 4: beta.15.2 source checkout update",
        )
        package_candidate_archive = (
            'archive "$package_candidate_revision" \\\n'
            '  | tar -x -C "$package_candidate_root"'
        )
        source_version_assignment = 'candidate_version=$(<"$repo_root/VERSION")'
        fresh_source_assertion = (
            'assert_install_state "$source_candidate_root" '
            '"$(<"$repo_root/VERSION")" checkout \\\n'
            '  "$candidate_revision"'
        )

        def assert_contract(text: str) -> None:
            for revision_pin in revision_pins:
                self.assertEqual(text.count(revision_pin), 1)
            for marker in arm_markers:
                self.assertEqual(text.count(marker), 1)
            self.assertIn(
                "# Published beta.14.1; lift to the next tag at release pin.",
                text,
            )
            self.assertIn("clone --quiet --shared --no-checkout", text)
            self.assertIn("checkout --quiet \\\n    --detach", text)
            self.assertIn(package_candidate_archive, text)
            self.assertIn('source_root="$source_candidate_root"', text)
            self.assertIn(fresh_source_assertion, text)
            self.assertEqual(text.count(source_version_assignment), 1)
            self.assertIn("fresh candidate source checkout", text)
            self.assertNotIn("fresh candidate package", text)
            self.assertEqual(text.count("run_update_arm \"$"), 3)
            self.assertIn(".installOrigin == $origin", text)
            self.assertIn(".payloadRoot == $root", text)
            self.assertIn(".sourceRoot == $root", text)

        runtime = runtime_path.read_text(encoding="utf-8")
        assert_contract(runtime)
        with tempfile.TemporaryDirectory(
            prefix="shibumi-quattro-arm-markers."
        ) as temporary:
            mutations = (
                runtime.replace(
                    source_version_assignment, "candidate_version=0.1.1-beta.15", 1
                ),
                runtime.replace(
                    fresh_source_assertion,
                    fresh_source_assertion.replace(
                        '\"$(<\"$repo_root/VERSION\")\"', "'0.1.1-beta.15'"
                    ),
                    1,
                ),
                runtime.replace(arm_markers[2], "", 1),
                runtime.replace(
                    package_candidate_archive,
                    package_candidate_archive.replace(
                        "$package_candidate_revision", "$candidate_revision"
                    ),
                    1,
                ),
                runtime.replace(
                    fresh_source_assertion,
                    fresh_source_assertion.replace(
                        '"$source_candidate_root"', '"$package_candidate_root"'
                    ),
                    1,
                ),
            )
            for index, mutated_runtime in enumerate(mutations):
                mutation = Path(temporary) / f"quattro-runtime-mutation-{index}.sh"
                mutation.write_text(mutated_runtime, encoding="utf-8")
                with self.assertRaises(AssertionError):
                    assert_contract(mutation.read_text(encoding="utf-8"))

    def test_quattro_uninstall_assertion_rejects_all_suite_leftovers(self) -> None:
        runtime = (ROOT / "tests/shibumi-suite-quattro-runtime.sh").read_text(
            encoding="utf-8"
        )
        helper_start = runtime.index("assert_uninstalled_arm() {\n")
        helper_end = runtime.index("\n}\n\nrun_keep_settings_cycle()", helper_start) + 3
        helper = runtime[helper_start:helper_end]

        with tempfile.TemporaryDirectory(
            prefix="shibumi-quattro-uninstall."
        ) as temporary:
            root = Path(temporary)
            harness = root / "assert-uninstalled"
            harness.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "config_home=$1\n"
                "state_home=$2\n"
                "cache_home=$3\n"
                "fail() { printf 'fixture fail: %s\\n' \"$*\" >&2; exit 1; }\n"
                "shell_ipc() { if [[ $* == 'shell ping' ]]; then printf 'ok\\n'; "
                "else printf '%s\\n' \"$(<\"$config_home/omarchy/shell.json\")\"; fi; }\n"
                f"{helper}\n"
                "assert_uninstalled_arm\n",
                encoding="utf-8",
            )
            harness.chmod(0o755)

            cases = (
                (
                    "audio-directory",
                    "plugin",
                    "fixture fail: Shibumi plugin entry remains after uninstall\n",
                ),
                (
                    "dangling-state",
                    "state",
                    "fixture fail: suite state remains after uninstall\n",
                ),
                (
                    "dangling-cache",
                    "cache",
                    "fixture fail: suite cache remains after uninstall\n",
                ),
                ("clean-control", "clean", ""),
            )
            for name, leftover, expected_stderr in cases:
                with self.subTest(case=name):
                    case_root = root / name
                    config_home = case_root / "config"
                    state_home = case_root / "state"
                    cache_home = case_root / "cache"
                    plugins = config_home / "omarchy/plugins"
                    plugins.mkdir(parents=True)
                    state_home.mkdir(parents=True)
                    cache_home.mkdir(parents=True)
                    (config_home / "omarchy/shell.json").write_text(
                        "{}\n", encoding="utf-8"
                    )
                    if leftover == "plugin":
                        (plugins / "hancore.shibumi.audio").mkdir()
                    elif leftover == "state":
                        (state_home / "shibumi").symlink_to(case_root / "missing")
                    elif leftover == "cache":
                        (cache_home / "shibumi").symlink_to(case_root / "missing")

                    result = subprocess.run(
                        [
                            str(harness),
                            str(config_home),
                            str(state_home),
                            str(cache_home),
                        ],
                        text=True,
                        capture_output=True,
                    )
                    expected_exit = 0 if leftover == "clean" else 1
                    self.assertEqual(result.returncode, expected_exit, result.stderr)
                    self.assertEqual(result.stderr, expected_stderr)

    def test_quattro_kept_settings_assertion_rejects_loss_and_partial_restore(self) -> None:
        runtime = (ROOT / "tests/shibumi-suite-quattro-runtime.sh").read_text()
        helpers = runtime[runtime.index("state_settings_snapshot() {"):
                          runtime.index("run_keep_settings_cycle() {")]
        entry = {
            "id": "hancore.shibumi.state",
            "shibumiStateSchemaVersion": 1,
            "foreignFuture": {"nested": [1, False, {"label": "Malmö"}]},
            "shibumi": {"version": 1, "presentation": {"accent": "color06"},
                        "widgets": {"G8": {"deep": [3, 2, 1]}}},
        }
        expected = json.dumps(entry, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        installed = {
            "version": 1,
            "bar": {"id": "hancore.shibumi.bar", "layout": {
                "left": ["hancore.shibumi.audio"], "center": [], "right": []}},
            "plugins": [entry, {"id": "hancore.shibumi.audio"}],
        }
        suite = Suite.load(ROOT)
        with tempfile.TemporaryDirectory(prefix="shibumi-quattro-kept-settings.") as temporary:
            root = Path(temporary)
            script = root / "assert-settings"
            script.write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\n"
                "config_home=$1; state_home=$2; cache_home=$3; live_config=$4\n"
                "fail() { printf 'fixture fail: %s\\n' \"$*\" >&2; exit 1; }\n"
                "shell_ipc() {\n"
                "  case \"$*\" in\n"
                "    'shell ping') printf 'ok\\n' ;;\n"
                "    'shell listShellConfig') printf '%s\\n' \"$(<\"$live_config\")\" ;;\n"
                "    *) return 99 ;;\n"
                "  esac\n}\n"
                f"{helpers}\n"
                "case $6 in\n"
                "  uninstall) assert_uninstalled_arm \"$5\" ;;\n"
                "  reinstall) assert_settings_preserved \"$5\" reinstall ;;\n"
                "  purge) assert_uninstalled_arm ;;\n"
                "esac\n"
            )
            # Exercise the real lifecycle transformation with/without retention,
            # then execute the exact Bash/JQ assertions used by the runtime gate.
            kept, dropped = [remove_suite(
                installed, suite.plugins, root / "absent-plugins",
                "hancore.shibumi.bar", "omarchy.clock", keep,
                restore_bar={"id": "omarchy.bar", "layout": {
                    "left": [{"id": "omarchy.menu"}],
                    "center": ["omarchy.clock"], "right": []}},
            ) for keep in (True, False)]
            self.assertEqual(kept["plugins"], [entry])
            self.assertEqual(dropped["plugins"], [])
            reset = json.loads(json.dumps(kept))
            reset["plugins"][0]["shibumi"]["presentation"]["accent"] = "color01"
            partial = json.loads(json.dumps(kept))
            del partial["plugins"][0]["foreignFuture"]
            duplicate = json.loads(json.dumps(kept))
            duplicate["plugins"].append(entry)
            bad_schema = json.loads(json.dumps(kept))
            bad_schema["plugins"][0]["shibumiStateSchemaVersion"] = 2
            cases = (
                ("retained-positive", kept, kept, "uninstall", "", ""),
                ("reinstall-positive", kept, kept, "reinstall", "", ""),
                ("without-keep-settings", dropped, dropped, "uninstall", "",
                 "keep-settings uninstall canonical State settings are missing or invalid"),
                ("reinstall-reset", reset, reset, "reinstall", "",
                 "reinstall changed the complete State settings entry"),
                ("lost-unknown-field", partial, partial, "reinstall", "",
                 "reinstall changed the complete State settings entry"),
                ("duplicate-entry", duplicate, duplicate, "uninstall", "",
                 "keep-settings uninstall canonical State settings are missing or invalid"),
                ("wrong-schema", bad_schema, bad_schema, "uninstall", "",
                 "keep-settings uninstall canonical State settings are missing or invalid"),
                ("live-reset", kept, reset, "reinstall", "",
                 "reinstall live State settings differ from file snapshot"),
                ("payload-leftover", kept, kept, "uninstall", "hancore.shibumi.state",
                 "Shibumi plugin entry remains after uninstall"),
                ("hidden-leftover", kept, kept, "uninstall", ".shibumi-stage-leftover",
                 "hidden lifecycle artifacts remain after uninstall"),
                ("purge-rejects-dormant-entry", kept, kept, "purge", "",
                 "uninstall did not restore a Shibumi-free config"),
            )
            for name, config, live, phase, leftover, diagnostic in cases:
                with self.subTest(case=name):
                    base = root / name
                    config_home, state_home, cache_home = [base / x for x in ("config", "state", "cache")]
                    plugins = config_home / "omarchy/plugins"
                    plugins.mkdir(parents=True)
                    state_home.mkdir()
                    cache_home.mkdir()
                    (config_home / "omarchy/shell.json").write_text(json.dumps(config))
                    live_path = base / "live.json"
                    live_path.write_text(json.dumps(live, sort_keys=True))
                    if leftover:
                        (plugins / leftover).mkdir()
                        (plugins / leftover / ".shibumi-managed.json").write_text("{}")
                    result = subprocess.run(
                        ["bash", str(script), str(config_home), str(state_home),
                         str(cache_home), str(live_path), expected, phase],
                        capture_output=True, text=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, 1 if diagnostic else 0, result.stderr)
                    self.assertEqual(result.stderr, f"fixture fail: {diagnostic}\n" if diagnostic else "")
                    print(f"keep-settings assertion control {name}: exit={result.returncode}; "
                          f"{diagnostic or 'identical complete State entry'}", flush=True)

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
            for unit in ("production-user.service", "shibumi-runtime-Ab12Cd-0.service",
                         "shibumi-runtime-Ab12Cd-26.service"):
                with self.subTest(unit=unit):
                    service_file.write_text(unit + "\n")
                    result = subprocess.run(
                        [str(script)], text=True, capture_output=True,
                        env=environment, timeout=10,
                    )
                    self.assertEqual(result.returncode, 1)
                    self.assertIn("refusing foreign fixture service", result.stderr)
                    self.assertFalse(systemctl_log.exists())
            # All 25 owned identities pass the start allowlist; a 26th generation
            # must be refused before any launch or service-file append.
            start_script = runtime.split(
                "cat >\"$start_shell\" <<'START_SHELL'\n", 1
            )[1].split("\nSTART_SHELL", 1)[0]
            script.write_text(start_script)
            full_budget = "".join(f"shibumi-runtime-Ab12Cd-{i}.service\n"
                                  for i in range(1, 26))
            service_file.write_text(full_budget)
            result = subprocess.run(
                [str(script)], text=True, capture_output=True,
                env=environment, timeout=10,
            )
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr, "isolated shell service generation limit exceeded\n")
            self.assertEqual(service_file.read_text(), full_budget)
            self.assertFalse(systemctl_log.exists())

    def test_quattro_cleanup_removal_failure_is_fatal(self) -> None:
        runtime = (ROOT / "tests/shibumi-suite-quattro-runtime.sh").read_text(
            encoding="utf-8"
        )
        helper_start = runtime.index("cleanup() {\n")
        helper_end = runtime.index("\n}\ntrap cleanup EXIT", helper_start) + 3
        cleanup = runtime[helper_start:helper_end]

        with tempfile.TemporaryDirectory(
            prefix="shibumi-cleanup-removal."
        ) as temporary:
            root = Path(temporary)
            harness = root / "cleanup"
            harness.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "tmpdir=$1\n"
                "stop_shells=\n"
                "cleanup_log=\n"
                "service_prefix=shibumi-runtime-Ab12Cd\n"
                "cleanup_probe_armed=0\n"
                "failed=0\n"
                f"{cleanup}\n"
                "cleanup\n",
                encoding="utf-8",
            )
            harness.chmod(0o755)

            failed_scratch = root / "failed-scratch"
            failed_scratch.mkdir()
            (failed_scratch / "sentinel").write_text("retained\n", encoding="utf-8")
            stub_bin = root / "bin"
            stub_bin.mkdir()
            rm_stub = stub_bin / "rm"
            rm_stub.write_text("#!/usr/bin/env bash\nexit 73\n", encoding="utf-8")
            rm_stub.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = f"{stub_bin}:{environment['PATH']}"
            failed = subprocess.run(
                [str(harness), str(failed_scratch)],
                text=True,
                capture_output=True,
                env=environment,
            )
            self.assertEqual(failed.returncode, 1, failed.stderr)
            self.assertTrue((failed_scratch / "sentinel").is_file())
            self.assertIn(
                "Runtime fixture temporary directory cleanup failed",
                failed.stderr,
            )

            removed_scratch = root / "removed-scratch"
            removed_scratch.mkdir()
            (removed_scratch / "sentinel").write_text("removed\n", encoding="utf-8")
            removed = subprocess.run(
                [str(harness), str(removed_scratch)],
                text=True,
                capture_output=True,
            )
            self.assertEqual(removed.returncode, 0, removed.stderr)
            self.assertFalse(removed_scratch.exists())
            self.assertFalse(removed_scratch.is_symlink())

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
        self.assertIn("mkdir -m 0700 \"$fixture_runtime_dir\"", runtime)
        self.assertIn('XDG_RUNTIME_DIR="$fixture_runtime_dir"', runtime)
        self.assertIn('WAYLAND_DISPLAY="$fixture_wayland_display"', runtime)
        self.assertIn('DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"', runtime)
        self.assertIn("systemd-run --user --machine=@.host --quiet --collect", runtime)
        self.assertEqual(runtime.count("systemd-run --user --machine=@.host"), 2)
        self.assertEqual(
            runtime.count("timeout --kill-after=1s 8s systemd-run --user"), 2
        )
        self.assertNotIn("$(systemctl --user show", runtime)
        self.assertIn("--property=KillMode=control-group", runtime)
        self.assertIn("SHIBUMI_TEST_SERVICE_FILE", runtime)
        self.assertIn("SHIBUMI_TEST_SERVICE_PREFIX", runtime)
        self.assertIn("refusing foreign fixture service", runtime)
        self.assertIn("^${SHIBUMI_TEST_SERVICE_PREFIX}-([1-9]|1[0-9]|2[0-5])", runtime)
        self.assertIn("package update (5) + fresh round trip (6) + two source round trips (7 each) = 25", runtime)
        self.assertIn("exact 25-shell generation budget", runtime)
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
            dict(rows)["native-catalog-resource"],
            "python3 tests/native-catalog-resource-regression.py",
        )
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
                "native-catalog-resource",
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
        replacements = dict(module.log_replacements([private_root]))
        self.assertEqual(replacements[str(ROOT).encode()], b"<repository>")
        self.assertEqual(replacements[str(Path.home()).encode()], b"<home>")
        self.assertEqual(replacements[private_root.encode()], b"<baseline:1>")

    def test_release_evidence_preflights_clean_exact_git_checkouts(self) -> None:
        path = ROOT / "scripts/collect-release-evidence"
        loader = importlib.machinery.SourceFileLoader(
            "release_evidence_preflight", str(path)
        )
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)

        with tempfile.TemporaryDirectory(
            prefix="shibumi-baseline-preflight."
        ) as temporary:
            checkout = Path(temporary) / "checkout"
            checkout.mkdir()
            subprocess.run(["git", "init", "-q", str(checkout)], check=True)
            tracked = checkout / "tracked"
            tracked.write_text("baseline\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(checkout), "add", "tracked"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(checkout),
                    "-c",
                    "user.name=Shibumi Test",
                    "-c",
                    "user.email=test.invalid@example.invalid",
                    "commit",
                    "-qm",
                    "baseline",
                ],
                check=True,
            )
            revision = subprocess.run(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()

            accepted = module.preflight_git_checkout(
                "SHIBUMI_TEST_BASELINE", str(checkout), revision
            )
            self.assertEqual(accepted["path"], str(checkout.resolve()))
            self.assertEqual(accepted["revision"], revision)
            self.assertEqual(accepted["status"], "clean")
            self.assertRegex(accepted["gitTree"], r"^[0-9a-f]{40}$")
            self.assertRegex(accepted["statusSha256"], r"^[0-9a-f]{64}$")
            self.assertRegex(accepted["workingTreeSha256"], r"^[0-9a-f]{64}$")

            hostile_git_environment = {
                "GIT_ALTERNATE_OBJECT_DIRECTORIES": str(Path(temporary) / "objects"),
                "GIT_CONFIG": str(Path(temporary) / "config"),
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "core.fsmonitor",
                "GIT_CONFIG_VALUE_0": "hostile",
                "GIT_DIR": str(Path(temporary) / "hostile.git"),
                "GIT_INDEX_FILE": str(Path(temporary) / "index"),
                "GIT_OBJECT_DIRECTORY": str(Path(temporary) / "objects"),
                "GIT_REPLACE_REF_BASE": "refs/hostile-replacements/",
                "GIT_WORK_TREE": str(Path(temporary) / "hostile-worktree"),
            }
            with patch.dict(os.environ, hostile_git_environment):
                hardened = module.preflight_git_checkout(
                    "SHIBUMI_TEST_BASELINE", str(checkout), revision
                )
            self.assertEqual(
                module.comparable_identity(hardened),
                module.comparable_identity(accepted),
            )
            self.assertFalse(
                any(name.startswith("GIT_") for name in module.checkout_git_environment())
            )

            tracked.write_text("replacement\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(checkout), "add", "tracked"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(checkout),
                    "-c",
                    "user.name=Shibumi Test",
                    "-c",
                    "user.email=test.invalid@example.invalid",
                    "commit",
                    "-qm",
                    "replacement",
                ],
                check=True,
            )
            replacement_revision = subprocess.run(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            subprocess.run(
                ["git", "-C", str(checkout), "checkout", "-q", revision], check=True
            )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(checkout),
                    "replace",
                    revision,
                    replacement_revision,
                ],
                check=True,
            )
            try:
                with self.assertRaisesRegex(ValueError, "replacement objects"):
                    module.preflight_git_checkout(
                        "SHIBUMI_TEST_BASELINE", str(checkout), revision
                    )
                with self.assertRaisesRegex(ValueError, "replacement objects"):
                    module.capture_git_checkout_identity(checkout)
            finally:
                subprocess.run(
                    ["git", "-C", str(checkout), "replace", "-d", revision],
                    check=True,
                    capture_output=True,
                )

            gate_environment, evidence_preflights = module.prepare_gate_environment(
                {
                    "SHIBUMI_TEST_BASELINE": "untrusted-alias",
                    **hostile_git_environment,
                },
                [accepted],
            )
            self.assertEqual(
                gate_environment["SHIBUMI_TEST_BASELINE"], str(checkout.resolve())
            )
            self.assertEqual(
                {
                    name: value
                    for name, value in gate_environment.items()
                    if name.startswith("GIT_")
                },
                {"GIT_NO_REPLACE_OBJECTS": "1"},
            )
            self.assertNotIn("path", evidence_preflights[0])
            self.assertNotIn(str(checkout.resolve()), json.dumps(evidence_preflights))

            helper = ROOT / "tests/lib/baselines.sh"
            shell_preflight = subprocess.run(
                [
                    "bash",
                    "-c",
                    'source "$1"; shibumi_preflight_clean_git_checkout "$2" "$3" test; printf "%s\\n" "$SHIBUMI_PREFLIGHT_OMARCHY_PATH"',
                    "shibumi-preflight-test",
                    str(helper),
                    str(checkout),
                    revision,
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(shell_preflight.returncode, 0, shell_preflight.stderr)
            self.assertEqual(shell_preflight.stdout.strip(), str(checkout.resolve()))

            linked_checkout = Path(temporary) / "linked-checkout"
            linked_checkout.symlink_to(checkout, target_is_directory=True)
            linked_parent = Path(temporary) / "linked-parent"
            linked_parent.symlink_to(Path(temporary), target_is_directory=True)
            noncanonical_checkout = str(checkout / ".." / checkout.name)
            invalid_cases = (
                ("", revision, "malformed checkout path"),
                ("relative/checkout", revision, "must be absolute"),
                (str(Path(temporary) / "missing"), revision, "is missing"),
                (str(linked_checkout), revision, "symlink component"),
                (
                    str(linked_parent / checkout.name),
                    revision,
                    "symlink component",
                ),
                (noncanonical_checkout, revision, "canonical and unlinked"),
                (str(checkout) + "/", revision, "canonical and unlinked"),
                (str(checkout), "malformed", "malformed expected revision"),
                (str(checkout), "0" * 40, "Git inspection failed"),
            )
            for checkout_path, expected, message in invalid_cases:
                with self.subTest(checkout_path=checkout_path, expected=expected):
                    with self.assertRaisesRegex(ValueError, message):
                        module.preflight_git_checkout(
                            "SHIBUMI_TEST_BASELINE", checkout_path, expected
                        )

            for checkout_path in (
                str(linked_checkout),
                str(linked_parent / checkout.name),
                noncanonical_checkout,
            ):
                with self.subTest(shell_checkout_path=checkout_path):
                    shell_alias = subprocess.run(
                        [
                            "bash",
                            "-c",
                            'source "$1"; shibumi_preflight_clean_git_checkout "$2" "$3" test',
                            "shibumi-preflight-test",
                            str(helper),
                            checkout_path,
                            revision,
                        ],
                        check=False,
                        capture_output=True,
                        text=True,
                    )
                    self.assertNotEqual(shell_alias.returncode, 0)
                    self.assertRegex(shell_alias.stderr, r"linked|canonical")

            (checkout / "untracked").write_text("dirty\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "checkout is dirty"):
                module.preflight_git_checkout(
                    "SHIBUMI_TEST_BASELINE", str(checkout), revision
                )
            shell_dirty = subprocess.run(
                [
                    "bash",
                    "-c",
                    'source "$1"; shibumi_preflight_clean_git_checkout "$2" "$3" test',
                    "shibumi-preflight-test",
                    str(helper),
                    str(checkout),
                    revision,
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(shell_dirty.returncode, 0)
            self.assertIn("checkout is dirty", shell_dirty.stderr)

        with self.assertRaises(ValueError) as missing:
            module.preflight_external_baselines({})
        for environment_name, _manifest in module.EXTERNAL_BASELINES:
            self.assertIn(environment_name, str(missing.exception))

        helper_text = (ROOT / "tests/lib/baselines.sh").read_text(encoding="utf-8")
        self.assertIn("shibumi_preflight_clean_git_checkout", helper_text)
        self.assertIn("--untracked-files=all --ignore-submodules=none", helper_text)

    def test_release_evidence_revalidates_inputs_around_every_gate(self) -> None:
        path = ROOT / "scripts/collect-release-evidence"
        loader = importlib.machinery.SourceFileLoader(
            "release_evidence_identity", str(path)
        )
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)

        def create_checkout(parent: Path, name: str) -> tuple[Path, str]:
            checkout = parent / name
            checkout.mkdir()
            subprocess.run(["git", "init", "-q", str(checkout)], check=True)
            tracked = checkout / "tracked"
            tracked.write_text(f"{name}\n", encoding="utf-8")
            tracked.chmod(0o644)
            subprocess.run(["git", "-C", str(checkout), "add", "tracked"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(checkout),
                    "-c",
                    "user.name=Shibumi Test",
                    "-c",
                    "user.email=test.invalid@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                check=True,
            )
            revision = subprocess.run(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            return checkout, revision

        with tempfile.TemporaryDirectory(
            prefix="shibumi-release-identities."
        ) as temporary:
            temporary_path = Path(temporary)
            candidate, _candidate_revision = create_checkout(
                temporary_path, "candidate"
            )
            baseline, baseline_revision = create_checkout(
                temporary_path, "baseline"
            )
            expected_candidate = module.capture_git_checkout_identity(candidate)
            expected_baseline = module.preflight_git_checkout(
                "SHIBUMI_TEST_BASELINE", str(baseline), baseline_revision
            )
            baselines = [expected_baseline]
            baseline_paths = [str(baseline)]
            environment, _evidence = module.prepare_gate_environment(
                os.environ.copy(), baselines
            )
            self.assertEqual(environment["GIT_NO_REPLACE_OBJECTS"], "1")

            unchanged = module.run_guarded_evidence_gate(
                "unchanged-control",
                (sys.executable, "-c", "pass"),
                temporary_path / "unchanged.log",
                baseline_paths,
                candidate,
                expected_candidate,
                baselines,
                timeout_seconds=2,
                environment=environment,
            )
            self.assertEqual(unchanged["status"], "passed")
            self.assertEqual(
                unchanged["inputValidation"],
                {"status": "passed", "phase": "before-and-after"},
            )

            candidate_tracked = candidate / "tracked"
            candidate_tracked.write_text("replacement\n", encoding="utf-8")
            subprocess.run(
                ["git", "-C", str(candidate), "add", "tracked"], check=True
            )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(candidate),
                    "-c",
                    "user.name=Shibumi Test",
                    "-c",
                    "user.email=test.invalid@example.invalid",
                    "commit",
                    "-qm",
                    "replacement",
                ],
                check=True,
            )
            replacement_revision = subprocess.run(
                ["git", "-C", str(candidate), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            subprocess.run(
                ["git", "-C", str(candidate), "checkout", "-q", _candidate_revision],
                check=True,
            )
            replacement_program = "\n".join((
                "import subprocess",
                f"repo = {str(candidate)!r}",
                f"original = {_candidate_revision!r}",
                f"replacement = {replacement_revision!r}",
                "subprocess.run(['git', '-C', repo, 'replace', original, replacement], check=True)",
                "try:",
                "    content = subprocess.run(['git', '-C', repo, 'show', 'HEAD:tracked'], check=True, capture_output=True, text=True).stdout",
                "    print(content, end='')",
                "finally:",
                "    subprocess.run(['git', '-C', repo, 'replace', '-d', original], check=True, capture_output=True)",
            ))
            transient_replacement = module.run_guarded_evidence_gate(
                "transient-replacement",
                (sys.executable, "-c", replacement_program),
                temporary_path / "transient-replacement.log",
                baseline_paths,
                candidate,
                expected_candidate,
                baselines,
                timeout_seconds=2,
                environment=environment,
            )
            self.assertEqual(transient_replacement["status"], "passed")
            self.assertEqual(
                (temporary_path / "transient-replacement.log").read_text(
                    encoding="utf-8"
                ),
                "candidate\n",
            )
            self.assertEqual(module.checkout_git(candidate, "replace", "-l"), "")

            untracked = baseline / "untracked"
            untracked.write_text("drift\n", encoding="utf-8")
            gate_marker = temporary_path / "refused-gate-ran"
            refused = module.run_guarded_evidence_gate(
                "baseline-precheck-drift",
                (
                    sys.executable,
                    "-c",
                    f"from pathlib import Path; Path({str(gate_marker)!r}).touch()",
                ),
                temporary_path / "baseline-precheck.log",
                baseline_paths,
                candidate,
                expected_candidate,
                baselines,
                timeout_seconds=2,
                environment=environment,
            )
            self.assertFalse(gate_marker.exists())
            self.assertEqual(refused["status"], "input-drift")
            self.assertEqual(refused["inputValidation"]["phase"], "before")
            untracked.unlink()

            baseline_program = (
                "from pathlib import Path; "
                f"Path({str(baseline / 'tracked')!r}).write_text('changed\\n')"
            )
            baseline_during = module.run_guarded_evidence_gate(
                "baseline-during-gate",
                (sys.executable, "-c", baseline_program),
                temporary_path / "baseline-during.log",
                baseline_paths,
                candidate,
                expected_candidate,
                baselines,
                timeout_seconds=2,
                environment=environment,
            )
            self.assertEqual(baseline_during["status"], "input-drift")
            self.assertEqual(baseline_during["inputValidation"]["phase"], "after")
            (baseline / "tracked").write_text("baseline\n", encoding="utf-8")

            candidate_program = (
                "from pathlib import Path; "
                f"Path({str(candidate / 'tracked')!r}).chmod(0o600)"
            )
            candidate_during = module.run_guarded_evidence_gate(
                "candidate-mode-during-gate",
                (sys.executable, "-c", candidate_program),
                temporary_path / "candidate-during.log",
                baseline_paths,
                candidate,
                expected_candidate,
                baselines,
                timeout_seconds=2,
                environment=environment,
            )
            self.assertEqual(candidate_during["status"], "input-drift")
            self.assertEqual(candidate_during["inputValidation"]["phase"], "after")
            (candidate / "tracked").chmod(0o644)

            module.validate_release_input_identities(
                candidate, expected_candidate, baselines
            )

            (candidate / "tracked").write_text("staged drift\n", encoding="utf-8")
            subprocess.run(
                ["git", "-C", str(candidate), "add", "tracked"], check=True
            )
            with self.assertRaisesRegex(ValueError, "candidate identity drift"):
                module.validate_release_input_identities(
                    candidate, expected_candidate, baselines
                )

    def test_release_evidence_gate_progress_and_timeout_are_bounded(self) -> None:
        path = ROOT / "scripts/collect-release-evidence"
        loader = importlib.machinery.SourceFileLoader(
            "release_evidence_progress", str(path)
        )
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)

        self.assertEqual(module.GATE_TIMEOUT_SECONDS, 1800)
        release_runbook = (ROOT / "docs/development/release.md").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "Every evidence gate has a 30-minute process-group timeout.",
            release_runbook,
        )
        self.assertNotIn(
            "Every evidence gate has a 15-minute process-group timeout.",
            release_runbook,
        )

        with tempfile.TemporaryDirectory(
            prefix="shibumi-evidence-progress."
        ) as temporary:
            temporary_path = Path(temporary)
            log_path = temporary_path / "pass.log"
            progress = io.StringIO()
            with contextlib.redirect_stdout(progress):
                result = module.run_evidence_gate(
                    "fixture-pass",
                    (sys.executable, "-c", "print('detailed output')"),
                    log_path,
                    [],
                    timeout_seconds=2,
                )
            lines = progress.getvalue().splitlines()
            self.assertEqual(len(lines), 3)
            self.assertEqual(sum("gate start:" in line for line in lines), 1)
            self.assertEqual(sum("gate result:" in line for line in lines), 1)
            self.assertEqual(sum("gate duration:" in line for line in lines), 1)
            self.assertNotIn("detailed output", progress.getvalue())
            self.assertEqual(log_path.read_text(encoding="utf-8"), "detailed output\n")
            self.assertEqual(result["status"], "passed")
            self.assertEqual(result["exitCode"], 0)
            self.assertFalse(result["timedOut"])

            nonzero_log = temporary_path / "nonzero.log"
            nonzero = module.run_evidence_gate(
                "fixture-nonzero",
                (sys.executable, "-c", "raise SystemExit(7)"),
                nonzero_log,
                [],
                timeout_seconds=2,
            )
            self.assertEqual(nonzero["status"], "failed")
            self.assertEqual(nonzero["exitCode"], 7)
            self.assertFalse(nonzero["timedOut"])

            start_log = temporary_path / "start.log"
            start_error = module.run_evidence_gate(
                "fixture-start-error",
                (str(temporary_path / "missing-command"),),
                start_log,
                [],
            )
            self.assertEqual(start_error["status"], "start-error")
            self.assertIsNone(start_error["exitCode"])
            self.assertEqual(start_error["timeoutSeconds"], 1800)
            self.assertIn("could not start gate", start_log.read_text(encoding="utf-8"))

            timeout_log = temporary_path / "timeout.log"
            timeout_progress = io.StringIO()
            timeout_program = """
import signal
import subprocess
import sys
import time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([
    sys.executable,
    "-c",
    "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)",
])
print(child.pid, flush=True)
time.sleep(30)
"""
            started = time.monotonic()
            with contextlib.redirect_stdout(timeout_progress):
                timeout_result = module.run_evidence_gate(
                    "fixture-timeout",
                    (sys.executable, "-c", timeout_program),
                    timeout_log,
                    [],
                    timeout_seconds=0.1,
                    termination_grace_seconds=0.1,
                )
            self.assertLess(time.monotonic() - started, 2)
            self.assertEqual(len(timeout_progress.getvalue().splitlines()), 3)
            self.assertNotEqual(timeout_result["exitCode"], 0)
            self.assertTrue(timeout_result["timedOut"])
            self.assertEqual(timeout_result["status"], "timed-out")
            self.assertIn("timed-out", timeout_progress.getvalue())
            child_pid = int(timeout_log.read_text(encoding="utf-8").strip())
            child_active = True
            for _attempt in range(50):
                status_path = Path(f"/proc/{child_pid}/stat")
                if not status_path.exists():
                    child_active = False
                    break
                fields = status_path.read_text(encoding="utf-8").rsplit(") ", 1)
                if len(fields) == 2 and fields[1].startswith("Z "):
                    child_active = False
                    break
                time.sleep(0.01)
            self.assertFalse(child_active, "timed-out child survived its process group")

    def test_release_evidence_refuses_reused_or_unsafe_output_paths(self) -> None:
        path = ROOT / "scripts/collect-release-evidence"
        loader = importlib.machinery.SourceFileLoader(
            "release_evidence_outputs", str(path)
        )
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)

        with tempfile.TemporaryDirectory(
            prefix="shibumi-evidence-outputs."
        ) as temporary:
            temporary_path = Path(temporary)
            log_dir = temporary_path / "logs"
            module.create_fresh_log_directory(log_dir)
            self.assertEqual(log_dir.stat().st_mode & 0o777, 0o700)
            with self.assertRaisesRegex(ValueError, "already exists"):
                module.create_fresh_log_directory(log_dir)

            result = module.run_evidence_gate(
                "fixture-pass",
                (sys.executable, "-c", "print('bounded')"),
                log_dir / "fixture-pass.log",
                [],
                timeout_seconds=2,
            )
            module.validate_log_inventory(log_dir, [result])
            stale = log_dir / "stale.log"
            stale.write_bytes(b"stale\n")
            with self.assertRaisesRegex(ValueError, "stale files"):
                module.validate_log_inventory(log_dir, [result])

            victim = temporary_path / "victim"
            victim.write_bytes(b"preserve\n")
            linked_log = temporary_path / "linked.log"
            linked_log.symlink_to(victim)
            with patch.object(module.subprocess, "Popen") as popen:
                with self.assertRaisesRegex(ValueError, "unsafe or already exists"):
                    module.run_evidence_gate(
                        "fixture-linked",
                        (sys.executable, "-c", "print('must not run')"),
                        linked_log,
                        [],
                        timeout_seconds=2,
                    )
            popen.assert_not_called()
            self.assertEqual(victim.read_bytes(), b"preserve\n")

            existing_log = temporary_path / "existing.log"
            existing_log.write_bytes(b"preserve-existing\n")
            with self.assertRaisesRegex(ValueError, "unsafe or already exists"):
                module.run_evidence_gate(
                    "fixture-existing",
                    (sys.executable, "-c", "print('must not run')"),
                    existing_log,
                    [],
                    timeout_seconds=2,
                )
            self.assertEqual(existing_log.read_bytes(), b"preserve-existing\n")

            linked_output = temporary_path / "evidence.json"
            linked_output.symlink_to(victim)
            with self.assertRaisesRegex(ValueError, "unsafe or already exists"):
                module.write_new_file(linked_output, b"replacement\n")
            self.assertEqual(victim.read_bytes(), b"preserve\n")

    def test_release_evidence_streams_redaction_and_enforces_log_budgets(self) -> None:
        path = ROOT / "scripts/collect-release-evidence"
        loader = importlib.machinery.SourceFileLoader(
            "release_evidence_limits", str(path)
        )
        spec = importlib.util.spec_from_loader(loader.name, loader)
        self.assertIsNotNone(spec)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)

        with tempfile.TemporaryDirectory(
            prefix="shibumi-evidence-limits."
        ) as temporary:
            temporary_path = Path(temporary)
            private_path = "/srv/private/omarchy-source"
            redacted_log = temporary_path / "redacted.log"
            with patch.object(module, "LOG_READ_CHUNK_BYTES", 3):
                redacted = module.run_evidence_gate(
                    "fixture-redaction",
                    (
                        sys.executable,
                        "-c",
                        f"import os; os.write(1, {private_path.encode()!r})",
                    ),
                    redacted_log,
                    [private_path],
                    timeout_seconds=2,
                )
            self.assertEqual(redacted["status"], "passed")
            self.assertEqual(redacted_log.read_bytes(), b"<baseline:1>")
            self.assertNotIn(private_path.encode(), redacted_log.read_bytes())

            for output_bytes in (63, 64):
                with self.subTest(raw_output_bytes=output_bytes):
                    bounded_log = temporary_path / f"bounded-{output_bytes}.log"
                    bounded = module.run_evidence_gate(
                        f"fixture-bounded-{output_bytes}",
                        (
                            sys.executable,
                            "-c",
                            f"import os; os.write(1, b'x' * {output_bytes})",
                        ),
                        bounded_log,
                        [],
                        timeout_seconds=2,
                        raw_byte_limit=64,
                        log_byte_limit=64,
                    )
                    self.assertEqual(bounded["status"], "passed")
                    self.assertEqual(bounded["rawLogBytes"], output_bytes)
                    self.assertEqual(bounded_log.stat().st_size, output_bytes)

            per_gate_log = temporary_path / "per-gate.log"
            per_gate = module.run_evidence_gate(
                "fixture-per-gate-limit",
                (sys.executable, "-c", "import os; os.write(1, b'x' * 65)"),
                per_gate_log,
                [],
                timeout_seconds=2,
                raw_byte_limit=64,
                log_byte_limit=64,
                termination_grace_seconds=0.1,
            )
            self.assertEqual(per_gate["status"], "output-limit")
            self.assertTrue(per_gate["outputLimitExceeded"])
            self.assertEqual(per_gate["rawLogBytes"], 64)
            self.assertLessEqual(per_gate_log.stat().st_size, 64)

            redacted_limit_log = temporary_path / "redacted-limit.log"
            redacted_limit = module.run_evidence_gate(
                "fixture-redacted-limit",
                (sys.executable, "-c", "import os; os.write(1, b'/x')"),
                redacted_limit_log,
                ["/x"],
                timeout_seconds=2,
                raw_byte_limit=64,
                log_byte_limit=len(b"<baseline:1>") - 1,
                termination_grace_seconds=0.1,
            )
            self.assertEqual(redacted_limit["status"], "output-limit")
            self.assertEqual(redacted_limit["rawLogBytes"], 2)
            self.assertLessEqual(
                redacted_limit_log.stat().st_size, len(b"<baseline:1>") - 1
            )

            budget = module.EvidenceLogBudget(
                total_raw_bytes=10,
                total_redacted_bytes=10,
                per_gate_raw_bytes=6,
                per_gate_redacted_bytes=6,
            )
            first_limits = budget.gate_limits()
            first = module.run_evidence_gate(
                "fixture-total-first",
                (sys.executable, "-c", "import os; os.write(1, b'123456')"),
                temporary_path / "total-first.log",
                [],
                timeout_seconds=2,
                raw_byte_limit=first_limits[0],
                log_byte_limit=first_limits[1],
            )
            self.assertEqual(first["status"], "passed")
            budget.consume(first)
            second_limits = budget.gate_limits()
            self.assertEqual(second_limits, (4, 4))
            second = module.run_evidence_gate(
                "fixture-total-second",
                (sys.executable, "-c", "import os; os.write(1, b'12345')"),
                temporary_path / "total-second.log",
                [],
                timeout_seconds=2,
                raw_byte_limit=second_limits[0],
                log_byte_limit=second_limits[1],
                termination_grace_seconds=0.1,
            )
            self.assertEqual(second["status"], "output-limit")
            budget.consume(second)
            self.assertEqual(budget.gate_limits(), (0, 4))
            exhausted_limits = budget.gate_limits()
            with patch.object(module.subprocess, "Popen") as popen:
                exhausted = module.run_evidence_gate(
                    "fixture-total-raw-exhausted",
                    (sys.executable, "-c", "print('must not run')"),
                    temporary_path / "total-raw-exhausted.log",
                    [],
                    timeout_seconds=2,
                    raw_byte_limit=exhausted_limits[0],
                    log_byte_limit=exhausted_limits[1],
                )
            popen.assert_not_called()
            self.assertEqual(exhausted["status"], "output-limit")

            redacted_budget = module.EvidenceLogBudget(
                total_raw_bytes=10,
                total_redacted_bytes=10,
                per_gate_raw_bytes=10,
                per_gate_redacted_bytes=10,
            )
            redacted_first = module.run_evidence_gate(
                "fixture-total-redacted-first",
                (sys.executable, "-c", "import os; os.write(1, b'123456')"),
                temporary_path / "total-redacted-first.log",
                [],
                timeout_seconds=2,
                raw_byte_limit=10,
                log_byte_limit=10,
            )
            redacted_budget.consume(redacted_first)
            redacted_limits = redacted_budget.gate_limits()
            self.assertEqual(redacted_limits, (4, 4))
            redacted_second = module.run_evidence_gate(
                "fixture-total-redacted-second",
                (sys.executable, "-c", "import os; os.write(1, b'/x')"),
                temporary_path / "total-redacted-second.log",
                ["/x"],
                timeout_seconds=2,
                raw_byte_limit=redacted_limits[0],
                log_byte_limit=redacted_limits[1],
            )
            self.assertEqual(redacted_second["status"], "output-limit")
            redacted_budget.consume(redacted_second)
            self.assertEqual(redacted_budget.gate_limits(), (2, 0))

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
