pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as StatePlugin
import "host" as Host
import "bar" as BarProbe

ShellRoot {
  id: root
  property int ticks: 0
  property bool checked: false
  property bool finishRequested: false
  property int phase: 0
  property var document: null
  FileView {
    id: writer
    path: Quickshell.env("XDG_CONFIG_HOME") + "/omarchy/shell.json"
    atomicWrites: true
    onLoaded: root.document = JSON.parse(text())
  }

  Host.PluginShellApi {
    id: host
    pluginId: "hancore.shibumi.state"
    barConfig: ({ shibumi: { version: 1, presentation: { accent: "color07" } },
      transparent: true, unrelated: { retained: [1, 2] } })
    // Neither the detached Bar snapshot nor wider poisoned authority is State storage.
    property var shellConfig: ({ bar: { shibumi: {
      version: 1, presentation: { accent: "color03" }
    } } })
  }

  StatePlugin.Service {
    id: state
    shell: host
    omarchyPath: Quickshell.env("OMARCHY_PATH")
    manifest: ({ id: "hancore.shibumi.state", version: "0.1.1-beta.15.1",
      kinds: ["service"], __sourceDir: Quickshell.env("DECOY_MARKER_DIR") })
  }
  BarProbe.Marker {
    id: bar
    manifest: ({ id: "hancore.shibumi.bar", __sourceDir: Quickshell.env("DECOY_MARKER_DIR") })
  }

  function check(value, message) {
    if (value) return
    console.error("scoped-state-regression: " + message)
    Qt.exit(1)
    throw new Error(message)
  }

  function mutations(loaded) {
    if (!loaded) {
      check(!state.ready && !state.setGroupSetting("G4", "compact", true), "invalid marker admitted State")
      return true
    }
    if (!state.ready || !document || state.writePending) return false
    check(state.selectedAccent === "color04", "canonical configuration was not authoritative")
    if (phase === 0) {
      check(state.setGroupSetting("G4", "compact", true), "scoped request was not queued")
      check(!state.groupSetting("G4", "compact", false), "queued request published optimistically")
      phase++
    } else if (phase === 1) {
      check(state.writeStatus === "refused" && !state.groupSetting("G4", "compact", false)
        && !document.plugins[0].shibumi.widgets.G4.compact, "denied write changed file-backed state")
      host._mutateBarConfig = function(callback) { check(false, "State used a Bar writer"); return false }
      host._updateSettings = function(id, entry) {
        check(id === "hancore.shibumi.state" && entry.id === id, "foreign entry dispatch")
        const next = JSON.parse(JSON.stringify(document))
        next.plugins[0] = entry
        document = next
        writer.setText(JSON.stringify(next))
        return true
      }
      check(state.setGroupSetting("G4", "compact", true), "own-entry request was not queued")
      phase++
    } else if (phase === 2) {
      check(state.writeStatus === "confirmed" && state.groupSetting("G4", "compact", false)
        && document.plugins[0].shibumi.widgets.G4.compact
        && JSON.stringify(document.plugins[0].foreign) === '{"retained":[1,false]}'
        && host.barConfig.shibumi.presentation.accent === "color07", "own-entry readback/preservation")
      state.shell = null
      check(!state.ready && !state.setGroupSetting("G4", "compact", false), "revoked scope accepted a write")
      state.shell = host
      host.barConfig = null
      phase++
    } else {
      check(state.groupSetting("G4", "compact", false), "scope recovery lost file truth or depended on Bar")
      return true
    }
    return false
  }

  IpcHandler {
    target: "scoped-state-test"
    function finish(): string { root.finishRequested = true; return "ok" }
  }
  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.check(++root.ticks < 400, "scoped State deadline " + state.writeStatus)
      if (root.finishRequested) {
        console.log("scoped state regression passed")
        stop()
        Qt.exit(0)
        return
      }
      if (root.checked) return
      const mode = Quickshell.env("MARKER_CASE")
      const loaded = mode === "valid" || mode === "wrong-digest"
      if (loaded && (!state.suitePayloadLoaded || !bar.suitePayloadLoaded)) {
        root.check(root.ticks < 100, "own entry-point marker did not load: state="
          + state.suitePayloadLoaded + " bar=" + bar.suitePayloadLoaded
          + " statePath=" + state.suiteMarkerPath + " barPath=" + bar.suiteMarkerPath)
        return
      }
      if (root.ticks < 20) return
      root.check(state.suitePayloadLoaded === loaded && bar.suitePayloadLoaded === loaded,
        "marker rejection or own-path authority failed")
      if (loaded) {
        const digest = (mode === "wrong-digest" ? "b" : "a").repeat(64)
        root.check(state.suitePayloadDigest === digest && bar.suitePayloadDigest === digest,
          "marker authority used a foreign manifest directory")
      }
      if (!root.mutations(loaded)) return
      root.checked = true
      console.log("scoped state regression ready")
    }
  }
}
