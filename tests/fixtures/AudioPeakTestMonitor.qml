import QtQuick

// IPC/report-only fixtures substitute this for the native peak capability.
Item {
  property int clients: 0
  readonly property real inputPeak: 0
  function acquire() { clients++; return true }
  function release() { clients = Math.max(0, clients - 1); return true }
}
