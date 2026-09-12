import QtQuick
import Quickshell.Io

// Observation/control IPC for the actual production service facade. No second
// catalog or admission implementation; native ensureService injects the base.
PluginUpdateService {
  id: probe
  property var catalogToken: null
  QtObject { id: consumer }
  IpcHandler {
    target: "native-catalog-probe"
    function status(): string {
      return JSON.stringify({ admitted: probe.available && probe.scopedHost,
        ready: probe.catalogReady, refreshing: probe.catalogRefreshing,
        nativeConstructed: probe.catalogNativeConstructed, requestSerial: probe.catalogRequestSerial,
        readSerial: probe.catalogReadSerial, localGeneration: probe.catalogGeneration,
        consumerCount: probe.catalogConsumerCount,
        widgetRevision: probe.pluginRevision,
        snapshot: probe.catalogObservation(probe.catalogToken) ? probe.catalogSnapshot : null })
    }
    function acquire(): string {
      probe.catalogToken = probe.acquireCatalogConsumer(consumer)
      return probe.catalogToken !== null ? "requested" : "refused"
    }
    function release(): string {
      var accepted = probe.releaseCatalogConsumer(probe.catalogToken)
      probe.catalogToken = null
      return accepted ? "released" : "refused"
    }
  }
}
