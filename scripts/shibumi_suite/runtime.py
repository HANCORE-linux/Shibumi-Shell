from __future__ import annotations

import json
import os
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class RuntimeFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class RuntimePaths:
    omarchy_root: Path
    plugin_dir: Path
    config_file: Path
    defaults_file: Path
    state_dir: Path
    cache_dir: Path
    lock_file: Path

    @classmethod
    def from_environment(cls) -> "RuntimePaths":
        home = Path.home()
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
        state_home = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
        cache_home = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
        runtime_home = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/shibumi-{os.getuid()}"))

        defaults_override = os.environ.get("SHIBUMI_DEFAULT_CONFIG")
        omarchy_root = _omarchy_root(home)
        defaults = Path(defaults_override) if defaults_override else (
            omarchy_root / "config/omarchy/shell.json"
        )
        return cls(
            omarchy_root=omarchy_root,
            plugin_dir=Path(
                os.environ.get("SHIBUMI_PLUGIN_DIR", config_home / "omarchy/plugins")
            ),
            config_file=Path(
                os.environ.get("SHIBUMI_CONFIG_FILE", config_home / "omarchy/shell.json")
            ),
            defaults_file=defaults,
            state_dir=Path(os.environ.get("SHIBUMI_STATE_DIR", state_home / "shibumi")),
            cache_dir=Path(os.environ.get("SHIBUMI_CACHE_DIR", cache_home / "shibumi")),
            lock_file=Path(
                os.environ.get("SHIBUMI_LOCK_FILE", runtime_home / "shibumi-suite.lock")
            ),
        )

    def validate(self) -> None:
        if not self.omarchy_root.is_absolute():
            raise RuntimeFailure("OMARCHY_PATH must be absolute")
        for command in ("omarchy", "omarchy-shell"):
            if not (self.omarchy_root / "bin" / command).is_file():
                raise RuntimeFailure(
                    f"Omarchy command is missing: {self.omarchy_root / 'bin' / command}"
                )
        if (
            not self.plugin_dir.is_absolute()
            or self.plugin_dir.name != "plugins"
            or self.plugin_dir.parent.name != "omarchy"
        ):
            raise RuntimeFailure(f"unsafe Omarchy plugin directory: {self.plugin_dir}")
        if (
            not self.config_file.is_absolute()
            or self.config_file.name != "shell.json"
            or self.config_file.parent.name != "omarchy"
        ):
            raise RuntimeFailure(f"unsafe Omarchy shell config path: {self.config_file}")
        if not self.state_dir.is_absolute() or self.state_dir.name != "shibumi":
            raise RuntimeFailure(f"unsafe Shibumi state directory: {self.state_dir}")
        if not self.cache_dir.is_absolute() or self.cache_dir.name != "shibumi":
            raise RuntimeFailure(f"unsafe Shibumi cache directory: {self.cache_dir}")
        if not self.lock_file.is_absolute():
            raise RuntimeFailure(f"unsafe Shibumi lock path: {self.lock_file}")
        if not self.defaults_file.is_absolute() or not self.defaults_file.is_file():
            raise RuntimeFailure(
                f"Omarchy shell defaults are missing: {self.defaults_file}"
            )
        if self.config_file.is_symlink():
            raise RuntimeFailure(
                f"refusing to replace symlinked Omarchy shell config: {self.config_file}"
            )


def _omarchy_root(home: Path) -> Path:
    override = os.environ.get("OMARCHY_PATH")
    candidates = [
        Path(override) if override else None,
        Path("/usr/share/omarchy"),
        home / ".local/share/omarchy",
    ]
    for candidate in candidates:
        if candidate and (candidate / "config/omarchy/shell.json").is_file():
            return candidate
    if override:
        return Path(override)
    raise RuntimeFailure(
        "Omarchy Quattro defaults were not found; set OMARCHY_PATH or SHIBUMI_DEFAULT_CONFIG"
    )


