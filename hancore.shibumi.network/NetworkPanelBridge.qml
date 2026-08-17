pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Host Quattro's complete network component as a hidden backend. This bridge
// is instantiated once by NetworkService, never once per output.
Item {
  id: root

  required property var bar
  required property Item ownerWidget
  property var networkService: null
  property Component panelComponent: null
  property url panelSource: ""
  property var panelSettings: ({})

  readonly property var panel: panelLoader.item
  readonly property bool ready: panel !== null
  readonly property bool opened: ready && panel.opened === true
  readonly property bool backendAvailable: ready
    && panel.networkManagerAvailable !== undefined
    ? panel.networkManagerAvailable === true : false
  readonly property string kind: ready && panel.kind !== undefined
    ? String(panel.kind || "disconnected") : "disconnected"
  // Quattro exposed `label` in early panel revisions, then moved the live
  // Wi-Fi name to the native connected network object. Prefer the current
  // event-driven source and retain narrow fallbacks for older hosts and the
  // panel-only details sample.
  readonly property string label: !ready ? ""
    : kind === "wifi" && connectedWifiLabel() !== ""
      ? connectedWifiLabel()
    : panel.label !== undefined && String(panel.label || "") !== ""
      ? String(panel.label)
    : kind === "ethernet" && panel.info && panel.info.iface !== undefined
      ? String(panel.info.iface || "") : ""
  readonly property int signalStrength: ready
    && panel.signalStrength !== undefined
    ? Math.max(0, Math.min(100, Number(panel.signalStrength) || 0)) : 0
  readonly property bool scanning: ready && panel.scanning !== undefined
    ? panel.scanning === true : false
  readonly property bool busy: ready && panel.busy !== undefined
    ? panel.busy === true : false
  property string pendingPresentationMode: ""
  property int presentationAttempts: 0
  property bool backendIpcSuppressed: false
  property var presentationOwner: null
  readonly property bool externalQrOpen: hostShellProxy.realShell
    && typeof hostShellProxy.realShell.isPluginOpen === "function"
    ? hostShellProxy.realShell.isPluginOpen("omarchy.wifiqr") === true
    : hostShellProxy.realShell
      && "openPanelIds" in hostShellProxy.realShell
      && hostShellProxy.realShell.openPanelIds
      && hostShellProxy.realShell.openPanelIds["omarchy.wifiqr"] === true

  function focusedPresentationWidget() {
    return bar && typeof bar.findPanelWidget === "function"
      ? bar.findPanelWidget("omarchy.network") : null
  }

  function presentationWidget() {
    return presentationOwner
  }

  function summonNetworkPresentation(mode) {
    const requestedMode = String(mode || "panel")
    if (requestedMode === "qr") {
      // Quattro's QR card is the authoritative presentation for this feature;
      // Shibumi has no second QR surface. Deliberately keep only that card.
      hideNetworkPresentation()
      return true
    }
    const owner = focusedPresentationWidget()
    if (!owner || typeof owner.open !== "function") return false
    presentationOwner = owner
    pendingPresentationMode = requestedMode
    presentationAttempts = 0
    if (owner.opened !== true) owner.open()
    presentationRedirect.restart()
    return true
  }

  function hideNetworkPresentation(closeBackend) {
    pendingPresentationMode = ""
    presentationRedirect.stop()
    const owner = presentationOwner
    const focusedOwner = closeBackend === true
      ? focusedPresentationWidget() : null
    presentationOwner = null
    if (owner && owner.opened === true && typeof owner.close === "function")
      owner.close()
    if (focusedOwner && focusedOwner !== owner
        && focusedOwner.opened === true
        && typeof focusedOwner.close === "function")
      focusedOwner.close()
    if (closeBackend === true) hostShellProxy.hide("omarchy.wifiqr")
    if (panel && (closeBackend === true || panel.opened === true)
        && typeof panel.close === "function")
      panel.close()
    return owner !== null || focusedOwner !== null
  }

  function applyPresentationMode() {
    const widget = presentationWidget()
    if (!widget) return false
    if (panel && panel.opened === true && typeof panel.close === "function")
      panel.close()
    if (widget.opened !== true && typeof widget.open === "function")
      widget.open()
    if (pendingPresentationMode === "speed") {
      if (widget.panelLoaded === true && widget.panelItem) {
        if ("speedDetailsVisible" in widget.panelItem)
          widget.panelItem.speedDetailsVisible = true
        if (networkService
            && typeof networkService.runSpeedTest === "function")
          networkService.runSpeedTest()
        pendingPresentationMode = ""
        return true
      }
      return false
    }
    pendingPresentationMode = ""
    return true
  }

  function connectedWifiLabel() {
    if (!ready || kind !== "wifi") return ""

    // `wifiNetworks` is the panel's normalized, event-driven public model and
    // carries the same connected row that the official panel renders. Prefer
    // it because some Qt NetworkManager objects expose `name` only after their
    // wrapper has emitted a later property change.
    const rows = panel.wifiNetworks
    if (Array.isArray(rows)) {
      for (let i = 0; i < rows.length; i++) {
        if (rows[i] && rows[i].connected === true
            && String(rows[i].ssid || "") !== "")
          return String(rows[i].ssid)
      }
    }

    const current = panel.connectedWifiNetwork
    if (current && current.name !== undefined
        && String(current.name || "") !== "")
      return String(current.name)
    if (panel.info && panel.info.ssid !== undefined)
      return String(panel.info.ssid || "")
    return ""
  }

  function open(scanWifi) {
    if (!ready || typeof panel.open !== "function") return false
    panel.open()
    if (scanWifi === true && typeof panel.refresh === "function") panel.refresh(true)
    return true
  }

  function close() {
    if (!ready || typeof panel.close !== "function") return false
    panel.close()
    return true
  }

  function toggle() {
    if (!ready) return false
    if (opened) return close()
    return open(false)
  }

  function suppressBackendKeyboardPanel() {
    if (!panel || !panel.data || panel.data.length === undefined) return false
    let suppressed = false
    for (let index = 0; index < panel.data.length; index++) {
      const candidate = panel.data[index]
      if (!candidate || typeof candidate.beginFocusPrime !== "function"
          || !("anchorItem" in candidate) || !("open" in candidate)
          || !("visible" in candidate) || !("owner" in candidate)
          || candidate.owner !== panel) continue
      // The official backend's KeyboardPanel is a separate PanelWindow, so
      // hiding the backend Item after Loader.onLoaded cannot hide that window.
      // Break only that KeyboardPanel visibility binding; QR remains routed
      // to Omarchy while speed-test requests are intercepted below.
      candidate.open = false
      candidate.visible = false
      suppressed = true
    }
    return suppressed
  }

  function suppressBackendIpc() {
    if (!panel || !panel.data || panel.data.length === undefined) return false
    let suppressed = false
    for (let index = 0; index < panel.data.length; index++) {
      const candidate = panel.data[index]
      if (!candidate || !("target" in candidate)
          || !("enabled" in candidate)
          || String(candidate.target || "") !== "omarchy.network") continue
      candidate.enabled = false
      suppressed = true
    }
    backendIpcSuppressed = suppressed
    return suppressed
  }

  function injectPanel() {
    if (!panel) return
    suppressBackendIpc()
    suppressBackendKeyboardPanel()
    if ("bar" in panel) panel.bar = hostProxy
    if ("moduleName" in panel) panel.moduleName = "omarchy.network"
    if ("settings" in panel) panel.settings = panelSettings
    if ("manageIpc" in panel) panel.manageIpc = false
    if (panel.opened === true && typeof panel.close === "function") panel.close()
    panel.opacity = 0
  }

  function syncPanelSource() {
    // Disable our replacement before destroying the suppressed host handler.
    // The newly loaded host handler owns the target only until injectPanel()
    // disables it and republishes this bridge handler.
    backendIpcSuppressed = false
    panelLoader.sourceComponent = null
    panelLoader.source = ""
    if (panelComponent !== null) {
      panelLoader.sourceComponent = panelComponent
    } else if (String(panelSource)) {
      panelLoader.setSource(panelSource, {
        bar: hostProxy,
        moduleName: "omarchy.network",
        manageIpc: false,
        settings: panelSettings
      })
    }
  }

  IpcHandler {
    target: "omarchy.network"
    enabled: root.backendIpcSuppressed

    function open(): void { root.summonNetworkPresentation("panel") }
    function show(): void { root.summonNetworkPresentation("panel") }
    function close(): void { root.hideNetworkPresentation(true) }
    function hide(): void { root.hideNetworkPresentation(true) }
    function toggle(): void {
      const owner = root.focusedPresentationWidget()
      const embeddedQrOpen = root.panel && ("qrVisible" in root.panel)
        && root.panel.qrVisible === true
      if ((owner && owner.opened === true) || embeddedQrOpen
          || root.externalQrOpen)
        root.hideNetworkPresentation(true)
      else root.summonNetworkPresentation("panel")
    }
    function toggleNetwork(): void {
      if (root.panel && typeof root.panel.toggleNetwork === "function")
        root.panel.toggleNetwork()
    }
    function showQr(): void {
      if (!root.panel) return
      root.hideNetworkPresentation(true)
      if (typeof root.panel.summonWifiQr === "function")
        root.panel.summonWifiQr(true)
      else if (typeof root.panel.showWifiQr === "function")
        root.panel.showWifiQr(true)
    }
    function speedTest(): void { root.summonNetworkPresentation("speed") }
  }

  Connections {
    target: root.panel
    ignoreUnknownSignals: true

    function onOpenedChanged() {
      if (!root.panel || root.panel.opened !== true) return
      root.summonNetworkPresentation("panel")
      if (typeof root.panel.close === "function") root.panel.close()
    }

    function onQrVisibleChanged() {
      if (root.panel && root.panel.qrVisible === true)
        root.summonNetworkPresentation("qr")
    }
  }

  Connections {
    target: root.presentationOwner
    ignoreUnknownSignals: true
    function onOpenedChanged() {
      const widget = root.presentationWidget()
      if (widget && widget.opened !== true)
        root.presentationOwner = null
    }
  }

  Timer {
    id: presentationRedirect
    interval: 25
    onTriggered: {
      root.presentationAttempts++
      if (!root.applyPresentationMode() && root.presentationAttempts < 20)
        restart()
      else if (root.presentationAttempts >= 20)
        root.pendingPresentationMode = ""
    }
  }

  onPanelSettingsChanged: injectPanel()
  onBarChanged: injectPanel()
  onPanelComponentChanged: Qt.callLater(syncPanelSource)
  onPanelSourceChanged: Qt.callLater(syncPanelSource)
  Component.onCompleted: Qt.callLater(syncPanelSource)
  Component.onDestruction: {
    hideNetworkPresentation()
    if (panel && panel.opened === true && typeof panel.close === "function")
      panel.close()
  }

  QtObject {
    id: hostProxy

    readonly property var realBar: root.bar
    readonly property bool vertical: realBar ? realBar.vertical === true : false
    readonly property int barSize: realBar ? Number(realBar.barSize) : 35
    readonly property int sizeHorizontal: realBar && realBar.sizeHorizontal !== undefined
      ? Number(realBar.sizeHorizontal) : barSize
    readonly property string position: realBar ? String(realBar.position || "top") : "top"
    readonly property string fontFamily: realBar ? String(realBar.fontFamily || "monospace") : "monospace"
    readonly property color foreground: realBar ? realBar.foreground : "#ffffff"
    readonly property color barForeground: foreground
    readonly property color urgent: realBar ? realBar.urgent : foreground
    readonly property bool foregroundAnimationEnabled: realBar
      ? realBar.foregroundAnimationEnabled !== false : false
    readonly property var shell: hostShellProxy
    readonly property var activePopout: realBar ? realBar.activePopout : null
    readonly property var clickTargets: realBar ? realBar.clickTargets : []

    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}

    function run(command) {
      if (realBar && typeof realBar.run === "function") realBar.run(command)
    }

    function requestPopout(owner) {
      if (realBar && typeof realBar.requestPopout === "function")
        realBar.requestPopout(owner)
    }

    function releasePopout(owner) {
      if (realBar && typeof realBar.releasePopout === "function")
        realBar.releasePopout(owner)
    }

    function switchPanelFrom(_owner, direction) {
      return realBar && typeof realBar.switchPanelFrom === "function"
        ? realBar.switchPanelFrom(root.ownerWidget, direction) : false
    }

    function targetBelongsToWindow(target, window) {
      return realBar && typeof realBar.targetBelongsToWindow === "function"
        ? realBar.targetBelongsToWindow(target, window) : false
    }
  }

  QtObject {
    id: hostShellProxy

    readonly property var realShell: root.bar ? root.bar.shell : null

    function summon(id, payloadJson) {
      if (String(id || "") === "omarchy.speedtest")
        return root.summonNetworkPresentation("speed") ? "ok" : "unknown"
      return realShell && typeof realShell.summon === "function"
        ? realShell.summon(id, payloadJson) : "unknown"
    }

    function hide(id) {
      return realShell && typeof realShell.hide === "function"
        ? realShell.hide(id) : undefined
    }
  }

  Loader {
    id: panelLoader
    anchors.fill: parent
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
