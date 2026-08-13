import QtQuick
import Quickshell
import "center" as Center

ShellRoot {
  id: root

  property int phase: 0
  property var clickTargets: []

  function fail(message) {
    console.error("center-widget-smoke:", message)
    Qt.exit(1)
  }

  function pillSurface(widget) {
    const children = widget ? widget.children || [] : []
    for (const child of children) {
      if (child && "v1AppearanceEnabled" in child
          && "tokenSource" in child) return child
    }
    return null
  }

  component FakeUpdate: Item {
    property var bar: null
    property string moduleName: ""
    property var settings: ({})
    property bool updateAvailable: true
    property int runCount: 0
    property int refreshCount: 0
    visible: updateAvailable
    implicitWidth: 24
    implicitHeight: 35
    function runUpdate() { runCount++ }
    function refresh() { refreshCount++ }
  }

  Component { id: updateComponent; FakeUpdate {} }

  QtObject {
    id: registry
    property int revision: 1
    property var widgets: ({
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
    property string feelsC: "23"
    property string feelsF: "73"
    property string description: "Clear"
    property string humidity: "54"
    property string windKmh: "12"
    property string windMph: "7"
    property var forecastDays: [
      { date: "2026-07-16", minC: "18", maxC: "27", minF: "64",
        maxF: "81", code: "113", rain: 5 },
      { date: "2026-07-17", minC: "17", maxC: "25", minF: "63",
        maxF: "77", code: "116", rain: 20 }
    ]
    property bool loaded: true
    property bool unavailable: false
    property bool refreshing: false
    function refresh(_force) {}
    function glyphForCode(_code, _night) { return "W" }
  }

  QtObject {
    id: sharedCenter
    property var clock: sharedClock
    property var weather: sharedWeather
  }

  QtObject {
    id: fakeShell
    property int weatherSettingCount: 0
    property color palette01: "#cc3355"
    function serviceFor(id) {
      if (id === "hancore.shibumi.center") return sharedCenter
      if (id === "hancore.shibumi.status") return sharedStatus
      if (id === "hancore.shibumi.state") return fakeShell
      return null
    }
    function setWidgetSetting(group, module, key, value) {
      if (group === "G8" && module === "omarchy.weather"
          && key === "unit" && value === "imperial") weatherSettingCount++
      return true
    }
    function paletteColor(id) {
      return id === "color01" ? palette01 : "#000000"
    }
  }

  Center.Service {
    id: serviceEntryPoint
    runtimeWeatherEnabled: false
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#101214"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var shell: fakeShell
    property var barWidgetRegistry: registry
    property var clickTargets: root.clickTargets
    property int summonCount: 0
    property var visualTokens: ({
      shellStyle: "shibumi",
      v2Shell: false,
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
      mutedInk: "#999999",
      panelRadius: 8,
      panelBackground: "#101214",
      panelBorder: "#454a50",
      panelBorderWidth: 1,
      tileRadius: 6,
      separator: "#353a40",
      fillIdle: "#15181b",
      fillHover: "#20252a",
      fillActive: "#28323b",
      fillPrimaryHover: "#9cc9ed",
      sumi: "#777777",
      sumiHi: "#aaaaaa",
      ink: fakeBar.foreground,
      paper: fakeBar.background,
      widgetHasFill: function(settings) {
        return settings && settings.color === "color01"
      },
      widgetFillColor: function(settings) {
        return settings && settings.color === "color01"
          ? fakeShell.palette01 : "transparent"
      },
      widgetSurfaceOpacity: function(settings) {
        return settings && settings.surfaceOpacity !== undefined
          ? Number(settings.surfaceOpacity) : 1
      },
      widgetContentColor: function(settings, fallback) {
        return settings && settings.color === "color01"
          && settings.tone === "background" ? fakeBar.background : fallback
      }
    })

    function widgetSettings(_group, module) {
      if (module === "omarchy.weather") return ({ unit: "metric" })
      if (module === "omarchy.system-update") return ({ marker: "G8-update" })
      return ({ clock12h: false })
    }
    function setWidgetSetting(_group, _module, _key, _value) { return true }
    function run(_command) {}
    function summonBarWidget(_module, _mode) {
      summonCount++
      return true
    }
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

  Center.BarWidget {
    id: center
    bar: fakeBar
    settings: ({
      color: "color01",
      colorMode: "border",
      tone: "background",
      surfaceOpacity: 0.6
    })
    availableWidth: 500
    calendarSource: Qt.resolvedUrl("CenterTestCalendar.qml")
  }

  Center.BarWidget {
    id: secondCenter
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
            || center.centerService !== secondCenter.centerService
            || center.statusService !== secondCenter.statusService
            || !Qt.colorEqual(center.widgetInk, fakeBar.background)
            || !Qt.colorEqual(secondCenter.widgetInk, fakeBar.foreground)
            || Math.abs(center.dateContentColor.r - fakeBar.background.r) > 0.001
            || Math.abs(center.dateContentColor.g - fakeBar.background.g) > 0.001
            || Math.abs(center.dateContentColor.b - fakeBar.background.b) > 0.001
            || Math.abs(center.dateContentColor.a - 0.5) > 0.001
            || !serviceEntryPoint.clock || !serviceEntryPoint.weather
            || serviceEntryPoint.weather.enabled
            || secondCenter.calendarLoaded
            || !center.weatherWidget || !center.indicatorWidget || !center.updateWidget
            || center.weatherWidget.settings.unit !== "metric"
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
            || !center.updateWidget.activate()
            || !center.updateWidget.refresh()
            || center.updateBackend.runCount !== 1
            || center.updateBackend.refreshCount !== 1
            || fakeBar.summonCount !== 0)
          return root.fail("update facade/backend contract")
        if (center.childPanelWidget("omarchy.weather") !== center.weatherWidget
            || center.childPanelWidget("omarchy.indicators") !== null)
          return root.fail("nested panel routing contract")
        center.weatherWidget.panelSource = Qt.resolvedUrl(
          "WeatherPanelTestView.qml")
        center.weatherWidget.togglePanel()
        if (!center.weatherWidget.opened)
          return root.fail("weather panel contract")
      } else if (root.phase === 1) {
        if (!center.weatherWidget.panelLoaded
            || center.weatherWidget.panelItem.weatherService !== sharedWeather)
          return root.fail("lazy V1 weather panel")
        if (!center.weatherWidget.toggleUnit()
            || fakeShell.weatherSettingCount !== 1)
          return root.fail("weather unit setting contract")
        center.weatherWidget.close()
        center.open()
      } else if (root.phase === 2) {
        if (!center.opened || !center.calendarLoaded
            || !center.calendarLoaderReady || secondCenter.calendarLoaded)
          return root.fail("lazy calendar open")
        center.close()
        center.availableWidth = 80
      } else if (root.phase === 3) {
        if (center.opened || center.calendarLoaded || center.stage !== 2)
          return root.fail("calendar close/minimal stage")
        sharedStatus.notificationsSilenced = true
        sharedStatus.recording = true
        sharedStatus.recordingElapsed = 3661
        sharedStatus.voxtypeActive = true
        sharedStatus.voxtypeState = "recording"
        center.availableWidth = 500
      } else if (root.phase === 4) {
        if (!center.indicatorWidget.hasActive
            || center.indicatorWidget.elapsedText() !== "1:01:01"
            || center.indicatorWidget.idleIconFamily !== center.bar.fontFamily
            || center.indicatorWidget.dndIconFamily !== "Material Symbols Rounded"
            || center.indicatorWidget.recordingIconFamily !== center.bar.fontFamily
            || center.indicatorWidget.recordingIconGlyph !== "󰻂"
            || !center.indicatorWidget.customToneActive
            || secondCenter.indicatorWidget.customToneActive
            || !Qt.colorEqual(center.indicatorWidget.recordingIconColor,
              fakeBar.background)
            || !Qt.colorEqual(secondCenter.indicatorWidget.recordingIconColor,
              fakeShell.palette01)
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
      } else if (root.phase === 5) {
        const surface = root.pillSurface(center)
        if (center.stage !== 0 || center.implicitHeight !== 35
            || !surface || surface.height !== 24
            || Math.abs(surface.y - 6) > 0.01
            || !surface.v1CustomFill
            || surface.renderedSurfaceCount !== 1)
          return root.fail("V1 center pill geometry"
            + " root=" + center.implicitHeight
            + " pill=" + (surface ? surface.height : -1)
            + " y=" + (surface ? surface.y : -1)
            + " fill=" + (surface ? surface.v1CustomFill : false))
        const v2Tokens = ({})
        for (const key in fakeBar.visualTokens)
          v2Tokens[key] = fakeBar.visualTokens[key]
        v2Tokens.shellStyle = "notch"
        v2Tokens.v2Shell = true
        fakeBar.visualTokens = v2Tokens
        fakeBar.barSize = 33
      } else {
        const surface = root.pillSurface(center)
        if (center.implicitHeight !== 33
            || !surface || surface.height !== 24
            || Math.abs(surface.y - 5) > 0.01
            || surface.shellPillVisible
            || surface.renderedSurfaceCount !== 0
            || !surface.customDecorated)
          return root.fail("V2 center pill geometry"
            + " root=" + center.implicitHeight
            + " pill=" + (surface ? surface.height : -1)
            + " y=" + (surface ? surface.y : -1)
            + " shellPill=" + (surface
              ? surface.shellPillVisible : true))
        stop()
        console.log("center plugin smoke passed")
        Qt.quit()
      }
      root.phase++
    }
  }
}