class OmarchyRuntime:
    def __init__(
        self,
        omarchy_root: Path | None = None,
        environment: dict[str, str] | None = None,
    ) -> None:
        self.omarchy_root = omarchy_root
        self.environment = os.environ.copy()
        if environment:
            self.environment.update(environment)
        if omarchy_root:
            bin_path = str(omarchy_root / "bin")
            self.environment["OMARCHY_PATH"] = str(omarchy_root)
            self.environment["PATH"] = bin_path + os.pathsep + self.environment.get(
                "PATH", ""
            )

    def command(self, name: str) -> str:
        if self.omarchy_root:
            candidate = self.omarchy_root / "bin" / name
            if not candidate.is_file():
                raise RuntimeFailure(f"Omarchy command is missing: {candidate}")
            return str(candidate)
        return name

    def run(
        self,
        command: list[str],
        *,
        timeout: float = 20,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        try:
            result = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
                timeout=timeout,
                env=self.environment,
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise RuntimeFailure(f"cannot run {' '.join(command)}: {error}") from error
        if check and result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            raise RuntimeFailure(
                f"{' '.join(command)} failed ({result.returncode})"
                + (f": {detail}" if detail else "")
            )
        return result

    def validate_plugin(self, directory: Path) -> None:
        self.run([self.command("omarchy"), "plugin", "validate", str(directory)])

    def rescan(self) -> None:
        self.run([self.command("omarchy"), "plugin", "rescan"])

    def reload_config(self, *, timeout: float = 30) -> None:
        command = [self.command("omarchy-shell"), "shell", "reloadConfig"]
        deadline = time.monotonic() + timeout
        detail = "shell did not answer"
        while time.monotonic() < deadline:
            result = self.run(command, check=False)
            response = result.stdout.strip()
            if result.returncode == 0 and response in ("", "ok"):
                return
            detail = (result.stderr or result.stdout).strip() or (
                f"exit {result.returncode}"
            )
            time.sleep(0.1)
        raise RuntimeFailure(f"reloadConfig did not settle: {detail}")

    def reload_payload(self, *, timeout: float = 8) -> None:
        deadline = time.monotonic() + timeout
        detail = "reload endpoint is not ready"
        targets = ("shibumi-suite-runtime", "shibumi-suite")
        while time.monotonic() < deadline:
            for target in targets:
                command = [
                    self.command("omarchy-shell"),
                    target,
                    "reloadPayload",
                ]
                result = self.run(command, check=False)
                if result.returncode == 0 and result.stdout.strip() == "ok":
                    return
                detail = (result.stderr or result.stdout).strip() or (
                    f"{target} exited {result.returncode}"
                )
            time.sleep(0.1)
        raise RuntimeFailure(
            "the running Shibumi state service cannot reload updated QML; "
            f"restart the Omarchy Shell once and retry ({detail})"
        )

    def ping(self) -> None:
        result = self.run([self.command("omarchy-shell"), "shell", "ping"])
        if result.stdout.strip() != "ok":
            raise RuntimeFailure(f"unexpected shell ping response: {result.stdout.strip()}")

    def list_plugins(self) -> dict[str, dict[str, Any]]:
        result = self.run([self.command("omarchy-shell"), "shell", "listPlugins"])
        try:
            values = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise RuntimeFailure("shell returned malformed plugin JSON") from error
        if not isinstance(values, list):
            raise RuntimeFailure("shell plugin response is not an array")
        return {
            str(item.get("id")): item
            for item in values
            if isinstance(item, dict) and item.get("id")
        }

    def payload_ready(self, payload_digest: str) -> bool:
        result = self.run(
            [
                self.command("omarchy-shell"),
                "shibumi-suite-runtime",
                "verifyPayload",
                payload_digest,
            ],
            check=False,
        )
        return result.returncode == 0 and result.stdout.strip() == "ok"

    def verify_install(
        self,
        plugin_ids: set[str],
        active_bar: str,
        payload_digest: str,
        *,
        enabled_plugin_ids: set[str] | None = None,
        timeout: float = 60,
    ) -> None:
        expected_enabled = (
            plugin_ids if enabled_plugin_ids is None else enabled_plugin_ids
        )
        deadline = time.monotonic() + timeout
        detail = "plugins were not visible"
        while time.monotonic() < deadline:
            try:
                plugins = self.list_plugins()
                missing = plugin_ids - plugins.keys()
                disabled = {
                    plugin_id
                    for plugin_id in expected_enabled
                    if plugin_id in plugins and plugins[plugin_id].get("enabled") is not True
                }
                active = plugins.get(active_bar, {}).get("active") is True
                payload_ready = self.payload_ready(payload_digest)
                if not missing and not disabled and active and payload_ready:
                    self.ping()
                    return
                detail = (
                    f"missing={sorted(missing)}, disabled={sorted(disabled)}, "
                    f"activeBar={active}, payloadReady={payload_ready}"
                )
            except RuntimeFailure as error:
                detail = str(error)
            time.sleep(0.1)
        raise RuntimeFailure(f"Shibumi activation verification failed: {detail}")

    def verify_update(
        self,
        plugin_ids: set[str],
        payload_digest: str,
        *,
        enabled_plugin_ids: set[str] | None = None,
        timeout: float = 60,
    ) -> None:
        expected_enabled = (
            plugin_ids if enabled_plugin_ids is None else enabled_plugin_ids
        )
        deadline = time.monotonic() + timeout
        detail = "plugins were not visible"
        while time.monotonic() < deadline:
            try:
                plugins = self.list_plugins()
                missing = plugin_ids - plugins.keys()
                disabled = {
                    plugin_id
                    for plugin_id in expected_enabled
                    if plugin_id in plugins and plugins[plugin_id].get("enabled") is not True
                }
                payload_ready = self.payload_ready(payload_digest)
                if not missing and not disabled and payload_ready:
                    self.ping()
                    return
                detail = (
                    f"missing={sorted(missing)}, disabled={sorted(disabled)}, "
                    f"payloadReady={payload_ready}"
                )
            except RuntimeFailure as error:
                detail = str(error)
            time.sleep(0.1)
        raise RuntimeFailure(f"Shibumi update verification failed: {detail}")

    def verify_deactivation(
        self,
        plugin_ids: set[str],
        shibumi_bar: str,
        *,
        allowed_enabled: set[str] | None = None,
        timeout: float = 60,
    ) -> None:
        allowed = allowed_enabled or set()
        deadline = time.monotonic() + timeout
        detail = "stock Omarchy bar was not visible"
        while time.monotonic() < deadline:
            try:
                plugins = self.list_plugins()
                stock_active = plugins.get("omarchy.bar", {}).get("active") is True
                shibumi_active = (
                    plugins.get(shibumi_bar, {}).get("active") is True
                )
                enabled = {
                    plugin_id
                    for plugin_id in plugin_ids
                    if plugins.get(plugin_id, {}).get("enabled") is True
                } - allowed
                if stock_active and not shibumi_active and not enabled:
                    self.ping()
                    return
                detail = (
                    f"stockActive={stock_active}, "
                    f"shibumiActive={shibumi_active}, "
                    f"enabled={sorted(enabled)}"
                )
            except RuntimeFailure as error:
                detail = str(error)
            time.sleep(0.1)
        raise RuntimeFailure(f"Shibumi deactivation verification failed: {detail}")

    def verify_uninstall(self, plugin_ids: set[str], *, timeout: float = 8) -> None:
        deadline = time.monotonic() + timeout
        detail = "removed plugins remain visible"
        while time.monotonic() < deadline:
            try:
                plugins = self.list_plugins()
                remaining = plugin_ids & plugins.keys()
                if not remaining:
                    self.ping()
                    return
                detail = f"remaining={sorted(remaining)}"
            except RuntimeFailure as error:
                detail = str(error)
            time.sleep(0.1)
        raise RuntimeFailure(f"Shibumi uninstall verification failed: {detail}")

    def reconcile_best_effort(self) -> None:
        for action in (self.rescan, self.reload_config, self.reload_payload):
            try:
                action()
            except RuntimeFailure:
                pass
