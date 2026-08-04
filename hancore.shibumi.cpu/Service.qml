pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property int contractVersion: 1
  readonly property bool ready: true
  readonly property alias gpu: gpuState

  GpuTelemetry {
    id: gpuState
    helperPath: String(Qt.resolvedUrl(
      "scripts/shibumi-gpu-probe")).replace("file://", "")
  }
}
