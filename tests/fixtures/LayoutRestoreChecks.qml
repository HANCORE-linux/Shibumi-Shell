import QtQuick
import Quickshell
import "../hancore.shibumi.bar/core/V2LayoutModel.js" as Layout
import "../hancore.shibumi.bar" as Host

// Actual Bar/coordinator/restore, complete inert State + native writer. Their
// publication clocks are deliberately separate; no FileView or host helper.
Scope {
  id: root
  required property var referenceBar
  readonly property alias bar: testBar
  Host.Bar {
    id: testBar
    outputWindowsEnabled: false
    omarchyPath: root.referenceBar.omarchyPath
    manifest: root.referenceBar.manifest
    shell: native
    pluginRegistry: root.referenceBar.pluginRegistry
    barWidgetRegistry: root.referenceBar.barWidgetRegistry
  }
  property bool started: false
  property bool done: false
  property int phase: 0
  property double began: 0
  property var saved: null
  function copy(value) { return JSON.parse(JSON.stringify(value)) }
  function check(value, message) {
    if (value) return
    console.error("layout-restore:", message); Qt.exit(1); throw new Error(message)
  }
  component Panel: QtObject {
    property bool opened: false
    property bool panelLoaded: true
    property var panelItem: ({settingsPage: "catalog"})
    property int opens: 0
    function openPage(page) { opens++; opened = true; panelItem = {settingsPage: page} }
    function open() { openPage("catalog") }
    function close() { opened = false }
  }
  Panel { id: oldPanel; opened: true }
  Panel { id: replacement }
  QtObject {
    id: slot
    property string moduleName: "hancore.shibumi.control-center"
    property string screenName: "layout-fixture-output"
    property bool visible: true
    property var activeItem: oldPanel
  }
  QtObject {
    id: state
    property bool ready: true
    property bool writePending: false
    property int writeSerial: 0
    property int revision: 0
    property var config: ({})
    property var desired: null
    signal persistenceSettled(int serial, string result)
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    function normalizedLayoutFamilyPatch(value) { return value && Layout.valid(value.v2Layout) ? root.copy(value) : null }
    function layoutFamilySnapshot(value) { return {v2Layout: root.copy(config.v2Layout)} }
    function setLayoutFamilyTransition(value) {
      desired = root.copy(value); writeSerial++; writePending = true; return true
    }
    function compensateLayoutFamilyTransition(serial, expected, rollback) { return false }
    function publish() {
      config = Object.assign({}, config, desired); revision++; writePending = false
      persistenceSettled(writeSerial, "confirmed")
    }
  }
  QtObject {
    id: native
    property var actual: null
    property int calls: 0
    function mutateShellConfig(callback) {
      calls++
      const value = {bar: root.copy(actual)}; callback(value); actual = value.bar
      return true // Publication into bar.barConfig is deliberately delayed.
    }
  }
  function start() {
    if (started) return
    started = true
    saved = {shell: bar.shell, state: bar.layoutController.stateService,
      config: copy(bar.barConfig), slots: bar.moduleSlots}
    const initial = Layout.defaultLayout(); initial.left.push("G:example.restore")
    state.config = {v2Layout: initial, presentation: {shellStyle: "shibumi"}}
    native.actual = {id: "fixture.bar", layout: {left: [{id: "example.restore"}], center: [], right: []}}
    bar.layoutController.stateService = state
    bar.shell = native; bar.barConfig = copy(native.actual); bar.moduleSlots = [slot]
    const target = copy(initial); target.left.pop(); target.right[target.right.length - 1] = "G:example.restore"
    check(bar.runWithControlCenterRestore(function() { return root.bar.layoutController.persistV2Layout(target) },
      "catalog", true, oldPanel, slot.screenName), "transition restore request refused")
    check(bar.pendingWidgetRestores.length === 1 && bar.pendingWidgetRestores[0].waitingLayout > 0,
      "transition restore did not enroll")
    state.publish()
    timer.start()
  }
  Timer {
    id: timer
    interval: 20; repeat: true
    onTriggered: {
      if (root.phase === 0) {
        if (!native.calls) return
        root.began = Date.now(); root.phase = 1
      }
      if (root.phase === 1) {
        const records = root.bar.pendingWidgetRestores
        root.check(root.bar.layoutTransitionBusy && records.length === 1
          && records[0].waitingWrites.length === 0 && records[0].waitingLayout > 0
          && records[0].attempts === 0 && oldPanel.opens === 0 && replacement.opens === 0,
          "native publication wait spent restore window")
        if (Date.now() - root.began < 1800) return
        slot.activeItem = replacement
        root.bar.barConfig = root.copy(native.actual)
        root.phase = 2
        return
      }
      if (root.bar.layoutTransitionBusy || root.bar.pendingWidgetRestores.length) return
      root.check(root.bar.layoutTransitionResult === "confirmed" && replacement.opened
        && replacement.panelItem.settingsPage === "catalog", "replacement did not restore after native publication")
      stop()
      root.bar.moduleSlots = root.saved.slots
      root.bar.shell = root.saved.shell
      root.bar.layoutController.stateService = root.saved.state
      root.bar.barConfig = root.saved.config
      root.done = true
      console.log("actual Bar restoration waited for separate native publication passed")
    }
  }
}
