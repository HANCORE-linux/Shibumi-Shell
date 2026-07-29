pragma ComponentBehavior: Bound

import QtQuick

Item {
  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var monitorService

  Component.onCompleted: {
    monitorService.backend.viewLoadCount++
    bar.requestPopout(ownerWidget)
  }
  Component.onDestruction: {
    if (bar.activePopout === ownerWidget) bar.releasePopout(ownerWidget)
  }
}
