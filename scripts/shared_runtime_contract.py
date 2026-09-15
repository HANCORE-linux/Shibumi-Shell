"""Narrow source-contract exceptions for cooperative State QML modules.

This is dependency validation, not a QML sandbox or trusted-caller check.
Changing either exact module or importer roster is an explicit architecture
change.
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

PRESENTATION_MODULE = Path("hancore.shibumi.state/lib/presentation")
PRESENTATION_MODULE_FILES = frozenset({
    "qmldir",
    "ControlCenterIconText.qml",
    "HostTokens.qml",
    "IconText.qml",
    "PacmanWorkspaceMarker.qml",
    "PillSurface.qml",
    "ShibumiPanelToolTip.qml",
    "ShibumiPillToolTip.qml",
})
PRESENTATION_IMPORTERS = frozenset({
    "hancore.shibumi.ai/AiUsagePanel.qml",
    "hancore.shibumi.ai/BarWidget.qml",
    "hancore.shibumi.audio/AudioPanel.qml",
    "hancore.shibumi.audio/BarWidget.qml",
    "hancore.shibumi.battery/BarWidget.qml",
    "hancore.shibumi.battery/BatteryPanel.qml",
    "hancore.shibumi.bluetooth/BarWidget.qml",
    "hancore.shibumi.bluetooth/BluetoothPanel.qml",
    "hancore.shibumi.brightness/BarWidget.qml",
    "hancore.shibumi.brightness/BrightnessPanel.qml",
    "hancore.shibumi.center/BarWidget.qml",
    "hancore.shibumi.center/CalendarPanel.qml",
    "hancore.shibumi.center/StatusIndicators.qml",
    "hancore.shibumi.center/SystemUpdateWidget.qml",
    "hancore.shibumi.center/WeatherPanel.qml",
    "hancore.shibumi.control-center/ActiveBarSettingsPage.qml",
    "hancore.shibumi.control-center/AppearanceWidgetTile.qml",
    "hancore.shibumi.control-center/BarWidget.qml",
    "hancore.shibumi.control-center/ConfigureLandingPage.qml",
    "hancore.shibumi.control-center/ControlCenterPanel.qml",
    "hancore.shibumi.control-center/ControlSearchPage.qml",
    "hancore.shibumi.control-center/ControlSettings.qml",
    "hancore.shibumi.control-center/PageHeaderHero.qml",
    "hancore.shibumi.control-center/PluginCatalogPage.qml",
    "hancore.shibumi.control-center/PluginProviderSummary.qml",
    "hancore.shibumi.control-center/PluginSectionHeader.qml",
    "hancore.shibumi.control-center/PredictiveSearchInput.qml",
    "hancore.shibumi.control-center/QuickControlPage.qml",
    "hancore.shibumi.control-center/SemanticPreviewImage.qml",
    "hancore.shibumi.control-center/WidgetAppearanceWorkbench.qml",
    "hancore.shibumi.control-center/WidgetModuleTile.qml",
    "hancore.shibumi.control-center/WorkspaceMarkerPreviewCard.qml",
    "hancore.shibumi.cpu/BarWidget.qml",
    "hancore.shibumi.gpu/BarWidget.qml",
    "hancore.shibumi.media/BarWidget.qml",
    "hancore.shibumi.media/MediaPanel.qml",
    "hancore.shibumi.memory/BarWidget.qml",
    "hancore.shibumi.network/BarWidget.qml",
    "hancore.shibumi.network/NetworkPanel.qml",
    "hancore.shibumi.power-profile/BarWidget.qml",
    "hancore.shibumi.power-profile/PowerProfilePanel.qml",
    "hancore.shibumi.quick-access/BarWidget.qml",
    "hancore.shibumi.quick-access/CarouselPickerImage.qml",
    "hancore.shibumi.quick-access/HearthstonePickerView.qml",
    "hancore.shibumi.quick-access/PickerImage.qml",
    "hancore.shibumi.quick-access/PickerOverlay.qml",
    "hancore.shibumi.quick-access/Service.qml",
    "hancore.shibumi.status/BarWidget.qml",
    "hancore.shibumi.status/NotificationPanel.qml",
    "hancore.shibumi.status/NotificationStatusView.qml",
    "hancore.shibumi.status/TrayAppMenuPanel.qml",
    "hancore.shibumi.status/TrayDrawerPanel.qml",
    "hancore.shibumi.status/TrayStatusView.qml",
    "hancore.shibumi.storage/BarWidget.qml",
    "hancore.shibumi.temperature/BarWidget.qml",
    "hancore.shibumi.update-center/PanelButton.qml",
    "hancore.shibumi.update-center/ThemesTab.qml",
    "hancore.shibumi.update-center/UpdateCenterPanel.qml",
    "hancore.shibumi.workspaces/BarWidget.qml",
    "hancore.shibumi.workspaces/WorkspacePanelContent.qml",
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


def module_present(root: Path, module: Path = MODULE,
                   members: frozenset[str] = MODULE_FILES) -> bool:
    """Require an exact regular sibling module with no symlinked component."""
    current = root
    for part in module.parts:
        current /= part
        if current.is_symlink() or not current.is_dir():
            return False
    names = set()
    for entry in current.iterdir():
        if entry.name not in members or entry.is_symlink() or not entry.is_file():
            return False
        names.add(entry.name)
    return names == members


def _approved_module_import(root: Path, source: Path, text: str, *,
                            module: Path, members: frozenset[str],
                            importers: frozenset[str], alias: str,
                            actual_imports: set[tuple[int, int]]) -> set[tuple[int, int]]:
    try:
        relative = source.relative_to(root).as_posix()
    except ValueError:
        return set()
    if relative not in importers or not module_present(root, module, members):
        return set()
    imported = Path(os.path.relpath(root / module, source.parent)).as_posix()
    pattern = re.compile(r'^[ \t]*import[ \t]+(?P<literal>"' + re.escape(imported)
        + r'")[ \t]+as[ \t]+' + re.escape(alias) + r'[ \t]*\r?$', re.MULTILINE)
    matches = [match for match in pattern.finditer(text)
               if match.span("literal") in actual_imports]
    return {matches[0].span("literal")} if len(matches) == 1 else set()


def approved_import_spans(root: Path, source: Path, text: str) -> set[tuple[int, int]]:
    """Return quoted spans for exact declared cooperative QML imports.

An identical string used as a source URL or command is not exempt. Different
spellings, aliases, importer paths and copies elsewhere remain subject to the
ordinary boundary checks.
"""
    if source.is_symlink() or not source.is_file():
        return set()
    for parent in source.parents:
        if parent == root:
            break
        if parent.is_symlink():
            return set()
    try:
        actual_imports = {span for span, _ in quoted_imports(text)}
    except ImportLexError:
        return set()
    return (
        _approved_module_import(
            root, source, text, module=MODULE, members=MODULE_FILES,
            importers=IMPORTERS, alias="SuiteRuntime",
            actual_imports=actual_imports)
        | _approved_module_import(
            root, source, text, module=PRESENTATION_MODULE,
            members=PRESENTATION_MODULE_FILES,
            importers=PRESENTATION_IMPORTERS, alias="Presentation",
            actual_imports=actual_imports)
    )
