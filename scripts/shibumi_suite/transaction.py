from __future__ import annotations

import fcntl
import json
import os
import shutil
import stat
import time
import uuid
from pathlib import Path
from typing import Any, Iterable

from . import MANAGED_MARKER, STATE_SCHEMA_VERSION, SUITE_ID
from .config import atomic_write
from .model import (
    ContractError,
    PluginSpec,
    payload_copy_ignore,
    suite_payload_digest,
)
from .runtime import OmarchyRuntime, RuntimeFailure, RuntimePaths


class TransactionError(RuntimeError):
    pass


LEGACY_SUITE_ID = "hancore.qsrise"
LEGACY_MANAGED_MARKER = ".qsrise-managed.json"
PREPARATION_PREFIX = ".shibumi-preparing."
CLEANUP_PREFIX = ".shibumi-cleanup."
COMMIT_PHASES = {"committing", "committed"}
PRE_EXPOSURE_PHASES = {
    "prepared",
    "stopping-shell",
    "shell-stopped",
    "staging",
    "staged",
    "recovery-required",
}
ROLLBACK_PHASES = {
    "prepared",
    "stopping-shell",
    "shell-stopped",
    "shell-started",
    "staging",
    "staged",
    "exposing",
    "exposed",
    "configuring",
    "menu-configuring",
    "prepared-removal",
    "removed",
    "prepared-legacy-removal",
    "legacy-removed",
    "configured",
    "menu-configured",
    "recovery-required",
}


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


def _durable_unlink(path: Path) -> None:
    existed = path.exists() or path.is_symlink()
    path.unlink(missing_ok=True)
    if existed and path.parent.is_dir():
        _fsync_directory(path.parent)


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _fsync_regular_file(path: Path) -> None:
    mode = path.lstat().st_mode
    if not stat.S_ISREG(mode):
        raise TransactionError(f"cannot durably flush regular file: {path}")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _fsync_tree(root: Path) -> None:
    if root.is_symlink() or not root.is_dir():
        raise TransactionError(f"cannot durably flush staged payload: {root}")
    for directory_name, _directory_names, file_names in os.walk(
        root, topdown=False, followlinks=False
    ):
        directory = Path(directory_name)
        for file_name in file_names:
            path = directory / file_name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                continue
            if not stat.S_ISREG(mode):
                raise TransactionError(
                    f"unsupported staged payload entry while flushing: {path}"
                )
            _fsync_regular_file(path)
        _fsync_directory(directory)


def _durable_mkdir(path: Path) -> None:
    if path.is_symlink():
        raise TransactionError(f"refusing symlinked transaction directory: {path}")
    missing: list[Path] = []
    current = path
    while not current.exists():
        missing.append(current)
        if current.parent == current:
            raise TransactionError(f"cannot create transaction directory: {path}")
        current = current.parent
    if not current.is_dir():
        raise TransactionError(f"transaction parent is not a directory: {current}")
    for directory in reversed(missing):
        directory.mkdir()
        # Persist both the new directory metadata and its entry in the parent
        # before any transaction can mutate live lifecycle state.
        _fsync_directory(directory)
        _fsync_directory(directory.parent)


def _discard_private_transactions(root: Path) -> int:
    if root.is_symlink():
        raise TransactionError(f"refusing symlinked transaction root: {root}")
    if not root.is_dir():
        return 0
    removed = 0
    for path in root.iterdir():
        if not path.name.startswith((PREPARATION_PREFIX, CLEANUP_PREFIX)):
            continue
        if path.is_symlink() or not path.is_dir():
            raise TransactionError(
                f"refusing malformed private transaction directory: {path}"
            )
        shutil.rmtree(path)
        removed += 1
    if removed:
        _fsync_directory(root)
    return removed


def _retire_transaction_directory(root: Path, directory: Path, token: str) -> None:
    cleanup = root / f"{CLEANUP_PREFIX}{token}"
    if cleanup.exists() or cleanup.is_symlink():
        raise TransactionError(f"transaction cleanup path already exists: {cleanup}")
    os.replace(directory, cleanup)
    _fsync_directory(root)
    shutil.rmtree(cleanup)
    _fsync_directory(root)


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


