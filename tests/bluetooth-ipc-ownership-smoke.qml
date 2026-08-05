pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "bluetooth" as Bluetooth
import "fixtures" as Fixtures

ShellRoot {
  id: root

  readonly property string requestedOrder: Quickshell.env("SHIBUMI_BT_IPC_ORDER")
  readonly property bool validOrder: requestedOrder === "service-first"
    || requestedOrder === "backend-first"
  readonly property bool ready: validOrder && serviceLoader.item
    && backendLoader.item && serviceLoader.item.ready
    && serviceLoader.item.backend === backendLoader.item
  property int stateGeneration: 0
  property int settledStateGeneration: 0
  property string settledStateValue: ""

  function fixtureBluetoothState() {
    if (!ready) return "loading"
    return [
      backendLoader.item.fakeAdapter.enabled ? 1 : 0,
      backendLoader.item.fakeAdapter.discovering ? 1 : 0
    ].join(":")
  }

  function scheduleSettledBluetoothState() {
    stateGeneration++
    const generation = stateGeneration
    Qt.callLater(function() {
      root.settledStateValue = root.fixtureBluetoothState()
      root.settledStateGeneration = generation
    })
    return String(generation)
  }

  function startOrderedOwners() {
    if (!validOrder) {
      console.error("bluetooth-ipc-ownership: invalid order", requestedOrder)
      Qt.exit(2)
      return
    }

    if (requestedOrder === "backend-first") {
      backendLoader.sourceComponent = backendComponent
      secondLoaderTimer.start()
    } else {
      serviceLoader.sourceComponent = serviceComponent
      secondLoaderTimer.start()
    }
  }

  Component.onCompleted: startOrderedOwners()

  Item {
    id: fakeBar

    visible: false
    width: 0
    height: 0
    property bool vertical: false
    property int barSize: 35
    property int sizeHorizontal: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: []
    property var shell: null
    property var barWidgetRegistry: null
    property bool bluetoothOpen: false
    property int summonCount: 0
    property int hideCount: 0

    function registeredWidgetSource(_id) { return "" }
    function registeredWidgetComponent(_id) { return null }
    function widgetSettings(_group, _module) { return ({}) }
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
    function summonBarWidget(id) {
      if (id !== "omarchy.bluetooth") return false
      summonCount++
      bluetoothOpen = true
      return true
    }
    function hideBarWidget(id) {
      if (id !== "omarchy.bluetooth") return false
      hideCount++
      bluetoothOpen = false
      return true
    }
    function isBarWidgetOpen(id) {
      return id === "omarchy.bluetooth" && bluetoothOpen
    }
  }

  Component {
    id: backendComponent
    Fixtures.BluetoothTestBackend {}
  }

  Component {
    id: serviceComponent
    Bluetooth.Service {
      bar: fakeBar
      backendOverride: backendLoader.item
    }
  }

  Loader { id: backendLoader }
  Loader { id: serviceLoader }

  Timer {
    id: secondLoaderTimer
    interval: 80
    repeat: false
    onTriggered: {
      if (root.requestedOrder === "backend-first")
        serviceLoader.sourceComponent = serviceComponent
      else
        backendLoader.sourceComponent = backendComponent
    }
  }

  IpcHandler {
    target: "shibumi-bluetooth-ipc-test"

    function ping(): string {
      return root.ready ? "ready:" + root.requestedOrder : "loading"
    }
    function state(): string {
      if (!root.ready) return "loading"
      return [
        fakeBar.bluetoothOpen ? 1 : 0,
        fakeBar.summonCount,
        fakeBar.hideCount,
        backendLoader.item.toggleCount,
        backendLoader.item.fakeAdapter.enabled ? 1 : 0,
        backendLoader.item.fakeAdapter.discovering ? 1 : 0
      ].join(":")
    }
    function bluetoothState(): string {
      return root.fixtureBluetoothState()
    }
    function settleBluetoothState(): string {
      if (!root.ready) return "loading"
      return root.scheduleSettledBluetoothState()
    }
    function restoreBluetooth(snapshot: string): string {
      if (!root.ready) return "loading"
      const values = String(snapshot || "").split(":")
      if (values.length !== 2) return "invalid"
      backendLoader.item.fakeAdapter.enabled = values[0] === "1"
      backendLoader.item.fakeAdapter.discovering = values[1] === "1"
      return root.scheduleSettledBluetoothState()
    }
    function settledBluetoothState(generation: int): string {
      if (root.settledStateGeneration < generation) return "pending"
      return root.settledStateValue
    }
    function mutateBluetoothForAbort(): string {
      if (!root.ready) return "loading"
      backendLoader.item.fakeAdapter.enabled =
        !backendLoader.item.fakeAdapter.enabled
      backendLoader.item.fakeAdapter.discovering =
        !backendLoader.item.fakeAdapter.discovering
      return root.fixtureBluetoothState()
    }
  }
}
