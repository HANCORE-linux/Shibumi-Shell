import QtQuick
import QtQuick.Window

// Component-test substitution for the platform PanelWindow shell only.
// Production QML card, holder, sizing, and positioning logic remains unchanged.
Window {
  id: root

  property int exclusionMode: 0
  property var mask: null
  property bool backingWindowVisible: visible
  property alias contentData: root.contentItem.data
  default property alias fixtureData: root.contentItem.data

  function itemPosition(item) {
    return item ? item.mapToItem(contentItem, 0, 0) : Qt.point(0, 0)
  }
}
