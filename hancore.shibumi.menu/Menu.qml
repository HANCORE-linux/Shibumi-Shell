import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons as Commons
import "MenuViewModel.js" as MenuViewModel

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var service: null
  property var actionAdapter: null
  property url surfaceSource: Qt.resolvedUrl("MenuSurface.qml")
  property bool opened: false
  property string requestedRoute: "root"
  property string activeRoute: "root"
  property string requestedScreenName: ""
  property var targetScreen: null
  property var navStack: []
  property string query: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool appEditMode: false
  property bool settingsOpen: false
  property var visibleRows: []
  readonly property var appMenuService: {
    if (service) return service
    const pluginId = manifest ? String(manifest.id || "") : ""
    return pluginId && shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor(pluginId)
      : null
  }
  readonly property var actions: actionAdapter || defaultActions
  readonly property bool serviceReady: !!appMenuService && appMenuService.ready === true
  readonly property bool appMode: activeRoute === "apps"
  readonly property var menuConfig: serviceReady ? appMenuService.menuConfig : ({})
  readonly property int presentationScale: menuConfig.presentation
    ? Number(menuConfig.presentation.scale || 100) : 100
  readonly property bool showIcons: !menuConfig.presentation
    || menuConfig.presentation.icons !== false
  readonly property string selectionStyle: menuConfig.presentation
    ? String(menuConfig.presentation.selectionStyle || "default") : "default"
  readonly property string backgroundMode: menuConfig.presentation
    ? String(menuConfig.presentation.background || "off") : "off"
  readonly property var launcherConfig: menuConfig.launcher || ({
    mode: "text", text: "shibumi", icon: "omarchy"
  })
  readonly property var barController: shell && shell.bar ? shell.bar : null
  readonly property var backgroundService: shell
    && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.background") : null
  readonly property string backgroundPath: backgroundService
    ? String(backgroundService.displayedBackground
      || backgroundService.currentBackground || "") : ""
  readonly property int backgroundVersion: backgroundService
    ? Number(backgroundService.backgroundVersion || 0) : 0
  readonly property string backgroundUrl: backgroundPath
    ? Commons.Util.fileUrl(backgroundPath) + "?v=" + backgroundVersion : ""
  readonly property string barPosition: barController
    ? String(barController.position || "top") : "top"
  readonly property int barSize: barController
    ? Number(barController.barSize || 0) : 0
  readonly property string menuTitle: settingsOpen ? "Shibumi settings"
    : appMode ? "Apps" : (() => {
    if (!serviceReady) return "Shibumi"
    const entry = appMenuService.menuItem(activeRoute)
    return entry ? entry.label : "Shibumi"
  })()
  readonly property string activeProviderStatus: {
    if (!serviceReady || appMode) return "idle"
    const entry = appMenuService.menuItem(activeRoute)
    return entry && entry.provider
      ? appMenuService.providerStatus(entry.id)
      : "idle"
  }
  readonly property string emptyMessage: query
    ? "No matches for “" + query + "”"
    : (activeProviderStatus === "running" || activeProviderStatus === "queued"
      ? "Loading options…"
      : (activeProviderStatus === "error" || activeProviderStatus === "unsupported"
        ? "Unable to load options"
        : "Nothing here yet"))

  visible: false
  width: 0
  height: 0

  function parsePayload(payloadJson) {
    try {
      const value = JSON.parse(String(payloadJson || "{}"))
      return value && typeof value === "object" && !Array.isArray(value)
        ? value
        : ({})
    } catch (error) {
      return ({})
    }
  }

  function screenValues() {
    const source = Quickshell.screens
    if (source && typeof source.length === "number") return source
    if (source && source.values && typeof source.values.length === "number")
      return source.values
    return []
  }

  function screenForName(value) {
    const name = String(value || "")
    const screens = screenValues()
    for (let i = 0; i < screens.length; i++) {
      if (screens[i] && String(screens[i].name || "") === name) return screens[i]
    }
    return null
  }

  function resolveTargetScreen(preferredName) {
    let resolved = screenForName(preferredName)
    if (resolved) return resolved
    const focusedName = Hyprland.focusedMonitor
      ? String(Hyprland.focusedMonitor.name || "") : ""
    resolved = screenForName(focusedName)
    const screens = screenValues()
    return resolved || (screens.length > 0 ? screens[0] : null)
  }

  function ensureTargetScreen() {
    const currentName = targetScreen ? String(targetScreen.name || "") : ""
    const current = screenForName(currentName)
    if (current) {
      targetScreen = current
      return
    }
    targetScreen = resolveTargetScreen(requestedScreenName)
  }

  function normalizeRoute(value) {
    const candidate = String(value || "root")
    if (/^(apps?|applications)$/.test(candidate)) return "apps"
    if (!serviceReady) return candidate === "root" ? "root" : candidate
    const resolved = appMenuService.resolveMenuRoute(candidate)
    return appMenuService.menuItem(resolved) ? resolved : "root"
  }

  function open(payloadJson) {
    const payload = parsePayload(payloadJson)
    requestedRoute = String(payload.menu || payload.initialMenu || "root")
    requestedScreenName = String(payload.screen || "")
    targetScreen = resolveTargetScreen(requestedScreenName)
    navStack = []
    query = ""
    selectedIndex = 0
    cursorActive = false
    appEditMode = false
    settingsOpen = false
    activeRoute = normalizeRoute(requestedRoute)
    opened = true
    if (serviceReady) appMenuService.menuOpen = true
    if (serviceReady) {
      appMenuService.evaluateGuards()
      loadProviders()
    }
    refreshRows()
    return "ok"
  }

  function close() {
    opened = false
    if (serviceReady) appMenuService.menuOpen = false
    query = ""
    navStack = []
    appEditMode = false
    settingsOpen = false
    visibleRows = []
  }

  function dismiss() {
    close()
    if (!shell || typeof shell.hide !== "function") return
    const pluginId = manifest ? String(manifest.id || "") : ""
    if (pluginId) Qt.callLater(function() { shell.hide(pluginId) })
  }

  function refresh() {
    return serviceReady && typeof appMenuService.refresh === "function"
      ? appMenuService.refresh()
      : "unavailable"
  }

  function ping() {
    return "ok"
  }

  function setRoute(value, pushHistory) {
    const next = normalizeRoute(value)
    if (pushHistory && next !== activeRoute)
      navStack = navStack.concat([activeRoute])
    activeRoute = next
    query = ""
    appEditMode = false
    settingsOpen = false
    selectedIndex = 0
    cursorActive = false
    loadProviders()
    refreshRows()
  }

  function goBack() {
    if (settingsOpen) {
      settingsOpen = false
      return true
    }
    if (query) {
      setQuery("")
      return true
    }
    if (appEditMode) {
      appEditMode = false
      refreshRows()
      return true
    }
    if (navStack.length > 0) {
      const previous = navStack[navStack.length - 1]
      navStack = navStack.slice(0, navStack.length - 1)
      setRoute(previous, false)
      return true
    }
    if (activeRoute !== "root") {
      if (appMode) setRoute("root", false)
      else {
        const current = serviceReady ? appMenuService.menuItem(activeRoute) : null
        setRoute(current && current.parent ? current.parent : "root", false)
      }
      return true
    }
    return false
  }

  function setQuery(value) {
    const next = String(value || "")
    if (query === next) return
    query = next
    selectedIndex = 0
    cursorActive = false
    loadProviders()
    refreshRows()
  }

  function setAppEditMode(value) {
    appEditMode = appMode && value === true
    selectedIndex = 0
    cursorActive = false
    refreshRows()
  }

  function openSettings() {
    query = ""
    appEditMode = false
    settingsOpen = true
    cursorActive = false
    selectedIndex = 0
  }

  function setPresentation(name, value) {
    return serviceReady && typeof appMenuService.setPresentation === "function"
      ? appMenuService.setPresentation(name, value)
      : false
  }

  function setLauncher(name, value) {
    return serviceReady && typeof appMenuService.setLauncher === "function"
      ? appMenuService.setLauncher(name, value)
      : false
  }

  Component.onDestruction: {
    if (serviceReady) appMenuService.menuOpen = false
  }

  function loadProviders() {
    if (!serviceReady || appMode) return
    const ids = MenuViewModel.providerIds(
      appMenuService.menuModel, activeRoute, query)
    for (let i = 0; i < ids.length; i++) appMenuService.loadProvider(ids[i])
  }

  function appRows() {
    if (!serviceReady) return []
    const source = appMenuService.search(query, appEditMode, 256)
    const result = []
    for (let i = 0; i < source.length; i++) {
      const row = source[i]
      result.push({
        id: row.id,
        isApp: true,
        kind: "app",
        target: "",
        label: row.name,
        icon: row.icon,
        iconFont: "",
        description: row.genericName || row.comment,
        detail: row.genericName || row.comment,
        action: "",
        checkedState: false,
        childCount: 0,
        section: "",
        score: row.score,
        favorite: row.favorite === true,
        hidden: row.hidden === true,
        entry: row.entry
      })
    }
    return result
  }

  function refreshRows() {
    if (!opened || !serviceReady) {
      visibleRows = []
      selectedIndex = 0
      return
    }
    visibleRows = appMode ? appRows() : MenuViewModel.routeRows(
      appMenuService.menuModel,
      activeRoute,
      query,
      appMenuService.whenResults,
      appMenuService.checkedResults,
      256)
    if (visibleRows.length === 0) selectedIndex = 0
    else selectedIndex = Math.max(0, Math.min(selectedIndex, visibleRows.length - 1))
  }

  function select(delta) {
    if (visibleRows.length === 0) return false
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? visibleRows.length - 1 : 0
      return true
    }
    cursorActive = true
    selectedIndex = (selectedIndex + delta + visibleRows.length) % visibleRows.length
    return true
  }

  function selectIndex(index) {
    if (index < 0 || index >= visibleRows.length) return false
    cursorActive = true
    selectedIndex = index
    return true
  }

  function activateIndex(index) {
    if (index < 0 || index >= visibleRows.length) return false
    const row = visibleRows[index]
    if (row.isApp) {
      if (appEditMode) return false
      const launched = actions.launchApplication(row.entry)
      if (launched) dismiss()
      return launched
    }
    if (row.kind === "menu" || row.kind === "link") {
      setRoute(row.target || row.id, true)
      return true
    }
    const dispatched = actions.runAction(row.action)
    if (dispatched) dismiss()
    return dispatched
  }

  function toggleFavorite(entryId) {
    if (!serviceReady || !appMenuService.toggleFavorite(entryId)) return false
    refreshRows()
    return true
  }

  function toggleHidden(entryId) {
    if (!serviceReady || !appMenuService.toggleHidden(entryId)) return false
    refreshRows()
    return true
  }

  function debugState(_arg) {
    return JSON.stringify({
      opened: opened,
      route: activeRoute,
      requestedRoute: requestedRoute,
      screen: targetScreen ? String(targetScreen.name || "") : "",
      serviceReady: serviceReady,
      rowCount: visibleRows.length,
      appMode: appMode,
      settingsOpen: settingsOpen,
      surfaceLoaded: surfaceLoader.item !== null
    })
  }

  function syncSurface() {
    const source = String(surfaceSource || "")
    if (!opened || !source) {
      surfaceLoader.source = ""
      return
    }
    surfaceLoader.setSource(surfaceSource, { controller: root })
  }

  MenuActions { id: defaultActions }

  Loader {
    id: surfaceLoader
    onLoaded: Qt.callLater(function() {
      if (surfaceLoader.item) surfaceLoader.item.focusSearch()
    })
  }

  onOpenedChanged: syncSurface()
  onSurfaceSourceChanged: syncSurface()

  Connections {
    target: root.appMenuService
    ignoreUnknownSignals: true
    function onRevisionChanged() {
      if (!root.opened) return
      root.activeRoute = root.normalizeRoute(root.activeRoute)
      root.refreshRows()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() { if (root.opened) root.ensureTargetScreen() }
  }
}
