pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "status" as Status
import "hancore.shibumi.bar/services" as BarServices
import "hancore.shibumi.state/runtime" as SuiteRuntime
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int phaseTicks: 0
  property real initialWidth: 0
  property var clickTargets: []
  property var statusSettings: ({ displayMode: "full" })
  readonly property var scopedStatus: scopedStatusLoader.item
  readonly property var scopedDiagnosticStatus: scopedDiagnosticStatusLoader.item
  property bool scopedServiceStarted: false
  property int scopedServicePhase: 0
  property int scopedStayAwakeChanges: 0
  property int scopedDndChanges: 0

  function fail(message) {
    console.error("status-widget-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeIdle
    property bool stayAwake: true
    function setIdleEnabled(enabled) {
      stayAwake = !enabled
    }
  }

  ListModel {
    id: pendingNotifications
    ListElement {
      app: "Fixture"
      appIcon: ""
      summary: "Pending"
      body: "Pending body"
      image: ""
      timestamp: 1
    }
    ListElement {
      app: "Fixture"
      appIcon: ""
      summary: "Pending two"
      body: "Pending body two"
      image: ""
      timestamp: 2
    }
    ListElement {
      app: "Fixture"
      appIcon: ""
      summary: "Pending three"
      body: "Pending body three"
      image: ""
      timestamp: 3
    }
  }

  ListModel {
    id: pastNotifications
    ListElement {
      app: "Fixture"
      appIcon: ""
      summary: "Recent"
      body: "Recent body"
      image: ""
      timestamp: 4
    }
  }

  QtObject {
    id: fakeNotifications
    property bool doNotDisturb: false
    property var pendingModel: pendingNotifications
    property var pastModel: pastNotifications
    property int dndToggleCount: 0
    property int markAllSeenCount: 0
    property int dismissPendingCount: 0
    function setDoNotDisturb(value) {
      doNotDisturb = value === true
      dndToggleCount++
    }
    function markAllSeen() { markAllSeenCount++ }
    function dismissPending(_index) { dismissPendingCount++ }
    function dismissPast(_index) {}
    function clearPast() { pastModel.clear() }
  }

  QtObject {
    id: fakeState
    property var writes: []

    function setWidgetSetting(groupId, moduleId, key, value) {
      writes = writes.concat([{
        groupId: String(groupId || ""),
        moduleId: String(moduleId || ""),
        key: String(key || ""),
        value: JSON.parse(JSON.stringify(value))
      }])
      return true
    }
  }

  QtObject {
    id: fakeShell
    property var statusFacade: null
    function serviceFor(id) {
      if (id === "hancore.shibumi.state") return fakeState
      if (id === "hancore.shibumi.status") return statusFacade
      return null
    }
    function firstPartyServiceFor(id) {
      if (id === "omarchy.idle") return fakeIdle
      if (id === "omarchy.notifications") return fakeNotifications
      return null
    }
  }

  QtObject {
    id: actionRecorder
    property var commands: []
    function run(command) {
      commands = commands.concat([command.slice()])
      return true
    }
  }

  QtObject {
    id: leasedIdleA
    property bool stayAwake: true
    property int setCalls: 0
    function setIdleEnabled(value) {
      stayAwake = value !== true
      setCalls++
    }
  }

  QtObject {
    id: leasedNotificationsA
    property bool doNotDisturb: true
    property int setCalls: 0
    function setDoNotDisturb(value) {
      doNotDisturb = value === true
      setCalls++
    }
  }

  QtObject {
    id: leasedIdleB
    property bool stayAwake: false
    property int setCalls: 0
    function setIdleEnabled(value) {
      stayAwake = value !== true
      setCalls++
    }
  }

  QtObject {
    id: leasedNotificationsB
    property bool doNotDisturb: false
    property int setCalls: 0
    function setDoNotDisturb(value) {
      doNotDisturb = value === true
      setCalls++
    }
  }

  QtObject {
    id: leasedBarHostA
    readonly property string pluginId: "hancore.shibumi.bar"
    function firstPartyServiceFor(id) {
      if (id === "omarchy.idle") return leasedIdleA
      if (id === "omarchy.notifications") return leasedNotificationsA
      return null
    }
  }

  QtObject {
    id: leasedBarHostB
    readonly property string pluginId: "hancore.shibumi.bar"
    function firstPartyServiceFor(id) {
      if (id === "omarchy.idle") return leasedIdleB
      if (id === "omarchy.notifications") return leasedNotificationsB
      return null
    }
  }

  Item {
    id: leasedBarOwner
    property var providerHost: leasedBarHostA
    SuiteRuntime.Provider {
      id: leasedBarProvider
      pluginId: "hancore.shibumi.bar"
      implementationVersion: "0.1.1-beta.15"
      owner: leasedBarOwner
      host: leasedBarOwner.providerHost
      manifest: ({ id: "hancore.shibumi.bar",
        version: "0.1.1-beta.15", kinds: ["bar"] })
    }
  }

  QtObject {
    id: rawScopedStatusShell
    readonly property string pluginId: "hancore.shibumi.status"
    function serviceFor(_id) { return null }
    function firstPartyServiceFor(_id) { return null }
  }

  Loader {
    id: scopedDiagnosticStatusLoader
    active: root.scopedServiceStarted
    sourceComponent: Component {
      Status.Service {
        shell: rawScopedStatusShell
        manifest: ({ id: "hancore.shibumi.status",
          version: "0.1.1-beta.15", kinds: ["service"] })
        actionRunner: actionRecorder
        runtimeProbesEnabled: false
      }
    }
  }

  Connections {
    target: root.scopedDiagnosticStatus
    function onStayAwakeChanged() { root.scopedStayAwakeChanges++ }
    function onNotificationsSilencedChanged() { root.scopedDndChanges++ }
  }

  Status.Service {
    id: statusService
    shell: fakeShell
    actionRunner: actionRecorder
    runtimeProbesEnabled: false
  }

  Component.onCompleted: fakeShell.statusFacade = statusService

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 35
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var shell: fakeShell
    property var layoutConfig: ({ left: [], center: [], right: [] })
    property var clickTargets: root.clickTargets
    property var barWidgetRegistry: null
    property var visualTokens: ({
      shellStyle: "full",
      v2Shell: true,
      pillHeight: 24,
      pillRadius: 12,
      pillPaddingX: 9,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      widgetHasFill: function(settings) {
        return settings && settings.color === "color05"
      },
      widgetFillColor: function(settings) {
        return settings && settings.color === "color05"
          ? "#cc8844" : "transparent"
      },
      widgetSurfaceOpacity: function(settings) {
        return settings && settings.surfaceOpacity !== undefined
          ? Number(settings.surfaceOpacity) : 1
      },
      widgetContentColor: function(settings, fallback) {
        return settings && settings.color === "color05"
          && settings.tone === "background" ? fakeBar.background : fallback
      }
    })

    function widgetSettings(group, module) {
      return group === "G3" ? ({
        marker: module,
        layoutRevision: Number(layoutConfig.revision || 0)
      }) : ({})
    }
    function registerClickTarget(target) {
      if (root.clickTargets.indexOf(target) < 0)
        root.clickTargets = root.clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      root.clickTargets = root.clickTargets.filter(item => item !== target)
    }
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return true }
    function targetBelongsToWindow(_target, _window) { return true }
  }

  QtObject {
    id: scopedFacade
    readonly property string pluginId: "hancore.shibumi.status"
  }

  QtObject {
    id: scopedRegistry
    readonly property var widgets: ({
      "hancore.shibumi.update-center": ({
        component: childComponent,
        metadata: { pluginId: "hancore.shibumi.update-center" }
      }),
      "omarchy.tray": ({
        component: childComponent,
        metadata: { pluginId: "omarchy.tray" }
      })
    })
  }

  QtObject {
    id: scopedBar
    property bool vertical: false
    property int barSize: 35
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var shell: fakeShell
    property var pluginRegistry: scopedFacade
    property var barWidgetRegistry: scopedRegistry
    property var layoutConfig: ({
      left: [{ id: "hancore.shibumi.status" }], center: [], right: []
    })
    property var visualTokens: fakeBar.visualTokens
    function registeredWidgetComponent(id) {
      return scopedResolver.componentFor(id)
    }
    function registeredEmbeddedWidgetComponent(ownerId, id) {
      return scopedResolver.embeddedComponentFor(ownerId, id)
    }
    function registeredWidgetSource(id) {
      return scopedResolver.entryPointUrl(id)
    }
    function widgetSettings(group, module) {
      return group === "G3" ? ({ marker: module }) : ({})
    }
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function switchPanelFrom(_owner, _direction) { return true }
    function targetBelongsToWindow(_target, _window) { return true }
  }

  BarServices.HostWidgetResolver {
    id: scopedResolver
    bar: scopedBar
  }

  QtObject {
    id: unavailableShell
    function firstPartyServiceFor(_id) { return null }
  }

  QtObject {
    id: unavailableBar
    property bool vertical: false
    property int barSize: 35
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color background: "#111111"
    property color urgent: "#88bbee"
    property var shell: unavailableShell
    property var barWidgetRegistry: null
    property var visualTokens: fakeBar.visualTokens
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
  }

  Component {
    id: childComponent
    Fixtures.StatusTestWidget {}
  }

  Loader {
    id: statusLoader
    active: true
    sourceComponent: Component {
      Status.BarWidget {
        bar: fakeBar
        settings: root.statusSettings
        updateComponent: childComponent
        trayComponent: childComponent
        trayDrawerSource: Qt.resolvedUrl(
          "fixtures/TrayDrawerTestPanel.qml")
        notificationPanelSource: Qt.resolvedUrl("status/NotificationPanel.qml")
      }
    }
  }

  Status.BarWidget {
    id: unavailableStatus
    bar: unavailableBar
    updateComponent: null
    trayComponent: null
  }

  Loader {
    id: scopedStatusLoader
    active: true
    sourceComponent: Component {
      Status.BarWidget { bar: scopedBar }
    }
  }

  function advanceScopedServiceRegression() {
    if (scopedServicePhase === 0) {
      if (!SuiteRuntime.Runtime.ready || !leasedBarProvider.registered) return false
      if (!scopedServiceStarted) {
        scopedServiceStarted = true
        return false
      }
      if (!scopedDiagnosticStatus) return false
      const notifications = scopedDiagnosticStatus.notificationService
      if (scopedDiagnosticStatus.idleService !== leasedIdleA || !notifications)
        return fail("scoped Status did not resolve owner A")
      if (notifications === leasedNotificationsA
          || !scopedDiagnosticStatus.stayAwake
          || !scopedDiagnosticStatus.notificationsSilenced
          || !notifications.historyAvailable
          || !notifications.pastDismissAvailable
          || !notifications.pastClearAvailable
          || notifications.pendingCount !== 0
          || notifications.recentCount !== 0
          || notifications.pendingModel.count !== 0
          || notifications.pastModel.count !== 0)
        return fail("owner A narrow notification capabilities were widened")
      const idleChanges = scopedStayAwakeChanges
      const dndChanges = scopedDndChanges
      if (!scopedDiagnosticStatus.toggleStayAwake()
          || leasedIdleA.setCalls !== 1
          || scopedDiagnosticStatus.stayAwake
          || scopedStayAwakeChanges <= idleChanges
          || !scopedDiagnosticStatus.toggleNotifications()
          || leasedNotificationsA.setCalls !== 1
          || scopedDiagnosticStatus.notificationsSilenced
          || scopedDndChanges <= dndChanges)
        return fail("owner A mutation notifications did not reach Status")
      console.log("status scoped capabilities: lease=A available=true"
        + " idle=" + scopedDiagnosticStatus.stayAwake
        + " dnd=" + scopedDiagnosticStatus.notificationsSilenced
        + " history=true pastDismiss=true pending=0 recent=0")
      leasedBarOwner.providerHost = null
      scopedServicePhase++
      return false
    }
    if (scopedServicePhase === 1) {
      if (leasedBarProvider.registered) return false
      if (scopedDiagnosticStatus.idleService !== null
          || scopedDiagnosticStatus.notificationService !== null
          || scopedDiagnosticStatus.stayAwake
          || scopedDiagnosticStatus.notificationsSilenced)
        return fail("scoped Status retained a withdrawn owner A lease")
      if (scopedDiagnosticStatus.toggleStayAwake()
          || scopedDiagnosticStatus.toggleNotifications()
          || leasedIdleA.setCalls !== 1
          || leasedNotificationsA.setCalls !== 1)
        return fail("withdrawn owner A remained mutable through Status")
      console.log("status scoped capabilities: lease=none available=false"
        + " idle=" + scopedDiagnosticStatus.stayAwake
        + " dnd=" + scopedDiagnosticStatus.notificationsSilenced
        + " history=false pending=0 recent=0")
      leasedBarOwner.providerHost = leasedBarHostB
      scopedServicePhase++
      return false
    }
    if (scopedServicePhase === 2) {
      if (!leasedBarProvider.registered) return false
      const notifications = scopedDiagnosticStatus.notificationService
      if (scopedDiagnosticStatus.idleService !== leasedIdleB || !notifications)
        return fail("scoped Status did not resolve owner B")
      if (scopedDiagnosticStatus.stayAwake
          || scopedDiagnosticStatus.notificationsSilenced
          || !notifications.historyAvailable
          || !notifications.pastDismissAvailable
          || !notifications.pastClearAvailable
          || notifications.pendingCount !== 0
          || notifications.recentCount !== 0
          || notifications.pendingModel.count !== 0
          || notifications.pastModel.count !== 0)
        return fail("owner B narrow notification state was incorrect")
      leasedIdleA.stayAwake = true
      leasedNotificationsA.doNotDisturb = true
      if (scopedDiagnosticStatus.stayAwake
          || scopedDiagnosticStatus.notificationsSilenced)
        return fail("withdrawn owner A still affected Status")
      const idleChanges = scopedStayAwakeChanges
      const dndChanges = scopedDndChanges
      if (!scopedDiagnosticStatus.toggleStayAwake()
          || leasedIdleB.setCalls !== 1
          || !scopedDiagnosticStatus.stayAwake
          || scopedStayAwakeChanges <= idleChanges
          || !scopedDiagnosticStatus.toggleNotifications()
          || leasedNotificationsB.setCalls !== 1
          || !scopedDiagnosticStatus.notificationsSilenced
          || scopedDndChanges <= dndChanges
          || leasedIdleA.setCalls !== 1
          || leasedNotificationsA.setCalls !== 1)
        return fail("owner B mutation notifications did not reach Status")
      console.log("status scoped capabilities: lease=B available=true"
        + " idle=" + scopedDiagnosticStatus.stayAwake
        + " dnd=" + scopedDiagnosticStatus.notificationsSilenced
        + " history=true pastDismiss=true pending=0 recent=0"
        + " oldOwnerIsolated=true")
      console.log("status scoped service lease regression passed")
      scopedServicePhase++
    }
    return true
  }

  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      if (!root.advanceScopedServiceRegression()) return
      root.phaseTicks++
      const status = statusLoader.item
      if (root.phase === 0) {
        if (!status || !status.ready || root.phaseTicks < 3) return
        if (!root.scopedStatus || !root.scopedStatus.visible
            || !root.scopedStatus.updateWidget
            || !root.scopedStatus.trayWidget) {
          if (root.phaseTicks < 25) return
          return root.fail("scoped G3 embedded widgets did not load: visible="
            + !!(root.scopedStatus && root.scopedStatus.visible)
            + ", update=" + !!(root.scopedStatus
              && root.scopedStatus.updateWidget)
            + ", tray=" + !!(root.scopedStatus
              && root.scopedStatus.trayWidget))
        }
        if (scopedResolver.componentFor(
              "hancore.shibumi.update-center") !== null
            || scopedResolver.embeddedComponentFor(
              "hancore.shibumi.status", "hancore.shibumi.update-center")
                !== childComponent
            || scopedResolver.embeddedComponentFor(
              "hancore.shibumi.status", "omarchy.tray") !== childComponent
            || scopedResolver.embeddedComponentFor(
              "hancore.shibumi.status", "fixture.not-allowed") !== null)
          return root.fail("scoped G3 component admission boundary")
        if (!status.visible || unavailableStatus.visible
            || !status.updateWidget || !status.trayWidget
            || !status.notificationService || root.clickTargets.length !== 4)
          return root.fail("child lifecycle/readiness: visible=" + status.visible
            + ", unavailable=" + unavailableStatus.visible
            + ", update=" + !!status.updateWidget
            + ", tray=" + !!status.trayWidget
            + ", notifications=" + !!status.notificationService
            + ", trayModule=" + String(status.trayWidget
              ? status.trayWidget.moduleName : "")
            + ", trayPinned=" + Number(status.trayWidget
              ? status.trayWidget.pinnedItems.length : -1)
            + ", trayDrawer=" + Number(status.trayWidget
              ? status.trayWidget.drawerCount : -1)
            + ", clickTargets=" + root.clickTargets.length)
        if (status.updateWidget.moduleName !== "hancore.shibumi.update-center"
            || status.trayWidget.moduleName !== "omarchy.tray"
            || status.updateWidget.settings.marker !== "hancore.shibumi.update-center"
            || status.trayWidget.settings.marker !== "omarchy.tray")
          return root.fail("child identity/settings injection")
        if (String(status.updateWidget.contentColor).toLowerCase()
            !== "#88bbee")
          return root.fail("initial embedded updater color")
        if (status.childPanelWidget("hancore.shibumi.update-center")
              !== status.updateWidget
            || status.childPanelWidget("omarchy.notifications") !== status
            || !status.ownsPanelWidget(status.updateWidget)
            || status.childPanelWidget("omarchy.tray") !== null)
          return root.fail("nested panel routing")
        if (!status.updatePresented || !status.trayPresented
            || !status.notificationPresented
            || status.notificationService.pendingModel.count !== 3
            || status.pendingCount !== 3 || status.recentCount !== 1
            || status.notificationCount !== 4)
          return root.fail("V1 tray/notification facade state")
        if (!status.v2Mode
            || status.horizontalInset !== 9
            || status.childGap !== 4
            || status.updateSlotWidth !== 22
            || status.traySlotWidth !== 42
            || status.notificationSlotWidth !== 22
            || status.trayPinnedIconOffset !== 1
            || status.notificationIconOffset !== 1
            || status.updateSlotLayer !== 3
            || status.traySlotLayer !== 2
            || status.notificationSlotLayer !== 1
            || status.updateBadgeLayer !== 10
            || status.trayBadgeLayer !== 10
            || status.notificationBadgeLayer !== 10
            || status.implicitWidth !== 112)
          return root.fail("V2 status geometry is not symmetric: inset="
            + Number(status.horizontalInset) + ", gap="
            + Number(status.childGap) + ", slots="
            + JSON.stringify([status.updateSlotWidth,
              status.traySlotWidth, status.notificationSlotWidth])
            + ", trayOffset=" + Number(status.trayPinnedIconOffset)
            + ", bellOffset=" + Number(status.notificationIconOffset)
            + ", width=" + Number(status.implicitWidth))
        statusService.recordingPid = "42"
        if (!statusService.stayAwake
            || !statusService.toggleStayAwake() || fakeIdle.stayAwake
            || statusService.notificationsSilenced
            || !statusService.toggleNotifications()
            || !fakeNotifications.doNotDisturb
            || !statusService.stopRecording()
            || !statusService.openVoxtypeModel()
            || !statusService.openVoxtypeConfig()
            || actionRecorder.commands.length !== 3
            || actionRecorder.commands[0].join("|")
              !== "omarchy-capture-screenrecording|--stop-recording"
            || actionRecorder.commands[1].join("|") !== "omarchy-voxtype-model"
            || actionRecorder.commands[2].join("|") !== "omarchy-voxtype-config")
          return root.fail("shared status service/action contract")
        statusService.updateVoxtype(JSON.stringify({
          alt: "recording",
          tooltip: "Voxtype recording\nModel: base.en"
        }))
        if (!statusService.voxtypeAvailable
            || statusService.voxtypeState !== "recording"
            || statusService.voxtypeHint !== "Voxtype recording"
            || !statusService.voxtypeActive)
          return root.fail("Voxtype recording snapshot mapping")
        statusService.updateVoxtype(JSON.stringify({
          class: "transcribing",
          tooltip: "Voxtype transcribing"
        }))
        if (statusService.voxtypeState !== "transcribing"
            || !statusService.voxtypeActive)
          return root.fail("Voxtype transcribing snapshot mapping")
        statusService.updateVoxtype("not-json")
        if (statusService.voxtypeState !== "idle"
            || statusService.voxtypeHint !== ""
            || statusService.voxtypeActive)
          return root.fail("Voxtype malformed snapshot fallback")
        status.updateWidget.open()
        if (!status.openTrayDrawer() || !status.trayDrawerOpen
            || status.updateWidget.popupOpen)
          return root.fail("tray drawer did not open")

        root.initialWidth = status.implicitWidth
        fakeBar.layoutConfig = ({
          left: [], center: [], right: [], revision: 1
        })
        fakeBar.urgent = "#cc8844"
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 1) {
        if (!status.trayDrawerLoaded || root.phaseTicks < 3) return
        if (String(status.updateWidget.contentColor).toLowerCase()
            !== "#cc8844")
          return root.fail("embedded updater color did not follow live theme")
        if (status.trayWidget.settings.layoutRevision !== 1)
          return root.fail("tray settings did not react to host layout changes")
        const drawer = status.trayDrawerItem
        if (drawer.ownerWidget !== status
            || drawer.trayBackend !== status.trayWidget
            || drawer.anchorItem === null
            || drawer.bar !== fakeBar)
          return root.fail("tray drawer injection contract")
        status.trayWidget.togglePin("fixture-drawer")
        if (status.trayWidget.pinToggleCount !== 1
            || fakeState.writes.length !== 2
            || fakeState.writes[0].groupId !== "G3"
            || fakeState.writes[0].moduleId !== "omarchy.tray"
            || fakeState.writes[0].key !== "pinned"
            || fakeState.writes[0].value[0] !== "fixture-drawer"
            || fakeState.writes[1].key !== "hidden")
          return root.fail("embedded tray pin did not persist into G3: "
            + JSON.stringify(fakeState.writes))
        status.trayWidget.trayMenuOpen = true
        status.closeTrayDrawer()
        status.trayWidget.pinnedItems = []
        status.trayWidget.drawerItems = []
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 2) {
        if (root.phaseTicks < 3) return
        if (status.trayDrawerLoaded)
          return root.fail("closed tray drawer remained loaded")
        if (status.trayWidget.trayMenuOpen)
          return root.fail("closed tray drawer left the host app menu open")
        if (status.implicitWidth >= root.initialWidth)
          return root.fail("hidden tray did not release width: initial="
            + root.initialWidth + ", current=" + status.implicitWidth
            + ", anyPresented=" + status.hasVisibleChild
            + ", rowWidth=" + status.contentWidth)
        if (!status.open() || !status.opened
            || !status.notificationPanelOpen)
          return root.fail("local notification panel did not open")
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 3) {
        if (!status.notificationPanelLoaded || root.phaseTicks < 3) return
        const notificationPanel = status.notificationPanelItem
        if (notificationPanel.ownerWidget !== status
            || notificationPanel.notificationService
              !== status.notificationService
            || notificationPanel.anchorItem === null
            || notificationPanel.bar !== fakeBar
            || notificationPanel.pendingCount !== 3
            || !notificationPanel.notificationService.pastDismissAvailable
            || !notificationPanel.notificationService.pastClearAvailable
            || fakeBar.activePopout !== status)
          return root.fail("notification panel injection/popout ownership")
        notificationPanel.setDnd(false)
        notificationPanel.clearActive()
        notificationPanel.dismiss("pending", 0)
        if (fakeNotifications.dndToggleCount !== 2
            || fakeNotifications.markAllSeenCount !== 1
            || fakeNotifications.dismissPendingCount !== 1)
          return root.fail("notification actions bypassed official service")
        status.trayWidget.managePopupOpen = true
        status.close()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 4) {
        if (root.phaseTicks < 3) return
        if (status.opened || status.notificationPanelLoaded
            || fakeBar.activePopout !== null)
          return root.fail("nested close cleanup")
        root.statusSettings = ({ displayMode: "icon" })
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 5) {
        if (root.phaseTicks < 3) return
        if (!status.iconMode || status.fullMode || status.textMode
            || status.presentedCount !== 1 || !status.hasVisibleChild)
          return root.fail("icon display mode")
        root.statusSettings = ({ displayMode: "text" })
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 6) {
        if (root.phaseTicks < 3) return
        if (!status.textMode || status.fullMode || status.iconMode
            || status.textLabel.length === 0 || !status.hasVisibleChild)
          return root.fail("text display mode")
        root.statusSettings = ({ displayMode: "full" })
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 7) {
        if (root.phaseTicks < 3) return
        if (!status.fullMode || status.iconMode || status.textMode
            || status.presentedCount < 2)
          return root.fail("full display mode restoration")
        const v1Tokens = ({})
        for (const key in fakeBar.visualTokens)
          v1Tokens[key] = fakeBar.visualTokens[key]
        v1Tokens.shellStyle = "shibumi"
        v1Tokens.v2Shell = false
        fakeBar.visualTokens = v1Tokens
        root.statusSettings = ({
          displayMode: "full",
          color: "color05",
          colorMode: "border",
          tone: "background",
          surfaceOpacity: 0.6
        })
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 8) {
        if (root.phaseTicks < 3) return
        if (status.v2Mode || !status.v1CustomToneActive
            || !status.updateWidget.customToneActive
            || Math.abs(status.trayDrawerIconColor.r
              - fakeBar.background.r) > 0.001
            || Math.abs(status.trayDrawerIconColor.g
              - fakeBar.background.g) > 0.001
            || Math.abs(status.trayDrawerIconColor.b
              - fakeBar.background.b) > 0.001
            || Math.abs(status.trayDrawerIconColor.a - 0.7) > 0.003
            || !Qt.colorEqual(
              status.trayDrawerBadgeColor, fakeBar.background)
            || !Qt.colorEqual(
              status.trayDrawerBadgeTextColor, "#cc8844")
            || !Qt.colorEqual(
              status.notificationBadgeColor, fakeBar.background)
            || !Qt.colorEqual(
              status.notificationBadgeTextColor, "#cc8844")
            || !Qt.colorEqual(status.badgeContrastColor, "#cc8844")
            || !Qt.colorEqual(
              status.updateWidget.badgeContrastColor, "#cc8844"))
          return root.fail("V1 tray drawer content tone"
            + " v2=" + status.v2Mode
            + " custom=" + status.v1CustomToneActive
            + " icon=" + status.trayDrawerIconColor
            + " badge=" + status.trayDrawerBadgeColor
            + " text=" + status.trayDrawerBadgeTextColor
            + " background=" + fakeBar.background)
        statusLoader.active = false
        root.phase++
        root.phaseTicks = 0
      } else {
        if (root.phaseTicks < 3) return
        if (root.clickTargets.length !== 0 || fakeBar.activePopout !== null)
          return root.fail("destruction cleanup")
        stop()
        console.log("status plugin smoke passed")
        Qt.quit()
      }
    }
  }
}
