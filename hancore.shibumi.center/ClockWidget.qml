pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
  id: root

  moduleName: "omarchy.clock"

  required property var clockService
  property color contentColor: bar
    ? bar.foreground : Commons.Color.foreground
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property var clock: clockService
  readonly property date displayDate: clock ? clock.date : new Date()
  readonly property bool clock12h: setting("clock12h", false) === true
  readonly property string timeText: formatTime(displayDate)
  readonly property string tooltipText: Qt.formatDate(displayDate, "ddd, d MMMM yyyy")

  implicitWidth: bar && bar.vertical ? bar.barSize : label.implicitWidth
  implicitHeight: bar ? bar.barSize : 35

  function pad(value) {
    return Number(value) < 10 ? "0" + Number(value) : String(Number(value))
  }

  function formatTime(value) {
    if (!(value instanceof Date) || isNaN(value.getTime())) return "--:--"
    const hours = value.getHours()
    if (clock12h) {
      let displayHours = hours % 12
      if (displayHours === 0) displayHours = 12
      return displayHours + ":" + pad(value.getMinutes())
        + (hours < 12 ? " AM" : " PM")
    }
    return pad(hours) + ":" + pad(value.getMinutes())
  }

  function toggleFormat() {
    return stateService && typeof stateService.setWidgetSetting === "function"
      ? stateService.setWidgetSetting("G8", moduleName, "clock12h", !clock12h)
      : false
  }

  function openTimezoneMenu() {
    if (!bar || typeof bar.run !== "function") return false
    bar.run("omarchy-menu-timezone")
    return true
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.bar && root.bar.vertical
      ? Qt.formatTime(root.displayDate, "HH\nmm") : root.timeText
    horizontalAlignment: Text.AlignHCenter
    color: root.contentColor
    font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: root.bar && "visualTokens" in root.bar
      && root.bar.visualTokens
      ? root.bar.visualTokens.labelSize : 12
    font.letterSpacing: root.bar && root.bar.vertical ? 0 : 1
    renderType: Text.NativeRendering
  }

  Ui.WidgetButton {
    anchors.fill: parent
    bar: root.bar
    text: " "
    keepSpace: true
    horizontalMargin: 0
    verticalPadding: 0
    tooltipText: root.tooltipText
    onPressed: function(button) {
      if (button === Qt.RightButton) root.openTimezoneMenu()
      else root.toggleFormat()
    }
  }
}
