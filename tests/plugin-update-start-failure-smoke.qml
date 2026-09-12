pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "control" as Control

ShellRoot {
  id: root
  property int phase: 0

  function fail(message) {
    console.error("plugin-update-start-failure:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  QtObject { id: legacyShell }

  Control.PluginUpdateService {
    id: service
    shell: legacyShell
    timeoutSeconds: 2
  }

  FileView {
    id: retryReady
    path: Quickshell.env("SHIBUMI_START_RETRY_READY")
    watchChanges: true
    onFileChanged: reload()
  }

  Timer {
    interval: 30
    repeat: true
    running: true
    onTriggered: {
      retryReady.reload()
      if (root.phase === 0) {
        if (!service.check(true)) root.fail("initial start-failure request refused")
        root.phase = 1
        return
      }
      if (root.phase === 1) {
        if (service.running) return
        if (service.scanStarted || service.checked
            || service.error !== "Plugin update check failed")
          root.fail("unstarted scanner did not settle as a failure")
        if (retryReady.text().trim() !== "ready") return
        if (!service.check(true)) root.fail("retry after start failure refused")
        root.phase = 2
        return
      }
      if (root.phase === 2) {
        if (service.running) return
        if (!service.checked || service.error !== ""
            || service.checkedCount !== 1 || service.updateCount !== 0)
          root.fail("retry after start failure did not publish success")
        console.log("plugin update start failure settled and retry passed")
        Qt.quit()
      }
    }
  }

  Timer {
    interval: 7000
    running: true
    onTriggered: root.fail("deadline")
  }
}
