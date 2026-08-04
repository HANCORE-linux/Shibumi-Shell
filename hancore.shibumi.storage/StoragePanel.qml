pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var storage
  readonly property color unmountedAccent: ownerWidget
    && ownerWidget.stateService
    && typeof ownerWidget.stateService.paletteColor === "function"
    ? ownerWidget.stateService.paletteColor("color04") : panel.controlAccent
  readonly property int driveGroupSpacing: Commons.Style.space(6)
  property string activeView: "drives"
  property string detailSource: String(ownerWidget.selectedSource || "root")
  readonly property var detailDrive: driveForSource(detailSource)
  readonly property var selectedDrive: driveForSource(ownerWidget.selectedSource)
  readonly property string barTabLabel: "BAR · " + (selectedDrive
    ? String(selectedDrive.name || "DRIVE").toUpperCase() : "ROOT")

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(390))
  contentHeight: fittedContentHeight(content.childrenRect.height)

  function capacity(bytes) {
    const value = Math.max(0, Number(bytes) || 0)
    if (value >= 1000000000000)
      return (value / 1000000000000).toFixed(value >= 10000000000000 ? 0 : 1)
        + " TB"
    if (value >= 1000000000)
      return (value / 1000000000).toFixed(value >= 100000000000 ? 0 : 1)
        + " GB"
    return (value / 1000000).toFixed(0) + " MB"
  }

  function dataSize(bytes) {
    const value = Math.max(0, Number(bytes) || 0)
    if (value >= 1099511627776)
      return (value / 1099511627776).toFixed(1) + " TiB"
    return (value / 1073741824).toFixed(1) + " GiB"
  }

  function freeSummary(usedPercent, freeBytes, totalBytes) {
    const usage = Math.max(0, Math.min(100,
      Math.round(Number(usedPercent) || 0)))
    const free = Math.max(0, Number(freeBytes) || 0)
    const total = Math.max(0, Number(totalBytes) || 0)
    const divisor = total >= 1099511627776 ? 1099511627776 : 1073741824
    const unit = divisor === 1099511627776 ? "TiB" : "GiB"
    return (100 - usage) + "% FREE · "
      + (free / divisor).toFixed(1) + "/"
      + (total / divisor).toFixed(1) + " " + unit
  }

  function driveIcon(driveType) {
    if (driveType === "usb") return ""
    if (driveType === "nvme") return "󰢮"
    if (driveType === "ssd") return "󰭳"
    return "󰋊"
  }

  function driveForSource(source) {
    const target = String(source || "")
    const rows = storage && Array.isArray(storage.drives)
      ? storage.drives : []
    for (let index = 0; index < rows.length; index++) {
      if (String(rows[index].path || "") === target) return rows[index]
    }
    return null
  }

  function selectSource(source) {
    const target = String(source || "")
    detailSource = target
    return ownerWidget.setStorageSource(target)
  }

  function showInfo(source) {
    const target = String(source || ownerWidget.selectedSource || "root")
    detailSource = target === "root" || driveForSource(target) ? target : "root"
    activeView = "info"
  }

  function detailRows() {
    const drive = detailDrive
    if (!drive) return [
      { label: "DEVICE", value: storage && storage.rootDevice !== ""
          ? storage.rootDevice : "/" },
      { label: "TYPE", value: "ROOT FILESYSTEM" },
      { label: "MOUNT", value: "/" },
      { label: "CAPACITY", value: dataSize(storage ? storage.totalBytes : 0) },
      { label: "USED", value: dataSize(storage ? storage.usedBytes : 0) },
      { label: "FREE", value: dataSize(storage ? storage.freeBytes : 0) },
      { label: "USAGE", value: (storage ? storage.percent : 0) + "%" }
    ]
    return [
      { label: "DEVICE", value: String(drive.path || "—") },
      { label: "TYPE", value: String(drive.media || "—") },
      { label: "TRANSPORT", value: String(drive.transport || "—").toUpperCase() },
      { label: "CAPACITY", value: capacity(drive.sizeBytes) },
      { label: "FILESYSTEM", value: String(drive.fileSystems || "—") },
      { label: "MOUNT", value: String(drive.mountSummary || "—") },
      { label: "REMOVABLE", value: drive.removable ? "YES" : "NO" }
    ]
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) {
      panel.ownerWidget.switchPanel(direction)
    }

    Column {
      id: content
      width: parent.width
      spacing: Commons.Style.space(10)

      Row {
        id: viewTabs
        width: parent.width
        spacing: Commons.Style.space(6)

        ChoiceButton {
          width: (viewTabs.width - viewTabs.spacing) / 2
          label: panel.barTabLabel
          selected: panel.activeView === "drives"
          onClicked: panel.activeView = "drives"
        }

        ChoiceButton {
          width: (viewTabs.width - viewTabs.spacing) / 2
          label: "LSBLK INFO"
          selected: panel.activeView === "info"
          onClicked: panel.showInfo(panel.detailSource)
        }
      }

      Column {
        id: drivesView
        visible: panel.activeView === "drives"
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: panel.driveGroupSpacing

      Rectangle {
        width: parent.width
        height: 1
        color: panel.shibumiTokens.separator
      }

      Rectangle {
        id: rootChoice
        readonly property bool selected:
          panel.ownerWidget.selectedSource === "root"
        readonly property bool hovered: rootChoicePointer.containsMouse
        width: parent.width
        implicitHeight: Math.max(rootChoiceIcon.implicitHeight,
          rootChoiceName.implicitHeight, rootChoiceMetrics.implicitHeight)
          + Commons.Style.space(8)
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: "Show root filesystem in the storage bar"
        radius: panel.controlRadius
        color: selected ? panel.controlActiveFillColor
          : hovered ? panel.controlHoverFillColor : panel.controlFillColor
        border.width: panel.controlBorderWidth
        border.color: selected || activeFocus ? panel.controlAccent
          : hovered ? panel.controlHoverBorderColor : panel.controlBorderColor

        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
          id: rootChoicePointer
          anchors.fill: parent
          hoverEnabled: true
          enabled: panel.storage && panel.storage.available
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: panel.selectSource("root")
        }

        Row {
          id: rootChoiceContent
          anchors.fill: parent
          anchors.margins: Commons.Style.space(4)
          spacing: Commons.Style.space(8)

          Text {
            id: rootChoiceIcon
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(20)
            text: "󰋊"
            color: panel.bar.urgent
            horizontalAlignment: Text.AlignHCenter
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.iconLarge
          }

          Text {
            id: rootChoiceName
            anchors.verticalCenter: parent.verticalCenter
            width: rootChoiceContent.width - rootChoiceIcon.width
              - rootChoiceMetrics.width - rootChoiceInfo.width
              - 3 * rootChoiceContent.spacing
            text: "Root filesystem"
            color: rootChoice.selected
              ? panel.controlAccent : panel.bar.foreground
            elide: Text.ElideRight
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.body
          }

          Column {
            id: rootChoiceMetrics
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(rootChoiceCapacity.implicitWidth,
              rootChoicePercent.implicitWidth)
            spacing: Commons.Style.space(1)

            Text {
              id: rootChoiceCapacity
              width: parent.width
              text: panel.dataSize(panel.storage ? panel.storage.totalBytes : 0)
              color: rootChoice.selected
                ? panel.controlAccent : panel.bar.foreground
              horizontalAlignment: Text.AlignRight
              font.family: panel.bar.fontFamily
              font.pixelSize: Commons.Style.font.body
              font.weight: Font.Medium
            }

            Text {
              id: rootChoicePercent
              width: parent.width
              text: panel.freeSummary(
                panel.storage ? panel.storage.percent : 0,
                panel.storage ? panel.storage.freeBytes : 0,
                panel.storage ? panel.storage.totalBytes : 0)
              color: panel.controlMutedHigh
              horizontalAlignment: Text.AlignRight
              font.family: panel.bar.fontFamily
              font.pixelSize: Commons.Style.font.caption
            }
          }

          InfoAction {
            id: rootChoiceInfo
            anchors.verticalCenter: parent.verticalCenter
            onClicked: panel.showInfo("root")
          }
        }

        Keys.onReturnPressed: if (rootChoicePointer.enabled)
          panel.selectSource("root")
        Keys.onEnterPressed: if (rootChoicePointer.enabled)
          panel.selectSource("root")
        Keys.onSpacePressed: if (rootChoicePointer.enabled)
          panel.selectSource("root")
      }

      Text {
        width: parent.width
        visible: panel.storage && panel.storage.inventoryLoading
        text: "Scanning drives …"
        color: panel.controlMutedHigh
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.body
      }

      Text {
        width: parent.width
        visible: panel.storage && !panel.storage.inventoryLoading
          && panel.storage.inventoryError !== ""
          && panel.storage.drives.length === 0
        text: panel.storage ? panel.storage.inventoryError : ""
        color: panel.bar.urgent
        wrapMode: Text.Wrap
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.body
      }

      Text {
        width: parent.width
        visible: panel.storage && panel.storage.inventoryAvailable
          && panel.storage.drives.length === 0
        text: "No physical drives found"
        color: panel.controlMutedHigh
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.body
      }

      Repeater {
        model: panel.storage ? panel.storage.drives : []

        delegate: Column {
          id: driveRow
          required property int index
          required property var modelData
          readonly property bool selected:
            panel.ownerWidget.selectedSource === String(modelData.path || "")
          readonly property bool selectable: modelData.percent >= 0
          readonly property bool hovered: drivePointer.containsMouse
          width: parent.width
          spacing: panel.driveGroupSpacing

          Rectangle {
            id: driveHeader
            width: parent.width
            implicitHeight: Math.max(driveIcon.implicitHeight,
              driveName.implicitHeight, driveMetrics.implicitHeight)
              + Commons.Style.space(8)
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Show "
              + String(driveRow.modelData.model || driveRow.modelData.name)
              + " in the storage bar"
            radius: panel.controlRadius
            color: driveRow.selected ? panel.controlActiveFillColor
              : driveRow.hovered
                ? panel.controlHoverFillColor : panel.controlFillColor
            border.width: panel.controlBorderWidth
            border.color: driveRow.selected || activeFocus
              ? panel.controlAccent : driveRow.hovered
                ? panel.controlHoverBorderColor : panel.controlBorderColor

            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
              id: drivePointer
              anchors.fill: parent
              hoverEnabled: true
              enabled: driveRow.selectable
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: panel.selectSource(
                String(driveRow.modelData.path || ""))
            }

            Row {
              id: driveHeaderContent
              anchors.fill: parent
              anchors.margins: Commons.Style.space(4)
              spacing: Commons.Style.space(8)

              Text {
                id: driveIcon
                anchors.verticalCenter: parent.verticalCenter
                width: Commons.Style.space(20)
                text: panel.driveIcon(driveRow.modelData.driveType)
                color: panel.bar.urgent
                horizontalAlignment: Text.AlignHCenter
                font.family: panel.bar.fontFamily
                font.pixelSize: Commons.Style.font.iconLarge
              }

              Text {
                id: driveName
                anchors.verticalCenter: parent.verticalCenter
                width: driveHeaderContent.width - driveIcon.width
                  - driveMetrics.width - driveInfo.width
                  - 3 * driveHeaderContent.spacing
                text: driveRow.modelData.model || driveRow.modelData.name
                color: driveRow.modelData.mountedVolumes === 0
                  ? panel.unmountedAccent : driveRow.selected
                    ? panel.controlAccent : panel.bar.foreground
                elide: Text.ElideRight
                font.family: panel.bar.fontFamily
                font.pixelSize: Commons.Style.font.body
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              Column {
                id: driveMetrics
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(driveCapacity.implicitWidth,
                  drivePercent.implicitWidth)
                spacing: Commons.Style.space(1)

                Text {
                  id: driveCapacity
                  width: parent.width
                  text: panel.capacity(driveRow.modelData.sizeBytes)
                  color: driveRow.modelData.mountedVolumes === 0
                    ? panel.unmountedAccent : driveRow.selected
                      ? panel.controlAccent : panel.bar.foreground
                  horizontalAlignment: Text.AlignRight
                  font.family: panel.bar.fontFamily
                  font.pixelSize: Commons.Style.font.body
                  font.weight: Font.Medium
                  Behavior on color { ColorAnimation { duration: 120 } }
                }

                Text {
                  id: drivePercent
                  width: parent.width
                  text: driveRow.modelData.percent >= 0
                    ? panel.freeSummary(driveRow.modelData.percent,
                      driveRow.modelData.freeBytes,
                      driveRow.modelData.totalBytes)
                    : "NOT MOUNTED"
                  color: driveRow.modelData.percent >= 0
                    ? panel.controlMutedHigh : panel.unmountedAccent
                  horizontalAlignment: Text.AlignRight
                  font.family: panel.bar.fontFamily
                  font.pixelSize: Commons.Style.font.caption
                }
              }

              InfoAction {
                id: driveInfo
                anchors.verticalCenter: parent.verticalCenter
                onClicked: panel.showInfo(
                  String(driveRow.modelData.path || ""))
              }
            }

            Keys.onReturnPressed: if (driveRow.selectable)
              panel.selectSource(String(driveRow.modelData.path || ""))
            Keys.onEnterPressed: if (driveRow.selectable)
              panel.selectSource(String(driveRow.modelData.path || ""))
            Keys.onSpacePressed: if (driveRow.selectable)
              panel.selectSource(String(driveRow.modelData.path || ""))
          }

          Rectangle {
            visible: driveRow.index < (panel.storage
              ? panel.storage.drives.length - 1 : 0)
            width: parent.width
            height: 1
            color: panel.shibumiTokens.separator
          }
        }
      }
      }

      Column {
        id: infoView
        visible: panel.activeView === "info"
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: Commons.Style.space(8)

        Row {
          width: parent.width
          spacing: Commons.Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(24)
            text: panel.detailDrive
              ? panel.driveIcon(panel.detailDrive.driveType) : "󰋊"
            color: panel.bar.urgent
            horizontalAlignment: Text.AlignHCenter
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.iconLarge
          }

          Column {
            width: parent.width - x
            spacing: Commons.Style.space(1)

            Text {
              width: parent.width
              text: panel.detailDrive
                ? String(panel.detailDrive.model || panel.detailDrive.name)
                : "Root filesystem"
              color: panel.bar.foreground
              elide: Text.ElideRight
              font.family: panel.bar.fontFamily
              font.pixelSize: Commons.Style.font.heading
              font.weight: Font.Medium
            }

            Text {
              width: parent.width
              text: panel.detailDrive
                ? String(panel.detailDrive.path || "")
                : panel.storage ? String(panel.storage.rootDevice || "/") : "/"
              color: panel.controlMutedHigh
              elide: Text.ElideMiddle
              font.family: panel.bar.fontFamily
              font.pixelSize: Commons.Style.font.caption
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: panel.shibumiTokens.separator
        }

        Repeater {
          model: panel.detailRows()

          delegate: DetailRow {
            required property var modelData
            width: infoView.width
            label: String(modelData.label || "")
            value: String(modelData.value || "—")
          }
        }

        Row {
          visible: panel.detailDrive
            && Array.isArray(panel.detailDrive.volumes)
            && panel.detailDrive.volumes.length > 0
          width: parent.width

          Text {
            width: parent.width - volumeCount.width
            text: "VOLUMES"
            color: panel.controlAccent
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: 0.5
          }

          Text {
            id: volumeCount
            text: panel.detailDrive
              && Array.isArray(panel.detailDrive.volumes)
              ? String(panel.detailDrive.volumes.length) : "0"
            color: panel.controlAccent
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.caption
            font.weight: Font.DemiBold
          }
        }

        Repeater {
          model: panel.detailDrive && Array.isArray(panel.detailDrive.volumes)
            ? panel.detailDrive.volumes : []

          delegate: Column {
            id: volumeInfo
            required property var modelData
            width: infoView.width
            spacing: Commons.Style.space(2)

            Row {
              width: parent.width

              Text {
                width: parent.width - volumeCapacity.width
                text: String(volumeInfo.modelData.path || "")
                color: panel.bar.foreground
                elide: Text.ElideMiddle
                font.family: panel.bar.fontFamily
                font.pixelSize: Commons.Style.font.body
              }

              Text {
                id: volumeCapacity
                text: panel.capacity(volumeInfo.modelData.sizeBytes)
                color: panel.bar.foreground
                font.family: panel.bar.fontFamily
                font.pixelSize: Commons.Style.font.body
                font.weight: Font.Medium
              }
            }

            Text {
              width: parent.width
              text: String(volumeInfo.modelData.fileSystem || "No filesystem")
                + " · " + (volumeInfo.modelData.mounted
                  ? String(volumeInfo.modelData.mountPoint || "Mounted")
                  : "Not mounted")
              color: panel.controlMutedHigh
              elide: Text.ElideMiddle
              font.family: panel.bar.fontFamily
              font.pixelSize: Commons.Style.font.caption
            }
          }
        }
      }
    }
  }

  component ChoiceButton: Rectangle {
    id: choice
    required property string label
    property bool selected: false
    signal clicked()

    implicitHeight: Commons.Style.space(25)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    radius: panel.controlRadius
    color: selected ? panel.controlActiveFillColor
      : choicePointer.containsMouse
        ? panel.controlHoverFillColor : panel.controlFillColor
    border.width: panel.controlBorderWidth
    border.color: selected || activeFocus ? panel.controlAccent
      : choicePointer.containsMouse ? panel.controlHoverBorderColor
        : panel.controlBorderColor

    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(6)
      anchors.rightMargin: Commons.Style.space(6)
      text: choice.label
      color: choice.selected ? panel.controlAccent : panel.bar.foreground
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      font.family: panel.bar.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.weight: choice.selected ? Font.DemiBold : Font.Normal
      font.letterSpacing: 0.35
    }

    MouseArea {
      id: choicePointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: choice.clicked()
    }

    Keys.onReturnPressed: choice.clicked()
    Keys.onEnterPressed: choice.clicked()
    Keys.onSpacePressed: choice.clicked()
  }

  component InfoAction: Ui.CursorSurface {
    id: infoAction
    signal clicked()

    z: 3
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    activeFocusOnTab: true
    radius: panel.controlRadius
    foreground: panel.bar.foreground
    accent: panel.controlAccent
    Accessible.role: Accessible.Button
    Accessible.name: "LSBLK INFO"

    Rectangle {
      anchors.fill: parent
      radius: infoAction.radius
      color: infoPointer.containsMouse || infoAction.activeFocus
        ? panel.controlHoverFillColor : "transparent"
      border.width: infoAction.activeFocus ? panel.controlBorderWidth : 0
      border.color: panel.controlAccent

      Behavior on color { ColorAnimation { duration: 120 } }
    }

    Rectangle {
      id: infoRing
      anchors.centerIn: parent
      width: 18
      height: 18
      radius: 9
      color: "transparent"
      border.width: 1
      border.color: panel.controlAccent
      antialiasing: true

      Rectangle {
        id: infoDot
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        width: 2
        height: 2
        radius: 1
        color: panel.controlAccent
        antialiasing: true
      }

      Rectangle {
        id: infoStem
        anchors.horizontalCenter: parent.horizontalCenter
        y: 7
        width: 2
        height: 6
        radius: 1
        color: panel.controlAccent
        antialiasing: true
      }
    }

    MouseArea {
      id: infoPointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: infoAction.hasCursor = containsMouse
      onClicked: infoAction.clicked()
    }

    Keys.onReturnPressed: infoAction.clicked()
    Keys.onEnterPressed: infoAction.clicked()
    Keys.onSpacePressed: infoAction.clicked()

  }

  component DetailRow: Item {
    id: detailRow
    required property string label
    required property string value
    implicitHeight: Commons.Style.space(21)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.34
      text: detailRow.label
      color: panel.controlMutedHigh
      font.family: panel.bar.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.weight: Font.Medium
      font.letterSpacing: 0.4
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: parent.width * 0.34
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: detailRow.value
      color: panel.bar.foreground
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideMiddle
      font.family: panel.bar.fontFamily
      font.pixelSize: Commons.Style.font.body
    }
  }

}
