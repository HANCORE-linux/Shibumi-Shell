from __future__ import annotations

import json
import hashlib
import re
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import SUITE_ID


PLUGIN_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class ContractError(RuntimeError):
    pass


def plugin_payload_digest(
    directory: Path, *, excluded_paths: tuple[str, ...] = ()
) -> str:
    """Hash the exact plugin payload, excluding the installed ownership marker."""
    if directory.is_symlink() or not directory.is_dir():
        raise ContractError(f"plugin payload is not a real directory: {directory}")

    digest = hashlib.sha256()
    digest.update(b"shibumi-plugin-payload-v1\0")
    for path in sorted(directory.rglob("*"), key=lambda item: item.relative_to(directory).as_posix()):
        relative = path.relative_to(directory).as_posix()
        if relative == ".shibumi-managed.json" or relative in excluded_paths:
            continue
        metadata = path.lstat()
        if path.is_symlink():
            raise ContractError(f"plugin payload contains a symlink: {path}")
        if path.is_dir():
            continue
        if not stat.S_ISREG(metadata.st_mode):
            raise ContractError(f"plugin payload contains a special file: {path}")
        digest.update(b"file\0")
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(f"{metadata.st_mode & 0o111:o}".encode("ascii"))
        digest.update(b"\0")
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
        digest.update(b"\0")
    return digest.hexdigest()


def suite_payload_digest(plugin_digests: dict[str, str]) -> str:
    digest = hashlib.sha256()
    digest.update(b"shibumi-suite-payload-v1\0")
    for plugin_id in sorted(plugin_digests):
        digest.update(plugin_id.encode("utf-8"))
        digest.update(b"\0")
        digest.update(plugin_digests[plugin_id].encode("ascii"))
        digest.update(b"\0")
    return digest.hexdigest()


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f"{label} must be an object")
    return value


def _strings(value: Any, label: str) -> tuple[str, ...]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise ContractError(f"{label} must be an array of strings")
    return tuple(value)


@dataclass(frozen=True)
class PluginSpec:
    id: str
    kinds: tuple[str, ...]
    role: str
    bundle: str
    requires: tuple[str, ...]
    recommends: tuple[str, ...]
    source: Path

    @property
    def is_bar_widget(self) -> bool:
        return "bar-widget" in self.kinds

    def payload_digest(self, directory: Path | None = None) -> str:
        return plugin_payload_digest(directory or self.source)


@dataclass(frozen=True)
class ProfileSpec:
    id: str
    active_bar: str
    install: tuple[str, ...]
    enable_services: tuple[str, ...]
    layout: dict[str, tuple[str, ...]]
    disabled_by_default: tuple[str, ...]


