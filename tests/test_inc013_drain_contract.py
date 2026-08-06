#!/usr/bin/env python3
"""Red contract tests for INC-013 registry-convergent shell draining.

Run from the repository root with:

    python3 tests/test_inc013_drain_contract.py

These tests intentionally exercise both production entry points without changing
either implementation.  Time is synthetic: no test sleeps on wall-clock time.
"""

from __future__ import annotations

import json
import math
import runpy
import subprocess
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

CONTRACT_QUIET_SECONDS = 0.1
SHORT_DEADLINE_SECONDS = 0.2
LONG_DEADLINE_SECONDS = 0.6
DEADLINE_OVERRUN_SECONDS = CONTRACT_QUIET_SECONDS + 0.05
COMMAND_LATENCY_PROFILES = {
    "fast": (0.005, 0.008),
    "slow": (0.04, 0.06),
}


@dataclass
class SyntheticClock:
    """Monotonic clock advanced only by synthetic sleeps."""

    now: float = 0.0
    reads: int = 0
    sleeps: list[float] = field(default_factory=list)
    command_delays: list[float] = field(default_factory=list)
    read_advances: dict[int, float] = field(default_factory=dict)

    def monotonic(self) -> float:
        self.reads += 1
        self.now += max(0.0, self.read_advances.get(self.reads, 0.0))
        return self.now

    def sleep(self, seconds: float) -> None:
        duration = max(0.0, seconds)
        self.sleeps.append(duration)
        self.now += duration

    def advance_command(self, seconds: float) -> None:
        duration = max(0.0, seconds)
        self.command_delays.append(duration)
        self.now += duration


@dataclass
class DrainScenario:
    """Deterministic fake for the Quickshell kill/list registry protocol."""

    root: Path
    matching_count: int
    foreign_count: int = 2
    behavior: str = "finite"
    temporary_respawns: int = 0
    clock: SyntheticClock | None = None
    timed_empty_respawn_delay: float | None = None
    registry_latency: float = 0.0
    kill_latency: float = 0.0
    registry_malformed: bool = False
    registry_latencies: list[float] = field(default_factory=list)
    registry_malformed_reads: set[int] = field(default_factory=set)
    matching: list[dict[str, object]] = field(init=False, default_factory=list)
    foreign: list[dict[str, object]] = field(init=False, default_factory=list)
    commands: list[tuple[str, ...]] = field(init=False, default_factory=list)
    kill_calls: int = field(init=False, default=0)
    registry_reads: int = field(init=False, default=0)
    next_pid: int = field(init=False, default=41000)
    empty_started_at: float | None = field(init=False, default=None)
    timed_respawn_injected_at: float | None = field(init=False, default=None)
    empty_snapshot_times: list[float] = field(init=False, default_factory=list)

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

    def run(self, command, **kwargs):
        argv = tuple(str(part) for part in command)
        self.commands.append(argv)
        if len(self.commands) > 5000:
            now = self.clock.now if self.clock is not None else "unbound"
            raise AssertionError(
                "INC-013 candidate did not terminate: "
                f"clock={now} reads={self.registry_reads} "
                f"kills={self.kill_calls} remaining={self.remaining_ids}"
            )

        if argv[:3] == ("quickshell", "kill", "-p"):
            self._advance_command(argv, self.kill_latency, kwargs.get("timeout"))
            return self._kill(argv)
        if argv == ("quickshell", "list", "--all", "--json"):
            latency = (
                self.registry_latencies[self.registry_reads]
                if self.registry_reads < len(self.registry_latencies)
                else self.registry_latency
            )
            self._advance_command(argv, latency, kwargs.get("timeout"))
            return self._list()
        raise AssertionError(f"unexpected command in INC-013 contract: {argv!r}")

    def _advance_command(
        self,
        argv: tuple[str, ...],
        latency: float,
        timeout: float | None,
    ) -> None:
        if self.clock is None:
            return
        if timeout is not None and latency > timeout:
            self.clock.advance_command(timeout)
            raise subprocess.TimeoutExpired(argv, timeout)
        self.clock.advance_command(latency)

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
            if not self.matching:
                self.empty_started_at = None

        if self.behavior == "permanent-respawn":
            self.matching.append(self._new_instance(self.config_path, "respawn"))
        elif self.temporary_respawns > 0:
            self.temporary_respawns -= 1
            self.matching.append(self._new_instance(self.config_path, "respawn"))

        return SimpleNamespace(returncode=0, stdout="", stderr="")

    def _list(self):
        self.registry_reads += 1
        if (
            self.registry_malformed
            or self.registry_reads in self.registry_malformed_reads
        ):
            return SimpleNamespace(returncode=0, stdout="{not-json", stderr="")

        now = self.clock.now if self.clock is not None else 0.0
        if not self.matching:
            if self.empty_started_at is None:
                self.empty_started_at = now
            self.empty_snapshot_times.append(now)
            due_at = (
                self.empty_started_at + self.timed_empty_respawn_delay
                if self.timed_empty_respawn_delay is not None
                else None
            )
            if (
                due_at is not None
                and self.timed_respawn_injected_at is None
                and now >= due_at
            ):
                self.matching.append(
                    self._new_instance(self.config_path, "late-respawn")
                )
                self.timed_respawn_injected_at = now
                self.empty_started_at = None
        else:
            self.empty_started_at = None

        payload = json.dumps([*self.matching, *self.foreign])
        return SimpleNamespace(returncode=0, stdout=payload, stderr="")


