import QtQuick
import Quickshell
import Quickshell.Io
import "StateStorageModel.js" as Model
import "ShibumiConfig.js" as Config

// One process-wide, read-only FileView pair; only the native own-entry API writes.
Item {
  id: root
  required property var host
  required property var authorityToken
  // Inherited Item.enabled is bound to the owning service's admission.
  required property string omarchyPath
  readonly property string userPath: (Quickshell.env("XDG_CONFIG_HOME")
    || (Quickshell.env("HOME") + "/.config")) + "/omarchy/shell.json"
  readonly property string defaultsPath: omarchyPath + "/config/omarchy/shell.json"
  readonly property bool ready: enabled && _entry !== null
  // An explicit publication permits synchronous cancellation from its notify
  // handler without recursively evaluating a binding over the cleared queue.
  readonly property alias pending: root._pending
  property bool _pending: false
  property var value: Config.defaultConfig()
  property string writeStatus: "idle"
  property int requestSerial: 0
  signal settled(int throughSerial, string result)
  property var _entry: null
  property var _desired: null
  property var _base: null
  property var _flight: null
  property bool _preparing: false
  property bool _useDefaults: false
  property bool _completed: false
  property bool _clearing: false

  function publishPending() {
    _pending = _desired !== null || _flight !== null || _preparing
  }

  function draft() {
    return Model.copy(_desired !== null ? _desired
      : _flight !== null ? _flight.value : value)
  }

  // true means queued, NOT saved. value/revision remain file-backed; callers
  // needing completion observe settled(throughSerial, "confirmed").
  function queue(next) {
    if (!ready || _clearing || !host || typeof host.updateEntryInline !== "function") return false
    if (!Model.finiteNumbers(next)) return false
    const proposed = Config.normalize(next)
    if (Model.same(proposed, draft())) return false
    const token = authorityToken
    const writer = host
    const serial = requestSerial + 1
    requestSerial = serial
    if (!ready || authorityToken !== token || host !== writer || requestSerial !== serial) return false
    if (_desired === null) _base = Model.copy(_flight ? _flight.value : value)
    _desired = Model.copy(proposed)
    publishPending()
    if (!ready || authorityToken !== token || host !== writer || _desired === null) return false
    writeStatus = "pending"
    if (!ready || authorityToken !== token || host !== writer || _desired === null) return false
    if (!_flight) debounce.restart()
    return true
  }

  function abandon(reason) {
    const serial = requestSerial
    const hadPending = pending
    _clearing = true
    debounce.stop()
    deadline.stop()
    _preparing = false
    _desired = null
    _base = null
    _flight = null
    publishPending()
    writeStatus = reason
    _clearing = false
    if (hadPending) settled(serial, reason)
  }

  function reset() {
    _entry = null
    abandon("unavailable")
    if (_completed && enabled) Qt.callLater(root.reloadUser)
  }

  function reloadUser() {
    if (!enabled || !_completed) return
    userFile.request()
  }

  function useDefaults() {
    if (!enabled) return
    if (!_useDefaults) _useDefaults = true
    else defaultsFile.request()
  }

  function accept(raw) {
    if (!enabled) return
    const entry = Model.parse(raw)
    if (!entry) {
      _entry = null
      abandon("invalid-config-or-migration-required")
      return
    }
    const observed = Config.normalize(entry.shibumi)
    const token = authorityToken
    const writer = host
    if (!Model.same(value, observed)) value = observed
    if (!enabled || authorityToken !== token || host !== writer) return
    _entry = entry // readiness must never precede the matching value
    if (!enabled || authorityToken !== token || host !== writer) return
    if (_flight) {
      const flight = _flight
      if (flight.token !== authorityToken) {
        abandon("unavailable")
        return
      }
      if (flight.dispatching) return
      if (Model.same(entry, flight.entry)) {
        deadline.stop()
        const result = flight.accepted ? "confirmed" : "unchanged"
        writeStatus = result
        if (!enabled || _flight !== flight || authorityToken !== token || host !== writer) return
        _flight = null
        publishPending()
        if (!enabled || authorityToken !== token || host !== writer) return
        settled(flight.serial, result)
        if (enabled && authorityToken === token && host === writer
            && _desired !== null && !_flight) debounce.restart()
      } else if (!Model.same(observed, flight.before)) {
        abandon("conflict")
      }
      return
    }
    if (_desired !== null && !Model.same(observed, _base)) {
      abandon("conflict")
      return
    }
    if (_preparing) dispatch()
  }

  function dispatch() {
    _preparing = false
    if (!enabled || !_entry || _desired === null || _flight) return
    const proposed = _desired
    const serial = requestSerial
    if (Model.same(value, proposed)) {
      abandon("unchanged")
      return
    }
    const flight = {entry: Model.replacement(_entry, value, proposed),
      value: Model.copy(proposed), before: Model.copy(value),
      serial: serial, token: authorityToken, dispatching: true, accepted: false}
    _flight = flight
    if (!enabled || _flight !== flight || authorityToken !== flight.token) return
    _desired = null
    if (!enabled || _flight !== flight || authorityToken !== flight.token) return
    _base = null
    // pending notifications can synchronously revoke our owner or queue more.
    if (!enabled || _flight !== flight || authorityToken !== flight.token) return
    let accepted = false
    try { accepted = host.updateEntryInline(Model.pluginId, Model.copy(flight.entry)) === true }
    catch (error) { accepted = false }
    if (!enabled || _flight !== flight || authorityToken !== flight.token) return
    flight.dispatching = false
    flight.accepted = accepted
    deadline.restart()
    // A pre-write cached read is not confirmation. Reload and then wait for
    // actual file publication; atomic replacement events also trigger reload.
    Qt.callLater(root.reloadUser)
  }

  onEnabledChanged: reset()
  onAuthorityTokenChanged: reset()
  onHostChanged: reset()
  Component.onCompleted: { _completed = true; reset() }
  Component.onDestruction: { _completed = false; debounce.stop(); deadline.stop() }

  Timer {
    id: debounce
    interval: 75
    onTriggered: {
      if (!root.ready || root._desired === null || root._flight) return
      root._preparing = true
      deadline.restart()
      root.reloadUser() // fresh complete entry, preserving foreign fields
    }
  }
  Timer {
    id: deadline
    interval: 2000
    onTriggered: root.abandon(root._flight && !root._flight.accepted
      ? "refused" : "readback-timeout")
  }
  // FileView coalesces reload() into an already running read. Keep a dirty
  // request until that read finishes, then reread after its loaded handler
  // unwinds. Otherwise a file event during a pre-write read can be lost.
  component ConfigReader: FileView {
    id: reader
    property bool reading: false
    property bool dirty: false
    signal snapshot(string raw)
    signal failure(int error)
    preload: false
    blockLoading: false
    blockAllReads: false
    watchChanges: path !== ""
    printErrors: false
    function request() {
      if (path === "") return
      dirty = true
      Qt.callLater(reader.drain)
    }
    function drain() {
      if (path === "" || reading || !dirty) return
      dirty = false
      reading = true
      reload()
      text() // start acquisition; this immediate cached result is NOT readback
    }
    function finish(error) {
      reading = false
      if (path === "") return
      if (dirty) { Qt.callLater(reader.drain); return }
      if (error === 0) snapshot(text())
      else failure(error)
    }
    onPathChanged: { reading = false; dirty = false; request() }
    onFileChanged: request()
    onLoaded: finish(0)
    onLoadFailed: function(error) { finish(error) }
  }
  ConfigReader {
    id: userFile
    path: root.enabled ? root.userPath : ""
    onSnapshot: function(raw) {
      if (!root.enabled) return
      if (raw.length === 0) root.useDefaults()
      else { root._useDefaults = false; root.accept(raw) }
    }
    onFailure: function(error) {
      if (!root.enabled) return
      if (error === FileViewError.FileNotFound) root.useDefaults()
      else { root._entry = null; root.abandon("read-error") }
    }
  }
  ConfigReader {
    id: defaultsFile
    path: root.enabled && root._useDefaults ? root.defaultsPath : ""
    onSnapshot: function(raw) { if (root.enabled && root._useDefaults) root.accept(raw) }
    onFailure: { if (root.enabled && root._useDefaults) {
      root._entry = null; root.abandon("defaults-read-error")
    } }
  }
}
