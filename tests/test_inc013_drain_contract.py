#!/usr/bin/env python3
"""Red contract tests for INC-013 registry-convergent shell draining.

Run from the repository root with:

    python3 tests/test_inc013_drain_contract.py

These tests intentionally exercise both production entry points without changing
either implementation.  Time is synthetic: no test sleeps on wall-clock time.
"""

from __future__ import annotations

import json
import runpy
import sys
import tempfile
import unittest
from dataclasses import dataclass, field
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import shibumi_suite.runtime as runtime_module  # noqa: E402


MANAGER_PATH = (
    ROOT
    / "hancore.shibumi.control-center"
    / "manager"
    / "shibumi-manager"
)
MANAGER = runpy.run_path(str(MANAGER_PATH))


@dataclass
class SyntheticClock:
    """Monotonic clock advanced only by observations or synthetic sleeps."""

    now: float = 0.0
    reads: int = 0

    def monotonic(self) -> float:
        value = self.now
        self.now += 0.01
        self.reads += 1
        return value

    def sleep(self, seconds: float) -> None:
        self.now += max(0.0, seconds)


@dataclass
class DrainScenario:
    """Deterministic fake for the Quickshell kill/list registry protocol."""

    root: Path
    matching_count: int
    foreign_count: int = 2
    behavior: str = "finite"
    temporary_respawns: int = 0
    post_empty_respawns: int = 0
    registry_malformed: bool = False
    matching: list[dict[str, object]] = field(init=False, default_factory=list)
    foreign: list[dict[str, object]] = field(init=False, default_factory=list)
    commands: list[tuple[str, ...]] = field(init=False, default_factory=list)
    kill_calls: int = field(init=False, default=0)
    registry_reads: int = field(init=False, default=0)
    next_pid: int = field(init=False, default=41000)

    def __post_init__(self) -> None:
        self.shell_path = self.root / "shell"
        self.config_path = self.shell_path / "shell.qml"
        self.foreign_config = self.root / "foreign" / "shell.qml"
        for _ in range(self.matching_count):
            self.matching.append(self._new_instance(self.config_path, "target"))
        for _ in range(self.foreign_count):
            self.foreign.append(self._new_instance(self.foreign_config, "foreign"))

    def _new_instance(self, config_path: Path, prefix: str) -> dict[str, object]:
        self.next_pid += 1
        return {
            "id": f"{prefix}-{self.next_pid}",
            "config_path": str(config_path),
            "pid": self.next_pid,
        }

    @property
    def remaining_ids(self) -> list[str]:
        return [str(instance["id"]) for instance in self.matching]

    def run(self, command, **_kwargs):
        argv = tuple(str(part) for part in command)
        self.commands.append(argv)

        if argv[:3] == ("quickshell", "kill", "-p"):
            return self._kill(argv)
        if argv == ("quickshell", "list", "--all", "--json"):
            return self._list()
        raise AssertionError(f"unexpected command in INC-013 contract: {argv!r}")

    def _kill(self, argv: tuple[str, ...]):
        expected = (
            "quickshell",
            "kill",
            "-p",
            str(self.shell_path),
            "--any-display",
        )
        if argv != expected:
            raise AssertionError(f"kill escaped exact Shibumi scope: {argv!r}")

        self.kill_calls += 1
        if not self.matching:
            return SimpleNamespace(returncode=1, stdout="", stderr="no instance")

        if self.behavior != "no-progress":
            self.matching.pop(0)

        if self.behavior == "permanent-respawn":
            self.matching.append(self._new_instance(self.config_path, "respawn"))
        elif self.temporary_respawns > 0:
            self.temporary_respawns -= 1
            self.matching.append(self._new_instance(self.config_path, "respawn"))

        return SimpleNamespace(returncode=0, stdout="", stderr="")

    def _list(self):
        self.registry_reads += 1
        if self.registry_malformed:
            return SimpleNamespace(returncode=0, stdout="{not-json", stderr="")
        payload = json.dumps([*self.matching, *self.foreign])
        # Model a process that appears only after an empty registry snapshot was
        # returned.  A single empty read is therefore not a stable drain proof.
        if not self.matching and self.post_empty_respawns > 0:
            self.post_empty_respawns -= 1
            self.matching.append(self._new_instance(self.config_path, "late-respawn"))
        return SimpleNamespace(returncode=0, stdout=payload, stderr="")


class ManagerAdapter:
    name = "standalone-manager"
    error_type = MANAGER["ManagerError"]

    @staticmethod
    def run(scenario: DrainScenario, clock: SyntheticClock) -> None:
        paths = {
            "omarchy_root": scenario.root,
            "shell": scenario.root / "bin" / "omarchy-shell",
        }
        stop_globals = MANAGER["stop_shell"].__globals__
        with (
            mock.patch.object(
                stop_globals["subprocess"],
                "run",
                side_effect=scenario.run,
            ),
            mock.patch.object(
                stop_globals["time"],
                "monotonic",
                side_effect=clock.monotonic,
            ),
            mock.patch.object(
                stop_globals["time"],
                "sleep",
                side_effect=clock.sleep,
            ),
        ):
            MANAGER["stop_shell"](paths)


