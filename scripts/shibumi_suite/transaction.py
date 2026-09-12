from __future__ import annotations

import errno
import fcntl
import hashlib
import json
import os
import shutil
import stat
import time
import uuid
from pathlib import Path
from typing import Any, Callable, Iterable

from . import MANAGED_MARKER, STATE_SCHEMA_VERSION, SUITE_ID
from .admission import (
    JOURNAL_SCHEMA_VERSION,
    MAX_STATE_BYTES,
    inventory_transactions,
    parse_config_parent_identity,
    supported_install_identities,
    verify_transaction_artifact_bindings,
)
from .config import atomic_write, parse_config_bytes, read_config
from .model import (
    ContractError,
    PluginSpec,
    Suite,
    payload_copy_ignore,
    plugin_payload_digest,
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


def _expected_directory_binding(
    bindings: list[dict[str, Any]] | None, path: Path
) -> dict[str, Any] | None:
    if bindings is None:
        return None
    matches = [
        binding for binding in bindings
        if binding.get("kind") == "directoryIdentity"
        and binding.get("path") == path
    ]
    if len(matches) != 1:
        raise TransactionError(
            f"validated archive directory binding is unavailable: {path}"
        )
    return matches[0]


def _verify_open_directory(
    descriptor: int,
    path: Path,
    expected: dict[str, Any] | None,
    created: os.stat_result | None = None,
) -> None:
    metadata = os.fstat(descriptor)
    authority = created if created is not None else expected
    if authority is None:
        return
    expected_device = (
        authority.st_dev if isinstance(authority, os.stat_result)
        else authority.get("device")
    )
    expected_inode = (
        authority.st_ino if isinstance(authority, os.stat_result)
        else authority.get("inode")
    )
    if metadata.st_dev != expected_device or metadata.st_ino != expected_inode:
        raise TransactionError(
            f"transaction archive directory identity changed: {path}"
        )


def _open_absolute_directory(
    path: Path, expected: dict[str, Any] | None
) -> int:
    if not path.is_absolute():
        raise TransactionError(f"transaction archive path is not absolute: {path}")
    descriptor = os.open(
        "/", os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW
    )
    try:
        for part in path.parts[1:]:
            child = os.open(
                part,
                os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=descriptor,
            )
            os.close(descriptor)
            descriptor = child
        _verify_open_directory(descriptor, path, expected)
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _open_config_parent(path: Path, *, create: bool) -> int:
    """Open an absolute directory component-wise without following symlinks."""
    if not path.is_absolute() or ".." in path.parts:
        raise TransactionError(f"unsafe live shell config parent: {path}")
    descriptor = os.open(
        "/", os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW
    )
    try:
        for part in path.parts[1:]:
            created: os.stat_result | None = None
            try:
                child = os.open(
                    part,
                    os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW,
                    dir_fd=descriptor,
                )
            except FileNotFoundError as error:
                if not create:
                    raise TransactionError(
                        f"live shell config parent is missing: {path}"
                    ) from error
                try:
                    os.mkdir(part, mode=0o777, dir_fd=descriptor)
                except FileExistsError as race:
                    raise TransactionError(
                        f"live shell config parent changed while binding: {path}"
                    ) from race
                os.fsync(descriptor)
                created = os.stat(part, dir_fd=descriptor, follow_symlinks=False)
                try:
                    child = os.open(
                        part,
                        os.O_RDONLY
                        | os.O_CLOEXEC
                        | os.O_DIRECTORY
                        | os.O_NOFOLLOW,
                        dir_fd=descriptor,
                    )
                except OSError as open_error:
                    raise TransactionError(
                        f"cannot bind live shell config parent {path}: {open_error}"
                    ) from open_error
            except OSError as error:
                raise TransactionError(
                    f"cannot bind live shell config parent {path}: {error}"
                ) from error
            if created is not None:
                metadata = os.fstat(child)
                if (
                    metadata.st_dev != created.st_dev
                    or metadata.st_ino != created.st_ino
                ):
                    os.close(child)
                    raise TransactionError(
                        f"live shell config parent changed while binding: {path}"
                    )
                os.fsync(child)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _open_verified_config_parent(
    path: Path, expected_device: int, expected_inode: int
) -> int:
    descriptor = _open_config_parent(path, create=False)
    try:
        metadata = os.fstat(descriptor)
        if (
            metadata.st_dev != expected_device
            or metadata.st_ino != expected_inode
        ):
            raise TransactionError(
                f"live shell config parent identity changed: {path}"
            )
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _require_open_config_parent_identity(
    path: Path, expected_device: int, expected_inode: int, descriptor: int
) -> None:
    try:
        held = os.fstat(descriptor)
    except OSError as error:
        raise TransactionError(
            f"open live shell config parent binding failed: {path}: {error}"
        ) from error
    if held.st_dev != expected_device or held.st_ino != expected_inode:
        raise TransactionError(
            f"open live shell config parent identity changed: {path}"
        )
    current = _open_verified_config_parent(path, expected_device, expected_inode)
    os.close(current)


def _read_bounded_regular_at(
    parent_fd: int,
    name: str,
    path: Path,
    *,
    label: str = "live shell config",
) -> tuple[bool, bytes | None]:
    try:
        descriptor = os.open(
            name,
            os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=parent_fd,
        )
    except OSError as error:
        if error.errno == errno.ENOENT:
            return False, None
        raise TransactionError(
            f"cannot read {label} {path}: {error}"
        ) from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise TransactionError(f"{label} is not a regular file: {path}")
        if before.st_size > MAX_STATE_BYTES:
            raise TransactionError(
                f"{label} exceeds the {MAX_STATE_BYTES}-byte limit: {path}"
            )
        payload = bytearray()
        while len(payload) <= MAX_STATE_BYTES:
            block = os.read(
                descriptor,
                min(65536, MAX_STATE_BYTES + 1 - len(payload)),
            )
            if not block:
                break
            payload.extend(block)
        after = os.fstat(descriptor)
        if (
            len(payload) > MAX_STATE_BYTES
            or len(payload) != after.st_size
            or before.st_dev != after.st_dev
            or before.st_ino != after.st_ino
            or before.st_size != after.st_size
            or before.st_mtime_ns != after.st_mtime_ns
            or before.st_ctime_ns != after.st_ctime_ns
        ):
            raise TransactionError(
                f"{label} changed or exceeded bounds while reading: {path}"
            )
        return True, bytes(payload)
    except OSError as error:
        raise TransactionError(
            f"cannot read {label} {path}: {error}"
        ) from error
    finally:
        os.close(descriptor)


def _read_bounded_regular_path(path: Path, label: str) -> bytes:
    parent_fd = _open_config_parent(path.parent, create=False)
    try:
        existed, payload = _read_bounded_regular_at(
            parent_fd, path.name, path, label=label
        )
    finally:
        os.close(parent_fd)
    if not existed or payload is None:
        raise TransactionError(f"{label} is missing: {path}")
    return payload


def _atomic_replace_at(
    parent_fd: int,
    name: str,
    payload: bytes,
    *,
    mode: int = 0o600,
) -> None:
    _require_bounded_config_payload(payload)
    temporary_name = f".{name}.{uuid.uuid4().hex}"
    descriptor = os.open(
        temporary_name,
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
        | os.O_CLOEXEC
        | os.O_NOFOLLOW,
        0o600,
        dir_fd=parent_fd,
    )
    try:
        view = memoryview(payload)
        written = 0
        while written < len(view):
            count = os.write(descriptor, view[written:])
            if count <= 0:
                raise OSError(errno.EIO, "short write while replacing shell config")
            written += count
        os.fchmod(descriptor, mode)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(
            temporary_name,
            name,
            src_dir_fd=parent_fd,
            dst_dir_fd=parent_fd,
        )
        os.fsync(parent_fd)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary_name, dir_fd=parent_fd)
        except FileNotFoundError:
            pass


