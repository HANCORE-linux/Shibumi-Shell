pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string glyph
  required property string label
  property string provider: "Shibumi"
  property string relationship: ""
  property bool inserted: false
  property bool replaced: false
  property string replacedBy: ""
  property bool removable: false
  property bool removalBusy: false
  property bool favorite: false
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  readonly property color activeStatusColor:
    typeof controller.accentColor === "function"
      ? controller.accentColor("color03") : accent
  readonly property color replacedStatusColor:
    typeof controller.accentColor === "function"
      ? controller.accentColor("color01") : accent
  readonly property color favoriteStatusColor:
    typeof controller.accentColor === "function"
      ? controller.accentColor("color03") : accent
  readonly property color favoriteGlyphColor:
    favorite ? favoriteStatusColor : foreground
  readonly property string favoriteGlyphText:
    favorite ? "󰓎" : "star_border"
  signal toggled()
  signal favoriteToggled()
  signal removeRequested()

  implicitHeight: Commons.Style.space(58)
  radius: controller.controlRadius
  color: pointer.containsMouse
    ? controller.controlHoverFillColor : controller.controlFillColor
  border.width: controller.controlBorderWidth
  border.color: controller.controlBorderColor

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    enabled: !root.removalBusy
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.toggled()
  }

  Row {
    anchors.fill: parent
    anchors.margins: Commons.Style.space(8)
    spacing: Commons.Style.space(8)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(32)
      height: width
      radius: root.controller.controlRadius
      color: Commons.Util.alpha(root.accent, 0.09)
      border.width: 1
      border.color: root.controller.controlBorderColor

      IconText {
        anchors.centerIn: parent
        text: root.glyph
        color: root.inserted ? root.accent : root.foreground
        font.pixelSize: Commons.Style.space(17) * root.uiScale
        font.weight: Font.Medium
        fill: 0
      }
    }

    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - actionRow.width - parent.spacing
      height: Commons.Style.space(38)

      Text {
        id: labelText
        anchors.left: parent.left
        anchors.right: statusLabel.left
        anchors.rightMargin: Commons.Style.space(8)
        anchors.top: parent.top
        width: parent.width
        text: root.label
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        font.weight: Font.DemiBold
      }

      Text {
        id: statusLabel
        anchors.right: parent.right
        anchors.top: parent.top
        text: root.inserted ? "ACTIVE"
          : root.replaced ? "REPLACED" : "AVAILABLE"
        color: root.inserted ? root.activeStatusColor
          : root.replaced ? root.replacedStatusColor : root.foreground
        opacity: root.inserted || root.replaced ? 1 : 0.54
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.weight: Font.DemiBold
        font.letterSpacing: 0.45
      }

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: root.replaced && root.replacedBy !== ""
          ? "Replaced by " + root.replacedBy
          : root.relationship !== "" ? root.relationship : root.provider
        color: root.replaced ? root.accent : root.foreground
        opacity: root.replaced ? 0.82 : 0.46
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }

    Row {
      id: actionRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Commons.Style.space(5)

      Rectangle {
        id: favoriteAction
        width: Commons.Style.space(24)
        height: width
        radius: root.controller.controlRadius
        color: favoritePointer.containsMouse
          ? root.controller.controlHoverFillColor : "transparent"
        border.width: 0

        Item {
          anchors.centerIn: parent
          width: Commons.Style.space(16) * root.uiScale
          height: width
          opacity: root.favorite || favoritePointer.containsMouse ? 1 : 0.46

          Text {
            anchors.centerIn: parent
            visible: root.favorite
            text: root.favoriteGlyphText
            color: root.favoriteGlyphColor
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: parent.width
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          IconText {
            anchors.centerIn: parent
            visible: !root.favorite
            text: root.favoriteGlyphText
            color: root.favoriteGlyphColor
            font.pixelSize: parent.width
            iconWeight: 500
            fill: 0
          }
        }

        MouseArea {
          id: favoritePointer
          anchors.fill: parent
          anchors.margins: -Commons.Style.space(3)
          z: 3
          enabled: !root.removalBusy
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.favoriteToggled()
        }
      }

      Rectangle {
        id: removeAction
        visible: root.removable
        width: visible ? Commons.Style.space(24) : 0
        height: width
        radius: root.controller.controlRadius
        color: removePointer.containsMouse
          ? Commons.Util.alpha(Commons.Color.urgent, 0.16) : "transparent"
        border.width: removePointer.containsMouse ? 1 : 0
        border.color: Commons.Util.alpha(Commons.Color.urgent, 0.62)

        IconText {
          anchors.centerIn: parent
          text: root.removalBusy ? "hourglass_top" : "delete"
          color: Commons.Color.urgent
          opacity: root.removalBusy ? 0.48 : 0.78
          font.pixelSize: Commons.Style.space(16) * root.uiScale
          font.weight: Font.Medium
          fill: 0
        }

        MouseArea {
          id: removePointer
          anchors.fill: parent
          anchors.margins: -Commons.Style.space(3)
          z: 3
          enabled: !root.removalBusy
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.removeRequested()
        }
      }

      Rectangle {
        id: enableSwitch
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(30)
        height: Commons.Style.space(17)
        radius: height / 2
        color: root.inserted
          ? root.accent : root.controller.controlHoverFillColor

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          x: root.inserted ? parent.width - width - Commons.Style.space(2)
            : Commons.Style.space(2)
          width: Commons.Style.space(13)
          height: width
          radius: width / 2
          color: root.inserted
            ? root.controller.marketBackground : root.foreground
          opacity: root.inserted ? 1 : 0.54
        }

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Commons.Style.space(7)
          z: 2
          enabled: !root.removalBusy
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.toggled()
        }
      }
    }
  }

}
