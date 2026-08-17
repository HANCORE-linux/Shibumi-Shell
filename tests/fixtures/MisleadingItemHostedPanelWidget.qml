import QtQuick

// An arbitrary object-valued `item` property is not an ownership edge. The
// hosted-panel adapter must not discover or restyle this detached candidate.
Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property real availableWidth: 0
  property QtObject detachedPanel: QtObject {
    objectName: "detachedPanelBehindArbitraryItem"
    property var anchorItem: null
    property point cardOrigin: Qt.point(0, 0)
    property var borderSpec: ({})
    property int contentWidth: 200
    property int contentHeight: 100
    property bool open: true
  }

  implicitWidth: 28
  implicitHeight: 28

  QtObject {
    property var item: root.detachedPanel
  }
}
