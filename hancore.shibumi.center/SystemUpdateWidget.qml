pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

// V1 presentation over Quattro's registered omarchy.system-update owner.
// The backend keeps update detection, IPC, and launch ownership.
Ui.BarWidget {
  id: root

  moduleName: "omarchy.system-update"
  property var backendWidget: null
  readonly property var updateService: bar && bar.shell
    && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.system-update") : null
  property color contentColor: bar
    ? bar.urgent : Commons.Color.urgent

  readonly property int updateCount: updateService
    ? Number(updateService.totalUpdateCount || 0) : 0
  readonly property bool updateAvailable: updateService
    ? updateCount > 0 || updateService.needsAttention === true
    : backendWidget ? backendWidget.updateAvailable === true : false
  readonly property string tooltipText: updateService
    ? updateCount > 0
      ? updateCount + " update" + (updateCount === 1 ? "" : "s") + " available"
      : updateService.needsAttention === true
        ? "Update check needs attention" : "System is up to date"
    : "Omarchy update available"
  readonly property string iconFamily: updateIcon.font.family
  readonly property real opticalCenterOffset: 1
  readonly property var interactionTarget: updateMouse

  visible: updateAvailable
  implicitWidth: updateAvailable ? 20 : 0
  implicitHeight: bar ? bar.barSize : Commons.Style.space(35)
  width: implicitWidth
  height: implicitHeight

  function activate() {
    if (!backendWidget || typeof backendWidget.runUpdate !== "function") return false
    backendWidget.runUpdate()
    return true
  }

  function refresh() {
    if (updateService && typeof updateService.refreshAll === "function") {
      updateService.refreshAll()
      return true
    }
    if (backendWidget && typeof backendWidget.refresh === "function") {
      backendWidget.refresh()
      return true
    }
    return false
  }

  IconText {
    id: updateIcon
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.opticalCenterOffset
    text: "\ue627"
    color: root.contentColor
    font.pixelSize: 15
  }

  MouseArea {
    id: updateMouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      if (mouse.button === Qt.RightButton) root.refresh()
      else root.activate()
    }
  }
}
