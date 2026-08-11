pragma ComponentBehavior: Bound

import QtQuick
import "core" as Core
import "styles/shibumi" as ShibumiStyle

Item {
  id: host

  signal ready()
  signal finished(string result)

  property bool externalMode: false
  property bool requestedV2: false
  property bool requestedEditing: false
  property bool requestedVertical: false
  property bool readyEmitted: false
  property int phase: 0
  property int attempts: 0
  property int cycleMode: 0
  property int cycleIndex: 0
  property bool cycleUnloaded: false
  property var activeSession: sessionA
  property var currentGroups: baseGroups
  readonly property var baseGroups: [
    "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8"
  ]
  readonly property int targetCount: activeSession
    ? activeSession.targets.length : 0

  width: 720
  height: 80

  function trace(event, detail) {
    console.log("INC012_EVENT " + event + " " + String(detail || ""))
  }

  function fail(message) {
    matrixTimer.stop()
    console.error("INC012_HARNESS_ERROR " + message)
    finished("failed:" + message)
  }

  function setGroups(values) {
    const copy = values.slice()
    currentGroups = copy
    fakeController.order = ({ left: copy, center: [], right: [] })
    fakeController.v1Slots = ({ left: copy, center: [], right: [] })
    fakeController.v2Slots = ({ left: copy, center: [], right: [] })
  }

  function configureVariant(v2, editing) {
    fakeController.v2Mode = v2 === true
    sessionA.setEditing(editing === true)
    sessionB.setEditing(editing === true)
  }

  function groupLocation(groupId) {
    const index = currentGroups.indexOf(String(groupId || ""))
    return index >= 0
      ? ({ region: "left", index: index, groupId: String(groupId) }) : null
  }

  Component {
    id: markerWidget

    Item {
      property var bar: null
      property string moduleName: ""
      property string hostGroupId: ""
      property var settings: ({})
      property real availableWidth: 0
      implicitWidth: 30
      implicitHeight: 20
      visible: true
    }
  }

  QtObject {
    id: fakeResolver
    property int revision: 0
    function ensureComponent(moduleName) {
      return moduleName ? markerWidget : null
    }
  }

  QtObject {
    id: fakePluginRegistry
    readonly property var installedPlugins: ({})
  }

  QtObject {
    id: fakeStateService
    property int revision: 0
    readonly property var config: ({ widgets: ({}) })
    readonly property color selectedColor: "#88aaff"
    function groupSettingsForVariant(groupId, variant) { return ({}) }
    function groupEnabledForVariant(groupId, variant) { return true }
  }

  QtObject {
    id: fakeShell
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.state" ? fakeStateService : null
    }
  }

  QtObject {
    id: fakeTokens
    readonly property bool v2Shell: fakeController.v2Mode
    readonly property int groupGap: 6
    readonly property int splitGap: 16
    readonly property int slotHeight: 28
    readonly property int pillHeight: 24
    readonly property int tileRadius: 8
    readonly property int pillRadius: 12
    readonly property int invalidDropDuration: 230
    readonly property int returnCleanupDuration: 240
    readonly property int panelRadius: 10
    readonly property int panelBorderWidth: 1
    readonly property color panelBorder: "#333333"
    readonly property color panelBackground: "#181818"
    readonly property color separator: "#777777"
    readonly property color sumi: "#777777"
    readonly property color pill: "#202020"
    readonly property color pillBorder: "#444444"
    readonly property int pillBorderWidth: 1
    readonly property bool shadowEnabled: false
    readonly property string shellStyle: "shibumi"
    function widgetHasFill(settings) { return false }
    function widgetHasBorder(settings) { return false }
    function widgetPadding(settings, decorated) { return 0 }
    function widgetRadius(settings) { return 8 }
    function widgetSurfaceOpacity(settings) { return 1 }
    function widgetFillColor(settings) { return "transparent" }
    function widgetBorderWidth(settings) { return 0 }
    function widgetBorderColor(settings) { return "transparent" }
  }

  QtObject {
    id: fakeController
    property bool v2Mode: false
    property var order: ({ left: host.baseGroups, center: [], right: [] })
    property var v1Slots: ({ left: host.baseGroups, center: [], right: [] })
    property var v2Slots: ({ left: host.baseGroups, center: [], right: [] })
    function groupLocation(groupId) { return host.groupLocation(groupId) }
    function splitEnabled(region, index) { return false }
    function baseV1SlotCount(region) { return region === "left" ? 8 : 0 }
    function maxV1SlotCount(region) { return region === "left" ? 10 : 0 }
    function baseV2SlotCount(region) { return region === "left" ? 8 : 0 }
    function maxV2SlotCount(region) { return region === "left" ? 10 : 0 }
    function isExtraV1Slot(region, index) { return index >= 8 }
    function toggleSplit(region, index) { return false }
  }

  QtObject {
    id: fakeBar
    readonly property bool vertical: host.requestedVertical
    readonly property int barSize: 28
    readonly property string position: "top"
    readonly property string fontFamily: "monospace"
    readonly property color foreground: "#eeeeee"
    readonly property color background: "#181818"
    readonly property color urgent: "#88aaff"
    readonly property var shell: fakeShell
    readonly property var visualTokens: fakeTokens
    readonly property var layoutConfig: ({ left: [], center: [], right: [] })
    readonly property var layoutController: fakeController
    readonly property var hostWidgetResolver: fakeResolver
    readonly property var pluginRegistry: fakePluginRegistry
    property var activePopout: null
    property var pendingTooltipTarget: null
    property var tooltipTarget: null
    function entryId(entry) { return entry && entry.id ? String(entry.id) : "" }
    function entrySettings(entry) { return entry || ({}) }
    function registeredWidgetComponent(moduleName) {
      return moduleName ? markerWidget : null
    }
    function registerModuleSlot(slot) {}
    function unregisterModuleSlot(slot) {}
    function showTooltip(owner, text) {}
    function hideTooltip(owner) {}
    function releasePopout(owner) {}
    function publishConnectedPanel(owner, screenName, x, reveal, geometry) {
      return false
    }
    function clearConnectedPanel(owner) {}
  }

  Core.DragSession {
    id: sessionA
    layoutController: fakeController
    screenName: "INC012-A"
  }

  Core.DragSession {
    id: sessionB
    layoutController: fakeController
    screenName: "INC012-B"
  }

  Component {
    id: sectionComponent

    ShibumiStyle.GroupSection {
      bar: fakeBar
      region: "left"
      screenName: "INC012"
      layoutSession: host.activeSession
      availableWidth: 720
    }
  }

  Loader {
    id: sectionLoader
    active: true
    sourceComponent: sectionComponent
  }

  Timer {
    id: matrixTimer
    interval: 2
    repeat: true
    running: true

    onTriggered: {
      attempts++
      if (attempts > 12000) {
        host.fail("matrix timeout at phase=" + host.phase
          + " mode=" + host.cycleMode + " cycle=" + host.cycleIndex
          + " targets=" + host.targetCount)
        return
      }

      if (host.externalMode) {
        host.configureVariant(host.requestedV2, host.requestedEditing)
        const expectedTargets = host.requestedVertical
          ? 0 : host.baseGroups.length
        if (!host.readyEmitted && sectionLoader.status === Loader.Ready
            && host.targetCount === expectedTargets) {
          host.readyEmitted = true
          host.ready()
        }
        return
      }

      if (host.phase === 0) {
        if (sectionLoader.status !== Loader.Ready
            || host.targetCount !== host.baseGroups.length) return
        host.trace("direct-initial", "targets=" + host.targetCount)
        host.activeSession = sessionB
        host.phase = 1
        return
      }
      if (host.phase === 1) {
        if (host.targetCount !== host.baseGroups.length) return
        host.trace("session-replaced", "targets=" + host.targetCount)
        host.activeSession = null
        host.phase = 2
        return
      }
      if (host.phase === 2) {
        if (sessionB.targets.length !== 0) return
        host.activeSession = sessionA
        host.phase = 3
        return
      }
      if (host.phase === 3) {
        if (host.targetCount !== host.baseGroups.length) return
        host.trace("session-restored", "targets=" + host.targetCount)
        host.setGroups([])
        host.phase = 4
        return
      }
      if (host.phase === 4) {
        if (host.targetCount !== 0) return
        host.trace("model-removed", "targets=0")
        host.setGroups(host.baseGroups)
        host.phase = 5
        return
      }
      if (host.phase === 5) {
        if (host.targetCount !== host.baseGroups.length) return
        host.trace("model-restored", "targets=" + host.targetCount)
        host.cycleMode = 0
        host.cycleIndex = 0
        host.cycleUnloaded = false
        host.phase = 6
        return
      }
      if (host.phase !== 6) return

      if (host.cycleMode >= 4) {
        sectionLoader.active = false
        host.trace("direct-complete", "cycles=80")
        stop()
        host.finished("passed")
        return
      }

      const useV2 = host.cycleMode >= 2
      const useEditing = host.cycleMode % 2 === 1
      host.configureVariant(useV2, useEditing)

      if (!host.cycleUnloaded) {
        if (host.targetCount !== host.baseGroups.length) return
        sectionLoader.active = false
        host.cycleUnloaded = true
        return
      }

      if (!sectionLoader.active) {
        if (host.targetCount !== 0) return
        sectionLoader.active = true
        return
      }

      if (sectionLoader.status !== Loader.Ready
          || host.targetCount !== host.baseGroups.length) return
      host.cycleUnloaded = false
      host.cycleIndex++
      if (host.cycleIndex < 20) return

      host.trace("direct-cycle-mode",
        "v2=" + useV2 + " editing=" + useEditing + " cycles=20")
      host.cycleIndex = 0
      host.cycleMode++
    }
  }
}