def _require_bounded_config_payload(payload: bytes) -> None:
    if len(payload) > MAX_STATE_BYTES:
        raise TransactionError(
            f"shell config payload exceeds the {MAX_STATE_BYTES}-byte limit"
        )


def _durable_unlink_at(parent_fd: int, name: str) -> None:
    try:
        os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    os.unlink(name, dir_fd=parent_fd)
    os.fsync(parent_fd)


def _open_directory_child(
    parent_fd: int,
    name: str,
    path: Path,
    expected: dict[str, Any] | None,
) -> int:
    expected_exists = bool(expected and expected.get("exists"))
    created: os.stat_result | None = None
    if expected is not None and not expected_exists:
        try:
            os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise TransactionError(
                f"transaction archive directory appeared after admission: {path}"
            )
    try:
        os.mkdir(name, mode=0o700, dir_fd=parent_fd)
        os.fsync(parent_fd)
        created = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileExistsError:
        if expected is not None and not expected_exists:
            raise TransactionError(
                f"transaction archive directory appeared after admission: {path}"
            )
    try:
        descriptor = os.open(
            name,
            os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW,
            dir_fd=parent_fd,
        )
    except OSError as error:
        raise TransactionError(
            f"cannot open trusted transaction archive directory {name}: {error}"
        ) from error
    try:
        _verify_open_directory(descriptor, path, expected, created)
        os.fsync(descriptor)
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _open_archive_descriptors(
    paths: RuntimePaths,
    token: str,
    bindings: list[dict[str, Any]] | None = None,
) -> tuple[int, int, int]:
    backup_path = paths.state_dir / "backups"
    destination_path = backup_path / token
    state_fd = _open_absolute_directory(
        paths.state_dir,
        _expected_directory_binding(bindings, paths.state_dir),
    )
    try:
        backup_fd = _open_directory_child(
            state_fd,
            "backups",
            backup_path,
            _expected_directory_binding(bindings, backup_path),
        )
        try:
            destination_fd = _open_directory_child(
                backup_fd,
                token,
                destination_path,
                _expected_directory_binding(bindings, destination_path),
            )
        except Exception:
            os.close(backup_fd)
            raise
    except Exception:
        os.close(state_fd)
        raise
    return state_fd, backup_fd, destination_fd


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


