pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var weatherService

  readonly property bool useImperial: ownerWidget.useImperial === true
  readonly property var forecastDays: weatherService
    && weatherService.forecastDays ? weatherService.forecastDays : []
  readonly property color primaryTextColor: shibumiTokens
    && shibumiTokens.paper !== undefined
    ? shibumiTokens.paper : renderedSurfaceColor

  owner: ownerWidget
  open: ownerWidget.panelOpen && weatherService !== null
  focusTarget: keyCatcher
  centerOnBar: true
  centerOnBarOffset: 1
  gap: 8
  padding: 12
  contentWidth: fittedContentWidth(300)
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    520)

  function closePanel() {
    ownerWidget.close()
  }

  function refresh() {
    if (weatherService && typeof weatherService.refresh === "function")
      weatherService.refresh(true)
  }

  function dayLabel(dateString, index) {
    if (index === 0) return "Today"
    if (index === 1) return "Tomorrow"
    const date = new Date(String(dateString || "") + "T00:00:00")
    if (isNaN(date.getTime())) return String(dateString || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()]
  }

  function dayRange(day) {
    if (!day) return ""
    const minimum = useImperial ? day.minF : day.minC
    const maximum = useImperial ? day.maxF : day.maxC
    return minimum + "°/" + maximum + "°" + (useImperial ? "F" : "C")
  }

  function feelsText() {
    if (!weatherService) return ""
    const value = useImperial ? weatherService.feelsF : weatherService.feelsC
    return value === "" ? "" : value + "°" + (useImperial ? "F" : "C")
  }

  function windText() {
    if (!weatherService) return ""
    const value = useImperial ? weatherService.windMph : weatherService.windKmh
    return value === "" ? "" : value + (useImperial ? " mph" : " km/h")
  }

  onOpenChanged: if (open && weatherService && !weatherService.loaded) refresh()

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.closePanel()
    onTabRequested: function(direction) {
      if (panel.ownerWidget
          && typeof panel.ownerWidget.switchPanel === "function")
        panel.ownerWidget.switchPanel(direction)
    }

      Column {
        id: contentColumn
        width: parent.width
        spacing: 8

      Item {
        width: parent.width
        height: 24

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Weather"
          color: panel.controlForeground
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 13
          font.letterSpacing: 2
          font.weight: Font.Medium
          renderType: Text.NativeRendering
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: panel.shellStyle === "shibumi"
          text: "\u2715"
          color: closeMouse.containsMouse
            ? panel.controlAccent : panel.controlMuted
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 12
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 120 } }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.closePanel()
          }
        }

        IconAction {
          icon: "close"
          tooltip: "Close"
          visible: panel.shellStyle !== "shibumi"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          onClicked: panel.closePanel()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Item {
        width: parent.width
        height: 36

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: panel.weatherService && panel.weatherService.loaded
            ? panel.ownerWidget.temperature + panel.ownerWidget.unitSuffix : "—"
          color: panel.controlAccent
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 26
          font.weight: Font.Medium
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width * 0.55
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: panel.weatherService
            ? panel.weatherService.description : ""
          color: panel.controlForeground
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 11
          horizontalAlignment: Text.AlignRight
          wrapMode: Text.WordWrap
          renderType: Text.NativeRendering
        }
      }

      Column {
        width: parent.width
        spacing: 4

        Row {
          width: parent.width
          visible: panel.weatherService
            && panel.weatherService.place !== ""

          Text {
            width: parent.width * 0.4
            text: "Location"
            color: panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
          Text {
            width: parent.width * 0.6
            text: panel.weatherService ? panel.weatherService.place : ""
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }
        }

        Row {
          width: parent.width
          visible: panel.feelsText() !== ""

          Text {
            width: parent.width * 0.4
            text: "Feels like"
            color: panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
          Text {
            text: panel.feelsText()
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
        }

        Row {
          width: parent.width
          visible: panel.weatherService
            && panel.weatherService.humidity !== ""

          Text {
            width: parent.width * 0.4
            text: "Humidity"
            color: panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
          Text {
            text: panel.weatherService
              ? panel.weatherService.humidity + "%" : ""
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
        }

        Row {
          width: parent.width
          visible: panel.windText() !== ""

          Text {
            width: parent.width * 0.4
            text: "Wind"
            color: panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
          Text {
            text: panel.windText()
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Column {
        id: forecastColumn
        width: parent.width
        spacing: 5
        visible: panel.forecastDays.length > 0

        Text {
          text: "3-DAY FORECAST"
          color: panel.controlMutedHigh
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 10
          font.letterSpacing: 1
          renderType: Text.NativeRendering
        }

        Repeater {
          model: panel.forecastDays

          delegate: Item {
            id: forecastRow
            required property var modelData
            required property int index

            width: forecastColumn.width
            height: 24

            Text {
              width: 66
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: panel.dayLabel(forecastRow.modelData.date,
                forecastRow.index)
              color: panel.controlForeground
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: 11
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 76
              anchors.verticalCenter: parent.verticalCenter
              text: panel.weatherService.glyphForCode(
                forecastRow.modelData.code, false)
              color: panel.controlAccent
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: 14
              renderType: Text.NativeRendering
            }

            Text {
              width: 76
              anchors.left: parent.left
              anchors.leftMargin: 106
              anchors.verticalCenter: parent.verticalCenter
              text: panel.dayRange(forecastRow.modelData)
              color: panel.controlForeground
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: 11
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              width: 76
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(Number(forecastRow.modelData.rain || 0))
                + "% rain"
              color: panel.controlMutedHigh
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: 10
              horizontalAlignment: Text.AlignRight
              renderType: Text.NativeRendering
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        visible: forecastColumn.visible
        color: panel.dividerColor
      }

      Row {
        width: parent.width
        height: 28
        spacing: 6

        Rectangle {
          width: (parent.width - parent.spacing) / 2
          height: parent.height
          radius: panel.controlRadius
          color: panel.weatherService && panel.weatherService.refreshing
            ? panel.controlActiveFillColor
            : refreshMouse.containsMouse
              ? panel.controlPrimaryHoverColor : panel.controlAccent

          Text {
            anchors.centerIn: parent
            text: panel.weatherService && panel.weatherService.refreshing
              ? "Refreshing\u2026" : "Refresh"
            color: panel.primaryTextColor
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }

          MouseArea {
            id: refreshMouse
            anchors.fill: parent
            enabled: !(panel.weatherService
              && panel.weatherService.refreshing)
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.refresh()
          }
        }

        Rectangle {
          width: (parent.width - parent.spacing) / 2
          height: parent.height
          radius: panel.controlRadius
          color: unitMouse.containsMouse
            ? panel.controlHoverFillColor : panel.controlFillColor
          border.width: panel.controlBorderWidth
          border.color: unitMouse.containsMouse
            ? panel.controlHoverBorderColor : panel.controlBorderColor

          Text {
            anchors.centerIn: parent
            text: panel.useImperial ? "metric" : "imperial"
            color: unitMouse.containsMouse
              ? panel.controlAccent : panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }

          MouseArea {
            id: unitMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.ownerWidget.toggleUnit()
          }
        }
      }
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

    IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
