pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "status" as Status
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int phaseTicks: 0
  property real initialWidth: 0
  property var clickTargets: []
  property var statusSettings: ({ displayMode: "full" })

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
    id: fakeShell
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

  Status.Service {
    id: statusService
    shell: fakeShell
    actionRunner: actionRecorder
    runtimeProbesEnabled: false
  }

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
      pillHeight: 24,
      pillRadius: 12,
      pillPaddingX: 9,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false
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
        notificationPanelSource: Qt.resolvedUrl(
          "fixtures/NotificationPanelTestView.qml")
      }
    }
  }

  Status.BarWidget {
    id: unavailableStatus
    bar: unavailableBar
    updateComponent: null
    trayComponent: null
  }

  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      root.phaseTicks++
      const status = statusLoader.item
      if (root.phase === 0) {
        if (!status || !status.ready || root.phaseTicks < 3) return
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
        if (status.childPanelWidget("hancore.shibumi.update-center")
              !== status.updateWidget
            || status.childPanelWidget("omarchy.notifications") !== status
            || !status.ownsPanelWidget(status.updateWidget)
            || status.childPanelWidget("omarchy.tray") !== null)
          return root.fail("nested panel routing")
        if (!status.updatePresented || !status.trayPresented
            || !status.notificationPresented
            || status.notificationService.pendingModel.count !== 3)
          return root.fail("V1 tray/notification facade state")
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
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 1) {
        if (!status.trayDrawerLoaded || root.phaseTicks < 3) return
        if (status.trayWidget.settings.layoutRevision !== 1)
          return root.fail("tray settings did not react to host layout changes")
        const drawer = status.trayDrawerItem
        if (drawer.ownerWidget !== status
            || drawer.trayBackend !== status.trayWidget
            || drawer.anchorItem === null
            || drawer.bar !== fakeBar)
          return root.fail("tray drawer injection contract")
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
            || fakeBar.activePopout !== status)
          return root.fail("notification panel injection/popout ownership")
        notificationPanel.toggleDnd()
        notificationPanel.markAllSeen()
        notificationPanel.dismissPending()
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