def _config_payload_enables_plugin(payload: bytes | None, plugin_id: str) -> bool:
    if payload is None:
        return False
    try:
        config = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
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
        self.phase = "prepared"
        self.finished = False
        self.commit_point_reached = False
        self.shell_stopped = False
        self.restore_requires_drain = False
        self.live_mutation_started = False
        self._config_snapshot_identity: tuple[int, int, str] | None = None
        self._config_path = paths.config_file
        self._config_parent_fd = _open_config_parent(
            self._config_path.parent, create=True
        )
        try:
            self._config_parent_identity = os.fstat(self._config_parent_fd)
            self.config_existed, config_payload = self._live_config()
            self.payload_reload_expected = (
                paths.plugin_dir / "hancore.shibumi.state"
            ).is_dir() and _config_payload_enables_plugin(
                config_payload, "hancore.shibumi.state"
            )
            self.menu_extension_existed = paths.menu_extension_file.is_file()

            _durable_mkdir(transaction_root)
            preparation_dir.mkdir(exist_ok=False)
            try:
                if self.config_existed:
                    assert config_payload is not None
                    atomic_write(self.snapshot_file, config_payload)
                    self._bind_config_snapshot(config_payload)
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
        except Exception:
            self._close_config_parent()
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
            "schemaVersion": JOURNAL_SCHEMA_VERSION,
            "suiteId": SUITE_ID,
            "token": self.token,
            "phase": phase,
            "pluginRoot": str(self.paths.plugin_dir.resolve(strict=False)),
            "configPath": str(self._config_path),
            "configParentIdentity": {
                "device": self._config_parent_identity.st_dev,
                "inode": self._config_parent_identity.st_ino,
            },
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
        *,
        on_durable: Callable[[], None] | None = None,
    ) -> None:
        payload = json.dumps(
            self._journal(phase, desired_state, archive_previous),
            indent=2,
            sort_keys=True,
        ).encode("utf-8") + b"\n"
        # The optional transition runs at the parent-fsync boundary, before
        # descriptor close or temporary cleanup can report a late error.
        if on_durable is None:
            atomic_write(self.journal_file, payload)
        else:
            atomic_write(
                self.journal_file, payload, on_durable=on_durable
            )
        self.phase = phase

    def _begin_live_mutation(self, phase: str) -> None:
        self._require_config_parent_identity()
        if self.live_mutation_started:
            return
        # Persist this boundary before touching a live path. Recovery can then
        # discard a crash-interrupted preflight transaction without reloading
        # the shell, while any transaction that may have crossed this point is
        # reconciled conservatively.
        self.live_mutation_started = True
        self._write_journal(phase)

    def stop_shell(self) -> None:
        self._require_config_parent_identity()
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
        self._require_config_parent_identity()
        self.runtime.stop_shell()
        self._require_config_parent_identity()
        self._write_journal("shell-stopped")

    def _close_config_parent(self) -> None:
        descriptor = self._config_parent_fd
        if descriptor >= 0:
            os.close(descriptor)
            self._config_parent_fd = -1

    def _require_config_parent_identity(self) -> None:
        if self._config_parent_fd < 0:
            raise TransactionError("live shell config parent binding is closed")
        expected = self._config_parent_identity
        _require_open_config_parent_identity(
            self._config_path.parent,
            expected.st_dev,
            expected.st_ino,
            self._config_parent_fd,
        )

    def _bind_config_snapshot(self, expected_payload: bytes) -> None:
        payload, identity = _snapshot_bytes_and_identity(
            self.snapshot_file, "config", self.snapshot_file.parent
        )
        if payload != expected_payload:
            raise TransactionError(
                "transaction config snapshot differs from its source"
            )
        self._config_snapshot_identity = identity

    def _config_snapshot_payload(self) -> bytes:
        if self._config_snapshot_identity is None:
            raise TransactionError("transaction config snapshot identity is unavailable")
        return _snapshot_bytes_and_identity(
            self.snapshot_file,
            "config",
            self.snapshot_file.parent,
            expected_identity=self._config_snapshot_identity,
        )[0]

    def _live_config(self) -> tuple[bool, bytes | None]:
        """Read one bounded regular file relative to the admitted parent FD."""
        self._require_config_parent_identity()
        return _read_bounded_regular_at(
            self._config_parent_fd, self._config_path.name, self._config_path
        )

    def _replace_live_config(self, payload: bytes) -> None:
        self._require_config_parent_identity()
        _atomic_replace_at(
            self._config_parent_fd, self._config_path.name, payload
        )

    def _unlink_live_config(self) -> None:
        self._require_config_parent_identity()
        _durable_unlink_at(self._config_parent_fd, self._config_path.name)

    def _replace_config_baseline(self) -> None:
        existed, payload = self._live_config()
        self.payload_reload_expected = (
            self.paths.plugin_dir / "hancore.shibumi.state"
        ).is_dir() and _config_payload_enables_plugin(
            payload, "hancore.shibumi.state"
        )
        if existed:
            assert payload is not None
            # Publishing bytes before the existence bit is safe: recovery of
            # the old absent journal ignores the unadmitted extra snapshot.
            atomic_write(self.snapshot_file, payload)
            self._bind_config_snapshot(payload)
            self.config_existed = True
            self._write_journal(self.phase)
        else:
            # Publish absence before unlinking an old snapshot. A crash on
            # either side leaves recovery with a complete journal/snapshot pair
            # and, while liveMutationStarted is false, foreign config is kept.
            self.config_existed = False
            self._config_snapshot_identity = None
            self._write_journal(self.phase)
            _durable_unlink(self.snapshot_file)

    def refresh_config_after_stop(self) -> dict[str, Any]:
        """Make the drained shell document the durable rollback baseline."""
        if not self.restore_requires_drain or not self.shell_stopped:
            raise TransactionError("config baseline refresh requires a drained shell")
        self._replace_config_baseline()
        snapshot_payload = (
            self._config_snapshot_payload() if self.config_existed else b""
        )
        if snapshot_payload:
            return parse_config_bytes(
                snapshot_payload,
                self.snapshot_file,
                user_config_exists=True,
            )[0]
        defaults_payload = _read_bounded_regular_path(
            self.paths.defaults_file, "shell config defaults"
        )
        return parse_config_bytes(
            defaults_payload,
            self.paths.defaults_file,
            user_config_exists=False,
        )[0]

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
            had_target = target.exists() or target.is_symlink()
            record = {
                "action": "replace",
                "pluginId": spec.id,
                "target": str(target),
                "stage": str(stage),
                "backup": str(backup),
                "hadTarget": had_target,
            }
            if had_target:
                record["beforePayloadDigest"] = plugin_payload_digest(target)
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
                "beforePayloadDigest": plugin_payload_digest(target),
            }
            self.records.append(record)
            self._require_config_parent_identity()
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
                "beforePayloadDigest": plugin_payload_digest(target),
            }
            self.records.append(record)
            self._require_config_parent_identity()
            self.live_mutation_started = True
            self._write_journal("prepared-legacy-removal")
            os.replace(target, backup)
            _fsync_directory(self.paths.plugin_dir)
            self._write_journal("legacy-removed")

    def write_config(self, payload: bytes) -> None:
        _require_bounded_config_payload(payload)
        self._begin_live_mutation("configuring")
        self._replace_live_config(payload)
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
            self._require_config_parent_identity()
            snapshot_payload = (
                self._config_snapshot_payload() if self.config_existed else None
            )
            if not self.live_mutation_started:
                # Validation and lifecycle preflights may fail after staging or
                # after a managed drain, but before any live path changed. The
                # shell may have saved config while draining, so never replace
                # that live document with the transaction-init snapshot.
                if self.restore_requires_drain:
                    self._require_config_parent_identity()
                    self.runtime.stop_shell()
                    self._require_config_parent_identity()
                    self.runtime.reconcile_rollback(
                        restart_required=self.restart_on_reconcile,
                        shell_was_stopped=True,
                        payload_reload_expected=self.payload_reload_expected,
                    )
                self._require_config_parent_identity()
                self._cleanup_transaction()
                self.finished = True
                self._close_config_parent()
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
                self._require_config_parent_identity()
                self.runtime.stop_shell()
                self._require_config_parent_identity()
            self._require_config_parent_identity()
            _restore_records(self.paths.plugin_dir, self.token, self.records)
            if self.config_existed:
                assert snapshot_payload is not None
                self._replace_live_config(snapshot_payload)
            else:
                self._unlink_live_config()
            self._require_config_parent_identity()
            self._restore_menu_extension()
            self._require_config_parent_identity()
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
            self._require_config_parent_identity()
            self._cleanup_transaction()
            self.finished = True
            self._close_config_parent()

    def finish(
        self,
        desired_state: dict[str, Any] | None,
        *,
        archive_previous: bool,
    ) -> None:
        self._require_config_parent_identity()

        def mark_commit_point() -> None:
            self.commit_point_reached = True

        # The durable committing journal is sufficient to roll forward. Mark
        # that boundary inside the atomic publisher: close or cleanup may still
        # report a late error after the parent directory has reached storage.
        self._write_journal(
            "committing",
            desired_state,
            archive_previous,
            on_durable=mark_commit_point,
        )
        self._require_config_parent_identity()
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
        self._require_config_parent_identity()
        self._cleanup_transaction()
        self.finished = True
        self._close_config_parent()

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
        try:
            if (
                exception_type is not None
                and not self.finished
                and not self.commit_point_reached
            ):
                self.rollback()
        finally:
            self._close_config_parent()


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
        target_exists = target.exists() or target.is_symlink()
        target_marker = _marker(target) if target.is_dir() else None
        unexpected_target = not bool(record.get("hadTarget")) and target_exists
        missing_original = bool(record.get("hadTarget")) and not target_exists
        unsafe_artifact = (
            target.is_symlink()
            or backup.is_symlink()
            or (stage is not None and stage.is_symlink())
        )
        if (
            unsafe_artifact
            or missing_original
            or backup.exists()
            or unexpected_target
            or (target_marker and target_marker.get("transaction") == token)
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
    plugin_root: Path,
    token: str,
    records: Iterable[dict[str, Any]],
    backup_overrides: dict[str, Path] | None = None,
) -> None:
    for record in reversed(list(records)):
        target, stage, expected_backup = _safe_record_paths(
            plugin_root, token, record
        )
        backup = (backup_overrides or {}).get(
            str(record.get("pluginId") or ""), expected_backup
        )
        target_exists = target.exists() or target.is_symlink()
        backup_exists = backup.exists() or backup.is_symlink()
        stage_exists = bool(stage and (stage.exists() or stage.is_symlink()))
        if (
            target.is_symlink()
            or backup.is_symlink()
            or (stage is not None and stage.is_symlink())
            or (target_exists and not target.is_dir())
            or (backup_exists and not backup.is_dir())
            or (stage_exists and stage is not None and not stage.is_dir())
        ):
            raise TransactionError(
                "transaction recovery artifact is unsafe or malformed"
            )
        target_marker = _marker(target) if target_exists else None
        action = str(record.get("action") or "")
        owner_check = is_legacy_managed_target \
            if action == "remove-legacy" else is_managed_target
        plugin_id = str(record.get("pluginId") or "")
        if target_exists and not owner_check(target, plugin_id):
            raise TransactionError(
                f"transaction contains an externally changed target: {target}"
            )
        if backup_exists and not owner_check(backup, plugin_id):
            raise TransactionError(
                f"transaction backup ownership is invalid: {backup}"
            )
        if bool(record.get("hadTarget")):
            # A replacement/removal of an existing target can have no backup
            # only before that target is renamed. Once the target is absent or
            # carries this transaction's exposed marker, the missing backup is
            # unrecoverable and must preserve the journal without mutation.
            if not backup_exists and (
                not target_exists
                or (
                    target_marker is not None
                    and target_marker.get("transaction") == token
                )
            ):
                raise TransactionError(
                    f"transaction backup is missing for exposed target: {target}"
                )
        elif backup_exists:
            raise TransactionError(
                f"transaction created an impossible backup for new target: {backup}"
            )
        if backup_exists:
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


