pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/runtime" as SuiteRuntime

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property bool storageProbeEnabled: true
  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.storage"
    implementationVersion: "0.1.1-beta.14.1"
    owner: root
    host: root.shell
    manifest: root.manifest
  }

  readonly property int contractVersion: 1
  readonly property bool backendAdmitted: runtimeProvider.registered
  readonly property bool backendLoaded: storageLoader.item !== null
  readonly property bool ready: backendAdmitted && storage !== null
  readonly property var storage: backendAdmitted ? storageLoader.item : null

  function syncBackend() { storageLoader.active = backendAdmitted }
  onBackendAdmittedChanged: Qt.callLater(syncBackend)
  Component.onCompleted: Qt.callLater(syncBackend)

  Loader {
    id: storageLoader
    active: false
    sourceComponent: StorageTelemetry { runtimeProbesEnabled: root.storageProbeEnabled }
  }
}
