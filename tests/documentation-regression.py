#!/usr/bin/env python3

from pathlib import Path
import re
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
CURRENT_DOCUMENTS = (
    "README.md",
    "CONTRIBUTING.md",
    "DESIGN.md",
    "docs/README.md",
    "docs/install.md",
    "docs/configuration.md",
    "docs/release-readiness.md",
    "docs/architecture/overview.md",
    "docs/plugins/README.md",
    "docs/screenshots/README.md",
    "docs/development/setup.md",
    "docs/development/testing.md",
    "docs/development/troubleshooting.md",
    "docs/development/release.md",
)
LINK_PATTERN = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def fail(message: str) -> None:
    print(f"documentation regression failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def local_target(source: Path, raw_target: str) -> Path | None:
    target = raw_target.strip()
    if not target or target.startswith(("#", "http://", "https://", "mailto:")):
        return None
    target = target.split("#", 1)[0]
    return (source.parent / target).resolve()


def main() -> None:
    for relative in CURRENT_DOCUMENTS:
        source = REPO_ROOT / relative
        if not source.is_file():
            fail(f"missing current document: {relative}")
        content = source.read_text(encoding="utf-8")
        for raw_target in LINK_PATTERN.findall(content):
            target = local_target(source, raw_target)
            if target is not None and not target.exists():
                fail(f"broken local link in {relative}: {raw_target}")

    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    if "/home/hancore/Projects/Quickshell-Dots" in readme:
        fail("README exposes the internal QS Rise worktree path")

    for placeholder in (
        "docs/screenshots/readme/shibumi-desktop.webp",
        "docs/screenshots/readme/shibumi-bars.webp",
        "docs/screenshots/readme/shibumi-appearance.webp",
    ):
        if placeholder not in readme:
            fail(f"README screenshot placeholder is missing: {placeholder}")

    print("documentation regression passed")


if __name__ == "__main__":
    main()