def _verify_recovery_backup(
    plugin_id: str,
    expected_backup: Path,
    current_backup: Path,
    bindings: list[dict[str, Any]],
    identities: list[dict[str, Any]],
    *,
    binding_path: Path | None = None,
) -> None:
    candidates = [
        binding for binding in bindings
        if binding.get("exists") is True
        and binding.get("kind") in {"managed", "legacy"}
        and binding.get("pluginId") == plugin_id
        and binding.get("role") == "backup"
    ]
    preferred_paths = {binding_path} if binding_path is not None else {
        expected_backup, current_backup
    }
    path_candidates = [
        binding for binding in candidates
        if binding.get("path") in preferred_paths
    ]
    if len(path_candidates) == 1:
        candidates = path_candidates
    if len(candidates) != 1:
        raise TransactionError(
            f"validated backup binding is unavailable: {expected_backup}"
        )
    current = dict(candidates[0])
    current["path"] = current_backup
    verify_transaction_artifact_bindings([current], identities)


def _restore_records(
    plugin_root: Path,
    token: str,
    records: Iterable[dict[str, Any]],
    backup_overrides: dict[str, Path] | None = None,
    backup_bindings: list[dict[str, Any]] | None = None,
    artifact_identities: list[dict[str, Any]] | None = None,
) -> None:
    record_list = list(records)
    _preflight_restore_records(
        plugin_root, token, record_list, backup_overrides
    )
    for record in reversed(record_list):
        target, stage, expected_backup = _safe_record_paths(
            plugin_root, token, record
        )
        plugin_id = str(record.get("pluginId") or "")
        backup = (backup_overrides or {}).get(plugin_id, expected_backup)
        discard = plugin_root / f".shibumi-discard.{token}.{plugin_id}"
        target_marker = _marker(target) if target.is_dir() else None
        backup_exists = backup.exists() or backup.is_symlink()
        discard_exists = discard.exists() or discard.is_symlink()
        if backup_exists:
            if backup_bindings and artifact_identities:
                _verify_recovery_backup(
                    plugin_id,
                    expected_backup,
                    backup,
                    backup_bindings,
                    artifact_identities,
                )
            if target.exists() or target.is_symlink():
                if not target_marker or target_marker.get("transaction") != token:
                    raise TransactionError(
                        f"cannot safely roll back externally changed target: {target}"
                    )
                if discard_exists:
                    raise TransactionError(
                        f"transaction rollback discard already exists: {discard}"
                    )
                os.replace(target, discard)
                discard_exists = True
                _fsync_directory(plugin_root)
            try:
                os.replace(backup, target)
                _fsync_directory(plugin_root)
                if backup_bindings and artifact_identities:
                    _verify_recovery_backup(
                        plugin_id,
                        expected_backup,
                        target,
                        backup_bindings,
                        artifact_identities,
                    )
            except Exception:
                if target.exists() or target.is_symlink():
                    os.replace(target, backup)
                if discard_exists and not (
                    target.exists() or target.is_symlink()
                ):
                    os.replace(discard, target)
                _fsync_directory(plugin_root)
                raise
            if discard_exists:
                _remove_path(discard)
        elif target.exists() or target.is_symlink():
            if target_marker and target_marker.get("transaction") == token:
                if discard_exists:
                    raise TransactionError(
                        f"transaction rollback discard conflicts with target: {discard}"
                    )
                os.replace(target, discard)
                _fsync_directory(plugin_root)
                _remove_path(discard)
            elif discard_exists:
                _remove_path(discard)
        elif discard_exists:
            _remove_path(discard)
        if stage and (stage.exists() or stage.is_symlink()):
            _remove_path(stage)
    if plugin_root.is_dir():
        _fsync_directory(plugin_root)


