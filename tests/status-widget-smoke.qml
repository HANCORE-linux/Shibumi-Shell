pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "widgets" as Widgets
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int phaseTicks: 0
  property real initialWidth: 0
  property var clickTargets: []

  function fail(message) {
    console.error("status-widget-smoke:", message)
    Qt.exit(1)
  }

  ListModel {
    id: pendingNotifications
    ListElement { summary: "First" }
    ListElement { summary: "Second" }
    ListElement { summary: "Third" }
  }

  QtObject {
    id: notificationService
    property var pendingModel: pendingNotifications
    property bool doNotDisturb: false
    function setDoNotDisturb(value) { doNotDisturb = value }
    function markAllSeen() {}
    function dismissPending(_index) {}
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
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.state" ? fakeState : null
    }
    function firstPartyServiceFor(pluginId) {
      return pluginId === "omarchy.notifications" ? notificationService : null
    }
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
      v2Shell: false,
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

  Component {
    id: childComponent
    Fixtures.StatusTestWidget {}
  }

  Loader {
    id: statusLoader
    active: true
    sourceComponent: Component {
      Widgets.StatusWidget {
        bar: fakeBar
        updateComponent: childComponent
        trayComponent: childComponent
        trayDrawerSource: Qt.resolvedUrl("fixtures/TrayDrawerTestPanel.qml")
        notificationPanelSource: Qt.resolvedUrl(
          "fixtures/NotificationPanelTestView.qml")
      }
    }
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
        if (!status.visible
            || !status.updateWidget || !status.trayWidget
            || !status.notificationService || root.clickTargets.length !== 4)
          return root.fail("child lifecycle/readiness: visible=" + status.visible
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
            || status.notificationService.pendingModel.count !== 3
            || status.pendingCount !== 3 || status.recentCount !== 0
            || status.notificationCount !== 3)
          return root.fail("V1 tray/notification facade state")
        if (status.v2Mode
            || status.horizontalInset !== 9
            || status.childGap !== 4
            || status.updateSlotWidth !== 22
            || status.traySlotWidth !== 42
            || status.notificationSlotWidth !== 22
            || status.trayPinnedIconOffset !== 1
            || status.notificationIconOffset !== 1
            || status.implicitWidth !== 112)
          return root.fail("V1 status geometry is not symmetric: inset="
            + Number(status.horizontalInset) + ", gap="
            + Number(status.childGap) + ", slots="
            + JSON.stringify([status.updateSlotWidth,
              status.traySlotWidth, status.notificationSlotWidth])
            + ", trayOffset=" + Number(status.trayPinnedIconOffset)
            + ", bellOffset=" + Number(status.notificationIconOffset)
            + ", width=" + Number(status.implicitWidth))
        status.updateWidget.open()
        if (!status.toggleTrayDrawer() || !status.trayDrawerOpen
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
        status.closeTrayDrawer()
        status.trayWidget.pinnedItems = []
        status.trayWidget.drawerItems = []
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 2) {
        if (root.phaseTicks < 3) return
        if (status.trayDrawerLoaded)
          return root.fail("closed tray drawer remained loaded")
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
        status.trayWidget.managePopupOpen = true
        status.close()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 4) {
        if (root.phaseTicks < 3) return
        if (status.opened || status.notificationPanelLoaded
            || fakeBar.activePopout !== null)
          return root.fail("nested close cleanup")
        statusLoader.active = false
        root.phase++
        root.phaseTicks = 0
      } else {
        if (root.phaseTicks < 3) return
        if (root.clickTargets.length !== 0 || fakeBar.activePopout !== null)
          return root.fail("destruction cleanup")
        stop()
        console.log("status widget smoke passed")
        Qt.quit()
      }
    }
  }
}
