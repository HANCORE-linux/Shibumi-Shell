import QtQuick
import Quickshell
import Quickshell.Io
import "../core/ShibumiConfig.js" as ShibumiConfig
import "AppIndex.js" as AppIndex
import "GuardModel.js" as GuardModel
import "MenuModel.js" as MenuModel
import "ProcessResult.js" as ProcessResult
import "ProviderModel.js" as ProviderModel

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property int revision: 0
  property var menuConfig: ShibumiConfig.defaultMenuConfig()
  property var favoriteIds: []
  property var hiddenIds: []
  property var allIndexedEntries: []
  property var indexedEntries: []
  property var defaultMenuItems: []
  property var userMenuItems: []
  property var menuModel: MenuModel.mergeMenuSources([], [])
  property var runtimeMenuItems: []
  property int menuGeneration: 0
  property bool defaultMenuValid: false
  property bool userMenuValid: true
  property string menuError: ""
  property var whenResults: ({})
  property var checkedResults: ({})
  property bool guardsReady: true
  property bool menuOpen: false
  property string guardStatus: "ready"
  property int guardRunGeneration: -1
  property bool guardRerunPending: false
  property var providerItemsByMenu: ({})
  property var providerStatuses: ({})
  property var providerQueue: []
  property int providerRunGeneration: -1
  property var desktopEntrySource: DesktopEntries.applications.values || []
  readonly property var desktopEntries: desktopEntrySource
  readonly property string defaultMenuPath: omarchyPath
    ? omarchyPath + "/default/omarchy/omarchy-menu.jsonc" : ""
  readonly property string userMenuPath: Quickshell.env("HOME")
    + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  readonly property bool ready: true
  readonly property bool menuReady: defaultMenuValid

  visible: false
  width: 0
  height: 0

  function refresh() {
    rebuildIndex()
    if (defaultMenuPath) defaultMenuFile.reload()
    if (userMenuPath) userMenuFile.reload()
    revision++
    return "ok"
  }

  function configure(value) {
    menuConfig = ShibumiConfig.normalizeMenu(value)
    favoriteIds = menuConfig.favorites.slice()
    hiddenIds = menuConfig.hidden.slice()
    rebuildIndex()
    revision++
  }

  function persistMenuConfig(value) {
    const next = ShibumiConfig.normalizeMenu(value)
    configure(next)
    if (!shell || typeof shell.mutateShellConfig !== "function") return true
    shell.mutateShellConfig(function(config) {
      if (!config.bar || typeof config.bar !== "object" || Array.isArray(config.bar))
        config.bar = ({})
      if (!config.bar.shibumi || typeof config.bar.shibumi !== "object"
          || Array.isArray(config.bar.shibumi)) config.bar.shibumi = ({})
      config.bar.shibumi.menu = next
    })
    return true
  }

  function persistMenuPreferences(nextFavorites, nextHidden) {
    return persistMenuConfig({
      version: menuConfig.version,
      favorites: nextFavorites,
      hidden: nextHidden,
      launcher: menuConfig.launcher,
      presentation: menuConfig.presentation
    })
  }

  function setPresentation(name, value) {
    const key = String(name || "")
    if (["icons", "scale", "selectionStyle", "background"].indexOf(key) < 0)
      return false
    const candidate = {
      icons: menuConfig.presentation.icons,
      scale: menuConfig.presentation.scale,
      selectionStyle: menuConfig.presentation.selectionStyle,
      background: menuConfig.presentation.background
    }
    candidate[key] = value
    const normalized = ShibumiConfig.normalizeMenu({
      version: menuConfig.version,
      favorites: favoriteIds,
      hidden: hiddenIds,
      launcher: menuConfig.launcher,
      presentation: candidate
    })
    if (normalized.presentation[key] !== value) return false
    return persistMenuConfig(normalized)
  }

  function setLauncher(name, value) {
    const key = String(name || "")
    if (["mode", "text", "icon"].indexOf(key) < 0) return false
    const candidate = {
      mode: menuConfig.launcher.mode,
      text: menuConfig.launcher.text,
      icon: menuConfig.launcher.icon
    }
    candidate[key] = value
    const normalized = ShibumiConfig.normalizeMenu({
      version: menuConfig.version,
      favorites: favoriteIds,
      hidden: hiddenIds,
      launcher: candidate,
      presentation: menuConfig.presentation
    })
    if (normalized.launcher[key] !== value) return false
    return persistMenuConfig(normalized)
  }

  function toggleFavorite(entryId) {
    const id = AppIndex.normalizeDesktopId(entryId)
    if (!id || !entryForId(id)) return false
    const next = favoriteIds.slice()
    const index = next.indexOf(id)
    if (index >= 0) next.splice(index, 1)
    else next.push(id)
    return persistMenuPreferences(next, hiddenIds)
  }

  function toggleHidden(entryId) {
    const id = AppIndex.normalizeDesktopId(entryId)
    if (!id || !entryForId(id)) return false
    const next = hiddenIds.slice()
    const index = next.indexOf(id)
    if (index >= 0) next.splice(index, 1)
    else next.push(id)
    return persistMenuPreferences(favoriteIds, next)
  }

  function syncConfiguration() {
    const config = shell && shell.shellConfig ? shell.shellConfig : null
    const barConfig = config && config.bar ? config.bar : null
    const shibumi = barConfig && barConfig.shibumi ? barConfig.shibumi : null
    configure(shibumi ? shibumi.menu : null)
  }

  function rebuildIndex() {
    allIndexedEntries = AppIndex.sortedEntries(
      desktopEntries, "", favoriteIds, hiddenIds, true)
    indexedEntries = AppIndex.sortedEntries(
      desktopEntries, "", favoriteIds, hiddenIds, false)
  }

  function search(query, includeHidden, limit) {
    const rows = AppIndex.sortedEntries(
      desktopEntries, query, favoriteIds, hiddenIds, includeHidden === true)
    const count = Math.max(1, Math.min(512, Number(limit) || 256))
    return rows.slice(0, count)
  }

  function entryForId(value) {
    const id = AppIndex.normalizeDesktopId(value)
    for (let i = 0; i < allIndexedEntries.length; i++) {
      if (allIndexedEntries[i].id === id) return allIndexedEntries[i].entry
    }
    return null
  }

  function replaceMenuTexts(defaultText, userText) {
    const defaultResult = MenuModel.parseMenuJsonc(defaultText)
    const userResult = MenuModel.parseMenuJsonc(userText)
    defaultMenuValid = defaultResult.ok && defaultResult.items.length > 0
    userMenuValid = userResult.ok
    defaultMenuItems = defaultMenuValid ? defaultResult.items : []
    userMenuItems = userResult.ok ? userResult.items : []
    menuError = !defaultResult.ok ? "invalid-default-menu"
      : (!userResult.ok ? "invalid-user-menu" : "")
    rebuildMenuModel()
  }

  function setDefaultMenuText(text, available) {
    const parsed = available === false
      ? ({ ok: false, items: [], error: "missing-default" })
      : MenuModel.parseMenuJsonc(text)
    defaultMenuValid = parsed.ok && parsed.items.length > 0
    defaultMenuItems = defaultMenuValid ? parsed.items : []
    menuError = defaultMenuValid ? (userMenuValid ? "" : "invalid-user-menu")
      : "invalid-default-menu"
    rebuildMenuModel()
  }

  function setUserMenuText(text, available) {
    const parsed = available === false
      ? ({ ok: true, items: [], error: "" })
      : MenuModel.parseMenuJsonc(text)
    userMenuValid = parsed.ok
    userMenuItems = parsed.ok ? parsed.items : []
    menuError = !defaultMenuValid ? "invalid-default-menu"
      : (parsed.ok ? "" : "invalid-user-menu")
    rebuildMenuModel()
  }

  function rebuildMenuModel() {
    menuGeneration++
    runtimeMenuItems = []
    providerItemsByMenu = ({})
    providerStatuses = ({})
    providerQueue = []
    composeMenuModel()
    evaluateGuards()
  }

  function composeMenuModel() {
    menuModel = MenuModel.mergeMenuSources(
      defaultMenuItems, userMenuItems, runtimeMenuItems)
    resetGuardState()
    revision++
  }

  function resetGuardState() {
    const initial = GuardModel.initialState(menuModel)
    whenResults = initial.whenResults
    checkedResults = initial.checkedResults
    guardsReady = initial.guardCount === 0
    guardStatus = guardsReady ? "ready" : "pending"
    guardRerunPending = false
  }

  function evaluateGuards() {
    const script = GuardModel.scriptFor(menuModel)
    resetGuardState()
    if (!script) return "ready"
    if (guardProc.running) {
      guardRerunPending = true
      guardStatus = "queued"
      return "queued"
    }
    guardProc.collected = ""
    guardRunGeneration = menuGeneration
    guardProc.command = ["timeout", "--kill-after=1s", "4s", "bash", "-lc", script]
    guardStatus = "running"
    guardProc.running = true
    return "running"
  }

  function providerStatus(menuId) {
    return providerStatuses["$" + String(menuId || "")] || "idle"
  }

  function setProviderStatus(menuId, status) {
    const next = ({})
    for (const key in providerStatuses) next[key] = providerStatuses[key]
    next["$" + String(menuId || "")] = status
    providerStatuses = next
  }

  function loadProvider(menuId) {
    const entry = menuItem(menuId)
    if (!entry || !entry.provider) return "none"
    if (ProviderModel.commandFor(entry.provider).length === 0) {
      setProviderStatus(entry.id, "unsupported")
      return "unsupported"
    }
    const status = providerStatus(entry.id)
    if (status === "loaded" || status === "running" || status === "queued") return status
    providerQueue = providerQueue.concat([entry.id])
    setProviderStatus(entry.id, "queued")
    startNextProvider()
    return providerStatus(entry.id)
  }

  function startNextProvider() {
    if (providerProc.running) return
    while (providerQueue.length > 0) {
      const menuId = providerQueue[0]
      providerQueue = providerQueue.slice(1)
      const entry = menuItem(menuId)
      const command = entry ? ProviderModel.commandFor(entry.provider) : []
      if (!entry || command.length === 0) {
        setProviderStatus(menuId, "unsupported")
        continue
      }
      providerProc.menuId = menuId
      providerProc.providerKey = entry.provider
      providerProc.collected = ""
      providerRunGeneration = menuGeneration
      providerProc.command = command
      setProviderStatus(menuId, "running")
      providerProc.running = true
      return
    }
  }

  function acceptProviderOutput(menuId, providerKey, output) {
    const rows = ProviderModel.rows(providerKey, menuId, output)
    const patches = []
    for (let i = 0; i < rows.length; i++) {
      const patch = MenuModel.patchForItem(rows[i].id, rows[i].raw)
      if (patch) patches.push(patch)
    }
    const nextByMenu = ({})
    for (const key in providerItemsByMenu) nextByMenu[key] = providerItemsByMenu[key]
    nextByMenu["$" + menuId] = patches
    providerItemsByMenu = nextByMenu
    const combined = []
    for (const key in nextByMenu) {
      const values = nextByMenu[key]
      for (let i = 0; i < values.length; i++) combined.push(values[i])
    }
    runtimeMenuItems = combined
    menuModel = MenuModel.mergeMenuSources(
      defaultMenuItems, userMenuItems, runtimeMenuItems)
    revision++
    return patches.length
  }

  function menuItem(value) {
    return MenuModel.item(menuModel, value)
  }

  function resolveMenuRoute(value) {
    return MenuModel.resolveRoute(menuModel, value)
  }

  function menuChildren(parentId, externalWhenResults, externalCheckedResults) {
    return MenuModel.children(
      menuModel,
      parentId,
      externalWhenResults || whenResults,
      externalCheckedResults || checkedResults)
  }

  function debugState() {
    return {
      ready: ready,
      revision: revision,
      appCount: indexedEntries.length,
      favoriteCount: favoriteIds.length,
      hiddenCount: hiddenIds.length,
      menuReady: menuReady,
      menuCount: menuModel.itemOrder.length,
      menuError: menuError,
      guardsReady: guardsReady,
      guardStatus: guardStatus,
      guardRunning: guardProc.running,
      providerRunning: providerProc.running,
      providerQueueCount: providerQueue.length
    }
  }

  onShellChanged: syncConfiguration()

  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onShellConfigChanged() { root.syncConfiguration() }
  }

  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: root.setDefaultMenuText(text(), true)
    onLoadFailed: root.setDefaultMenuText("", false)
    onFileChanged: reload()
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: data => guardProc.collected += data + "\n"
    }
    onExited: function(exitCode, exitStatus) {
      if (ProcessResult.succeeded(exitCode, exitStatus)
          && root.guardRunGeneration === root.menuGeneration) {
        const state = GuardModel.parseOutput(root.menuModel, guardProc.collected)
        root.whenResults = state.whenResults
        root.checkedResults = state.checkedResults
        root.guardsReady = true
        root.guardStatus = "ready"
        root.revision++
      } else if (root.guardRunGeneration === root.menuGeneration) {
        root.guardStatus = "error"
      }
      if (root.guardRerunPending) {
        root.guardRerunPending = false
        root.evaluateGuards()
      }
    }
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    stdout: SplitParser {
      onRead: data => providerProc.collected += data + "\n"
    }
    onExited: function(exitCode, exitStatus) {
      if (root.providerRunGeneration === root.menuGeneration) {
        if (ProcessResult.succeeded(exitCode, exitStatus)) {
          root.acceptProviderOutput(
            providerProc.menuId, providerProc.providerKey, providerProc.collected)
          root.setProviderStatus(providerProc.menuId, "loaded")
        } else {
          root.setProviderStatus(providerProc.menuId, "error")
        }
      }
      root.startNextProvider()
    }
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: root.setUserMenuText(text(), true)
    onLoadFailed: root.setUserMenuText("", false)
    onFileChanged: reload()
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.refresh() }
  }

  Component.onCompleted: syncConfiguration()
}