class ManagerAdapter:
    name = "standalone-manager"
    error_type = MANAGER["ManagerError"]

    @staticmethod
    def run(
        scenario: DrainScenario,
        clock: SyntheticClock,
        *,
        timeout: float | None = None,
        quiet_period: float | None = None,
    ) -> None:
        if scenario.clock is None:
            scenario.clock = clock
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
            timing = {}
            if timeout is not None:
                timing["timeout"] = timeout
            if quiet_period is not None:
                timing["quiet_period"] = quiet_period
            MANAGER["stop_shell"](paths, **timing)


class RuntimeAdapter:
    name = "suite-runtime"
    error_type = runtime_module.RuntimeFailure

    @staticmethod
    def run(
        scenario: DrainScenario,
        clock: SyntheticClock,
        *,
        timeout: float | None = None,
        quiet_period: float | None = None,
    ) -> None:
        if scenario.clock is None:
            scenario.clock = clock
        runtime = runtime_module.OmarchyRuntime(scenario.root)

        def runtime_run(command, **kwargs):
            try:
                return scenario.run(command, **kwargs)
            except (OSError, subprocess.SubprocessError) as error:
                raise runtime_module.RuntimeFailure(
                    f"cannot run {' '.join(str(part) for part in command)}: {error}"
                ) from error

        with (
            mock.patch.object(runtime, "run", side_effect=runtime_run),
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
            timing = {}
            if timeout is not None:
                timing["timeout"] = timeout
            if quiet_period is not None:
                timing["quiet_period"] = quiet_period
            runtime.stop_shell(**timing)


ADAPTERS = (ManagerAdapter, RuntimeAdapter)


def assert_deadline_failure(
    testcase: unittest.TestCase,
    adapter,
    scenario: DrainScenario,
    clock: SyntheticClock,
    timeout: float,
) -> int:
    """Require time-bounded nonconvergence, never an attempt-count failure."""

    with testcase.assertRaises(adapter.error_type) as raised:
        adapter.run(
            scenario,
            clock,
            timeout=timeout,
            quiet_period=CONTRACT_QUIET_SECONDS,
        )

    elapsed = clock.now
    testcase.assertGreaterEqual(
        elapsed,
        timeout,
        "nonconvergence failed before the requested monotonic deadline",
    )
    testcase.assertLessEqual(
        elapsed,
        timeout + DEADLINE_OVERRUN_SECONDS,
        "nonconvergence followed an attempt cap instead of the requested deadline",
    )
    testcase.assertTrue(clock.sleeps, "deadline polling must not busy-spin")
    testcase.assertTrue(
        clock.command_delays,
        "deadline profile did not include command execution time",
    )

    message = str(raised.exception)
    testcase.assertRegex(message.lower(), r"progress|drain|converg|deadline")
    testcase.assertTrue(
        any(instance_id in message for instance_id in scenario.remaining_ids),
        f"failure lacks remaining registry evidence: {message}",
    )
    return scenario.kill_calls


def assert_quiet_window_convergence(
    testcase: unittest.TestCase,
    adapter,
    scenario: DrainScenario,
    clock: SyntheticClock,
) -> None:
    """Require elapsed stable-empty time and catch a respawn inside that time."""

    adapter.run(
        scenario,
        clock,
        timeout=LONG_DEADLINE_SECONDS,
        quiet_period=CONTRACT_QUIET_SECONDS,
    )

    testcase.assertEqual([], scenario.matching)
    testcase.assertIsNotNone(
        scenario.timed_respawn_injected_at,
        "the candidate returned before the within-window respawn became observable",
    )
    testcase.assertIsNotNone(scenario.empty_started_at)
    testcase.assertGreaterEqual(
        clock.now - scenario.empty_started_at,
        CONTRACT_QUIET_SECONDS,
        "success preceded the required elapsed stable-empty quiet period",
    )
    testcase.assertTrue(clock.sleeps, "quiet-window polling must not busy-spin")


class MutationCandidateError(RuntimeError):
    pass


class FixedCapImmediateEmptyMutation:
    """Deliberately wrong candidate used to prove the temporal contract is live."""

    name = "fixed-100-immediate-double-empty"
    error_type = MutationCandidateError

    @staticmethod
    def run(
        scenario: DrainScenario,
        clock: SyntheticClock,
        *,
        timeout: float | None = None,
        quiet_period: float | None = None,
    ) -> None:
        del timeout, quiet_period
        clock.monotonic()  # Pro-forma only: never compared with a deadline.
        empty_snapshots = 0
        for _attempt in range(100):
            result = scenario.run(["quickshell", "list", "--all", "--json"])
            try:
                values = json.loads(result.stdout)
            except (TypeError, json.JSONDecodeError) as error:
                raise MutationCandidateError("registry malformed JSON") from error
            expected = str(scenario.config_path.resolve(strict=False))
            matching = [
                value
                for value in values
                if isinstance(value, dict)
                and isinstance(value.get("config_path"), str)
                and str(Path(value["config_path"]).resolve(strict=False))
                == expected
            ]
            if not matching:
                empty_snapshots += 1
                if empty_snapshots >= 2:
                    return
                continue
            empty_snapshots = 0
            scenario.run(
                [
                    "quickshell",
                    "kill",
                    "-p",
                    str(scenario.shell_path),
                    "--any-display",
                ]
            )
        remaining = ",".join(scenario.remaining_ids)
        raise MutationCandidateError(
            f"drain deadline reached without progress; remaining={remaining}"
        )


class TimeoutDerivedAttemptBudgetMutation:
    """Wrong candidate deriving counts from timeout while ignoring command time."""

    name = "timeout-derived-attempt-budget"
    error_type = MutationCandidateError

    @staticmethod
    def run(
        scenario: DrainScenario,
        clock: SyntheticClock,
        *,
        timeout: float | None = None,
        quiet_period: float | None = None,
    ) -> None:
        poll = 0.05
        effective_timeout = 5.0 if timeout is None else timeout
        effective_quiet = 0.1 if quiet_period is None else quiet_period
        attempts = math.ceil(effective_timeout / poll)
        empty_attempts_needed = math.ceil(effective_quiet / poll)
        clock.monotonic()  # Pro-forma only: command latency is never observed.
        empty_attempts = 0
        for _attempt in range(attempts):
            result = scenario.run(["quickshell", "list", "--all", "--json"])
            try:
                values = json.loads(result.stdout)
            except (TypeError, json.JSONDecodeError) as error:
                raise MutationCandidateError("registry malformed JSON") from error
            expected = str(scenario.config_path.resolve(strict=False))
            matching = [
                value
                for value in values
                if isinstance(value, dict)
                and isinstance(value.get("config_path"), str)
                and str(Path(value["config_path"]).resolve(strict=False))
                == expected
            ]
            if matching:
                empty_attempts = 0
                scenario.run(
                    [
                        "quickshell",
                        "kill",
                        "-p",
                        str(scenario.shell_path),
                        "--any-display",
                    ]
                )
            else:
                empty_attempts += 1
                if empty_attempts > empty_attempts_needed:
                    clock.sleep(poll)
                    return
            clock.sleep(poll)
        remaining = ",".join(scenario.remaining_ids)
        raise MutationCandidateError(
            f"drain deadline reached without progress; remaining={remaining}"
        )


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
                    if count == 0:
                        self.assertEqual(
                            0,
                            scenario.kill_calls,
                            "an empty matching registry must not issue a kill",
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
            for profile, latencies in COMMAND_LATENCY_PROFILES.items():
                with self.subTest(path=adapter.name, latency=profile), tempfile.TemporaryDirectory() as tmp:
                    clock = SyntheticClock()
                    scenario = self.make_scenario(
                        tmp,
                        matching_count=1,
                        clock=clock,
                        timed_empty_respawn_delay=CONTRACT_QUIET_SECONDS / 2,
                        registry_latency=latencies[0],
                        kill_latency=latencies[1],
                    )

                    assert_quiet_window_convergence(
                        self,
                        adapter,
                        scenario,
                        clock,
                    )

    def test_permanent_respawn_fails_on_monotonic_deadline_with_registry_evidence(self):
        for adapter in ADAPTERS:
            for profile, latencies in COMMAND_LATENCY_PROFILES.items():
                kill_counts = []
                for timeout in (SHORT_DEADLINE_SECONDS, LONG_DEADLINE_SECONDS):
                    with self.subTest(
                        path=adapter.name,
                        latency=profile,
                        timeout=timeout,
                    ), tempfile.TemporaryDirectory() as tmp:
                        clock = SyntheticClock()
                        scenario = self.make_scenario(
                            tmp,
                            matching_count=1,
                            behavior="permanent-respawn",
                            clock=clock,
                            registry_latency=latencies[0],
                            kill_latency=latencies[1],
                        )
                        kill_counts.append(
                            assert_deadline_failure(
                                self,
                                adapter,
                                scenario,
                                clock,
                                timeout,
                            )
                        )
                self.assertEqual(
                    2,
                    len(kill_counts),
                    "both requested deadline profiles must complete",
                )
                self.assertGreater(
                    kill_counts[1],
                    kill_counts[0],
                    "work remained tied to a fixed attempt count instead of elapsed time",
                )

    def test_no_progress_fails_on_monotonic_deadline_with_registry_evidence(self):
        for adapter in ADAPTERS:
            for profile, latencies in COMMAND_LATENCY_PROFILES.items():
                with self.subTest(path=adapter.name, latency=profile), tempfile.TemporaryDirectory() as tmp:
                    clock = SyntheticClock()
                    scenario = self.make_scenario(
                        tmp,
                        matching_count=2,
                        behavior="no-progress",
                        clock=clock,
                        registry_latency=latencies[0],
                        kill_latency=latencies[1],
                    )
                    assert_deadline_failure(
                        self,
                        adapter,
                        scenario,
                        clock,
                        SHORT_DEADLINE_SECONDS,
                    )

    def test_slow_final_snapshot_stays_inside_total_evidence_budget(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                clock = SyntheticClock()
                scenario = self.make_scenario(
                    tmp,
                    matching_count=1,
                    behavior="permanent-respawn",
                    clock=clock,
                    registry_latencies=[0.18, 0.19],
                    kill_latency=0.015,
                )
                last_good_id = scenario.remaining_ids[0]

                with self.assertRaises(adapter.error_type) as raised:
                    adapter.run(
                        scenario,
                        clock,
                        timeout=SHORT_DEADLINE_SECONDS,
                        quiet_period=CONTRACT_QUIET_SECONDS,
                    )

                self.assertLessEqual(
                    clock.now,
                    SHORT_DEADLINE_SECONDS + DEADLINE_OVERRUN_SECONDS,
                    "the final evidence read escaped the total deadline budget",
                )
                message = str(raised.exception)
                self.assertIn(last_good_id, message)
                self.assertIn("snapshots=", message)
                self.assertIn("final_snapshot_error=", message)
                self.assertRegex(message.lower(), r"timed out|timeout")

    def test_registry_read_reaching_deadline_never_starts_a_kill(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                clock = SyntheticClock()
                scenario = self.make_scenario(
                    tmp,
                    matching_count=1,
                    clock=clock,
                    registry_latency=SHORT_DEADLINE_SECONDS,
                    kill_latency=0.0005,
                )

                with self.assertRaises(adapter.error_type) as raised:
                    adapter.run(
                        scenario,
                        clock,
                        timeout=SHORT_DEADLINE_SECONDS,
                        quiet_period=CONTRACT_QUIET_SECONDS,
                    )

                self.assertEqual(
                    0,
                    scenario.kill_calls,
                    "a mutating kill started after the drain deadline",
                )
                self.assertIn(scenario.remaining_ids[0], str(raised.exception))
                self.assertLessEqual(
                    clock.now,
                    SHORT_DEADLINE_SECONDS + DEADLINE_OVERRUN_SECONDS,
                )

    def test_expired_fresh_kill_budget_never_uses_a_positive_floor(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                clock = SyntheticClock(read_advances={5: 0.0002})
                scenario = self.make_scenario(
                    tmp,
                    matching_count=1,
                    clock=clock,
                    registry_latency=SHORT_DEADLINE_SECONDS - 0.0001,
                    kill_latency=0.0001,
                )

                with self.assertRaises(adapter.error_type):
                    adapter.run(
                        scenario,
                        clock,
                        timeout=SHORT_DEADLINE_SECONDS,
                        quiet_period=CONTRACT_QUIET_SECONDS,
                    )

                self.assertEqual(
                    0,
                    scenario.kill_calls,
                    "expired kill budget was rounded up into a mutating command",
                )
                self.assertGreaterEqual(clock.now, SHORT_DEADLINE_SECONDS)
                self.assertLessEqual(
                    clock.now,
                    SHORT_DEADLINE_SECONDS + DEADLINE_OVERRUN_SECONDS,
                )

    def test_malformed_final_snapshot_retains_last_good_evidence(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                clock = SyntheticClock()
                scenario = self.make_scenario(
                    tmp,
                    matching_count=1,
                    behavior="permanent-respawn",
                    clock=clock,
                    registry_latencies=[0.18, 0.01],
                    registry_malformed_reads={2},
                    kill_latency=0.015,
                )
                last_good_id = scenario.remaining_ids[0]

                with self.assertRaises(adapter.error_type) as raised:
                    adapter.run(
                        scenario,
                        clock,
                        timeout=SHORT_DEADLINE_SECONDS,
                        quiet_period=CONTRACT_QUIET_SECONDS,
                    )

                message = str(raised.exception)
                self.assertLessEqual(
                    clock.now,
                    SHORT_DEADLINE_SECONDS + DEADLINE_OVERRUN_SECONDS,
                )
                self.assertIn(last_good_id, message)
                self.assertIn("remaining=", message)
                self.assertIn("snapshots=", message)
                self.assertIn("final_snapshot_error=", message)
                self.assertRegex(message.lower(), r"json|malformed")

    def test_foreign_only_registry_is_success_without_cross_targeting(self):
        for adapter in ADAPTERS:
            with self.subTest(path=adapter.name), tempfile.TemporaryDirectory() as tmp:
                scenario = self.make_scenario(tmp, matching_count=0, foreign_count=3)
                foreign_before = tuple(scenario.foreign)

                adapter.run(scenario, SyntheticClock())

                self.assertEqual(foreign_before, tuple(scenario.foreign))
                self.assertEqual(0, scenario.kill_calls)
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
                self.assertEqual(
                    0,
                    scenario.kill_calls,
                    "a broken registry must fail before any kill",
                )
                self.assertRegex(
                    str(raised.exception).lower(),
                    r"registry|json|malformed|inspect",
                )


class Incident013ContractMutationTests(unittest.TestCase):
    """Prove the contract kills the two reviewer-supplied false fixes."""

    def test_fixed_high_attempt_cap_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            clock = SyntheticClock()
            scenario = DrainScenario(
                root=Path(tmp) / "omarchy",
                matching_count=1,
                behavior="permanent-respawn",
                clock=clock,
            )
            with self.assertRaises(AssertionError):
                assert_deadline_failure(
                    self,
                    FixedCapImmediateEmptyMutation,
                    scenario,
                    clock,
                    SHORT_DEADLINE_SECONDS,
                )

    def test_immediate_double_empty_snapshot_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            clock = SyntheticClock()
            scenario = DrainScenario(
                root=Path(tmp) / "omarchy",
                matching_count=1,
                clock=clock,
                timed_empty_respawn_delay=CONTRACT_QUIET_SECONDS / 2,
            )
            with self.assertRaises(AssertionError):
                assert_quiet_window_convergence(
                    self,
                    FixedCapImmediateEmptyMutation,
                    scenario,
                    clock,
                )

    def test_timeout_derived_attempt_budget_ignoring_command_time_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            clock = SyntheticClock()
            latencies = COMMAND_LATENCY_PROFILES["slow"]
            scenario = DrainScenario(
                root=Path(tmp) / "omarchy",
                matching_count=1,
                behavior="permanent-respawn",
                clock=clock,
                registry_latency=latencies[0],
                kill_latency=latencies[1],
            )
            with self.assertRaises(AssertionError):
                assert_deadline_failure(
                    self,
                    TimeoutDerivedAttemptBudgetMutation,
                    scenario,
                    clock,
                    SHORT_DEADLINE_SECONDS,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
