from __future__ import annotations

import copy
import json
import math
import os
import tempfile
from pathlib import Path
from typing import Any, Callable

from .model import PluginSpec, ProfileSpec


REGIONS = ("left", "center", "right")
LEGACY_PLUGIN_PREFIX = "hancore.qsrise"
PLUGIN_PREFIX = "hancore.shibumi"
OMARCHY_PLUGIN_PREFIX = "omarchy."
IDENTITY_VERSION = 3
STATE_PLUGIN_ID = "hancore.shibumi.state"
STATE_STORAGE_SCHEMA = "shibumiStateSchemaVersion"


class ConfigError(RuntimeError):
    pass


def _object(value: Any) -> dict[str, Any]:
    return copy.deepcopy(value) if isinstance(value, dict) else {}


def _array(value: Any) -> list[Any]:
    return copy.deepcopy(value) if isinstance(value, list) else []


def entry_id(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return str(value.get("id") or "")
    return ""


def _migrated_identifier(value: str) -> str:
    if value == LEGACY_PLUGIN_PREFIX or value.startswith(LEGACY_PLUGIN_PREFIX + "."):
        return PLUGIN_PREFIX + value[len(LEGACY_PLUGIN_PREFIX):]
    return value


def _migrated_value(value: Any) -> Any:
    if isinstance(value, dict):
        migrated: dict[str, Any] = {}
        for key, item in value.items():
            next_key = _migrated_identifier(key) if isinstance(key, str) else key
            if next_key in migrated:
                raise ConfigError(
                    f"legacy configuration collides after migration: {next_key}"
                )
            migrated[next_key] = _migrated_value(item)
        return migrated
    if isinstance(value, list):
        return [_migrated_value(item) for item in value]
    if isinstance(value, str):
        return _migrated_identifier(value)
    return copy.deepcopy(value)


def migrate_legacy_config(config: dict[str, Any]) -> dict[str, Any]:
    """Move the private QS Rise namespace to Shibumi without losing settings."""
    result = _normalize(config)
    bar = result["bar"]

    if "qsrise" in bar and "shibumi" in bar:
        raise ConfigError(
            "shell config contains both bar.qsrise and bar.shibumi; "
            "refusing an ambiguous migration"
        )
    if "qsrise" in bar:
        bar["shibumi"] = _migrated_value(bar.pop("qsrise"))

    if isinstance(bar.get("id"), str):
        bar["id"] = _migrated_identifier(bar["id"])
    if isinstance(bar.get("centerAnchor"), str):
        bar["centerAnchor"] = _migrated_identifier(bar["centerAnchor"])
    if bar.get("style") == "qsrise":
        bar["style"] = "shibumi"

    for region in REGIONS:
        bar["layout"][region] = [
            _migrated_value(entry) for entry in bar["layout"][region]
        ]
    result["plugins"] = [_migrated_value(entry) for entry in result["plugins"]]
    return result


def validate_state_envelope(config: dict[str, Any]) -> None:
    """Match the runtime's shell envelope before any normalizing migration."""
    if (not isinstance(config, dict) or type(config.get("version")) not in (int, float)
            or config["version"] != 1 or not isinstance(config.get("plugins"), list)
            or len(config["plugins"]) > 512 or not isinstance(config.get("bar"), dict)
            or not isinstance(config["bar"].get("layout"), dict)
            or any(not isinstance(config["bar"]["layout"].get(region), list) for region in REGIONS)):
        raise ConfigError("invalid canonical State shell envelope")


def state_entry(config: dict[str, Any]) -> dict[str, Any] | None:
    entries = config.get("plugins", [])
    if not isinstance(entries, list):
        raise ConfigError("invalid plugins array")
    matches = [entry for entry in entries if entry_id(entry) == STATE_PLUGIN_ID]
    if len(matches) > 1 or (matches and not isinstance(matches[0], dict)):
        raise ConfigError("ambiguous State service entry")
    if matches and (STATE_STORAGE_SCHEMA in matches[0] or "shibumi" in matches[0]):
        validate_state_envelope(config)
    bar = config.get("bar", {})
    if not isinstance(bar, dict) or not isinstance(bar.get("layout", {}), dict):
        raise ConfigError("invalid bar layout")
    layout = bar.get("layout", {})
    if any(not isinstance(layout.get(region, []), list) for region in REGIONS):
        raise ConfigError("invalid bar layout region")
    if any(entry_id(entry) == STATE_PLUGIN_ID
           for region in REGIONS for entry in layout.get(region, [])):
        raise ConfigError("State service must not be a bar layout entry")
    return matches[0] if matches else None


def validate_state_settings(config: dict[str, Any]) -> dict[str, Any]:
    """Validate canonical storage without creating, normalizing or migrating it."""
    validate_state_envelope(config)
    entry = state_entry(config)
    # JSON's numeric 1 and 1.0 have the same meaning in the native/QML parser.
    # Booleans and strings are not schema numbers.
    if (entry is None or type(entry.get(STATE_STORAGE_SCHEMA)) not in (int, float)
            or entry[STATE_STORAGE_SCHEMA] != 1
            or not isinstance(entry.get("shibumi"), dict)
            or type(entry["shibumi"].get("version")) not in (int, float)
            or entry["shibumi"]["version"] != 1):
        raise ConfigError("invalid canonical State settings; refusing legacy fallback")
    return entry["shibumi"]


def migrate_state_settings(config: dict[str, Any], *, import_legacy: bool = True) -> dict[str, Any]:
    """One-way, drained lifecycle migration; runtime never writes bar.shibumi."""
    state_entry(config)  # Reject ambiguity before normalization/deduplication.
    result = _normalize(config)
    entry = state_entry(result)
    if entry is None:
        entry = {"id": STATE_PLUGIN_ID}
        result["plugins"].append(entry)
    if STATE_STORAGE_SCHEMA in entry or "shibumi" in entry:
        validate_state_settings(result)
    else:
        legacy = result["bar"].get("shibumi", {"version": 1}) if import_legacy else {"version": 1}
        version = legacy.get("version", 1) if isinstance(legacy, dict) else None
        if not isinstance(legacy, dict) or not (
                (type(version) in (int, float) and version == 1) or version == "1"):
            raise ConfigError("unsupported legacy State settings")
        entry[STATE_STORAGE_SCHEMA] = 1
        entry["shibumi"] = copy.deepcopy(legacy)
        entry["shibumi"]["version"] = 1
    # Stock keeps legacy data inert; it is never a runtime source. Cleanup is
    # allowed only when the suite Bar is selected in the lifecycle document.
    if result["bar"].get("id") == "hancore.shibumi.bar":
        result["bar"].pop("shibumi", None)
    validate_state_settings(result)
    return result


def apply_identity_contract(config: dict[str, Any], *, migrate_storage: bool = True) -> dict[str, Any]:
    """Migrate storage with the new payload; old-payload activation stays legacy."""
    result = migrate_state_settings(config) if migrate_storage else _normalize(config)
    settings = state_entry(result)["shibumi"] if migrate_storage else result["bar"].get("shibumi")
    if not isinstance(settings, dict):
        return result
    try:
        current_version = int(settings.get("identityVersion") or 0)
    except (TypeError, ValueError):
        current_version = 0
    menu = settings.get("menu")
    legacy_launcher = menu.get("launcher") if isinstance(menu, dict) else None
    launcher = settings.get("launcher")
    if not isinstance(launcher, dict) and isinstance(legacy_launcher, dict):
        launcher = copy.deepcopy(legacy_launcher)
        settings["launcher"] = launcher
    if (
        current_version < 2
        and isinstance(launcher, dict)
        and launcher.get("text") == "omarchy"
    ):
        launcher["text"] = "shibumi"
    settings.pop("menu", None)
    settings["identityVersion"] = IDENTITY_VERSION
    return result


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant: {value}")


def _finite_json_float(raw: str) -> float:
    value = float(raw)
    if not math.isfinite(value):
        raise ValueError("non-finite JSON number")
    return value


def _finite_json_int(raw: str) -> int:
    _finite_json_float(raw)  # QML numbers must remain finite even without an exponent.
    return int(raw)


def parse_config_bytes(
    payload: bytes,
    source: Path,
    *,
    user_config_exists: bool,
) -> tuple[dict[str, Any], bool]:
    """Parse already acquired config bytes with the canonical JSON rules."""
    try:
        raw = payload.decode("utf-8")
        # Same parser budget as StateStorageModel; acquisition callers must
        # impose their own byte and file-type bounds before invoking this.
        if len(raw.encode("utf-16-le")) // 2 > 1048576:
            raise ValueError("shell config exceeds State parser budget")
        data = json.loads(raw, parse_constant=_reject_json_constant,
                          parse_float=_finite_json_float, parse_int=_finite_json_int)
    except (UnicodeError, ValueError) as error:
        raise ConfigError(f"cannot read shell config {source}: {error}") from error
    if not isinstance(data, dict):
        raise ConfigError(f"shell config must be a JSON object: {source}")
    if not user_config_exists:
        # Host defaults provide a construction fallback, not a saved stock-bar
        # transparency preference. Do not materialize that preference merely
        # because Shibumi creates the first user shell configuration.
        bar = data.get("bar")
        if isinstance(bar, dict):
            bar.pop("transparent", None)
    return data, user_config_exists


def read_config(path: Path, defaults_path: Path) -> tuple[dict[str, Any], bool]:
    source = path if path.is_file() and path.stat().st_size > 0 else defaults_path
    try:
        payload = source.read_bytes()
    except OSError as error:
        raise ConfigError(f"cannot read shell config {source}: {error}") from error
    return parse_config_bytes(
        payload, source, user_config_exists=source == path
    )


def _normalize(config: dict[str, Any]) -> dict[str, Any]:
    result = _object(config)
    result["version"] = 1
    result["bar"] = _object(result.get("bar"))
    result["bar"]["layout"] = _object(result["bar"].get("layout"))
    for region in REGIONS:
        result["bar"]["layout"][region] = _array(
            result["bar"]["layout"].get(region)
        )
    result["plugins"] = _array(result.get("plugins"))
    return result


def apply_profile(
    config: dict[str, Any],
    profile: ProfileSpec,
    plugins: dict[str, PluginSpec],
) -> dict[str, Any]:
    state_entry(config)
    result = _normalize(config)
    managed_widget_ids = {
        plugin_id for plugin_id, spec in plugins.items() if spec.is_bar_widget
    }

    existing_entries: dict[str, Any] = {}
    for region in REGIONS:
        for entry in result["bar"]["layout"][region]:
            plugin_id = entry_id(entry)
            if plugin_id in managed_widget_ids and plugin_id not in existing_entries:
                existing_entries[plugin_id] = copy.deepcopy(entry)

    for region in REGIONS:
        extras = [
            entry
            for entry in result["bar"]["layout"][region]
            if entry_id(entry) not in managed_widget_ids
            and not entry_id(entry).startswith(OMARCHY_PLUGIN_PREFIX)
        ]
        managed = [
            copy.deepcopy(existing_entries.get(plugin_id, {"id": plugin_id}))
            for plugin_id in profile.layout[region]
        ]
        result["bar"]["layout"][region] = managed + extras

    service_ids = set(profile.enable_services)
    plugin_entries = [
        entry for entry in result["plugins"] if entry_id(entry) not in plugins
    ]
    existing_services = {
        entry_id(entry): copy.deepcopy(entry)
        for entry in result["plugins"]
        if entry_id(entry) in service_ids
    }
    plugin_entries.extend(
        existing_services.get(plugin_id, {"id": plugin_id})
        for plugin_id in profile.enable_services
    )
    result["plugins"] = plugin_entries

    result["bar"]["id"] = profile.active_bar
    result["bar"]["centerAnchor"] = "hancore.shibumi.center"
    result["bar"]["style"] = "shibumi"
    if result["bar"].get("position") not in ("top", "bottom"):
        result["bar"]["position"] = "top"
    return result


def reconcile_profile_services(
    config: dict[str, Any],
    profile: ProfileSpec,
) -> dict[str, Any]:
    """Enable newly introduced suite services without rewriting user layout."""
    result = _normalize(config)
    enabled = {entry_id(entry) for entry in result["plugins"]}
    for plugin_id in profile.enable_services:
        if plugin_id not in enabled:
            result["plugins"].append({"id": plugin_id})
            enabled.add(plugin_id)
    return result


def remove_plugin_ids(
    config: dict[str, Any], plugin_ids: set[str] | tuple[str, ...]
) -> dict[str, Any]:
    """Remove retired Shibumi roots from services and any stale bar layout."""
    result = _normalize(config)
    retired = set(plugin_ids)
    for region in REGIONS:
        result["bar"]["layout"][region] = [
            entry
            for entry in result["bar"]["layout"][region]
            if entry_id(entry) not in retired
        ]
    result["plugins"] = [
        entry for entry in result["plugins"] if entry_id(entry) not in retired
    ]
    return result


def reconcile_profile_additions(
    config: dict[str, Any],
    profile: ProfileSpec,
    previous_plugin_ids: set[str],
    plugins: dict[str, PluginSpec],
) -> dict[str, Any]:
    """Add only newly introduced profile widgets without reordering user state."""
    result = _normalize(config)
    present = {
        entry_id(entry)
        for region in REGIONS
        for entry in result["bar"]["layout"][region]
    }
    introduced = set(profile.install) - previous_plugin_ids
    for region in REGIONS:
        for plugin_id in profile.layout[region]:
            spec = plugins.get(plugin_id)
            if plugin_id not in introduced or plugin_id in present \
                    or spec is None or not spec.is_bar_widget:
                continue
            result["bar"]["layout"][region].append({"id": plugin_id})
            present.add(plugin_id)
    return result


def select_omarchy_image_picker(config: dict[str, Any]) -> dict[str, Any]:
    """Route theme/wallpaper selection back to Quattro on the stock bar."""
    result = _normalize(config)
    entry = state_entry(result)
    shibumi = entry.get("shibumi") if entry and entry.get(STATE_STORAGE_SCHEMA) == 1 else result["bar"].get("shibumi")
    if isinstance(shibumi, dict):
        picker = shibumi.get("picker")
        if not isinstance(picker, dict):
            picker = {}
            shibumi["picker"] = picker
        picker["imageStyle"] = "omarchy"
    return result


def remove_suite(
    config: dict[str, Any],
    plugins: dict[str, PluginSpec],
    active_bar: str,
    default_center_anchor: str,
    keep_settings: bool,
    preserve_ids: set[str] | None = None,
    restore_bar: dict[str, Any] | None = None,
) -> dict[str, Any]:
    result = _normalize(config)
    current_bar = copy.deepcopy(result["bar"])
    retained_entry = copy.deepcopy(state_entry(result)) if keep_settings else None
    plugin_ids = set(plugins)
    preserved = preserve_ids or set()
    for region in REGIONS:
        result["bar"]["layout"][region] = [
            entry
            for entry in result["bar"]["layout"][region]
            if entry_id(entry) not in plugin_ids
            or entry_id(entry) in preserved
        ]
    result["plugins"] = [
        entry
        for entry in result["plugins"]
        if entry_id(entry) not in plugin_ids
        or entry_id(entry) in preserved
    ]
    # A kept settings entry is inert when its payload is absent. Preserve the
    # complete envelope, not just settings; normal uninstall removes it.
    if retained_entry is not None and not any(
            entry_id(entry) == STATE_PLUGIN_ID for entry in result["plugins"]):
        result["plugins"].append(retained_entry)
    if result["bar"].get("id") == active_bar and restore_bar is not None:
        restored = _object(restore_bar)
        restored_layout = _object(restored.get("layout"))
        filtered_layout = result["bar"]["layout"]
        for region in REGIONS:
            entries = _array(restored_layout.get(region))
            known = {entry_id(entry) for entry in entries}
            entries.extend(
                copy.deepcopy(entry)
                for entry in filtered_layout[region]
                if entry_id(entry) and entry_id(entry) not in known
            )
            restored_layout[region] = entries
        restored["layout"] = restored_layout
        result["bar"] = restored
        if "transparent" in current_bar:
            result["bar"]["transparent"] = copy.deepcopy(
                current_bar["transparent"]
            )
        else:
            result["bar"].pop("transparent", None)
        if retained_entry is not None and retained_entry.get(STATE_STORAGE_SCHEMA) == 1:
            result["bar"].pop("shibumi", None)
        elif keep_settings and isinstance(current_bar.get("shibumi"), dict):
            result["bar"]["shibumi"] = copy.deepcopy(current_bar["shibumi"])
    elif result["bar"].get("id") == active_bar:
        result["bar"].pop("id", None)
    if result["bar"].get("centerAnchor") == "hancore.shibumi.center":
        if default_center_anchor:
            result["bar"]["centerAnchor"] = default_center_anchor
        else:
            result["bar"].pop("centerAnchor", None)
    if result["bar"].get("style") == "shibumi":
        result["bar"].pop("style", None)
    if not keep_settings:
        result["bar"].pop("shibumi", None)
    return result


def encode_config(config: dict[str, Any]) -> bytes:
    return (json.dumps(config, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")


def _fsync_directory(
    path: Path,
    *,
    on_durable: Callable[[], None] | None = None,
) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
        if on_durable is not None:
            on_durable()
    finally:
        os.close(descriptor)


def _durable_mkdir(path: Path) -> None:
    missing: list[Path] = []
    current = path
    while not current.exists():
        missing.append(current)
        if current.parent == current:
            raise ConfigError(f"cannot create configuration directory: {path}")
        current = current.parent
    if not current.is_dir():
        raise ConfigError(f"configuration parent is not a directory: {current}")
    for directory in reversed(missing):
        directory.mkdir()
        _fsync_directory(directory)
        _fsync_directory(directory.parent)


def atomic_write(
    path: Path,
    payload: bytes,
    mode: int = 0o600,
    *,
    on_durable: Callable[[], None] | None = None,
) -> None:
    _durable_mkdir(path.parent)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
        _fsync_directory(path.parent, on_durable=on_durable)
    finally:
        temporary.unlink(missing_ok=True)
