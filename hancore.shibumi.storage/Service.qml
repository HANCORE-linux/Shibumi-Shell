pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/host" as ShibumiHost

Item {
  id: root

  readonly property var suiteHostShell: ShibumiHost.HostShell {
    pluginId: "hancore.shibumi.storage"
    owner: root
  }

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property int contractVersion: 1
  readonly property bool ready: true
  readonly property alias storage: storageState

  StorageTelemetry { id: storageState }
}
