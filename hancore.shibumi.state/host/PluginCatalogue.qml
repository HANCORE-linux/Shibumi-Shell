import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: catalogue

  property var bar: null
  property var barHost: null
  readonly property string pluginsDir: decodeURIComponent(
    String(Qt.resolvedUrl("../..")).replace(/^file:\/\//, "").replace(/\/+$/, ""))
  readonly property string firstPartyDir:
    (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/shell/plugins"
  property var installedPlugins: ({})
  property var pluginStates: ({})
  property int registryRevision: 0
  property bool scanning: false
  property bool rescanPending: false
  property string lastEnableError: ""

  signal pluginsChanged()

  function isPlainObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value)
  }

  function isEnabled(id) {
    const state = pluginStates[String(id || "")]
    return !!state && state.enabled === true
  }

  function entryPointUrl(manifest, kind) {
    if (!isPlainObject(manifest) || !isPlainObject(manifest.entryPoints)) return ""
    const entry = manifest.entryPoints[String(kind || "")]
    const dir = String(manifest.__sourceDir || "").replace(/\/$/, "")
    if (!entry || !dir) return ""
    const resolved = dir + "/" + String(entry)
    if (resolved.indexOf(dir + "/") !== 0 || String(entry).indexOf("..") !== -1) return ""
    return "file://" + resolved.split("/").map(encodeURIComponent).join("/")
  }

  function setEnabled(id, value, placement) {
    const key = String(id || "")
    if (!key || !installedPlugins[key]) return false
    lastEnableError = ""
    const command = value === true && isPlainObject(placement)
      ? ["omarchy-shell", "shell", "enablePlugin", key, JSON.stringify(placement)]
      : ["omarchy-shell", "shell", "setPluginEnabled", key, value === true ? "true" : "false"]
    Quickshell.execDetached(command)
    const next = ({})
    for (const existing in pluginStates) next[existing] = pluginStates[existing]
    next[key] = { enabled: value === true }
    pluginStates = next
    requestRescan()
    return true
  }

  function requestRescan() {
    rescanDebounce.restart()
  }

  function rescan() {
    if (scanning) {
      rescanPending = true
      return
    }
    scanning = true
    scanProcess.running = true
  }

  function validated(manifest, sourceDir, firstParty) {
    if (!isPlainObject(manifest) || manifest.schemaVersion !== 1) return null
    const id = String(manifest.id || "")
    if (!id || id.indexOf("/") !== -1 || id.indexOf("..") !== -1) return null
    if (!Array.isArray(manifest.kinds) || manifest.kinds.length === 0) return null
    if (!isPlainObject(manifest.entryPoints)) return null
    manifest.__sourceDir = sourceDir
    manifest.__isFirstParty = firstParty
    return manifest
  }

  function parseScanOutput(text) {
    const lines = String(text || "").split("\n")
    const firstParty = ({})
    const thirdParty = ({})
    let states = []
    let currentSource = null
    let currentKind = null
    let currentJson = []
    let inStates = false
    const stateLines = []

    function flush() {
      if (!currentSource) return
      try {
        const manifest = validated(JSON.parse(currentJson.join("\n")),
          currentSource, currentKind === "firstparty")
        if (manifest) {
          if (currentKind === "firstparty") firstParty[manifest.id] = manifest
          else thirdParty[manifest.id] = manifest
        }
      } catch (error) {
        console.warn("Shibumi plugin catalogue: bad manifest at " + currentSource + ": " + error)
      }
      currentSource = null
      currentKind = null
      currentJson = []
    }

    for (let index = 0; index < lines.length; index++) {
      const line = lines[index]
      if (inStates) {
        stateLines.push(line)
        continue
      }
      if (line === "=== STATES ===") {
        flush()
        inStates = true
        continue
      }
      const start = line.match(/^===([a-z]+)::(.+)===$/)
      if (start) {
        flush()
        currentKind = start[1]
        currentSource = start[2].replace(/\/$/, "")
        currentJson = []
        continue
      }
      if (line === "=== EOM ===") {
        flush()
        continue
      }
      if (currentSource) currentJson.push(line)
    }
    flush()
    try {
      const parsed = JSON.parse(stateLines.join("\n").trim() || "[]")
      if (Array.isArray(parsed)) states = parsed
    } catch (error) {
      console.warn("Shibumi plugin catalogue: bad plugin state list: " + error)
    }

    const merged = ({})
    for (const firstPartyId in firstParty) merged[firstPartyId] = firstParty[firstPartyId]
    for (const thirdPartyId in thirdParty) {
      if (firstParty[thirdPartyId] || thirdPartyId.indexOf("omarchy.") === 0) continue
      merged[thirdPartyId] = thirdParty[thirdPartyId]
    }
    const nextStates = ({})
    for (let index = 0; index < states.length; index++) {
      const state = states[index]
      if (isPlainObject(state) && state.id) nextStates[String(state.id)] = state
    }

    installedPlugins = merged
    pluginStates = nextStates
    registryRevision++
    scanning = false
    pluginsChanged()
    if (rescanPending) {
      rescanPending = false
      rescan()
    }
  }

  readonly property string scanScript: "emit_manifest() { local kind=\"$1\" manifest=\"$2\" sub; "
    + "if [[ ${manifest##*/} == manifest.json ]]; then sub=${manifest%/manifest.json}; else sub=$(dirname -- \"$manifest\"); fi; "
    + "printf '===%s::%s===\\n' \"$kind\" \"$sub\"; cat -- \"$manifest\"; printf '\\n=== EOM ===\\n'; }; "
    + "if [[ -d $0 ]]; then while IFS= read -r manifest; do emit_manifest firstparty \"$manifest\"; done "
    + "< <(find \"$0\" -mindepth 2 -maxdepth 3 -type f \\( -name manifest.json -o -name '*.manifest.json' \\) | sort); fi; "
    + "if [[ -d $1 ]]; then for sub in \"$1\"/*/; do [[ -f $sub/manifest.json ]] && emit_manifest thirdparty \"$sub/manifest.json\"; done; fi; "
    + "printf '=== STATES ===\\n'; omarchy-shell shell listPlugins 2>/dev/null || printf '[]\\n'"

  property Process scanProcess: Process {
    command: ["bash", "-c", catalogue.scanScript, catalogue.firstPartyDir, catalogue.pluginsDir]
    stdout: StdioCollector {
      id: scanOutput
      waitForEnd: true
    }
    onExited: catalogue.parseScanOutput(scanOutput.text)
  }

  property Timer rescanDebounce: Timer {
    interval: 150
    onTriggered: catalogue.rescan()
  }

  property Connections barHostConnections: Connections {
    target: catalogue.barHost
    ignoreUnknownSignals: true
    function onBarConfigChanged() { catalogue.requestRescan() }
  }

  property Connections widgetCatalogueConnections: Connections {
    target: catalogue.bar && catalogue.bar.barWidgetRegistry
      ? catalogue.bar.barWidgetRegistry : null
    ignoreUnknownSignals: true
    function onRevisionChanged() { catalogue.requestRescan() }
  }

  onBarChanged: requestRescan()
  Component.onCompleted: rescan()
}
