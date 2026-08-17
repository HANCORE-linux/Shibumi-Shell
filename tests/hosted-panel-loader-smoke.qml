import QtQuick
import Quickshell
import "core" as Core
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int attempts: 0
  property int phase: -1
  property int firstLoadGeneration: 0
  property int eagerReplacementGeneration: 0
  property int eagerClosedSurfaceAttempts: 0
  property int closedSurfaceAttempts: 0

  function fail(message) {
    console.error("hosted-panel-loader-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: tokens

    property color panelBackground: "#191716"
    property color panelBorder: "#3f3d39"
    property int panelBorderWidth: 1
    property int panelRadius: 12
    property string shellStyle: "shibumi"
  }

  QtObject {
    id: pluginRegistry

    property var installedPlugins: ({
      "example.nested-panel": {
        id: "example.nested-panel",
        name: "Nested panel fixture",
        barWidget: { displayName: "Nested panel fixture" }
      },
      "example.direct-panel": {
        id: "example.direct-panel",
        name: "Direct panel fixture",
        barWidget: { displayName: "Direct panel fixture" }
      },
      "example.misleading-item": {
        id: "example.misleading-item",
        name: "Misleading item fixture",
        barWidget: { displayName: "Misleading item fixture" }
      },
      "example.eager-nested-panel": {
        id: "example.eager-nested-panel",
        name: "Eager nested panel fixture",
        barWidget: { displayName: "Eager nested panel fixture" }
      }
    })
  }

  Component {
    id: nestedWidgetComponent

    Fixtures.NestedHostedPanelWidget {}
  }

  Component {
    id: directWidgetComponent

    Fixtures.DirectPreferredHostedPanelWidget {}
  }

  Component {
    id: misleadingWidgetComponent

    Fixtures.MisleadingItemHostedPanelWidget {}
  }

  Component {
    id: eagerNestedWidgetComponent

    Fixtures.NestedHostedPanelWidget { eagerPanel: true }
  }

  QtObject {
    id: fakeBar

    property string position: "top"
    property bool vertical: false
    property int barSize: 35
    property var visualTokens: tokens
    property var pluginRegistry: pluginRegistry
    property var pendingTooltipTarget: null
    property var tooltipTarget: null
    property var activePopout: null

    function entryId(entry) { return String(entry.id || "") }
    function entrySettings(entry) { return entry }
    function registeredWidgetComponent(moduleName) {
      if (moduleName === "example.direct-panel") return directWidgetComponent
      if (moduleName === "example.misleading-item")
        return misleadingWidgetComponent
      if (moduleName === "example.eager-nested-panel")
        return eagerNestedWidgetComponent
      return nestedWidgetComponent
    }
    function registerModuleSlot(_slot) {}
    function unregisterModuleSlot(_slot) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function publishConnectedPanel(_owner, _screenName, _x, _reveal, _geometry) {
      return true
    }
    function clearConnectedPanel(_owner) { return true }
  }

  Core.WidgetSlot {
    id: slot

    bar: fakeBar
    entry: ({ id: "example.nested-panel" })
    screenName: "fixture-output"
  }

  Core.WidgetSlot {
    id: directSlot

    bar: fakeBar
    entry: ({ id: "example.direct-panel" })
    screenName: "fixture-output"
  }

  Core.WidgetSlot {
    id: misleadingSlot

    bar: fakeBar
    entry: ({ id: "example.misleading-item" })
    screenName: "fixture-output"
  }

  Core.WidgetSlot {
    id: eagerSlot

    bar: fakeBar
    entry: ({ id: "example.eager-nested-panel" })
    screenName: "fixture-output"
  }

  Timer {
    interval: 20
    repeat: true
    running: true

    onTriggered: {
      root.attempts++
      if (!slot.activeItem || !directSlot.activeItem
          || !misleadingSlot.activeItem || !eagerSlot.activeItem) {
        if (root.attempts < 100) return
        return root.fail("hosted fixtures did not load")
      }

      if (!directSlot.compatibilityPanel || !directSlot.compatibilityCard) {
        if (root.attempts < 100) return
        return root.fail("direct standard panel was not discovered")
      }
      if (directSlot.compatibilityPanel !== directSlot.activeItem.directPanel
          || directSlot.compatibilityPanel
            === directSlot.activeItem.nestedPanel)
        return root.fail("nested panel overrode the direct provider contract")

      if (root.phase === -1) {
        if (!eagerSlot.compatibilityPanel
            || eagerSlot.compatibilityPanel.contentHeight <= 120) {
          if (root.attempts < 50) return
          return root.fail("eager nested panel did not receive initial height repair")
        }
        eagerSlot.activeItem.openOnDemand()
        root.phase = -2
        root.attempts = 0
        return
      }

      if (root.phase === -2) {
        if (root.attempts < 6) return
        if (!eagerSlot.compatibilityPanel
            || eagerSlot.compatibilityPanel.contentHeight <= 120)
          return root.fail("opening eager nested panel dropped its repaired height")
        root.phase = -3
        root.attempts = 0
        return
      }

      if (root.phase === -3) {
        // Let the 800 ms construction window expire before changing content.
        if (root.attempts < 50) return
        eagerSlot.activeItem.desiredContentHeight = 520
        root.phase = -4
        root.attempts = 0
        return
      }

      if (root.phase === -4) {
        if (Math.abs(eagerSlot.compatibilityPanel.contentHeight - 544) > 0.5) {
          if (root.attempts < 30) return
          return root.fail("late hosted-panel growth was not reconciled")
        }
        eagerSlot.activeItem.desiredContentHeight = 240
        root.phase = -5
        root.attempts = 0
        return
      }

      if (root.phase === -5) {
        if (Math.abs(eagerSlot.compatibilityPanel.contentHeight - 264) > 0.5) {
          if (root.attempts < 30) return
          return root.fail("late hosted-panel shrink was not reconciled")
        }
        root.eagerReplacementGeneration
          = eagerSlot.activeItem.loadGeneration
        eagerSlot.activeItem.replaceWhileOpen()
        root.phase = -6
        root.attempts = 0
        return
      }

      if (root.phase === -6) {
        if (!eagerSlot.activeItem.exposedPanel
            || !eagerSlot.compatibilityPanel
            || eagerSlot.activeItem.loadGeneration
              <= root.eagerReplacementGeneration) {
          if (root.attempts < 50) return
          return root.fail("same-open Loader replacement was not rediscovered")
        }
        if (Math.abs(eagerSlot.compatibilityPanel.contentHeight - 264) > 0.5) {
          if (root.attempts < 50) return
          return root.fail("replacement panel lost repaired content height")
        }
        root.eagerClosedSurfaceAttempts
          = eagerSlot.compatibilitySurfaceResolutionAttempts
        eagerSlot.activeItem.closeLoaded()
        root.phase = -7
        root.attempts = 0
        return
      }

      if (root.phase === -7) {
        if (root.attempts < 6) return
        if (!eagerSlot.activeItem.exposedPanel
            || !eagerSlot.compatibilityPanel)
          return root.fail("close-only path destroyed the hosted panel")
        if (eagerSlot.compatibilityMeasurementRunning
            || eagerSlot.compatibilitySurfaceResolutionAttempts
              !== root.eagerClosedSurfaceAttempts)
          return root.fail("close-only path retained compatibility polling")
        eagerSlot.activeItem.openOnDemand()
        root.phase = -8
        root.attempts = 0
        return
      }

      if (root.phase === -8) {
        if (root.attempts < 6) return
        if (!eagerSlot.compatibilityPanel
            || Math.abs(eagerSlot.compatibilityPanel.contentHeight - 264) > 0.5)
          return root.fail("same-panel reopen lost repaired content height")
        root.phase = 0
        root.attempts = 0
        return
      }

      if (root.phase === 0) {
        if (slot.compatibilityPanel || slot.compatibilityCard)
          return root.fail("panel appeared before its on-demand Loader")
        if (slot.compatibilitySurfaceResolutionAttempts < 20
            || misleadingSlot.compatibilitySurfaceResolutionAttempts < 20)
          return
        if (misleadingSlot.compatibilityPanel
            || misleadingSlot.compatibilityCard)
          return root.fail("arbitrary item property escaped the owned tree")
        root.phase = 1
        root.attempts = 0
        slot.activeItem.openOnDemand()
        return
      }

      if (root.phase === 3) {
        if (slot.activeItem.exposedPanel
            || slot.compatibilityPanel || slot.compatibilityCard) {
          if (root.attempts < 50) return
          return root.fail("unloaded panel left stale compatibility objects")
        }
        if (slot.compatibilityMeasurementRunning)
          return root.fail("unloaded panel retained its measurement timer")
        root.closedSurfaceAttempts
          = slot.compatibilitySurfaceResolutionAttempts
        root.phase = 30
        root.attempts = 0
        return
      }

      if (root.phase === 30) {
        // Stay closed beyond the fast settling interval. Closing must not
        // re-arm either compatibility worker before the next explicit open.
        if (root.attempts < 6) return
        if (slot.compatibilitySurfaceResolutionAttempts
              !== root.closedSurfaceAttempts
            || slot.compatibilityMeasurementRunning)
          return root.fail("closed panel re-armed compatibility polling")
        fakeBar.position = "top"
        root.phase = 4
        root.attempts = 0
        slot.activeItem.openOnDemand()
        return
      }

      if (!slot.activeItem.exposedPanel
          || !slot.compatibilityPanel || !slot.compatibilityCard) {
        if (root.attempts < 50) return
        return root.fail("standard panel behind Loader was not discovered")
      }
      if (slot.compatibilityPanel !== slot.activeItem.exposedPanel)
        return root.fail("adapter selected the wrong nested panel")
      if (slot.compatibilityPanel.objectName !== "nestedStandardKeyboardPanel"
          || slot.compatibilityCard.objectName !== "nestedStandardPanelCard")
        return root.fail("adapter did not preserve the standard panel/card pair")

      const expectedX = 700 + 12 - 210
      if (Math.abs(slot.compatibilityCard.x - expectedX) > 0.5)
        return root.fail("nested panel did not follow its invoking widget")
      if (slot.compatibilityPanel.contentHeight <= 120) {
        if (root.attempts < 50) return
        return root.fail("nested panel remained at its collapsed native height"
          + " measured=" + slot.compatibilityMeasuredContentHeight
          + " desired=" + slot.compatibilityDesiredContentHeight
          + " native=" + slot.compatibilityNativeContentHeight
          + " placement=" + slot.hostPanelPlacementEnabled
          + " repair=" + slot.hostPanelHeightRepairEnabled)
      }
      if (Math.abs(slot.compatibilityPanel.contentHeight - 384) > 0.5)
        return root.fail("nested panel did not recover its complete content height")

      if (root.phase === 1) {
        const expectedTopY = fakeBar.barSize + slot.compatibilityPanel.gap
        if (Math.abs(slot.compatibilityCard.y - expectedTopY) > 0.5)
          return root.fail("top panel remained at the screen bottom")
        root.firstLoadGeneration = slot.activeItem.loadGeneration
        root.phase = 2
        root.attempts = 0
        fakeBar.position = "bottom"
        return
      }

      if (root.phase === 2) {
        const expectedBottomY = slot.compatibilityPanel.screenH
          - fakeBar.barSize - slot.compatibilityPanel.contentHeight
          - slot.compatibilityPanel.gap
        if (Math.abs(slot.compatibilityCard.y - expectedBottomY) > 0.5)
          return root.fail("bottom panel did not follow the visible bar edge")
        root.phase = 3
        root.attempts = 0
        slot.activeItem.closeAndUnload()
        return
      }

      if (slot.activeItem.loadGeneration <= root.firstLoadGeneration)
        return root.fail("panel Loader did not create a fresh panel owner")
      const expectedReloadedTopY = fakeBar.barSize
        + slot.compatibilityPanel.gap
      if (Math.abs(slot.compatibilityCard.y - expectedReloadedTopY) > 0.5)
        return root.fail("reloaded top panel lost visible-edge placement")

      stop()
      console.log("hosted panel loader smoke passed")
      Qt.exit(0)
    }
  }
}
