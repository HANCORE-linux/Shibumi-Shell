#!/usr/bin/env python3
"""Fail-closed unit contract for the Native Catalog resource gate."""

from __future__ import annotations

import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
if str(TESTS) not in sys.path:
    sys.path.insert(0, str(TESTS))
sys.dont_write_bytecode = True


def load_resource_gate():
    path = TESTS / "native-catalog-resource-regression.py"
    spec = importlib.util.spec_from_file_location(
        "shibumi_native_catalog_resource_contract", path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("resource gate cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


RESOURCE = load_resource_gate()


def measurement_output(cold=None, warm=None):
    cold_record = {
        "baselinePssKiB": 100,
        "cycleCpuSeconds": [0.01, 0.02, 0.03],
        "cycles": 3,
        "maximumPssOverBaselineKiB": 30,
        "pssKiB": [110, 120, 130],
        "requestSerials": [3, 4, 5],
    }
    warm_record = {
        "baselinePssKiB": 130,
        "cycleCpuSeconds": [0.01, 0.02, 0.03],
        "cycles": 3,
        "maximumPssOverBaselineKiB": 2,
        "pssKiB": [129, 132, 131],
        "requestSerials": [6, 7, 8],
        "unchangedCeilingKiB": 512,
    }
    if cold is not None:
        cold_record = cold
    if warm is not None:
        warm_record = warm
    return (
        "NATIVE_CATALOG_RESOURCE_COLD_INITIALIZATION "
        + json.dumps(cold_record, allow_nan=True)
        + "\nNATIVE_CATALOG_RESOURCE_WARM_MEASUREMENT "
        + json.dumps(warm_record, allow_nan=True)
        + "\n"
    )


class NativeCatalogResourceContract(unittest.TestCase):
    def test_three_plus_three_parser_rejects_ambiguous_numbers_and_serials(self):
        accepted = RESOURCE.require_three_plus_three_measurement(measurement_output())
        self.assertEqual(accepted["warm"]["requestSerials"], [6, 7, 8])

        base_cold = json.loads(
            measurement_output().splitlines()[0].split(" ", 1)[1]
        )
        base_warm = json.loads(
            measurement_output().splitlines()[1].split(" ", 1)[1]
        )
        cases = []
        cold = copy.deepcopy(base_cold)
        cold["cycles"] = 3.0
        cases.append(("float cycle count", measurement_output(cold=cold)))
        warm = copy.deepcopy(base_warm)
        warm["baselinePssKiB"] = 130.0
        cases.append(("float warm baseline", measurement_output(warm=warm)))
        warm = copy.deepcopy(base_warm)
        warm["unchangedCeilingKiB"] = 512.0
        cases.append(("float ceiling", measurement_output(warm=warm)))
        cold = copy.deepcopy(base_cold)
        cold.update({
            "baselinePssKiB": 1,
            "maximumPssOverBaselineKiB": 0,
            "pssKiB": [1, 1, 1],
        })
        warm = copy.deepcopy(base_warm)
        warm.update({
            "baselinePssKiB": True,
            "maximumPssOverBaselineKiB": 0,
            "pssKiB": [1, 1, 1],
        })
        cases.append(("boolean warm baseline", measurement_output(cold, warm)))
        for invalid_cpu in (math.nan, math.inf, "0.1", None, -0.1):
            cold = copy.deepcopy(base_cold)
            cold["cycleCpuSeconds"][1] = invalid_cpu
            cases.append(("invalid CPU", measurement_output(cold=cold)))
        cold = copy.deepcopy(base_cold)
        cold["cycleCpuSeconds"][1] = 1e300
        overflow_float = measurement_output(cold=cold).replace("1e+300", "1e400")
        cases.append(("overflow float", overflow_float))
        for invalid_serials in (
                [3, 3, 5], [3, 4, 6], [3, 4, 5.0], [3, 4, "5"]):
            cold = copy.deepcopy(base_cold)
            cold["requestSerials"] = invalid_serials
            cases.append(("invalid serials", measurement_output(cold=cold)))
        warm = copy.deepcopy(base_warm)
        warm["requestSerials"] = [7, 8, 9]
        cases.append(("cross-phase serial gap", measurement_output(warm=warm)))
        cold = copy.deepcopy(base_cold)
        cold["unexpected"] = True
        cases.append(("unknown field", measurement_output(cold=cold)))

        for label, output in cases:
            with self.subTest(label=label):
                with self.assertRaises(RuntimeError):
                    RESOURCE.require_three_plus_three_measurement(output)

    def test_bounded_command_accepts_boundary_and_kills_over_limit_process(self):
        exact = RESOURCE.bounded_command(
            [sys.executable, "-c", "import os; os.write(1, b'abcd')"],
            ROOT,
            4,
            5,
        )
        self.assertEqual(exact, b"abcd")

        with tempfile.TemporaryDirectory(
                prefix="shibumi-resource-bound-", dir="/tmp") as temporary:
            pid_path = Path(temporary) / "pid"
            script = (
                "import os,sys,time; "
                f"open({str(pid_path)!r}, 'w').write(str(os.getpid())); "
                "os.write(1, b'x' * 4096); time.sleep(30)"
            )
            with self.assertRaisesRegex(RuntimeError, "output exceeded limit"):
                RESOURCE.bounded_command(
                    [sys.executable, "-c", script], ROOT, 4, 5
                )
            pid = int(pid_path.read_text(encoding="ascii"))
            for _ in range(50):
                if not Path(f"/proc/{pid}").exists():
                    break
                time.sleep(0.01)
            self.assertFalse(Path(f"/proc/{pid}").exists())

    def test_git_replacement_refs_are_rejected_and_git_overrides_are_ignored(self):
        with tempfile.TemporaryDirectory(
                prefix="shibumi-resource-git-", dir="/tmp") as temporary:
            repository = Path(temporary)

            def git(*arguments):
                return subprocess.run(
                    [RESOURCE.GIT, *arguments],
                    cwd=repository,
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout.strip()

            git("init", "--quiet")
            (repository / "record").write_text("original\n", encoding="utf-8")
            git("add", "record")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture.invalid",
                "commit", "--quiet", "-m", "original")
            original = git("rev-parse", "HEAD")
            (repository / "record").write_text("replacement\n", encoding="utf-8")
            git("add", "record")
            git("-c", "user.name=Fixture", "-c", "user.email=fixture.invalid",
                "commit", "--quiet", "-m", "replacement")
            replacement = git("rev-parse", "HEAD")
            git("replace", original, replacement)

            native = SimpleNamespace(PLUGINS=("hancore.shibumi.bar",))
            with patch.object(RESOURCE, "ROOT", repository), \
                    patch.object(RESOURCE, "BETA13_COMMIT", original):
                with self.assertRaisesRegex(RuntimeError, "replacement refs"):
                    RESOURCE.materialize_exact_beta13(
                        native, repository / "materialized"
                    )
                with patch.dict(os.environ, {
                    "GIT_DIR": str(repository / "missing"),
                    "GIT_NO_REPLACE_OBJECTS": "0",
                }):
                    resolved = RESOURCE.run_git(
                        ["rev-parse", "--verify", original + "^{commit}"],
                        128,
                        5,
                    ).decode("ascii").strip()
            self.assertEqual(resolved, original)
            self.assertFalse((repository / "materialized").exists())

    def test_roster_rejects_broad_or_reordered_pathspecs(self):
        native = SimpleNamespace(PLUGINS=("hancore.shibumi.bar",))
        exact = {"plugins": [{"id": value} for value in RESOURCE.EXPECTED_PLUGIN_IDS]}
        self.assertEqual(
            RESOURCE.require_current_plugin_roster(exact, native),
            RESOURCE.EXPECTED_PLUGIN_IDS,
        )
        for invalid in (
                {"plugins": [{"id": "."}]},
                {"plugins": list(reversed(exact["plugins"]))},
                {"plugins": exact["plugins"][:-1]}):
            with self.assertRaisesRegex(RuntimeError, "24-plugin roster"):
                RESOURCE.require_current_plugin_roster(invalid, native)


if __name__ == "__main__":
    unittest.main(verbosity=2)
