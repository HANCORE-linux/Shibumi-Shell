from __future__ import annotations

import hashlib
import json
import math
import os
import re
import stat
from pathlib import Path
from typing import Any

from . import MANAGED_MARKER, STATE_SCHEMA_VERSION, SUITE_ID
from .model import Suite, payload_path_excluded, suite_payload_digest
from .runtime import RuntimePaths


class AdmissionError(RuntimeError):
    pass


MAX_STATE_BYTES = 1024 * 1024
MAX_JOURNAL_BYTES = 4 * 1024 * 1024
MAX_TRANSACTION_ENTRIES = 128
MAX_RECORDS = 256
MAX_PLUGIN_PAYLOAD_ENTRIES = 16384
MAX_PLUGIN_PAYLOAD_BYTES = 64 * 1024 * 1024
PLUGIN_ID_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}")
TRANSACTION_TOKEN_PATTERN = re.compile(r"[0-9]{1,20}-[0-9]{1,20}-[0-9a-f]{8}")
STATE_BASE_KEYS = {
    "schemaVersion",
    "suiteId",
    "suiteVersion",
    "profile",
    "activeBar",
    "plugins",
    "installOrigin",
    "payloadRoot",
    "sourceRevision",
    "payloadDigest",
    "pluginDigests",
    "activation",
    "updatedEpoch",
    "menuExtension",
}
ACTIVATION_KEYS = {
    "activeBar",
    "mode",
    "layoutPolicy",
    "configuredBar",
    "layout",
    "enableServices",
    "continuityPlugins",
}
MARKER_KEYS = {
    "schemaVersion",
    "suiteId",
    "suiteVersion",
    "pluginId",
    "sourceRevision",
    "payloadDigest",
    "suitePayloadDigest",
    "transaction",
}
PRIVATE_PREFIXES = (".shibumi-preparing.", ".shibumi-cleanup.")
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
JOURNAL_KEYS = {
    "schemaVersion",
    "suiteId",
    "token",
    "phase",
    "pluginRoot",
    "configPath",
    "configParentIdentity",
    "configExisted",
    "menuExtensionPath",
    "menuExtensionExisted",
    "restartOnReconcile",
    "shellStopped",
    "restoreRequiresDrain",
    "liveMutationStarted",
    "payloadReloadExpected",
    "records",
    "desiredState",
    "archivePrevious",
}
REQUIRED_JOURNAL_KEYS = {
    "schemaVersion",
    "suiteId",
    "token",
    "phase",
    "pluginRoot",
    "configPath",
    "configParentIdentity",
    "configExisted",
    "menuExtensionPath",
    "menuExtensionExisted",
    "restartOnReconcile",
    "shellStopped",
    "restoreRequiresDrain",
    "liveMutationStarted",
    "payloadReloadExpected",
    "records",
}
RECORD_KEYS = {"action", "pluginId", "target", "stage", "backup", "hadTarget"}
RECORD_BOUND_KEYS = RECORD_KEYS | {"beforePayloadDigest"}
RECORD_ACTIONS = {"replace", "remove", "remove-legacy"}
MAX_FILESYSTEM_ID = (1 << 64) - 1
JOURNAL_SCHEMA_VERSION = 2
LEGACY_JOURNAL_SCHEMA_VERSION = 1


def parse_config_parent_identity(value: Any) -> tuple[int, int]:
    if not isinstance(value, dict) or set(value) != {"device", "inode"}:
        raise ValueError("config parent identity must contain only device and inode")
    device = value.get("device")
    inode = value.get("inode")
    if (
        type(device) is not int
        or type(inode) is not int
        or device < 0
        or inode <= 0
        or device > MAX_FILESYSTEM_ID
        or inode > MAX_FILESYSTEM_ID
    ):
        raise ValueError("config parent device/inode are out of range")
    return device, inode


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON field: {key}")
        value[key] = item
    return value


def _finite_float(value: str) -> float:
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"non-finite JSON number: {value}")
    return result


def _read_json_object(path: Path, *, limit: int, label: str) -> dict[str, Any]:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    except OSError as error:
        raise AdmissionError(f"cannot read {label} {path}: {error}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise AdmissionError(f"{label} is not a regular file: {path}")
        if before.st_size > limit:
            raise AdmissionError(f"{label} exceeds the {limit}-byte limit: {path}")
        payload = bytearray()
        while len(payload) <= limit:
            block = os.read(descriptor, min(65536, limit + 1 - len(payload)))
            if not block:
                break
            payload.extend(block)
        after = os.fstat(descriptor)
        if len(payload) > limit:
            raise AdmissionError(f"{label} exceeds the {limit}-byte limit: {path}")
        if (
            before.st_dev != after.st_dev
            or before.st_ino != after.st_ino
            or before.st_size != after.st_size
            or before.st_mtime_ns != after.st_mtime_ns
            or len(payload) != after.st_size
        ):
            raise AdmissionError(f"{label} changed while being read: {path}")
    finally:
        os.close(descriptor)
    try:
        value = json.loads(
            bytes(payload),
            object_pairs_hook=_reject_duplicates,
            parse_constant=lambda item: (_ for _ in ()).throw(
                ValueError(f"non-finite JSON number: {item}")
            ),
            parse_float=_finite_float,
        )
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError, RecursionError) as error:
        raise AdmissionError(f"{label} is malformed: {path}: {error}") from error
    if not isinstance(value, dict):
        raise AdmissionError(f"{label} is not an object: {path}")
    return value


def _load_predecessors(suite: Suite) -> list[dict[str, Any]]:
    path = suite.root / "contracts/lifecycle-predecessors-v1.json"
    value = _read_json_object(path, limit=MAX_STATE_BYTES, label="predecessor contract")
    states = value.get("states")
    if (
        set(value) != {"schemaVersion", "contractId", "states"}
        or type(value.get("schemaVersion")) is not int
        or value.get("schemaVersion") != 1
        or value.get("contractId") != "hancore.shibumi.lifecycle-predecessors"
        or not isinstance(states, list)
        or len(states) != 2
        or any(not isinstance(item, dict) for item in states)
    ):
        raise AdmissionError(f"invalid lifecycle predecessor contract: {path}")
    expected_keys = {
        "id",
        "suiteVersion",
        "sourceRevisions",
        "payloadDigest",
        "pluginDigests",
        "pluginIds",
    }
    expected_revisions = {
        "public-beta.11": {
            "adbb11068e9c77561ff0c3d1b8fca5212653ae3c",
            "package:0.1.1-beta.11",
        },
        "step-5-tip": {"5154c020a44d71139a6614a183ec91021b9772c1"},
    }
    expected_ids = set(expected_revisions)
    if {item.get("id") for item in states} != expected_ids:
        raise AdmissionError(f"invalid lifecycle predecessor identities: {path}")
    for item in states:
        revisions = item.get("sourceRevisions")
        plugin_ids = item.get("pluginIds")
        plugin_digests = item.get("pluginDigests")
        if (
            set(item) != expected_keys
            or item.get("suiteVersion") != "0.1.1-beta.11"
            or not isinstance(revisions, list)
            or not revisions
            or len(revisions) != len(set(revisions))
            or set(revisions) != expected_revisions.get(str(item.get("id")), set())
            or any(
                not isinstance(revision, str)
                or not re.fullmatch(r"(?:[0-9a-f]{40}|package:0\.1\.1-beta\.11)", revision)
                for revision in revisions
            )
            or not isinstance(plugin_ids, list)
            or len(plugin_ids) != 24
            or len(plugin_ids) != len(set(plugin_ids))
            or any(
                not isinstance(plugin_id, str)
                or not PLUGIN_ID_PATTERN.fullmatch(plugin_id)
                for plugin_id in plugin_ids
            )
            or not isinstance(plugin_digests, dict)
            or set(plugin_digests) != set(plugin_ids)
            or any(
                not isinstance(digest, str)
                or not re.fullmatch(r"[0-9a-f]{64}", digest)
                for digest in plugin_digests.values()
            )
            or item.get("payloadDigest") != suite_payload_digest(plugin_digests)
        ):
            raise AdmissionError(f"invalid lifecycle predecessor identity: {path}")
    return states