def _archive_transaction_backups_open(
    paths: RuntimePaths,
    token: str,
    records: Iterable[dict[str, Any]],
    destination: Path,
    logical_destination: Path,
    backup_root: Path,
    backup_overrides: dict[str, Path] | None = None,
    backup_bindings: list[dict[str, Any]] | None = None,
    artifact_identities: list[dict[str, Any]] | None = None,
) -> None:
    for record in records:
        _, _, expected_backup = _safe_record_paths(
            paths.plugin_dir, token, record
        )
        plugin_id = str(record["pluginId"])
        backup = (backup_overrides or {}).get(plugin_id, expected_backup)
        archived = destination / plugin_id
        logical_archived = logical_destination / plugin_id
        partial = destination / f".{plugin_id}.partial"
        if partial.exists() or partial.is_symlink():
            _remove_path(partial)
        if archived.exists() or archived.is_symlink():
            # The archive-side rename is the per-record commit point. A crash
            # after it but before source removal legitimately leaves both.
            if (backup.exists() or backup.is_symlink()) \
                    and backup_bindings and artifact_identities:
                _verify_recovery_backup(
                    plugin_id,
                    expected_backup,
                    backup,
                    backup_bindings,
                    artifact_identities,
                )
            if backup_bindings and artifact_identities:
                _verify_recovery_backup(
                    plugin_id,
                    expected_backup,
                    archived,
                    backup_bindings,
                    artifact_identities,
                    binding_path=logical_archived,
                )
            if backup.exists() or backup.is_symlink():
                _remove_path(backup)
                _fsync_directory(paths.plugin_dir)
            continue
        if not (backup.exists() or backup.is_symlink()):
            continue
        if backup_bindings and artifact_identities:
            _verify_recovery_backup(
                plugin_id,
                expected_backup,
                backup,
                backup_bindings,
                artifact_identities,
            )
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
            if backup_bindings and artifact_identities:
                _verify_recovery_backup(
                    plugin_id,
                    expected_backup,
                    archived,
                    backup_bindings,
                    artifact_identities,
                )
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


