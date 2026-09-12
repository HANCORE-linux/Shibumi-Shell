"""Narrow source-contract exception for the single cooperative QML runtime.

This is dependency validation, not a QML sandbox or trusted-caller check.
Changing the importer roster is an explicit source/architecture change.
"""
from collections import deque
from itertools import islice
from pathlib import Path
import os
import posixpath
import re
from scripts.qml_import_lexer import ImportLexError, tokens

MODULE = Path("hancore.shibumi.state/runtime")
MODULE_FILES = frozenset({"qmldir", "Runtime.qml", "Provider.qml", "HostShell.qml"})
IMPORTERS = frozenset({
    "hancore.shibumi.ai/Service.qml",
    "hancore.shibumi.audio/BarWidget.qml",
    "hancore.shibumi.audio/Service.qml",
    "hancore.shibumi.bar/Bar.qml",
    "hancore.shibumi.battery/BarWidget.qml",
    "hancore.shibumi.bluetooth/Service.qml",
    "hancore.shibumi.brightness/Service.qml",
    "hancore.shibumi.center/Service.qml",
    "hancore.shibumi.control-center/BarWidget.qml",
    "hancore.shibumi.control-center/PluginUpdateService.qml",
    "hancore.shibumi.cpu/BarWidget.qml",
    "hancore.shibumi.cpu/Service.qml",
    "hancore.shibumi.gpu/BarWidget.qml",
    "hancore.shibumi.media/BarWidget.qml",
    "hancore.shibumi.media/Service.qml",
    "hancore.shibumi.memory/BarWidget.qml",
    "hancore.shibumi.network/Service.qml",
    "hancore.shibumi.power-profile/BarWidget.qml",
    "hancore.shibumi.power-state/Service.qml",
    "hancore.shibumi.quick-access/Service.qml",
    "hancore.shibumi.reactor/Service.qml",
    "hancore.shibumi.status/Service.qml",
    "hancore.shibumi.storage/BarWidget.qml",
    "hancore.shibumi.storage/Service.qml",
    "hancore.shibumi.telemetry/Service.qml",
    "hancore.shibumi.temperature/BarWidget.qml",
    "hancore.shibumi.update-center/Service.qml",
    "hancore.shibumi.workspaces/BarWidget.qml",
    "hancore.shibumi.workspaces/WorkspaceService.qml",
})


# Paths accept no escapes or URL encodings. Unsupported lexical ambiguity
# fails closed; this remains static dependency lint, not a QML sandbox.
def quoted_imports(text: str):
    stream = tokens(text)
    window = deque(islice(stream, 4))
    while len(window) > 1:
        word = window[0].text if window[0].kind == "word" else ""
        following = window[1]
        # QML/.import, ESM side effects, and ESM import/export ... from.
        if word in {"import", "from"} and following.kind == "string":
            yield following.span, following.text[1:-1]
        elif word == "import" and following.text == "(":
            # Do not treat a computed expression as a verified local path.
            literal = window[2] if len(window) > 2 else None
            closing = window[3] if len(window) > 3 else None
            if (literal is not None and literal.kind == "string"
                    and closing is not None and closing.text == ")"):
                yield literal.span, literal.text[1:-1]
            else:
                yield following.span, ""
        window.popleft()
        window.extend(islice(stream, 1))


def invalid_imports(plugin: Path, source: Path, text: str):
    try:
        yield from _invalid_imports(plugin, source, text)
    except ImportLexError as error:
        yield (error.offset, error.offset + 1), "unsupported lexical input: " + str(error)


def _invalid_imports(plugin: Path, source: Path, text: str):
    approved = approved_import_spans(plugin.parent, source, text)
    for span, imported in quoted_imports(text):
        if span in approved:
            continue
        if (not imported or any(char in imported for char in ("\\", "%", ":"))
                or imported.startswith("/") or posixpath.normpath(imported) != imported):
            yield span, imported
            continue
        resolved = (source.parent / imported).resolve(strict=False)
        if not resolved.is_relative_to(plugin):
            yield span, imported


def module_present(root: Path) -> bool:
    """Require the actual sibling module, not a link or an incomplete copy."""
    for directory in (root / MODULE.parent, root / MODULE):
        if directory.is_symlink() or not directory.is_dir():
            return False
    directory = root / MODULE
    # Stop as soon as an unexpected entry is found; never follow subdirectories.
    names = set()
    for entry in directory.iterdir():
        if entry.name not in MODULE_FILES or entry.is_symlink() or not entry.is_file():
            return False
        names.add(entry.name)
    return names == MODULE_FILES


def approved_import_spans(root: Path, source: Path, text: str) -> set[tuple[int, int]]:
    """Return only the quoted span of one exact declared QML import line.

An identical string used as a source URL or command is NOT exempt. Different
spellings, aliases, importer paths and copies elsewhere remain subject to the
ordinary boundary checks.
"""
    try:
        relative = source.relative_to(root).as_posix()
    except ValueError:
        return set()
    if relative not in IMPORTERS or not module_present(root):
        return set()
    if source.is_symlink() or not source.is_file():
        return set()
    for parent in source.parents:
        if parent == root:
            break
        if parent.is_symlink():
            return set()
    imported = Path(os.path.relpath(root / MODULE, source.parent)).as_posix()
    pattern = re.compile(r'^[ \t]*import[ \t]+(?P<literal>"' + re.escape(imported)
        + r'")[ \t]+as[ \t]+SuiteRuntime[ \t]*\r?$', re.MULTILINE)
    try:
        actual_imports = {span for span, _ in quoted_imports(text)}
    except ImportLexError:
        return set()
    matches = [match for match in pattern.finditer(text)
               if match.span("literal") in actual_imports]
    return {matches[0].span("literal")} if len(matches) == 1 else set()
