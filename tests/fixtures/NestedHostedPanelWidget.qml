import QtQuick

// Models third-party plugins such as Otoru and Snake: the bar-widget entry
// point loads its standard panel owner through an intermediate Loader.
Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property real availableWidth: 0
  property bool eagerPanel: false
  property bool panelLoaderActive: false
  property bool opened: false
  property int loadGeneration: 0
  property int desiredContentHeight: 360
  readonly property var exposedPanel: panelLoader.item
    ? panelLoader.item.standardPanel : null

  function openOnDemand() {
    root.opened = true
    activationTimer.restart()
  }

  function closeLoaded() {
    root.opened = false
  }

  function closeAndUnload() {
    activationTimer.stop()
    replacementTimer.stop()
    root.panelLoaderActive = false
    root.opened = false
  }

  function replaceWhileOpen() {
    if (!root.opened) return
    root.panelLoaderActive = false
    replacementTimer.restart()
  }

  implicitWidth: 28
  implicitHeight: 28

  Component.onCompleted: {
    if (root.eagerPanel) root.panelLoaderActive = true
  }

  Timer {
    id: activationTimer

    interval: 80
    repeat: false
    onTriggered: root.panelLoaderActive = true
  }

  Timer {
    id: replacementTimer

    interval: 80
    repeat: false
    onTriggered: root.panelLoaderActive = true
  }

  Loader {
    id: panelLoader

    active: root.panelLoaderActive
    // The real KeyboardPanel owns a separate window, so its card remains
    // effectively visible even though Otoru/Snake hide their owner Loader.
    visible: true
    onLoaded: root.loadGeneration++
    sourceComponent: Component {
      Item {
        id: loadedPanelOwner

        property alias standardPanel: standardPanel

        QtObject {
          id: cycleA
          property list<QtObject> data: [cycleB]
        }

        QtObject {
          id: cycleB
          property list<QtObject> data: [cycleA]
        }

        Item {
          id: anchor
          width: 24
          height: 24
        }

        Item {
          id: standardPanel

          objectName: "nestedStandardKeyboardPanel"
          property Item anchorItem: anchor
          property point cardOrigin: Qt.point(900, 900)
          property var borderSpec: ({ source: "provider" })
          property int contentWidth: 420
          // A screen-sized Shibumi anchor makes native KeyboardPanel cap its
          // content to the 120px safety minimum before host repair.
          property int contentHeight: 120
          property bool open: root.opened
          property int margin: 8
          property int gap: 8
          property int screenW: 1920
          property int screenH: 1080
          property string barPos: root.bar ? root.bar.position : "top"
          property point anchorScreenPos: Qt.point(700, 0)
          property real anchorW: anchor.width
          property real anchorH: anchor.height

          Item {
            id: card

            objectName: "nestedStandardPanelCard"
            x: standardPanel.cardOrigin.x
            y: standardPanel.cardOrigin.y
            width: standardPanel.contentWidth
            height: standardPanel.contentHeight
            property int contentTopInset: 12
            property int contentBottomInset: 12
            property var borderSpec: ({ source: "provider" })
            property int radius: 4
            property color color: "#202020"

            Item {
              anchors.fill: parent

              Rectangle {
                width: 120
                height: root.desiredContentHeight
              }
            }
          }
        }
      }
    }
  }
}
