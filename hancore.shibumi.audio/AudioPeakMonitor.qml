pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire

// One process-wide, read-only microphone peak capability for the transitional
// official audio owner. Native AudioBackendAdapter replaces it at activation.
Item {
  id: root

  property int clients: 0
  readonly property bool ready: Pipewire.ready === true
  readonly property real inputPeak: root.clients > 0 && ready
    && peakMonitor.node !== null ? Number(peakMonitor.peak) || 0 : 0

  function acquire() {
    clients++
    return true
  }

  function release() {
    clients = Math.max(0, clients - 1)
    return true
  }

  PwNodePeakMonitor {
    id: peakMonitor
    node: Pipewire.ready === true && Pipewire.defaultAudioSource
      && Pipewire.defaultAudioSource.ready !== false
      ? Pipewire.defaultAudioSource : null
    enabled: root.clients > 0 && root.ready && node !== null
  }
}
