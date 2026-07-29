#!/usr/bin/env python3
"""Reject QML/JS imports that escape an installed plugin directory."""

from __future__ import annotations

import re
import sys
from pathlib import Path


QML_IMPORT = re.compile(r'^\s*import\s+["\']([^"\']+)["\']')
JS_IMPORT = re.compile(r'^\s*\.import\s+["\']([^"\']+)["\']')


def escapes(root: Path, source: Path, imported: str) -> bool:
    if "://" in imported or imported.startswith(("/", "qrc:")):
        return False
    resolved = (source.parent / imported).resolve(strict=False)
    return not resolved.is_relative_to(root)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} <plugin-directory>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve(strict=True)
    violations: list[str] = []
    sources = (*root.rglob("*.qml"), *root.rglob("*.js"))
    for source in sorted(sources):
        for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
            match = QML_IMPORT.match(line) or JS_IMPORT.match(line)
            if match and escapes(root, source, match.group(1)):
                violations.append(
                    f"{source.relative_to(root)}:{number}: {match.group(1)}"
                )

    if violations:
        print("Plugin imports escape their plugin boundary:", file=sys.stderr)
        print("\n".join(violations), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