class RuntimeAdapter:
    name = "suite-runtime"
    error_type = runtime_module.RuntimeFailure

    @staticmethod
    def run(scenario: DrainScenario, clock: SyntheticClock) -> None:
        runtime = runtime_module.OmarchyRuntime(scenario.root)
        with (
            mock.patch.object(runtime, "run", side_effect=scenario.run),
            mock.patch.object(
                runtime_module.time,
                "monotonic",
                side_effect=clock.monotonic,
            ),
            mock.patch.object(
                runtime_module.time,
                "sleep",
                side_effect=clock.sleep,
            ),
        ):
            runtime.stop_shell()


ADAPTERS = (ManagerAdapter, RuntimeAdapter)


class Incident013DrainContractTests(unittest.TestCase):
    """Behavioral contract: drain to stable registry emptiness, not a count cap."""

    def make_scenario(self, temporary_root: str, **kwargs) -> DrainScenario:
        return DrainScenario(root=Path(temporary_root) / "omarchy", **kwargs)

    def test_all_finite_populations_converge_without_touching_foreign_instances(self):
        for adapter in ADAPTERS:
            for count in (0, 1, 2, 8, 9, 20):
                with self.subTest(path=adapter.name, count=count), tempfile.TemporaryDirectory() as tmp:
                    scenario = self.make_scenario(tmp, matching_count=count)
                    foreign_before = tuple(scenario.foreign)

                    adapter.run(scenario, SyntheticClock())

                    self.assertEqual([], scenario.matching)
                    self.assertEqual(foreign_before, tuple(scenario.foreign))
                    self.assertGreater(
                        scenario.registry_reads,
                        0,
                        "success must be proved by the authoritative registry",
                    )

    def test_temporary_respawn_still_converges(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                scenario = self.make_scenario(
                    tmp,
                    matching_count=1,
                    temporary_respawns=10,
                )

                adapter.run(scenario, SyntheticClock())

                self.assertEqual([], scenario.matching)
                self.assertGreaterEqual(scenario.kill_calls, 11)
                self.assertGreater(scenario.registry_reads, 0)

    def test_respawn_during_empty_quiet_window_is_not_missed(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                scenario = self.make_scenario(
                    tmp,
                    matching_count=1,
                    post_empty_respawns=1,
                )

                adapter.run(scenario, SyntheticClock())

                self.assertEqual([], scenario.matching)
                self.assertGreaterEqual(
                    scenario.registry_reads,
                    2,
                    "success requires an empty-registry quiet window",
                )

    def test_permanent_respawn_fails_on_monotonic_deadline_with_registry_evidence(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                scenario = self.make_scenario(
                    tmp,
                    matching_count=1,
                    behavior="permanent-respawn",
                )
                clock = SyntheticClock()

                with self.assertRaises(adapter.error_type) as raised:
                    adapter.run(scenario, clock)

                message = str(raised.exception)
                self.assertGreater(clock.reads, 0, "failure must use a monotonic deadline")
                self.assertRegex(message.lower(), r"drain|converg|deadline")
                self.assertTrue(
                    any(instance_id in message for instance_id in scenario.remaining_ids),
                    f"failure lacks remaining registry evidence: {message}",
                )

    def test_no_progress_fails_on_monotonic_deadline_with_registry_evidence(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                scenario = self.make_scenario(
                    tmp,
                    matching_count=2,
                    behavior="no-progress",
                )
                clock = SyntheticClock()

                with self.assertRaises(adapter.error_type) as raised:
                    adapter.run(scenario, clock)

                message = str(raised.exception)
                self.assertGreater(clock.reads, 0, "failure must use a monotonic deadline")
                self.assertRegex(message.lower(), r"progress|drain|converg|deadline")
                self.assertTrue(
                    any(instance_id in message for instance_id in scenario.remaining_ids),
                    f"failure lacks remaining registry evidence: {message}",
                )

    def test_foreign_only_registry_is_success_without_cross_targeting(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                scenario = self.make_scenario(tmp, matching_count=0, foreign_count=3)
                foreign_before = tuple(scenario.foreign)

                adapter.run(scenario, SyntheticClock())

                self.assertEqual(foreign_before, tuple(scenario.foreign))
                self.assertGreater(
                    scenario.registry_reads,
                    0,
                    "foreign-only success must still be registry-proven",
                )

    def test_malformed_registry_fails_closed(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                scenario = self.make_scenario(
                    tmp,
                    matching_count=1,
                    registry_malformed=True,
                )

                with self.assertRaises(adapter.error_type) as raised:
                    adapter.run(scenario, SyntheticClock())

                self.assertGreater(scenario.registry_reads, 0)
                self.assertRegex(
                    str(raised.exception).lower(),
                    r"registry|json|malformed|inspect",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
