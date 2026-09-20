pragma ComponentBehavior: Bound

import QtQuick
import "staged/barcore" as Core

Item {
  id: root

  required property var hostState
  required property Component statusComponent
  required property Component centerComponent
  required property Component audioComponent
  required property Component networkComponent
  required property Component catalogComponent
  readonly property int creationId: hostState.allocateBarSerial()
  property var moduleSlots: []
  property var loadedOwners: []
  property var clickTargets: []
  property bool tearingDown: false
  property var activePopout: null
  property bool vertical: false
  property real barSize: 35
  property var visualTokens: null
  property string position: "top"
  property string fontFamily: "monospace"
  property color foreground: "#eeeeee"
  property color barForeground: foreground
  property color background: "#111111"
  property color urgent: "#88bbee"
  property bool foregroundAnimationEnabled: false
  property var shell: QtObject {
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.network"
        ? root.hostState.networkService : null
    }
  }
  property var v1FamilySlotBindings: ({})
  property var layoutConfig: ({
    left: [
      { id: "hancore.shibumi.status" },
      { id: "hancore.shibumi.center" },
      { id: "hancore.shibumi.audio" },
      { id: "hancore.shibumi.network" },
      { id: "hancore.shibumi.control-center" }
    ],
    center: [],
    right: []
  })
  property var pluginRegistry: QtObject {
    property string pluginId: "fixture.host"
  }
  property var layoutController: QtObject {
    property bool v2Mode: false
    function unplacedPluginIdsFor(specs) { return [] }
  }
  property var barWidgetRegistry: QtObject {
    property int revision: root.hostState.registryRevision
    property var widgets: {
      void(revision)
      const result = ({
        "hancore.shibumi.center": {
          metadata: { pluginId: "hancore.shibumi.center" },
          component: root.centerComponent
        },
        "hancore.shibumi.audio": {
          metadata: { pluginId: "hancore.shibumi.audio" },
          component: root.audioComponent
        },
        "hancore.shibumi.network": {
          metadata: { pluginId: "hancore.shibumi.network" },
          component: root.networkComponent
        },
        "hancore.shibumi.control-center": {
          metadata: { pluginId: "hancore.shibumi.control-center" },
          component: root.catalogComponent
        }
      })
      if (root.hostState.statusEnabled) {
        result["hancore.shibumi.status"] = {
          metadata: { pluginId: "hancore.shibumi.status" },
          component: root.statusComponent
        }
      }
      return result
    }
  }
  property Component loadedOwnerSentinel: Component {
    QtObject {
      id: sentinel
      required property Item slot
      required property string screenName
      Component.onCompleted: {
        root.loadedOwners = root.loadedOwners.concat([sentinel])
        root.hostState.ownerCreated++
      }
      Component.onDestruction: {
        root.loadedOwners = root.loadedOwners.filter(candidate => candidate !== sentinel)
        root.hostState.ownerReleased++
      }
    }
  }

  function entryId(entry) { return String(entry && entry.id || "") }
  function entrySettings(entry) { return entry || ({}) }
  function registerModuleSlot(slot) {
    if (moduleSlots.indexOf(slot) < 0) moduleSlots = moduleSlots.concat([slot])
  }
  function unregisterModuleSlot(slot) {
    moduleSlots = moduleSlots.filter(candidate => candidate !== slot)
  }
  function widgetSlotLoadAdmitted(slot) { return true }
  function claimLoadedOwner(slot, item) {
    return !!loadedOwnerSentinel.createObject(item, {
      slot: slot,
      objectName: slot.moduleName,
      screenName: slot.screenName
    })
  }
  function noteHostWidgetResolution(slot, ready) { return true }
  function registeredWidgetComponent(pluginId) {
    hostState.helperMarks.push("component:" + pluginId)
    return null
  }
  function registeredEmbeddedWidgetComponent(ownerId, pluginId) {
    hostState.helperMarks.push("embedded:" + ownerId + ":" + pluginId)
    return null
  }
  function registeredWidgetSource(pluginId) {
    hostState.helperMarks.push("source:" + pluginId)
    return ""
  }
  function activePluginSpecs() {
    hostState.helperMarks.push("catalog")
    return [{ pluginId: "fixture.provider" }]
  }
  function registerClickTarget(target) {
    if (clickTargets.indexOf(target) < 0) clickTargets = clickTargets.concat([target])
  }
  function unregisterClickTarget(target) {
    clickTargets = clickTargets.filter(candidate => candidate !== target)
  }
  function showTooltip(target, text) {}
  function hideTooltip(target) {}
  function releasePopout(target) {}

  Component.onDestruction: {
    tearingDown = true
    hostState.events.push("bar-destruction:" + creationId)
  }

  Core.WidgetSlot {
    bar: root
    entry: ({ id: "hancore.shibumi.status",
      enabled: root.hostState.statusEntryEnabled })
    region: root.hostState.slotRegion
    screenName: "fixture-output"
  }
  Core.WidgetSlot {
    bar: root
    entry: ({ id: "hancore.shibumi.center", enabled: true })
    region: root.hostState.slotRegion
    screenName: "fixture-output"
  }
  Core.WidgetSlot {
    bar: root
    entry: ({ id: "hancore.shibumi.audio", enabled: true })
    region: root.hostState.slotRegion
    screenName: "fixture-output"
  }
  Core.WidgetSlot {
    bar: root
    entry: ({ id: "hancore.shibumi.network", enabled: true })
    region: root.hostState.slotRegion
    screenName: "fixture-output"
  }
  Core.WidgetSlot {
    bar: root
    entry: ({ id: "hancore.shibumi.control-center", enabled: true })
    region: root.hostState.slotRegion
    screenName: "fixture-output"
  }
}
