pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var bluetoothService
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool actionFocused: false
  property string selectedAddress: ""

  readonly property var rows: {
    const result = []
    const append = function(section, values) {
      const list = Array.isArray(values) ? values : []
      for (let i = 0; i < list.length; i++)
        if (list[i]) result.push({ section: section, device: list[i] })
    }
    append("connected", bluetoothService.connectedDevices)
    append("paired", bluetoothService.knownDevices)
    if (bluetoothService.discovering)
      append("available", bluetoothService.discoveredDevices)
    return result
  }

  owner: ownerWidget
  open: ownerWidget.opened && bluetoothService && bluetoothService.ready
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(380))
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    Commons.Style.space(620))

  function sectionLabel(section) {
    if (section === "connected") return "CONNECTED"
    if (section === "paired") return "PAIRED"
    return "AVAILABLE"
  }

  function sectionStarts(index) {
    const current = rowAt(index)
    if (!current) return false
    const previous = rowAt(index - 1)
    return !previous || previous.section !== current.section
  }

  function rowAt(index) {
    return index >= 0 && index < rows.length ? rows[index] : null
  }

  function deviceAddress(device) {
    return device ? String(device.address || "") : ""
  }

  function canForget(row) {
    return row && (row.section === "connected" || row.section === "paired")
  }

  function primaryAction(row) {
    if (!row || !row.device) return false
    return row.device.connected
      ? bluetoothService.disconnectDevice(row.device)
      : bluetoothService.connectDevice(row.device)
  }

  function forget(row) {
    return canForget(row) && bluetoothService.forgetDevice(row.device)
  }

  function batteryStatusText(device) {
    if (!device || !device.batteryAvailable) return ""
    const icon = String(device.icon || "").toLowerCase()
    // BlueZ may expose coarse or stale phone charge without provenance, and
    // Quickshell does not expose Battery1.Source or an update timestamp.
    if (icon === "phone" || icon === "smartphone") return ""
    const battery = Number(device.battery)
    if (!Number.isFinite(battery) || battery < 0 || battery > 1) return ""
    return Math.round(battery * 100) + "%"
  }

  function statusText(row) {
    if (!row || !row.device) return ""
    void(bluetoothService.pendingActions)
    const device = row.device
    const pending = bluetoothService.pendingAction(deviceAddress(device))
    if (pending === "forgetting") return "Forgetting..."
    if (pending === "disconnecting" || Number(device.state) === 2)
      return "Disconnecting..."
    if (pending === "connecting" || Number(device.state) === 3
        || device.pairing === true) return "Connecting..."
    if (device.connected) {
      const batteryText = batteryStatusText(device)
      if (batteryText !== "") return "Connected · " + batteryText
      return "Connected"
    }
    return row.section === "paired" ? "Paired" : "Available"
  }

  function resetCursor() {
    selectedIndex = 0
    selectedAddress = rows.length > 0 ? deviceAddress(rows[0].device) : ""
    cursorActive = false
    actionFocused = false
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + delta))
    selectedAddress = deviceAddress(rows[selectedIndex].device)
    actionFocused = false
    ensureVisibleForIndex(selectedIndex)
  }

  function moveCursorHorizontal(delta) {
    const row = rowAt(selectedIndex)
    if (!canForget(row)) return
    actionFocused = delta > 0
  }

  function activateCursor() {
    const row = rowAt(selectedIndex)
    if (!row) return
    if (actionFocused) forget(row)
    else primaryAction(row)
  }

  function reselectAddress() {
    if (rows.length === 0) {
      selectedIndex = 0
      selectedAddress = ""
      actionFocused = false
      return
    }
    for (let i = 0; i < rows.length; i++) {
      if (deviceAddress(rows[i].device) === selectedAddress) {
        selectedIndex = i
        if (!canForget(rows[i])) actionFocused = false
        return
      }
    }
    selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex))
    selectedAddress = deviceAddress(rows[selectedIndex].device)
    actionFocused = false
  }

  function ensureVisibleForIndex(index) {
    if (!deviceRepeater || index < 0 || index >= deviceRepeater.count) return
    const item = deviceRepeater.itemAt(index)
    if (!item || !deviceFlick) return
    const point = item.mapToItem(deviceFlick.contentItem, 0, 0)
    const top = point.y
    const bottom = top + item.height
    if (top < deviceFlick.contentY)
      deviceFlick.contentY = Math.max(0, top - Commons.Style.space(4))
    else if (bottom > deviceFlick.contentY + deviceFlick.height)
      deviceFlick.contentY = Math.max(0,
        bottom - deviceFlick.height + Commons.Style.space(4))
  }

  function heroStatus() {
    if (!bluetoothService.adapterAvailable) return "NO ADAPTER"
    if (!bluetoothService.radioEnabled) return "TURNED OFF"
    if (bluetoothService.discovering) return "SCANNING FOR DEVICES"
    if (bluetoothService.connectedCount > 0)
      return bluetoothService.connectedCount + " CONNECTED"
    return "READY"
  }

  onOpenChanged: if (open) resetCursor()
  onRowsChanged: reselectAddress()

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }
    onMoveRequested: function(dx, dy) {
      if (!panel.cursorActive) {
        panel.cursorActive = true
        return
      }
      if (dy !== 0) panel.moveCursor(dy)
      else if (dx !== 0) panel.moveCursorHorizontal(dx)
    }
    onActivateRequested: if (panel.cursorActive) panel.activateCursor()
    onDeleteRequested: if (panel.cursorActive)
      panel.forget(panel.rowAt(panel.selectedIndex))

    Column {
      id: contentColumn
      width: parent.width
      spacing: Commons.Style.space(10)

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)

        Text {
          width: parent.width - headerActions.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: "Bluetooth"
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.heading
          font.letterSpacing: 2
          font.weight: Font.Medium
          renderType: Text.NativeRendering
        }

        Row {
          id: headerActions
          spacing: Commons.Style.space(4)

          IconAction {
            icon: panel.bluetoothService.discovering ? "sync" : "refresh"
            tooltip: "Scan for devices"
            enabled: panel.bluetoothService.radioEnabled
            onClicked: panel.bluetoothService.restartDiscovery()
          }

          IconAction {
            icon: "close"
            tooltip: "Close"
            onClicked: panel.ownerWidget.close()
          }
        }
      }

      Ui.PanelSeparator { width: parent.width }

      Row {
        width: parent.width
        spacing: Commons.Style.space(10)

        IconText {
          anchors.verticalCenter: parent.verticalCenter
          text: !panel.bluetoothService.radioEnabled ? "\uE1A9"
            : panel.bluetoothService.connectedCount > 0
              ? "\uE1A8" : "\uE1A7"
          color: panel.bar ? panel.bar.urgent : Commons.Color.accent
          opacity: panel.bluetoothService.radioEnabled ? 1 : 0.45
          font.pixelSize: Commons.Style.font.display
          fill: 1
        }

        Column {
          width: parent.width - x - heroPowerToggle.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(2)

          Text {
            width: parent.width
            text: "Bluetooth"
            color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.title
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            text: panel.heroStatus()
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.56)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            font.letterSpacing: 1.1
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }
        }

        PowerToggle {
          id: heroPowerToggle
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Ui.PanelSeparator { width: parent.width }

      Text {
        width: parent.width
        visible: !panel.bluetoothService.radioEnabled
        text: "Bluetooth is off"
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
          panel.bar.foreground.g, panel.bar.foreground.b, 0.48)
          : Commons.Color.foreground
        font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
      }

      Flickable {
        id: deviceFlick
        width: parent.width
        height: panel.bluetoothService.radioEnabled
          ? Math.min(deviceColumn.implicitHeight, Commons.Style.space(400)) : 0
        visible: panel.bluetoothService.radioEnabled
        contentWidth: width
        contentHeight: deviceColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: deviceColumn
          width: deviceFlick.width
          spacing: Commons.Style.space(6)

          Repeater {
            id: deviceRepeater
            model: panel.rows

            DeviceEntry {
              required property var modelData
              required property int index
              width: deviceColumn.width
              entry: modelData
              rowIndex: index
              sectionStart: panel.sectionStarts(index)
            }
          }

          Text {
            width: parent.width
            visible: panel.rows.length === 0
            text: panel.bluetoothService.discovering
              ? "Scanning for devices..." : "No Bluetooth devices found"
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.48)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
          }
        }
      }

    }
  }

  component SectionLabel: Text {
    color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
      panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
      : Commons.Color.foreground
    font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    font.letterSpacing: 1.2
    font.weight: Font.Medium
    renderType: Text.NativeRendering
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent
    opacity: enabled ? 1 : 0.35

    IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      enabled: action.enabled
      hoverEnabled: true
      cursorShape: action.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }

  component PowerToggle: Item {
    id: powerToggle
    implicitWidth: Commons.Style.space(46)
    implicitHeight: Commons.Style.space(28)

    Rectangle {
      anchors.centerIn: parent
      width: Commons.Style.space(42)
      height: Commons.Style.space(20)
      radius: height / 2
      color: panel.bluetoothService.radioEnabled && panel.bar
        ? Qt.rgba(panel.bar.urgent.r, panel.bar.urgent.g,
          panel.bar.urgent.b, 0.18)
        : panel.controlFillColor
      border.width: panel.controlBorderWidth
      border.color: panel.bluetoothService.radioEnabled && panel.bar
        ? panel.bar.urgent : panel.controlBorderColor

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: panel.bluetoothService.radioEnabled
          ? parent.width - width - Commons.Style.space(3) : Commons.Style.space(3)
        width: Commons.Style.space(14)
        height: width
        radius: width / 2
        color: panel.bluetoothService.radioEnabled && panel.bar
          ? panel.bar.urgent : panel.bar ? Qt.rgba(panel.bar.foreground.r,
            panel.bar.foreground.g, panel.bar.foreground.b, 0.55)
            : Commons.Color.foreground
        Behavior on x {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }

    MouseArea {
      id: powerMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: panel.bluetoothService.toggleBluetooth()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: powerMouse.containsMouse
      text: panel.bluetoothService.radioEnabled
        ? "Turn Bluetooth off" : "Turn Bluetooth on"
    }
  }

  component DeviceEntry: Column {
    id: entryItem
    required property var entry
    required property int rowIndex
    required property bool sectionStart
    readonly property var device: entry ? entry.device : null
    readonly property bool connected: device && device.connected === true
    readonly property bool forgettable: panel.canForget(entry)
    readonly property bool selected: panel.cursorActive
      && panel.selectedIndex === rowIndex
    spacing: Commons.Style.space(4)

    SectionLabel {
      visible: entryItem.sectionStart
      width: parent.width
      text: panel.sectionLabel(entryItem.entry.section)
    }

    Ui.CursorSurface {
      id: deviceSurface
      width: parent.width
      implicitHeight: Commons.Style.space(42)
      radius: panel.controlRadius
      bordered: true
      current: entryItem.connected
      hasCursor: entryItem.selected && !panel.actionFocused
      foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
      accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Commons.Style.space(8)
        anchors.rightMargin: Commons.Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Commons.Style.space(8)

        IconText {
          anchors.verticalCenter: parent.verticalCenter
          text: entryItem.connected ? "\uE1A8" : "\uE1A7"
          color: entryItem.connected && panel.bar
            ? panel.bar.urgent : deviceSurface.foreground
          font.pixelSize: Commons.Style.font.heading
          fill: 1
        }

        Column {
          width: parent.width - x - forgetAction.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Text {
            width: parent.width
            text: panel.bluetoothService.deviceLabel(entryItem.device) || "Device"
            color: deviceSurface.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            font.weight: entryItem.connected ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            text: panel.statusText(entryItem.entry)
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.56)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }
        }

        IconAction {
          id: forgetAction
          visible: entryItem.forgettable
            && (deviceMouse.containsMouse || entryItem.selected)
          icon: "delete"
          tooltip: "Forget device"
          onClicked: panel.forget(entryItem.entry)
        }
      }

      MouseArea {
        id: deviceMouse
        anchors.fill: parent
        anchors.rightMargin: forgetAction.visible ? forgetAction.width : 0
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) {
          panel.cursorActive = true
          panel.selectedIndex = entryItem.rowIndex
          panel.selectedAddress = panel.deviceAddress(entryItem.device)
          panel.actionFocused = false
        }
        onClicked: panel.primaryAction(entryItem.entry)
      }
    }
  }
}
