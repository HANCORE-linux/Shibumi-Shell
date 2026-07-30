pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var flickable
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool active: true
  property real minimumThumbHeight: Commons.Style.space(18)
  readonly property bool scrollable: !!flickable
    && flickable.contentHeight > flickable.height + 0.5
  readonly property bool engaged: pointer.containsMouse || pointer.pressed
    || (flickable && flickable.movingVertically)

  function setThumbTop(localTop) {
    if (!root.scrollable) return
    const trackRange = Math.max(1, root.height - thumb.height)
    const contentRange = Math.max(
      0, root.flickable.contentHeight - root.flickable.height)
    const ratio = Math.max(0, Math.min(
      1, Number(localTop) / trackRange))
    root.flickable.contentY = ratio * contentRange
  }

  function seek(localY) {
    root.setThumbTop(Number(localY) - thumb.height / 2)
  }

  implicitWidth: Commons.Style.space(7)
  visible: active && !!flickable && flickable.visible && scrollable

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    width: 1
    height: parent.height
    radius: width / 2
    color: Commons.Util.alpha(root.foreground, 0.10)
  }

  Rectangle {
    id: thumb

    anchors.horizontalCenter: parent.horizontalCenter
    width: root.engaged ? 3 : 2
    height: Math.min(root.height, Math.max(root.minimumThumbHeight,
      root.height * Math.min(1, root.flickable.visibleArea.heightRatio)))
    y: Math.max(0, Math.min(root.height - height,
      root.flickable.visibleArea.yPosition * root.height))
    radius: width / 2
    color: root.engaged
      ? Commons.Util.alpha(root.accent, 0.82)
      : Commons.Util.alpha(root.foreground, 0.38)

    Behavior on width {
      NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
    }
    Behavior on color {
      ColorAnimation { duration: 100 }
    }
  }

  MouseArea {
    id: pointer
    property real dragOffset: 0

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: function(mouse) {
      const onThumb = mouse.y >= thumb.y
        && mouse.y <= thumb.y + thumb.height
      if (onThumb) {
        dragOffset = mouse.y - thumb.y
      } else {
        root.seek(mouse.y)
        dragOffset = thumb.height / 2
      }
      mouse.accepted = true
    }
    onPositionChanged: function(mouse) {
      if (pressed) root.setThumbTop(mouse.y - dragOffset)
    }
  }
}
