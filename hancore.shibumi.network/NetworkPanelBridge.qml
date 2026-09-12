pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Process-wide compatibility route for the documented Omarchy Network IPC
// target. It owns no host panel/backend and forwards presentation requests to
// the focused output-local Shibumi widget.
Item {
  id: root

  property var bar: null
  property var networkService: null
  property var presentationOwner: null

  visible: false
  width: 0
  height: 0

  function focusedPresentationWidget() {
    if (!bar || typeof bar.findPanelWidget !== "function") return null
    return bar.findPanelWidget("hancore.shibumi.network")
      || bar.findPanelWidget("omarchy.network")
  }

  function summonNetworkPresentation(mode) {
    const owner = focusedPresentationWidget()
    if (!owner) return false
    presentationOwner = owner
    if (typeof owner.openNetworkPresentation === "function")
      return owner.openNetworkPresentation(String(mode || "panel"))
    if (typeof owner.open === "function") {
      owner.open()
      return true
    }
    presentationOwner = null
    return false
  }

  function hideNetworkPresentation() {
    const focused = focusedPresentationWidget()
    const owner = presentationOwner
    presentationOwner = null
    let closed = false
    if (owner && owner.opened === true && typeof owner.close === "function") {
      owner.close()
      closed = true
    }
    if (focused && focused !== owner && focused.opened === true
        && typeof focused.close === "function") {
      focused.close()
      closed = true
    }
    return closed
  }

  IpcHandler {
    target: "omarchy.network"

    function open(): void { root.summonNetworkPresentation("panel") }
    function show(): void { root.summonNetworkPresentation("panel") }
    function close(): void { root.hideNetworkPresentation() }
    function hide(): void { root.hideNetworkPresentation() }
    function toggle(): void {
      const owner = root.focusedPresentationWidget()
      if (owner && owner.opened === true) root.hideNetworkPresentation()
      else root.summonNetworkPresentation("panel")
    }
    function toggleNetwork(): void {
      if (root.networkService
          && typeof root.networkService.toggleWifi === "function")
        root.networkService.toggleWifi()
    }
    function showQr(): void { root.summonNetworkPresentation("qr") }
    function speedTest(): void { root.summonNetworkPresentation("speed") }
  }

  Connections {
    target: root.presentationOwner
    ignoreUnknownSignals: true
    function onOpenedChanged() {
      if (root.presentationOwner
          && root.presentationOwner.opened !== true)
        root.presentationOwner = null
    }
  }

  Component.onDestruction: hideNetworkPresentation()
}
