#!/usr/bin/env python3
"""Calibrated restoration mutants; the shell gate stages actual Bar privately."""
import os
from pathlib import Path
from lib.isolated_process import run_bounded

ROOT = Path(__file__).resolve().parents[1]
CONTROLS = (
    ("none", "bar host registry regression passed"),
    ("navigation-rollback", "navigation retained rejected replacement or retry reset"),
    ("output-dedup", "one output enrolled twice or lost preferred page"),
    ("bar-admission", "Bar revocation with ready State retained restores"),
    ("sync-settlement", "synchronous confirmed request refused"),
    ("rejected-existing", "rejected callback changed an existing restore"),
    ("window-reset", "new handoff inherited expired retry window"),
    ("pending-window", "pending write spent restore window or reopened a panel"),
    ("native-window", "native publication wait spent restore window"),
    ("false-settlement", "refused request retained restore"),
    ("snapshot-replay", "timer revived cancelled restore or lost reentrant scheduling"),
    ("same-owner-veto", "same ready owner was reopened instead of satisfying the restore"),
    ("active-page-readiness", "unready active owner completed before page readiness"),
    ("page-readiness", "late unready owner completed before page readiness"),
    ("copied-record-prune", "reentrant record copy escaped expiry pruning"),
    ("revision-prune", "old timer turn pruned a newer restore revision"),
    ("output-prune", "one output expiry changed another output restore"),
    ("none", "bar host registry regression passed"),
)

for control, diagnostic in CONTROLS:
    environment = dict(os.environ, SHIBUMI_TEST_RESTORE_CONTROL=control)
    result = run_bounded(["bash", str(ROOT / "tests/bar-host-registry-regression.sh")],
                         env=environment, cwd=ROOT, timeout=60, maximum=131072)
    output = (result.stdout + result.stderr).decode(errors="replace")
    print(output)
    positive = control == "none"
    if (result.returncode == 0) != positive or diagnostic not in output:
        raise RuntimeError("restore control did not reach its intended result: " + control)
    if not positive and "bar host registry regression passed" in output:
        raise RuntimeError("negative restore control reached success: " + control)
    if any(token in output for token in ("TypeError", "ReferenceError", "Binding loop", "Unable to assign", "Cannot assign")):
        raise RuntimeError("restore control had an unrelated runtime error: " + control)
    print("restore control passed: " + control)
print("State restore calibrated controls passed; not physical output acceptance")
