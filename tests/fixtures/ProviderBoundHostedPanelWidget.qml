import QtQuick
import qs.Ui as Ui

// Representative provider body. The provider's own fittedContentHeight binding,
// not WidgetSlot traversal or repair, owns the standard KeyboardPanel height.
Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property real availableWidth: 0
  property bool opened: true
  property int bodyHeight: 278
  property int panelPadding: 15
  readonly property alias standardPanel: panel

  implicitWidth: 28
  implicitHeight: 28

  Ui.KeyboardPanel {
    id: panel

    anchorItem: root
    bar: root.bar
    open: root.opened
    padding: root.panelPadding
    contentWidth: 420
    contentHeight: fittedContentHeight(root.bodyHeight, 600)

    Item {
      width: parent.width
      implicitHeight: root.bodyHeight

      // These controlled shapes represent overhang, Control-like, and image-like
      // descendants. Their geometry cannot replace the provider height binding.
      Item {
        width: parent.width
        height: parent.height + 14
        implicitHeight: 180
      }
      Rectangle { width: 120; height: 90; color: "transparent" }
      Image { width: 320; height: 260; fillMode: Image.PreserveAspectFit }
    }
  }
}
