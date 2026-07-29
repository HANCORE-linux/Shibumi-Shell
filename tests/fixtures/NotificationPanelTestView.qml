pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var notificationService
  readonly property int pendingCount: notificationService
    && notificationService.pendingModel
    ? notificationService.pendingModel.count : 0

  function toggleDnd() {
    notificationService.setDoNotDisturb(!notificationService.doNotDisturb)
  }

  function markAllSeen() {
    notificationService.markAllSeen()
  }

  function dismissPending() {
    notificationService.dismissPending(0)
  }

  Component.onCompleted: {
    if (ownerWidget.notificationPanelOpen && bar
        && typeof bar.requestPopout === "function")
      bar.requestPopout(ownerWidget)
  }

  Component.onDestruction: {
    if (bar && bar.activePopout === ownerWidget
        && typeof bar.releasePopout === "function")
      bar.releasePopout(ownerWidget)
  }
}
