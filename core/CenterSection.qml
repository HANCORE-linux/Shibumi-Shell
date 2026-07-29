pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property var bar
  property var entries: []
  property string anchorId: ""
  readonly property int anchorIndex: bar.entryIndex(entries, anchorId)
  readonly property var anchorEntry: anchorIndex >= 0 ? entries[anchorIndex] : null
  readonly property var beforeEntries: anchorIndex >= 0 ? entries.slice(0, anchorIndex) : []
  readonly property var afterEntries: anchorIndex >= 0 ? entries.slice(anchorIndex + 1) : []

  Loader {
    anchors.fill: parent
    sourceComponent: root.bar.vertical ? verticalContent : horizontalContent
  }

  Component {
    id: horizontalContent

    Item {
      BarSection {
        visible: root.anchorIndex < 0
        bar: root.bar
        region: "center"
        entries: root.anchorIndex < 0 ? root.entries : []
        anchors.centerIn: parent
      }

      BarSection {
        visible: root.anchorIndex >= 0
        bar: root.bar
        region: "center"
        entries: root.beforeEntries
        anchors.right: anchorSlot.left
        anchors.verticalCenter: anchorSlot.verticalCenter
      }

      WidgetSlot {
        id: anchorSlot
        visible: root.anchorIndex >= 0
        bar: root.bar
        region: "center"
        entry: root.anchorEntry
        anchors.centerIn: parent
      }

      BarSection {
        visible: root.anchorIndex >= 0
        bar: root.bar
        region: "center"
        entries: root.afterEntries
        anchors.left: anchorSlot.right
        anchors.verticalCenter: anchorSlot.verticalCenter
      }
    }
  }

  Component {
    id: verticalContent

    Item {
      BarSection {
        visible: root.anchorIndex < 0
        bar: root.bar
        region: "center"
        entries: root.anchorIndex < 0 ? root.entries : []
        anchors.centerIn: parent
      }

      BarSection {
        visible: root.anchorIndex >= 0
        bar: root.bar
        region: "center"
        entries: root.beforeEntries
        anchors.bottom: anchorSlot.top
        anchors.horizontalCenter: anchorSlot.horizontalCenter
      }

      WidgetSlot {
        id: anchorSlot
        visible: root.anchorIndex >= 0
        bar: root.bar
        region: "center"
        entry: root.anchorEntry
        anchors.centerIn: parent
      }

      BarSection {
        visible: root.anchorIndex >= 0
        bar: root.bar
        region: "center"
        entries: root.afterEntries
        anchors.top: anchorSlot.bottom
        anchors.horizontalCenter: anchorSlot.horizontalCenter
      }
    }
  }
}