def _current_identity(suite: Suite) -> dict[str, Any]:
    plugin_digests = {
        plugin_id: spec.payload_digest()
        for plugin_id, spec in suite.plugins.items()
    }
    return {
        "id": "current-release",
        "suiteVersion": suite.version,
        "sourceRevisions": [suite.revision()],
        "payloadDigest": suite_payload_digest(plugin_digests),
        "pluginDigests": plugin_digests,
        "pluginIds": list(suite.profile("default").install),
    }


def _identity_matches(state: dict[str, Any], identity: dict[str, Any]) -> bool:
    revisions = identity.get("sourceRevisions")
    return bool(
        isinstance(revisions, list)
        and state.get("suiteVersion") == identity.get("suiteVersion")
        and state.get("sourceRevision") in revisions
        and state.get("payloadDigest") == identity.get("payloadDigest")
        and state.get("pluginDigests") == identity.get("pluginDigests")
        and state.get("plugins") == identity.get("pluginIds")
    )


def _validate_activation(state: dict[str, Any], suite: Suite) -> None:
    activation = state.get("activation")
    if not isinstance(activation, dict) or set(activation) != ACTIVATION_KEYS:
        unknown = sorted(set(activation or {}) - ACTIVATION_KEYS) \
            if isinstance(activation, dict) else []
        detail = f": {', '.join(unknown)}" if unknown else ""
        raise AdmissionError(
            "Step-6 or unknown activation metadata is unsupported" + detail
        )
    profile_id = state.get("profile")
    if not isinstance(profile_id, str) or profile_id not in suite.profiles:
        raise AdmissionError("unknown Shibumi installation profile; refusing mutation")
    profile = suite.profile(profile_id)
    continuity = sorted(
        {"hancore.shibumi.control-center", "hancore.shibumi.state"}
    )
    if (
        state.get("activeBar") != profile.active_bar
        or activation.get("activeBar") != profile.active_bar
        or activation.get("enableServices") != list(profile.enable_services)
        or activation.get("continuityPlugins") != continuity
        or not isinstance(activation.get("configuredBar"), str)
        or not PLUGIN_ID_PATTERN.fullmatch(activation["configuredBar"])
    ):
        raise AdmissionError(
            "unknown activation ownership metadata; no recovery or mutation was attempted"
        )
    mode = activation.get("mode")
    policy = activation.get("layoutPolicy")
    layout = activation.get("layout")
    if (
        mode not in {"managed", "external"}
        or policy not in {"managed", "preserved"}
        or (mode == "managed") != (policy == "managed")
        or not isinstance(layout, dict)
        or set(layout) != {"left", "center", "right"}
    ):
        raise AdmissionError(
            "unknown activation mode/layout metadata; refusing mutation"
        )
    for region in ("left", "center", "right"):
        values = layout.get(region)
        if (
            not isinstance(values, list)
            or len(values) > 256
            or any(
                not isinstance(item, str) or not PLUGIN_ID_PATTERN.fullmatch(item)
                for item in values
            )
        ):
            raise AdmissionError("activation layout is malformed or unbounded")
    if mode == "managed" and (
        activation["configuredBar"] != profile.active_bar
        or layout != {
            region: list(profile.layout[region])
            for region in ("left", "center", "right")
        }
    ):
        raise AdmissionError("managed activation layout is not the exact profile layout")


def classify_install_state(
    state: dict[str, Any], suite: Suite, identities: list[dict[str, Any]]
) -> str:
    activation = state.get("activation")
    if isinstance(activation, dict) and "powerRegistration" in activation:
        raise AdmissionError(
            "Step-6 installation state is unsupported by this Beta.12 release; "
            "use the separately reviewed Step-6 rollback procedure"
        )
    if type(state.get("schemaVersion")) is not int \
            or state.get("schemaVersion") != STATE_SCHEMA_VERSION \
            or state.get("suiteId") != SUITE_ID:
        raise AdmissionError("unknown Shibumi installation state; refusing mutation")
    origin = state.get("installOrigin")
    required_keys = set(STATE_BASE_KEYS)
    revision = state.get("sourceRevision")
    if origin == "package":
        required_keys.update({"packageName", "packageVersion"})
    elif origin == "checkout":
        required_keys.add("sourceRoot")
    else:
        raise AdmissionError("installation authority metadata is inconsistent")
    if "settingsStorageVersion" in state:
        if type(state["settingsStorageVersion"]) is not int or state["settingsStorageVersion"] != 1:
            raise AdmissionError("unsupported settings storage migration version")
        required_keys.add("settingsStorageVersion")
    if "previousBar" in state:
        required_keys.add("previousBar")
    if "migratedFrom" in state:
        required_keys.add("migratedFrom")
    if set(state) != required_keys:
        raise AdmissionError(
            "Step-6 or unknown installation metadata is unsupported; refusing mutation"
        )
    if (
        type(state.get("updatedEpoch")) is not int
        or state["updatedEpoch"] < 0
        or not isinstance(state.get("payloadRoot"), str)
        or not Path(state["payloadRoot"]).is_absolute()
        or (
            "previousBar" in state
            and not isinstance(state.get("previousBar"), dict)
        )
        or not isinstance(state.get("menuExtension"), dict)
        or set(state["menuExtension"]) != {"schemaVersion", "createdFile"}
        or type(state["menuExtension"].get("schemaVersion")) is not int
        or state["menuExtension"].get("schemaVersion") != 1
        or type(state["menuExtension"].get("createdFile")) is not bool
    ):
        raise AdmissionError("installation metadata values are malformed")
    if "migratedFrom" in state:
        migrated = state["migratedFrom"]
        if (
            not isinstance(migrated, dict)
            or set(migrated) != {
                "suiteId",
                "suiteVersion",
                "sourceRevision",
                "payloadDigest",
                "migratedEpoch",
            }
            or migrated.get("suiteId") != "hancore.qsrise"
            or (
                migrated.get("suiteVersion") is not None
                and not isinstance(migrated.get("suiteVersion"), str)
            )
            or (
                migrated.get("sourceRevision") is not None
                and not isinstance(migrated.get("sourceRevision"), str)
            )
            or (
                migrated.get("payloadDigest") is not None
                and (
                    not isinstance(migrated.get("payloadDigest"), str)
                    or not re.fullmatch(r"[0-9a-f]{64}", migrated["payloadDigest"])
                )
            )
            or type(migrated.get("migratedEpoch")) is not int
            or migrated["migratedEpoch"] < 0
        ):
            raise AdmissionError("migration continuity metadata is malformed")
    if origin == "package":
        if (
            not isinstance(revision, str)
            or not revision.startswith("package:")
            or state.get("packageName") != "shibumi-shell"
            or state.get("packageVersion") != revision.removeprefix("package:")
        ):
            raise AdmissionError("package installation authority metadata is inconsistent")
    elif (
        not isinstance(state.get("sourceRoot"), str)
        or not Path(state["sourceRoot"]).is_absolute()
        or state["sourceRoot"] != state["payloadRoot"]
        or not isinstance(revision, str)
        or not re.fullmatch(r"[0-9a-f]{40}(?:-dirty)?", revision)
    ):
        raise AdmissionError("checkout installation authority metadata is inconsistent")
    _validate_activation(state, suite)

    matches = [item for item in identities if _identity_matches(state, item)]
    if len(matches) != 1:
        raise AdmissionError(
            "installation revision/digest identity is not an explicitly supported "
            "Beta.11 or Step-5 state; no recovery or mutation was attempted"
        )
    identity = str(matches[0].get("id") or "supported")
    expects_entry_storage = identity == "current-release" and suite.settings_storage_version == 1
    if expects_entry_storage != (state.get("settingsStorageVersion") == 1):
        raise AdmissionError("settings storage version does not match payload identity")
    return identity


