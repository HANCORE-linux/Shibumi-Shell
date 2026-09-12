pragma ComponentBehavior: Bound

import QtQuick

Item {
  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var networkService
  property bool speedDetailsVisible: false

  Component.onCompleted: networkService.viewLoadCount++
}
