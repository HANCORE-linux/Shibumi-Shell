from __future__ import annotations

import fcntl
import json
import os
import shutil
import time
import uuid
from pathlib import Path
from typing import Any, Iterable

from . import MANAGED_MARKER, STATE_SCHEMA_VERSION, SUITE_ID
from .config import atomic_write
from .model import (
    ContractError,
    PluginSpec,
    suite_payload_digest,
)
from .runtime import OmarchyRuntime, RuntimeFailure, RuntimePaths


class TransactionError(RuntimeError):
    pass


LEGACY_SUITE_ID = "hancore.qsrise"
LEGACY_MANAGED_MARKER = ".qsrise-managed.json"


class SuiteLock:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.handle: Any = None

    def __enter__(self) -> "SuiteLock":
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = self.path.open("a+")
        try:
            fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            self.handle.close()
            raise TransactionError("another Shibumi lifecycle operation is running") from error
        return self

    def __exit__(self, *_: object) -> None:
        if self.handle:
            fcntl.flock(self.handle.fileno(), fcntl.LOCK_UN)
            self.handle.close()


def _remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.is_dir():
        shutil.rmtree(path)


def _marker(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads((path / MANAGED_MARKER).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _legacy_marker(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(
            (path / LEGACY_MANAGED_MARKER).read_text(encoding="utf-8")
        )
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def is_managed_target(path: Path, plugin_id: str) -> bool:
    if path.is_symlink() or not path.is_dir():
        return False
    value = _marker(path)
    return bool(
        value
        and value.get("schemaVersion") == STATE_SCHEMA_VERSION
        and value.get("suiteId") == SUITE_ID
        and value.get("pluginId") == plugin_id
    )


def is_adoptable_markerless_target(
    path: Path, plugin_id: str, expected_plugin_ids: set[str]
) -> bool:
    if (
        plugin_id not in expected_plugin_ids
        or path.is_symlink()
        or not path.is_dir()
        or (path / MANAGED_MARKER).exists()
    ):
        return False
    try:
        manifest = json.loads((path / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    metadata = manifest.get("x-shibumi")
    return bool(
        isinstance(manifest, dict)
        and manifest.get("schemaVersion") == 1
        and manifest.get("id") == plugin_id
        and isinstance(metadata, dict)
        and metadata.get("suiteId") == SUITE_ID
    )


def is_legacy_managed_target(path: Path, plugin_id: str) -> bool:
    if path.is_symlink() or not path.is_dir():
        return False
    value = _legacy_marker(path)
    return bool(
        value
        and value.get("schemaVersion") == STATE_SCHEMA_VERSION
        and value.get("suiteId") == LEGACY_SUITE_ID
        and value.get("pluginId") == plugin_id
    )


def preflight_replacements(
    plugin_dir: Path,
    specs: Iterable[PluginSpec],
    adoptable_plugin_ids: set[str] | None = None,
) -> None:
    adoptable = adoptable_plugin_ids or set()
    for spec in specs:
        target = plugin_dir / spec.id
        if (
            (target.exists() or target.is_symlink())
            and not is_managed_target(target, spec.id)
            and not is_adoptable_markerless_target(
                target, spec.id, adoptable
            )
        ):
            raise TransactionError(
                f"refusing to replace non-Shibumi plugin directory: {target}"
            )


def preflight_removals(plugin_dir: Path, specs: Iterable[PluginSpec]) -> None:
    for spec in specs:
        target = plugin_dir / spec.id
        if (target.exists() or target.is_symlink()) and not is_managed_target(
            target, spec.id
        ):
            raise TransactionError(
                f"refusing to remove non-Shibumi plugin directory: {target}"
            )


def preflight_legacy_removals(plugin_dir: Path, plugin_ids: Iterable[str]) -> None:
    for plugin_id in plugin_ids:
        target = plugin_dir / plugin_id
        if not target.is_dir() or not is_legacy_managed_target(target, plugin_id):
            raise TransactionError(
                f"refusing to migrate unmanaged legacy plugin directory: {target}"
            )


class PluginTransaction:
    def __init__(self, paths: RuntimePaths, runtime: OmarchyRuntime) -> None:
        self.paths = paths
        self.runtime = runtime
        self.token = f"{int(time.time())}-{os.getpid()}-{uuid.uuid4().hex[:8]}"
        self.transaction_dir = paths.state_dir / "transactions" / self.token
        self.journal_file = self.transaction_dir / "journal.json"
        self.snapshot_file = self.transaction_dir / "shell.json.before"
        self.records: list[dict[str, Any]] = []
        self.finished = False
        self.config_existed = paths.config_file.is_file()

        self.transaction_dir.mkdir(parents=True, exist_ok=False)
        if self.config_existed:
            self.snapshot_file.write_bytes(paths.config_file.read_bytes())
        self._write_journal("prepared")

    def _journal(self, phase: str, desired_state: Any = "unchanged") -> dict[str, Any]:
        value: dict[str, Any] = {
            "schemaVersion": 1,
            "suiteId": SUITE_ID,
            "token": self.token,
            "phase": phase,
            "pluginRoot": str(self.paths.plugin_dir.resolve(strict=False)),
            "configPath": str(self.paths.config_file.resolve(strict=False)),
            "configExisted": self.config_existed,
            "records": self.records,
        }
        if desired_state != "unchanged":
            value["desiredState"] = desired_state
        return value

    def _write_journal(self, phase: str, desired_state: Any = "unchanged") -> None:
        payload = json.dumps(
            self._journal(phase, desired_state), indent=2, sort_keys=True
        ).encode("utf-8") + b"\n"
        atomic_write(self.journal_file, payload)

    def preflight_targets(
        self,
        specs: Iterable[PluginSpec],
        adoptable_plugin_ids: set[str] | None = None,
    ) -> None:
        preflight_replacements(
            self.paths.plugin_dir, specs, adoptable_plugin_ids
        )

    def stage(
        self,
        specs: Iterable[PluginSpec],
        *,
        revision: str,
        suite_version: str,
    ) -> tuple[str, dict[str, str]]:
        self.paths.plugin_dir.mkdir(parents=True, exist_ok=True)
        selected = list(specs)
        plugin_digests: dict[str, str] = {}
        records_by_id: dict[str, dict[str, Any]] = {}
        for spec in selected:
            stage = self.paths.plugin_dir / f".shibumi-stage.{self.token}.{spec.id}"
            backup = self.paths.plugin_dir / f".shibumi-backup.{self.token}.{spec.id}"
            target = self.paths.plugin_dir / spec.id
            if stage.exists() or backup.exists():
                raise TransactionError(f"transaction path already exists for {spec.id}")
            record = {
                "action": "replace",
                "pluginId": spec.id,
                "target": str(target),
                "stage": str(stage),
                "backup": str(backup),
                "hadTarget": target.exists() or target.is_symlink(),
            }
            self.records.append(record)
            records_by_id[spec.id] = record
            self._write_journal("staging")
            try:
                source_digest = spec.payload_digest()
                shutil.copytree(spec.source, stage, symlinks=True)
                stage_digest = spec.payload_digest(stage)
            except (ContractError, OSError, shutil.Error) as error:
                raise TransactionError(
                    f"cannot stage plugin payload {spec.id}: {error}"
                ) from error
            if stage_digest != source_digest:
                raise TransactionError(
                    f"plugin payload changed while staging: {spec.id}"
                )
            plugin_digests[spec.id] = stage_digest

        payload_digest = suite_payload_digest(plugin_digests)
        for spec in selected:
            record = records_by_id[spec.id]
            stage = Path(record["stage"])
            marker = {
                "schemaVersion": STATE_SCHEMA_VERSION,
                "suiteId": SUITE_ID,
                "suiteVersion": suite_version,
                "pluginId": spec.id,
                "sourceRevision": revision,
                "payloadDigest": plugin_digests[spec.id],
                "suitePayloadDigest": payload_digest,
                "transaction": self.token,
            }
            atomic_write(
                stage / MANAGED_MARKER,
                (json.dumps(marker, indent=2, sort_keys=True) + "\n").encode("utf-8"),
            )
            self.runtime.validate_plugin(stage)
            try:
                verified_digest = spec.payload_digest(stage)
            except ContractError as error:
                raise TransactionError(
                    f"invalid staged plugin payload {spec.id}: {error}"
                ) from error
            if verified_digest != plugin_digests[spec.id]:
                raise TransactionError(
                    f"validator changed staged plugin payload: {spec.id}"
                )
        self._write_journal("staged")
        return payload_digest, plugin_digests

    def expose(self) -> None:
        for record in self.records:
            if record["action"] != "replace":
                continue
            target = Path(record["target"])
            stage = Path(record["stage"])
            backup = Path(record["backup"])
            if record["hadTarget"]:
                os.replace(target, backup)
            os.replace(stage, target)
            self._write_journal("exposed")

    def stage_removal(self, specs: Iterable[PluginSpec]) -> None:
        self.paths.plugin_dir.mkdir(parents=True, exist_ok=True)
        for spec in specs:
            target = self.paths.plugin_dir / spec.id
            if not (target.exists() or target.is_symlink()):
                continue
            if not is_managed_target(target, spec.id):
                raise TransactionError(
                    f"refusing to remove non-Shibumi plugin directory: {target}"
                )
            backup = self.paths.plugin_dir / f".shibumi-backup.{self.token}.{spec.id}"
            record = {
                "action": "remove",
                "pluginId": spec.id,
                "target": str(target),
                "stage": "",
                "backup": str(backup),
                "hadTarget": True,
            }
            self.records.append(record)
            self._write_journal("prepared-removal")
            os.replace(target, backup)
            self._write_journal("removed")

    def stage_legacy_removal(self, plugin_ids: Iterable[str]) -> None:
        self.paths.plugin_dir.mkdir(parents=True, exist_ok=True)
        for plugin_id in plugin_ids:
            target = self.paths.plugin_dir / plugin_id
            if not target.is_dir() or not is_legacy_managed_target(target, plugin_id):
                raise TransactionError(
                    f"refusing to migrate unmanaged legacy plugin directory: {target}"
                )
            backup = self.paths.plugin_dir / (
                f".shibumi-backup.{self.token}.{plugin_id}"
            )
            record = {
                "action": "remove-legacy",
                "pluginId": plugin_id,
                "target": str(target),
                "stage": "",
                "backup": str(backup),
                "hadTarget": True,
            }
            self.records.append(record)
            self._write_journal("prepared-legacy-removal")
            os.replace(target, backup)
            self._write_journal("legacy-removed")

    def write_config(self, payload: bytes) -> None:
        atomic_write(self.paths.config_file, payload)
        self._write_journal("configured")

    def rollback(self) -> None:
        if self.finished:
            return
        try:
            _restore_records(self.paths.plugin_dir, self.token, self.records)
            if self.config_existed:
                atomic_write(self.paths.config_file, self.snapshot_file.read_bytes())
            else:
                self.paths.config_file.unlink(missing_ok=True)
            self.runtime.reconcile_best_effort()
        finally:
            self._cleanup_transaction()
            self.finished = True

    def finish(
        self,
        desired_state: dict[str, Any] | None,
        *,
        archive_previous: bool,
    ) -> None:
        self._write_journal("committing", desired_state)
        state_file = self.paths.state_dir / "install.json"
        if desired_state is None:
            state_file.unlink(missing_ok=True)
        else:
            atomic_write(
                state_file,
                (json.dumps(desired_state, indent=2, sort_keys=True) + "\n").encode(
                    "utf-8"
                ),
            )
        self._write_journal("committed", desired_state)

        if archive_previous:
            self._archive_backups()
        else:
            for record in self.records:
                backup = Path(record["backup"])
                if backup.exists() or backup.is_symlink():
                    _remove_path(backup)
        self._cleanup_transaction()
        self.finished = True

    def _archive_backups(self) -> None:
        backups = [
            (str(record["pluginId"]), Path(record["backup"]))
            for record in self.records
            if Path(record["backup"]).exists() or Path(record["backup"]).is_symlink()
        ]
        if backups:
            destination = self.paths.state_dir / "backups" / self.token
            destination.mkdir(parents=True, exist_ok=False)
            for plugin_id, backup in backups:
                shutil.move(str(backup), destination / plugin_id)
        backup_root = self.paths.state_dir / "backups"
        if backup_root.is_dir():
            retained = sorted(
                (path for path in backup_root.iterdir() if path.is_dir()),
                key=lambda path: path.stat().st_mtime,
                reverse=True,
            )
            for stale in retained[2:]:
                _remove_path(stale)

    def _cleanup_transaction(self) -> None:
        for record in self.records:
            stage = Path(record["stage"]) if record.get("stage") else None
            if stage and (stage.exists() or stage.is_symlink()):
                _remove_path(stage)
        if self.transaction_dir.exists():
            shutil.rmtree(self.transaction_dir)
        transactions = self.paths.state_dir / "transactions"
        if transactions.is_dir() and not any(transactions.iterdir()):
            transactions.rmdir()
        if self.paths.state_dir.is_dir() and not any(self.paths.state_dir.iterdir()):
            self.paths.state_dir.rmdir()

    def __enter__(self) -> "PluginTransaction":
        return self

    def __exit__(self, exception_type: Any, *_: object) -> None:
        if exception_type is not None and not self.finished:
            self.rollback()


def _safe_record_paths(
    plugin_root: Path, token: str, record: dict[str, Any]
) -> tuple[Path, Path | None, Path]:
    root = plugin_root.resolve(strict=False)
    target = Path(str(record.get("target") or ""))
    stage_value = str(record.get("stage") or "")
    stage = Path(stage_value) if stage_value else None
    backup = Path(str(record.get("backup") or ""))
    plugin_id = str(record.get("pluginId") or "")
    if (
        target.parent.resolve(strict=False) != root
        or backup.parent.resolve(strict=False) != root
        or target.name != plugin_id
        or not backup.name.startswith(f".shibumi-backup.{token}.")
        or (stage and stage.parent.resolve(strict=False) != root)
        or (stage and not stage.name.startswith(f".shibumi-stage.{token}."))
    ):
        raise TransactionError("unsafe path in Shibumi transaction journal")
    return target, stage, backup


def _restore_records(
    plugin_root: Path, token: str, records: Iterable[dict[str, Any]]
) -> None:
    for record in reversed(list(records)):
        target, stage, backup = _safe_record_paths(plugin_root, token, record)
        target_marker = _marker(target) if target.is_dir() else None
        if backup.exists() or backup.is_symlink():
            if target.exists() or target.is_symlink():
                if not target_marker or target_marker.get("transaction") != token:
                    raise TransactionError(
                        f"cannot safely roll back externally changed target: {target}"
                    )
                _remove_path(target)
            os.replace(backup, target)
        elif target.exists() or target.is_symlink():
            if target_marker and target_marker.get("transaction") == token:
                _remove_path(target)
        if stage and (stage.exists() or stage.is_symlink()):
            _remove_path(stage)


def recover_transactions(paths: RuntimePaths, runtime: OmarchyRuntime) -> int:
    root = paths.state_dir / "transactions"
    if not root.is_dir():
        return 0
    recovered = 0
    for directory in sorted(path for path in root.iterdir() if path.is_dir()):
        journal_file = directory / "journal.json"
        try:
            journal = json.loads(journal_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise TransactionError(f"cannot recover transaction {directory}: {error}") from error
        if journal.get("suiteId") != SUITE_ID or journal.get("schemaVersion") != 1:
            raise TransactionError(f"refusing unknown transaction journal: {directory}")
        token = str(journal.get("token") or "")
        if directory.name != token:
            raise TransactionError(f"transaction token mismatch: {directory}")
        plugin_root = Path(str(journal.get("pluginRoot") or ""))
        config_path = Path(str(journal.get("configPath") or ""))
        if (
            plugin_root.resolve(strict=False) != paths.plugin_dir.resolve(strict=False)
            or config_path.resolve(strict=False) != paths.config_file.resolve(strict=False)
        ):
            raise TransactionError(f"transaction path mismatch: {directory}")
        records = journal.get("records")
        if not isinstance(records, list):
            raise TransactionError(f"transaction records are malformed: {directory}")

        phase = str(journal.get("phase") or "")
        if phase in ("committing", "committed"):
            desired = journal.get("desiredState")
            state_file = paths.state_dir / "install.json"
            if desired is None:
                state_file.unlink(missing_ok=True)
            elif isinstance(desired, dict):
                atomic_write(
                    state_file,
                    (json.dumps(desired, indent=2, sort_keys=True) + "\n").encode(
                        "utf-8"
                    ),
                )
            for record in records:
                _, stage, backup = _safe_record_paths(plugin_root, token, record)
                if stage and (stage.exists() or stage.is_symlink()):
                    _remove_path(stage)
                if backup.exists() or backup.is_symlink():
                    _remove_path(backup)
        else:
            _restore_records(plugin_root, token, records)
            snapshot = directory / "shell.json.before"
            if journal.get("configExisted") is True:
                atomic_write(config_path, snapshot.read_bytes())
            else:
                config_path.unlink(missing_ok=True)
            runtime.reconcile_best_effort()
        shutil.rmtree(directory)
        recovered += 1
    if root.is_dir() and not any(root.iterdir()):
        root.rmdir()
    return recovered
