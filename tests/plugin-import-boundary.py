#!/usr/bin/env python3
"""Check canonical local QML/JS imports and the declared sibling exception."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.shared_runtime_contract import invalid_imports


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} <plugin-directory>", file=sys.stderr)
        return 2

    candidate = Path(sys.argv[1]).absolute()
    if any(path.is_symlink() for path in (candidate, *candidate.parents)):
        print("Plugin import boundary rejects symlinked roots", file=sys.stderr)
        return 1
    if not candidate.is_dir():
        print("Plugin import boundary requires a directory", file=sys.stderr)
        return 1
    root = candidate.resolve(strict=True)
    violations: list[str] = []
    sources = [path for path in root.rglob("*")
               if path.suffix.lower() in {".qml", ".js", ".mjs"}]
    for source in sorted(sources):
        if source.is_symlink() or not source.is_file():
            violations.append(f"{source.relative_to(root)}: nonregular or symlinked source")
            continue
        text = source.read_text(encoding="utf-8")
        for (start, _), imported in invalid_imports(root, source, text):
            number = text.count("\n", 0, start) + 1
            violations.append(f"{source.relative_to(root)}:{number}: {imported!r}")

    if violations:
        print("Plugin imports escape their boundary or use noncanonical paths:", file=sys.stderr)
        print("\n".join(violations), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
