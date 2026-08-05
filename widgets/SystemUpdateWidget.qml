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

  readonly property bool updateAvailable: backendWidget
    ? backendWidget.updateAvailable === true : false
  readonly property string tooltipText: "Omarchy update available"
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
    if (!backendWidget || typeof backendWidget.refresh !== "function") return false
    backendWidget.refresh()
    return true
  }

  IconText {
    id: updateIcon
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.opticalCenterOffset
    text: "\ue627"
    color: root.bar ? root.bar.urgent : Commons.Color.urgent
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
