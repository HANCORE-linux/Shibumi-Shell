#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from shibumi_suite.admission import (  # noqa: E402
    AdmissionError,
    classify_install_state,
    inventory_transactions,
    preflight_lifecycle_state,
    supported_install_identities,
)
from shibumi_suite.model import Suite  # noqa: E402
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
        self.identities = supported_install_identities(self.suite)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def state_for(self, identity: dict[str, object]) -> dict[str, object]:
        revision = str(identity["sourceRevisions"][0])
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
        if package:
            state["packageName"] = "shibumi-shell"
            state["packageVersion"] = revision.removeprefix("package:")
        else:
            state["sourceRoot"] = str(REPO_ROOT)
        return state

    def write_state(self, state: dict[str, object]) -> None:
        (self.paths.state_dir / "install.json").write_text(
            json.dumps(state, sort_keys=True) + "\n", encoding="utf-8"
        )

    def journal(self, token: str, phase: str = "prepared") -> dict[str, object]:
        return {
            "schemaVersion": 1,
            "suiteId": "hancore.shibumi",
            "token": token,
            "phase": phase,
            "pluginRoot": str(self.paths.plugin_dir.resolve(strict=False)),
            "configPath": str(self.paths.config_file.resolve(strict=False)),
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

    def write_journal(
        self, token: str, journal: dict[str, object], *, prefix: str = ""
    ) -> Path:
        directory = self.paths.state_dir / "transactions" / f"{prefix}{token}"
        directory.mkdir(parents=True, exist_ok=False)
        (directory / "journal.json").write_text(
            json.dumps(journal, sort_keys=True) + "\n", encoding="utf-8"
        )
        return directory

    def test_exact_public_beta_and_step5_states_are_admitted(self) -> None:
        for identity_id in ("public-beta.11", "step-5-tip"):
            with self.subTest(identity=identity_id):
                identity = next(
                    item for item in self.identities if item["id"] == identity_id
                )
                state = self.state_for(identity)
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
