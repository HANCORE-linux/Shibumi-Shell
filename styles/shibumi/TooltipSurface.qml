import QtQuick

Item {
  id: root

  required property var bar
  readonly property string resolvedText: {
    const target = bar ? bar.tooltipTarget : null
    return target && target.tooltipText !== undefined
      ? String(target.tooltipText) : String(bar ? bar.tooltipText || "" : "")
  }

  implicitWidth: tooltipBubble.implicitWidth
  implicitHeight: tooltipBubble.implicitHeight

  Rectangle {
    id: tooltipBubble

    anchors.fill: parent
    implicitWidth: tooltipLabel.implicitWidth
      + 2 * root.bar.visualTokens.tooltipPaddingX
    implicitHeight: tooltipLabel.implicitHeight
      + 2 * root.bar.visualTokens.tooltipPaddingY
    color: root.bar.background
    border.color: root.bar.visualTokens.pillBorder
    border.width: root.bar.visualTokens.panelBorderWidth
    radius: root.bar.visualTokens.tooltipRadius

    Text {
      id: tooltipLabel

      anchors.centerIn: parent
      text: root.resolvedText
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: 12
      font.letterSpacing: 1
      renderType: Text.NativeRendering
    }
  }
}