def preflight_removal_ids(plugin_dir: Path, plugin_ids: Iterable[str]) -> None:
    for plugin_id in plugin_ids:
        target = plugin_dir / plugin_id
        if (target.exists() or target.is_symlink()) and not is_managed_target(
            target, plugin_id
        ):
            raise TransactionError(
                f"refusing to remove non-Shibumi plugin directory: {target}"
            )


def _config_enables_plugin(config_file: Path, plugin_id: str) -> bool:
    try:
        config = json.loads(config_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    if not isinstance(config, dict):
        return False

    def entry_id(value: Any) -> str:
        if isinstance(value, dict):
            return str(value.get("id") or "")
        return str(value or "")

    plugins = config.get("plugins")
    if isinstance(plugins, list) and any(
        entry_id(entry) == plugin_id for entry in plugins
    ):
        return True
    bar = config.get("bar")
    if not isinstance(bar, dict):
        return False
    if entry_id(bar.get("id")) == plugin_id:
        return True
    layout = bar.get("layout")
    if not isinstance(layout, dict):
        return False
    return any(
        entry_id(entry) == plugin_id
        for section in ("left", "center", "right")
        for entry in (
            layout.get(section) if isinstance(layout.get(section), list) else []
        )
    )


def preflight_legacy_removals(plugin_dir: Path, plugin_ids: Iterable[str]) -> None:
    for plugin_id in plugin_ids:
        target = plugin_dir / plugin_id
        if not target.is_dir() or not is_legacy_managed_target(target, plugin_id):
            raise TransactionError(
                f"refusing to migrate unmanaged legacy plugin directory: {target}"
            )


class PluginTransaction:
    def __init__(
        self,
        paths: RuntimePaths,
        runtime: OmarchyRuntime,
        *,
        restart_on_reconcile: bool = False,
    ) -> None:
        self.paths = paths
        self.runtime = runtime
        self.restart_on_reconcile = restart_on_reconcile
        self.token = f"{int(time.time())}-{os.getpid()}-{uuid.uuid4().hex[:8]}"
        transaction_root = paths.state_dir / "transactions"
        self.transaction_dir = transaction_root / self.token
        preparation_dir = transaction_root / f"{PREPARATION_PREFIX}{self.token}"
        self.journal_file = preparation_dir / "journal.json"
        self.snapshot_file = preparation_dir / "shell.json.before"
        self.menu_extension_snapshot_file = (
            preparation_dir / "omarchy-menu.jsonc.before"
        )
        self.records: list[dict[str, Any]] = []
        self.finished = False
        self.commit_point_reached = False
        self.shell_stopped = False
        self.restore_requires_drain = False
        self.live_mutation_started = False
        self.payload_reload_expected = (
            paths.plugin_dir / "hancore.shibumi.state"
        ).is_dir() and _config_enables_plugin(
            paths.config_file, "hancore.shibumi.state"
        )
        self.config_existed = paths.config_file.is_file()
        self.menu_extension_existed = paths.menu_extension_file.is_file()

        _durable_mkdir(transaction_root)
        preparation_dir.mkdir(exist_ok=False)
        try:
            if self.config_existed:
                atomic_write(
                    self.snapshot_file,
                    paths.config_file.read_bytes(),
                )
            if self.menu_extension_existed:
                atomic_write(
                    self.menu_extension_snapshot_file,
                    paths.menu_extension_file.read_bytes(),
                )
            self._write_journal("prepared")
            _fsync_directory(preparation_dir)
            os.replace(preparation_dir, self.transaction_dir)
            _fsync_directory(transaction_root)
        except Exception:
            # Before the directory rename no lifecycle mutation has happened,
            # so an in-process preparation failure can be discarded. If the
            # rename already succeeded, keep the complete public transaction
            # as the durable recovery path.
            if preparation_dir.exists() and not preparation_dir.is_symlink():
                shutil.rmtree(preparation_dir)
            raise
        self.journal_file = self.transaction_dir / "journal.json"
        self.snapshot_file = self.transaction_dir / "shell.json.before"
        self.menu_extension_snapshot_file = (
            self.transaction_dir / "omarchy-menu.jsonc.before"
        )

    def _journal(
        self,
        phase: str,
        desired_state: Any = "unchanged",
        archive_previous: Any = "unchanged",
    ) -> dict[str, Any]:
        value: dict[str, Any] = {
            "schemaVersion": 1,
            "suiteId": SUITE_ID,
            "token": self.token,
            "phase": phase,
            "pluginRoot": str(self.paths.plugin_dir.resolve(strict=False)),
            "configPath": str(self.paths.config_file.resolve(strict=False)),
            "configExisted": self.config_existed,
            "menuExtensionPath": str(
                self.paths.menu_extension_file.resolve(strict=False)
            ),
            "menuExtensionExisted": self.menu_extension_existed,
            "restartOnReconcile": self.restart_on_reconcile,
            "shellStopped": self.shell_stopped,
            "restoreRequiresDrain": self.restore_requires_drain,
            "liveMutationStarted": self.live_mutation_started,
            "payloadReloadExpected": self.payload_reload_expected,
            "records": self.records,
        }
        if desired_state != "unchanged":
            value["desiredState"] = desired_state
        if archive_previous != "unchanged":
            value["archivePrevious"] = archive_previous is True
        return value

    def _write_journal(
        self,
        phase: str,
        desired_state: Any = "unchanged",
        archive_previous: Any = "unchanged",
    ) -> None:
        payload = json.dumps(
            self._journal(phase, desired_state, archive_previous),
            indent=2,
            sort_keys=True,
        ).encode("utf-8") + b"\n"
        atomic_write(self.journal_file, payload)
        # The next operation may rename live plugin targets. Persist the
        # record-bearing journal replacement before crossing that boundary.
        _fsync_directory(self.journal_file.parent)

    def _begin_live_mutation(self, phase: str) -> None:
        if self.live_mutation_started:
            return
        # Persist this boundary before touching a live path. Recovery can then
        # discard a crash-interrupted preflight transaction without reloading
        # the shell, while any transaction that may have crossed this point is
        # reconciled conservatively.
        self.live_mutation_started = True
        self._write_journal(phase)

    def stop_shell(self) -> None:
        # A drain can kill the shell before the caller regains control. Record
        # that uncertainty first so an interruption can never be recovered as
        # a no-op while leaving the production shell stopped.
        previous_shell_stopped = self.shell_stopped
        previous_restore_requires_drain = self.restore_requires_drain
        self.shell_stopped = True
        self.restore_requires_drain = True
        try:
            self._write_journal("stopping-shell")
        except Exception:
            # No drain has occurred. Keep memory aligned with the last durable
            # journal so context rollback cannot stop a shell whose recovery
            # record still describes a pre-stop transaction.
            self.shell_stopped = previous_shell_stopped
            self.restore_requires_drain = previous_restore_requires_drain
            raise
        self.runtime.stop_shell()
        self._write_journal("shell-stopped")

    def mark_shell_started(self) -> None:
        self.shell_stopped = False
        self._write_journal("shell-started")

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
        _durable_mkdir(self.paths.plugin_dir)
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
                shutil.copytree(
                    spec.source,
                    stage,
                    symlinks=True,
                    ignore=payload_copy_ignore,
                )
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
            _fsync_tree(stage)
            _fsync_directory(self.paths.plugin_dir)
        self._write_journal("staged")
        return payload_digest, plugin_digests

    def expose(self) -> None:
        replacements = [
            record for record in self.records if record["action"] == "replace"
        ]
        if replacements:
            self._begin_live_mutation("exposing")
        for record in replacements:
            target = Path(record["target"])
            stage = Path(record["stage"])
            backup = Path(record["backup"])
            if record["hadTarget"]:
                os.replace(target, backup)
                _fsync_directory(self.paths.plugin_dir)
            os.replace(stage, target)
            _fsync_directory(self.paths.plugin_dir)
            self._write_journal("exposed")

    def stage_removal(self, specs: Iterable[PluginSpec]) -> None:
        self.stage_removal_ids(spec.id for spec in specs)

    def stage_removal_ids(self, plugin_ids: Iterable[str]) -> None:
        _durable_mkdir(self.paths.plugin_dir)
        for plugin_id in plugin_ids:
            target = self.paths.plugin_dir / plugin_id
            if not (target.exists() or target.is_symlink()):
                continue
            if not is_managed_target(target, plugin_id):
                raise TransactionError(
                    f"refusing to remove non-Shibumi plugin directory: {target}"
                )
            backup = self.paths.plugin_dir / f".shibumi-backup.{self.token}.{plugin_id}"
            record = {
                "action": "remove",
                "pluginId": plugin_id,
                "target": str(target),
                "stage": "",
                "backup": str(backup),
                "hadTarget": True,
            }
            self.records.append(record)
            self.live_mutation_started = True
            self._write_journal("prepared-removal")
            os.replace(target, backup)
            _fsync_directory(self.paths.plugin_dir)
            self._write_journal("removed")

    def stage_legacy_removal(self, plugin_ids: Iterable[str]) -> None:
        _durable_mkdir(self.paths.plugin_dir)
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
            self.live_mutation_started = True
            self._write_journal("prepared-legacy-removal")
            os.replace(target, backup)
            _fsync_directory(self.paths.plugin_dir)
            self._write_journal("legacy-removed")

    def write_config(self, payload: bytes) -> None:
        self._begin_live_mutation("configuring")
        atomic_write(self.paths.config_file, payload)
        self._write_journal("configured")

    def write_menu_extension(self, payload: bytes | None) -> None:
        path = self.paths.menu_extension_file
        if path.is_symlink() or path.parent.is_symlink():
            raise TransactionError(f"refusing symlinked Omarchy menu extension: {path}")
        self._begin_live_mutation("menu-configuring")
        if payload is None:
            _durable_unlink(path)
        else:
            atomic_write(path, payload)
        self._write_journal("menu-configured")

    def _restore_menu_extension(self) -> None:
        path = self.paths.menu_extension_file
        if self.menu_extension_existed:
            atomic_write(path, self.menu_extension_snapshot_file.read_bytes())
        else:
            _durable_unlink(path)
            if path.parent.is_dir() and not any(path.parent.iterdir()):
                parent = path.parent.parent
                path.parent.rmdir()
                if parent.is_dir():
                    _fsync_directory(parent)

    def rollback(self) -> None:
        if self.finished or self.commit_point_reached:
            return
        try:
            if not self.live_mutation_started and not self.shell_stopped:
                # Validation and lifecycle preflights may fail after the full
                # payload has been staged but before any live path changed.
                # Discard those hidden stages without causing a needless
                # rescan, reload, restart, or rewrite of unchanged config.
                self._cleanup_transaction()
                self.finished = True
                return
            # A managed transaction records a monotonic restore drain before
            # its first stop. A later start may succeed before verification or
            # commit, so drain again before restoring live roots and avoid a
            # hot reload against the reconciliation restart. Transactions that
            # never owned a stop retain the in-process external-bar fallback.
            if self.restore_requires_drain:
                _preflight_restore_records(
                    self.paths.plugin_dir, self.token, self.records
                )
                self.runtime.stop_shell()
            _restore_records(self.paths.plugin_dir, self.token, self.records)
            if self.config_existed:
                atomic_write(self.paths.config_file, self.snapshot_file.read_bytes())
            else:
                _durable_unlink(self.paths.config_file)
            self._restore_menu_extension()
            self.runtime.reconcile_rollback(
                restart_required=self.restart_on_reconcile,
                shell_was_stopped=(
                    self.shell_stopped or self.restore_requires_drain
                ),
                payload_reload_expected=self.payload_reload_expected,
            )
        except Exception:
            # The transaction directory is the only durable recovery path. A
            # failed restoration must retain its snapshots and journal so a
            # later `recover` can safely complete the same idempotent steps.
            try:
                self._write_journal("recovery-required")
            except Exception:
                # Keep the last durable journal when even the phase update
                # fails; never trade recovery data for a secondary error.
                pass
            raise
        else:
            self._cleanup_transaction()
            self.finished = True

    def finish(
        self,
        desired_state: dict[str, Any] | None,
        *,
        archive_previous: bool,
    ) -> None:
        self._write_journal("committing", desired_state, archive_previous)
        state_file = self.paths.state_dir / "install.json"
        if desired_state is None:
            _durable_unlink(state_file)
        else:
            atomic_write(
                state_file,
                (json.dumps(desired_state, indent=2, sort_keys=True) + "\n").encode(
                    "utf-8"
                ),
            )
        # install.json is the roll-forward commit point. Once it has changed,
        # rolling payloads back would make durable state describe the wrong
        # bytes. Any later failure retains the committing/committed journal so
        # recover_transactions() can idempotently finish the new state.
        self.commit_point_reached = True
        self._write_journal("committed", desired_state, archive_previous)

        if archive_previous:
            self._archive_backups()
        else:
            removed_backup = False
            for record in self.records:
                backup = Path(record["backup"])
                if backup.exists() or backup.is_symlink():
                    _remove_path(backup)
                    removed_backup = True
            if removed_backup:
                _fsync_directory(self.paths.plugin_dir)
        self._cleanup_transaction()
        self.finished = True

    def _archive_backups(self) -> None:
        _archive_transaction_backups(
            self.paths, self.token, self.records
        )

    def _cleanup_transaction(self) -> None:
        removed_stage = False
        for record in self.records:
            stage = Path(record["stage"]) if record.get("stage") else None
            if stage and (stage.exists() or stage.is_symlink()):
                _remove_path(stage)
                removed_stage = True
        if removed_stage:
            _fsync_directory(self.paths.plugin_dir)
        transactions = self.paths.state_dir / "transactions"
        if self.transaction_dir.exists():
            _retire_transaction_directory(
                transactions, self.transaction_dir, self.token
            )
        if transactions.is_dir() and not any(transactions.iterdir()):
            transactions.rmdir()
            if self.paths.state_dir.is_dir():
                _fsync_directory(self.paths.state_dir)
        if self.paths.state_dir.is_dir() and not any(self.paths.state_dir.iterdir()):
            state_parent = self.paths.state_dir.parent
            self.paths.state_dir.rmdir()
            if state_parent.is_dir():
                _fsync_directory(state_parent)

    def __enter__(self) -> "PluginTransaction":
        return self

    def __exit__(self, exception_type: Any, *_: object) -> None:
        if (
            exception_type is not None
            and not self.finished
            and not self.commit_point_reached
        ):
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


def _discard_pre_exposure_records(
    plugin_root: Path, token: str, records: Iterable[dict[str, Any]]
) -> None:
    stages: list[Path] = []
    for record in records:
        target, stage, backup = _safe_record_paths(plugin_root, token, record)
        target_marker = _marker(target) if target.is_dir() else None
        unexpected_target = not bool(record.get("hadTarget")) and (
            target.exists() or target.is_symlink()
        )
        if backup.exists() or backup.is_symlink() or unexpected_target or (
            target_marker and target_marker.get("transaction") == token
        ):
            raise TransactionError(
                "pre-exposure transaction contains live mutation artifacts"
            )
        if stage and (stage.exists() or stage.is_symlink()):
            stages.append(stage)
    for stage in stages:
        _remove_path(stage)
    removed_stage = bool(stages)
    if removed_stage and plugin_root.is_dir():
        _fsync_directory(plugin_root)


def _preflight_restore_records(
    plugin_root: Path, token: str, records: Iterable[dict[str, Any]]
) -> None:
    for record in reversed(list(records)):
        target, _stage, backup = _safe_record_paths(plugin_root, token, record)
        target_marker = _marker(target) if target.is_dir() else None
        target_exists = target.exists() or target.is_symlink()
        if backup.exists() or backup.is_symlink():
            if target_exists:
                if not target_marker or target_marker.get("transaction") != token:
                    raise TransactionError(
                        f"cannot safely roll back externally changed target: {target}"
                    )
        elif not bool(record.get("hadTarget")) and target_exists:
            if not target_marker or target_marker.get("transaction") != token:
                raise TransactionError(
                    f"cannot safely roll back externally changed target: {target}"
                )


def _restore_records(
    plugin_root: Path, token: str, records: Iterable[dict[str, Any]]
) -> None:
    record_list = list(records)
    _preflight_restore_records(plugin_root, token, record_list)
    for record in reversed(record_list):
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
    if plugin_root.is_dir():
        _fsync_directory(plugin_root)


def _archive_transaction_backups(
    paths: RuntimePaths,
    token: str,
    records: Iterable[dict[str, Any]],
) -> None:
    destination = paths.state_dir / "backups" / token
    for record in records:
        _, _, backup = _safe_record_paths(paths.plugin_dir, token, record)
        plugin_id = str(record["pluginId"])
        archived = destination / plugin_id
        partial = destination / f".{plugin_id}.partial"
        if partial.exists() or partial.is_symlink():
            _remove_path(partial)
        if archived.exists() or archived.is_symlink():
            # The archive-side rename is the per-record commit point. A crash
            # after it but before source removal legitimately leaves both.
            if backup.exists() or backup.is_symlink():
                _remove_path(backup)
                _fsync_directory(paths.plugin_dir)
            continue
        if not (backup.exists() or backup.is_symlink()):
            continue
        _durable_mkdir(destination)
        try:
            if backup.is_symlink():
                partial.symlink_to(os.readlink(backup))
            elif backup.is_dir():
                shutil.copytree(backup, partial, symlinks=True)
                _fsync_tree(partial)
            else:
                shutil.copy2(backup, partial, follow_symlinks=False)
                _fsync_regular_file(partial)
            os.replace(partial, archived)
            _fsync_directory(destination)
            _remove_path(backup)
            _fsync_directory(paths.plugin_dir)
        except Exception:
            # A partial copy is never authoritative and is safe to retry. Keep
            # the source backup until the archive-side atomic rename succeeds.
            if partial.exists() or partial.is_symlink():
                _remove_path(partial)
            raise

    if paths.plugin_dir.is_dir():
        _fsync_directory(paths.plugin_dir)

    backup_root = paths.state_dir / "backups"
    if backup_root.is_dir():
        retained = sorted(
            (path for path in backup_root.iterdir() if path.is_dir()),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        removed_stale = False
        for stale in retained[2:]:
            _remove_path(stale)
            removed_stale = True
        if removed_stale:
            _fsync_directory(backup_root)


def _snapshot_bytes(path: Path, label: str, directory: Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise TransactionError(
            f"transaction {label} snapshot is missing or unsafe: {directory}"
        )
    try:
        return path.read_bytes()
    except OSError as error:
        raise TransactionError(
            f"cannot read transaction {label} snapshot {directory}: {error}"
        ) from error


def recover_transactions(paths: RuntimePaths, runtime: OmarchyRuntime) -> int:
    root = paths.state_dir / "transactions"
    if root.is_symlink():
        raise TransactionError(f"refusing symlinked transaction root: {root}")
    if not root.exists():
        return 0
    if not root.is_dir():
        raise TransactionError(f"transaction root is not a directory: {root}")
    # Preparation and cleanup directories are never authoritative. Public
    # journals appear only after preparation and disappear atomically before
    # recursive cleanup.
    _discard_private_transactions(root)
    entries = sorted(root.iterdir())
    for entry in entries:
        if entry.is_symlink() or not entry.is_dir():
            raise TransactionError(
                f"refusing malformed transaction namespace entry: {entry}"
            )
    recovered = 0
    for directory in entries:
        journal_file = directory / "journal.json"
        if journal_file.is_symlink() or not journal_file.is_file():
            raise TransactionError(
                f"transaction journal is missing or unsafe: {directory}"
            )
        try:
            journal = json.loads(journal_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise TransactionError(f"cannot recover transaction {directory}: {error}") from error
        if not isinstance(journal, dict):
            raise TransactionError(
                f"transaction journal is not an object: {directory}"
            )
        schema = journal.get("schemaVersion")
        if (
            journal.get("suiteId") != SUITE_ID
            or type(schema) is not int
            or schema != 1
        ):
            raise TransactionError(f"refusing unknown transaction journal: {directory}")
        token = str(journal.get("token") or "")
        if directory.name != token:
            raise TransactionError(f"transaction token mismatch: {directory}")
        plugin_root = Path(str(journal.get("pluginRoot") or ""))
        config_path = Path(str(journal.get("configPath") or ""))
        menu_extension_value = journal.get("menuExtensionPath")
        menu_extension_path = (
            Path(str(menu_extension_value))
            if menu_extension_value else paths.menu_extension_file
        )
        if (
            plugin_root.resolve(strict=False) != paths.plugin_dir.resolve(strict=False)
            or config_path.resolve(strict=False) != paths.config_file.resolve(strict=False)
            or (
                menu_extension_value
                and menu_extension_path.resolve(strict=False)
                != paths.menu_extension_file.resolve(strict=False)
            )
        ):
            raise TransactionError(f"transaction path mismatch: {directory}")
        records_value = journal.get("records")
        if not isinstance(records_value, list):
            raise TransactionError(f"transaction records are malformed: {directory}")
        records: list[dict[str, Any]] = []
        for record in records_value:
            if not isinstance(record, dict):
                raise TransactionError(
                    f"transaction record is malformed: {directory}"
                )
            _safe_record_paths(plugin_root, token, record)
            records.append(record)

        phase_value = journal.get("phase")
        if not isinstance(phase_value, str) or phase_value not in (
            COMMIT_PHASES | ROLLBACK_PHASES
        ):
            raise TransactionError(f"transaction phase is malformed: {directory}")
        phase = phase_value
        config_existed_value = journal.get("configExisted")
        if not isinstance(config_existed_value, bool):
            raise TransactionError(
                f"transaction configExisted is malformed: {directory}"
            )
        restart_value = journal.get("restartOnReconcile", False)
        if not isinstance(restart_value, bool):
            raise TransactionError(
                f"transaction restartOnReconcile is malformed: {directory}"
            )
        if menu_extension_value and not isinstance(
            journal.get("menuExtensionExisted"), bool
        ):
            raise TransactionError(
                f"transaction menuExtensionExisted is malformed: {directory}"
            )

        config_snapshot_payload: bytes | None = None
        menu_snapshot_payload: bytes | None = None
        shell_stopped_value = True
        restore_requires_drain_value: bool | None = None
        live_mutation_value: bool | None = None
        payload_reload_value: bool | None = None
        if phase in ROLLBACK_PHASES:
            if config_existed_value:
                config_snapshot_payload = _snapshot_bytes(
                    directory / "shell.json.before", "config", directory
                )
            if menu_extension_value and journal["menuExtensionExisted"]:
                menu_snapshot_payload = _snapshot_bytes(
                    directory / "omarchy-menu.jsonc.before", "menu", directory
                )
            shell_stopped_value = journal.get("shellStopped", True)
            if not isinstance(shell_stopped_value, bool):
                raise TransactionError(
                    f"transaction shellStopped is malformed: {directory}"
                )
            if "restoreRequiresDrain" in journal:
                restore_requires_drain_value = journal[
                    "restoreRequiresDrain"
                ]
                if not isinstance(restore_requires_drain_value, bool):
                    raise TransactionError(
                        "transaction restoreRequiresDrain is malformed: "
                        f"{directory}"
                    )
            if "liveMutationStarted" in journal:
                live_mutation_value = journal["liveMutationStarted"]
                if not isinstance(live_mutation_value, bool):
                    raise TransactionError(
                        "transaction liveMutationStarted is malformed: "
                        f"{directory}"
                    )
            if live_mutation_value is False and phase not in PRE_EXPOSURE_PHASES:
                raise TransactionError(
                    "transaction pre-exposure phase is inconsistent: "
                    f"{directory}"
                )
            if restore_requires_drain_value is None:
                restore_requires_drain_value = shell_stopped_value or (
                    restart_value and live_mutation_value is not False
                )
            if "payloadReloadExpected" in journal:
                payload_reload_value = journal["payloadReloadExpected"]
                if not isinstance(payload_reload_value, bool):
                    raise TransactionError(
                        "transaction payloadReloadExpected is malformed: "
                        f"{directory}"
                    )

        if phase in COMMIT_PHASES:
            if "desiredState" not in journal:
                raise TransactionError(
                    f"transaction desired state is missing: {directory}"
                )
            desired = journal.get("desiredState")
            if desired is not None and not isinstance(desired, dict):
                raise TransactionError(
                    f"transaction desired state is malformed: {directory}"
                )
            archive_value = journal.get("archivePrevious")
            if not isinstance(archive_value, bool):
                raise TransactionError(
                    f"transaction archive intent is malformed: {directory}"
                )
            state_file = paths.state_dir / "install.json"
            if desired is None:
                _durable_unlink(state_file)
            elif isinstance(desired, dict):
                atomic_write(
                    state_file,
                    (json.dumps(desired, indent=2, sort_keys=True) + "\n").encode(
                        "utf-8"
                    ),
                )
            removed_stage = False
            for record in records:
                _, stage, _ = _safe_record_paths(plugin_root, token, record)
                if stage and (stage.exists() or stage.is_symlink()):
                    _remove_path(stage)
                    removed_stage = True
            if removed_stage:
                _fsync_directory(plugin_root)
            if archive_value:
                _archive_transaction_backups(paths, token, records)
            else:
                removed_backup = False
                for record in records:
                    _, _, backup = _safe_record_paths(plugin_root, token, record)
                    if backup.exists() or backup.is_symlink():
                        _remove_path(backup)
                        removed_backup = True
                if removed_backup:
                    _fsync_directory(plugin_root)
        else:
            restart_on_reconcile = restart_value
            if live_mutation_value is False and not shell_stopped_value:
                _discard_pre_exposure_records(plugin_root, token, records)
            else:
                # A managed transaction keeps restoreRequiresDrain monotonic
                # after its first stop. A later start may have succeeded even
                # when shellStopped is false, so re-establish the stopped state
                # before restoring any live plugin root.
                if restore_requires_drain_value:
                    _preflight_restore_records(plugin_root, token, records)
                    runtime.stop_shell()
                _restore_records(plugin_root, token, records)
                if config_existed_value:
                    atomic_write(config_path, config_snapshot_payload)
                else:
                    _durable_unlink(config_path)
                if menu_extension_value:
                    if journal["menuExtensionExisted"]:
                        atomic_write(menu_extension_path, menu_snapshot_payload)
                    else:
                        _durable_unlink(menu_extension_path)
                        if menu_extension_path.parent.is_dir() \
                                and not any(menu_extension_path.parent.iterdir()):
                            parent = menu_extension_path.parent.parent
                            menu_extension_path.parent.rmdir()
                            if parent.is_dir():
                                _fsync_directory(parent)
                if payload_reload_value is None:
                    payload_reload_value = (
                        (paths.plugin_dir / "hancore.shibumi.state").is_dir()
                        and _config_enables_plugin(
                            paths.config_file, "hancore.shibumi.state"
                        )
                    )
                runtime.reconcile_rollback(
                    restart_required=restart_on_reconcile,
                    # Schema-v1 journals predating the live-mutation field are
                    # conservative because they may have crossed an exposure
                    # or ownership-changing stop boundary.
                    shell_was_stopped=(
                        shell_stopped_value
                        or restore_requires_drain_value is True
                    ),
                    payload_reload_expected=payload_reload_value,
                )
        _retire_transaction_directory(root, directory, token)
        recovered += 1
    if root.is_dir() and not any(root.iterdir()):
        root.rmdir()
        if paths.state_dir.is_dir():
            _fsync_directory(paths.state_dir)
    return recovered
