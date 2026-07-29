pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property var bar
  property string region: ""
  property string screenName: ""
  property var entries: []
  readonly property Item contentItem: content.item

  visible: entries.length > 0
  implicitWidth: contentItem ? contentItem.implicitWidth : 0
  implicitHeight: contentItem ? contentItem.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight

  Loader {
    id: content
    sourceComponent: root.bar.vertical ? verticalList : horizontalList
  }

  Component {
    id: horizontalList

    Row {
      Repeater {
        model: root.entries
        WidgetSlot {
          required property var modelData
          bar: root.bar
          entry: modelData
          region: root.region
          screenName: root.screenName
        }
      }
    }
  }

  Component {
    id: verticalList

    Column {
      Repeater {
        model: root.entries
        WidgetSlot {
          required property var modelData
          bar: root.bar
          entry: modelData
          region: root.region
          screenName: root.screenName
        }
      }
    }
  }
}
