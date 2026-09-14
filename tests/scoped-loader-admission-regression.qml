pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "hancore.shibumi.bar/core" as Core
import "hancore.shibumi.bar/services" as Services

ShellRoot {
  id: root

  readonly property string pluginId: "fixture.stock-widget"
  property int stage: 0
  property int stageAttempts: 0
  property int readyCalls: 0
  property int invalidReadyCalls: 0
  property int failedResolutionCalls: 0
  property int bogusIndex: 0
  property bool bogusPublished: false
  property var firstItem: null
  property var disabledItem: null
  property int stablePairChecks: 0
  property string injectionMode: ""
  property int injectionTransitions: 0
  property bool completionReplacementArmed: false
  property int completionReplacements: 0
  property bool invalidationReplacementArmed: false
  property int invalidationReplacements: 0
  property var invalidationItem: null
  property int invalidationStableChecks: 0
  property var errorComponent: null
  property bool observedErrorLoading: false

  function fail(message) {
    console.error("scoped-loader-admission-regression:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  function entry(component, metadataId) {
    return {
      component: component,
      metadata: { pluginId: metadataId === undefined ? pluginId : metadataId,
        displayName: "Scoped stock fixture" }
    }
  }

  function publish(registry, component, metadataId) {
    const next = ({})
    next[pluginId] = entry(component, metadataId)
    registry.widgets = next
    registry.revision++
  }

  function clearRegistry(registry) {
    registry.widgets = ({})
    registry.revision++
  }

  function runInjectionTransition() {
    const mode = injectionMode
    injectionMode = ""
    injectionTransitions++
    if (mode === "revoke") {
      clearRegistry(registryA)
      slot.resolvedComponent = null
    } else if (mode === "replace") {
      publish(registryA, widgetB, pluginId)
      slot.resolvedComponent = widgetB
    } else {
      fail("unexpected property-injection transition " + mode)
    }
  }

  function configuredBarConfig(enabled) {
    return {
      layout: {
        left: [{ id: pluginId, enabled: enabled !== false }],
        center: [], right: []
      }
    }
  }

  function loaded(component, marker, expectedCalls) {
    return slot.resolvedComponent === component
      && slot.loadedSourceComponent === component
      && slot.loadedItem === slot.activeItem
      && slot.loaderActive && slot.loaderStatus === Loader.Ready
      && slot.loaderHasItem && slot.activeItem
      && slot.activeItem.marker === marker
      && slot.currentLoadReady()
      && readyCalls === expectedCalls && invalidReadyCalls === 0
  }

  Component {
    id: widgetA
    Item {
      readonly property string marker: "A"
      implicitWidth: 20
      implicitHeight: 20
    }
  }

  Component {
    id: widgetB
    Item {
      readonly property string marker: "B"
      implicitWidth: 22
      implicitHeight: 20
    }
  }

  Component {
    id: injectionWidget
    Item {
      readonly property string marker: "injection"
      property var bar: null
      implicitWidth: 24
      implicitHeight: 20
      onBarChanged: {
        if (bar !== null) root.runInjectionTransition()
      }
    }
  }

  QtObject { id: foreignObject; property int status: Component.Ready }

  QtObject {
    id: scopedFacadeA
    readonly property string pluginId: root.pluginId
  }

  QtObject {
    id: scopedFacadeB
    readonly property string pluginId: root.pluginId
  }

  QtObject {
    id: registryA
    property int revision: 0
    property var widgets: {
      const value = ({})
      value[root.pluginId] = root.entry(widgetA, root.pluginId)
      return value
    }
  }

  QtObject {
    id: registryB
    property int revision: 0
    property var widgets: ({})
  }

  QtObject {
    id: fakeBar
    property var pluginRegistry: scopedFacadeA
    property var barWidgetRegistry: registryA
    property var barConfig: root.configuredBarConfig(true)
    property var hostWidgetResolver: resolver
    property var activePopout: null
    property var visualTokens: null
    property var pendingTooltipTarget: null
    property var tooltipTarget: null
    property bool vertical: false
    property real barSize: 32
    property string position: "top"
    property var slots: []
    property int registerCalls: 0

    function entryId(value) { return String(value && value.id || value || "") }
    function entrySettings(value) { return value && typeof value === "object" ? value : ({}) }
    function registeredWidgetComponent(id) { return resolver.componentFor(id) }
    function registerModuleSlot(value) {
      registerCalls++
      slots = [value]
    }
    function unregisterModuleSlot(_value) { slots = [] }
    function hideTooltip(_owner) {}
    function showTooltip(_owner, _text) {}
    function releasePopout(_owner) {}
    function noteHostWidgetResolution(value, ready) {
      if (ready === false) {
        failedResolutionCalls++
        return true
      }
      if (ready !== true || !value || !value.currentLoadReady()
          || registerCalls !== 1 || slots.length !== 1
          || slots[0] !== value || value.slotComplete !== true) {
        invalidReadyCalls++
        return false
      }
      readyCalls++
      return true
    }
  }

  Services.HostWidgetResolver {
    id: resolver
    bar: fakeBar
  }

  Core.WidgetSlot {
    id: slot
    bar: fakeBar
    entry: ({ id: root.pluginId })
    width: 32
    height: 32
  }

  Connections {
    target: slot

    function onLoadedItemChanged() {
      if (!root.completionReplacementArmed || slot.loadedItem === null) return
      root.completionReplacementArmed = false
      root.completionReplacements++
      root.publish(registryA, widgetB, root.pluginId)
      slot.resolvedComponent = widgetB
    }

    function onLoadedSourceComponentChanged() {
      if (!root.invalidationReplacementArmed
          || slot.loadedSourceComponent !== null) return
      root.invalidationReplacementArmed = false
      root.invalidationReplacements++
      // Re-enter from the first completion-invalidation write. A remains the
      // latest authorized source, so the stale outer B request must never
      // reach the Loader setter. Reusing A also exercises a no-op native setter.
      root.publish(registryA, widgetA, root.pluginId)
      slot.resolvedComponent = widgetA
    }
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.stageAttempts++
      if (root.stageAttempts > 150)
        return root.fail("timed out at stage " + root.stage)

      if (root.stage === 0) {
        if (!root.loaded(widgetA, "A", 1)) return
        root.firstItem = slot.activeItem
        root.stage = 1
      } else if (root.stage === 1) {
        // Let deferred Loader.item/activeItem notifications settle. They must
        // preserve the exact already-confirmed source/item pair.
        if (!root.loaded(widgetA, "A", 1)
            || slot.activeItem !== root.firstItem)
          return root.fail("delayed alias notification lost exact success")
        root.stablePairChecks++
        if (root.stablePairChecks < 3) return
        root.publish(registryA, widgetB, root.pluginId)
        if (slot.currentLoadReady())
          return root.fail("replacement retained current success before reload")
        root.stage = 2
      } else if (root.stage === 2) {
        if (!root.loaded(widgetB, "B", 2)) return
        if (slot.activeItem === root.firstItem)
          return root.fail("A to B replacement retained the old item")
        root.clearRegistry(registryA)
        root.stage = 3
      } else if (root.stage === 3) {
        if (slot.resolvedComponent !== null || slot.loaderHasItem) return
        const bogus = [
          null,
          undefined,
          foreignObject,
          ({ status: Component.Ready }),
          ({ status: Component.Ready, createObject: function() { return null } }),
          "not-a-component"
        ]
        if (root.bogusIndex < bogus.length) {
          if (!root.bogusPublished) {
            root.publish(registryA, bogus[root.bogusIndex], root.pluginId)
            root.bogusPublished = true
            return
          }
          if (slot.resolvedComponent !== null || slot.loaderHasItem
              || root.readyCalls !== 2 || root.invalidReadyCalls !== 0)
            return root.fail("bogus candidate reached Loader at index " + root.bogusIndex)
          root.bogusPublished = false
          root.bogusIndex++
          return
        }
        if (!root.bogusPublished) {
          root.publish(registryA, widgetA, "fixture.wrong-id")
          root.bogusPublished = true
          return
        }
        if (slot.resolvedComponent !== null || slot.loaderHasItem)
          return root.fail("mismatched metadata identity was admitted")
        root.errorComponent = Qt.createComponent(
          Qt.resolvedUrl("fixtures/ScopedLoaderBroken.qml"),
          Component.Asynchronous)
        if (!(root.errorComponent instanceof Component)
            || (root.errorComponent.status !== Component.Loading
              && root.errorComponent.status !== Component.Error))
          return root.fail("failed to construct an asynchronous error Component")
        root.observedErrorLoading = root.errorComponent.status
          === Component.Loading
        root.publish(registryA, root.errorComponent, root.pluginId)
        root.stage = 4
      } else if (root.stage === 4) {
        if (root.errorComponent.status === Component.Loading) {
          root.observedErrorLoading = true
          if (slot.loaderHasItem || slot.loadedSourceComponent !== null
              || slot.currentLoadReady() || root.readyCalls !== 2)
            return root.fail("asynchronous loading claimed success before onLoaded")
          return
        }
        if (slot.resolvedComponent !== root.errorComponent
            || slot.loaderStatus !== Loader.Error) return
        if (!root.observedErrorLoading)
          return root.fail("error Component never exercised asynchronous loading")
        if (slot.loaderHasItem || slot.loadedSourceComponent !== null
            || slot.currentLoadReady() || root.readyCalls !== 2)
          return root.fail("Loader.Error claimed successful loading")
        root.publish(registryA, widgetA, root.pluginId)
        root.stage = 5
      } else if (root.stage === 5) {
        if (!root.loaded(widgetA, "A", 3)) return
        root.disabledItem = slot.activeItem
        slot.entry = ({ id: root.pluginId, enabled: false })
        root.stage = 6
      } else if (root.stage === 6) {
        if (slot.moduleEnabled || slot.loaderActive || slot.loaderHasItem) return
        if (slot.loadedSourceComponent !== null || slot.loadedItem !== null
            || slot.currentLoadReady() || root.readyCalls !== 3)
          return root.fail("disabled module retained successful loading")
        slot.entry = ({ id: root.pluginId })
        root.stage = 7
      } else if (root.stage === 7) {
        if (!root.loaded(widgetA, "A", 4)) return
        if (slot.activeItem === root.disabledItem)
          return root.fail("same-handle reload retained the disabled item")
        fakeBar.barConfig = ({ layout: { left: [], center: [], right: [] } })
        root.stage = 8
      } else if (root.stage === 8) {
        if (slot.resolvedComponent !== null || slot.loaderHasItem) return
        if (slot.currentLoadReady() || root.readyCalls !== 4)
          return root.fail("removed configuration retained successful loading")
        fakeBar.barConfig = root.configuredBarConfig(true)
        root.stage = 9
      } else if (root.stage === 9) {
        if (!root.loaded(widgetA, "A", 5)) return
        fakeBar.barWidgetRegistry = null
        if (slot.currentLoadReady())
          return root.fail("registry loss retained current success")
        root.stage = 10
      } else if (root.stage === 10) {
        if (slot.resolvedComponent !== null || slot.loaderHasItem) return
        root.publish(registryB, widgetB, root.pluginId)
        fakeBar.barWidgetRegistry = registryB
        root.stage = 11
      } else if (root.stage === 11) {
        if (!root.loaded(widgetB, "B", 6)) return
        fakeBar.barWidgetRegistry = null
        fakeBar.pluginRegistry = null
        root.stage = 12
      } else if (root.stage === 12) {
        if (slot.resolvedComponent !== null || slot.loaderHasItem) return
        root.publish(registryA, widgetA, root.pluginId)
        fakeBar.pluginRegistry = scopedFacadeB
        fakeBar.barWidgetRegistry = registryA
        root.stage = 13
      } else if (root.stage === 13) {
        if (!root.loaded(widgetA, "A", 7)) return
        root.injectionMode = "revoke"
        root.publish(registryA, injectionWidget, root.pluginId)
        root.stage = 14
      } else if (root.stage === 14) {
        if (root.injectionTransitions < 1) return
        if (slot.resolvedComponent !== null || slot.loaderHasItem
            || slot.loadedSourceComponent !== null || slot.loadedItem !== null
            || slot.currentLoadReady() || root.readyCalls !== 7
            || root.invalidReadyCalls !== 0)
          return root.fail("revocation during property injection claimed success")
        root.injectionMode = "replace"
        root.publish(registryA, injectionWidget, root.pluginId)
        root.stage = 15
      } else if (root.stage === 15) {
        if (!root.loaded(widgetB, "B", 8)) return
        if (root.injectionTransitions !== 2)
          return root.fail("replacement injection transition count drifted")
        root.completionReplacementArmed = true
        root.publish(registryA, widgetA, root.pluginId)
        root.stage = 16
      } else if (root.stage === 16) {
        if (!root.loaded(widgetB, "B", 9)) return
        if (root.completionReplacements !== 1
            || root.completionReplacementArmed)
          return root.fail("completion publication reentrancy was not bounded")
        root.publish(registryA, widgetA, root.pluginId)
        slot.resolvedComponent = widgetA
        root.stage = 17
      } else if (root.stage === 17) {
        if (!root.loaded(widgetA, "A", 10)) return
        root.invalidationItem = slot.activeItem
        root.invalidationReplacementArmed = true
        root.publish(registryA, widgetB, root.pluginId)
        slot.resolvedComponent = widgetB
        root.stage = 18
      } else if (root.stage === 18) {
        if (root.invalidationReplacements !== 1
            || root.invalidationReplacementArmed) return
        if ((slot._dispatchedSubmission
              && slot._dispatchedSubmission.source === widgetB)
            || (slot.activeItem && slot.activeItem.marker === "B"))
          return root.fail("invalidation reentry dispatched stale source B")
        if (!root.loaded(widgetA, "A", 10)
            || !slot._dispatchedSubmission
            || slot._dispatchedSubmission.source !== widgetA
            || slot.activeItem !== root.invalidationItem) return
        root.invalidationStableChecks++
        if (root.invalidationStableChecks < 3) return
        console.log("scoped loader admission regression passed")
        Qt.quit()
      }
      root.stageAttempts = 0
    }
  }
}
