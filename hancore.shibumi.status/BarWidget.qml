pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  property var bar: null
  property string moduleName: "hancore.shibumi.status"
  property var settings: ({})
  readonly property url updateSource: registeredSource(
    "hancore.shibumi.update-center")
  readonly property url traySource: registeredSource("omarchy.tray")
  property Component updateComponent: String(updateSource) ? null
    : registeredComponent("hancore.shibumi.update-center")
  property Component trayComponent: String(traySource) ? null
    : registeredComponent("omarchy.tray")
  property url trayDrawerSource: Qt.resolvedUrl("TrayDrawerPanel.qml")
  property url trayAppMenuSource: Qt.resolvedUrl("TrayAppMenuPanel.qml")
  property url notificationPanelSource: Qt.resolvedUrl("NotificationPanel.qml")
  property bool trayDrawerOpen: false
  property bool trayAppMenuOpen: false
  property var trayAppMenuItem: null
  property var trayAppMenuAnchor: null
  property real trayAppMenuAnchorX: 0
  property bool notificationPanelOpen: false

  HostTokens { id: hostTokens; bar: root.bar }
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property string displayMode: {
    const value = String(settings && settings.displayMode !== undefined
      ? settings.displayMode : "full")
    return ["full", "icon", "text"].indexOf(value) >= 0 ? value : "full"
  }
  readonly property bool fullMode: displayMode === "full"
  readonly property bool iconMode: displayMode === "icon"
  readonly property bool textMode: displayMode === "text"
  readonly property bool v2Mode: tokens && tokens.v2Shell === true
  readonly property int statusActionSlot: Commons.Style.space(22)
  readonly property int horizontalInset: tokens
    && tokens.pillPaddingX !== undefined
    ? Number(tokens.pillPaddingX) || Commons.Style.space(9)
    : Commons.Style.space(9)
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property bool v1CustomToneActive: !!(tokens
    && tokens.v2Shell !== true
    && typeof tokens.widgetHasFill === "function"
    && tokens.widgetHasFill(settings))
  readonly property color badgeContrastColor: v1CustomToneActive && tokens
    && typeof tokens.widgetFillColor === "function"
    ? tokens.widgetFillColor(settings)
    : bar ? bar.background : Commons.Color.background
  readonly property var updateWidget: updateLoader.item
  readonly property var trayWidget: trayLoader.item
  readonly property var notificationService: bar && bar.shell
    && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var trayDrawerItem: trayDrawerLoader.item
  readonly property var trayAppMenuPanelItem: trayAppMenuLoader.item
  readonly property var notificationPanelItem: notificationPanelLoader.item
  readonly property bool trayDrawerLoaded: trayDrawerItem !== null
  readonly property bool notificationPanelLoaded: notificationPanelItem !== null
  readonly property bool panelLoaded: notificationPanelLoaded
  readonly property bool updatePresented: updateWidget !== null
  readonly property bool trayPresented: trayView.presented
  readonly property bool notificationPresented: notificationView.presented
  readonly property int pendingCount: notificationView.pendingCount
  readonly property int recentCount: notificationView.recentCount
  readonly property int notificationCount: notificationView.notificationCount
  readonly property string textLabel: notificationService
    && notificationService.doNotDisturb === true ? "DND"
    : notificationCount > 0
      ? notificationCount + (notificationCount === 1
        ? " NOTIFICATION" : " NOTIFICATIONS") : "CLEAR"
  readonly property bool ready: updateWidget !== null || trayWidget !== null
    || notificationService !== null
  readonly property bool opened: trayDrawerOpen || trayAppMenuOpen
    || notificationPanelOpen
    || childOpened(updateWidget)
    || childOpened(trayWidget)
  readonly property bool hasVisibleChild:
    fullMode && (updatePresented || trayPresented || notificationPresented)
    || iconMode && notificationPresented
    || textMode && notificationService !== null
  readonly property real childGap: Commons.Style.space(4)
  readonly property int presentedCount: fullMode
    ? (updatePresented ? 1 : 0) + (trayPresented ? 1 : 0)
      + (notificationPresented ? 1 : 0)
    : hasVisibleChild ? 1 : 0
  readonly property real contentWidth:
    fullMode
      ? updateSlotWidth + traySlotWidth + notificationSlotWidth
        + Math.max(0, presentedCount - 1) * childGap
      : textMode ? textStatus.implicitWidth : notificationView.implicitWidth
  readonly property real updateSlotWidth: updatePresented
    ? updateSlot.implicitWidth : 0
  readonly property real traySlotWidth: trayPresented
    ? trayView.implicitWidth : 0
  readonly property real notificationSlotWidth: notificationPresented
    ? notificationView.implicitWidth : 0
  readonly property real trayPinnedIconOffset:
    trayView.pinnedIconHorizontalOffset
  readonly property color trayDrawerIconColor: trayView.drawerIconColor
  readonly property color trayDrawerBadgeColor: trayView.drawerBadgeColor
  readonly property color trayDrawerBadgeTextColor:
    trayView.drawerBadgeTextColor
  readonly property color notificationBadgeColor:
    notificationView.badgeFillColor
  readonly property color notificationBadgeTextColor:
    notificationView.badgeTextColor
  readonly property real notificationIconOffset:
    notificationView.iconHorizontalOffset
  readonly property real updateSlotLayer: updateSlot.z
  readonly property real traySlotLayer: trayView.z
  readonly property real notificationSlotLayer: notificationView.z
  readonly property real updateBadgeLayer: updateWidget
    && "badgeLayer" in updateWidget ? Number(updateWidget.badgeLayer) : 0
  readonly property real trayBadgeLayer: trayView.badgeLayer
  readonly property real notificationBadgeLayer: notificationView.badgeLayer

  visible: ready && hasVisibleChild
  implicitWidth: visible ? contentWidth + 2 * horizontalInset : 0
  implicitHeight: visible ? (bar ? bar.barSize : Commons.Style.space(35)) : 0

  function registeredComponent(id) {
    if (bar && typeof bar.registeredWidgetComponent === "function")
      return bar.registeredWidgetComponent(id)
    const registry = bar ? bar.barWidgetRegistry : null
    if (registry) void(registry.revision)
    const widgets = registry && registry.widgets ? registry.widgets : ({})
    const entry = widgets[id]
    return entry ? entry.component : null
  }

  function registeredSource(id) {
    if (bar && typeof bar.registeredWidgetSource === "function")
      return bar.registeredWidgetSource(id)
    const registry = bar && bar.shell
      && "pluginRegistry" in bar.shell ? bar.shell.pluginRegistry : null
    const pluginManifest = registry && registry.installedPlugins
      ? registry.installedPlugins[String(id || "")] : null
    return registry && typeof registry.entryPointUrl === "function"
      ? registry.entryPointUrl(pluginManifest, "barWidget") : ""
  }

  function childSettings(id) {
    return bar && typeof bar.widgetSettings === "function"
      ? bar.widgetSettings("G3", id) : ({})
  }

  function persistEmbeddedTraySettings(moduleId, values) {
    const id = String(moduleId || "")
    if (id !== "omarchy.tray" || !values || typeof values !== "object"
        || Array.isArray(values)) return false
    const state = bar && bar.shell
      && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("hancore.shibumi.state") : null
    if (!state || typeof state.setWidgetSetting !== "function") return false
    let changed = false
    for (const key in values) {
      if (key === "id"
          || !Object.prototype.hasOwnProperty.call(values, key)) continue
      changed = state.setWidgetSetting("G3", id, key, values[key]) || changed
    }
    return changed
  }

  function injectChild(item, id) {
    if (!item) return
    if ("bar" in item) item.bar = hostProxy
    if ("moduleName" in item) item.moduleName = id
    if ("settings" in item) item.settings = childSettings(id)
    item.opacity = 0
  }

  function injectUpdateChild(item) {
    if (!item) return
    if ("bar" in item) item.bar = root.bar
    if ("moduleName" in item) item.moduleName = "hancore.shibumi.update-center"
    if ("settings" in item)
      item.settings = childSettings("hancore.shibumi.update-center")
    if ("contentColor" in item) item.contentColor = root.widgetInk
    if ("customToneActive" in item)
      item.customToneActive = root.v1CustomToneActive
    if ("badgeContrastColor" in item)
      item.badgeContrastColor = root.badgeContrastColor
  }

  function syncUpdateInk() {
    if (!updateWidget) return
    if ("contentColor" in updateWidget)
      updateWidget.contentColor = root.widgetInk
    if ("customToneActive" in updateWidget)
      updateWidget.customToneActive = root.v1CustomToneActive
    if ("badgeContrastColor" in updateWidget)
      updateWidget.badgeContrastColor = root.badgeContrastColor
  }

  function injectChildren() {
    injectUpdateChild(updateWidget)
    injectChild(trayWidget, "omarchy.tray")
  }

  function syncLoader(loader, component, source, id) {
    loader.sourceComponent = null
    loader.source = ""
    if (component !== null) {
      loader.sourceComponent = component
    } else if (String(source)) {
      loader.setSource(source, {
        bar: hostProxy,
        moduleName: id,
        settings: childSettings(id)
      })
    }
  }

  function syncTrayLoader() {
    syncLoader(trayLoader, trayComponent, traySource, "omarchy.tray")
  }

  function syncUpdateLoader() {
    updateLoader.sourceComponent = null
    updateLoader.source = ""
    if (updateComponent !== null) {
      updateLoader.sourceComponent = updateComponent
    } else if (String(updateSource)) {
      updateLoader.setSource(updateSource, {
        bar: root.bar,
        moduleName: "hancore.shibumi.update-center",
        settings: childSettings("hancore.shibumi.update-center")
      })
    }
  }

  function syncTrayDrawerLoader() {
    trayDrawerLoader.source = ""
    if (!trayDrawerOpen || !trayWidget || !String(trayDrawerSource)) return
    trayDrawerLoader.setSource(trayDrawerSource, {
      ownerWidget: root,
      trayBackend: trayWidget,
      anchorItem: trayView,
      bar: root.bar
    })
  }

  function syncTrayAppMenuLoader() {
    trayAppMenuLoader.source = ""
    if (!trayAppMenuOpen || !trayAppMenuItem || !trayAppMenuAnchor
        || !String(trayAppMenuSource)) return
    trayAppMenuLoader.setSource(trayAppMenuSource, {
      ownerWidget: root,
      trayItem: trayAppMenuItem,
      anchorItem: trayAppMenuAnchor,
      bar: root.bar
    })
  }

  function syncNotificationPanelLoader() {
    notificationPanelLoader.source = ""
    if (!notificationPanelOpen || !notificationService
        || !String(notificationPanelSource)) return
    notificationPanelLoader.setSource(notificationPanelSource, {
      ownerWidget: root,
      notificationService: root.notificationService,
      anchorItem: notificationView,
      bar: root.bar
    })
  }

  function childOpened(item) {
    if (!item) return false
    return item.opened === true || item.popupOpen === true
      || item.managePopupOpen === true || item.trayMenuOpen === true
  }

  function open() {
    closeTrayDrawer()
    closeChild(updateWidget)
    closeChild(trayWidget)
    if (!notificationService || !String(notificationPanelSource)) return false
    notificationPanelOpen = true
    return true
  }

  function closeChild(item) {
    if (!item) return
    if (typeof item.close === "function") item.close()
    else {
      if ("opened" in item) item.opened = false
      if ("popupOpen" in item) item.popupOpen = false
      if ("managePopupOpen" in item) item.managePopupOpen = false
      if ("trayMenuOpen" in item) item.trayMenuOpen = false
    }
  }

  function closeTrayDrawer() {
    trayDrawerOpen = false
    closeTrayAppMenu()
    // The host tray menu is a separate popup owned by omarchy.tray. Closing
    // our drawer must close that popup too, otherwise Escape/outside-click
    // can leave the app menu visible without its owning drawer.
    closeChild(trayWidget)
  }

  function trayItemName(item) {
    if (!item) return "Tray App"
    const title = String(item.title || "").trim()
    if (title !== "") return title
    const tooltipTitle = String(item.tooltipTitle || "").trim()
    if (tooltipTitle !== "") return tooltipTitle
    return String(item.id || "Tray App")
  }

  function appMenuAnchorX(anchor) {
    const fallback = trayView.x + trayView.width / 2
    if (!anchor || typeof anchor.mapToItem !== "function"
        || typeof root.mapFromItem !== "function") return fallback
    try {
      const globalPoint = anchor.mapToItem(null,
        Number(anchor.width || 0) / 2, Number(anchor.height || 0) / 2)
      const localPoint = root.mapFromItem(null, globalPoint.x, globalPoint.y)
      return Number.isFinite(localPoint.x) ? localPoint.x : fallback
    } catch (error) {
      return fallback
    }
  }

  function openTrayAppMenu(item, anchor) {
    if (!item || !item.menu || !anchor || !String(trayAppMenuSource))
      return false
    closeChild(trayWidget)
    trayAppMenuItem = item
    trayAppMenuAnchorX = appMenuAnchorX(anchor)
    // The clicked button lives in the full-screen drawer window. Preserve its
    // X position, but anchor the child panel to the real bar window so panel
    // height and top/bottom placement are computed from the bar, as in V1.
    trayAppMenuAnchor = trayAppMenuBarAnchor
    // V1 popupOpened() makes the drawer and the DBus menu mutually exclusive.
    // Closing only after preserving the X coordinate avoids leaving the
    // full-screen drawer layer above the newly opened menu.
    trayDrawerOpen = false
    trayAppMenuOpen = true
    return true
  }

  function closeTrayAppMenu() {
    trayAppMenuOpen = false
    trayAppMenuItem = null
    trayAppMenuAnchor = null
    closeChild(trayWidget)
  }

  function closeNotificationPanel() {
    notificationPanelOpen = false
  }

  function toggleTrayDrawer() {
    if (!trayWidget || Number(trayWidget.drawerCount || 0) <= 0) return false
    if (trayDrawerOpen) {
      closeTrayDrawer()
      return true
    }
    return openTrayDrawer()
  }

  function openTrayDrawer() {
    if (!trayWidget || Number(trayWidget.drawerCount || 0) <= 0) return false
    closeChild(updateWidget)
    closeNotificationPanel()
    closeChild(trayWidget)
    trayDrawerOpen = true
    return true
  }

  function toggleNotificationDnd() {
    const service = notificationService
    if (!service || typeof service.setDoNotDisturb !== "function") return false
    service.setDoNotDisturb(service.doNotDisturb !== true)
    return true
  }

  function close() {
    closeTrayDrawer()
    closeTrayAppMenu()
    closeNotificationPanel()
    closeChild(updateWidget)
    closeChild(trayWidget)
  }

  function toggle() {
    if (notificationPanelOpen) {
      closeNotificationPanel()
      return true
    }
    return open()
  }

  function switchPanel(direction) {
    return bar && typeof bar.switchPanelFrom === "function"
      ? bar.switchPanelFrom(root, direction) : false
  }

  function childPanelWidget(pluginId) {
    const id = String(pluginId || "")
    if (id === "hancore.shibumi.update-center") return updateWidget
    return id === "omarchy.notifications" ? root : null
  }

  function ownsPanelWidget(owner) {
    return !!owner && (owner === root || owner === updateWidget
      || owner === notificationPanelItem
      || owner === trayWidget || owner === trayDrawerItem
      || owner === trayAppMenuPanelItem
      || (trayAppMenuPanelItem && owner === trayAppMenuPanelItem.owner))
  }

  function scheduleChildSync() {
    childSyncTimer.restart()
  }

  onBarChanged: {
    scheduleChildSync()
    if (trayDrawerOpen) syncTrayDrawerLoader()
    if (notificationPanelOpen) syncNotificationPanelLoader()
  }
  onSettingsChanged: injectChildren()
  onUpdateComponentChanged: scheduleChildSync()
  onUpdateSourceChanged: scheduleChildSync()
  onTrayComponentChanged: scheduleChildSync()
  onTraySourceChanged: scheduleChildSync()
  onTrayDrawerOpenChanged: syncTrayDrawerLoader()
  onTrayDrawerSourceChanged: syncTrayDrawerLoader()
  onTrayWidgetChanged: if (trayDrawerOpen) syncTrayDrawerLoader()
  onTrayAppMenuOpenChanged: syncTrayAppMenuLoader()
  onTrayAppMenuSourceChanged: syncTrayAppMenuLoader()
  onTrayAppMenuItemChanged: if (trayAppMenuOpen) syncTrayAppMenuLoader()
  onTrayAppMenuAnchorChanged: if (trayAppMenuOpen) syncTrayAppMenuLoader()
  onNotificationPanelOpenChanged: syncNotificationPanelLoader()
  onNotificationPanelSourceChanged: syncNotificationPanelLoader()
  onNotificationServiceChanged: if (notificationPanelOpen)
    syncNotificationPanelLoader()

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onLayoutConfigChanged() { root.injectChildren() }
  }

  onWidgetInkChanged: syncUpdateInk()
  onV1CustomToneActiveChanged: syncUpdateInk()
  onBadgeContrastColorChanged: syncUpdateInk()

  Component.onCompleted: {
    scheduleChildSync()
  }
  Component.onDestruction: {
    close()
    if (updateWidget && "bar" in updateWidget) updateWidget.bar = null
    if (trayWidget && "bar" in trayWidget) trayWidget.bar = null
  }

  QtObject {
    id: trayShellProxy

    readonly property var realShell: root.bar ? root.bar.shell : null

    function updateEntryInline(moduleId, values) {
      if (String(moduleId || "") === "omarchy.tray")
        return root.persistEmbeddedTraySettings(moduleId, values)
      return realShell && typeof realShell.updateEntryInline === "function"
        ? realShell.updateEntryInline(moduleId, values) : false
    }

    function serviceFor(pluginId) {
      return realShell && typeof realShell.serviceFor === "function"
        ? realShell.serviceFor(pluginId) : null
    }

    function firstPartyServiceFor(pluginId) {
      return realShell && typeof realShell.firstPartyServiceFor === "function"
        ? realShell.firstPartyServiceFor(pluginId) : null
    }
  }

  QtObject {
    id: hostProxy

    readonly property var realBar: root.bar
    readonly property bool vertical: realBar ? realBar.vertical === true : false
    readonly property int barSize: realBar ? Number(realBar.barSize) : 35
    readonly property int sizeHorizontal: realBar
      && realBar.sizeHorizontal !== undefined
      ? Number(realBar.sizeHorizontal) : barSize
    readonly property string position: realBar
      ? String(realBar.position || "top") : "top"
    readonly property string fontFamily: realBar
      ? String(realBar.fontFamily || "monospace") : "monospace"
    readonly property color foreground: root.widgetInk
    readonly property color barForeground: foreground
    readonly property color urgent: root.widgetInk
    readonly property color background: realBar
      ? realBar.background : "#111111"
    readonly property var visualTokens: root.tokens
    readonly property bool foregroundAnimationEnabled: realBar
      ? realBar.foregroundAnimationEnabled !== false : false
    readonly property var shell: trayShellProxy
    readonly property var layoutConfig: realBar ? realBar.layoutConfig : ({})
    readonly property var activePopout: realBar ? realBar.activePopout : null
    readonly property var clickTargets: realBar ? realBar.clickTargets : []

    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}

    function requestPopout(owner) {
      if (realBar && typeof realBar.requestPopout === "function")
        realBar.requestPopout(owner)
    }

    function releasePopout(owner) {
      if (realBar && typeof realBar.releasePopout === "function")
        realBar.releasePopout(owner)
    }

    function switchPanelFrom(_owner, direction) {
      return realBar && typeof realBar.switchPanelFrom === "function"
        ? realBar.switchPanelFrom(root, direction) : false
    }

    function targetBelongsToWindow(target, window) {
      return realBar && typeof realBar.targetBelongsToWindow === "function"
        ? realBar.targetBelongsToWindow(target, window) : false
    }
  }

  Timer {
    id: childSyncTimer
    interval: 0
    onTriggered: {
      root.syncUpdateLoader()
      root.syncTrayLoader()
      root.injectChildren()
    }
  }

  PillSurface {
    tokenSource: root.tokens
    settings: root.settings
    v1AppearanceEnabled: true
    anchors.fill: parent
    anchors.topMargin: root.tokens
      ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
    anchors.bottomMargin: root.tokens
      ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
    bar: root.bar
  }

  Row {
    id: statusRow
    anchors.centerIn: parent
    spacing: root.childGap
    z: 2

    Item {
      id: updateSlot
      anchors.verticalCenter: parent.verticalCenter
      visible: root.fullMode && updateLoader.item !== null
      implicitWidth: visible ? root.statusActionSlot : 0
      implicitHeight: updateLoader.implicitHeight
      width: implicitWidth
      height: implicitHeight
      z: 3

      Loader {
        id: updateLoader
        anchors.centerIn: parent
        onLoaded: root.injectUpdateChild(item)
      }
    }

    TrayStatusView {
      id: trayView
      visible: root.fullMode && presented
      bar: root.bar
      trayBackend: root.trayWidget
      customToneActive: root.v1CustomToneActive
      contentColor: root.v1CustomToneActive
        ? root.widgetInk : root.bar ? root.bar.foreground : root.widgetInk
      badgeContrastColor: root.badgeContrastColor
      z: 2
      onDrawerRequested: root.toggleTrayDrawer()
    }

    NotificationStatusView {
      id: notificationView
      visible: (root.fullMode || root.iconMode) && presented
      bar: root.bar
      contentColor: root.widgetInk
      customToneActive: root.v1CustomToneActive
      badgeContrastColor: root.badgeContrastColor
      slotWidth: root.statusActionSlot
      notificationService: root.notificationService
      z: 1
      onToggleRequested: root.toggle()
      onDndRequested: root.toggleNotificationDnd()
    }

    Item {
      id: textStatus

      visible: root.textMode && root.notificationService !== null
      implicitWidth: statusText.implicitWidth + Commons.Style.space(4)
      implicitHeight: root.bar ? root.bar.barSize : Commons.Style.space(35)
      width: visible ? implicitWidth : 0
      height: implicitHeight
      property bool registered: false

      function syncRegistration() {
        if (!root.bar) return
        if (visible && !registered) {
          root.bar.registerClickTarget(textStatus)
          registered = true
        } else if (!visible && registered) {
          root.bar.unregisterClickTarget(textStatus)
          registered = false
        }
      }

      onVisibleChanged: syncRegistration()
      Component.onCompleted: syncRegistration()
      Component.onDestruction: if (root.bar && registered)
        root.bar.unregisterClickTarget(textStatus)

      Text {
        id: statusText
        anchors.centerIn: parent
        text: root.textLabel
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens && root.tokens.labelSize !== undefined
          ? root.tokens.labelSize : Commons.Style.font.body
        font.weight: Font.Medium
        renderType: Text.NativeRendering
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root.bar) root.bar.showTooltip(textStatus,
          root.notificationCount > 0
            ? root.notificationCount + (root.notificationCount === 1
              ? " notification" : " notifications") : root.textLabel)
        onExited: if (root.bar) root.bar.hideTooltip(textStatus)
        onClicked: function(mouse) {
          if (root.bar) root.bar.hideTooltip(textStatus)
          if (mouse.button === Qt.RightButton) root.toggleNotificationDnd()
          else root.toggle()
        }
      }

      function triggerPress(button) {
        if (button === Qt.RightButton) return root.toggleNotificationDnd()
        return root.toggle()
      }
    }
  }

  Loader {
    id: trayLoader
    x: statusRow.x + trayView.x
    width: trayView.width
    height: root.height
    opacity: 0
    z: 0
    onLoaded: {
      root.injectChild(item, "omarchy.tray")
    }
  }

  Loader { id: trayDrawerLoader }
  Loader { id: trayAppMenuLoader }

  Item {
    id: trayAppMenuBarAnchor
    x: root.trayAppMenuAnchorX
    y: 0
    width: 0
    height: root.height
    visible: false
  }
  Loader { id: notificationPanelLoader }
}
