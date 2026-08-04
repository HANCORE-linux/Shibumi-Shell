pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons as Commons
import "PickerModel.js" as PickerModel

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property bool runtimeWorkersEnabled: true
  property bool presentationEnabled: true
  readonly property var stateService: shell
    && typeof shell.serviceFor === "function"
    ? shell.serviceFor("hancore.shibumi.state") : null
  readonly property var bar: shell ? shell.bar : null
  readonly property string home: Quickshell.env("HOME")
  readonly property string scriptPath: String(
    Qt.resolvedUrl("scripts/shibumi-picker")).replace("file://", "")
  readonly property bool available: shell !== null && stateService !== null
    && stateService.ready === true && omarchyPath !== ""

  property bool opened: false
  property string mode: "wallpaper"
  readonly property var pickerConfig: stateService && stateService.config
    && stateService.config.picker ? stateService.config.picker : ({})
  readonly property string imagePickerStyle: normalizeImageStyle(
    pickerConfig.imageStyle || pickerConfig.style || "omarchy")
  readonly property string mediaPickerStyle: normalizeMediaStyle(
    pickerConfig.mediaStyle || pickerConfig.style || "carousel")
  readonly property string pickerStyle: imageMode
    ? imagePickerStyle : mediaPickerStyle
  readonly property bool usingOfficialPicker: imageMode
    && imagePickerStyle === "omarchy"
  property bool idleInhibited: false
  property var activeScreen: null
  property string activeScreenName: activeScreen ? String(activeScreen.name || "") : ""
  property var entries: []
  property var readyThumbnails: ({})
  property int thumbnailRevision: 0
  readonly property var filteredEntries: PickerModel.filtered(entries, filterText)
  property int selectedIndex: 0
  readonly property var selectedEntry: filteredEntries.length > 0
    ? filteredEntries[PickerModel.clampIndex(selectedIndex, filteredEntries.length)] : null
  property string filterText: ""
  property bool loading: false
  property bool scanComplete: false
  property bool confirmDelete: false
  property string currentSelection: ""
  property string statusText: ""
  property string lastActionFailure: ""
  readonly property bool actionRunning: actionProc.running
  property int requestSerial: 0
  property bool cachedRowsApplied: false
  readonly property int imageVisibleRadius: 5
  readonly property int imagePreloadRadius: imageVisibleRadius + 1
  property string selectedThemeAuthor: ""
  property string selectedThemeRepo: ""
  property var selectedThemePalette: []

  readonly property bool imageMode: mode === "theme" || mode === "wallpaper"
  readonly property bool mediaMode: mode === "screenshots" || mode === "videos"
  readonly property bool videoMode: mode === "videos"
  readonly property string title: mode === "theme" ? "Themes"
    : mode === "wallpaper" ? "Wallpapers"
    : mode === "videos" ? "Videos" : "Screenshots"
  readonly property string emptyText: loading ? "Loading " + title.toLowerCase() + "..."
    : "No " + title.toLowerCase() + " found"
  readonly property string currentThemeNamePath:
    home + "/.local/state/omarchy/current/theme.name"
  readonly property bool overlayLoaded: overlayLoader.item !== null
  readonly property bool refreshScanPending: scanDelay.running

  function normalizeImageStyle(value) {
    const candidate = String(value || "")
    if (candidate === "carousel") return "omarchy"
    return ["omarchy", "tanzaku", "hearthstone"].indexOf(candidate) >= 0
      ? candidate : "omarchy"
  }

  function normalizeMediaStyle(value) {
    const candidate = String(value || "")
    if (candidate === "default") return "carousel"
    return ["tanzaku", "hearthstone", "carousel"].indexOf(candidate) >= 0
      ? candidate : "carousel"
  }

  function resolveTargetScreen(preferred) {
    if (preferred && String(preferred.name || "") !== "") return preferred
    const focusedName = Hyprland.focusedMonitor
      ? String(Hyprland.focusedMonitor.name || "") : ""
    return bar && typeof bar.screenForName === "function"
      ? bar.screenForName(focusedName) : null
  }

  function cycleStyle(direction) {
    const styles = imageMode
      ? ["omarchy", "tanzaku", "hearthstone"]
      : ["tanzaku", "hearthstone", "carousel"]
    const current = Math.max(0, styles.indexOf(
      imageMode ? normalizeImageStyle(pickerStyle)
        : normalizeMediaStyle(pickerStyle)))
    const step = Number(direction) < 0 ? -1 : 1
    const next = styles[(current + step + styles.length) % styles.length]
    if (!stateService) return false
    if (imageMode && typeof stateService.setImagePickerStyle === "function") {
      const reopenOfficial = opened && next === "omarchy"
      const reopenMode = mode
      const reopenScreen = activeScreen
      const changed = stateService.setImagePickerStyle(next)
      if (!changed || !reopenOfficial) return changed
      close()
      return openMode(reopenMode, reopenScreen)
    }
    return typeof stateService.setMediaPickerStyle === "function"
      ? stateService.setMediaPickerStyle(next) : false
  }

  function toggleIdleInhibitor() {
    idleInhibited = !idleInhibited
    return idleInhibited
  }

  function syncOverlay() {
    if (!presentationEnabled || !opened || bar === null
        || usingOfficialPicker) {
      overlayLoader.active = false
      overlayLoader.source = ""
      return
    }
    overlayLoader.active = true
    if (!overlayLoader.item) {
      overlayLoader.setSource(Qt.resolvedUrl("PickerOverlay.qml"), {
        bar: bar,
        controller: root
      })
    }
  }

  function openMode(nextMode, screen) {
    const candidate = String(nextMode || "")
    if (["theme", "wallpaper", "screenshots", "videos"].indexOf(candidate) < 0)
      return false
    if (officialPickerProc.running) return false
    requestSerial++
    stopForegroundWorkers()
    mode = candidate
    activeScreen = resolveTargetScreen(screen)
    filterText = ""
    selectedIndex = 0
    confirmDelete = false
    currentSelection = ""
    statusText = ""
    clearThemeMetadata()
    readyThumbnails = ({})
    thumbnailRevision++
    entries = []
    cachedRowsApplied = false
    scanComplete = false
    loading = true
    opened = true
    if (usingOfficialPicker) {
      loading = false
      scanComplete = true
      if (runtimeWorkersEnabled) {
        officialPickerProc.activeSerial = requestSerial
        officialPickerProc.requestedMode = mode
        officialPickerProc.command = [mode === "theme"
          ? "omarchy-theme-switcher" : "omarchy-theme-bg-switcher"]
        officialPickerProc.running = true
      }
      return true
    }
    if (!runtimeWorkersEnabled) {
      loading = false
      scanComplete = true
      return true
    }
    if (mode === "theme" || mode === "wallpaper") {
      currentProc.activeSerial = requestSerial
      currentProc.command = mode === "theme"
        ? ["cat", currentThemeNamePath]
        : ["readlink", "-f", home + "/.local/state/omarchy/current/background"]
      currentProc.running = true
    } else {
      beginLoads(requestSerial)
    }
    return true
  }

  function toggleMode(nextMode, screen) {
    if (opened && mode === nextMode) {
      close()
      return true
    }
    return openMode(nextMode, screen)
  }

  // Optional host-facing provider contract. Callers keep their native Omarchy
  // action and execute it when this returns "native" or "unavailable".
  function routeOmarchyAction(nextMode, screen) {
    const candidate = String(nextMode || "")
    if (candidate !== "theme" && candidate !== "wallpaper")
      return "unavailable"
    if (!available || imagePickerStyle === "omarchy") return "native"
    return openMode(candidate, screen) ? "handled" : "unavailable"
  }

  function close() {
    if (!opened) return
    requestSerial++
    if (officialPickerProc.running)
      Quickshell.execDetached(["omarchy-shell", "image-selector", "cancel"])
    opened = false
    confirmDelete = false
    filterText = ""
    stopForegroundWorkers()
    loading = false
  }

  function stopForegroundWorkers() {
    currentProc.running = false
    cacheProc.running = false
    scanProc.running = false
    priorityWarmProc.running = false
    warmProc.running = false
    warmDelay.stop()
    scanDelay.stop()
    clearThemeMetadata()
    if (runtimeWorkersEnabled) {
      cleanupProc.running = false
      cleanupProc.command = [scriptPath, "cleanup"]
      cleanupProc.running = true
    }
  }

  function beginLoads(serial, forceScan) {
    if (!runtimeWorkersEnabled || !opened || serial !== requestSerial) return
    if (forceScan === true) {
      startScan(serial)
      return
    }
    cacheProc.activeSerial = serial
    cacheProc.command = [scriptPath, "cached", mode]
    cacheProc.running = true
  }

  function startScan(serial) {
    if (!runtimeWorkersEnabled || !opened || serial !== requestSerial
        || scanProc.running) return
    scanProc.activeSerial = serial
    scanProc.command = ["nice", "-n", "10", scriptPath,
      "scan", mode, omarchyPath]
    scanProc.running = true
  }

  function finishCacheLoad(text, serial) {
    if (!opened || serial !== requestSerial) return
    const hasCachedRows = applyRows(text, true, serial)
    if (!hasCachedRows) {
      startScan(serial)
      return
    }
    loading = false
    scanDelay.activeSerial = serial
    scanDelay.restart()
  }

  function applyRows(text, fromCache, serial) {
    if (!opened || serial !== requestSerial) return
    const parsed = PickerModel.parseRows(text)
    if (fromCache && (cachedRowsApplied || parsed.length === 0)) return false
    if (fromCache && entries.length > 0) return false
    if (!fromCache) scanComplete = true
    if (parsed.length === 0 && fromCache) return false
    const entriesChanged = !PickerModel.entriesEqual(entries, parsed)
    if (entriesChanged) {
      entries = parsed
      selectedIndex = selectedIndexForCurrent(parsed)
    }
    cachedRowsApplied = fromCache
    loading = false
    if (!entriesChanged) return parsed.length > 0
    Qt.callLater(function() {
      if (!root.opened || serial !== root.requestSerial) return
      root.warmVisible()
      warmDelay.restart()
    })
    return parsed.length > 0
  }

  function selectedIndexForCurrent(nextEntries) {
    if (mode === "theme") {
      for (let i = 0; i < nextEntries.length; i++) {
        if (String(nextEntries[i].label || "") === currentSelection) return i
      }
      return 0
    }
    return PickerModel.indexForSource(nextEntries, currentSelection)
  }

  function moveSelection(delta) {
    selectedIndex = PickerModel.clampIndex(selectedIndex + Number(delta),
      filteredEntries.length)
    confirmDelete = false
    warmVisible()
  }

  function clearThemeMetadata() {
    themeMetaDelay.stop()
    themeMetaProc.running = false
    selectedThemeAuthor = ""
    selectedThemeRepo = ""
    selectedThemePalette = []
  }

  function requestThemeMetadata() {
    clearThemeMetadata()
    if (mode === "theme" && selectedEntry && selectedEntry.directory)
      themeMetaDelay.restart()
  }

  function openSelectedThemeRepo() {
    if (!selectedThemeRepo) return false
    let url = String(selectedThemeRepo)
      .replace(/^git@github\.com:/, "https://github.com/")
      .replace(/\.git$/, "")
    if (!/^https?:\/\//.test(url)) return false
    Quickshell.execDetached(["xdg-open", url])
    return true
  }

  function selectIndex(index) {
    selectedIndex = PickerModel.clampIndex(index, filteredEntries.length)
    confirmDelete = false
    warmVisible()
  }

  function updateFilter(text) {
    filterText = String(text || "")
    selectedIndex = 0
    confirmDelete = false
    warmVisible()
  }

  function thumbnailUrl(entry) {
    if (!isThumbnailReady(entry) || !entry.thumbnailPath) return ""
    return Commons.Util.fileUrl(entry.thumbnailPath)
  }

  function isThumbnailReady(entry) {
    if (!entry) return false
    const thumbnailPath = String(entry.thumbnailPath || "")
    return thumbnailRevision >= 0 && (entry.thumbnailReady === true
      || (thumbnailPath !== "" && readyThumbnails[thumbnailPath] === true))
  }

  function shouldLoadImage(entry, index) {
    if (!opened || !entry) return false
    const candidate = Number(index)
    return Number.isFinite(candidate)
      && Math.abs(candidate - selectedIndex) <= imagePreloadRadius
  }

  function sourcePaths(visibleOnly) {
    const result = []
    const seen = {}
    if (visibleOnly) {
      for (let distance = 0; distance <= 5; distance++) {
        const indexes = distance === 0 ? [selectedIndex]
          : [selectedIndex - distance, selectedIndex + distance]
        for (let j = 0; j < indexes.length; j++) {
          const entry = filteredEntries[indexes[j]]
          if (!entry || !entry.sourcePath || isThumbnailReady(entry)
              || seen[entry.sourcePath]) continue
          seen[entry.sourcePath] = true
          result.push(entry.sourcePath)
        }
      }
      return result
    }
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      if (!entry || !entry.sourcePath || isThumbnailReady(entry)
          || seen[entry.sourcePath]) continue
      seen[entry.sourcePath] = true
      result.push(entry.sourcePath)
    }
    return result
  }

  function startWarm(process, sources, niceLevel) {
    if (!runtimeWorkersEnabled || !opened || !Array.isArray(sources)
        || sources.length === 0) return
    process.activeSerial = requestSerial
    process.command = [scriptPath, "warm", mode, String(niceLevel)].concat(sources)
    process.running = true
  }

  function warmVisible() {
    startWarm(priorityWarmProc, sourcePaths(true), 10)
  }

  function warmAll() {
    startWarm(warmProc, sourcePaths(false), 19)
  }

  function noteThumbnailReady(path, serial) {
    if (!opened || serial !== requestSerial) return
    const thumbnailPath = String(path || "").trim()
    if (thumbnailPath === "") return
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      if (!entry || String(entry.thumbnailPath || "") !== thumbnailPath) continue
      if (isThumbnailReady(entry)) return
      readyThumbnails[thumbnailPath] = true
      thumbnailRevision++
      return
    }
  }

  function actionFailureDetail(text, exitCode) {
    const detail = String(text || "").replace(/[\u0000-\u001f\u007f]+/g, " ")
      .replace(/\s+/g, " ").trim()
    return detail !== "" ? detail.slice(0, 240)
      : "Command exited with code " + Number(exitCode) + "."
  }

  function reportActionFailure(kind, label, exitCode, details) {
    const noun = kind === "theme" ? "Theme" : "Wallpaper"
    const target = String(label || "").replace(/[\u0000-\u001f\u007f]+/g, " ")
      .replace(/\s+/g, " ").trim().slice(0, 120)
    const detail = actionFailureDetail(details, exitCode)
    const message = "Could not apply "
      + (target !== "" ? target : noun.toLowerCase()) + ". " + detail
    console.warn("Shibumi " + noun.toLowerCase() + " action failed:", message)
    Quickshell.execDetached(["notify-send", "-a", "Shibumi",
      noun + " change failed", message])
    lastActionFailure = message
  }

  function startSelectionAction(kind, label, command) {
    if (actionProc.running || !Array.isArray(command) || command.length === 0)
      return false
    lastActionFailure = ""
    actionProc.actionKind = String(kind || "")
    actionProc.actionLabel = String(label || "")
    actionProc.errorText = ""
    actionProc.command = command
    actionProc.running = true
    return true
  }

  function activateSelected() {
    const entry = selectedEntry
    if (!entry || !entry.sourcePath) return false
    if (mode === "theme") {
      if (!startSelectionAction("theme", entry.label,
          ["env", "OMARCHY_PATH=" + omarchyPath,
            "omarchy-theme-set", entry.label])) return false
    } else if (mode === "wallpaper") {
      if (!startSelectionAction("wallpaper", entry.label || entry.sourcePath,
          ["omarchy-theme-bg-set", entry.sourcePath])) return false
    } else {
      Quickshell.execDetached(["xdg-open", entry.sourcePath])
      close()
      return true
    }
    close()
    return true
  }

  function applyOfficialSelection(text, requestedMode, serial) {
    if (serial !== requestSerial || !opened) return
    const selection = String(text || "").trim()
    opened = false
    if (selection === "") return
    if (requestedMode === "theme") {
      startSelectionAction("theme", selection,
        ["env", "OMARCHY_PATH=" + omarchyPath,
          "omarchy-theme-set", selection])
    } else if (requestedMode === "wallpaper") {
      startSelectionAction("wallpaper", selection,
        ["omarchy-theme-bg-set", selection])
    } else {
      return
    }
  }

  function copySelected() {
    const entry = selectedEntry
    if (!mediaMode || !entry || !entry.sourcePath) return false
    copyProc.command = videoMode
      ? ["bash", "-c", "printf '%s' \"$1\" | wl-copy", "shibumi-copy", entry.sourcePath]
      : ["bash", "-c", [
          "mime=$(file -Lb --mime-type -- \"$1\") || exit 1;",
          "[[ $mime == image/* ]] || exit 1;",
          "wl-copy --type \"$mime\" < \"$1\""
        ].join(" "), "shibumi-copy", entry.sourcePath]
    statusText = "Copying..."
    copyProc.running = true
    return true
  }

  function requestDeleteSelected() {
    const entry = selectedEntry
    if (!mediaMode || !entry || !entry.sourcePath) return false
    if (!confirmDelete) {
      confirmDelete = true
      deleteConfirmTimeout.restart()
      return true
    }
    deleteConfirmTimeout.stop()
    confirmDelete = false
    deleteProc.command = ["bash", "-c",
      "gio trash -- \"$1\" 2>/dev/null || trash-put -- \"$1\" 2>/dev/null",
      "shibumi-trash", entry.sourcePath]
    deleteProc.running = true
    return true
  }

  onSelectedIndexChanged: confirmDelete = false
  onSelectedEntryChanged: requestThemeMetadata()
  onOpenedChanged: syncOverlay()
  onPresentationEnabledChanged: syncOverlay()
  onBarChanged: syncOverlay()
  onAvailableChanged: if (available && runtimeWorkersEnabled)
    initialPrewarmDelay.restart()
  Component.onDestruction: {
    stopForegroundWorkers()
    wallpaperPrewarmProc.running = false
    themePrewarmProc.running = false
    initialPrewarmDelay.stop()
    wallpaperPrewarmDelay.stop()
  }

  Process {
    id: currentProc
    property int activeSerial: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (currentProc.activeSerial !== root.requestSerial || !root.opened) return
        root.currentSelection = String(text || "").trim()
        root.beginLoads(currentProc.activeSerial)
      }
    }
    onExited: {
      if (activeSerial === root.requestSerial && root.opened && !cacheProc.running
          && !scanProc.running && !scanDelay.running) root.beginLoads(activeSerial)
    }
  }

  Process {
    id: cacheProc
    property int activeSerial: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishCacheLoad(text, cacheProc.activeSerial)
    }
  }

  Process {
    id: scanProc
    property int activeSerial: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRows(text, false, scanProc.activeSerial)
    }
    onExited: function(code) {
      if (activeSerial !== root.requestSerial || !root.opened) return
      root.loading = false
      if (code !== 0) root.statusText = "Scan failed"
    }
  }

  Process {
    id: priorityWarmProc
    property int activeSerial: 0
    stdout: SplitParser {
      onRead: line => root.noteThumbnailReady(line, priorityWarmProc.activeSerial)
    }
  }

  Process {
    id: warmProc
    property int activeSerial: 0
    stdout: SplitParser {
      onRead: line => root.noteThumbnailReady(line, warmProc.activeSerial)
    }
  }

  Process {
    id: cleanupProc
  }

  Process {
    id: actionProc
    property string actionKind: ""
    property string actionLabel: ""
    property string errorText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: actionProc.errorText = String(text || "")
    }
    onExited: function(code) {
      if (code !== 0)
        root.reportActionFailure(actionKind, actionLabel, code, errorText)
    }
  }
  Process {
    id: officialPickerProc
    property int activeSerial: 0
    property string requestedMode: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyOfficialSelection(text,
        officialPickerProc.requestedMode, officialPickerProc.activeSerial)
    }
    onExited: if (activeSerial === root.requestSerial) root.opened = false
  }
  Process {
    id: copyProc
    onExited: function(code) {
      root.statusText = code === 0 ? "Copied" : "Copy failed"
    }
  }

  Process {
    id: themeMetaProc
    property string requestedDirectory: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.selectedEntry
            || String(root.selectedEntry.directory || "") !== themeMetaProc.requestedDirectory)
          return
        const parts = String(text || "").replace(/\n+$/, "").split("\t")
        root.selectedThemeAuthor = parts[0] || ""
        root.selectedThemeRepo = parts[1] || ""
        root.selectedThemePalette = parts[2] ? parts[2].split(",") : []
      }
    }
  }

  Process {
    id: deleteProc
    onExited: function(code) {
      if (code !== 0) {
        root.statusText = "Delete failed; file kept"
        return
      }
      root.statusText = "Moved to trash"
      if (root.opened) root.beginLoads(root.requestSerial, true)
    }
  }

  Process {
    id: wallpaperPrewarmProc
  }

  Process {
    id: themePrewarmProc
  }

  Timer {
    id: warmDelay
    interval: 450
    onTriggered: root.warmAll()
  }

  Timer {
    id: scanDelay
    property int activeSerial: 0
    interval: 650
    onTriggered: root.startScan(activeSerial)
  }

  Timer {
    id: deleteConfirmTimeout
    interval: 3500
    onTriggered: root.confirmDelete = false
  }

  Timer {
    id: themeMetaDelay
    interval: 70
    onTriggered: {
      if (!root.selectedEntry || !root.selectedEntry.directory) return
      const directory = String(root.selectedEntry.directory)
      themeMetaProc.requestedDirectory = directory
      themeMetaProc.command = ["bash", "-c", [
        "d=$1; repo=''; author='';",
        "if [[ -f $d/.git/config ]]; then",
        "repo=$(sed -nE 's#^[[:space:]]*url = (.*)$#\\1#p' \"$d/.git/config\" | head -1);",
        "author=$(printf '%s' \"$repo\" | sed -nE 's#.*github\\.com[:/]+([^/]+)/.*#\\1#p'); fi;",
        "palette=$(awk -F'\"' '$2 ~ /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/ { if (out != \"\") out=out \",\"; out=out $2; if (++n == 6) exit } END { print out }' \"$d/colors.toml\" 2>/dev/null);",
        "printf '%s\\t%s\\t%s\\n' \"$author\" \"$repo\" \"$palette\""
      ].join(" "), "shibumi-theme-meta", directory]
      themeMetaProc.running = true
    }
  }

  Timer {
    id: wallpaperPrewarmDelay
    interval: 120
    onTriggered: {
      if (!root.available || root.imagePickerStyle === "omarchy") return
      wallpaperPrewarmProc.running = false
      wallpaperPrewarmProc.command = [root.scriptPath, "prewarm", "wallpaper",
        root.omarchyPath]
      wallpaperPrewarmProc.running = true
    }
  }

  Timer {
    id: initialPrewarmDelay
    interval: 900
    onTriggered: {
      if (!root.available || root.imagePickerStyle === "omarchy") return
      themePrewarmProc.command = [root.scriptPath, "prewarm", "theme",
        root.omarchyPath]
      themePrewarmProc.running = true
      wallpaperPrewarmDelay.restart()
    }
  }

  FileView {
    path: root.available && root.runtimeWorkersEnabled
      ? root.currentThemeNamePath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: if (root.imagePickerStyle !== "omarchy")
      wallpaperPrewarmDelay.restart()
  }

  onImagePickerStyleChanged: if (available && runtimeWorkersEnabled
      && imagePickerStyle !== "omarchy") initialPrewarmDelay.restart()

  Loader {
    id: overlayLoader
    active: false
  }

  IpcHandler {
    target: "shibumi-picker"

    function theme(): void { root.openMode("theme", null) }
    function wallpaper(): void { root.openMode("wallpaper", null) }
    function route(mode: string): string {
      return root.routeOmarchyAction(mode, null)
    }
    function screenshots(): void { root.openMode("screenshots", null) }
    function videos(): void { root.openMode("videos", null) }
    function close(): void { root.close() }
    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        mode: root.mode,
        style: root.pickerStyle,
        imageStyle: root.imagePickerStyle,
        mediaStyle: root.mediaPickerStyle,
        entries: root.entries.length,
        selected: root.selectedIndex,
        screen: root.activeScreenName,
        loading: root.loading,
        idleInhibited: root.idleInhibited
      })
    }
  }
}
