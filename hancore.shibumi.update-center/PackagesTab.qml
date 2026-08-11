pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  required property var updateService
  required property var panel

  readonly property var packageStatus: updateService
    ? updateService.packageState : Model.emptyPackageState()
  readonly property var packages: packageStatus
    && Array.isArray(packageStatus.packages) ? packageStatus.packages : []
  readonly property color foreground: panel.controlForeground
  readonly property color dim: panel.controlMuted
  readonly property color urgent: panel.bar
    ? panel.bar.urgent : panel.controlAccent
  readonly property string fontFamily: panel.bar
    ? String(panel.bar.fontFamily || Commons.Style.font.family)
    : Commons.Style.font.family

  function openSystemUpdater() {
    updateService.launchPackageUpdate()
    if (panel.ownerWidget
        && typeof panel.ownerWidget.close === "function")
      panel.ownerWidget.close()
  }

  function summaryText() {
    if (!updateService) return "Update service is loading"
    if (updateService.packageRefreshing)
      return "Checking official repositories…"
    if (updateService.packageError !== "") return updateService.packageError
    if (packageStatus.state === "loading")
      return "Repository packages have not been checked"
    if (packageStatus.state === "unavailable")
      return "Repository scan unavailable"
    if (packageStatus.state === "invalid")
      return "Repository scan returned invalid data"
    if (packages.length === 0)
      return "Official repository packages are up to date"
    return packages.length + " official package"
      + (packages.length === 1 ? "" : "s") + " ready for review"
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Commons.Style.space(8)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 1

      Text {
        Layout.fillWidth: true
        text: root.summaryText()
        color: root.packageStatus.state === "unavailable"
          || root.packageStatus.state === "invalid"
          || root.updateService.packageError !== ""
          ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.bodySmall
        font.weight: root.packages.length > 0 ? Font.Medium : Font.Normal
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        text: Model.checkedLabel(root.packageStatus.checkedEpoch)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: root.panel.dividerColor
    }

    Row {
      Layout.fillWidth: true
      Layout.preferredHeight: Commons.Style.space(16)
      spacing: Commons.Style.space(12)
      visible: root.packages.length > 0

      HeaderText {
        width: parent.width - Commons.Style.space(248)
        text: "PACKAGE"
      }
      HeaderText {
        width: Commons.Style.space(112)
        text: "INSTALLED"
      }
      HeaderText {
        width: Commons.Style.space(112)
        text: "AVAILABLE"
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ListView {
        id: packageList
        anchors.fill: parent
        anchors.rightMargin: overflowThumb.visible
          ? Commons.Style.space(7) : 0
        clip: true
        spacing: 0
        model: root.packages
        visible: root.packages.length > 0
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
          required property var modelData
          required property int index
          width: ListView.view.width
          height: Commons.Style.space(26)

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Commons.Style.space(12)

            CellText {
              width: parent.width - Commons.Style.space(248)
              text: modelData.name
              color: root.foreground
              font.pixelSize: Commons.Style.font.bodySmall
            }
            CellText {
              width: Commons.Style.space(112)
              text: modelData.installed
            }
            CellText {
              width: Commons.Style.space(112)
              text: modelData.target
              color: root.panel.controlAccent
              font.weight: Font.Medium
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            visible: index < root.packages.length - 1
            color: Qt.rgba(root.foreground.r, root.foreground.g,
              root.foreground.b, 0.08)
          }
        }
      }

      Item {
        id: overflowThumb
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Commons.Style.space(7)
        visible: packageList.contentHeight > packageList.height + 1

        Rectangle {
          width: dragArea.containsMouse || dragArea.pressed ? 5 : 3
          height: packageList.contentHeight > 0
            ? Math.max(Commons.Style.space(22),
              overflowThumb.height * overflowThumb.height
                / packageList.contentHeight) : 0
          x: (overflowThumb.width - width) / 2
          y: packageList.contentHeight > packageList.height
            ? (overflowThumb.height - height)
              * packageList.contentY
              / (packageList.contentHeight - packageList.height) : 0
          radius: width / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g,
            root.foreground.b,
            dragArea.containsMouse || dragArea.pressed ? 0.5 : 0.28)
        }

        MouseArea {
          id: dragArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          property real startY: 0
          property real startContentY: 0
          onPressed: function(mouse) {
            startY = mouse.y
            startContentY = packageList.contentY
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            const scrollable = packageList.contentHeight - packageList.height
            if (scrollable <= 0) return
            packageList.contentY = Math.max(0, Math.min(scrollable,
              startContentY + (mouse.y - startY)
                * scrollable / Math.max(1, height)))
          }
        }
      }

      Column {
        anchors.centerIn: parent
        visible: root.packages.length === 0
        spacing: Commons.Style.space(6)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.updateService.packageRefreshing ? "\uf021"
            : root.packageStatus.state === "current" ? "\uf058" : "\uf071"
          color: root.packageStatus.state === "current"
            ? root.panel.controlAccent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.display
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.summaryText()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.bodySmall
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: root.panel.dividerColor
    }

    Row {
      Layout.fillWidth: true
      Layout.preferredHeight: Commons.Style.space(28)
      spacing: Commons.Style.space(8)

      PanelButton {
        objectName: "packageFooterRefresh"
        width: Commons.Style.space(150)
        panel: root.panel
        text: root.updateService.packageRefreshing ? "Checking…" : "Refresh"
        iconText: "\uf021"
        enabled: !root.updateService.packageRefreshing
          && root.updateService.actionKind === ""
        controlHeight: Commons.Style.space(28)
        onClicked: root.updateService.refreshPackages()
      }

      PanelButton {
        objectName: "packageFooterSystemUpdate"
        width: parent.width - Commons.Style.space(158)
        panel: root.panel
        text: root.packages.length > 0
          ? "Full system update (" + root.packages.length + ")"
          : "Open system updater"
        iconText: "\uf019"
        primary: root.packages.length > 0
        enabled: !root.updateService.packageRefreshing
        controlHeight: Commons.Style.space(28)
        tooltipText: "Open Omarchy's full system updater"
        onClicked: root.openSystemUpdater()
      }
    }
  }

  component HeaderText: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.weight: Font.Medium
    font.letterSpacing: 1
    elide: Text.ElideRight
  }

  component CellText: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    elide: Text.ElideRight
    maximumLineCount: 1
  }
}