def _validate_record(
    record: Any,
    directory: Path,
    token: str,
    paths: RuntimePaths,
    suite: Suite,
) -> str | None:
    if not isinstance(record, dict):
        return f"transaction record is not an object: {directory}"
    if frozenset(record) not in {
        frozenset(RECORD_KEYS),
        frozenset(RECORD_BOUND_KEYS),
    }:
        return f"transaction record schema is unsupported: {directory}"
    plugin_id = record.get("pluginId")
    target_value = record.get("target")
    stage_value = record.get("stage")
    backup_value = record.get("backup")
    if (
        record.get("action") not in RECORD_ACTIONS
        or not isinstance(plugin_id, str)
        or not PLUGIN_ID_PATTERN.fullmatch(plugin_id)
        or not isinstance(target_value, str)
        or not isinstance(stage_value, str)
        or not isinstance(backup_value, str)
        or type(record.get("hadTarget")) is not bool
        or (
            "beforePayloadDigest" in record
            and (
                record["hadTarget"] is not True
                or not isinstance(record["beforePayloadDigest"], str)
                or not re.fullmatch(r"[0-9a-f]{64}", record["beforePayloadDigest"])
            )
        )
    ):
        return f"transaction record values are malformed: {directory}"
    root = paths.plugin_dir.resolve(strict=False)
    target = Path(target_value)
    stage = Path(stage_value) if stage_value else None
    backup = Path(backup_value)
    action = record["action"]
    allowed_ids = {
        "replace": set(suite.plugins),
        "remove": set(suite.retired_plugins),
        "remove-legacy": {
            "hancore.qsrise" + plugin[len("hancore.shibumi"):]
            for plugin in suite.plugins
        },
    }
    expected_target = root / plugin_id
    expected_backup = root / f".shibumi-backup.{token}.{plugin_id}"
    expected_stage = root / f".shibumi-stage.{token}.{plugin_id}"
    if (
        plugin_id not in allowed_ids[action]
        or target != expected_target
        or backup != expected_backup
        or (action == "replace" and stage != expected_stage)
        or (action != "replace" and stage is not None)
        or (action != "replace" and record["hadTarget"] is not True)
        or (
            action == "remove-legacy"
            and not plugin_id.startswith("hancore.qsrise")
        )
        or (
            action in {"replace", "remove"}
            and not plugin_id.startswith("hancore.shibumi")
        )
    ):
        return f"unsafe or inconsistent path/action in transaction record: {directory}"
    return None


def _read_snapshot(path: Path, directory: Path, label: str) -> bytes:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    except OSError as error:
        raise AdmissionError(
            f"transaction {label} snapshot is missing or unsafe in {directory}: {error}"
        ) from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_STATE_BYTES:
            raise AdmissionError(
                f"transaction {label} snapshot is malformed or unbounded: {directory}"
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
        ):
            raise AdmissionError(
                f"transaction {label} snapshot changed or exceeded bounds: {directory}"
            )
        return bytes(payload)
    finally:
        os.close(descriptor)


def _managed_artifact_marker(
    path: Path,
    plugin_id: str,
    identities: list[dict[str, Any]],
    budget: dict[str, int],
    *,
    role: str,
    journal_token: str,
    before_payload_digest: str | None,
) -> dict[str, Any]:
    marker = _read_json_object(
        path / MANAGED_MARKER,
        limit=MAX_STATE_BYTES,
        label="transaction plugin marker",
    )
    matches = [
        identity
        for identity in identities
        if marker.get("suiteVersion") == identity.get("suiteVersion")
        and marker.get("sourceRevision") in identity.get("sourceRevisions", [])
        and marker.get("payloadDigest")
        == identity.get("pluginDigests", {}).get(plugin_id)
        and marker.get("suitePayloadDigest") == identity.get("payloadDigest")
    ]
    marker_transaction = marker.get("transaction")
    marker_digest = str(marker.get("payloadDigest"))
    if role == "backup":
        permitted_digests = {
            before_payload_digest
            if before_payload_digest is not None else marker_digest
        }
    elif marker_transaction == journal_token:
        permitted_digests = {marker_digest}
    else:
        permitted_digests = {
            before_payload_digest
            if before_payload_digest is not None else marker_digest
        }
    actual_digest = _bounded_plugin_payload_digest(path, budget)
    if (
        set(marker) != MARKER_KEYS
        or type(marker.get("schemaVersion")) is not int
        or marker.get("schemaVersion") != STATE_SCHEMA_VERSION
        or marker.get("suiteId") != SUITE_ID
        or marker.get("pluginId") != plugin_id
        or not isinstance(marker_transaction, str)
        or not TRANSACTION_TOKEN_PATTERN.fullmatch(marker_transaction)
        or role not in {"target", "backup"}
        or (role == "backup" and marker_transaction == journal_token)
        or len(matches) != 1
        or actual_digest not in permitted_digests
    ):
        raise AdmissionError(
            f"transaction plugin artifact identity is unsupported: {path}"
        )
    return marker


