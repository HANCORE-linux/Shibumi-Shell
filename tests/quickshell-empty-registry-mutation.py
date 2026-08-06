#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PRODUCTION_PATHS = (
    Path("hancore.shibumi.control-center/manager/shibumi-manager"),
    Path("scripts/shibumi_suite/runtime.py"),
    Path("hancore.shibumi.control-center/manager/shibumi-health"),
)
EXACT_GUARD = 'if result.stdout == "No running instances.\\n":'
MUTATIONS = {
    "missing-sentinel": (
        'if False and result.stdout == "No running instances.\\n":',
        (
            "tests.test_shibumi_manager.ContinuityManagerTests."
            "test_empty_quickshell_registry_sentinel_is_an_empty_array",
            "tests.test_shibumi_suite.RuntimeProcessTests."
            "test_empty_quickshell_registry_sentinel_is_an_empty_array",
            "tests.test_shibumi_health.HealthDiagnosticsTests."
            "test_empty_quickshell_registry_sentinel_reports_zero_processes",
        ),
    ),
    "strip-sentinel": (
        'if result.stdout.strip() == "No running instances.":',
        (
            "tests.test_shibumi_manager.ContinuityManagerTests."
            "test_empty_registry_sentinel_variants_fail_closed",
            "tests.test_shibumi_suite.RuntimeProcessTests."
            "test_empty_registry_sentinel_variants_fail_closed",
            "tests.test_shibumi_health.HealthDiagnosticsTests."
            "test_empty_registry_sentinel_variants_fail_closed",
        ),
    ),
    "startswith-sentinel": (
        'if result.stdout.startswith("No running instances.\\n"):',
        (
            "tests.test_shibumi_manager.ContinuityManagerTests."
            "test_empty_registry_sentinel_variants_fail_closed",
            "tests.test_shibumi_suite.RuntimeProcessTests."
            "test_empty_registry_sentinel_variants_fail_closed",
            "tests.test_shibumi_health.HealthDiagnosticsTests."
            "test_empty_registry_sentinel_variants_fail_closed",
        ),
    ),
}


def mutate_checkout(root: Path, replacement: str) -> None:
    for relative in PRODUCTION_PATHS:
        path = root / relative
        source = path.read_text(encoding="utf-8")
        if source.count(EXACT_GUARD) != 1:
            raise AssertionError(f"expected one exact sentinel guard in {relative}")
        path.write_text(source.replace(EXACT_GUARD, replacement), encoding="utf-8")


def assert_mutation_is_killed(name: str, replacement: str, tests: tuple[str, ...]) -> None:
    with tempfile.TemporaryDirectory(prefix=f"inc013-{name}.") as temporary:
        root = Path(temporary) / "shibumi"
        shutil.copytree(
            REPO_ROOT,
            root,
            ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc"),
        )
        mutate_checkout(root, replacement)
        result = subprocess.run(
            [sys.executable, "-m", "unittest", "-v", *tests],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = result.stdout + result.stderr
        if result.returncode == 0:
            raise AssertionError(f"{name} mutation survived:\n{output}")
        if "Ran 3 tests" not in output or "FAILED" not in output:
            raise AssertionError(
                f"{name} mutation failed outside the focused contract:\n{output}"
            )
        print(f"INC-013 mutation killed: {name}")


def main() -> int:
    for name, (replacement, tests) in MUTATIONS.items():
        assert_mutation_is_killed(name, replacement, tests)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
