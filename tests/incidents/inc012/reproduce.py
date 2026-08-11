#!/usr/bin/env python3
"""Run the revision-bound, non-production INC-012 lifecycle matrix."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
HARNESS_ROOT = Path(__file__).resolve().parent
DEFAULT_OMARCHY = Path("/usr/share/omarchy")
DEFAULT_QUICKSHELL = Path("/usr/bin/quickshell")
LOG_LINE_LIMIT = 120
LOG_COLUMN_LIMIT = 600
PROCESS_TIMEOUT_SECONDS = 40

REVISION_CONTRACT = {
    "beta3": {
        "ref": "v0.1.1-beta.3",
        "commit": "c8d0b263c01aff3112f5204cc3bbe3097926e429",
        "groupSectionSha256": (
            "e709a66de9091c242afbec1096898fc4a7ffef9d8cb33356df859220cf617442"
        ),
    },
    "current": {
        "ref": "47c85d155a8ffeaeedb7f675a650347e40b70659",
        "commit": "47c85d155a8ffeaeedb7f675a650347e40b70659",
        "groupSectionSha256": (
            "e4d98d7d098d5f5c8da70402c63a9f04dae59bee7c5ce25b2e32aadf693c6092"
        ),
    },
}

QML_HARNESS_FILES = (
    "SectionHost.qml",
    "direct-shell.qml",
    "async-shell.qml",
)
EVIDENCE_FILES = (*QML_HARNESS_FILES, "reproduce.py", "README.md")

ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
HISTORICAL_SIGNATURE = re.compile(
    r"TypeError:.*(?:read|reading).*slotEditing.*null",
    re.IGNORECASE,
)
REVIEWABLE_LINE = re.compile(
    r"INC012_|Configuration Loaded|GroupSection\.qml|slotEditing|"
    r"TypeError|ReferenceError|QQml.*(?:error|warning)|critical|fatal",
    re.IGNORECASE,
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_tree(root: Path) -> str:
    """Hash names, node types, modes, link targets, and regular-file bytes."""

    digest = hashlib.sha256()
    entries = sorted(root.rglob("*"), key=lambda path: path.relative_to(root).as_posix())
    for path in entries:
        relative = path.relative_to(root).as_posix().encode()
        metadata = path.lstat()
        if stat.S_ISDIR(metadata.st_mode):
            kind = b"directory"
            payload = b""
        elif stat.S_ISREG(metadata.st_mode):
            kind = b"file"
            payload = path.read_bytes()
        elif stat.S_ISLNK(metadata.st_mode):
            kind = b"symlink"
            payload = os.readlink(path).encode()
        else:
            kind = b"special"
            payload = str(stat.S_IFMT(metadata.st_mode)).encode()
        for value in (
            relative,
            kind,
            f"{stat.S_IMODE(metadata.st_mode):04o}".encode(),
            payload,
        ):
            digest.update(len(value).to_bytes(8, "big"))
            digest.update(value)
    return digest.hexdigest()


def git_output(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def validate_revision(label: str) -> dict[str, str]:
    contract = REVISION_CONTRACT[label]
    resolved = git_output("rev-parse", f"{contract['ref']}^{{commit}}")
    if resolved != contract["commit"]:
        raise RuntimeError(
            f"revision drift for {label}: expected {contract['commit']}, got {resolved}"
        )
    return contract


def extract_source(commit: str, destination: Path) -> None:
    archive = subprocess.run(
        ["git", "archive", "--format=tar", commit, "core", "styles"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    ).stdout
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
        stream.extractall(destination, filter="data")


def source_tree_digest(commit: str) -> str:
    with tempfile.TemporaryDirectory(prefix="shibumi-inc012-source-") as tmp:
        destination = Path(tmp)
        extract_source(commit, destination)
        return digest_tree(destination)


def private_environment(root: Path, omarchy_path: Path) -> dict[str, str]:
    environment = os.environ.copy()
    private_paths = {
        "HOME": root / "home",
        "XDG_CONFIG_HOME": root / "config",
        "XDG_CACHE_HOME": root / "cache",
        "XDG_DATA_HOME": root / "data",
        "XDG_STATE_HOME": root / "state",
        "XDG_RUNTIME_DIR": root / "runtime",
    }
    for name, path in private_paths.items():
        path.mkdir(parents=True, exist_ok=True)
        environment[name] = str(path)
    (root / "runtime").chmod(0o700)
    environment.update(
        {
            "OMARCHY_PATH": str(omarchy_path),
            "QT_QPA_PLATFORM": "offscreen",
            "QT_QPA_PLATFORMTHEME": "",
            "QSG_RHI_BACKEND": "software",
        }
    )
    for name in (
        "WAYLAND_DISPLAY",
        "HYPRLAND_INSTANCE_SIGNATURE",
        "QS_CONFIG_PATH",
        "SHIBUMI_TEST_VERTICAL",
    ):
        environment.pop(name, None)
    return environment


def bounded_log(output: str) -> tuple[list[str], bool]:
    lines = []
    for raw_line in output.splitlines():
        line = ANSI_ESCAPE.sub("", raw_line).replace("\x00", "")
        if REVIEWABLE_LINE.search(line):
            lines.append(line[:LOG_COLUMN_LIMIT])
    truncated = len(lines) > LOG_LINE_LIMIT
    return lines[:LOG_LINE_LIMIT], truncated


def run_mode(
    *,
    label: str,
    commit: str,
    mode: str,
    omarchy_path: Path,
    quickshell: Path,
) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix=f"shibumi-inc012-{label}-{mode}-") as tmp:
        private_root = Path(tmp)
        shell_root = private_root / "fixture-shell"
        shell_root.mkdir()
        extract_source(commit, shell_root)
        shutil.copytree(
            omarchy_path / "shell" / "Commons",
            shell_root / "Commons",
            symlinks=True,
        )
        for filename in QML_HARNESS_FILES:
            shutil.copy2(HARNESS_ROOT / filename, shell_root / filename)
        shutil.copy2(HARNESS_ROOT / f"{mode}-shell.qml", shell_root / "shell.qml")

        environment = private_environment(private_root, omarchy_path)
        argv = [str(quickshell), "-p", str(shell_root), "--no-color"]
        timed_out = False
        try:
            completed = subprocess.run(
                argv,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=PROCESS_TIMEOUT_SECONDS,
                check=False,
            )
            returncode = completed.returncode
            output = completed.stdout
        except subprocess.TimeoutExpired as error:
            timed_out = True
            returncode = 124
            raw_output = error.stdout or ""
            output = raw_output.decode(errors="replace") if isinstance(raw_output, bytes) else raw_output

        selected_log, log_truncated = bounded_log(output)
        signature_lines = [
            ANSI_ESCAPE.sub("", line)[:LOG_COLUMN_LIMIT]
            for line in output.splitlines()
            if HISTORICAL_SIGNATURE.search(ANSI_ESCAPE.sub("", line))
        ][:20]
        completion_marker = f"INC012_COMPLETE {mode}"
        completed_matrix = completion_marker in output
        harness_errors = [line for line in selected_log if "INC012_HARNESS_ERROR" in line]

        if signature_lines:
            outcome = "historical-signature-observed"
        elif timed_out or returncode != 0 or not completed_matrix or harness_errors:
            outcome = "harness-failed"
        else:
            outcome = "not-reproduced-in-harness"

        return {
            "revision": label,
            "commit": commit,
            "mode": mode,
            "command": [
                str(quickshell),
                "-p",
                "<private-fixture-shell>",
                "--no-color",
            ],
            "timeoutSeconds": PROCESS_TIMEOUT_SECONDS,
            "exitCode": returncode,
            "timedOut": timed_out,
            "completionMarker": completion_marker,
            "completionObserved": completed_matrix,
            "historicalSignatureObserved": bool(signature_lines),
            "historicalSignatureLines": signature_lines,
            "outcome": outcome,
            "boundedLog": {
                "lineLimit": LOG_LINE_LIMIT,
                "columnLimit": LOG_COLUMN_LIMIT,
                "truncated": log_truncated,
                "lines": selected_log,
            },
        }


def quickshell_version(quickshell: Path) -> str:
    result = subprocess.run(
        [str(quickshell), "--version"],
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    return (result.stdout or result.stderr).strip()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--revision",
        action="append",
        choices=tuple(REVISION_CONTRACT),
        help="revision contract to run; repeatable (default: beta3 and current)",
    )
    parser.add_argument(
        "--omarchy-path",
        type=Path,
        default=DEFAULT_OMARCHY,
        help="read-only Omarchy root providing shell/Commons",
    )
    parser.add_argument(
        "--quickshell",
        type=Path,
        default=DEFAULT_QUICKSHELL,
        help="Quickshell executable",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="write the bounded JSON report here (default: stdout)",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    labels = arguments.revision or ["beta3", "current"]
    omarchy_path = arguments.omarchy_path.resolve()
    quickshell = arguments.quickshell.resolve()
    commons = omarchy_path / "shell" / "Commons"
    if not commons.is_dir():
        raise RuntimeError(f"Omarchy Commons directory is missing: {commons}")
    if not quickshell.is_file():
        raise RuntimeError(f"Quickshell executable is missing: {quickshell}")

    contracts = {label: validate_revision(label) for label in labels}
    harness_digests = {
        filename: sha256_file(HARNESS_ROOT / filename) for filename in EVIDENCE_FILES
    }
    started = dt.datetime.now(dt.timezone.utc)
    runs = []
    revisions = []
    for label in labels:
        contract = contracts[label]
        source = subprocess.run(
            [
                "git",
                "show",
                f"{contract['commit']}:styles/shibumi/GroupSection.qml",
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
        ).stdout
        source_digest = hashlib.sha256(source).hexdigest()
        if source_digest != contract["groupSectionSha256"]:
            raise RuntimeError(
                f"GroupSection digest drift for {label}: "
                f"expected {contract['groupSectionSha256']}, got {source_digest}"
            )
        revisions.append(
            {
                "label": label,
                "ref": contract["ref"],
                "commit": contract["commit"],
                "groupSectionSha256": source_digest,
                "sourceTreeSha256": source_tree_digest(contract["commit"]),
            }
        )
        for mode in ("direct", "async"):
            runs.append(
                run_mode(
                    label=label,
                    commit=contract["commit"],
                    mode=mode,
                    omarchy_path=omarchy_path,
                    quickshell=quickshell,
                )
            )

    finished = dt.datetime.now(dt.timezone.utc)
    report = {
        "schemaVersion": 1,
        "incident": "INC-012",
        "scope": "reproduction evidence only; no fix or closure",
        "startedAt": started.isoformat(),
        "finishedAt": finished.isoformat(),
        "durationSeconds": round((finished - started).total_seconds(), 3),
        "repositoryHead": git_output("rev-parse", "HEAD"),
        "revisions": revisions,
        "host": {
            "omarchyPath": str(omarchy_path),
            "commonsTreeSha256": digest_tree(commons),
            "quickshell": str(quickshell),
            "quickshellVersion": quickshell_version(quickshell),
            "platform": "QT_QPA_PLATFORM=offscreen",
            "productionWaylandInherited": False,
        },
        "harnessSha256": harness_digests,
        "logBounds": {
            "linesPerRun": LOG_LINE_LIMIT,
            "columnsPerLine": LOG_COLUMN_LIMIT,
            "signatureLinesPerRun": 20,
        },
        "runs": runs,
        "disposition": (
            "open-root-cause-unconfirmed; negative bounded evidence is not closure"
        ),
    }

    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if arguments.report:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(rendered)
    else:
        sys.stdout.write(rendered)

    if any(run["outcome"] == "historical-signature-observed" for run in runs):
        return 2
    if any(run["outcome"] != "not-reproduced-in-harness" for run in runs):
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"INC012_RUNNER_ERROR {error}", file=sys.stderr)
        raise SystemExit(1) from error
