from __future__ import annotations

import json
import os
import select
import signal
import subprocess
import sys
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

    @property
    def menu_extension_file(self) -> Path:
        return self.config_file.parent / "extensions/omarchy-menu.jsonc"

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
        for command in (
            "omarchy",
            "omarchy-shell",
            "omarchy-bluetooth-device",
            "omarchy-bluetooth-power",
            "omarchy-audio-output-set-default",
        ):
            if not (self.omarchy_root / "bin" / command).is_file():
                raise RuntimeFailure(
                    f"Omarchy command is missing: {self.omarchy_root / 'bin' / command}"
                )
        quattro_sources = {
            self.omarchy_root / "shell/services/PluginRegistry.qml": (
                "function entryPointUrl",
                "function isEnabled",
            ),
            self.omarchy_root / "shell/shell.qml": (
                "function configureBar",
                "target.pluginRegistry = shell.pluginRegistry",
            ),
            self.omarchy_root / "shell/Ui/KeyboardPanel.qml": (
                "property var borderSpec:",
                "BorderSurface {",
            ),
        }
        validator = self.omarchy_root / "bin/omarchy-plugin-validate"
        if not validator.is_file():
            raise RuntimeFailure(
                "Shibumi supports Omarchy Quattro only: plugin validator is missing"
            )
        for path, required_symbols in quattro_sources.items():
            try:
                source = path.read_text(encoding="utf-8")
            except OSError as error:
                raise RuntimeFailure(
                    f"Shibumi supports Omarchy Quattro only: missing {path}: {error}"
                ) from error
            missing = [symbol for symbol in required_symbols if symbol not in source]
            if missing:
                raise RuntimeFailure(
                    "Shibumi supports Omarchy Quattro only: incompatible host "
                    f"contract in {path} ({', '.join(missing)})"
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
        mutable_paths = {
            "Omarchy plugin directory": self.plugin_dir,
            "Omarchy config directory": self.config_file.parent,
            "Shibumi state directory": self.state_dir,
            "Shibumi cache directory": self.cache_dir,
            "Shibumi lock directory": self.lock_file.parent,
            "Shibumi lock file": self.lock_file,
        }
        for label, path in mutable_paths.items():
            symlink = _first_existing_symlink(path)
            if symlink is not None:
                raise RuntimeFailure(
                    f"refusing symlinked {label}: {symlink}"
                )
        if self.config_file.is_symlink():
            raise RuntimeFailure(
                f"refusing to replace symlinked Omarchy shell config: {self.config_file}"
            )
        if self.menu_extension_file.is_symlink() \
                or self.menu_extension_file.parent.is_symlink():
            raise RuntimeFailure(
                "refusing symlinked Omarchy menu extension path: "
                f"{self.menu_extension_file}"
            )


def _first_existing_symlink(path: Path) -> Path | None:
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        try:
            if current.is_symlink():
                return current
            current.lstat()
        except FileNotFoundError:
            break
        except OSError as error:
            raise RuntimeFailure(
                f"cannot validate writable path component {current}: {error}"
            ) from error
    return None


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

    def require_session_unlocked(self, operation: str) -> None:
        """Fail closed unless Omarchy reports an explicitly idle lock service."""
        action = operation.strip() or "Shibumi lifecycle mutation"
        command = [self.command("omarchy-shell"), "lock", "status"]
        try:
            result = self.run(command, timeout=4, check=False)
        except RuntimeFailure as error:
            raise RuntimeFailure(
                f"cannot verify that the session is unlocked before {action}: {error}"
            ) from error
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip() or (
                f"exit {result.returncode}"
            )
            raise RuntimeFailure(
                f"cannot verify that the session is unlocked before {action}: "
                f"lock status failed ({detail})"
            )

        def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
            value: dict[str, Any] = {}
            for key, item in pairs:
                if key in value:
                    raise ValueError(f"duplicate lock status field: {key}")
                value[key] = item
            return value

        def reject_nonfinite_number(value: str) -> Any:
            raise ValueError(f"non-finite lock status number: {value}")

        try:
            status = json.loads(
                result.stdout,
                object_pairs_hook=reject_duplicate_keys,
                parse_constant=reject_nonfinite_number,
            )
        except (json.JSONDecodeError, ValueError) as error:
            raise RuntimeFailure(
                f"cannot verify that the session is unlocked before {action}: "
                "lock status returned malformed or ambiguous JSON"
            ) from error
        required = ("locked", "requested", "pending", "sessionLocked", "secure")
        if not isinstance(status, dict):
            raise RuntimeFailure(
                f"cannot verify that the session is unlocked before {action}: "
                "lock status is not an object"
            )
        invalid = [name for name in required if type(status.get(name)) is not bool]
        if invalid:
            raise RuntimeFailure(
                f"cannot verify that the session is unlocked before {action}: "
                "lock status has missing or non-boolean fields "
                + ", ".join(invalid)
            )
        active = [name for name in required if status[name] is True]
        if active:
            raise RuntimeFailure(
                f"refusing {action} while the Omarchy session lock is active "
                f"({', '.join(active)}); unlock the session and retry"
            )

    def rescan(self) -> None:
        self.run([self.command("omarchy-shell"), "shell", "rescanPlugins"])

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

    def restart_shell(self, *, timeout: float | None = None) -> None:
        """Allow the host's per-instance stop, dying-instance and ready phases."""
        if timeout is None:
            # v4.0.5: 30 s per kill, including the terminating failed attempt,
            # then 30 s for a dying instance and 60 s for native readiness.
            count = len(self.shell_instances())
            timeout = 30 * (count + 1) + 30 + 60
            registry_timeout = 60
        else:
            registry_timeout = min(60, timeout)
        self.run([self.command("omarchy-restart-shell")], timeout=timeout)
        self.wait_for_single_shell_instance(timeout=registry_timeout)

    @property
    def shell_config_file(self) -> Path:
        if self.omarchy_root is None:
            raise RuntimeFailure(
                "cannot inspect shell instances without an Omarchy root"
            )
        return (self.omarchy_root / "shell/shell.qml").resolve(strict=False)

    def quickshell_instances(self, *, timeout: float = 6) -> list[dict[str, Any]]:
        result = self.run(
            ["quickshell", "list", "--all", "--json"],
            timeout=timeout,
        )
        if result.stdout == "No running instances.\n":
            values = []
        else:
            try:
                values = json.loads(result.stdout)
            except json.JSONDecodeError as error:
                raise RuntimeFailure(
                    "Quickshell returned malformed instance JSON"
                ) from error
        if not isinstance(values, list):
            raise RuntimeFailure("Quickshell instance response is not an array")
        return [value for value in values if isinstance(value, dict)]

    def shell_instances(self, *, timeout: float = 6) -> list[dict[str, Any]]:
        expected = self.shell_config_file
        matches: list[dict[str, Any]] = []
        for value in self.quickshell_instances(timeout=timeout):
            config_path = value.get("config_path")
            if not isinstance(config_path, str) or not config_path:
                continue
            if Path(config_path).resolve(strict=False) == expected:
                matches.append(value)
        return matches

    def verify_single_shell_instance(self, *, timeout: float = 6) -> None:
        instances = self.shell_instances(timeout=timeout)
        if len(instances) != 1:
            raise RuntimeFailure(
                "expected exactly one Omarchy shell instance, "
                f"found {len(instances)}; foreign Quickshell configs were left untouched"
            )

    def wait_for_single_shell_instance(self, *, timeout: float = 60) -> None:
        deadline = time.monotonic() + timeout
        detail = "the Omarchy shell instance is not registered"
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                self.verify_single_shell_instance(timeout=min(6, remaining))
                return
            except RuntimeFailure as error:
                detail = str(error)
            time.sleep(min(0.1, max(0, deadline - time.monotonic())))
        raise RuntimeFailure(f"Omarchy shell restart did not settle: {detail}")

    def bar_layers(self) -> list[tuple[str, int | None]] | None:
        result = self.run(["hyprctl", "layers", "-j"], timeout=6, check=False)
        if result.returncode != 0:
            return None
        try:
            values = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise RuntimeFailure("Hyprland returned malformed layer JSON") from error

        layers: list[tuple[str, int | None]] = []

        def collect(value: Any) -> None:
            if isinstance(value, dict):
                namespace = value.get("namespace")
                if isinstance(namespace, str):
                    raw_pid = value.get("pid")
                    pid = (
                        raw_pid
                        if isinstance(raw_pid, int)
                        and not isinstance(raw_pid, bool)
                        and raw_pid > 0
                        else None
                    )
                    layers.append((namespace, pid))
                for child in value.values():
                    collect(child)
            elif isinstance(value, list):
                for child in value:
                    collect(child)

        collect(values)
        return layers

    def verify_bar_layer_ownership(self, expected_namespace: str) -> None:
        layers = self.bar_layers()
        if layers is None:
            return
        names = {namespace for namespace, _pid in layers}
        managed = names & {"omarchy-bar", "shibumi-bar"}
        if len(managed) > 1:
            raise RuntimeFailure(
                "conflicting Omarchy and Shibumi bar layers are active; "
                "foreign Quickshell instances were left untouched"
            )
        if expected_namespace not in managed:
            raise RuntimeFailure(
                f"expected bar layer {expected_namespace!r}, found {sorted(managed)}"
            )
        production_pids = {
            value.get("pid")
            for value in self.shell_instances()
            if isinstance(value.get("pid"), int)
        }
        foreign_pids = {
            pid
            for namespace, pid in layers
            if namespace in managed
            and pid is not None
            and pid not in production_pids
        }
        if foreign_pids:
            raise RuntimeFailure(
                "a managed bar layer belongs to a foreign Quickshell instance; "
                "the foreign instance was left untouched"
            )

    def _shell_process_identity(self, pid: int) -> int:
        """Bind signal escalation to the same user's explicit exact shell path."""
        try:
            directory = os.open(
                f"/proc/{pid}", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
            )
            try:
                if os.fstat(directory).st_uid != os.getuid():
                    raise ValueError("different process owner")

                def field(name: str, limit: int) -> bytes:
                    descriptor = os.open(
                        name, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
                        dir_fd=directory,
                    )
                    with os.fdopen(descriptor, "rb") as stream:
                        raw = stream.read(limit + 1)
                    if len(raw) > limit:
                        raise ValueError("process identity field exceeds its bound")
                    return raw

                def started() -> int:
                    return int(field("stat", 4096).rsplit(b") ", 1)[1].split()[19])

                before = started()
                command = [part.decode("utf-8") for part in field("cmdline", 65536).split(b"\0") if part]
                after = started()
            finally:
                os.close(directory)
            if before != after or not command or Path(command[0]).name not in ("quickshell", "qs"):
                raise ValueError("not the same Quickshell process")
            paths = []
            index = 1
            while index < len(command):
                argument = command[index]
                if argument in ("-p", "--path"):
                    index += 1
                    paths.append(command[index])
                elif argument.startswith("--path="):
                    paths.append(argument[len("--path="):])
                index += 1
            if len(paths) != 1 or not Path(paths[0]).is_absolute():
                raise ValueError("no unique absolute shell path")
            path = Path(paths[0])
            config = path if path.name == "shell.qml" else path / "shell.qml"
            if config.resolve(strict=False) != self.shell_config_file:
                raise ValueError("foreign shell configuration")
            return after
        except (OSError, UnicodeError, ValueError, IndexError) as error:
            raise RuntimeFailure(
                f"shell drain: refusing signals to unverified PID {pid}: {error}"
            ) from error

    def _terminate_timed_out_shell(self, target: dict[str, Any], deadline: float) -> None:
        """TERM, then KILL, through one held kernel process reference only."""
        pid = target["pid"]
        identity = target.get("id")
        if not isinstance(identity, str) or not identity:
            raise RuntimeFailure("shell drain: signal fallback requires a registry identity")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return
        current = self.shell_instances(timeout=min(6, remaining))
        if not any(value.get("pid") == pid and value.get("id") == identity for value in current):
            return  # A replacement is handled by the outer registry drain.
        try:
            descriptor = os.pidfd_open(pid)
        except ProcessLookupError:
            return
        except (OSError, AttributeError) as error:
            raise RuntimeFailure(f"shell drain: cannot bind PID {pid} for signal fallback: {error}") from error
        try:
            def exited(wait: float = 0) -> bool:
                remaining = max(0, deadline - time.monotonic())
                return bool(select.select([descriptor], [], [], min(wait, remaining))[0])

            if exited():
                return
            try:
                started = self._shell_process_identity(pid)
            except RuntimeFailure:
                if exited():
                    return
                raise
            if exited() or time.monotonic() >= deadline:
                return
            print(f"shibumi-suite: shell drain: shutdown IPC timed out for PID {pid}; sending TERM", file=sys.stderr)
            signal.pidfd_send_signal(descriptor, signal.SIGTERM)
            if exited(5) or time.monotonic() >= deadline:
                return
            try:
                if self._shell_process_identity(pid) != started:
                    raise RuntimeFailure("shell drain: process identity changed; refusing KILL")
            except RuntimeFailure:
                if exited():
                    return
                raise
            if exited() or time.monotonic() >= deadline:
                return
            print(f"shibumi-suite: shell drain: TERM grace expired for PID {pid}; sending KILL", file=sys.stderr)
            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
            exited(2)  # Registry emptiness, not signal delivery, still proves success.
        except ProcessLookupError:
            return
        except OSError as error:
            raise RuntimeFailure(f"shell drain: signal fallback failed for PID {pid}: {error}") from error
        finally:
            os.close(descriptor)

    def stop_shell(
        self,
        *,
        timeout: float | None = None,
        quiet_period: float = 0.1,
    ) -> None:
        """Drain the exact Quattro registry until it remains stably empty."""
        shell_path = self.omarchy_root / "shell" if self.omarchy_root else None
        if shell_path is None:
            raise RuntimeFailure("cannot stop shell without an Omarchy root")
        initial_instances = None
        if timeout is None:
            initial_instances = self.shell_instances()
            # Freeze the budget once; respawns must never extend it. Per initial
            # instance: 30 s IPC, 5 s TERM, 2 s KILL, two 6 s registry reads,
            # and 1 s for preparation/quiet observation. Discovery is bounded
            # separately by shell_instances' existing 6-second limit.
            timeout = 50 * max(1, len(initial_instances))
        if timeout <= 0:
            raise RuntimeFailure("shell drain timeout must be positive")
        if quiet_period < 0:
            raise RuntimeFailure("shell drain quiet period cannot be negative")
        prepare_settle = 0.2
        kill_reserve = 0.05
        poll_interval = 0.05
        deadline = time.monotonic() + timeout
        evidence_deadline = deadline + 0.15
        final_snapshot_limit = 0.1
        empty_since: float | None = None
        snapshots: list[list[dict[str, Any]]] = []
        instances: list[dict[str, Any]] = []
        deadline_operation_error: str | None = None

        def evidence(values: list[dict[str, Any]]) -> list[dict[str, Any]]:
            return [
                {
                    "id": str(value.get("id") or ""),
                    "pid": value.get("pid"),
                    "config_path": str(value.get("config_path") or ""),
                }
                for value in values
            ]

        def record(values: list[dict[str, Any]]) -> None:
            snapshots.append(evidence(values))
            del snapshots[:-6]

        while time.monotonic() < deadline:
            registry_budget = deadline - time.monotonic()
            if registry_budget <= 0:
                break
            try:
                if initial_instances is not None:
                    instances = initial_instances
                    initial_instances = None
                else:
                    instances = self.shell_instances(timeout=min(6, registry_budget))
            except RuntimeFailure as error:
                if time.monotonic() < deadline:
                    raise
                deadline_operation_error = str(error)
                break
            record(instances)
            now = time.monotonic()

            if not instances:
                if empty_since is None:
                    empty_since = now
                if now - empty_since >= max(0.0, quiet_period - 1e-9):
                    return
                sleep_for = min(
                    poll_interval,
                    max(0.0, deadline - now),
                    max(0.0, quiet_period - (now - empty_since)),
                )
                if sleep_for > 0:
                    time.sleep(sleep_for)
                continue

            target = instances[0]
            pid = target.get("pid")
            if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
                raise RuntimeFailure(
                    "matching Omarchy shell instance has no valid PID"
                )
            prepared = False
            prepare_budget = (
                deadline - time.monotonic() - prepare_settle - kill_reserve
            )
            if prepare_budget > 0:
                try:
                    result = self.run(
                        [
                            "quickshell",
                            "ipc",
                            "--pid",
                            str(pid),
                            "call",
                            "shibumi-suite",
                            "prepareShutdown",
                        ],
                        timeout=min(0.25, prepare_budget),
                        check=False,
                    )
                except RuntimeFailure:
                    pass
                else:
                    prepared = (
                        result.returncode == 0
                        and result.stdout.strip() == "ok"
                    )
            if prepared:
                settle_budget = deadline - time.monotonic()
                if settle_budget > 0:
                    time.sleep(min(prepare_settle, settle_budget))

            kill_budget = deadline - time.monotonic()
            if kill_budget <= 0:
                break
            empty_since = None
            try:
                self.run(
                    ["quickshell", "kill", "--pid", str(pid)],
                    timeout=min(30, kill_budget),
                    check=False,
                )
            except RuntimeFailure as error:
                if time.monotonic() < deadline:
                    if isinstance(error.__cause__, subprocess.TimeoutExpired):
                        self._terminate_timed_out_shell(target, deadline)
                    else:
                        raise
                else:
                    deadline_operation_error = str(error)
                    break
            now = time.monotonic()
            if now < deadline:
                time.sleep(min(poll_interval, deadline - now))

        # The last in-flight command may have replaced the selected
        # registration. Spend at most the explicit evidence grace on one final
        # snapshot, retaining the last good evidence if that read itself fails.
        final_snapshot_error: str | None = None
        evidence_budget = evidence_deadline - time.monotonic()
        if evidence_budget > 0:
            try:
                instances = self.shell_instances(
                    timeout=min(final_snapshot_limit, evidence_budget)
                )
            except RuntimeFailure as error:
                final_snapshot_error = str(error)
            else:
                record(instances)
        else:
            final_snapshot_error = (
                "evidence deadline exhausted before final registry snapshot"
            )
        remaining = evidence(instances)
        detail = (
            "Quickshell registry did not converge before the drain deadline; "
            f"remaining={json.dumps(remaining, sort_keys=True)}; "
            f"snapshots={json.dumps(snapshots, sort_keys=True)}"
        )
        if deadline_operation_error is not None:
            detail += "; deadline_operation_error=" + json.dumps(
                deadline_operation_error
            )
        if final_snapshot_error is not None:
            detail += "; final_snapshot_error=" + json.dumps(
                final_snapshot_error
            )
        raise RuntimeFailure(detail)

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

    def refresh_menu(self, *, timeout: float = 8) -> None:
        command = [
            self.command("omarchy-shell"),
            "shell",
            "call",
            "omarchy.menu",
            "refresh",
            "{}",
        ]
        deadline = time.monotonic() + timeout
        detail = "Omarchy menu is not ready"
        while time.monotonic() < deadline:
            result = self.run(command, check=False)
            response = result.stdout.strip()
            if result.returncode == 0 and response in ("", "ok"):
                return
            detail = (result.stderr or result.stdout).strip() or (
                f"exit {result.returncode}"
            )
            time.sleep(0.1)
        raise RuntimeFailure(f"Omarchy menu refresh did not settle: {detail}")

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
                    self.verify_single_shell_instance()
                    self.verify_bar_layer_ownership("shibumi-bar")
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
                    self.verify_single_shell_instance()
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
                    self.verify_single_shell_instance()
                    self.verify_bar_layer_ownership("omarchy-bar")
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

    def verify_uninstall(
        self,
        plugin_ids: set[str],
        *,
        expected_bar_namespace: str = "omarchy-bar",
        timeout: float = 8,
    ) -> None:
        deadline = time.monotonic() + timeout
        detail = "removed plugins remain visible"
        while time.monotonic() < deadline:
            try:
                plugins = self.list_plugins()
                remaining = plugin_ids & plugins.keys()
                if not remaining:
                    self.verify_single_shell_instance()
                    self.verify_bar_layer_ownership(expected_bar_namespace)
                    self.ping()
                    return
                detail = f"remaining={sorted(remaining)}"
            except RuntimeFailure as error:
                detail = str(error)
            time.sleep(0.1)
        raise RuntimeFailure(f"Shibumi uninstall verification failed: {detail}")

    def reconcile_rollback(
        self,
        *,
        restart_required: bool,
        shell_was_stopped: bool,
        payload_reload_expected: bool,
    ) -> None:
        """Reconcile restored bytes without hiding a dead or stale shell."""
        if restart_required:
            try:
                self.restart_shell()
                return
            except RuntimeFailure as restart_error:
                if shell_was_stopped:
                    raise
                # A restart command may reject its own preflight before killing
                # the current process. Only that still-running case may use
                # ownership-preserving in-process rollback reconciliation.
                try:
                    self.verify_single_shell_instance()
                    self.ping()
                except RuntimeFailure:
                    raise restart_error

        actions = [self.rescan, self.reload_config]
        if payload_reload_expected:
            actions.append(self.reload_payload)
        actions.append(self.refresh_menu)
        failures: list[str] = []
        for action in actions:
            try:
                action()
            except RuntimeFailure as error:
                failures.append(f"{action.__name__}: {error}")
        if failures:
            raise RuntimeFailure(
                "rollback reconciliation failed: " + "; ".join(failures)
            )
        self.verify_single_shell_instance()
        self.ping()
