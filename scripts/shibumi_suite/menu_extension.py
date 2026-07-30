from __future__ import annotations

import json
from pathlib import Path


class MenuExtensionError(RuntimeError):
    pass


START_MARKER = "// shibumi-picker-routing-start"
END_MARKER = "// shibumi-picker-routing-end"
EMPTY_EXTENSION = "{\n}\n"
ROUTER = (
    '"$HOME/.config/omarchy/plugins/'
    'hancore.shibumi.quick-access/scripts/shibumi-picker-route"'
)


def _strip_jsonc(raw: str, *, strip_trailing_commas: bool = True) -> str:
    out = list(raw)
    in_string = False
    escaped = False
    index = 0
    while index < len(raw):
        char = raw[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            index += 1
            continue
        if char == "/" and index + 1 < len(raw) and raw[index + 1] == "/":
            end = raw.find("\n", index + 2)
            if end < 0:
                end = len(raw)
            for offset in range(index, end):
                out[offset] = " "
            index = end
            continue
        if char == "/" and index + 1 < len(raw) and raw[index + 1] == "*":
            end = raw.find("*/", index + 2)
            if end < 0:
                raise MenuExtensionError("unterminated block comment in Omarchy menu extension")
            for offset in range(index, end + 2):
                if out[offset] != "\n":
                    out[offset] = " "
            index = end + 2
            continue
        index += 1
    if in_string:
        raise MenuExtensionError("unterminated string in Omarchy menu extension")
    if not strip_trailing_commas:
        return "".join(out)
    in_string = False
    escaped = False
    for index, char in enumerate(out):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
            continue
        if char != ",":
            continue
        cursor = index + 1
        while cursor < len(out) and out[cursor].isspace():
            cursor += 1
        if cursor < len(out) and out[cursor] in ("}", "]"):
            out[index] = " "
    return "".join(out)


def _decoded(raw: str) -> dict[str, object]:
    try:
        value = json.loads(_strip_jsonc(raw))
    except json.JSONDecodeError as error:
        raise MenuExtensionError(
            f"invalid Omarchy menu extension JSONC: {error}"
        ) from error
    if not isinstance(value, dict):
        raise MenuExtensionError("Omarchy menu extension root must be an object")
    return value


def _string_end(raw: str, start: int) -> int:
    escaped = False
    for index in range(start + 1, len(raw)):
        char = raw[index]
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            return index + 1
    raise MenuExtensionError("unterminated JSON string")


def _matching_brace(raw: str, start: int) -> int:
    depth = 0
    index = start
    while index < len(raw):
        char = raw[index]
        if char == '"':
            index = _string_end(raw, index)
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise MenuExtensionError("unbalanced Omarchy menu extension object")


def _root_object(raw: str) -> tuple[int, int]:
    stripped = _strip_jsonc(raw)
    start = next((i for i, char in enumerate(stripped) if not char.isspace()), -1)
    if start < 0 or stripped[start] != "{":
        raise MenuExtensionError("Omarchy menu extension root must be an object")
    return start, _matching_brace(stripped, start)


def _items_object(raw: str, root_start: int, root_end: int) -> tuple[int, int] | None:
    stripped = _strip_jsonc(raw)
    depth = 0
    index = root_start
    while index < root_end:
        char = stripped[index]
        if char == '"':
            end = _string_end(stripped, index)
            if depth == 1:
                try:
                    key = json.loads(stripped[index:end])
                except json.JSONDecodeError:
                    key = ""
                cursor = end
                while cursor < root_end and stripped[cursor].isspace():
                    cursor += 1
                if cursor < root_end and stripped[cursor] == ":" and key == "items":
                    cursor += 1
                    while cursor < root_end and stripped[cursor].isspace():
                        cursor += 1
                    if cursor >= root_end or stripped[cursor] != "{":
                        raise MenuExtensionError(
                            "Omarchy menu extension items must be an object"
                        )
                    return cursor, _matching_brace(stripped, cursor)
            index = end
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        index += 1
    return None


def remove_picker_routing(raw: str) -> str:
    starts = raw.count(START_MARKER)
    ends = raw.count(END_MARKER)
    if starts == 0 and ends == 0:
        return raw
    if starts != 1 or ends != 1:
        raise MenuExtensionError("malformed Shibumi picker routing markers")
    start = raw.index(START_MARKER)
    end = raw.index(END_MARKER)
    if end <= start:
        raise MenuExtensionError("reversed Shibumi picker routing markers")
    line_start = raw.rfind("\n", 0, start) + 1
    line_end = raw.find("\n", end + len(END_MARKER))
    line_end = len(raw) if line_end < 0 else line_end + 1
    result = raw[:line_start] + raw[line_end:]
    _decoded(result)
    return result


def install_picker_routing(raw: str | None) -> str:
    base = raw if raw and raw.strip() else EMPTY_EXTENSION
    base = remove_picker_routing(base)
    decoded = _decoded(base)
    root_start, root_end = _root_object(base)
    items = decoded.get("items")
    target = _items_object(base, root_start, root_end) if isinstance(items, dict) else None
    target_start, target_end = target or (root_start, root_end)
    target_value = items if isinstance(items, dict) else decoded

    line_start = base.rfind("\n", 0, target_end) + 1
    if base[line_start:target_end].strip():
        insertion = target_end
        closing_indent = ""
        lead = "\n"
    else:
        insertion = line_start
        closing_indent = base[line_start:target_end]
        lead = ""
    indent = closing_indent + "  "
    untrimmed = _strip_jsonc(base, strip_trailing_commas=False)
    cursor = target_end - 1
    while cursor > target_start and untrimmed[cursor].isspace():
        cursor -= 1
    has_trailing_comma = cursor > target_start and untrimmed[cursor] == ","
    separator = indent + ",\n" if target_value and not has_trailing_comma else ""
    entries = {
        "style.theme": {
            "icon": "󰸌",
            "label": "Theme",
            "aliases": ["theme", "themes"],
            "action": f"{ROUTER} theme",
        },
        "style.background": {
            "icon": "",
            "label": "Background",
            "aliases": ["background", "wallpaper"],
            "action": f"{ROUTER} wallpaper",
        },
    }
    block = (
        lead
        + indent
        + START_MARKER
        + "\n"
        + separator
        + indent
        + json.dumps("style.theme")
        + ": "
        + json.dumps(
            entries["style.theme"], ensure_ascii=False, separators=(",", ":")
        )
        + ",\n"
        + indent
        + json.dumps("style.background")
        + ": "
        + json.dumps(
            entries["style.background"],
            ensure_ascii=False,
            separators=(",", ":"),
        )
        + "\n"
        + indent
        + END_MARKER
        + "\n"
    )
    result = base[:insertion] + block + base[insertion:]
    _decoded(result)
    return result


def generated_extension_is_empty(raw: str) -> bool:
    return raw in (EMPTY_EXTENSION, "{}", "{}\n")


def read_extension(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except OSError as error:
        raise MenuExtensionError(f"cannot read Omarchy menu extension {path}: {error}") from error
