pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons
import "PickerModel.js" as PickerModel

PanelWindow {
  id: root

  required property var bar
  required property var controller
  readonly property bool validScreen: controller.activeScreen !== null
    && String(controller.activeScreen.name || "") !== ""
  readonly property bool tanzakuActive: controller.pickerStyle === "tanzaku"
  readonly property bool selectedIsCurrent: controller.selectedEntry !== null
    && (controller.mode === "theme"
      ? String(controller.selectedEntry.label || "")
        === String(controller.currentSelection || "")
      : String(controller.selectedEntry.sourcePath || "")
        === String(controller.currentSelection || ""))

  function selectedLabel() {
    const entry = controller.selectedEntry
    if (!entry) return controller.emptyText
    return controller.mediaMode
      ? PickerModel.mediaLabel(entry.sourcePath)
      : String(entry.label || "")
  }

  function selectedHeadline() {
    const label = selectedLabel()
    return controller.mediaMode
      ? controller.title + " · " + label : label
  }

  screen: controller.activeScreen
  visible: controller.opened && validScreen
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "shibumi-picker"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onVisibleChanged: if (visible) Qt.callLater(stage.forceActiveFocus)

  Rectangle {
    anchors.fill: parent
    color: root.tanzakuActive
      ? Qt.rgba(root.bar.background.r, root.bar.background.g,
          root.bar.background.b, 0.8)
      : Qt.rgba(0.035, 0.035, 0.05, 0.975)

    Behavior on opacity { NumberAnimation { duration: 170 } }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.controller.close()
  }

  FocusScope {
    id: stage
    anchors.fill: parent
    focus: root.visible

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.controller.close()
      } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
        root.controller.moveSelection(-1)
      } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
        root.controller.moveSelection(1)
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.controller.activateSelected()
      } else if (event.key === Qt.Key_Backspace) {
        root.controller.updateFilter(root.controller.filterText.slice(0, -1))
      } else if (event.key === Qt.Key_Delete && root.controller.mediaMode) {
        root.controller.requestDeleteSelected()
      } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C
          && root.controller.mediaMode) {
        root.controller.copySelected()
      } else if (event.key === Qt.Key_Tab) {
        root.controller.cycleStyle(event.modifiers & Qt.ShiftModifier ? -1 : 1)
      } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier
          | Qt.MetaModifier)) && event.text && event.text.length === 1
          && event.text.charCodeAt(0) >= 32) {
        root.controller.updateFilter(root.controller.filterText + event.text)
      } else {
        return
      }
      event.accepted = true
    }

    Loader {
      id: viewLoader
      anchors.fill: parent
      sourceComponent: root.controller.pickerStyle === "hearthstone" ? hearthstoneView
        : tanzakuView
    }

    Component {
      id: tanzakuView
      TanzakuPickerView { controller: root.controller; bar: root.bar }
    }

    Component {
      id: hearthstoneView
      HearthstonePickerView { controller: root.controller; bar: root.bar }
    }

    Column {
      id: tanzakuFooter

      readonly property real focusedWidth: Math.min(Commons.Style.space(460),
        parent.width * 0.48)
      readonly property real focusedHeight: focusedWidth * 9 / 16

      visible: root.tanzakuActive && root.controller.selectedEntry !== null
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 - Commons.Style.space(10) + focusedHeight / 2
        + Commons.Style.space(16)
      width: Math.min(parent.width - Commons.Style.space(48),
        focusedWidth + Commons.Style.space(120))
      spacing: Commons.Style.space(12)

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: tanzakuFooter.focusedWidth * 0.42
        height: Commons.Style.space(3)
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 0.5; color: root.bar.urgent }
          GradientStop { position: 1; color: "transparent" }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.selectedHeadline()
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.space(22)
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        maximumLineCount: 1
        renderType: Text.NativeRendering
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.controller.mode === "theme"
          && root.controller.selectedThemePalette.length > 0
        spacing: Commons.Style.space(6)

        Repeater {
          model: root.controller.selectedThemePalette
          delegate: Rectangle {
            required property var modelData
            width: Commons.Style.space(13)
            height: width
            radius: width / 2
            color: String(modelData || "transparent")
            border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
              root.bar.foreground.b, 0.15)
            border.width: 1
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.selectedIsCurrent
          || (root.controller.mode === "theme"
            && root.controller.selectedThemeAuthor !== "")
        spacing: Commons.Style.space(12)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.selectedIsCurrent
          text: "● current"
          color: root.bar.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Commons.Style.font.caption
          renderType: Text.NativeRendering
        }

        Text {
          id: tanzakuAuthor
          anchors.verticalCenter: parent.verticalCenter
          visible: root.controller.mode === "theme"
            && root.controller.selectedThemeAuthor !== ""
          text: "by " + root.controller.selectedThemeAuthor + "  ↗"
          color: tanzakuAuthorMouse.containsMouse ? root.bar.urgent
            : root.bar.visualTokens ? root.bar.visualTokens.mutedInk
            : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
              root.bar.foreground.b, 0.45)
          font.family: root.bar.fontFamily
          font.pixelSize: Commons.Style.font.caption
          renderType: Text.NativeRendering

          MouseArea {
            id: tanzakuAuthorMouse
            anchors.fill: parent
            enabled: root.controller.selectedThemeRepo !== ""
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.controller.openSelectedThemeRepo()
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.controller.mediaMode
        spacing: Commons.Style.space(7)

        OverlayAction {
          icon: "open_in_new"
          label: "Open"
          onTriggered: root.controller.activateSelected()
        }
        OverlayAction {
          icon: "content_copy"
          label: "Copy"
          onTriggered: root.controller.copySelected()
        }
        OverlayAction {
          icon: root.controller.confirmDelete ? "delete_forever" : "delete"
          label: root.controller.confirmDelete ? "Confirm" : "Trash"
          urgent: root.controller.confirmDelete
          onTriggered: root.controller.requestDeleteSelected()
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.controller.filterText !== ""
        text: root.controller.filterText
        color: root.bar.urgent
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.font.body
        renderType: Text.NativeRendering
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "← →  navigate     Enter "
          + (root.controller.mediaMode ? "open" : "apply")
          + "     Esc cancel     type to filter     Tab style"
        color: root.bar.visualTokens ? root.bar.visualTokens.mutedInk
          : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
            root.bar.foreground.b, 0.45)
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.NativeRendering
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.controller.statusText !== ""
        text: root.controller.statusText
        color: root.bar.urgent
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    Column {
      visible: !root.tanzakuActive
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.max(Commons.Style.space(32), parent.height * 0.06)
      spacing: Commons.Style.space(5)
      width: Math.min(parent.width - Commons.Style.space(48), Commons.Style.space(760))

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.selectedHeadline()
        color: root.controller.selectedEntry ? "#ececee"
          : Qt.rgba(0.92, 0.92, 0.94, 0.55)
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.space(26)
        font.weight: Font.DemiBold
        elide: Text.ElideMiddle
        maximumLineCount: 1
        renderType: Text.NativeRendering
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.controller.mode === "theme"
          && (root.controller.selectedThemeAuthor !== ""
            || root.controller.selectedThemePalette.length > 0)
        spacing: Commons.Style.space(6)

        Repeater {
          model: root.controller.selectedThemePalette
          delegate: Rectangle {
            required property var modelData
            width: Commons.Style.space(12)
            height: width
            radius: width / 2
            color: String(modelData || "transparent")
            border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
              root.bar.foreground.b, 0.28)
            border.width: 1
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.controller.selectedThemeAuthor !== ""
          text: "by " + root.controller.selectedThemeAuthor
          color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
            root.bar.foreground.b, 0.62)
          font.family: root.bar.fontFamily
          font.pixelSize: Commons.Style.font.caption
          renderType: Text.NativeRendering

          MouseArea {
            anchors.fill: parent
            enabled: root.controller.selectedThemeRepo !== ""
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.controller.openSelectedThemeRepo()
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.controller.mediaMode && root.controller.selectedEntry !== null
        spacing: Commons.Style.space(7)

        OverlayAction {
          icon: "open_in_new"
          label: "Open"
          onTriggered: root.controller.activateSelected()
        }
        OverlayAction {
          icon: "content_copy"
          label: "Copy"
          onTriggered: root.controller.copySelected()
        }
        OverlayAction {
          icon: root.controller.confirmDelete ? "delete_forever" : "delete"
          label: root.controller.confirmDelete ? "Confirm" : "Trash"
          urgent: root.controller.confirmDelete
          onTriggered: root.controller.requestDeleteSelected()
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "← →  scroll navigate     Enter "
          + (root.controller.mediaMode ? "open" : "apply") + "     Esc cancel"
          + "     type to filter     Tab switch style"
        color: Qt.rgba(0.92, 0.92, 0.94, 0.55)
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.controller.filterText !== ""
          || root.controller.confirmDelete
        text: root.controller.filterText !== ""
          ? "Filter: " + root.controller.filterText
          : "Press Delete again to move this file to Trash"
        color: root.controller.confirmDelete ? root.bar.urgent
          : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
            root.bar.foreground.b, 0.62)
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.controller.statusText !== ""
        text: root.controller.statusText
        color: root.bar.urgent
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }

  component OverlayAction: Rectangle {
    id: action
    required property string icon
    required property string label
    property bool urgent: false
    signal triggered()

    implicitWidth: actionContent.implicitWidth + Commons.Style.space(18)
    implicitHeight: Commons.Style.space(28)
    radius: root.bar.visualTokens ? root.bar.visualTokens.tileRadius
      : Commons.Style.cornerRadius
    color: action.urgent
      ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g, root.bar.urgent.b, 0.18)
      : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, actionMouse.containsMouse ? 0.14 : 0.08)
    border.color: action.urgent ? root.bar.urgent
      : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, 0.22)
    border.width: 1

    Row {
      id: actionContent
      anchors.centerIn: parent
      spacing: Commons.Style.space(5)

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: action.icon
        color: action.urgent ? root.bar.urgent : root.bar.foreground
        font.pixelSize: Commons.Style.font.body
        fill: 0
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: action.label
        color: action.urgent ? root.bar.urgent : root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.triggered()
    }
  }
}