class Suite:
    def __init__(
        self,
        root: Path,
        version: str,
        plugins: dict[str, PluginSpec],
        profiles: dict[str, ProfileSpec],
    ) -> None:
        self.root = root
        self.version = version
        self.plugins = plugins
        self.profiles = profiles

    @classmethod
    def load(cls, root: Path) -> "Suite":
        root = root.resolve(strict=True)
        contract_path = root / "contracts/plugin-suite-v1.json"
        try:
            data = json.loads(contract_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ContractError(f"cannot read {contract_path}: {error}") from error

        if data.get("schemaVersion") != 1 or data.get("suiteId") != SUITE_ID:
            raise ContractError("unsupported Shibumi suite contract")
        version = str(data.get("suiteVersion") or "").strip()
        if not version:
            raise ContractError("suiteVersion is required")

        plugins: dict[str, PluginSpec] = {}
        for raw in data.get("plugins", []):
            item = _object(raw, "plugin")
            plugin_id = str(item.get("id") or "")
            if not PLUGIN_ID.fullmatch(plugin_id) or ".." in plugin_id:
                raise ContractError(f"unsafe plugin id: {plugin_id!r}")
            if plugin_id in plugins:
                raise ContractError(f"duplicate plugin id: {plugin_id}")
            source = root / plugin_id
            spec = PluginSpec(
                id=plugin_id,
                kinds=_strings(item.get("kinds"), f"{plugin_id}.kinds"),
                role=str(item.get("role") or ""),
                bundle=str(item.get("bundle") or ""),
                requires=_strings(item.get("requires", []), f"{plugin_id}.requires"),
                recommends=_strings(item.get("recommends", []), f"{plugin_id}.recommends"),
                source=source,
            )
            cls._validate_manifest(spec)
            plugins[plugin_id] = spec

        for spec in plugins.values():
            unknown = set(spec.requires) - plugins.keys()
            if unknown:
                raise ContractError(
                    f"{spec.id} requires unknown plugins: {', '.join(sorted(unknown))}"
                )

        profiles: dict[str, ProfileSpec] = {}
        for raw in data.get("profiles", []):
            item = _object(raw, "profile")
            profile_id = str(item.get("id") or "")
            if not profile_id or profile_id in profiles:
                raise ContractError(f"invalid or duplicate profile id: {profile_id!r}")
            raw_layout = _object(item.get("layout"), f"{profile_id}.layout")
            layout = {
                region: _strings(raw_layout.get(region), f"{profile_id}.layout.{region}")
                for region in ("left", "center", "right")
            }
            profile = ProfileSpec(
                id=profile_id,
                active_bar=str(item.get("activeBar") or ""),
                install=_strings(item.get("install"), f"{profile_id}.install"),
                enable_services=_strings(
                    item.get("enableServices", []), f"{profile_id}.enableServices"
                ),
                layout=layout,
                disabled_by_default=_strings(
                    item.get("disabledByDefault", []),
                    f"{profile_id}.disabledByDefault",
                ),
            )
            cls._validate_profile(profile, plugins)
            profiles[profile_id] = profile

        if not plugins or not profiles:
            raise ContractError("suite must declare plugins and profiles")
        return cls(root, version, plugins, profiles)

    @staticmethod
    def _validate_manifest(spec: PluginSpec) -> None:
        if spec.source.is_symlink() or not spec.source.is_dir():
            raise ContractError(f"plugin source is not a real directory: {spec.id}")
        manifest_path = spec.source / "manifest.json"
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ContractError(f"cannot read {manifest_path}: {error}") from error
        meta = manifest.get("x-shibumi")
        if (
            manifest.get("schemaVersion") != 1
            or manifest.get("id") != spec.id
            or tuple(manifest.get("kinds") or ()) != spec.kinds
            or not isinstance(manifest.get("entryPoints"), dict)
            or not isinstance(meta, dict)
            or meta.get("suiteId") != SUITE_ID
            or meta.get("role") != spec.role
            or meta.get("bundle") != spec.bundle
            or tuple(meta.get("requires") or ()) != spec.requires
        ):
            raise ContractError(f"manifest drifts from suite contract: {spec.id}")
        for entry_point in manifest["entryPoints"].values():
            if not isinstance(entry_point, str) or not entry_point:
                raise ContractError(f"invalid entry point in {spec.id}")
            candidate = (spec.source / entry_point).resolve(strict=False)
            if not candidate.is_relative_to(spec.source.resolve()) or not candidate.is_file():
                raise ContractError(f"unsafe or missing entry point in {spec.id}: {entry_point}")
        spec.payload_digest()

    @staticmethod
    def _validate_profile(
        profile: ProfileSpec, plugins: dict[str, PluginSpec]
    ) -> None:
        selected = set(profile.install)
        if selected != set(plugins):
            raise ContractError(
                f"profile {profile.id} must install the complete declared suite"
            )
        if profile.active_bar not in selected or "bar" not in plugins[profile.active_bar].kinds:
            raise ContractError(f"profile {profile.id} has an invalid active bar")
        enabled = set(profile.enable_services)
        for values in profile.layout.values():
            enabled.update(values)
            for plugin_id in values:
                if plugin_id not in plugins or not plugins[plugin_id].is_bar_widget:
                    raise ContractError(
                        f"profile {profile.id} layout contains invalid widget {plugin_id}"
                    )
        missing = selected - enabled - {profile.active_bar}
        if missing:
            raise ContractError(
                f"profile {profile.id} leaves plugins disabled: {', '.join(sorted(missing))}"
            )
        if not set(profile.disabled_by_default).issubset(enabled):
            raise ContractError(
                f"profile {profile.id} disabledByDefault plugins must remain registry-enabled"
            )

    def profile(self, profile_id: str) -> ProfileSpec:
        try:
            return self.profiles[profile_id]
        except KeyError as error:
            raise ContractError(f"unknown profile: {profile_id}") from error

    def selected(self, ids: tuple[str, ...]) -> list[PluginSpec]:
        return [self.plugins[plugin_id] for plugin_id in ids]

    def revision(self) -> str:
        try:
            result = subprocess.run(
                ["git", "-C", str(self.root), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            return "archive"
        revision = result.stdout.strip()
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            return "archive"
        try:
            status = subprocess.run(
                [
                    "git",
                    "-C",
                    str(self.root),
                    "status",
                    "--porcelain=v1",
                    "--untracked-files=normal",
                    "--",
                    "contracts/plugin-suite-v1.json",
                    *(sorted(self.plugins)),
                ],
                check=True,
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            return "archive"
        return f"{revision}-dirty" if status.stdout.strip() else revision
