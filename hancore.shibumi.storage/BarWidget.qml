pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.storage"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var storageService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.storage") : null
  readonly property var storage: storageService
    ? storageService.storage : null
  readonly property var stateService: hostShell
    && typeof hostShell.serviceFor === "function"
      ? hostShell.serviceFor("hancore.shibumi.state") : null
  property string hostGroupId: ""
  readonly property string stateGroupId: hostGroupId !== "" ? hostGroupId : "G18"
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  readonly property bool valueVisible: displayMode !== "icon"
  readonly property int iconSlotSize: 14
  // The Nerd Font storage glyph overhangs its advance box on the right.
  readonly property int compactIconOpticalOffset: compact
    && tokens.v2Shell !== true
    ? -Math.max(1, Math.round(Number(tokens.iconSize) / 18)) : 0
  readonly property string configuredSource: String(setting("source", "root"))
  readonly property var selectedDrive: driveForSource(configuredSource)
  readonly property string selectedSource:
    configuredSource === "root" || selectedDrive ? configuredSource : "root"
  readonly property int selectedPercent: selectedSource === "root"
    ? (storage ? storage.percent : 0)
    : selectedDrive ? selectedDrive.percent : 0
  readonly property string selectedLabel: selectedSource === "root"
    ? "Root filesystem"
    : selectedDrive ? String(selectedDrive.model || selectedDrive.name) : "Storage"
  property var acquiredStorage: null

  implicitWidth: bar && bar.vertical ? bar.barSize : surface.implicitWidth
  implicitHeight: bar && bar.vertical ? surface.implicitHeight
    : bar ? bar.barSize : 28
  visible: root.storage && root.storage.available

  function syncStorageOwner() {
    if (acquiredStorage === storage) return
    if (acquiredStorage) acquiredStorage.release()
    acquiredStorage = storage
    if (acquiredStorage) acquiredStorage.acquire()
  }

  function driveForSource(source) {
    const target = String(source || "")
    const rows = storage && Array.isArray(storage.drives)
      ? storage.drives : []
    for (let index = 0; index < rows.length; index++) {
      if (String(rows[index].path || "") === target
          && Number(rows[index].percent) >= 0) return rows[index]
    }
    return null
  }

  function storageSourceAvailable(source) {
    const target = String(source || "")
    return target === "root" ? !!(storage && storage.available)
      : driveForSource(target) !== null
  }

  function setStorageSource(source) {
    const target = String(source || "")
    if (!storageSourceAvailable(target)) return false
    return stateService && typeof stateService.setGroupSetting === "function"
      ? stateService.setGroupSetting(stateGroupId, "source", target) : false
  }

  function syncPanelLoader() {
    if (!opened) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(Qt.resolvedUrl("StoragePanel.qml"), {
      anchorItem: surface,
      bar: root.bar,
      ownerWidget: root,
      storage: root.storage
    })
  }

  onStorageChanged: syncStorageOwner()
  onOpenedChanged: syncPanelLoader()
  Component.onCompleted: syncStorageOwner()
  Component.onDestruction: if (acquiredStorage) acquiredStorage.release()

  Item {
    id: surface
    anchors.centerIn: parent
    implicitWidth: content.visibleContentWidth
      + 2 * root.tokens.pillPaddingX
    implicitHeight: root.tokens ? root.tokens.slotHeight : 28
    width: implicitWidth
    height: implicitHeight

    PillSurface {
      tokenSource: root.tokens
      bar: root.bar
      settings: root.settings
      v1AppearanceEnabled: true
      anchors.fill: parent
      anchors.topMargin: Math.round(
        (parent.height - root.tokens.pillHeight) / 2)
      anchors.bottomMargin: Math.round(
        (parent.height - root.tokens.pillHeight) / 2)
    }

    Row {
      id: content
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.compactIconOpticalOffset
      readonly property real visibleContentWidth:
        (storageIconSlot.visible ? storageIconSlot.width : 0)
        + (storageValue.visible ? storageValue.implicitWidth : 0)
        + spacing
      width: visibleContentWidth
      spacing: storageIconSlot.visible && storageValue.visible
        ? root.tokens.compactGap : 0

      Item {
        id: storageIconSlot
        visible: root.displayMode !== "text"
        width: visible ? root.iconSlotSize : 0
        height: root.iconSlotSize
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: storageIcon
          anchors.centerIn: parent
          text: "󰋊"
          color: root.widgetInk
          font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: root.tokens.iconSize
          horizontalAlignment: Text.AlignHCenter
          renderType: Text.NativeRendering
        }
      }

      Text {
        id: storageValue
        visible: root.valueVisible
        width: visible ? implicitWidth : 0
        anchors.verticalCenter: parent.verticalCenter
        text: String(Math.min(100, root.selectedPercent)).padStart(2, "0") + "%"
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar && root.storage)
        root.bar.showTooltip(surface,
          root.selectedLabel + " · " + root.selectedPercent + "%")
      onExited: if (root.bar) root.bar.hideTooltip(surface)
      onClicked: root.toggle()
    }
  }

  Loader { id: panelLoader }
}
