pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui as Ui
import "WeatherLocationModel.js" as WeatherLocationModel

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
  readonly property string configuredLocationName: {
    const location = weatherService && weatherService.configuredLocation
      ? weatherService.configuredLocation : null
    return location ? String(location.name || "").trim() : ""
  }
  readonly property string displayLocation: configuredLocationName
    || (weatherService ? String(weatherService.place || "") : "")
  property bool editingLocation: false
  property bool savingLocation: false
  property bool locationInputReady: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string locationError: ""
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""
  property string geocodeOutput: ""
  readonly property string geocodeLanguage: "de"
  property alias locationEditorText: locationField.text
  readonly property bool locationCanCommit: editingLocation
    && locationInputReady && !savingLocation && !geocodeProc.running
    && locationSuggestions.length > 0
    && geocodeActiveQuery === locationField.text.trim()

  owner: ownerWidget
  open: ownerWidget.panelOpen && weatherService !== null
  focusTarget: keyCatcher
  centerOnBar: true
  centerOnBarOffset: 1
  padding: 12
  contentWidth: fittedContentWidth(300)
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    520)

  function closePanel() {
    if (savingLocation) return
    if (editingLocation) cancelEditingLocation()
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

  function startEditingLocation() {
    if (savingLocation) return
    locationInputReady = false
    locationError = ""
    locationSuggestions = []
    suggestionIndex = 0
    locationField.text = configuredLocationName
    editingLocation = true
    Qt.callLater(function() {
      if (!panel.editingLocation) return
      locationField.selectAll()
      locationField.forceActiveFocus()
      Qt.callLater(function() {
        if (panel.editingLocation) panel.locationInputReady = true
      })
    })
  }

  function cancelEditingLocation() {
    if (savingLocation) return
    locationInputReady = false
    editingLocation = false
    locationSuggestions = []
    locationError = ""
    geocodePendingQuery = ""
    geocodeDebounce.stop()
    Qt.callLater(function() {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function commitLocation() {
    if (savingLocation) return false
    const query = locationField.text.trim()
    if (query.length < 2) {
      locationError = "Enter at least 2 characters"
      return false
    }
    if (!WeatherLocationModel.isMeaningfulQuery(query)) {
      locationError = "No matching location"
      locationSuggestions = []
      return false
    }
    if (geocodeProc.running || geocodePendingQuery !== query
        || geocodeActiveQuery !== query) {
      locationError = "Searching…"
      requestGeocode()
      return false
    }
    if (locationSuggestions.length === 0) {
      locationError = "No matching location"
      return false
    }
    const location = WeatherLocationModel.locationCommit(locationField.text,
      locationSuggestions, suggestionIndex)
    persistLocation(location.name, location.latitude, location.longitude)
    return true
  }

  function pickSuggestion(suggestion) {
    if (!suggestion || savingLocation) return
    persistLocation(suggestion.name, suggestion.latitude,
      suggestion.longitude)
  }

  function clearLocation() {
    if (savingLocation) return
    persistLocation("", null, null)
  }

  function persistLocation(name, latitude, longitude) {
    if (locationSaveProc.running) return
    savingLocation = true
    locationError = ""
    if (name && latitude !== null && longitude !== null) {
      locationSaveProc.command = ["omarchy-weather-location", "--set",
        String(name), latitude + "," + longitude]
    } else if (name) {
      locationSaveProc.command = ["omarchy-weather-location", "--set",
        String(name)]
    } else {
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    }
    locationSaveProc.running = true
  }

  function requestGeocode() {
    const query = locationField.text.trim()
    if (query.length < 2) {
      geocodePendingQuery = ""
      locationSuggestions = []
      return
    }
    if (!WeatherLocationModel.isMeaningfulQuery(query)) {
      geocodePendingQuery = ""
      locationSuggestions = []
      locationError = "No matching location"
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    if (!editingLocation || savingLocation || geocodeProc.running
        || geocodePendingQuery.length < 2) return
    geocodeActiveQuery = geocodePendingQuery
    geocodeOutput = ""
    locationError = ""
    geocodeProc.command = ["curl", "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name="
        + encodeURIComponent(geocodeActiveQuery)
        + "&count=5&language=" + panel.geocodeLanguage + "&format=json"]
    geocodeProc.running = true
  }

  function locationEditorContainsPoint(x, y) {
    const local = locationEditor.mapFromItem(keyCatcher, x, y)
    return local.x >= 0 && local.x <= locationEditor.width
      && local.y >= 0 && local.y <= locationEditor.height
  }

  function dismissLocationEditorAt(x, y) {
    if (!editingLocation || savingLocation
        || locationEditorContainsPoint(x, y)) return false
    cancelEditingLocation()
    return true
  }

  onOpenChanged: {
    if (open && weatherService && !weatherService.loaded) refresh()
    if (!open && editingLocation && !savingLocation) cancelEditingLocation()
  }

  property Process geocodeProcess: Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: panel.geocodeOutput = String(text || "")
    }
    onExited: function(exitCode) {
      const currentQuery = locationField.text.trim()
      if (exitCode === 0 && panel.editingLocation
          && currentQuery === panel.geocodeActiveQuery) {
        panel.locationSuggestions =
          WeatherLocationModel.parseGeocodingResults(panel.geocodeOutput,
            panel.geocodeActiveQuery)
        panel.suggestionIndex = 0
        if (panel.locationSuggestions.length === 0)
          panel.locationError = "No matching location"
      } else if (exitCode !== 0 && panel.editingLocation
          && currentQuery === panel.geocodeActiveQuery) {
        panel.locationSuggestions = []
        panel.locationError = "Location search unavailable"
      }
      if (panel.editingLocation && !panel.savingLocation
          && panel.geocodePendingQuery !== panel.geocodeActiveQuery)
        Qt.callLater(function() { panel.startGeocode() })
    }
  }

  property Timer geocodeDebounceTimer: Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: panel.requestGeocode()
  }

  property Process locationSaveProcess: Process {
    id: locationSaveProc
    onExited: function(exitCode) {
      if (!panel.savingLocation) return
      panel.savingLocation = false
      if (exitCode !== 0) {
        panel.locationError = "Could not save location"
        return
      }
      if (panel.weatherService
          && typeof panel.weatherService.reloadLocation === "function")
        panel.weatherService.reloadLocation()
      panel.refresh()
      panel.cancelEditingLocation()
    }
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: panel.editingLocation
    onReturnRequested: panel.startEditingLocation()
    onCloseRequested: panel.closePanel()
    onTabRequested: function(direction) {
      if (panel.ownerWidget
          && typeof panel.ownerWidget.switchPanel === "function")
        panel.ownerWidget.switchPanel(direction)
    }

    TapHandler {
      enabled: panel.editingLocation && !panel.savingLocation
      acceptedButtons: Qt.LeftButton
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onTapped: function(eventPoint, _button) {
        panel.dismissLocationEditorAt(
          eventPoint.position.x, eventPoint.position.y)
      }
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

        Item {
          id: locationDisplay
          width: parent.width
          height: visible ? 24 : 0
          visible: !panel.editingLocation
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: "Change weather location"

          Keys.onReturnPressed: panel.startEditingLocation()
          Keys.onEnterPressed: panel.startEditingLocation()
          Keys.onSpacePressed: panel.startEditingLocation()

          Rectangle {
            id: locationHoverSurface
            x: -4
            width: parent.width + 8
            height: parent.height
            radius: panel.controlRadius
            color: locationDisplay.activeFocus
              || locationMouse.containsMouse
              ? panel.controlHoverFillColor : "transparent"
            border.width: locationDisplay.activeFocus
              ? panel.controlBorderWidth : 0
            border.color: panel.controlAccent
          }

          Text {
            width: parent.width * 0.4
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Location"
            color: panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: parent.width * 0.4
            anchors.right: locationEditIcon.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: panel.displayLocation !== ""
              ? panel.displayLocation : "Automatic"
            color: locationMouse.containsMouse || locationDisplay.activeFocus
              ? panel.controlAccent : panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }

          IconText {
            id: locationEditIcon
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: "edit_location_alt"
            color: locationMouse.containsMouse || locationDisplay.activeFocus
              ? panel.controlAccent : panel.controlMutedHigh
            font.pixelSize: 14
          }

          MouseArea {
            id: locationMouse
            anchors.fill: locationHoverSurface
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.startEditingLocation()
          }
        }

        Column {
          id: locationEditor
          width: parent.width
          height: visible ? implicitHeight : 0
          visible: panel.editingLocation
          spacing: 4

          Row {
            width: parent.width
            height: 28
            spacing: 4

            TextField {
              id: locationField
              width: parent.width - saveLocationAction.width
                - autoLocationAction.width - parent.spacing * 2
              height: parent.height
              enabled: !panel.savingLocation
              placeholderText: "Search city"
              color: panel.controlForeground
              placeholderTextColor: panel.controlMuted
              selectionColor: panel.controlAccent
              selectedTextColor: panel.primaryTextColor
              selectByMouse: true
              leftPadding: 4
              rightPadding: 4
              topPadding: 3
              bottomPadding: 3
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: 11

              background: Rectangle {
                radius: panel.controlRadius
                color: locationField.activeFocus
                  ? panel.controlHoverFillColor : panel.controlFillColor
                border.width: panel.controlBorderWidth
                border.color: locationField.activeFocus
                  ? panel.controlHoverBorderColor : panel.controlBorderColor

                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on border.color { ColorAnimation { duration: 100 } }
              }

              onTextChanged: {
                if (!panel.editingLocation || panel.savingLocation) return
                panel.locationSuggestions = []
                panel.suggestionIndex = 0
                panel.locationError = ""
                geocodeDebounce.restart()
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  panel.cancelEditingLocation()
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  if (panel.suggestionIndex
                      < panel.locationSuggestions.length - 1)
                    panel.suggestionIndex++
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  if (panel.suggestionIndex > 0) panel.suggestionIndex--
                  event.accepted = true
                } else if (event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter) {
                  if (panel.locationInputReady) panel.commitLocation()
                  event.accepted = true
                }
              }
            }

            PanelButton {
              id: saveLocationAction
              width: 28
              height: parent.height
              label: panel.savingLocation ? "…" : "✓"
              accessibleName: "Save weather location"
              enabled: panel.locationCanCommit
              onClicked: panel.commitLocation()
            }

            PanelButton {
              id: autoLocationAction
              width: 48
              height: parent.height
              label: "AUTO"
              accessibleName: "Use automatic weather location"
              enabled: !panel.savingLocation
              onClicked: panel.clearLocation()
            }
          }

          Column {
            width: parent.width
            height: visible ? implicitHeight : 0
            visible: !panel.savingLocation
              && panel.locationSuggestions.length > 0
            spacing: 0

            Repeater {
              model: panel.locationSuggestions

              delegate: Rectangle {
                id: suggestion
                required property var modelData
                required property int index

                width: parent.width
                height: 28
                radius: panel.controlRadius
                color: index === panel.suggestionIndex
                  ? panel.controlHoverFillColor : "transparent"
                border.width: index === panel.suggestionIndex
                  ? panel.controlBorderWidth : 0
                border.color: panel.controlHoverBorderColor

                Text {
                  id: suggestionName
                  width: 104
                  anchors.left: parent.left
                  anchors.leftMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(suggestion.modelData.name || "")
                  color: suggestion.index === panel.suggestionIndex
                    ? panel.controlAccent : panel.controlForeground
                  font.family: panel.bar ? panel.bar.fontFamily
                    : Commons.Style.font.family
                  font.pixelSize: 11
                  elide: Text.ElideRight
                  renderType: Text.NativeRendering
                }

                Text {
                  anchors.left: suggestionName.right
                  anchors.leftMargin: 8
                  anchors.right: parent.right
                  anchors.rightMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(suggestion.modelData.description || "")
                  color: panel.controlMutedHigh
                  font.family: panel.bar ? panel.bar.fontFamily
                    : Commons.Style.font.family
                  font.pixelSize: 10
                  elide: Text.ElideRight
                  renderType: Text.NativeRendering
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: panel.suggestionIndex = suggestion.index
                  onClicked: panel.pickSuggestion(suggestion.modelData)
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: panel.savingLocation || geocodeProc.running
              || panel.locationError !== ""
            text: panel.savingLocation ? "Saving location…"
              : geocodeProc.running ? "Searching…" : panel.locationError
            color: panel.locationError !== ""
              ? panel.controlAccent : panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 10
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

  component PanelButton: Rectangle {
    id: button

    property string label: ""
    property string accessibleName: label
    signal clicked()
    readonly property bool hovered: buttonMouse.containsMouse && enabled
    readonly property bool highlighted: hovered || activeFocus

    activeFocusOnTab: enabled
    radius: panel.controlRadius
    color: highlighted
      ? panel.controlHoverFillColor : panel.controlFillColor
    border.width: panel.controlBorderWidth
    border.color: highlighted
      ? panel.controlHoverBorderColor : panel.controlBorderColor
    opacity: enabled ? 1 : 0.42
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    Keys.onReturnPressed: if (enabled) button.clicked()
    Keys.onEnterPressed: if (enabled) button.clicked()
    Keys.onSpacePressed: if (enabled) button.clicked()
    Keys.onEscapePressed: panel.cancelEditingLocation()

    Text {
      anchors.centerIn: parent
      width: parent.width - 8
      text: button.label
      color: button.highlighted
        ? panel.controlAccent : panel.controlForeground
      font.family: panel.bar ? panel.bar.fontFamily
        : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      enabled: button.enabled
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: button.clicked()
    }
  }
}
