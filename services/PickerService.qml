pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons as Commons
import "PickerModel.js" as PickerModel

Item {
  id: root

  property var bar: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string scriptPath: String(
    Qt.resolvedUrl("../scripts/shibumi-picker")).replace("file://", "")
  readonly property bool available: bar !== null && bar.hostReady
    && bar.omarchyPath !== ""

  property bool opened: false
  property string mode: "wallpaper"
  property string pickerStyle: "tanzaku"
  property var activeScreen: null
  property string activeScreenName: activeScreen ? String(activeScreen.name || "") : ""
  property var entries: []
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
  property int requestSerial: 0
  property bool cachedRowsApplied: false
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

  function normalizeStyle(value) {
    const candidate = String(value || "")
    return ["tanzaku", "hearthstone", "carousel"].indexOf(candidate) >= 0
      ? candidate : "tanzaku"
  }

  function resolveTargetScreen(preferred) {
    if (preferred && String(preferred.name || "") !== "") return preferred
    const focusedName = Hyprland.focusedMonitor
      ? String(Hyprland.focusedMonitor.name || "") : ""
    return bar && typeof bar.screenForName === "function"
      ? bar.screenForName(focusedName) : null
  }

  function cycleStyle(direction) {
    const styles = ["tanzaku", "hearthstone", "carousel"]
    const current = Math.max(0, styles.indexOf(normalizeStyle(pickerStyle)))
    const step = Number(direction) < 0 ? -1 : 1
    const next = styles[(current + step + styles.length) % styles.length]
    if (!bar || typeof bar.mutateShibumiConfig !== "function") return false
    return bar.mutateShibumiConfig(function(config) {
      if (!config.picker || typeof config.picker !== "object") config.picker = {}
      config.picker.style = next
    })
  }

  function openMode(nextMode, screen) {
    const candidate = String(nextMode || "")
    if (["theme", "wallpaper", "screenshots", "videos"].indexOf(candidate) < 0)
      return false
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
    entries = []
    cachedRowsApplied = false
    scanComplete = false
    loading = true
    opened = true
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

  function close() {
    if (!opened) return
    requestSerial++
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
    clearThemeMetadata()
  }

  function beginLoads(serial) {
    if (!opened || serial !== requestSerial) return
    cacheProc.activeSerial = serial
    cacheProc.command = [scriptPath, "cached", mode]
    cacheProc.running = true
    scanProc.activeSerial = serial
    scanProc.command = [scriptPath, "scan", mode, bar.omarchyPath]
    scanProc.running = true
  }

  function applyRows(text, fromCache, serial) {
    if (!opened || serial !== requestSerial) return
    const parsed = PickerModel.parseRows(text)
    if (fromCache && (cachedRowsApplied || parsed.length === 0)) return
    if (fromCache && entries.length > 0) return
    if (!fromCache) scanComplete = true
    if (parsed.length === 0 && fromCache) return
    entries = parsed
    cachedRowsApplied = fromCache
    selectedIndex = selectedIndexForCurrent(parsed)
    loading = fromCache ? true : false
    Qt.callLater(function() {
      if (!root.opened || serial !== root.requestSerial) return
      root.warmVisible()
      warmDelay.restart()
    })
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
    if (!entry || !entry.thumbnailReady || !entry.thumbnailPath) return ""
    return Commons.Util.fileUrl(entry.thumbnailPath)
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
          if (!entry || !entry.sourcePath || entry.thumbnailReady
              || seen[entry.sourcePath]) continue
          seen[entry.sourcePath] = true
          result.push(entry.sourcePath)
        }
      }
      return result
    }
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i]
      if (!entry || !entry.sourcePath || entry.thumbnailReady
          || seen[entry.sourcePath]) continue
      seen[entry.sourcePath] = true
      result.push(entry.sourcePath)
    }
    return result
  }

  function startWarm(process, sources, niceLevel) {
    if (!opened || !Array.isArray(sources) || sources.length === 0) return
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
    entries = PickerModel.replaceThumbnailReady(entries, String(path || "").trim())
  }

  function activateSelected() {
    const entry = selectedEntry
    if (!entry || !entry.sourcePath) return false
    if (mode === "theme") {
      actionProc.command = ["env", "OMARCHY_PATH=" + bar.omarchyPath,
        "omarchy-theme-set", entry.label]
    } else if (mode === "wallpaper") {
      actionProc.command = ["omarchy-theme-bg-set", entry.sourcePath]
    } else {
      Quickshell.execDetached(["xdg-open", entry.sourcePath])
      close()
      return true
    }
    actionProc.running = true
    close()
    return true
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
  onAvailableChanged: if (available) initialPrewarmDelay.restart()
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
          && !scanProc.running) root.beginLoads(activeSerial)
    }
  }

  Process {
    id: cacheProc
    property int activeSerial: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRows(text, true, cacheProc.activeSerial)
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

  Process { id: actionProc }
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
      if (root.opened) root.beginLoads(root.requestSerial)
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
      if (!root.available) return
      wallpaperPrewarmProc.running = false
      wallpaperPrewarmProc.command = [root.scriptPath, "prewarm", "wallpaper",
        root.bar.omarchyPath]
      wallpaperPrewarmProc.running = true
    }
  }

  Timer {
    id: initialPrewarmDelay
    interval: 900
    onTriggered: {
      if (!root.available) return
      themePrewarmProc.command = [root.scriptPath, "prewarm", "theme",
        root.bar.omarchyPath]
      themePrewarmProc.running = true
      wallpaperPrewarmDelay.restart()
    }
  }

  FileView {
    path: root.available ? root.currentThemeNamePath : ""
    watchChanges: true
    printErrors: false
    onFileChanged: wallpaperPrewarmDelay.restart()
  }
}