def _archive_transaction_backups(
    paths: RuntimePaths,
    token: str,
    records: Iterable[dict[str, Any]],
    backup_overrides: dict[str, Path] | None = None,
    backup_bindings: list[dict[str, Any]] | None = None,
    artifact_identities: list[dict[str, Any]] | None = None,
    archive_descriptors: tuple[int, int, int] | None = None,
) -> None:
    state_fd, backup_fd, destination_fd = (
        archive_descriptors
        if archive_descriptors is not None
        else _open_archive_descriptors(paths, token)
    )
    try:
        proc_root = Path("/proc/self/fd")
        _archive_transaction_backups_open(
            paths,
            token,
            records,
            proc_root / str(destination_fd),
            paths.state_dir / "backups" / token,
            proc_root / str(backup_fd),
            backup_overrides,
            backup_bindings,
            artifact_identities,
        )
    finally:
        os.close(destination_fd)
        os.close(backup_fd)
        os.close(state_fd)


def _restore_quarantined_backups(
    plugin_root: Path,
    quarantined: dict[str, tuple[Path, Path]],
) -> None:
    conflict: Path | None = None
    for original, quarantine in reversed(list(quarantined.values())):
        if not (quarantine.exists() or quarantine.is_symlink()):
            continue
        if original.exists() or original.is_symlink():
            conflict = original
            continue
        os.replace(quarantine, original)
    if plugin_root.is_dir():
        _fsync_directory(plugin_root)
    if conflict is not None:
        raise TransactionError(
            f"cannot restore quarantined transaction backup: {conflict}"
        )


def _quarantine_recovery_backups(
    plugin_root: Path,
    token: str,
    records: Iterable[dict[str, Any]],
    bindings: list[dict[str, Any]],
    identities: list[dict[str, Any]],
) -> dict[str, tuple[Path, Path]]:
    quarantined: dict[str, tuple[Path, Path]] = {}
    try:
        for record in records:
            plugin_id = str(record["pluginId"])
            _, _, backup = _safe_record_paths(plugin_root, token, record)
            quarantine = plugin_root / (
                f".shibumi-recovery.{token}.{plugin_id}"
            )
            admitted = [
                binding for binding in bindings
                if binding.get("path") in {backup, quarantine}
                and binding.get("exists") is True
                and binding.get("kind") in {"managed", "legacy"}
            ]
            if not admitted:
                if backup.exists() or backup.is_symlink() \
                        or quarantine.exists() or quarantine.is_symlink():
                    raise TransactionError(
                        f"unadmitted transaction backup appeared: {backup}"
                    )
                continue
            if len(admitted) != 1:
                raise TransactionError(
                    f"validated backup authority is ambiguous: {backup}"
                )
            admitted_path = admitted[0]["path"]
            if admitted_path == backup:
                if not (backup.exists() or backup.is_symlink()) \
                        or quarantine.exists() or quarantine.is_symlink():
                    raise TransactionError(
                        f"admitted transaction backup disappeared: {backup}"
                    )
                os.replace(backup, quarantine)
                _fsync_directory(plugin_root)
            elif admitted_path != quarantine \
                    or not (quarantine.exists() or quarantine.is_symlink()) \
                    or backup.exists() or backup.is_symlink():
                raise TransactionError(
                    f"admitted transaction quarantine changed: {quarantine}"
                )
            quarantined[plugin_id] = (backup, quarantine)
            moved_binding = dict(admitted[0])
            moved_binding["path"] = quarantine
            verify_transaction_artifact_bindings([moved_binding], identities)
    except Exception:
        _restore_quarantined_backups(plugin_root, quarantined)
        raise
    return quarantined


def _snapshot_bytes_and_identity(
    path: Path,
    label: str,
    directory: Path,
    *,
    expected_identity: tuple[int, int, str] | None = None,
) -> tuple[bytes, tuple[int, int, str]]:
    try:
        descriptor = os.open(
            path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
        )
    except OSError as error:
        raise TransactionError(
            f"transaction {label} snapshot is missing or unsafe in "
            f"{directory}: {error}"
        ) from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_STATE_BYTES:
            raise TransactionError(
                f"transaction {label} snapshot is malformed or exceeds the "
                f"{MAX_STATE_BYTES}-byte limit: {directory}"
            )
        if expected_identity is not None and (
            before.st_dev != expected_identity[0]
            or before.st_ino != expected_identity[1]
        ):
            raise TransactionError(
                f"transaction {label} snapshot was replaced: {directory}"
            )
        payload = bytearray()
        while len(payload) <= MAX_STATE_BYTES:
            block = os.read(
                descriptor,
                min(65536, MAX_STATE_BYTES + 1 - len(payload)),
            )
            if not block:
                break
            payload.extend(block)
        after = os.fstat(descriptor)
        if (
            len(payload) > MAX_STATE_BYTES
            or len(payload) != after.st_size
            or before.st_dev != after.st_dev
            or before.st_ino != after.st_ino
            or before.st_size != after.st_size
            or before.st_mtime_ns != after.st_mtime_ns
            or before.st_ctime_ns != after.st_ctime_ns
        ):
            raise TransactionError(
                f"transaction {label} snapshot changed or exceeded bounds: "
                f"{directory}"
            )
        result = bytes(payload)
        digest = hashlib.sha256(result).hexdigest()
        if expected_identity is not None and digest != expected_identity[2]:
            raise TransactionError(
                f"transaction {label} snapshot content changed: {directory}"
            )
        return result, (before.st_dev, before.st_ino, digest)
    except OSError as error:
        raise TransactionError(
            f"cannot read transaction {label} snapshot {directory}: {error}"
        ) from error
    finally:
        os.close(descriptor)


