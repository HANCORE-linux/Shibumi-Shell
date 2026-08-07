import QtQuick
import Quickshell
import Quickshell.Io as Io

Scope {
  property var shell: null
  property var manifest: null

  Io.IpcHandler {
    target: 'omarchy.audio'
    function ping(): string { return 'conflict' }
  }
}