def _legacy_artifact_is_managed(path: Path, plugin_id: str) -> bool:
    try:
        marker = _read_json_object(
            path / ".qsrise-managed.json",
            limit=MAX_STATE_BYTES,
            label="legacy transaction plugin marker",
        )
    except AdmissionError:
        return False
    return bool(
        type(marker.get("schemaVersion")) is int
        and marker.get("schemaVersion") == STATE_SCHEMA_VERSION
        and marker.get("suiteId") == "hancore.qsrise"
        and marker.get("pluginId") == plugin_id
    )


def verify_transaction_artifact_bindings(
    bindings: list[dict[str, Any]],
    identities: list[dict[str, Any]],
) -> None:
    budget = {"entries": 0, "bytes": 0}
    for binding in bindings:
        path = binding.get("path")
        if not isinstance(path, Path):
            raise AdmissionError("validated transaction artifact binding is malformed")
        exists = path.exists() or path.is_symlink()
        kind = binding.get("kind")
        if kind == "directoryIdentity":
            expected_exists = bool(binding.get("exists"))
            if exists != expected_exists or (
                exists and (path.is_symlink() or not path.is_dir())
            ):
                raise AdmissionError(
                    f"transaction directory identity changed after admission: {path}"
                )
            if exists:
                metadata = path.stat(follow_symlinks=False)
                if metadata.st_dev != binding.get("device") or \
                        metadata.st_ino != binding.get("inode"):
                    raise AdmissionError(
                        f"transaction directory identity changed after admission: {path}"
                    )
            continue
        if kind == "namespace":
            expected_exists = bool(binding.get("exists"))
            if exists != expected_exists or (
                exists and (path.is_symlink() or not path.is_dir())
            ):
                raise AdmissionError(
                    f"transaction artifact namespace changed after admission: {path}"
                )
            prefixes = binding.get("prefixes")
            expected_names = binding.get("names")
            if not isinstance(prefixes, tuple) or not isinstance(expected_names, list):
                raise AdmissionError(
                    "validated transaction namespace binding is malformed"
                )
            names = sorted(
                item.name for item in path.iterdir()
                if any(item.name.startswith(prefix) for prefix in prefixes)
            ) if exists else []
            if names != expected_names:
                raise AdmissionError(
                    f"transaction artifact namespace changed after admission: {path}"
                )
            continue
        expected_exists = bool(binding.get("exists"))
        if exists != expected_exists:
            raise AdmissionError(
                f"transaction artifact changed after admission: {path}"
            )
        if not exists:
            continue
        if path.is_symlink() or not path.is_dir():
            raise AdmissionError(
                f"transaction artifact changed after admission: {path}"
            )
        if kind == "directory":
            continue
        plugin_id = binding.get("pluginId")
        if not isinstance(plugin_id, str):
            raise AdmissionError("validated transaction artifact binding is malformed")
        if kind == "legacy":
            if not _legacy_artifact_is_managed(path, plugin_id) or \
                    _bounded_plugin_payload_digest(path, budget) != \
                    binding.get("payloadDigest"):
                raise AdmissionError(
                    f"transaction artifact changed after admission: {path}"
                )
        elif kind == "managed":
            try:
                marker = _managed_artifact_marker(
                    path,
                    plugin_id,
                    identities,
                    budget,
                    role=str(binding.get("role")),
                    journal_token=str(binding.get("journalToken")),
                    before_payload_digest=binding.get("beforePayloadDigest"),
                )
            except AdmissionError as error:
                raise AdmissionError(
                    f"transaction artifact changed after admission: {path}"
                ) from error
            if marker != binding.get("marker"):
                raise AdmissionError(
                    f"transaction artifact changed after admission: {path}"
                )
        else:
            raise AdmissionError("validated transaction artifact binding is malformed")


