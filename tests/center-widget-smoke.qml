import QtQuick
import Quickshell
import "widgets" as Widgets

ShellRoot {
  id: root

  property int phase: 0
  property var clickTargets: []

  function fail(message) {
    console.error("center-widget-smoke:", message)
    Qt.exit(1)
  }

  component FakeWeather: Item {
    property var bar: null
    property string moduleName: ""
    property var settings: ({})
    property bool opened: false
    implicitWidth: 44
    implicitHeight: 35
    function open() { opened = true }
    function close() { opened = false }
    function togglePanel() { opened = !opened }
    function refresh() {}
  }

  component FakeUpdate: Item {
    property var bar: null
    property string moduleName: ""
    property var settings: ({})
    property bool updateAvailable: true
    property int runCount: 0
    visible: updateAvailable
    implicitWidth: 24
    implicitHeight: 35
    function runUpdate() { runCount++ }
  }

  Component { id: weatherComponent; FakeWeather {} }
  Component { id: updateComponent; FakeUpdate {} }

  QtObject {
    id: registry
    property int revision: 1
    property var widgets: ({
      "omarchy.weather": { component: weatherComponent },
      "omarchy.system-update": { component: updateComponent }
    })
  }

  QtObject {
    id: sharedClock
    property date date: new Date(2026, 6, 16, 13, 5, 0)
  }

  QtObject {
    id: sharedStatus
    property bool stayAwake: true
    property bool notificationsSilenced: false
    property bool recording: false
    property int recordingElapsed: 0
    property bool voxtypeActive: false
    property string voxtypeState: "idle"
    property string voxtypeHint: ""
    property int stopCount: 0
    property int modelCount: 0
    property int configCount: 0
    function toggleStayAwake() { stayAwake = !stayAwake; return true }
    function toggleNotifications() { notificationsSilenced = !notificationsSilenced; return true }
    function stopRecording() { stopCount++; return true }
    function openVoxtypeModel() { modelCount++; return true }
    function openVoxtypeConfig() { configCount++; return true }
  }

  QtObject {
    id: sharedWeather
    property string icon: "W"
    property string place: "Berlin"
    property string tempC: "24"
    property string tempF: "75"
    property string description: "Clear"
    property bool loaded: true
    property bool unavailable: false
    function refresh(_force) {}
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var barWidgetRegistry: registry
    property var clockService: sharedClock
    property var statusService: sharedStatus
    property var weatherService: sharedWeather
    property var clickTargets: root.clickTargets
    property var visualTokens: ({
      pillHeight: 24,
      pillRadius: 12,
      pillPaddingX: 9,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      labelSize: 12,
      captionSize: 10,
      mutedInk: "#999999"
    })

    function widgetSettings(_group, module) {
      if (module === "omarchy.weather") return ({ unit: "C" })
      if (module === "omarchy.system-update") return ({ marker: "G8-update" })
      return ({ clock12h: false })
    }
    function setWidgetSetting(_group, _module, _key, _value) { return true }
    function run(_command) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function registerClickTarget(target) {
      if (root.clickTargets.indexOf(target) < 0)
        root.clickTargets = root.clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      root.clickTargets = root.clickTargets.filter(item => item !== target)
    }
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
  }

  Widgets.CenterWidget {
    id: center
    bar: fakeBar
    availableWidth: 500
    calendarSource: Qt.resolvedUrl("CenterTestCalendar.qml")
  }

  Timer {
    interval: 130
    repeat: true
    running: true
    onTriggered: {
      if (root.phase === 0) {
        if (center.stage !== 0 || center.dateText !== "Thu 16"
            || !center.weatherWidget || !center.indicatorWidget || !center.updateWidget
            || center.weatherWidget.settings.unit !== "C"
            || center.weatherWidget.weatherService !== sharedWeather
            || center.weatherWidget.implicitWidth !== 20
            || center.indicatorWidget.statusService !== sharedStatus
            || center.indicatorWidget.dndOpticalCenterOffset !== 1
            || center.indicatorWidget.implicitWidth <= 0
            || center.updateWidget.settings.marker !== "G8-update"
            || center.updateWidget.moduleName !== "omarchy.system-update"
            || center.updateWidget.implicitWidth !== 20
            || center.updateWidget.opticalCenterOffset !== 1
            || center.weatherWidget.implicitWidth
              !== center.updateWidget.implicitWidth)
          return root.fail("center children/settings/presentation"
            + " stage=" + center.stage
            + " date=" + center.dateText
            + " weather=" + Boolean(center.weatherWidget)
            + " indicator=" + Boolean(center.indicatorWidget)
            + " update=" + Boolean(center.updateWidget)
            + " indicatorWidth=" + (center.indicatorWidget
              ? center.indicatorWidget.implicitWidth : -1)
            + " hasActive=" + (center.indicatorWidget
              ? center.indicatorWidget.hasActive : false)
            + " updateModule=" + (center.updateWidget
              ? center.updateWidget.moduleName : "missing"))
        if (!center.updateBackend
            || center.updateBackend.settings.marker !== "G8-update"
            || center.updateWidget.backendWidget !== center.updateBackend
            || center.updateWidget.tooltipText !== "Omarchy update available"
            || center.updateWidget.iconFamily !== "Material Symbols Rounded"
            || center.updateWidget.width <= 0
            || center.updateWidget.height <= 0
            || !center.updateWidget.interactionTarget
            || center.updateWidget.interactionTarget.width <= 0
            || center.updateWidget.interactionTarget.height <= 0
            || !center.updateWidget.activate()
            || center.updateBackend.runCount !== 1)
          return root.fail("update facade/backend contract")
        if (center.childPanelWidget("omarchy.weather") !== center.weatherWidget
            || center.childPanelWidget("omarchy.clock") !== center
            || center.childPanelWidget("omarchy.indicators") !== null)
          return root.fail("nested panel routing contract")
        center.weatherWidget.panelSource = Qt.resolvedUrl(
          "WeatherPanelTestView.qml")
        center.weatherWidget.togglePanel()
        if (!center.weatherWidget.opened)
          return root.fail("weather panel contract")
        center.open()
      } else if (root.phase === 1) {
        if (!center.weatherWidget.panelLoaded
            || center.weatherWidget.panelItem.weatherService !== sharedWeather)
          return root.fail("lazy weather panel")
        if (!center.opened || !center.calendarLoaded
            || !center.calendarLoaderReady)
          return root.fail("lazy calendar open")
        center.weatherWidget.close()
        center.close()
        center.availableWidth = 80
      } else if (root.phase === 2) {
        if (center.opened || center.calendarLoaded || center.stage !== 2)
          return root.fail("calendar close/minimal stage")
        sharedStatus.notificationsSilenced = true
        sharedStatus.recording = true
        sharedStatus.recordingElapsed = 3661
        sharedStatus.voxtypeActive = true
        sharedStatus.voxtypeState = "recording"
        center.availableWidth = 500
      } else if (root.phase === 3) {
        if (!center.indicatorWidget.hasActive
            || center.indicatorWidget.elapsedText() !== "1:01:01"
            || center.indicatorWidget.idleIconFamily !== center.bar.fontFamily
            || center.indicatorWidget.dndIconFamily !== "Material Symbols Rounded"
            || center.indicatorWidget.recordingIconFamily !== center.bar.fontFamily
            || center.indicatorWidget.recordingIconGlyph !== "󰻂"
            || center.indicatorWidget.recordingIconColor !== center.bar.urgent
            || center.indicatorWidget.voxtypeIconFamily !== "Material Symbols Rounded"
            || !center.indicatorWidget.toggleStayAwake()
            || sharedStatus.stayAwake
            || !center.indicatorWidget.toggleNotifications()
            || sharedStatus.notificationsSilenced
            || !center.indicatorWidget.stopRecording()
            || !center.indicatorWidget.activateVoxtype(Qt.LeftButton)
            || !center.indicatorWidget.activateVoxtype(Qt.RightButton)
            || sharedStatus.stopCount !== 1
            || sharedStatus.modelCount !== 1
            || sharedStatus.configCount !== 1)
          return root.fail("status indicator state/action contract")
        sharedStatus.recording = false
        sharedStatus.voxtypeActive = false
        sharedStatus.voxtypeState = "idle"
      } else {
        if (center.stage !== 0 || center.implicitHeight !== 35)
          return root.fail("normal stage restore/geometry")
        stop()
        console.log("center widget smoke passed")
        Qt.quit()
      }
      root.phase++
    }
  }
}
