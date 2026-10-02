import QtQuick
import qs.Commons as Commons

// The established Memory, CPU and Volume heading typography.
Text {
  id: root

  font.family: Commons.Style.font.family
  font.pixelSize: 13
  font.weight: Font.Medium
  font.letterSpacing: 2
  font.capitalization: Font.AllUppercase
  renderType: Text.NativeRendering

  // Preserve a former line box where content or input is anchored to it.
  property font layoutFont: font
  property bool reserveLayoutWidth: false
  width: reserveLayoutWidth ? layoutMetrics.advanceWidth : implicitWidth
  height: Math.ceil(layoutMetrics.boundingRect.height)
  horizontalAlignment: reserveLayoutWidth ? Text.AlignHCenter : Text.AlignLeft
  verticalAlignment: Text.AlignVCenter

  TextMetrics {
    id: layoutMetrics
    text: root.text
    font: root.layoutFont
  }
}
