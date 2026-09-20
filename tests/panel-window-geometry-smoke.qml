import QtQuick
import QtQuick.Window
import Quickshell
import "hancore.shibumi.bar/core" as Core
import "fixtures" as Fixtures
import "shared" as Shared

ShellRoot {
  id: root

  // The fullscreen-anchor negative control changes this one staged value.
  property int nativeAnchorHeight: 35
  property int ticks: 0
  property int phase: 0

  function fail(message) {
    console.error("PANEL_GEOMETRY_FAIL " + message)
    Qt.exit(1)
  }

  function near(actual, expected) {
    return Math.abs(Number(actual) - Number(expected)) <= 0.5
  }

  function findObject(object, predicate, seen) {
    if (!object || seen.indexOf(object) >= 0) return null
    seen.push(object)
    try { if (predicate(object)) return object } catch (error) {}
    let objects = []
    try { objects = object.data || [] } catch (error) {}
    for (let index = 0; index < objects.length; index++) {
      const found = findObject(objects[index], predicate, seen)
      if (found) return found
    }
    return null
  }

  function cardFor(panel) {
    return findObject(panel, function(object) {
      return object !== panel && "contentTopInset" in object
        && "contentBottomInset" in object && "borderSpec" in object
        && "radius" in object && "color" in object
    }, [])
  }

  function forwarderFor(panel) {
    return findObject(panel, function(object) {
      return typeof object.barPoint === "function"
        && typeof object.pressTargetAt === "function"
        && typeof object.forwardBarClick === "function"
    }, [])
  }

  function checkSameCard(label, formerPanel, currentPanel) {
    const former = cardFor(formerPanel)
    const current = cardFor(currentPanel)
    if (!former || !current) return false
    if (!near(former.x, current.x) || !near(former.y, current.y)
        || !near(former.width, current.width)
        || !near(former.height, current.height))
      fail(label + " card geometry changed: former="
        + [former.x, former.y, former.width, former.height].join(",")
        + " current="
        + [current.x, current.y, current.width, current.height].join(","))
    console.log("SHIBUMI_PANEL_CASE " + label + " card="
      + [current.x, current.y, current.width, current.height].join(","))
    return true
  }

  function checkClickPair(label, formerPanel, currentPanel,
      formerTarget, currentTarget, px, py, expectedFormerY, expectedCurrentY) {
    const former = forwarderFor(formerPanel)
    const current = forwarderFor(currentPanel)
    if (!former || !current) return false
    const formerPoint = former.barPoint(px, py)
    const currentPoint = current.barPoint(px, py)
    if (!near(formerPoint.y, expectedFormerY)
        || !near(currentPoint.y, expectedCurrentY))
      fail(label + " raw bar-local translation changed: former="
        + formerPoint.y + " current=" + currentPoint.y)
    if (former.pressTargetAt(px, py) !== formerTarget
        || current.pressTargetAt(px, py) !== currentTarget)
      fail(label + " did not resolve the same semantic click target")
    if (!former.forwardBarClick(px, py, Qt.LeftButton)
        || !current.forwardBarClick(px, py, Qt.LeftButton))
      fail(label + " click forwarding refused its semantic target")
    if (formerTarget.pressCount !== 1 || currentTarget.pressCount !== 1)
      fail(label + " click forwarding dispatched more or less than once")
    console.log("SHIBUMI_PANEL_CLICK " + label + " screen=" + px + "," + py
      + " localY=" + formerPoint.y + "->" + currentPoint.y)
    return true
  }

  QtObject {
    id: tokens
    property string shellStyle: "shibumi"
    property int panelBorderWidth: 1
    property int panelRadius: 12
    property int tileRadius: 6
    property bool shadowEnabled: false
    property color panelBackground: "#191716"
    property color panelBorder: "#3f3d39"
    property color pillShadow: "transparent"
    property color sumi: "#888888"
    property color sumiHi: "#aaaaaa"
    property color separator: "#444444"
    property color fillIdle: "#202020"
    property color fillHover: "#282828"
    property color fillActive: "#303030"
    property color fillPrimaryHover: "#383838"
  }

  QtObject {
    id: scopedRegistry
    property string pluginId: "hancore.shibumi.bar"
  }

  Component {
    id: mainComponent
    // Pinned BorderSurface adds two 1px edges: 278 + 14*2 + 2 = 308.
    Fixtures.ProviderBoundHostedPanelWidget { bodyHeight: 278; panelPadding: 14 }
  }

  Component {
    id: insetComponent
    // Explicit provider inset: 360 + 11*2 + two 1px edges = 384.
    Fixtures.ProviderBoundHostedPanelWidget { bodyHeight: 360; panelPadding: 11 }
  }

  QtObject {
    id: widgetRegistry
    property var widgets: ({
      "fixture.main": {
        metadata: { pluginId: "fixture.main", displayName: "Main" },
        component: mainComponent
      },
      "fixture.inset": {
        metadata: { pluginId: "fixture.inset", displayName: "Inset" },
        component: insetComponent
      }
    })
  }

  QtObject {
    id: nativeBar
    property string position: "top"
    property bool vertical: false
    property int barSize: 35
    property color foreground: "#eeeeee"
    property color urgent: "#ff5555"
    property var visualTokens: tokens
    property var pluginRegistry: scopedRegistry
    property var barWidgetRegistry: widgetRegistry
    property var layoutConfig: ({
      left: ["fixture.main", "fixture.inset"], center: [], right: []
    })
    property var barConfig: ({ layout: layoutConfig })
    property var pendingTooltipTarget: null
    property var tooltipTarget: null
    property var activePopout: null
    property var clickTargets: []
    function entryId(entry) { return String(entry.id || entry || "") }
    function entrySettings(entry) { return entry }
    function registerModuleSlot(_slot) {}
    function unregisterModuleSlot(_slot) {}
    function noteHostWidgetResolution(_slot, _loaded) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function publishConnectedPanel(_owner, _screen, _x, _reveal, _geometry) { return true }
    function clearConnectedPanel(_owner) { return true }
  }

  FloatingWindow {
    id: nativeAnchorWindow
    visible: true
    implicitWidth: 800
    implicitHeight: root.nativeAnchorHeight
    color: "transparent"

    Core.WidgetSlot {
      id: mainSlot
      x: 300
      y: 4
      bar: nativeBar
      entry: ({ id: "fixture.main" })
      screenName: "component-stub"
    }

    Core.WidgetSlot {
      id: insetSlot
      x: 340
      y: 4
      bar: nativeBar
      entry: ({ id: "fixture.inset" })
      screenName: "component-stub"
    }
  }

  QtObject {
    id: topBar
    property string position: "top"
    property int barSize: 35
    property color foreground: "#eeeeee"
    property color urgent: "#ff5555"
    property var visualTokens: tokens
    property var clickTargets: [formerTopTarget, currentTopTarget]
    property var activePopout: null
    function activePopoutForScreen(_screen) { return activePopout }
    function requestPopout(owner, _screen) { activePopout = owner }
    function releasePopout(owner, _screen) { if (activePopout === owner) activePopout = null }
    function publishConnectedPanel() { return true }
    function clearConnectedPanel() { return true }
    function targetBelongsToWindow(target, window) {
      return target && target.QsWindow && target.QsWindow.window === window
    }
  }

  QtObject {
    id: bottomBar
    property string position: "bottom"
    property int barSize: 35
    property color foreground: "#eeeeee"
    property color urgent: "#ff5555"
    property var visualTokens: tokens
    property var clickTargets: [formerBottomTarget, currentBottomTarget]
    property var activePopout: null
    function activePopoutForScreen(_screen) { return activePopout }
    function requestPopout(owner, _screen) { activePopout = owner }
    function releasePopout(owner, _screen) { if (activePopout === owner) activePopout = null }
    function publishConnectedPanel() { return true }
    function clearConnectedPanel() { return true }
    function targetBelongsToWindow(target, window) {
      return target && target.QsWindow && target.QsWindow.window === window
    }
  }

  FloatingWindow {
    id: formerTopWindow
    visible: true
    implicitWidth: 800
    implicitHeight: 800
    color: "transparent"
    Item {
      id: formerTopTarget
      x: 360; y: 6; width: 24; height: 20
      property int pressCount: 0
      function triggerPress(_button) { pressCount++ }
    }
  }

  FloatingWindow {
    id: currentTopWindow
    visible: true
    implicitWidth: 800
    implicitHeight: 35
    color: "transparent"
    Item {
      id: currentTopTarget
      x: 360; y: 6; width: 24; height: 20
      property int pressCount: 0
      function triggerPress(_button) { pressCount++ }
    }
  }

  FloatingWindow {
    id: formerBottomWindow
    visible: true
    implicitWidth: 800
    implicitHeight: 800
    color: "transparent"
    Item {
      id: formerBottomTarget
      x: 360; y: 771; width: 24; height: 20
      property int pressCount: 0
      function triggerPress(_button) { pressCount++ }
    }
  }

  FloatingWindow {
    id: currentBottomWindow
    visible: true
    implicitWidth: 800
    implicitHeight: 35
    color: "transparent"
    Item {
      id: currentBottomTarget
      x: 360; y: 6; width: 24; height: 20
      property int pressCount: 0
      function triggerPress(_button) { pressCount++ }
    }
  }

  Shared.ShibumiPanel {
    id: formerTopAnchored
    anchorItem: formerTopTarget; bar: topBar; open: true
    contentWidth: 240; contentHeight: 180
  }
  Shared.ShibumiPanel {
    id: currentTopAnchored
    anchorItem: currentTopTarget; bar: topBar; open: true
    contentWidth: 240; contentHeight: 180
  }
  Shared.ShibumiPanel {
    id: formerTopCentered
    anchorItem: formerTopTarget; bar: topBar; open: true; centerOnBar: true
    contentWidth: 240; contentHeight: 180
  }
  Shared.ShibumiPanel {
    id: currentTopCentered
    anchorItem: currentTopTarget; bar: topBar; open: true; centerOnBar: true
    contentWidth: 240; contentHeight: 180
  }
  Shared.ShibumiPanel {
    id: formerBottomAnchored
    anchorItem: formerBottomTarget; bar: bottomBar; open: true
    contentWidth: 240; contentHeight: 180
  }
  Shared.ShibumiPanel {
    id: currentBottomAnchored
    anchorItem: currentBottomTarget; bar: bottomBar; open: true
    contentWidth: 240; contentHeight: 180
  }
  Shared.ShibumiPanel {
    id: formerBottomCentered
    anchorItem: formerBottomTarget; bar: bottomBar; open: true; centerOnBar: true
    contentWidth: 240; contentHeight: 180
  }
  Shared.ShibumiPanel {
    id: currentBottomCentered
    anchorItem: currentBottomTarget; bar: bottomBar; open: true; centerOnBar: true
    contentWidth: 240; contentHeight: 180
  }

  Timer {
    interval: 20
    repeat: true
    running: true

    onTriggered: {
      root.ticks++
      if (!mainSlot.activeItem || !insetSlot.activeItem
          || !mainSlot.compatibilityPanel || !mainSlot.compatibilityCard
          || !insetSlot.compatibilityPanel || !insetSlot.compatibilityCard) {
        if (root.ticks < 100) return
        return root.fail("pinned KeyboardPanel components did not load")
      }

      const main = mainSlot.compatibilityPanel
      const inset = insetSlot.compatibilityPanel
      if (!root.near(main.anchorWindow.height, 35)
          || !root.near(main.barH, 35))
        return root.fail("fixture anchor window height drifted: "
          + main.anchorWindow.height + "/" + main.barH)

      if (root.phase === 0) {
        if (!root.near(main.contentHeight, 308)
            || !root.near(mainSlot.compatibilityCard.height, 308))
          return root.fail("Basecamp/HEY main provider binding was not 278+30=308: "
            + main.contentHeight + "/" + mainSlot.compatibilityCard.height)
        if (!root.near(inset.contentHeight, 384)
            || !root.near(insetSlot.compatibilityCard.height, 384))
          return root.fail("nested provider binding was not 360+24=384: "
            + inset.contentHeight + "/" + insetSlot.compatibilityCard.height)
        mainSlot.activeItem.bodyHeight = 179
        root.phase = 1
        return
      }
      if (root.phase === 1) {
        if (!root.near(main.contentHeight, 209)
            || !root.near(mainSlot.compatibilityCard.height, 209)) return
        nativeBar.position = "bottom"
        mainSlot.activeItem.bodyHeight = 278
        root.phase = 2
        return
      }
      if (!root.near(main.contentHeight, 308)
          || !root.near(main.cardOrigin.y,
            main.screenH - 35 - 308 - main.gap)) return

      if (!root.checkSameCard("top-anchored", formerTopAnchored,
          currentTopAnchored)
          || !root.checkSameCard("top-centered", formerTopCentered,
            currentTopCentered)
          || !root.checkSameCard("bottom-anchored", formerBottomAnchored,
            currentBottomAnchored)
          || !root.checkSameCard("bottom-centered", formerBottomCentered,
            currentBottomCentered)) return

      if (!root.checkClickPair("top", formerTopAnchored, currentTopAnchored,
          formerTopTarget, currentTopTarget, 372, 16, 16, 16)
          || !root.checkClickPair("bottom", formerBottomAnchored,
            currentBottomAnchored, formerBottomTarget, currentBottomTarget,
            372, 781, 781, 16)) return

      stop()
      console.log("PINNED_KEYBOARD_PANEL_COMPONENT_CASES main=308 settings=209 inset=384 anchor=35")
      console.log("PANEL_WINDOW_GEOMETRY_PASS component-stub-not-native-wayland")
      Qt.exit(0)
    }
  }
}