def _snapshot_bytes(path: Path, label: str, directory: Path) -> bytes:
    return _snapshot_bytes_and_identity(path, label, directory)[0]


def recover_transactions(
    paths: RuntimePaths,
    runtime: OmarchyRuntime,
    *,
    suite: Suite | None = None,
) -> int:
    validated_inventory: list[dict[str, Any]] | None = None
    if suite is not None:
        # Repeat the all-journal read-only inventory at the recovery boundary
        # and consume those exact parsed/snapshot values below. Recovery must
        # never reparse a different journal after admission.
        validated_inventory = inventory_transactions(
            paths, suite, supported_install_identities(suite)
        )
    root = paths.state_dir / "transactions"
    if root.is_symlink():
        raise TransactionError(f"refusing symlinked transaction root: {root}")
    if not root.exists():
        return 0
    if not root.is_dir():
        raise TransactionError(f"transaction root is not a directory: {root}")
    # Preparation and cleanup directories are never authoritative. Public
    # journals appear only after preparation and disappear atomically before
    # recursive cleanup. When admission is active, bind names and directory
    # inodes before the first discard or recovery mutation.
    validated_by_directory: dict[Path, dict[str, Any]] = {}
    if validated_inventory is not None:
        current = sorted(root.iterdir(), key=lambda item: item.name)
        expected = sorted(
            (item["directory"] for item in validated_inventory),
            key=lambda item: item.name,
        )
        if [item.name for item in current] != [item.name for item in expected]:
            raise TransactionError(
                "transaction inventory changed after lifecycle admission"
            )
        for item, directory in zip(validated_inventory, expected, strict=True):
            metadata = directory.lstat()
            if (
                directory.is_symlink()
                or not directory.is_dir()
                or metadata.st_dev != item["device"]
                or metadata.st_ino != item["inode"]
            ):
                raise TransactionError(
                    f"transaction directory changed after lifecycle admission: {directory}"
                )
            validated_by_directory[directory] = item
        entries = sorted(
            (
                item["directory"]
                for item in validated_inventory
                if item["kind"] == "public"
            ),
            key=lambda item: item.name,
        )
    else:
        all_entries = sorted(root.iterdir())
        for entry in all_entries:
            if entry.is_symlink() or not entry.is_dir():
                raise TransactionError(
                    f"refusing malformed transaction namespace entry: {entry}"
                )
        entries = [
            entry for entry in all_entries
            if not entry.name.startswith((PREPARATION_PREFIX, CLEANUP_PREFIX))
        ]
    recovered = 0
    for directory in entries:
        validated = validated_by_directory.get(directory)
        if validated is not None:
            journal = validated["journal"]
            if not isinstance(journal, dict):
                raise TransactionError(
                    f"validated transaction journal is unavailable: {directory}"
                )
        else:
            journal_file = directory / "journal.json"
            if journal_file.is_symlink() or not journal_file.is_file():
                raise TransactionError(
                    f"transaction journal is missing or unsafe: {directory}"
                )
            try:
                journal = json.loads(journal_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as error:
                raise TransactionError(
                    f"cannot recover transaction {directory}: {error}"
                ) from error
            if not isinstance(journal, dict):
                raise TransactionError(
                    f"transaction journal is not an object: {directory}"
                )
        schema = journal.get("schemaVersion")
        if (
            type(schema) is int
            and schema == 1
            and journal.get("suiteId") == SUITE_ID
            and "configParentIdentity" not in journal
        ):
            raise TransactionError(
                "legacy schema-1 transaction lacks config parent identity; "
                f"recovery is unsafe and the journal was retained: {directory}"
            )
        if (
            journal.get("suiteId") != SUITE_ID
            or type(schema) is not int
            or schema != JOURNAL_SCHEMA_VERSION
        ):
            raise TransactionError(f"refusing unknown transaction journal: {directory}")
        token = str(journal.get("token") or "")
        if directory.name != token:
            raise TransactionError(f"transaction token mismatch: {directory}")
        plugin_root = Path(str(journal.get("pluginRoot") or ""))
        config_path = Path(str(journal.get("configPath") or ""))
        try:
            config_parent_device, config_parent_inode = (
                parse_config_parent_identity(
                    journal.get("configParentIdentity")
                )
            )
        except ValueError as error:
            raise TransactionError(
                f"transaction config parent identity is malformed: {directory}"
            ) from error
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
            admitted_snapshots = validated["snapshots"] if validated else {}
            if config_existed_value:
                config_snapshot_payload = admitted_snapshots.get("config") \
                    if validated else _snapshot_bytes(
                        directory / "shell.json.before", "config", directory
                    )
                if config_snapshot_payload is None:
                    raise TransactionError(
                        f"validated config snapshot is unavailable: {directory}"
                    )
            if menu_extension_value and journal["menuExtensionExisted"]:
                menu_snapshot_payload = admitted_snapshots.get("menu") \
                    if validated else _snapshot_bytes(
                        directory / "omarchy-menu.jsonc.before", "menu", directory
                    )
                if menu_snapshot_payload is None:
                    raise TransactionError(
                        f"validated menu snapshot is unavailable: {directory}"
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

        artifact_bindings: list[dict[str, Any]] = []
        artifact_identities: list[dict[str, Any]] = []
        if validated is not None and suite is not None:
            bindings_value = validated.get("artifacts")
            if not isinstance(bindings_value, list):
                raise TransactionError(
                    f"validated transaction artifacts are unavailable: {directory}"
                )
            artifact_bindings = bindings_value
            artifact_identities = supported_install_identities(suite)
            verify_transaction_artifact_bindings(
                artifact_bindings, artifact_identities
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
            config_parent_fd = _open_verified_config_parent(
                config_path.parent,
                config_parent_device,
                config_parent_inode,
            )
            quarantined: dict[str, tuple[Path, Path]] = {}
            archive_descriptors: tuple[int, int, int] | None = None
            try:
                _require_open_config_parent_identity(
                    config_path.parent,
                    config_parent_device,
                    config_parent_inode,
                    config_parent_fd,
                )
                quarantined = _quarantine_recovery_backups(
                    plugin_root,
                    token,
                    records,
                    artifact_bindings,
                    artifact_identities,
                ) if artifact_bindings else {}
                backup_overrides = {
                    plugin_id: quarantine
                    for plugin_id, (_, quarantine) in quarantined.items()
                }
                archive_descriptors = _open_archive_descriptors(
                    paths, token, artifact_bindings or None
                ) if archive_value else None
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
                    descriptors_for_archive = archive_descriptors
                    archive_descriptors = None
                    _archive_transaction_backups(
                        paths,
                        token,
                        records,
                        backup_overrides,
                        artifact_bindings,
                        artifact_identities,
                        descriptors_for_archive,
                    )
                else:
                    removed_backup = False
                    for record in records:
                        _, _, expected_backup = _safe_record_paths(
                            plugin_root, token, record
                        )
                        backup = backup_overrides.get(
                            str(record["pluginId"]), expected_backup
                        )
                        if backup.exists() or backup.is_symlink():
                            if artifact_bindings:
                                _verify_recovery_backup(
                                    str(record["pluginId"]),
                                    expected_backup,
                                    backup,
                                    artifact_bindings,
                                    artifact_identities,
                                )
                            _remove_path(backup)
                            removed_backup = True
                    if removed_backup:
                        _fsync_directory(plugin_root)
            except Exception:
                if archive_descriptors is not None:
                    for descriptor in reversed(archive_descriptors):
                        os.close(descriptor)
                _restore_quarantined_backups(plugin_root, quarantined)
                raise
            finally:
                os.close(config_parent_fd)
        else:
            restart_on_reconcile = restart_value
            if live_mutation_value is False:
                config_parent_fd = _open_verified_config_parent(
                    config_path.parent,
                    config_parent_device,
                    config_parent_inode,
                )
                try:
                    # No lifecycle path changed yet. In particular, preserve any
                    # config the shell saved between transaction preparation and
                    # its drain instead of replaying the stale initial snapshot.
                    _require_open_config_parent_identity(
                        config_path.parent,
                        config_parent_device,
                        config_parent_inode,
                        config_parent_fd,
                    )
                    _discard_pre_exposure_records(plugin_root, token, records)
                    if restore_requires_drain_value:
                        runtime.stop_shell()
                        _require_open_config_parent_identity(
                            config_path.parent,
                            config_parent_device,
                            config_parent_inode,
                            config_parent_fd,
                        )
                        runtime.reconcile_rollback(
                            restart_required=restart_on_reconcile,
                            shell_was_stopped=True,
                            payload_reload_expected=bool(payload_reload_value),
                        )
                finally:
                    os.close(config_parent_fd)
            else:
                # Atomically move each admitted backup out of its replaceable
                # public name, validate the moved object, and consume only
                # those quarantined objects after all preflights succeed.
                config_parent_fd = _open_verified_config_parent(
                    config_path.parent,
                    config_parent_device,
                    config_parent_inode,
                )
                quarantined: dict[str, tuple[Path, Path]] = {}
                try:
                    quarantined = _quarantine_recovery_backups(
                        plugin_root,
                        token,
                        records,
                        artifact_bindings,
                        artifact_identities,
                    ) if artifact_bindings else {}
                    backup_overrides = {
                        plugin_id: quarantine
                        for plugin_id, (_, quarantine) in quarantined.items()
                    }
                    # A managed transaction keeps restoreRequiresDrain monotonic
                    # after its first stop. A later start may have succeeded even
                    # when shellStopped is false, so re-establish the stopped state
                    # before restoring any live plugin root.
                    if restore_requires_drain_value:
                        _preflight_restore_records(
                            plugin_root, token, records, backup_overrides
                        )
                        runtime.stop_shell()
                        _require_open_config_parent_identity(
                            config_path.parent,
                            config_parent_device,
                            config_parent_inode,
                            config_parent_fd,
                        )
                    _require_open_config_parent_identity(
                        config_path.parent,
                        config_parent_device,
                        config_parent_inode,
                        config_parent_fd,
                    )
                    _restore_records(
                        plugin_root,
                        token,
                        records,
                        backup_overrides,
                        artifact_bindings,
                        artifact_identities,
                    )
                    if config_existed_value:
                        assert config_snapshot_payload is not None
                        _atomic_replace_at(
                            config_parent_fd,
                            config_path.name,
                            config_snapshot_payload,
                        )
                    else:
                        _durable_unlink_at(config_parent_fd, config_path.name)
                except Exception:
                    _restore_quarantined_backups(plugin_root, quarantined)
                    raise
                finally:
                    os.close(config_parent_fd)
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
                        and _config_payload_enables_plugin(
                            config_snapshot_payload,
                            "hancore.shibumi.state",
                        )
                    )
                check = _open_verified_config_parent(
                    config_path.parent, config_parent_device, config_parent_inode
                )
                os.close(check)
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
        check = _open_verified_config_parent(
            config_path.parent, config_parent_device, config_parent_inode
        )
        os.close(check)
        _retire_transaction_directory(root, directory, token)
        recovered += 1
    _discard_private_transactions(root)
    if root.is_dir() and not any(root.iterdir()):
        root.rmdir()
        if paths.state_dir.is_dir():
            _fsync_directory(paths.state_dir)
    return recovered