def _classify_journal(
    journal: dict[str, Any],
    directory: Path,
    token: str,
    paths: RuntimePaths,
    suite: Suite,
    identities: list[dict[str, Any]],
    artifact_budget: dict[str, int],
    *,
    authoritative: bool,
) -> tuple[list[str], dict[str, bytes], list[dict[str, Any]]]:
    errors: list[str] = []
    snapshots: dict[str, bytes] = {}
    artifact_bindings: list[dict[str, Any]] = []
    schema = journal.get("schemaVersion")
    if (
        type(schema) is int
        and schema == LEGACY_JOURNAL_SCHEMA_VERSION
        and journal.get("suiteId") == SUITE_ID
        and "configParentIdentity" not in journal
    ):
        return ([
            "legacy schema-1 transaction lacks config parent identity; "
            f"recovery is unsafe and the journal was retained: {directory}"
        ], snapshots, artifact_bindings)
    unknown = set(journal) - JOURNAL_KEYS
    missing = REQUIRED_JOURNAL_KEYS - set(journal)
    if unknown:
        errors.append(
            "Step-6 or unknown transaction metadata is unsupported in "
            f"{directory}: {', '.join(sorted(unknown))}"
        )
    if missing:
        errors.append(
            f"transaction journal fields are missing in {directory}: "
            + ", ".join(sorted(missing))
        )
    if errors:
        return errors, snapshots, artifact_bindings
    if type(schema) is not int \
            or schema != JOURNAL_SCHEMA_VERSION \
            or journal.get("suiteId") != SUITE_ID:
        errors.append(f"unknown transaction journal schema: {directory}")
    if journal.get("token") != token:
        errors.append(f"transaction token mismatch: {directory}")
    phase_value = journal.get("phase")
    phase = phase_value if isinstance(phase_value, str) else ""
    if not phase or phase not in COMMIT_PHASES | ROLLBACK_PHASES:
        errors.append(f"Step-6 or unknown transaction phase is unsupported: {directory}")
    for name in (
        "configExisted",
        "restartOnReconcile",
        "menuExtensionExisted",
        "shellStopped",
        "restoreRequiresDrain",
        "liveMutationStarted",
        "payloadReloadExpected",
    ):
        if name in journal and type(journal[name]) is not bool:
            errors.append(f"transaction {name} is malformed: {directory}")
    if Path(str(journal.get("pluginRoot") or "")).resolve(strict=False) \
            != paths.plugin_dir.resolve(strict=False):
        errors.append(f"transaction plugin path mismatch: {directory}")
    if Path(str(journal.get("configPath") or "")).resolve(strict=False) \
            != paths.config_file.resolve(strict=False):
        errors.append(f"transaction config path mismatch: {directory}")
    try:
        parse_config_parent_identity(journal.get("configParentIdentity"))
    except ValueError:
        errors.append(
            f"transaction config parent identity is malformed: {directory}"
        )
    menu_path = journal.get("menuExtensionPath")
    if (
        not isinstance(menu_path, str)
        or Path(menu_path).resolve(strict=False)
        != paths.menu_extension_file.resolve(strict=False)
    ):
        errors.append(f"transaction menu path mismatch: {directory}")
    validated_records: list[dict[str, Any]] = []
    commit_topology: dict[str, tuple[bool, bool, bool]] = {}
    records = journal.get("records")
    if not isinstance(records, list) or len(records) > MAX_RECORDS:
        errors.append(f"transaction records are malformed or unbounded: {directory}")
    else:
        seen_plugin_ids: set[str] = set()
        seen_paths: set[str] = set()
        for record in records:
            error = _validate_record(record, directory, token, paths, suite)
            if error:
                errors.append(error)
                continue
            validated_records.append(record)
            plugin_id = str(record["pluginId"])
            record_paths = {
                str(record["target"]),
                str(record["backup"]),
                *([str(record["stage"])] if record["stage"] else []),
            }
            if plugin_id in seen_plugin_ids or seen_paths.intersection(record_paths):
                errors.append(f"duplicate transaction record authority: {directory}")
            seen_plugin_ids.add(plugin_id)
            seen_paths.update(record_paths)
        if authoritative and phase in ROLLBACK_PHASES | COMMIT_PHASES:
            for record in validated_records:
                plugin_id = str(record["pluginId"])
                target = Path(str(record["target"]))
                stage = Path(str(record["stage"])) if record["stage"] else None
                backup = Path(str(record["backup"]))
                quarantine = paths.plugin_dir / (
                    f".shibumi-recovery.{token}.{plugin_id}"
                )
                discard = paths.plugin_dir / (
                    f".shibumi-discard.{token}.{plugin_id}"
                )
                target_exists = target.exists() or target.is_symlink()
                backup_exists = backup.exists() or backup.is_symlink()
                quarantine_exists = quarantine.exists() or quarantine.is_symlink()
                discard_exists = discard.exists() or discard.is_symlink()
                effective_backup = quarantine if quarantine_exists else backup
                effective_backup_exists = backup_exists or quarantine_exists
                stage_exists = bool(
                    stage and (stage.exists() or stage.is_symlink())
                )
                commit_topology[plugin_id] = (
                    target_exists,
                    effective_backup_exists,
                    stage_exists,
                )
                if (
                    target.is_symlink()
                    or backup.is_symlink()
                    or (stage is not None and stage.is_symlink())
                    or (target_exists and not target.is_dir())
                    or (backup_exists and not backup.is_dir())
                    or (quarantine_exists and (
                        quarantine.is_symlink() or not quarantine.is_dir()
                    ))
                    or (discard_exists and (
                        discard.is_symlink() or not discard.is_dir()
                    ))
                    or (stage_exists and stage is not None and not stage.is_dir())
                    or (backup_exists and quarantine_exists)
                ):
                    errors.append(
                        f"transaction plugin artifact is unsafe: {directory}"
                    )
                    continue
                target_marker: dict[str, Any] | None = None
                before_digest = record.get("beforePayloadDigest")
                bound_digest = before_digest \
                    if isinstance(before_digest, str) else None
                try:
                    if target_exists:
                        if record["action"] == "remove-legacy":
                            if not _legacy_artifact_is_managed(target, plugin_id):
                                raise AdmissionError(
                                    f"legacy transaction target is unmanaged: {target}"
                                )
                            target_digest = _bounded_plugin_payload_digest(
                                target, artifact_budget
                            )
                            if bound_digest is not None and \
                                    target_digest != bound_digest:
                                raise AdmissionError(
                                    f"legacy transaction target changed: {target}"
                                )
                            artifact_bindings.append({
                                "path": target,
                                "exists": True,
                                "kind": "legacy",
                                "pluginId": plugin_id,
                                "role": "target",
                                "payloadDigest": target_digest,
                            })
                        else:
                            target_marker = _managed_artifact_marker(
                                target,
                                plugin_id,
                                identities,
                                artifact_budget,
                                role="target",
                                journal_token=token,
                                before_payload_digest=bound_digest,
                            )
                            artifact_bindings.append({
                                "path": target,
                                "exists": True,
                                "kind": "managed",
                                "pluginId": plugin_id,
                                "role": "target",
                                "journalToken": token,
                                "beforePayloadDigest": bound_digest,
                                "marker": target_marker,
                            })
                    if effective_backup_exists:
                        if record["action"] == "remove-legacy":
                            if not _legacy_artifact_is_managed(
                                effective_backup, plugin_id
                            ):
                                raise AdmissionError(
                                    f"legacy transaction backup is unmanaged: {effective_backup}"
                                )
                            backup_digest = _bounded_plugin_payload_digest(
                                effective_backup, artifact_budget
                            )
                            if bound_digest is not None and \
                                    backup_digest != bound_digest:
                                raise AdmissionError(
                                    f"legacy transaction backup changed: {effective_backup}"
                                )
                            artifact_bindings.append({
                                "path": effective_backup,
                                "exists": True,
                                "kind": "legacy",
                                "pluginId": plugin_id,
                                "role": "backup",
                                "payloadDigest": backup_digest,
                            })
                        else:
                            backup_marker = _managed_artifact_marker(
                                effective_backup,
                                plugin_id,
                                identities,
                                artifact_budget,
                                role="backup",
                                journal_token=token,
                                before_payload_digest=bound_digest,
                            )
                            artifact_bindings.append({
                                "path": effective_backup,
                                "exists": True,
                                "kind": "managed",
                                "pluginId": plugin_id,
                                "role": "backup",
                                "journalToken": token,
                                "beforePayloadDigest": bound_digest,
                                "marker": backup_marker,
                            })
                    if discard_exists:
                        if phase not in ROLLBACK_PHASES \
                                or record["action"] != "replace":
                            raise AdmissionError(
                                f"transaction rollback discard is unexpected: {discard}"
                            )
                        discard_marker = _managed_artifact_marker(
                            discard,
                            plugin_id,
                            identities,
                            artifact_budget,
                            role="target",
                            journal_token=token,
                            before_payload_digest=None,
                        )
                        if discard_marker.get("transaction") != token:
                            raise AdmissionError(
                                f"transaction rollback discard is not current: {discard}"
                            )
                        artifact_bindings.append({
                            "path": discard,
                            "exists": True,
                            "kind": "managed",
                            "pluginId": plugin_id,
                            "role": "target",
                            "journalToken": token,
                            "beforePayloadDigest": None,
                            "marker": discard_marker,
                        })
                except AdmissionError as error:
                    errors.append(str(error))
                    continue
                paths_and_existence = [
                    (target, target_exists),
                    (backup, backup_exists),
                    (quarantine, quarantine_exists),
                    (discard, discard_exists),
                ]
                if stage is not None:
                    paths_and_existence.append((stage, stage_exists))
                for artifact_path, exists in paths_and_existence:
                    if not exists:
                        artifact_bindings.append({
                            "path": artifact_path,
                            "exists": False,
                            "kind": "absent",
                        })
                if stage_exists and stage is not None:
                    artifact_bindings.append({
                        "path": stage,
                        "exists": True,
                        "kind": "directory",
                    })
                if phase in ROLLBACK_PHASES and bool(record["hadTarget"]):
                    if not effective_backup_exists and (
                        not target_exists
                        or (
                            target_marker is not None
                            and target_marker.get("transaction") == token
                        )
                    ):
                        errors.append(
                            f"transaction backup is missing for exposed target: {target}"
                        )
                elif not bool(record["hadTarget"]) and effective_backup_exists:
                    errors.append(
                        f"transaction has an impossible backup for new target: {backup}"
                    )
                if phase in ROLLBACK_PHASES and discard_exists and (
                    (effective_backup_exists and target_exists)
                    or (
                        not effective_backup_exists
                        and target_exists
                        and target_marker is not None
                        and target_marker.get("transaction") == token
                    )
                ):
                    errors.append(
                        f"transaction rollback discard topology is inconsistent: {plugin_id}"
                    )
                if phase in COMMIT_PHASES and (
                    stage_exists
                    or discard_exists
                    or (record["action"] != "replace" and target_exists)
                ):
                    errors.append(
                        f"committing transaction has unexposed live artifacts: {directory}"
                    )
    if journal.get("liveMutationStarted") is False \
            and phase not in PRE_EXPOSURE_PHASES:
        errors.append(f"transaction pre-exposure phase is inconsistent: {directory}")
    if authoritative and phase in ROLLBACK_PHASES:
        if journal.get("configExisted") is True:
            try:
                snapshots["config"] = _read_snapshot(
                    directory / "shell.json.before", directory, "config"
                )
            except AdmissionError as error:
                errors.append(str(error))
        if journal.get("menuExtensionPath") \
                and journal.get("menuExtensionExisted") is True:
            try:
                snapshots["menu"] = _read_snapshot(
                    directory / "omarchy-menu.jsonc.before", directory, "menu"
                )
            except AdmissionError as error:
                errors.append(str(error))
    if phase in COMMIT_PHASES:
        archive_value = journal.get("archivePrevious")
        if type(archive_value) is not bool:
            errors.append(f"transaction archive intent is malformed: {directory}")
        archive_root = paths.state_dir / "backups"
        archive_directory = archive_root / token
        for archive_path in (paths.state_dir, archive_root, archive_directory):
            archive_exists = archive_path.exists() or archive_path.is_symlink()
            archive_binding: dict[str, Any] = {
                "path": archive_path,
                "exists": archive_exists,
                "kind": "directoryIdentity",
            }
            if archive_exists and not archive_path.is_symlink() \
                    and archive_path.is_dir():
                archive_metadata = archive_path.stat(follow_symlinks=False)
                archive_binding.update({
                    "device": archive_metadata.st_dev,
                    "inode": archive_metadata.st_ino,
                })
            artifact_bindings.append(archive_binding)
        if (
            archive_root.is_symlink()
            or archive_directory.is_symlink()
            or (archive_root.exists() and not archive_root.is_dir())
            or (archive_directory.exists() and not archive_directory.is_dir())
        ):
            errors.append(
                f"transaction archive namespace is unsafe: {archive_directory}"
            )
        else:
            declared_archive_names = {
                name
                for record in validated_records
                for name in (
                    str(record["pluginId"]),
                    f'.{record["pluginId"]}.partial',
                )
            }
            archive_names = (
                sorted(item.name for item in archive_directory.iterdir())
                if archive_directory.is_dir() else []
            )
            artifact_bindings.append({
                "path": archive_directory,
                "exists": archive_directory.is_dir(),
                "kind": "namespace",
                "prefixes": ("",),
                "names": archive_names,
            })
            if archive_directory.is_dir():
                unknown_archive_names = set(archive_names) - declared_archive_names
                if unknown_archive_names:
                    errors.append(
                        f"transaction archive contains undeclared artifacts: {archive_directory}"
                    )
            for record in validated_records:
                plugin_id = str(record["pluginId"])
                archived = archive_directory / plugin_id
                partial = archive_directory / f".{plugin_id}.partial"
                archived_exists = archived.exists() or archived.is_symlink()
                partial_exists = partial.exists() or partial.is_symlink()
                if (
                    archived.is_symlink()
                    or partial.is_symlink()
                    or (archived_exists and not archived.is_dir())
                    or (partial_exists and not partial.is_dir())
                    or (archive_value is not True and (archived_exists or partial_exists))
                ):
                    errors.append(
                        f"transaction archive artifact is unsafe: {archived}"
                    )
                    continue
                if archived_exists:
                    before_digest = record.get("beforePayloadDigest")
                    bound_digest = before_digest \
                        if isinstance(before_digest, str) else None
                    try:
                        if record["action"] == "remove-legacy":
                            if not _legacy_artifact_is_managed(archived, plugin_id):
                                raise AdmissionError(
                                    f"legacy transaction archive is unmanaged: {archived}"
                                )
                            archived_digest = _bounded_plugin_payload_digest(
                                archived, artifact_budget
                            )
                            if bound_digest is not None and \
                                    archived_digest != bound_digest:
                                raise AdmissionError(
                                    f"legacy transaction archive changed: {archived}"
                                )
                            artifact_bindings.append({
                                "path": archived,
                                "exists": True,
                                "kind": "legacy",
                                "pluginId": plugin_id,
                                "role": "backup",
                                "payloadDigest": archived_digest,
                            })
                        else:
                            archived_marker = _managed_artifact_marker(
                                archived,
                                plugin_id,
                                identities,
                                artifact_budget,
                                role="backup",
                                journal_token=token,
                                before_payload_digest=bound_digest,
                            )
                            artifact_bindings.append({
                                "path": archived,
                                "exists": True,
                                "kind": "managed",
                                "pluginId": plugin_id,
                                "role": "backup",
                                "journalToken": token,
                                "beforePayloadDigest": bound_digest,
                                "marker": archived_marker,
                            })
                    except AdmissionError as error:
                        errors.append(str(error))
                if not archived_exists:
                    artifact_bindings.append({
                        "path": archived,
                        "exists": False,
                        "kind": "absent",
                    })
                artifact_bindings.append({
                    "path": partial,
                    "exists": partial_exists,
                    "kind": "directory" if partial_exists else "absent",
                })
                _, source_backup_exists, _ = commit_topology.get(
                    plugin_id, (False, False, False)
                )
                had_target = bool(record["hadTarget"])
                if phase in COMMIT_PHASES and archive_value is True and (
                    (had_target and not (source_backup_exists or archived_exists))
                    or (partial_exists and not source_backup_exists)
                ):
                    errors.append(
                        f"committing transaction archive topology is incomplete: {plugin_id}"
                    )
                if not had_target and (
                    source_backup_exists or archived_exists or partial_exists
                ):
                    errors.append(
                        f"transaction has backup artifacts for a new target: {plugin_id}"
                    )
        transaction_prefixes = (
            f".shibumi-stage.{token}.",
            f".shibumi-backup.{token}.",
            f".shibumi-recovery.{token}.",
            f".shibumi-discard.{token}.",
        )
        if paths.plugin_dir.is_dir():
            declared_transaction_entries = {
                Path(str(record[key])).name
                for record in validated_records
                for key in ("stage", "backup")
                if record[key]
            } | {
                name
                for record in validated_records
                for name in (
                    f'.shibumi-recovery.{token}.{record["pluginId"]}',
                    f'.shibumi-discard.{token}.{record["pluginId"]}',
                )
            }
            transaction_names: list[str] = []
            managed_names: list[str] = []
            for artifact in paths.plugin_dir.iterdir():
                if artifact.name.startswith(transaction_prefixes):
                    transaction_names.append(artifact.name)
                    if artifact.name not in declared_transaction_entries:
                        errors.append(
                            f"transaction plugin root contains undeclared artifacts: {artifact}"
                        )
                if artifact.name.startswith("hancore.shibumi"):
                    managed_names.append(artifact.name)
            artifact_bindings.extend((
                {
                    "path": paths.plugin_dir,
                    "exists": True,
                    "kind": "namespace",
                    "prefixes": transaction_prefixes,
                    "names": sorted(transaction_names),
                },
                {
                    "path": paths.plugin_dir,
                    "exists": True,
                    "kind": "namespace",
                    "prefixes": ("hancore.shibumi",),
                    "names": sorted(managed_names),
                },
            ))
        else:
            artifact_bindings.append({
                "path": paths.plugin_dir,
                "exists": False,
                "kind": "namespace",
                "prefixes": transaction_prefixes,
                "names": [],
            })
        desired = journal.get("desiredState", "missing")
        if desired != "missing" and desired is not None and isinstance(desired, dict):
            try:
                classify_install_state(desired, suite, identities)
                _validate_live_markers(paths, desired)
                declared_exposed_targets = {
                    str(record["target"])
                    for record in validated_records
                    if record["action"] == "replace"
                }
                for plugin_id in desired["plugins"]:
                    target = paths.plugin_dir / plugin_id
                    marker = _managed_artifact_marker(
                        target,
                        plugin_id,
                        identities,
                        artifact_budget,
                        role="target",
                        journal_token=token,
                        before_payload_digest=None,
                    )
                    artifact_bindings.append({
                        "path": target,
                        "exists": True,
                        "kind": "managed",
                        "pluginId": plugin_id,
                        "role": "target",
                        "journalToken": token,
                        "beforePayloadDigest": None,
                        "marker": marker,
                    })
                    if marker.get("transaction") == token and \
                            str(target) not in declared_exposed_targets:
                        raise AdmissionError(
                            f"committing transaction has an undeclared exposed target: {target}"
                        )
            except AdmissionError as error:
                errors.append(
                    f"unsupported transaction desired/live state in {directory}: {error}"
                )
        elif desired != "missing" and desired is None:
            try:
                _validate_live_markers(paths, None)
            except AdmissionError as error:
                errors.append(
                    f"unsupported transaction uninstalled live state in {directory}: {error}"
                )
        else:
            errors.append(f"transaction desired state is malformed: {directory}")
    elif "desiredState" in journal or "archivePrevious" in journal:
        errors.append(f"rollback journal contains commit-only metadata: {directory}")
    return errors, snapshots, artifact_bindings


