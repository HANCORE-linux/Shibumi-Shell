pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "CenterLayout.js" as CenterLayout
import "CalendarModel.js" as CalendarModel

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.center"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }
  property url calendarSource: Qt.resolvedUrl("CalendarPanel.qml")
  property real availableWidth: 0
  // Start conservatively when the widget is recreated after a provider
  // switch. Starting at the widest stage can make the outer bar hide G9/G10
  // before this widget receives its real center budget, creating a coupled
  // hysteresis trap. A genuinely roomy center expands to stage 0 on the first
  // measured update.
  property int stage: 1
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.foreground : Commons.Color.foreground)
    : (bar ? bar.foreground : Commons.Color.foreground)
  readonly property bool v1CustomToneActive: !!(tokens
    && tokens.v2Shell !== true
    && typeof tokens.widgetHasFill === "function"
    && tokens.widgetHasFill(settings))
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  property var centerService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.center") : null
  property var statusService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.status") : null
  readonly property var clock: centerService ? centerService.clock : null
  readonly property var weather: centerService ? centerService.weather : null
  readonly property date displayDate: clock ? clock.date : new Date()
  readonly property string dateText: CalendarModel.dateLabel(displayDate)
  readonly property bool centered: availableWidth > 0
  readonly property bool showWeather: displayMode === "full" && stage <= 1
  readonly property bool showDate: displayMode === "full" && stage === 0
  readonly property real weatherNaturalWidth: weatherView.implicitWidth
  readonly property real indicatorNaturalWidth: statusIndicators.implicitWidth
  readonly property real updateNaturalWidth: updateView.implicitWidth
  readonly property bool showIndicators: displayMode === "full"
    && (indicatorNaturalWidth > 0.5 || updateNaturalWidth > 0.5)
  readonly property real statusNaturalWidth: indicatorNaturalWidth
    + updateNaturalWidth
    + (indicatorNaturalWidth > 0.5 && updateNaturalWidth > 0.5 ? Commons.Style.space(8) : 0)
  readonly property real centerPadding: tokens ? tokens.pillPaddingX : 9
  readonly property real centerSpacing: Commons.Style.space(8)
  readonly property real needMinimal: 2 * centerPadding + clockWidget.implicitWidth
    + (showIndicators ? centerSpacing + statusNaturalWidth : 0)
  readonly property real minimumResponsiveWidth: needMinimal
  readonly property real needCompact: needMinimal
    + (weatherNaturalWidth > 0.5 ? centerSpacing + weatherNaturalWidth : 0)
  readonly property real needNormal: needCompact
    + (dateButton.implicitWidth > 0.5 ? centerSpacing + dateButton.implicitWidth : 0)
  readonly property var weatherWidget: weatherView
  readonly property var indicatorWidget: statusIndicators
  readonly property var updateWidget: updateView
  readonly property var updateBackend: updateLoader.item
  readonly property color dateContentColor: dateButton.foreground
  readonly property bool calendarLoaded: calendarLoader.item !== null
  readonly property bool calendarLoaderReady: calendarLoader.item
    ? calendarLoader.item.ready === true : false
  readonly property var weatherSettings: childSettings("omarchy.weather")
  readonly property var clockSettings: childSettings("omarchy.clock")
  readonly property var updateSettings: childSettings("omarchy.system-update")
  readonly property url updateSource: registeredSource("omarchy.system-update")
  property Component updateComponent: String(updateSource) ? null
    : registeredComponent("omarchy.system-update")

  implicitWidth: bar && bar.vertical ? bar.barSize
    : Math.round(centerRow.implicitWidth) + 2 * centerPadding
  implicitHeight: bar ? bar.barSize : Commons.Style.space(35)

  function childSettings(id) {
    if (bar && typeof bar.widgetSettings === "function")
      return bar.widgetSettings("G8", id)
    return settings && settings[id] && typeof settings[id] === "object"
      ? settings[id] : ({})
  }

  function registeredComponent(id) {
    if (bar && typeof bar.registeredWidgetComponent === "function")
      return bar.registeredWidgetComponent(id)
    const registry = bar ? bar.barWidgetRegistry : null
    if (registry) void(registry.revision)
    const widgets = registry && registry.widgets ? registry.widgets : ({})
    const entry = widgets[id]
    return entry ? entry.component : null
  }

  function registeredSource(id) {
    if (bar && typeof bar.registeredWidgetSource === "function")
      return bar.registeredWidgetSource(id)
    const registry = bar && bar.shell
      && "pluginRegistry" in bar.shell ? bar.shell.pluginRegistry : null
    const pluginManifest = registry && registry.installedPlugins
      ? registry.installedPlugins[String(id || "")] : null
    return registry && typeof registry.entryPointUrl === "function"
      ? registry.entryPointUrl(pluginManifest, "barWidget") : ""
  }

  function syncOfficialLoader(loader, component, source, id, childSettingsValue) {
    loader.sourceComponent = null
    loader.source = ""
    if (component !== null) {
      loader.sourceComponent = component
    } else if (String(source)) {
      loader.setSource(source, {
        bar: root.bar,
        moduleName: id,
        settings: childSettingsValue
      })
    }
  }

  function syncUpdateLoader() {
    syncOfficialLoader(updateLoader, updateComponent, updateSource,
      "omarchy.system-update", updateSettings)
  }

  function injectChild(item, id, childSettingsValue) {
    if (!item) return
    if ("bar" in item) item.bar = bar
    if ("moduleName" in item) item.moduleName = id
    if ("settings" in item) item.settings = childSettingsValue
  }

  function injectChildren() {
    injectChild(updateLoader.item, "omarchy.system-update", updateSettings)
  }

  function scheduleOfficialSync() {
    officialSyncTimer.restart()
  }

  function childPanelWidget(pluginId) {
    const id = String(pluginId || "")
    if (id === "omarchy.clock") return root
    if (id === "omarchy.weather") return weatherView
    return null
  }

  function updateStage() {
    stage = CenterLayout.nextStage(stage, availableWidth,
      needNormal, needCompact, centered)
  }

  function syncCalendarLoader() {
    if (!opened) {
      calendarLoader.source = ""
      return
    }
    calendarLoader.setSource(calendarSource, {
      anchorItem: dateButton,
      bar: root.bar,
      ownerWidget: root,
      clockService: root.clock
    })
  }

  onOpenedChanged: syncCalendarLoader()
  onBarChanged: scheduleOfficialSync()
  onUpdateSettingsChanged: injectChildren()
  onUpdateComponentChanged: scheduleOfficialSync()
  onUpdateSourceChanged: scheduleOfficialSync()
  onAvailableWidthChanged: restageTimer.restart()
  onNeedNormalChanged: restageTimer.restart()
  onNeedCompactChanged: restageTimer.restart()
  Component.onCompleted: {
    restageTimer.restart()
    scheduleOfficialSync()
  }

  Timer {
    id: restageTimer
    interval: 80
    onTriggered: root.updateStage()
  }

  Timer {
    id: officialSyncTimer
    interval: 0
    onTriggered: {
      root.syncUpdateLoader()
      root.injectChildren()
    }
  }

  PillSurface {
    tokenSource: root.tokens
    bar: root.bar
    settings: root.settings
    v1AppearanceEnabled: true
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: root.tokens ? root.tokens.pillHeight : 0
  }

  Row {
    id: centerRow
    anchors.centerIn: parent
    spacing: root.centerSpacing

    Item {
      id: weatherHolder
      visible: width > 0.5
      width: root.showWeather ? root.weatherNaturalWidth : 0
      height: root.implicitHeight
      clip: true
      opacity: root.showWeather ? 1 : 0

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      WeatherWidget {
        id: weatherView
        anchors.centerIn: parent
        bar: root.bar
        settings: root.weatherSettings
        weatherService: root.weather
        contentColor: root.widgetInk
      }
    }

    ClockWidget {
      id: clockWidget
      visible: root.displayMode !== "icon"
      bar: root.bar
      settings: root.clockSettings
      clockService: root.clock
      contentColor: root.widgetInk
    }

    IconText {
      visible: root.displayMode === "icon"
      anchors.verticalCenter: parent.verticalCenter
      text: "schedule"
      color: root.widgetInk
      font.pixelSize: root.tokens && root.tokens.iconSize !== undefined
        ? root.tokens.iconSize : 14
      font.weight: Font.Medium
    }

    Item {
      id: dateHolder
      visible: width > 0.5
      width: root.showDate ? dateButton.implicitWidth : 0
      height: root.implicitHeight
      clip: true
      opacity: root.showDate ? 1 : 0

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      Ui.WidgetButton {
        id: dateButton
        anchors.centerIn: parent
        bar: root.bar
        text: root.dateText
        fontFamily: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        fontSize: root.tokens ? root.tokens.captionSize : 10
        foreground: Commons.Util.alpha(root.widgetInk, 0.5)
        horizontalMargin: 0
        verticalPadding: 0
        fixedHeight: root.implicitHeight
        tooltipText: Qt.formatDate(root.displayDate, "dddd, d MMMM yyyy")
        onPressed: function(button) {
          if (button === Qt.RightButton && root.bar) root.bar.run("omarchy-menu-timezone")
          else root.toggle()
        }
      }
    }

    Item {
      id: indicatorHolder
      visible: root.showIndicators || width > 0.5
      width: root.showIndicators ? root.statusNaturalWidth : 0
      height: root.implicitHeight
      clip: true
      opacity: root.showIndicators ? 1 : 0

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      Row {
        anchors.centerIn: parent
        spacing: Commons.Style.space(8)

        StatusIndicators {
          id: statusIndicators
          width: implicitWidth
          height: root.implicitHeight
          bar: root.bar
          statusService: root.statusService
          contentColor: root.widgetInk
          customToneActive: root.v1CustomToneActive
        }

        SystemUpdateWidget {
          id: updateView
          bar: root.bar
          settings: root.updateSettings
          backendWidget: updateLoader.item
          contentColor: root.widgetInk
        }
      }
    }
  }

  Loader {
    id: updateLoader
    visible: false
    onLoaded: {
      root.injectChild(item, "omarchy.system-update", root.updateSettings)
    }
  }

  Loader { id: calendarLoader }
}
