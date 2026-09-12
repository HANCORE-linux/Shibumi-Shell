import QtQuick
import "." as Local

QtObject {
  id: provider

  required property string pluginId
  property var owner: null
  property var host: null
  property var manifest: null
  // This belongs to the executing provider, not to refreshed host metadata.
  required property string implementationVersion
  property bool completed: false
  property var lease: null
  readonly property bool registered: lease !== null
    && Local.Runtime._selected(pluginId) === lease

  function reconcile() {
    if (!completed) return
    lease = Local.Runtime.refreshProvider(lease, pluginId, owner, host, manifest,
      implementationVersion)
  }

  onPluginIdChanged: reconcile()
  onOwnerChanged: reconcile()
  onHostChanged: reconcile()
  onManifestChanged: reconcile()
  onImplementationVersionChanged: reconcile()
  property Connections runtimeConnection: Connections {
    target: Local.Runtime
    function onReadyChanged() { provider.reconcile() }
  }
  Component.onCompleted: {
    completed = true
    reconcile()
  }
  Component.onDestruction: {
    completed = false
    Local.Runtime.unregisterProvider(lease)
  }
}