def inventory_transactions(
    paths: RuntimePaths, suite: Suite, identities: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    root = paths.state_dir / "transactions"
    if not root.exists() and not root.is_symlink():
        return []
    if root.is_symlink() or not root.is_dir():
        raise AdmissionError(f"transaction root is missing or unsafe: {root}")
    entries = sorted(root.iterdir(), key=lambda item: item.name)
    if len(entries) > MAX_TRANSACTION_ENTRIES:
        raise AdmissionError("transaction inventory exceeds the supported bound")

    errors: list[str] = []
    classified: list[dict[str, Any]] = []
    artifact_budget = {"entries": 0, "bytes": 0}
    for directory in entries:
        private_prefix = next(
            (prefix for prefix in PRIVATE_PREFIXES if directory.name.startswith(prefix)),
            None,
        )
        token = directory.name[len(private_prefix):] if private_prefix else directory.name
        if (
            directory.is_symlink()
            or not directory.is_dir()
            or not TRANSACTION_TOKEN_PATTERN.fullmatch(token)
        ):
            errors.append(f"malformed transaction namespace entry: {directory}")
            continue
        metadata = directory.lstat()
        journal_file = directory / "journal.json"
        if not journal_file.exists() and not journal_file.is_symlink():
            if private_prefix:
                classified.append({
                    "kind": "private",
                    "directory": directory,
                    "device": metadata.st_dev,
                    "inode": metadata.st_ino,
                    "journal": None,
                    "snapshots": {},
                    "artifacts": [],
                })
                continue
            errors.append(f"transaction journal is missing: {directory}")
            continue
        try:
            journal = _read_json_object(
                journal_file, limit=MAX_JOURNAL_BYTES, label="transaction journal"
            )
        except AdmissionError as error:
            errors.append(str(error))
            continue
        journal_errors, snapshots, artifact_bindings = _classify_journal(
            journal,
            directory,
            token,
            paths,
            suite,
            identities,
            artifact_budget,
            authoritative=private_prefix is None,
        )
        errors.extend(journal_errors)
        classified.append({
            "kind": "private" if private_prefix else "public",
            "directory": directory,
            "device": metadata.st_dev,
            "inode": metadata.st_ino,
            "journal": journal,
            "snapshots": snapshots,
            "artifacts": artifact_bindings,
        })
    public_count = sum(item["kind"] == "public" for item in classified)
    if public_count > 1:
        errors.append(
            "multiple authoritative transaction journals are ambiguous"
        )
    if errors:
        raise AdmissionError(
            "transaction inventory contains unsupported state; no journal was "
            "recovered or discarded:\n  - " + "\n  - ".join(errors)
        )
    return classified


def _bounded_plugin_payload_digest(
    directory: Path,
    budget: dict[str, int],
) -> str:
    if directory.is_symlink() or not directory.is_dir():
        raise AdmissionError(f"plugin payload is not a real directory: {directory}")
    files: list[tuple[str, Path, os.stat_result]] = []
    pending = [directory]
    try:
        while pending:
            current = pending.pop()
            with os.scandir(current) as entries:
                for entry in entries:
                    path = Path(entry.path)
                    relative = path.relative_to(directory).as_posix()
                    metadata = entry.stat(follow_symlinks=False)
                    budget["entries"] += 1
                    if budget["entries"] > MAX_PLUGIN_PAYLOAD_ENTRIES:
                        raise AdmissionError(
                            "installed plugin payload entry inventory is unbounded"
                        )
                    if payload_path_excluded(relative):
                        continue
                    if stat.S_ISLNK(metadata.st_mode):
                        raise AdmissionError(
                            f"installed plugin payload contains a symlink: {path}"
                        )
                    if stat.S_ISDIR(metadata.st_mode):
                        pending.append(path)
                    elif stat.S_ISREG(metadata.st_mode):
                        budget["bytes"] += metadata.st_size
                        if budget["bytes"] > MAX_PLUGIN_PAYLOAD_BYTES:
                            raise AdmissionError(
                                "installed plugin payload byte inventory is unbounded"
                            )
                        files.append((relative, path, metadata))
                    else:
                        raise AdmissionError(
                            f"installed plugin payload contains a special file: {path}"
                        )
    except OSError as error:
        raise AdmissionError(
            f"cannot inventory installed plugin payload {directory}: {error}"
        ) from error

    digest = hashlib.sha256()
    digest.update(b"shibumi-plugin-payload-v1\0")
    for relative, path, expected in sorted(files):
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
        except OSError as error:
            raise AdmissionError(
                f"cannot open installed plugin payload file {path}: {error}"
            ) from error
        try:
            before = os.fstat(descriptor)
            if (
                before.st_dev != expected.st_dev
                or before.st_ino != expected.st_ino
                or before.st_size != expected.st_size
                or not stat.S_ISREG(before.st_mode)
            ):
                raise AdmissionError(
                    f"installed plugin payload changed during inventory: {path}"
                )
            digest.update(b"file\0")
            digest.update(relative.encode("utf-8"))
            digest.update(b"\0")
            digest.update(f"{before.st_mode & 0o111:o}".encode("ascii"))
            digest.update(b"\0")
            remaining = before.st_size
            while remaining:
                block = os.read(descriptor, min(1024 * 1024, remaining))
                if not block:
                    raise AdmissionError(
                        f"installed plugin payload changed while being read: {path}"
                    )
                remaining -= len(block)
                digest.update(block)
            if os.read(descriptor, 1):
                raise AdmissionError(
                    f"installed plugin payload grew while being read: {path}"
                )
            after = os.fstat(descriptor)
            if (
                before.st_dev != after.st_dev
                or before.st_ino != after.st_ino
                or before.st_size != after.st_size
                or before.st_mtime_ns != after.st_mtime_ns
            ):
                raise AdmissionError(
                    f"installed plugin payload changed while being read: {path}"
                )
            digest.update(b"\0")
        finally:
            os.close(descriptor)
    return digest.hexdigest()


def _validate_live_markers(
    paths: RuntimePaths,
    state: dict[str, Any] | None,
    *,
    allow_payload_repair: bool = False,
) -> None:
    if paths.plugin_dir.is_symlink():
        raise AdmissionError(f"managed plugin root is symlinked: {paths.plugin_dir}")
    if not paths.plugin_dir.exists():
        if state is None:
            return
        raise AdmissionError(f"managed plugin root is missing: {paths.plugin_dir}")
    if not paths.plugin_dir.is_dir():
        raise AdmissionError(f"managed plugin root is unsafe: {paths.plugin_dir}")
    expected = set(state.get("plugins", [])) if state else set()
    plugin_digests = state.get("pluginDigests", {}) if state else {}
    budget = {"entries": 0, "bytes": 0}
    observed: set[str] = set()
    for target in sorted(paths.plugin_dir.iterdir(), key=lambda item: item.name):
        plugin_id = target.name
        if not plugin_id.startswith("hancore.shibumi"):
            continue
        observed.add(plugin_id)
        if state is None or plugin_id not in expected:
            raise AdmissionError(
                f"unknown Shibumi plugin exists without supported state: {target}"
            )
        if target.is_symlink() or not target.is_dir():
            raise AdmissionError(f"managed plugin target is unsafe: {target}")
        marker_path = target / MANAGED_MARKER
        if not marker_path.exists() and not marker_path.is_symlink():
            raise AdmissionError(f"managed plugin marker is missing: {target}")
        marker = _read_json_object(
            marker_path, limit=MAX_STATE_BYTES, label="managed plugin marker"
        )
        actual_digest = _bounded_plugin_payload_digest(target, budget)
        if (
            set(marker) != MARKER_KEYS
            or type(marker.get("schemaVersion")) is not int
            or marker.get("schemaVersion") != STATE_SCHEMA_VERSION
            or marker.get("suiteId") != SUITE_ID
            or marker.get("pluginId") != plugin_id
            or marker.get("suiteVersion") != state.get("suiteVersion")
            or marker.get("sourceRevision") != state.get("sourceRevision")
            or marker.get("payloadDigest") != plugin_digests.get(plugin_id)
            or marker.get("suitePayloadDigest") != state.get("payloadDigest")
            or not isinstance(marker.get("transaction"), str)
            or not TRANSACTION_TOKEN_PATTERN.fullmatch(marker["transaction"])
            or (
                not allow_payload_repair
                and actual_digest != plugin_digests.get(plugin_id)
            )
        ):
            raise AdmissionError(
                "live plugin marker or payload does not match the admitted installation "
                f"identity (possible Step-6 or interrupted foreign state): {target}"
            )
    if state is not None and observed != expected and not allow_payload_repair:
        missing = ", ".join(sorted(expected - observed))
        raise AdmissionError(
            f"managed plugin inventory is incomplete: {missing or 'unknown drift'}"
        )


def supported_install_identities(suite: Suite) -> list[dict[str, Any]]:
    return _load_predecessors(suite) + [_current_identity(suite)]


def preflight_lifecycle_state(
    paths: RuntimePaths,
    suite: Suite,
    *,
    allow_pending_recovery: bool = False,
    allow_payload_repair: bool = False,
) -> str:
    identities = supported_install_identities(suite)
    # Inventory every journal before recovery is allowed to act on any one of
    # them, including private preparation/cleanup directories.
    transactions = inventory_transactions(paths, suite, identities)
    public_transactions = [
        item for item in transactions if item["kind"] == "public"
    ]
    if public_transactions and not allow_pending_recovery:
        raise AdmissionError(
            "an admitted interrupted transaction requires recovery before status"
        )

    state_path = paths.state_dir / "install.json"
    state: dict[str, Any] | None = None
    classification = "fresh"
    if state_path.exists() or state_path.is_symlink():
        state = _read_json_object(
            state_path, limit=MAX_STATE_BYTES, label="Shibumi install state"
        )
        classification = classify_install_state(state, suite, identities)
    # An admitted public journal can explain target/state drift after an
    # exposure rename. The mutating CLI consumes that validated journal, then
    # repeats this complete live-state check before executing the requested
    # command.
    if not public_transactions:
        _validate_live_markers(
            paths,
            state,
            allow_payload_repair=allow_payload_repair,
        )
    return classification
