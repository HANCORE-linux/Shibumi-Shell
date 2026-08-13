from __future__ import annotations

import copy
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from .model import PluginSpec, ProfileSpec


REGIONS = ("left", "center", "right")
LEGACY_PLUGIN_PREFIX = "hancore.qsrise"
PLUGIN_PREFIX = "hancore.shibumi"
OMARCHY_PLUGIN_PREFIX = "omarchy."
IDENTITY_VERSION = 3


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


def apply_identity_contract(config: dict[str, Any]) -> dict[str, Any]:
    """Record the Shibumi identity and replace the pre-release default once."""
    result = _normalize(config)
    settings = result["bar"].get("shibumi")
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


def read_config(path: Path, defaults_path: Path) -> tuple[dict[str, Any], bool]:
    source = path if path.is_file() and path.stat().st_size > 0 else defaults_path
    try:
        data = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigError(f"cannot read shell config {source}: {error}") from error
    if not isinstance(data, dict):
        raise ConfigError(f"shell config must be a JSON object: {source}")
    user_config_exists = source == path
    if not user_config_exists:
        # Host defaults provide a construction fallback, not a saved stock-bar
        # transparency preference. Do not materialize that preference merely
        # because Shibumi creates the first user shell configuration.
        bar = data.get("bar")
        if isinstance(bar, dict):
            bar.pop("transparent", None)
    return data, user_config_exists


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
    shibumi = result["bar"].get("shibumi")
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
        if keep_settings and isinstance(current_bar.get("shibumi"), dict):
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
    return (json.dumps(config, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
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


def atomic_write(path: Path, payload: bytes, mode: int = 0o600) -> None:
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
        _fsync_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)
