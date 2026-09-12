pragma ComponentBehavior: Bound

import QtQuick

// Keeps exact-profile completion evidence alive independently of the panel
// that dispatched the mutation. It owns no worker; it only holds one lease in
// the process-wide telemetry and saved-profile authorities until settlement.
Item {
  id: root

  property bool active: false
  property var networkTelemetry: null
  property var savedProfileCatalog: null
  property var actionCoordinator: null
  property bool held: false

  visible: false
  width: 0
  height: 0

  function acquire() {
    if (held) return true
    if (!active || !networkTelemetry || !savedProfileCatalog
        || typeof networkTelemetry.acquire !== "function"
        || typeof savedProfileCatalog.acquire !== "function") return false
    if (networkTelemetry.acquire(root) !== true) return false
    if (savedProfileCatalog.acquire(root) !== true) {
      networkTelemetry.release(root)
      return false
    }
    held = true
    return true
  }

  function retainIfPending(expectedKind) {
    let snapshot = null
    try {
      snapshot = actionCoordinator ? actionCoordinator.actionSnapshot : null
    } catch (error) {}
    if (held && snapshot && snapshot.phase === "pending"
        && snapshot.kind === String(expectedKind || "")
        && (snapshot.kind === "connect-profile"
          || snapshot.kind === "forget-profile")) return true
    release()
    return false
  }

  function release() {
    if (!held) return false
    held = false
    if (savedProfileCatalog
        && typeof savedProfileCatalog.release === "function")
      savedProfileCatalog.release(root)
    if (networkTelemetry && typeof networkTelemetry.release === "function")
      networkTelemetry.release(root)
    return true
  }

  onActiveChanged: if (!active) release()
  onNetworkTelemetryChanged: release()
  onSavedProfileCatalogChanged: release()
  onActionCoordinatorChanged: release()

  Connections {
    target: root.actionCoordinator
    ignoreUnknownSignals: true
    function onPhaseChanged() {
      if (root.held && (!root.actionCoordinator
          || root.actionCoordinator.phase !== "pending")) root.release()
    }
  }

  Component.onDestruction: release()
}
