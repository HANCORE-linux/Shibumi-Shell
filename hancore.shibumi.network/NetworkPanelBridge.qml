pragma ComponentBehavior: Bound

import QtQuick

// Host Quattro's complete network component as a hidden backend. This bridge
// is instantiated once by NetworkService, never once per output.
Item {
  id: root

  required property var bar
  required property Item ownerWidget
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
  property bool synchronizingPanelState: false
  property var presentationOwner: null

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

  function hideNetworkPresentation() {
    pendingPresentationMode = ""
    presentationRedirect.stop()
    const owner = presentationOwner
    presentationOwner = null
    if (!owner) return false
    if (owner.opened === true && typeof owner.close === "function")
      owner.close()
    return true
  }

  function applyPresentationMode() {
    const widget = presentationWidget()
    if (!widget) return false
    if (widget.opened !== true && typeof widget.open === "function")
      widget.open()
    if (pendingPresentationMode === "speed") {
      if (widget.panelLoaded === true && widget.panelItem) {
        if ("speedDetailsVisible" in widget.panelItem)
          widget.panelItem.speedDetailsVisible = true
        // Keep the authoritative speed-test process and data owner. Preserve
        // its compatibility open/close/toggle state before hiding the stock
        // modal so subsequent direct IPC remains synchronized with Shibumi.
        if (panel && panel.controller
            && typeof panel.controller.show === "function"
            && panel.opened !== true)
          panel.controller.show()
        if (panel && "speedTestModalOpen" in panel)
          panel.speedTestModalOpen = false
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
      // Break only the KeyboardPanel visibility binding; centered QR and speed
      // overlays (which do not expose beginFocusPrime) remain authoritative.
      candidate.open = false
      candidate.visible = false
      suppressed = true
    }
    return suppressed
  }

  function injectPanel() {
    if (!panel) return
    suppressBackendKeyboardPanel()
    if ("bar" in panel) panel.bar = hostProxy
    if ("moduleName" in panel) panel.moduleName = "omarchy.network"
    if ("settings" in panel) panel.settings = panelSettings
    if ("manageIpc" in panel) panel.manageIpc = false
    if (panel.opened === true && typeof panel.close === "function") panel.close()
    if (panel.wifiDevice) panel.wifiDevice.scannerEnabled = false
    panel.opacity = 0
  }

  function syncPanelSource() {
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

  Connections {
    target: root.panel
    ignoreUnknownSignals: true

    function onOpenedChanged() {
      if (!root.panel || root.synchronizingPanelState) return
      if (root.panel.opened === true)
        root.summonNetworkPresentation("panel")
      else if (!root.panel.qrVisible && !root.panel.speedTestModalOpen)
        root.hideNetworkPresentation()
    }

    function onQrVisibleChanged() {
      if (root.panel && root.panel.qrVisible === true)
        root.summonNetworkPresentation("qr")
    }

    function onSpeedTestModalOpenChanged() {
      if (root.panel && root.panel.speedTestModalOpen === true)
        root.summonNetworkPresentation("speed")
    }
  }

  Connections {
    target: root.presentationOwner
    ignoreUnknownSignals: true

    function onOpenedChanged() {
      const widget = root.presentationWidget()
      if (!widget || !root.panel || root.synchronizingPanelState
          || root.panel.qrVisible || root.panel.speedTestModalOpen) return
      root.synchronizingPanelState = true
      if (widget.opened === true && root.panel.opened !== true
          && typeof root.panel.open === "function")
        root.panel.open()
      else if (widget.opened !== true && root.panel.opened === true
          && typeof root.panel.close === "function")
        root.panel.close()
      const observedOwner = widget
      Qt.callLater(function() {
        if (root.presentationOwner === observedOwner
            && observedOwner.opened !== true)
          root.presentationOwner = null
        root.synchronizingPanelState = false
      })
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
    readonly property var shell: realBar ? realBar.shell : null
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

  Loader {
    id: panelLoader
    anchors.fill: parent
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
