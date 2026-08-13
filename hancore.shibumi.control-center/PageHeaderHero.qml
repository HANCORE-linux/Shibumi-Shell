pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var controller
  property bool active: false
  property string pageKey: ""
  property string eyebrow: ""
  property string title: ""
  property string description: ""
  property Component descriptionComponent: null
  property bool descriptionWrap: false
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property real uiScale: 1
  property real preferredHeight: Commons.Style.space(80)
  property real previewWidth: Commons.Style.space(150)
  property real actionWidth: Commons.Style.space(116)
  property string actionLabel: ""
  property string actionGlyph: ""
  property string secondaryActionLabel: ""
  property string secondaryActionGlyph: ""
  property bool secondaryActionEnabled: true
  property string secondaryActionStatusText: ""
  property string secondaryActionDescription: ""
  property color secondaryActionStatusColor: foreground
  signal actionRequested()
  signal secondaryActionRequested()

  width: parent ? parent.width : implicitWidth
  implicitHeight: preferredHeight

  Row {
    anchors.fill: parent
    spacing: Commons.Style.space(16)

    Column {
      width: parent.width - trailingStage.width - parent.spacing
      anchors.top: parent.top
      anchors.topMargin: Commons.Style.space(5)
      spacing: Commons.Style.space(7)

      Text {
        width: parent.width
        text: root.eyebrow
        color: root.accent
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
      }

      Text {
        width: parent.width
        text: root.title
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.space(24) * root.uiScale
        font.weight: Font.DemiBold
      }

      Text {
        width: parent.width
        visible: root.descriptionComponent === null
          && root.description !== ""
        text: root.description
        color: root.foreground
        opacity: 0.58
        wrapMode: root.descriptionWrap ? Text.WordWrap : Text.NoWrap
        maximumLineCount: root.descriptionWrap ? 2 : 1
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }

      Loader {
        width: parent.width
        visible: root.descriptionComponent !== null
        sourceComponent: root.descriptionComponent
      }
    }

    Item {
      id: trailingStage
      width: Math.min(root.previewWidth, parent.width * 0.43)
      height: parent.height

      PageMotionStage {
        anchors.fill: parent
        visible: root.actionLabel === ""
          && root.secondaryActionLabel === ""
        controller: root.controller
        active: root.active
        pageKey: root.pageKey
        foreground: root.foreground
        accent: root.accent
      }

      Rectangle {
        id: primaryAction
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.secondaryActionLabel !== ""
          ? -Commons.Style.space(20) : 0
        visible: root.actionLabel !== ""
        width: root.actionWidth
        height: Commons.Style.space(34)
        radius: root.controller.controlRadius
        color: actionPointer.containsMouse
          ? root.controller.controlHoverFillColor
          : root.controller.controlFillColor
        border.width: root.controller.controlBorderWidth
        border.color: root.controller.controlBorderColor

        Row {
          anchors.left: root.secondaryActionLabel !== ""
            ? parent.left : undefined
          anchors.leftMargin: root.secondaryActionLabel !== ""
            ? Commons.Style.space(10) : 0
          anchors.horizontalCenter: root.secondaryActionLabel === ""
            ? parent.horizontalCenter : undefined
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(6)

          IconText {
            id: primaryActionIcon
            visible: root.actionGlyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(17) * root.uiScale
            text: root.actionGlyph
            color: root.accent
            font.pixelSize: Commons.Style.space(17) * root.uiScale
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            fill: 0
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.actionLabel
            color: root.foreground
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
            font.weight: Font.Medium
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignLeft
          }
        }

        MouseArea {
          id: actionPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.actionRequested()
        }
      }

      Rectangle {
        id: secondaryAction
        anchors.right: parent.right
        anchors.top: primaryAction.bottom
        anchors.topMargin: Commons.Style.space(6)
        visible: root.secondaryActionLabel !== ""
        width: root.actionWidth
        height: Commons.Style.space(34)
        radius: root.controller.controlRadius
        color: secondaryPointer.containsMouse
          ? root.controller.controlHoverFillColor
          : root.controller.controlFillColor
        border.width: root.controller.controlBorderWidth
        border.color: activeFocus ? root.accent
          : root.controller.controlBorderColor
        enabled: root.secondaryActionEnabled
        opacity: enabled ? 1 : 0.62
        activeFocusOnTab: enabled
        Accessible.role: Accessible.Button
        Accessible.name: root.secondaryActionLabel
        Accessible.description: root.secondaryActionDescription
        Accessible.onPressAction: if (root.secondaryActionEnabled)
          root.secondaryActionRequested()

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Commons.Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(6)

          IconText {
            id: secondaryActionIcon
            visible: root.secondaryActionGlyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(17) * root.uiScale
            text: root.secondaryActionGlyph
            color: root.accent
            font.pixelSize: Commons.Style.space(17) * root.uiScale
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            fill: 0
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.secondaryActionLabel
            color: root.foreground
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
            font.weight: Font.Medium
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignLeft
          }
        }

        ShibumiPanelToolTip {
          panel: root.controller
          visible: secondaryPointer.containsMouse
            && root.secondaryActionDescription !== ""
          text: root.secondaryActionDescription
        }

        MouseArea {
          id: secondaryPointer
          anchors.fill: parent
          hoverEnabled: true
          enabled: root.secondaryActionEnabled
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.secondaryActionRequested()
        }

        Keys.onReturnPressed: if (root.secondaryActionEnabled)
          root.secondaryActionRequested()
        Keys.onEnterPressed: if (root.secondaryActionEnabled)
          root.secondaryActionRequested()
        Keys.onSpacePressed: if (root.secondaryActionEnabled)
          root.secondaryActionRequested()
      }

      Text {
        anchors.top: secondaryAction.bottom
        anchors.topMargin: Commons.Style.space(2)
        anchors.horizontalCenter: secondaryAction.horizontalCenter
        visible: secondaryAction.visible
          && root.secondaryActionStatusText !== ""
        width: secondaryAction.width
        text: root.secondaryActionStatusText
        color: root.secondaryActionStatusColor
        opacity: 0.68
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.weight: Font.Medium
        renderType: Text.NativeRendering
      }
    }
  }
}
