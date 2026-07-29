pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "CalendarModel.js" as CalendarModel

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var clockService
  property int monthOffset: 0
  property int selectedDay: 0
  readonly property date displayDate: clockService ? clockService.date : new Date()
  readonly property var calendarCells: CalendarModel.cells(displayDate, monthOffset)
  readonly property string monthName: CalendarModel.monthName(displayDate, monthOffset)
  readonly property string calendarYear: CalendarModel.year(displayDate, monthOffset)
  readonly property int renderedDayCount: dayRepeater.count
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property color deepInk: stateService
    && typeof stateService.paletteColor === "function"
    ? stateService.paletteColor("color07") : controlForeground

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  centerOnBar: true
  gap: 8
  padding: 12
  contentWidth: fittedContentWidth(280)
  contentHeight: fittedContentHeight(content.implicitHeight)

  function previousMonth() { monthOffset-- }
  function nextMonth() { monthOffset++ }
  function resetToToday() {
    monthOffset = 0
    selectedDay = displayDate.getDate()
  }

  Component.onCompleted: resetToToday()

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: ownerWidget.close()
    onMoveRequested: function(dx, _dy) {
      if (dx < 0) panel.previousMonth()
      else if (dx > 0) panel.nextMonth()
    }
    onTabRequested: function(direction) {
      panel.ownerWidget.switchPanel(direction)
    }

    Column {
      id: content
      width: parent.width
      spacing: 10

      Item {
        width: parent.width
        height: 24

        CalendarAction {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: "‹"
          tooltipText: "Previous month"
          onClicked: panel.previousMonth()
        }

        Text {
          anchors.centerIn: parent
          text: panel.monthName + "  " + panel.calendarYear
          color: monthMouse.containsMouse && panel.monthOffset !== 0
            ? panel.controlAccent : panel.controlForeground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 12
          font.letterSpacing: 2
          font.weight: Font.Medium
          renderType: Text.NativeRendering

          MouseArea {
            id: monthMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            enabled: panel.monthOffset !== 0
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.resetToToday()
          }
        }

        CalendarAction {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "›"
          tooltipText: "Next month"
          onClicked: panel.nextMonth()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Row {
        width: parent.width

        Repeater {
          model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

          delegate: Item {
            required property string modelData
            required property int index
            width: content.width / 7
            height: 20

            Text {
              anchors.centerIn: parent
              text: modelData
              color: index >= 5 ? panel.controlAccent : panel.deepInk
              opacity: index >= 5 ? 0.85 : 0.7
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: 10
              font.letterSpacing: 2
              renderType: Text.NativeRendering
            }
          }
        }
      }

      Grid {
        columns: 7
        rowSpacing: 2
        columnSpacing: 0
        width: parent.width

        Repeater {
          id: dayRepeater
          model: panel.calendarCells

          delegate: Item {
            id: dayCell
            required property var modelData
            required property int index
            readonly property bool hasDay: modelData.day > 0
            readonly property bool today: modelData.today === true
            readonly property bool selected: hasDay && !today
              && panel.selectedDay === modelData.day && panel.monthOffset === 0
            readonly property bool weekend: index % 7 >= 5
            width: content.width / 7
            height: 28

            Rectangle {
              anchors.centerIn: parent
              width: 24
              height: width
              radius: 12
              visible: dayCell.today
              color: panel.controlAccent
            }

            Rectangle {
              anchors.centerIn: parent
              width: 24
              height: width
              radius: 12
              visible: dayCell.selected
              color: "transparent"
              border.width: 1
              border.color: panel.controlAccent
            }

            Text {
              anchors.centerIn: parent
              text: dayCell.hasDay ? dayCell.modelData.day : ""
              color: dayCell.today
                ? panel.controlAccent.hsvValue < 0.5
                  ? panel.controlForeground : Commons.Color.background
                : dayCell.weekend ? panel.controlAccent : panel.controlForeground
              opacity: dayCell.hasDay ? 1 : 0.35
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: 12
              font.weight: dayCell.today ? Font.Medium : Font.Light
              renderType: Text.NativeRendering
            }

            MouseArea {
              anchors.fill: parent
              enabled: dayCell.hasDay
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: panel.selectedDay = dayCell.modelData.day
            }
          }
        }
      }
    }
  }

  component CalendarAction: Rectangle {
    id: action
    property string iconText: ""
    property string tooltipText: ""
    signal clicked()
    readonly property bool hovered: actionMouse.containsMouse
    width: 24
    height: 24
    radius: panel.controlRadius
    color: "transparent"

    Text {
      anchors.centerIn: parent
      text: action.iconText
      color: action.hovered ? panel.controlAccent : panel.controlMuted
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: 16
      renderType: Text.NativeRendering
      Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: panel.shellStyle !== "shibumi"
        && action.tooltipText !== "" && actionMouse.containsMouse
      text: action.tooltipText
    }
  }
}
