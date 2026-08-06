#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
EXACT_GUARD = 'if result.stdout == "No running instances.\\n":'
CONSUMERS = {
    "manager": {
        "path": Path("hancore.shibumi.control-center/manager/shibumi-manager"),
        "positive_test": (
            "tests.test_shibumi_manager.ContinuityManagerTests."
            "test_empty_quickshell_registry_sentinel_is_an_empty_array"
        ),
        "invalid_test": (
            "tests.test_shibumi_manager.ContinuityManagerTests."
            "test_empty_registry_sentinel_variants_fail_closed"
        ),
        "nonzero_test": (
            "tests.test_shibumi_manager.ContinuityManagerTests."
            "test_empty_registry_sentinel_with_nonzero_exit_fails_closed"
        ),
    },
    "runtime": {
        "path": Path("scripts/shibumi_suite/runtime.py"),
        "positive_test": (
            "tests.test_shibumi_suite.RuntimeProcessTests."
            "test_empty_quickshell_registry_sentinel_is_an_empty_array"
        ),
        "invalid_test": (
            "tests.test_shibumi_suite.RuntimeProcessTests."
            "test_empty_registry_sentinel_variants_fail_closed"
        ),
        "nonzero_test": (
            "tests.test_shibumi_suite.RuntimeProcessTests."
            "test_empty_registry_sentinel_with_nonzero_exit_fails_closed"
        ),
    },
    "health": {
        "path": Path("hancore.shibumi.control-center/manager/shibumi-health"),
        "positive_test": (
            "tests.test_shibumi_health.HealthDiagnosticsTests."
            "test_empty_quickshell_registry_sentinel_reports_zero_processes"
        ),
        "invalid_test": (
            "tests.test_shibumi_health.HealthDiagnosticsTests."
            "test_empty_registry_sentinel_variants_fail_closed"
        ),
        "nonzero_test": (
            "tests.test_shibumi_health.HealthDiagnosticsTests."
            "test_empty_registry_sentinel_with_nonzero_exit_fails_closed"
        ),
    },
}
SENTINEL_MUTATIONS = {
    "missing-sentinel": (
        'if False and result.stdout == "No running instances.\\n":',
        "positive_test",
    ),
    "strip-sentinel": (
        'if result.stdout.strip() == "No running instances.":',
        "invalid_test",
    ),
    "startswith-sentinel": (
        'if result.stdout.startswith("No running instances.\\n"):',
        "invalid_test",
    ),
}
RETURNCODE_MUTATIONS = {
    "manager": (
        "    if result.returncode != 0:\n"
        "        detail = (result.stderr or result.stdout).strip()",
        "    if (result.returncode != 0\n"
        "            and result.stdout != \"No running instances.\\n\"):\n"
        "        detail = (result.stderr or result.stdout).strip()",
    ),
    "runtime": (
        "        if check and result.returncode != 0:\n"
        "            detail = (result.stderr or result.stdout).strip()",
        "        if (check and result.returncode != 0\n"
        "                and result.stdout != \"No running instances.\\n\"):\n"
        "            detail = (result.stderr or result.stdout).strip()",
    ),
    "health": (
        "                if result.returncode != 0:\n"
        "                    raise RuntimeError(\n"
        "                        result.stderr or result.stdout or "
        "\"instance query failed\"",
        "                if (result.returncode != 0\n"
        "                        and result.stdout != \"No running instances.\\n\"):\n"
        "                    raise RuntimeError(\n"
        "                        result.stderr or result.stdout or "
        "\"instance query failed\"",
    ),
}


def mutate_checkout(
    root: Path,
    relative: Path,
    search: str,
    replacement: str,
) -> None:
    path = root / relative
    source = path.read_text(encoding="utf-8")
    if source.count(search) != 1:
        raise AssertionError(f"expected one mutation target in {relative}")
    path.write_text(source.replace(search, replacement), encoding="utf-8")


def assert_mutation_is_killed(
    consumer: str,
    name: str,
    search: str,
    replacement: str,
    test: str,
) -> None:
    with tempfile.TemporaryDirectory(prefix=f"inc013-{name}.") as temporary:
        root = Path(temporary) / "shibumi"
        shutil.copytree(
            REPO_ROOT,
            root,
            ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc"),
        )
        mutate_checkout(root, CONSUMERS[consumer]["path"], search, replacement)
        result = subprocess.run(
            [sys.executable, "-m", "unittest", "-v", test],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = result.stdout + result.stderr
        if result.returncode == 0:
            raise AssertionError(
                f"{consumer}/{name} mutation survived:\n{output}"
            )
        if "Ran 1 test" not in output or "FAILED" not in output:
            raise AssertionError(
                f"{consumer}/{name} mutation failed outside the focused contract:\n"
                f"{output}"
            )
        print(f"INC-013 mutation killed: {consumer}/{name}")


def main() -> int:
    for consumer, contract in CONSUMERS.items():
        for name, (replacement, test_key) in SENTINEL_MUTATIONS.items():
            assert_mutation_is_killed(
                consumer,
                name,
                EXACT_GUARD,
                replacement,
                contract[test_key],
            )
        search, replacement = RETURNCODE_MUTATIONS[consumer]
        assert_mutation_is_killed(
            consumer,
            "returncode-after-sentinel",
            search,
            replacement,
            contract["nonzero_test"],
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
