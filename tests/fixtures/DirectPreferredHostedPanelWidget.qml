import QtQuick

// Keeps a nested candidate before a direct standard panel in declaration
// order. Breadth-first discovery must retain the direct provider contract.
Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property real availableWidth: 0
  property alias directPanel: directPanel
  readonly property var nestedPanel: nestedLoader.item
    ? nestedLoader.item.standardPanel : null

  implicitWidth: 28
  implicitHeight: 28

  Loader {
    id: nestedLoader

    active: true
    visible: false
    sourceComponent: Component {
      Item {
        property alias standardPanel: standardPanel

        Item {
          id: standardPanel

          objectName: "nestedPanelThatMustNotWin"
          property Item anchorItem: standardPanel
          property point cardOrigin: Qt.point(0, 0)
          property var borderSpec: ({})
          property int contentWidth: 200
          property int contentHeight: 100
          property bool open: true

          Item {
            property int contentTopInset: 0
            property var borderSpec: ({})
            property int radius: 0
            property color color: "#000000"
          }
        }
      }
    }
  }

  Item {
    id: directPanel

    objectName: "directStandardPanel"
    property Item anchorItem: directPanel
    property point cardOrigin: Qt.point(0, 0)
    property var borderSpec: ({})
    property int contentWidth: 200
    property int contentHeight: 100
    property bool open: true

    Item {
      property int contentTopInset: 0
      property var borderSpec: ({})
      property int radius: 0
      property color color: "#000000"
    }
  }
}
