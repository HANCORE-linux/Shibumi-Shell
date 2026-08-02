pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var controller
  required property int shibumiCount
  required property int omarchyCount
  required property int thirdPartyCount
  property bool active: false
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  readonly property bool reducedMotion: controller
    && "reducedMotion" in controller
    && controller.reducedMotion === true
  readonly property bool motionEnabled: active && !reducedMotion
  readonly property string countKey: shibumiCount + ":"
    + omarchyCount + ":" + thirdPartyCount
  property real glossX: -Commons.Style.space(54)

  implicitHeight: Commons.Style.space(52)
  clip: true

  function runGloss() {
    if (!motionEnabled) return
    glossPass.stop()
    glossX = -Commons.Style.space(54)
    glossPass.start()
  }

  onActiveChanged: if (active) Qt.callLater(runGloss)
  onCountKeyChanged: if (active) Qt.callLater(runGloss)

  Rectangle {
    anchors.fill: parent
    visible: root.reducedMotion
    color: Commons.Util.alpha(root.accent, 0.045)
  }

  Rectangle {
    x: root.glossX
    width: Commons.Style.space(54)
    height: parent.height
    visible: glossPass.running
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: "transparent"
      }
      GradientStop {
        position: 0.5
        color: Commons.Util.alpha(root.accent, 0.15)
      }
      GradientStop {
        position: 1
        color: "transparent"
      }
    }
  }

  NumberAnimation {
    id: glossPass
    target: root
    property: "glossX"
    from: -Commons.Style.space(54)
    to: root.width + Commons.Style.space(12)
    duration: 560
    easing.type: Easing.InOutCubic
  }

  Column {
    anchors.fill: parent
    spacing: Commons.Style.space(2)

    ProviderRow {
      width: parent.width
      iconSource: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")
      fallbackGlyph: "radio_button_checked"
      imageSize: Commons.Style.space(18)
      label: root.shibumiCount + " INSTALLED SHIBUMI PLUGINS"
    }

    ProviderRow {
      width: parent.width
      iconSource: "file:///usr/share/omarchy/icon.png"
      fallbackGlyph: "deployed_code"
      imageSize: Commons.Style.space(15)
      label: root.omarchyCount + " COMPATIBLE OMARCHY WIDGETS"
    }

    ProviderRow {
      width: parent.width
      glyphOnly: true
      fallbackGlyph: "extension"
      label: root.thirdPartyCount + " THIRD-PARTY "
        + (root.thirdPartyCount === 1 ? "PLUGIN" : "PLUGINS")
    }
  }

  component ProviderRow: Item {
    property url iconSource: ""
    required property string fallbackGlyph
    required property string label
    property bool glyphOnly: false
    property real imageSize: Commons.Style.space(15)

    implicitHeight: Commons.Style.space(16)

    Item {
      id: iconCell
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(18)
      height: width

      Image {
        id: providerIcon
        anchors.centerIn: parent
        width: parent.parent.imageSize
        height: width
        visible: !parent.parent.glyphOnly
        source: parent.parent.iconSource
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
      }

      IconText {
        anchors.centerIn: parent
        visible: parent.parent.glyphOnly
          || providerIcon.status === Image.Error
        text: parent.parent.fallbackGlyph
        color: root.accent
        font.pixelSize: Commons.Style.space(15) * root.uiScale
        fill: 0
      }
    }

    Text {
      anchors.left: iconCell.right
      anchors.leftMargin: Commons.Style.space(7)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      color: root.foreground
      elide: Text.ElideRight
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.DemiBold
      font.letterSpacing: 1.2
    }
  }
}
