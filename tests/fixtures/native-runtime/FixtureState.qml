import Quickshell.Io
import "runtime" as Shared
Service {
  id: probe
  property var transitionPatch: null
  property var transitionRollback: null
  property int transitionSerial: 0
  IpcHandler {
    target: "native-state-probe"
    function status(): string {
      return JSON.stringify({ready: probe.ready, objectName: probe.objectName,
        registered: Shared.Runtime.serviceFor("hancore.shibumi.state") === probe,
        hasBar: Shared.Runtime.hasActiveBar, revision: probe.revision,
        pending: probe.writePending, writeStatus: probe.writeStatus,
        transitionTarget: probe.transitionPatch, transitionBefore: probe.transitionRollback,
        transitionProjection: probe.layoutFamilySnapshot(probe.transitionPatch),
        config: probe.config})
    }
    // Probe the actual host-granted service capability, not the suite Bar broker.
    // Extra envelope-field proof; production settings use the queued State API.
    function inlineEntry(pluginId: string, valueJson: string): string {
      if (!probe.shell || typeof probe.shell.updateEntryInline !== "function")
        return "not-ready"
      const value = JSON.parse(valueJson)
      return probe.shell.updateEntryInline(pluginId, value) === true ? "changed" : "unchanged"
    }
    function burst(): string {
      const before = JSON.stringify(probe.config)
      const first = probe.setWidgetSetting("G8", "omarchy.clock", "format", "HH:mm")
      const second = probe.setWidgetSetting("G8", "omarchy.clock", "calendar", true)
      return first && second && probe.writePending && JSON.stringify(probe.config) === before
        ? "queued-without-optimism" : "failed"
    }
    function layoutFamily(): string {
      if (!probe.ready || probe.writePending) return "not-ready"
      const order = JSON.parse(JSON.stringify(probe.config.order))
      const first = order.left[0]; order.left[0] = order.left[1]; order.left[1] = first
      probe.transitionPatch = {v1Layout: {order: order, splits: probe.config.splits},
        v2Boundaries: [true, false], familyStates: {G6: {v1: false, v2: true}},
        separators: {G2: true, G3: false}}
      probe.transitionRollback = probe.layoutFamilySnapshot(probe.transitionPatch)
      const before = JSON.stringify(probe.config)
      if (!probe.transitionRollback || !probe.setLayoutFamilyTransition(probe.transitionPatch)) return "refused"
      probe.transitionSerial = probe.writeSerial
      return probe.writePending && JSON.stringify(probe.config) === before ? "queued-without-optimism" : "failed"
    }
    function compensateLayoutFamily(): string {
      return probe.compensateLayoutFamilyTransition(probe.transitionSerial,
        probe.transitionPatch, probe.transitionRollback) ? "queued" : "refused"
    }
    function compact(value: bool): string {
      return probe.setGroupSetting("G4", "compact", value) ? "queued" : "not-ready"
    }
  }
}
