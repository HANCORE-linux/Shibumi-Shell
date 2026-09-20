#!/usr/bin/env python3

from __future__ import annotations

import copy
import io
import json
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from shibumi_suite.admission import (  # noqa: E402
    AdmissionError,
    UnsupportedInstallIdentity,
    JOURNAL_SCHEMA_VERSION,
    MAX_PREDECESSOR_STATES,
    classify_install_state,
    inventory_transactions,
    preflight_lifecycle_state,
    supported_install_identities,
)
from shibumi_suite.cli import command_status_with_admission  # noqa: E402
from shibumi_suite.model import Suite, suite_payload_digest  # noqa: E402
from shibumi_suite.runtime import OmarchyRuntime, RuntimePaths  # noqa: E402
from shibumi_suite.transaction import (  # noqa: E402
    PluginTransaction,
    TransactionError,
    recover_transactions,
)
import shibumi_suite.transaction as transaction_module  # noqa: E402


class LifecycleAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="shibumi-admission-")
        self.root = Path(self.temporary.name)
        self.suite = Suite.load(REPO_ROOT)
        self.paths = RuntimePaths(
            omarchy_root=self.root / "omarchy",
            plugin_dir=self.root / "config/omarchy/plugins",
            config_file=self.root / "config/omarchy/shell.json",
            defaults_file=self.root / "defaults/shell.json",
            state_dir=self.root / "state/shibumi",
            cache_dir=self.root / "cache/shibumi",
            lock_file=self.root / "runtime/shibumi-suite.lock",
        )
        self.paths.state_dir.mkdir(parents=True)
        # The repository may intentionally contain unrelated payload work while
        # these isolated lifecycle fixtures run. Give fixture-generated current
        # payloads a clean synthetic source identity; production dirty revisions
        # are covered by an explicit rejection below.
        self.suite.revision = Mock(return_value="f" * 40)  # type: ignore[method-assign]
        self.identities = supported_install_identities(self.suite)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def state_for(
        self,
        identity: dict[str, object],
        revision: str | None = None,
    ) -> dict[str, object]:
        revision = revision or str(identity["sourceRevisions"][0])
        package = revision.startswith("package:")
        state: dict[str, object] = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": identity["suiteVersion"],
            "profile": "default",
            "activeBar": "hancore.shibumi.bar",
            "plugins": list(self.suite.profile("default").install),
            "installOrigin": "package" if package else "checkout",
            "payloadRoot": "/usr/share/shibumi" if package else str(REPO_ROOT),
            "sourceRevision": revision,
            "payloadDigest": identity["payloadDigest"],
            "pluginDigests": copy.deepcopy(identity["pluginDigests"]),
            "activation": {
                "activeBar": "hancore.shibumi.bar",
                "mode": "managed",
                "layoutPolicy": "managed",
                "configuredBar": "hancore.shibumi.bar",
                "layout": {
                    region: list(self.suite.profile("default").layout[region])
                    for region in ("left", "center", "right")
                },
                "enableServices": list(
                    self.suite.profile("default").enable_services
                ),
                "continuityPlugins": [
                    "hancore.shibumi.control-center",
                    "hancore.shibumi.state",
                ],
            },
            "updatedEpoch": 1,
            "menuExtension": {
                "schemaVersion": 1,
                "createdFile": True,
            },
        }
        if identity["settingsStorageVersion"] == 1:
            state["settingsStorageVersion"] = 1
        if package:
            state["packageName"] = "shibumi-shell"
            state["packageVersion"] = revision.removeprefix("package:")
        else:
            state["sourceRoot"] = str(REPO_ROOT)
        return state

    def test_storage_metadata_must_match_payload_identity(self) -> None:
        for identity in self.identities:
            state = self.state_for(identity)
            if identity["settingsStorageVersion"] == 1:
                state.pop("settingsStorageVersion")
            else:
                state["settingsStorageVersion"] = 1
            with self.subTest(identity=identity["id"]), self.assertRaisesRegex(
                    AdmissionError, "revision/digest identity"):
                classify_install_state(state, self.suite, self.identities)

    def write_state(self, state: dict[str, object]) -> None:
        (self.paths.state_dir / "install.json").write_text(
            json.dumps(state, sort_keys=True) + "\n", encoding="utf-8"
        )

    def journal(self, token: str, phase: str = "prepared") -> dict[str, object]:
        self.paths.config_file.parent.mkdir(parents=True, exist_ok=True)
        config_parent = self.paths.config_file.parent.stat()
        return {
            "schemaVersion": JOURNAL_SCHEMA_VERSION,
            "suiteId": "hancore.shibumi",
            "token": token,
            "phase": phase,
            "pluginRoot": str(self.paths.plugin_dir.resolve(strict=False)),
            "configPath": str(self.paths.config_file.resolve(strict=False)),
            "configParentIdentity": {
                "device": config_parent.st_dev,
                "inode": config_parent.st_ino,
            },
            "configExisted": False,
            "menuExtensionPath": str(
                self.paths.menu_extension_file.resolve(strict=False)
            ),
            "menuExtensionExisted": False,
            "restartOnReconcile": False,
            "shellStopped": False,
            "restoreRequiresDrain": False,
            "liveMutationStarted": False,
            "payloadReloadExpected": False,
            "records": [],
        }

    def materialize_live_state(
        self, state: dict[str, object], transaction: str
    ) -> None:
        for plugin_id in state["plugins"]:
            target = self.paths.plugin_dir / plugin_id
            shutil.copytree(self.suite.plugins[plugin_id].source, target)
            marker = {
                "schemaVersion": 1,
                "suiteId": "hancore.shibumi",
                "suiteVersion": state["suiteVersion"],
                "pluginId": plugin_id,
                "sourceRevision": state["sourceRevision"],
                "payloadDigest": state["pluginDigests"][plugin_id],
                "suitePayloadDigest": state["payloadDigest"],
                "transaction": transaction,
            }
            (target / ".shibumi-managed.json").write_text(
                json.dumps(marker) + "\n", encoding="utf-8"
            )

    def materialize_beta141_payload_drift(
        self, revision: str
    ) -> tuple[dict[str, object], Path]:
        if self.paths.plugin_dir.exists():
            shutil.rmtree(self.paths.plugin_dir)
        state_path = self.paths.state_dir / "install.json"
        state_path.unlink(missing_ok=True)

        identity = next(
            item for item in self.identities if item["id"] == "public-beta.14.1"
        )
        beta141_revision = "7a6c853b1947d303bad9a5b640c224c01b669106"
        beta141_digest = (
            "0350a8f66d81dc640b6d268ace149620ae78c40aea13ad2cd507ad6de93d8de3"
        )
        self.assertIn(beta141_revision, identity["sourceRevisions"])
        self.assertEqual(identity["payloadDigest"], beta141_digest)

        state = self.state_for(identity, revision)
        for plugin_id in state["plugins"]:
            shutil.copytree(
                self.suite.plugins[plugin_id].source,
                self.paths.plugin_dir / plugin_id,
            )
        changed_payload = (
            self.paths.plugin_dir
            / str(state["plugins"][0])
            / "manifest.json"
        )
        changed_payload.write_bytes(
            changed_payload.read_bytes() + b"\n// deterministic debug overlay\n"
        )

        actual_plugin_digests = {
            str(plugin_id): self.suite.plugins[str(plugin_id)].payload_digest(
                self.paths.plugin_dir / str(plugin_id)
            )
            for plugin_id in state["plugins"]
        }
        actual_suite_digest = suite_payload_digest(actual_plugin_digests)
        self.assertNotEqual(actual_suite_digest, beta141_digest)
        state["pluginDigests"] = actual_plugin_digests
        state["payloadDigest"] = actual_suite_digest
        self.write_state(state)

        transaction = "1700000000-1-14114114"
        for plugin_id in state["plugins"]:
            target = self.paths.plugin_dir / str(plugin_id)
            marker = {
                "schemaVersion": 1,
                "suiteId": "hancore.shibumi",
                "suiteVersion": state["suiteVersion"],
                "pluginId": plugin_id,
                "sourceRevision": revision,
                "payloadDigest": actual_plugin_digests[str(plugin_id)],
                "suitePayloadDigest": actual_suite_digest,
                "transaction": transaction,
            }
            (target / ".shibumi-managed.json").write_text(
                json.dumps(marker) + "\n", encoding="utf-8"
            )
            self.assertEqual(
                self.suite.plugins[str(plugin_id)].payload_digest(target),
                actual_plugin_digests[str(plugin_id)],
            )
        return state, changed_payload

    def write_journal(
        self, token: str, journal: dict[str, object], *, prefix: str = ""
    ) -> Path:
        directory = self.paths.state_dir / "transactions" / f"{prefix}{token}"
        directory.mkdir(parents=True, exist_ok=False)
        (directory / "journal.json").write_text(
            json.dumps(journal, sort_keys=True) + "\n", encoding="utf-8"
        )
        return directory

    def test_exact_public_release_and_step5_states_are_admitted(self) -> None:
        for identity_id in (
            "public-beta.11",
            "step-5-tip",
            "public-beta.12",
            "public-beta.13",
            "source-beta.14",
            "public-beta.14.1",
            "public-beta.15",
        ):
            identity = next(
                item for item in self.identities if item["id"] == identity_id
            )
            for revision in identity["sourceRevisions"]:
                with self.subTest(identity=identity_id, revision=revision):
                    state = self.state_for(identity, str(revision))
                    self.assertEqual(
                        classify_install_state(state, self.suite, self.identities),
                        identity_id,
                    )
        migrated = self.state_for(
            next(item for item in self.identities if item["id"] == "step-5-tip")
        )
        migrated["migratedFrom"] = {
            "suiteId": "hancore.qsrise",
            "suiteVersion": "0.1.0",
            "sourceRevision": "legacy",
            "payloadDigest": "a" * 64,
            "migratedEpoch": 1,
        }
        self.assertEqual(
            classify_install_state(migrated, self.suite, self.identities),
            "step-5-tip",
        )

    def test_predecessor_contract_parser_is_exact_and_bounded(self) -> None:
        contract = json.loads(
            (REPO_ROOT / "contracts/lifecycle-predecessors-v1.json").read_text(
                encoding="utf-8"
            )
        )
        contract_root = self.root / "contract-fixture"
        contract_dir = contract_root / "contracts"
        contract_dir.mkdir(parents=True)
        fixture_suite = copy.copy(self.suite)
        fixture_suite.root = contract_root
        fixture_suite.revision = Mock(return_value="f" * 40)  # type: ignore[method-assign]

        cases: dict[str, dict[str, object]] = {}
        unknown_field = copy.deepcopy(contract)
        unknown_field["states"][0]["futureIdentity"] = True
        cases["unknown-field"] = unknown_field
        duplicate_id = copy.deepcopy(contract)
        duplicate_id["states"][1]["id"] = duplicate_id["states"][0]["id"]
        cases["duplicate-id"] = duplicate_id
        duplicate_revision = copy.deepcopy(contract)
        duplicate_revision["states"][1]["sourceRevisions"] = [
            duplicate_revision["states"][0]["sourceRevisions"][0]
        ]
        cases["duplicate-revision"] = duplicate_revision
        non_string_revision = copy.deepcopy(contract)
        non_string_revision["states"][0]["sourceRevisions"] = [{}]
        cases["non-string-revision"] = non_string_revision
        no_states = copy.deepcopy(contract)
        no_states["states"] = []
        cases["empty"] = no_states
        too_many = copy.deepcopy(contract)
        too_many["states"] = [
            copy.deepcopy(contract["states"][0])
            for _ in range(MAX_PREDECESSOR_STATES + 1)
        ]
        cases["too-many"] = too_many

        contract_path = contract_dir / "lifecycle-predecessors-v1.json"
        for name, value in cases.items():
            with self.subTest(name=name):
                contract_path.write_text(
                    json.dumps(value) + "\n", encoding="utf-8"
                )
                with self.assertRaisesRegex(
                    AdmissionError, "invalid lifecycle predecessor"
                ):
                    supported_install_identities(fixture_suite)

        contract_path.write_bytes(b" " * (1024 * 1024 + 1))
        with self.assertRaisesRegex(AdmissionError, "exceeds the"):
            supported_install_identities(fixture_suite)

    def test_unknown_install_or_activation_fields_fail_closed(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "step-5-tip"
        )
        for mutation in ("top-level", "activation-mode", "activation-field"):
            with self.subTest(mutation=mutation):
                state = self.state_for(identity)
                if mutation == "top-level":
                    state["futureAuthority"] = {"enabled": True}
                elif mutation == "activation-mode":
                    state["activation"]["mode"] = "step6"  # type: ignore[index]
                else:
                    state["activation"]["futureWriter"] = True  # type: ignore[index]
                with self.assertRaisesRegex(AdmissionError, "unknown|Step-6"):
                    classify_install_state(state, self.suite, self.identities)

    def test_beta14_source_revision_cannot_authorize_beta141_payload(self) -> None:
        source_beta14 = next(
            item for item in self.identities if item["id"] == "source-beta.14"
        )
        beta141 = next(
            item for item in self.identities if item["id"] == "public-beta.14.1"
        )
        old_revision = "11c9f63147ffea3265bdff442bb556f23700d209"
        self.assertEqual(source_beta14["sourceRevisions"][0], old_revision)
        self.assertEqual(
            beta141["payloadDigest"],
            "0350a8f66d81dc640b6d268ace149620ae78c40aea13ad2cd507ad6de93d8de3",
        )

        self.assertEqual(
            classify_install_state(
                self.state_for(source_beta14, old_revision),
                self.suite,
                self.identities,
            ),
            "source-beta.14",
        )
        self.assertEqual(
            classify_install_state(
                self.state_for(beta141), self.suite, self.identities
            ),
            "public-beta.14.1",
        )

        mixed = self.state_for(beta141, old_revision)
        with self.assertRaisesRegex(AdmissionError, "revision/digest identity"):
            classify_install_state(mixed, self.suite, self.identities)

    def test_update_rejects_beta141_same_revision_honest_payload_drift(self) -> None:
        beta141_revision = "7a6c853b1947d303bad9a5b640c224c01b669106"
        for revision in (beta141_revision, f"{beta141_revision}-dirty"):
            with self.subTest(revision=revision):
                state, changed_payload = self.materialize_beta141_payload_drift(
                    revision
                )
                state_before = (self.paths.state_dir / "install.json").read_bytes()
                payload_before = changed_payload.read_bytes()

                with self.assertRaises(UnsupportedInstallIdentity) as raised:
                    preflight_lifecycle_state(
                        self.paths,
                        self.suite,
                        allow_payload_repair=False,
                    )

                self.assertEqual(
                    raised.exception.diagnostic["sourceRevision"], revision
                )
                self.assertEqual(
                    raised.exception.diagnostic["suitePayloadDigest"],
                    state["payloadDigest"],
                )
                self.assertIn("revision/digest identity", str(raised.exception))
                self.assertIn("no recovery or mutation", str(raised.exception))
                self.assertEqual(
                    (self.paths.state_dir / "install.json").read_bytes(),
                    state_before,
                )
                self.assertEqual(changed_payload.read_bytes(), payload_before)

    def test_repair_rejects_beta141_same_revision_honest_payload_drift(self) -> None:
        beta141_revision = "7a6c853b1947d303bad9a5b640c224c01b669106"
        for revision in (beta141_revision, f"{beta141_revision}-dirty"):
            with self.subTest(revision=revision):
                state, changed_payload = self.materialize_beta141_payload_drift(
                    revision
                )
                state_before = (self.paths.state_dir / "install.json").read_bytes()
                payload_before = changed_payload.read_bytes()

                with self.assertRaises(UnsupportedInstallIdentity) as raised:
                    preflight_lifecycle_state(
                        self.paths,
                        self.suite,
                        allow_payload_repair=True,
                    )

                self.assertEqual(
                    raised.exception.diagnostic["sourceRevision"], revision
                )
                self.assertEqual(
                    raised.exception.diagnostic["suitePayloadDigest"],
                    state["payloadDigest"],
                )
                self.assertIn("revision/digest identity", str(raised.exception))
                self.assertIn("no recovery or mutation", str(raised.exception))
                self.assertEqual(
                    (self.paths.state_dir / "install.json").read_bytes(),
                    state_before,
                )
                self.assertEqual(changed_payload.read_bytes(), payload_before)

    def test_shared_version_with_wrong_revision_or_digest_is_rejected(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "step-5-tip"
        )
        for mutation in ("revision", "digest"):
            with self.subTest(mutation=mutation):
                state = self.state_for(identity)
                if mutation == "revision":
                    state["sourceRevision"] = "08ade6e000000000000000000000000000000000"
                else:
                    state["payloadDigest"] = "0" * 64
                self.write_state(state)
                with self.assertRaisesRegex(
                    AdmissionError, "revision/digest identity"
                ):
                    preflight_lifecycle_state(self.paths, self.suite)
                (self.paths.state_dir / "install.json").unlink()

    def test_status_emits_exact_redaction_safe_unsupported_identity(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        state = self.state_for(identity)
        state["suiteVersion"] = "0.1.1-beta.12"
        state["sourceRevision"] = "a" * 40
        state["payloadRoot"] = "/home/reporter/private/shibumi"
        state["sourceRoot"] = "/home/reporter/private/shibumi"
        state["previousBar"] = {
            "command": "DO-NOT-PRINT",
            "config": "PRIVATE-CONTENT",
            "username": "reporter",
        }
        self.write_state(state)
        before = (self.paths.state_dir / "install.json").read_bytes()
        stdout = io.StringIO()
        stderr = io.StringIO()

        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = command_status_with_admission(self.suite, self.paths)

        diagnostic = {
            "suiteVersion": state["suiteVersion"],
            "sourceRevision": state["sourceRevision"],
            "suitePayloadDigest": state["payloadDigest"],
            "pluginIds": state["plugins"],
            "pluginDigests": state["pluginDigests"],
            "settingsStorageVersion": state["settingsStorageVersion"],
            "profile": state["profile"],
            "activeBar": state["activeBar"],
        }
        labels = ", ".join(str(item["id"]) for item in self.identities)
        expected = (
            "shibumi-suite: installed identity is unsupported\n"
            f"shibumi-suite: supported identity labels: {labels}\n"
            "shibumi-suite: diagnostic is read-only and is not authorization; "
            "no recovery or mutation was attempted\n"
            "shibumi-suite: identity diagnostic:\n"
            + json.dumps(diagnostic, indent=2, sort_keys=True)
            + "\n"
        )
        self.assertEqual(result, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), expected)
        self.assertNotIn("/home/", stderr.getvalue())
        self.assertNotIn("DO-NOT-PRINT", stderr.getvalue())
        self.assertNotIn("PRIVATE-CONTENT", stderr.getvalue())
        self.assertNotIn("reporter", stderr.getvalue())
        self.assertEqual((self.paths.state_dir / "install.json").read_bytes(), before)
        self.assertFalse((self.paths.state_dir / "transactions").exists())
        self.assertFalse(self.paths.plugin_dir.exists())

    def test_status_rejects_unsafe_state_without_diagnostic_or_leak(self) -> None:
        state_path = self.paths.state_dir / "install.json"
        external = self.root / "PRIVATE-EXTERNAL.json"
        external.write_bytes(b'{"secret":"DO-NOT-PRINT"}\n')
        oversized = b'{"secret":"DO-NOT-PRINT","padding":"' + (
            b"x" * (1024 * 1024)
        ) + b'"}\n'
        cases = {
            "malformed": b'{"secret":"DO-NOT-PRINT"',
            "duplicate": (
                b'{"schemaVersion":1,"schemaVersion":1,'
                b'"secret":"DO-NOT-PRINT"}\n'
            ),
            "oversized": oversized,
        }
        expected = (
            "shibumi-suite: status admission refused; malformed, unsafe, "
            "ambiguous, or unsupported state was not inspected further; "
            "no recovery or mutation was attempted\n"
        )
        for name, payload in cases.items():
            with self.subTest(name=name):
                state_path.write_bytes(payload)
                stdout = io.StringIO()
                stderr = io.StringIO()
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    result = command_status_with_admission(self.suite, self.paths)
                self.assertEqual(result, 1)
                self.assertEqual(stdout.getvalue(), "")
                self.assertEqual(stderr.getvalue(), expected)
                self.assertNotIn("identity diagnostic", stderr.getvalue())
                self.assertNotIn("DO-NOT-PRINT", stderr.getvalue())
                self.assertNotIn(str(self.root), stderr.getvalue())
                self.assertEqual(state_path.read_bytes(), payload)
                state_path.unlink()

        state_path.symlink_to(external)
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = command_status_with_admission(self.suite, self.paths)
        self.assertEqual(result, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), expected)
        self.assertTrue(state_path.is_symlink())
        self.assertEqual(external.read_bytes(), b'{"secret":"DO-NOT-PRINT"}\n')

    def test_status_keeps_all_one_byte_identity_deviations_nonzero(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "public-beta.13"
        )
        base = self.state_for(identity)
        revision = str(base["sourceRevision"])
        first_plugin = str(base["plugins"][0])
        cases: dict[str, dict[str, object]] = {}

        suite_version = copy.deepcopy(base)
        suite_version["suiteVersion"] = (
            str(suite_version["suiteVersion"])[:-1]
            + ("2" if str(suite_version["suiteVersion"])[-1] != "2" else "3")
        )
        cases["suite-version"] = suite_version

        source_revision = copy.deepcopy(base)
        source_revision["sourceRevision"] = (
            ("0" if revision[0] != "0" else "1") + revision[1:]
        )
        cases["source-revision"] = source_revision

        payload_digest = copy.deepcopy(base)
        digest = str(payload_digest["payloadDigest"])
        payload_digest["payloadDigest"] = (
            ("0" if digest[0] != "0" else "1") + digest[1:]
        )
        cases["suite-payload-digest"] = payload_digest

        plugin_digest = copy.deepcopy(base)
        digest = str(plugin_digest["pluginDigests"][first_plugin])
        plugin_digest["pluginDigests"][first_plugin] = (
            ("0" if digest[0] != "0" else "1") + digest[1:]
        )
        plugin_digest["payloadDigest"] = suite_payload_digest(
            plugin_digest["pluginDigests"]
        )
        cases["plugin-digest"] = plugin_digest

        plugin_order = copy.deepcopy(base)
        plugin_order["plugins"][0], plugin_order["plugins"][1] = (
            plugin_order["plugins"][1],
            plugin_order["plugins"][0],
        )
        cases["plugin-order"] = plugin_order

        plugin_id = copy.deepcopy(base)
        changed_plugin = first_plugin[:-1] + (
            "x" if first_plugin[-1] != "x" else "y"
        )
        plugin_id["plugins"][0] = changed_plugin
        plugin_id["pluginDigests"][changed_plugin] = plugin_id[
            "pluginDigests"
        ].pop(first_plugin)
        plugin_id["payloadDigest"] = suite_payload_digest(plugin_id["pluginDigests"])
        cases["plugin-id"] = plugin_id

        storage_version = copy.deepcopy(base)
        storage_version["settingsStorageVersion"] = 0
        cases["settings-storage-version"] = storage_version

        private = self.paths.state_dir / (
            "transactions/.shibumi-preparing.1700000000-1-53535353"
        )
        private.mkdir(parents=True)
        journal_sentinel = private / "sentinel"
        journal_sentinel.write_bytes(b"journal-preserved\n")
        self.paths.plugin_dir.mkdir(parents=True)
        plugin_sentinel = self.paths.plugin_dir / "foreign.plugin"
        plugin_sentinel.write_bytes(b"plugin-preserved\n")

        for name, state in cases.items():
            with self.subTest(name=name):
                self.write_state(state)
                stdout = io.StringIO()
                stderr = io.StringIO()
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    result = command_status_with_admission(self.suite, self.paths)
                self.assertEqual(result, 1)
                self.assertEqual(stdout.getvalue(), "")
                self.assertIn("no recovery or mutation was attempted", stderr.getvalue())
                self.assertEqual(
                    (self.paths.state_dir / "install.json").read_text(encoding="utf-8"),
                    json.dumps(state, sort_keys=True) + "\n",
                )
                self.assertEqual(journal_sentinel.read_bytes(), b"journal-preserved\n")
                self.assertEqual(plugin_sentinel.read_bytes(), b"plugin-preserved\n")
                (self.paths.state_dir / "install.json").unlink()

    def test_public_identity_origin_aliases_and_mixed_states_fail_closed(self) -> None:
        beta12 = next(
            item for item in self.identities if item["id"] == "public-beta.12"
        )
        beta13 = next(
            item for item in self.identities if item["id"] == "public-beta.13"
        )
        cases: dict[str, dict[str, object]] = {}

        beta12_package = self.state_for(beta12)
        beta12_package.update({
            "installOrigin": "package",
            "payloadRoot": "/usr/share/shibumi-shell",
            "sourceRevision": "package:0.1.1-beta.12",
            "packageName": "shibumi-shell",
            "packageVersion": "0.1.1-beta.12",
        })
        beta12_package.pop("sourceRoot")
        cases["beta12-package-alias"] = beta12_package

        package_as_source = self.state_for(beta13, "package:0.1.1-beta.13")
        package_as_source["installOrigin"] = "checkout"
        package_as_source["payloadRoot"] = str(REPO_ROOT)
        package_as_source["sourceRoot"] = str(REPO_ROOT)
        package_as_source.pop("packageName")
        package_as_source.pop("packageVersion")
        cases["package-revision-as-source"] = package_as_source

        source_as_package = self.state_for(
            beta13, "2760cdb8272255790d5e4613fed8a48cb63c3555"
        )
        source_as_package["installOrigin"] = "package"
        source_as_package["payloadRoot"] = "/usr/share/shibumi-shell"
        source_as_package["packageName"] = "shibumi-shell"
        source_as_package["packageVersion"] = "0.1.1-beta.13"
        source_as_package.pop("sourceRoot")
        cases["source-revision-as-package"] = source_as_package

        mixed = self.state_for(beta13)
        mixed["sourceRevision"] = beta12["sourceRevisions"][0]
        cases["beta12-revision-beta13-payload"] = mixed

        dirty = self.state_for(beta13)
        dirty["sourceRevision"] = str(dirty["sourceRevision"]) + "-dirty"
        cases["dirty-source"] = dirty

        private = self.paths.state_dir / (
            "transactions/.shibumi-cleanup.1700000000-1-54545454"
        )
        private.mkdir(parents=True)
        journal_sentinel = private / "sentinel"
        journal_sentinel.write_bytes(b"journal-preserved\n")
        self.paths.plugin_dir.mkdir(parents=True)
        plugin_sentinel = self.paths.plugin_dir / "foreign.plugin"
        plugin_sentinel.write_bytes(b"plugin-preserved\n")

        for name, state in cases.items():
            with self.subTest(name=name):
                self.write_state(state)
                state_before = (self.paths.state_dir / "install.json").read_bytes()
                with self.assertRaises(AdmissionError):
                    preflight_lifecycle_state(self.paths, self.suite)
                self.assertEqual(
                    (self.paths.state_dir / "install.json").read_bytes(), state_before
                )
                self.assertEqual(journal_sentinel.read_bytes(), b"journal-preserved\n")
                self.assertEqual(plugin_sentinel.read_bytes(), b"plugin-preserved\n")
                (self.paths.state_dir / "install.json").unlink()

    def test_dirty_caller_checkout_does_not_become_an_installed_identity(self) -> None:
        dirty_suite = copy.copy(self.suite)
        dirty_suite.revision = Mock(  # type: ignore[method-assign]
            return_value="3cb7f6d26df47b0e2d697575e4b42ba48e405c1d-dirty"
        )
        identities = supported_install_identities(dirty_suite)
        self.assertNotIn("current-release", {item["id"] for item in identities})
        beta12 = next(item for item in identities if item["id"] == "public-beta.12")
        self.assertEqual(
            classify_install_state(self.state_for(beta12), dirty_suite, identities),
            "public-beta.12",
        )

        package_suite = copy.copy(self.suite)
        package_suite.revision = Mock(  # type: ignore[method-assign]
            return_value="package:0.1.1-beta.13"
        )
        package_identities = supported_install_identities(package_suite)
        self.assertNotIn(
            "current-release", {item["id"] for item in package_identities}
        )
        public_beta13 = next(
            item for item in package_identities if item["id"] == "public-beta.13"
        )
        self.assertNotEqual(
            public_beta13["payloadDigest"],
            suite_payload_digest({
                plugin_id: spec.payload_digest()
                for plugin_id, spec in package_suite.plugins.items()
            }),
            "the fixture must exercise local payload drift at a published alias",
        )

    def test_supported_status_still_reaches_existing_status_behavior(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        state = self.state_for(identity)
        self.write_state(state)
        self.materialize_live_state(state, "1700000000-1-53535353")
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            patch("shibumi_suite.cli.command_status", return_value=7) as status,
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            result = command_status_with_admission(self.suite, self.paths)

        self.assertEqual(result, 7)
        status.assert_called_once_with(self.suite, self.paths)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "")

    def test_step6_activation_is_rejected_before_any_recovery(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "step-5-tip"
        )
        state = self.state_for(identity)
        state["activation"]["powerRegistration"] = {
            "schemaVersion": 1,
            "mode": "promoted-inert",
        }
        self.write_state(state)
        private = self.paths.state_dir / "transactions/.shibumi-preparing.1700000000-1-eeeeeeee"
        private.mkdir(parents=True)

        with self.assertRaisesRegex(AdmissionError, "Step-6 installation state"):
            preflight_lifecycle_state(self.paths, self.suite)
        self.assertTrue(private.is_dir())

        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = command_status_with_admission(self.suite, self.paths)
        self.assertEqual(result, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertNotIn("identity diagnostic", stderr.getvalue())
        self.assertNotIn("powerRegistration", stderr.getvalue())
        self.assertTrue(private.is_dir())

    def test_schema1_without_config_parent_identity_is_retained(self) -> None:
        token = "1700000000-1-10101010"
        journal = self.journal(token)
        journal["schemaVersion"] = 1
        journal.pop("configParentIdentity")
        directory = self.write_journal(token, journal)

        with self.assertRaisesRegex(
            AdmissionError, "schema-1 transaction lacks config parent identity"
        ):
            recover_transactions(self.paths, Mock(), suite=self.suite)

        self.assertTrue(directory.is_dir())
        self.assertTrue((directory / "journal.json").is_file())

    def test_all_journals_are_classified_before_recovery_or_discard(self) -> None:
        valid_token = "1700000000-1-11111111"
        unsupported_token = "1700000000-1-22222222"
        valid = self.write_journal(valid_token, self.journal(valid_token))
        unsupported_journal = self.journal(unsupported_token)
        unsupported_journal["powerCutover"] = {"schemaVersion": 1}
        unsupported = self.write_journal(unsupported_token, unsupported_journal)
        private = self.paths.state_dir / (
            "transactions/.shibumi-cleanup.1700000000-1-33333333"
        )
        private.mkdir()

        with self.assertRaisesRegex(AdmissionError, "powerCutover"):
            preflight_lifecycle_state(self.paths, self.suite)
        self.assertTrue(valid.is_dir())
        self.assertTrue(unsupported.is_dir())
        self.assertTrue(private.is_dir())

        with self.assertRaises(AdmissionError):
            recover_transactions(
                self.paths, OmarchyRuntime(), suite=self.suite
            )
        self.assertTrue(valid.is_dir())
        self.assertTrue(unsupported.is_dir())
        self.assertTrue(private.is_dir())

    def test_record_paths_actions_and_authority_are_exact(self) -> None:
        token = "1700000000-1-aaaaaaaa"
        plugin_id = "hancore.shibumi.bar"
        journal = self.journal(token)
        record = {
            "action": "replace",
            "pluginId": plugin_id,
            "target": str(self.paths.plugin_dir / plugin_id),
            "stage": str(
                self.paths.plugin_dir / f".shibumi-stage.{token}.{plugin_id}"
            ),
            "backup": str(
                self.paths.plugin_dir / f".shibumi-backup.{token}.{plugin_id}"
            ),
            "hadTarget": False,
        }
        for mutation in ("backup-suffix", "duplicate"):
            with self.subTest(mutation=mutation):
                candidate = copy.deepcopy(journal)
                candidate["records"] = [copy.deepcopy(record)]
                if mutation == "backup-suffix":
                    candidate["records"][0]["backup"] += ".foreign"
                else:
                    candidate["records"].append(copy.deepcopy(record))
                directory = self.write_journal(token, candidate)
                with self.assertRaisesRegex(
                    AdmissionError, "inconsistent path/action|duplicate"
                ):
                    inventory_transactions(self.paths, self.suite, self.identities)
                shutil.rmtree(directory.parent)

    def test_recovery_consumes_the_admitted_snapshot_not_a_replacement(self) -> None:
        token = "1700000000-1-bbbbbbbb"
        journal = self.journal(token, phase="configured")
        journal["configExisted"] = True
        journal["liveMutationStarted"] = True
        directory = self.write_journal(token, journal)
        snapshot = directory / "shell.json.before"
        snapshot.write_bytes(b'{"admitted":true}\n')
        self.paths.config_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.config_file.write_bytes(b'{"current":true}\n')
        original_inventory = transaction_module.inventory_transactions

        def replace_after_inventory(*args, **kwargs):
            result = original_inventory(*args, **kwargs)
            snapshot.write_bytes(b'{"replacement":true}\n')
            return result

        runtime = Mock()
        with patch.object(
            transaction_module,
            "inventory_transactions",
            side_effect=replace_after_inventory,
        ):
            self.assertEqual(
                recover_transactions(self.paths, runtime, suite=self.suite), 1
            )
        self.assertEqual(
            self.paths.config_file.read_bytes(), b'{"admitted":true}\n'
        )

    def test_commit_recovery_requires_exact_desired_live_inventory(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        desired = self.state_for(identity)
        token = "1700000000-1-78787878"
        journal = self.journal(token, phase="committed")
        journal["liveMutationStarted"] = True
        journal["desiredState"] = desired
        journal["archivePrevious"] = False
        directory = self.write_journal(token, journal)
        state_path = self.paths.state_dir / "install.json"

        with self.assertRaisesRegex(AdmissionError, "missing|incomplete"):
            recover_transactions(self.paths, Mock(), suite=self.suite)
        self.assertFalse(state_path.exists())
        self.assertTrue(directory.is_dir())

    def test_commit_recovery_rejects_desired_target_byte_drift(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        desired = self.state_for(identity)
        self.materialize_live_state(
            desired, "1700000000-1-79797979"
        )
        plugin_id = str(desired["plugins"][0])
        payload = self.paths.plugin_dir / plugin_id / "manifest.json"
        payload.write_bytes(payload.read_bytes() + b" ")
        token = "1700000000-1-80808080"
        journal = self.journal(token, phase="committed")
        journal["liveMutationStarted"] = True
        journal["desiredState"] = desired
        journal["archivePrevious"] = False
        directory = self.write_journal(token, journal)
        state_path = self.paths.state_dir / "install.json"

        with self.assertRaisesRegex(AdmissionError, "marker or payload"):
            recover_transactions(self.paths, Mock(), suite=self.suite)
        self.assertFalse(state_path.exists())
        self.assertTrue(payload.is_file())
        self.assertTrue(directory.is_dir())

    def test_multiple_public_journals_are_rejected_before_any_recovery(self) -> None:
        directories = []
        for suffix in ("11111111", "22222222"):
            token = f"1700000000-1-{suffix}"
            directories.append(self.write_journal(token, self.journal(token)))
        with self.assertRaisesRegex(AdmissionError, "multiple authoritative"):
            recover_transactions(self.paths, Mock(), suite=self.suite)
        self.assertTrue(all(directory.is_dir() for directory in directories))

    def test_admitted_exposure_journal_recovers_before_live_validation(self) -> None:
        token = "1700000000-1-12121212"
        plugin_id = "hancore.shibumi.bar"
        target = self.paths.plugin_dir / plugin_id
        shutil.copytree(self.suite.plugins[plugin_id].source, target)
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        marker = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": identity["suiteVersion"],
            "pluginId": plugin_id,
            "sourceRevision": identity["sourceRevisions"][0],
            "payloadDigest": identity["pluginDigests"][plugin_id],
            "suitePayloadDigest": identity["payloadDigest"],
            "transaction": token,
        }
        (target / ".shibumi-managed.json").write_text(
            json.dumps(marker) + "\n", encoding="utf-8"
        )
        journal = self.journal(token, phase="exposed")
        journal["liveMutationStarted"] = True
        journal["records"] = [{
            "action": "replace",
            "pluginId": plugin_id,
            "target": str(target),
            "stage": str(
                self.paths.plugin_dir / f".shibumi-stage.{token}.{plugin_id}"
            ),
            "backup": str(
                self.paths.plugin_dir / f".shibumi-backup.{token}.{plugin_id}"
            ),
            "hadTarget": False,
        }]
        self.write_journal(token, journal)

        self.assertEqual(
            preflight_lifecycle_state(
                self.paths, self.suite, allow_pending_recovery=True
            ),
            "fresh",
        )
        self.assertTrue(target.is_dir())
        self.assertEqual(
            recover_transactions(self.paths, Mock(), suite=self.suite), 1
        )
        self.assertFalse(target.exists())
        self.assertEqual(
            preflight_lifecycle_state(self.paths, self.suite), "fresh"
        )

    def test_missing_backup_for_exposed_existing_target_fails_before_stop(self) -> None:
        token = "1700000000-1-34343434"
        plugin_id = "hancore.shibumi.bar"
        target = self.paths.plugin_dir / plugin_id
        shutil.copytree(self.suite.plugins[plugin_id].source, target)
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        marker = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": identity["suiteVersion"],
            "pluginId": plugin_id,
            "sourceRevision": identity["sourceRevisions"][0],
            "payloadDigest": identity["pluginDigests"][plugin_id],
            "suitePayloadDigest": identity["payloadDigest"],
            "transaction": token,
        }
        (target / ".shibumi-managed.json").write_text(
            json.dumps(marker) + "\n", encoding="utf-8"
        )
        journal = self.journal(token, phase="exposed")
        journal["shellStopped"] = True
        journal["restoreRequiresDrain"] = True
        journal["liveMutationStarted"] = True
        journal["records"] = [{
            "action": "replace",
            "pluginId": plugin_id,
            "target": str(target),
            "stage": str(
                self.paths.plugin_dir / f".shibumi-stage.{token}.{plugin_id}"
            ),
            "backup": str(
                self.paths.plugin_dir / f".shibumi-backup.{token}.{plugin_id}"
            ),
            "hadTarget": True,
        }]
        directory = self.write_journal(token, journal)
        runtime = Mock()

        with self.assertRaisesRegex(AdmissionError, "backup is missing"):
            recover_transactions(self.paths, runtime, suite=self.suite)
        runtime.stop_shell.assert_not_called()
        self.assertTrue(target.is_dir())
        self.assertTrue(directory.is_dir())
        self.assertFalse(self.paths.config_file.exists())

        marker_path = target / ".shibumi-managed.json"
        marker_payload = marker_path.read_bytes()
        marker_path.unlink()
        with self.assertRaisesRegex(AdmissionError, "plugin marker"):
            recover_transactions(self.paths, runtime, suite=self.suite)
        runtime.stop_shell.assert_not_called()
        self.assertTrue(target.is_dir())
        self.assertTrue(directory.is_dir())

        marker_path.write_bytes(marker_payload)
        backup = Path(journal["records"][0]["backup"])
        shutil.copytree(self.suite.plugins[plugin_id].source, backup)
        with self.assertRaisesRegex(AdmissionError, "plugin marker"):
            recover_transactions(self.paths, runtime, suite=self.suite)
        runtime.stop_shell.assert_not_called()
        self.assertTrue(target.is_dir())
        self.assertTrue(backup.is_dir())
        self.assertTrue(directory.is_dir())
        self.assertFalse(self.paths.config_file.exists())

    def test_generated_before_digest_rejects_backup_byte_drift(self) -> None:
        plugin_id = "hancore.shibumi.bar"
        target = self.paths.plugin_dir / plugin_id
        shutil.copytree(self.suite.plugins[plugin_id].source, target)
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        marker = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": identity["suiteVersion"],
            "pluginId": plugin_id,
            "sourceRevision": identity["sourceRevisions"][0],
            "payloadDigest": identity["pluginDigests"][plugin_id],
            "suitePayloadDigest": identity["payloadDigest"],
            "transaction": "1700000000-1-56565656",
        }
        (target / ".shibumi-managed.json").write_text(
            json.dumps(marker) + "\n", encoding="utf-8"
        )
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        record = next(
            item for item in transaction.records if item["pluginId"] == plugin_id
        )
        self.assertEqual(
            record["beforePayloadDigest"], identity["pluginDigests"][plugin_id]
        )
        transaction.expose()
        backup = Path(record["backup"])
        payload = backup / "manifest.json"
        payload.write_bytes(payload.read_bytes() + b" ")
        runtime = Mock()

        with self.assertRaisesRegex(AdmissionError, "artifact identity"):
            recover_transactions(self.paths, runtime, suite=self.suite)
        runtime.stop_shell.assert_not_called()
        self.assertTrue(target.is_dir())
        self.assertTrue(backup.is_dir())
        self.assertTrue(transaction.transaction_dir.is_dir())

    def test_commit_recovery_rejects_mutated_generated_backup(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        desired = self.state_for(identity)
        self.materialize_live_state(desired, "1700000000-1-89898989")
        plugin_id = "hancore.shibumi.bar"
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        transaction.expose()
        transaction._write_journal(
            "committed", desired_state=desired, archive_previous=True
        )
        record = next(
            item for item in transaction.records if item["pluginId"] == plugin_id
        )
        backup = Path(record["backup"])
        payload = backup / "manifest.json"
        payload.write_bytes(payload.read_bytes() + b" ")
        state_path = self.paths.state_dir / "install.json"
        runtime = Mock()

        with self.assertRaisesRegex(AdmissionError, "artifact identity"):
            recover_transactions(self.paths, runtime, suite=self.suite)
        runtime.stop_shell.assert_not_called()
        self.assertFalse(state_path.exists())
        self.assertTrue(backup.is_dir())
        self.assertTrue(transaction.transaction_dir.is_dir())

    def test_committed_archive_requires_source_or_archived_backup(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        desired = self.state_for(identity)
        self.materialize_live_state(desired, "1700000000-1-91919191")
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        transaction.expose()
        transaction._write_journal(
            "committed", desired_state=desired, archive_previous=True
        )
        record = transaction.records[0]
        backup = Path(record["backup"])
        shutil.rmtree(backup)
        state_path = self.paths.state_dir / "install.json"

        with self.assertRaisesRegex(AdmissionError, "topology is incomplete"):
            recover_transactions(self.paths, Mock(), suite=self.suite)
        self.assertFalse(state_path.exists())
        self.assertTrue(transaction.transaction_dir.is_dir())

    def test_committed_archive_only_backup_is_recoverable(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        desired = self.state_for(identity)
        self.materialize_live_state(desired, "1700000000-1-92929292")
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        transaction.expose()
        transaction._write_journal(
            "committed", desired_state=desired, archive_previous=True
        )
        record = transaction.records[0]
        backup = Path(record["backup"])
        archived = (
            self.paths.state_dir
            / "backups"
            / transaction.token
            / str(record["pluginId"])
        )
        archived.parent.mkdir(parents=True)
        backup.rename(archived)

        self.assertEqual(
            recover_transactions(self.paths, Mock(), suite=self.suite), 1
        )
        self.assertTrue(archived.is_dir())
        self.assertFalse(transaction.transaction_dir.exists())
        self.assertEqual(
            json.loads((self.paths.state_dir / "install.json").read_text()),
            desired,
        )

    def test_committing_partial_archive_resumes_from_mixed_backups(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        desired = self.state_for(identity)
        self.materialize_live_state(desired, "1700000000-1-93939393")
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        transaction.expose()
        transaction._write_journal(
            "committing", desired_state=desired, archive_previous=True
        )
        first = transaction.records[0]
        archived = (
            self.paths.state_dir / "backups" / transaction.token / first["pluginId"]
        )
        archived.parent.mkdir(parents=True)
        Path(first["backup"]).rename(archived)

        self.assertEqual(
            recover_transactions(self.paths, Mock(), suite=self.suite), 1
        )
        archive = self.paths.state_dir / "backups" / transaction.token
        self.assertTrue(all((archive / record["pluginId"]).is_dir()
                            for record in transaction.records))
        self.assertEqual(
            json.loads((self.paths.state_dir / "install.json").read_text()), desired
        )
        self.assertFalse(transaction.transaction_dir.exists())

    def test_backup_replacement_at_quarantine_fails_before_mutation(self) -> None:
        plugin_id = "hancore.shibumi.bar"
        target = self.paths.plugin_dir / plugin_id
        shutil.copytree(self.suite.plugins[plugin_id].source, target)
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        marker = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": identity["suiteVersion"],
            "pluginId": plugin_id,
            "sourceRevision": identity["sourceRevisions"][0],
            "payloadDigest": identity["pluginDigests"][plugin_id],
            "suitePayloadDigest": identity["payloadDigest"],
            "transaction": "1700000000-1-90909090",
        }
        (target / ".shibumi-managed.json").write_text(
            json.dumps(marker) + "\n", encoding="utf-8"
        )
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        transaction.expose()
        record = next(
            item for item in transaction.records if item["pluginId"] == plugin_id
        )
        backup = Path(record["backup"])
        target_before = (target / "manifest.json").read_bytes()
        original_replace = transaction_module.os.replace

        def replace_at_quarantine(source: object, destination: object) -> None:
            if Path(source) == backup and ".shibumi-recovery." in Path(destination).name:
                payload = backup / "manifest.json"
                payload.write_bytes(payload.read_bytes() + b" ")
            original_replace(source, destination)

        runtime = Mock()
        with (
            patch.object(
                transaction_module.os,
                "replace",
                side_effect=replace_at_quarantine,
            ),
            self.assertRaisesRegex(AdmissionError, "changed after admission"),
        ):
            recover_transactions(self.paths, runtime, suite=self.suite)
        runtime.stop_shell.assert_not_called()
        self.assertEqual(
            (target / "manifest.json").read_bytes(), target_before
        )
        self.assertTrue(backup.is_dir())
        self.assertTrue(transaction.transaction_dir.is_dir())

    def test_quarantine_crash_state_resumes_recovery(self) -> None:
        plugin_id = "hancore.shibumi.bar"
        target = self.paths.plugin_dir / plugin_id
        shutil.copytree(self.suite.plugins[plugin_id].source, target)
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        marker = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": identity["suiteVersion"],
            "pluginId": plugin_id,
            "sourceRevision": identity["sourceRevisions"][0],
            "payloadDigest": identity["pluginDigests"][plugin_id],
            "suitePayloadDigest": identity["payloadDigest"],
            "transaction": "1700000000-1-93939393",
        }
        (target / ".shibumi-managed.json").write_text(
            json.dumps(marker) + "\n", encoding="utf-8"
        )
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        transaction.expose()
        record = next(
            item for item in transaction.records if item["pluginId"] == plugin_id
        )
        backup = Path(record["backup"])
        quarantine = self.paths.plugin_dir / (
            f".shibumi-recovery.{transaction.token}.{plugin_id}"
        )
        discard = self.paths.plugin_dir / (
            f".shibumi-discard.{transaction.token}.{plugin_id}"
        )
        backup.rename(quarantine)
        target.rename(discard)

        self.assertEqual(
            recover_transactions(self.paths, Mock(), suite=self.suite), 1
        )
        self.assertFalse(quarantine.exists())
        self.assertFalse(discard.exists())
        self.assertFalse(transaction.transaction_dir.exists())
        self.assertEqual(
            json.loads((target / ".shibumi-managed.json").read_text()), marker
        )

    def test_backup_replacement_at_restore_is_reversed(self) -> None:
        plugin_id = "hancore.shibumi.bar"
        target = self.paths.plugin_dir / plugin_id
        shutil.copytree(self.suite.plugins[plugin_id].source, target)
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        marker = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": identity["suiteVersion"],
            "pluginId": plugin_id,
            "sourceRevision": identity["sourceRevisions"][0],
            "payloadDigest": identity["pluginDigests"][plugin_id],
            "suitePayloadDigest": identity["payloadDigest"],
            "transaction": "1700000000-1-94949494",
        }
        (target / ".shibumi-managed.json").write_text(
            json.dumps(marker) + "\n", encoding="utf-8"
        )
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        transaction.expose()
        record = next(
            item for item in transaction.records if item["pluginId"] == plugin_id
        )
        backup = Path(record["backup"])
        target_before = (target / "manifest.json").read_bytes()
        original_replace = transaction_module.os.replace
        raced = False

        def replace_at_restore(source: object, destination: object) -> None:
            nonlocal raced
            source_path = Path(source)
            if (
                not raced
                and ".shibumi-recovery." in source_path.name
                and Path(destination) == target
            ):
                payload = source_path / "manifest.json"
                payload.write_bytes(payload.read_bytes() + b" ")
                raced = True
            original_replace(source, destination)

        runtime = Mock()
        with (
            patch.object(
                transaction_module.os,
                "replace",
                side_effect=replace_at_restore,
            ),
            self.assertRaisesRegex(AdmissionError, "changed after admission"),
        ):
            recover_transactions(self.paths, runtime, suite=self.suite)
        runtime.stop_shell.assert_not_called()
        self.assertTrue(raced)
        self.assertEqual(
            (target / "manifest.json").read_bytes(), target_before
        )
        self.assertTrue(backup.is_dir())
        self.assertTrue(transaction.transaction_dir.is_dir())

    def test_archive_parent_symlink_after_quarantine_writes_nothing_external(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        desired = self.state_for(identity)
        self.materialize_live_state(desired, "1700000000-1-95959595")
        transaction = PluginTransaction(self.paths, Mock())
        transaction.stage(
            tuple(self.suite.plugins.values()),
            revision=str(identity["sourceRevisions"][0]),
            suite_version=str(identity["suiteVersion"]),
        )
        transaction.expose()
        transaction._write_journal(
            "committed", desired_state=desired, archive_previous=True
        )
        record = transaction.records[0]
        backup = Path(record["backup"])
        state_path = self.paths.state_dir / "install.json"
        external = self.root / "external-archive"
        external.mkdir()
        sentinel = external / "sentinel"
        sentinel.write_text("preserve\n", encoding="utf-8")
        real_quarantine = transaction_module._quarantine_recovery_backups

        def replace_archive_root(*args: object, **kwargs: object) -> object:
            admitted = real_quarantine(*args, **kwargs)
            (self.paths.state_dir / "backups").symlink_to(
                external, target_is_directory=True
            )
            return admitted

        with (
            patch.object(
                transaction_module,
                "_quarantine_recovery_backups",
                side_effect=replace_archive_root,
            ),
            self.assertRaises(TransactionError),
        ):
            recover_transactions(self.paths, Mock(), suite=self.suite)
        self.assertFalse(state_path.exists())
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve\n")
        self.assertEqual(sorted(item.name for item in external.iterdir()), ["sentinel"])
        self.assertTrue(backup.is_dir())
        self.assertTrue(transaction.transaction_dir.is_dir())

    def test_unknown_phase_and_malformed_private_journal_fail_closed(self) -> None:
        token = "1700000000-1-cccccccc"
        unknown = self.journal(token, phase="power-configuring")
        self.write_journal(token, unknown)
        malformed = self.paths.state_dir / (
            "transactions/.shibumi-preparing.1700000000-1-dddddddd"
        )
        malformed.mkdir()
        (malformed / "journal.json").write_text("{\"phase\":", encoding="utf-8")

        with self.assertRaisesRegex(AdmissionError, "transaction inventory"):
            inventory_transactions(self.paths, self.suite, self.identities)
        self.assertTrue(unknown)
        self.assertTrue(malformed.is_dir())

    def test_commit_journal_requires_an_admitted_desired_state(self) -> None:
        token = "1700000000-1-eeeeeeee"
        journal = self.journal(token, phase="committed")
        journal["archivePrevious"] = True
        identity = next(
            item for item in self.identities if item["id"] == "step-5-tip"
        )
        desired = self.state_for(identity)
        desired["sourceRevision"] = "0788cce400999e40737c9c61c96b3909df0eca88"
        journal["desiredState"] = desired
        directory = self.write_journal(token, journal)

        with self.assertRaisesRegex(AdmissionError, "desired/live state"):
            inventory_transactions(self.paths, self.suite, self.identities)
        self.assertTrue(directory.is_dir())

    def test_exact_live_payload_and_marker_schema_are_required(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "current-release"
        )
        state = self.state_for(identity)
        self.write_state(state)
        transaction = "1700000000-1-ffffffff"
        for plugin_id in state["plugins"]:
            target = self.paths.plugin_dir / plugin_id
            shutil.copytree(self.suite.plugins[plugin_id].source, target)
            marker = {
                "schemaVersion": 1,
                "suiteId": "hancore.shibumi",
                "suiteVersion": state["suiteVersion"],
                "pluginId": plugin_id,
                "sourceRevision": state["sourceRevision"],
                "payloadDigest": state["pluginDigests"][plugin_id],
                "suitePayloadDigest": state["payloadDigest"],
                "transaction": transaction,
            }
            (target / ".shibumi-managed.json").write_text(
                json.dumps(marker) + "\n", encoding="utf-8"
            )
        self.assertEqual(
            preflight_lifecycle_state(self.paths, self.suite), "current-release"
        )

        first = str(state["plugins"][0])
        marker_path = self.paths.plugin_dir / first / ".shibumi-managed.json"
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
        marker["futureAuthority"] = True
        marker_path.write_text(json.dumps(marker) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(AdmissionError, "marker or payload"):
            preflight_lifecycle_state(self.paths, self.suite)
        marker.pop("futureAuthority")
        marker_path.write_text(json.dumps(marker) + "\n", encoding="utf-8")

        payload = self.paths.plugin_dir / first / "manifest.json"
        payload.write_text(
            payload.read_text(encoding="utf-8") + " ", encoding="utf-8"
        )
        with self.assertRaisesRegex(AdmissionError, "marker or payload"):
            preflight_lifecycle_state(self.paths, self.suite)
        self.assertEqual(
            preflight_lifecycle_state(
                self.paths, self.suite, allow_payload_repair=True
            ),
            "current-release",
        )

        shutil.copy2(self.suite.plugins[first].source / "manifest.json", payload)
        missing = str(state["plugins"][1])
        shutil.rmtree(self.paths.plugin_dir / missing)
        self.assertEqual(
            preflight_lifecycle_state(
                self.paths, self.suite, allow_payload_repair=True
            ),
            "current-release",
        )
        with self.assertRaisesRegex(AdmissionError, "incomplete"):
            preflight_lifecycle_state(self.paths, self.suite)

    def test_live_marker_must_match_every_admitted_state_identity(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "step-5-tip"
        )
        state = self.state_for(identity)
        self.write_state(state)
        plugin_id = str(state["plugins"][0])
        target = self.paths.plugin_dir / plugin_id
        target.mkdir(parents=True)
        marker = {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "suiteVersion": state["suiteVersion"],
            "pluginId": plugin_id,
            "sourceRevision": "08ade6e000000000000000000000000000000000",
            "payloadDigest": state["pluginDigests"][plugin_id],
            "suitePayloadDigest": state["payloadDigest"],
            "transaction": "foreign",
        }
        (target / ".shibumi-managed.json").write_text(
            json.dumps(marker) + "\n", encoding="utf-8"
        )

        with self.assertRaisesRegex(AdmissionError, "live plugin marker"):
            preflight_lifecycle_state(self.paths, self.suite)

    def test_nonfinite_numbers_and_boolean_schema_versions_are_rejected(self) -> None:
        identity = next(
            item for item in self.identities if item["id"] == "step-5-tip"
        )
        for location in ("state", "menu"):
            with self.subTest(location=location):
                state = self.state_for(identity)
                if location == "state":
                    state["schemaVersion"] = True
                else:
                    state["menuExtension"]["schemaVersion"] = True
                with self.assertRaisesRegex(AdmissionError, "unknown|malformed"):
                    classify_install_state(state, self.suite, self.identities)

        state = self.state_for(identity)
        state["previousBar"] = {"nested": {"value": "OVERFLOW"}}
        payload = json.dumps(state).replace('"OVERFLOW"', "1e309")
        (self.paths.state_dir / "install.json").write_text(
            payload + "\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(AdmissionError, "non-finite JSON number"):
            preflight_lifecycle_state(self.paths, self.suite)

    def test_duplicate_json_fields_and_symlinks_are_rejected(self) -> None:
        state_path = self.paths.state_dir / "install.json"
        state_path.write_text(
            '{"schemaVersion":1,"schemaVersion":1}\n', encoding="utf-8"
        )
        with self.assertRaisesRegex(AdmissionError, "duplicate JSON field"):
            preflight_lifecycle_state(self.paths, self.suite)
        state_path.unlink()
        external = self.root / "external.json"
        external.write_text("{}\n", encoding="utf-8")
        state_path.symlink_to(external)
        with self.assertRaisesRegex(AdmissionError, "cannot read"):
            preflight_lifecycle_state(self.paths, self.suite)


if __name__ == "__main__":
    unittest.main()
