pragma ComponentBehavior: Bound

import QtQuick

Item {
  required property var ownerWidget
  required property var trayBackend
  required property Item anchorItem
  required property QtObject bar
}
