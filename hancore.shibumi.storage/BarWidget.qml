pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.storage"
  manageIpc: false

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var storageService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.storage") : null
  readonly property var storage: storageService
    ? storageService.storage : null
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
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
    implicitWidth: content.implicitWidth + 2 * root.tokens.pillPaddingX
    implicitHeight: root.tokens ? root.tokens.slotHeight : 28
    width: implicitWidth
    height: implicitHeight

    PillSurface {
      bar: root.bar
      settings: root.settings
      anchors.fill: parent
      anchors.topMargin: Math.round(
        (parent.height - root.tokens.pillHeight) / 2)
      anchors.bottomMargin: Math.round(
        (parent.height - root.tokens.pillHeight) / 2)
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: root.tokens.compactGap

      Text {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        text: "󰋊"
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.iconSize
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
      }

      Text {
        visible: root.displayMode !== "icon"
        anchors.verticalCenter: parent.verticalCenter
        text: String(Math.min(100,
          root.storage ? root.storage.percent : 0)).padStart(2, "0") + "%"
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
          root.storage.usedGiB.toFixed(1) + " / "
          + root.storage.totalGiB.toFixed(1) + " GiB")
      onExited: if (root.bar) root.bar.hideTooltip(surface)
      onClicked: root.toggle()
    }
  }

  Loader { id: panelLoader }
}
