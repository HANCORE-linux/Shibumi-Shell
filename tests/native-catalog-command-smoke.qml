pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "catalog" as Catalog

Scope {
  id: root
  property int stage: 0
  property string mode: "happy"
  property QtObject owner: firstOwner
  property var catalog: catalogLoader.item
  QtObject { id: firstOwner }
  QtObject { id: secondOwner }
  Loader {
    id: catalogLoader
    active: true
    sourceComponent: Component {
      Catalog.NativeCatalog {
        admitted: true
        sourceToken: root.owner
        shellDirectory: "/fixture/" + root.mode + "/shell"
        demand: true
      }
    }
  }
  FileView {
    id: readyFile
    path: Quickshell.env("CATALOG_PID_DIR") + "/ready"
    watchChanges: true
    onFileChanged: reload()
  }
  function assert(value, message) {
    if (value) return
    console.error("native-catalog-command:", stage, message)
    Qt.exit(1)
    throw new Error(message)
  }
  function started(name) { return readyFile.text().trim() === name }
  Timer {
    interval: 20; running: true; repeat: true
    onTriggered: {
      readyFile.reload()
      switch (root.stage) {
      case 0:
        if (Quickshell.env("CATALOG_START_FAILURE") === "1") {
          if (!root.catalog || root.catalog.requestSerial === 0 || root.catalog.refreshing) break
          root.assert(!root.catalog.ready && root.catalog.errorCode === "read-failed"
            && root.catalog.nativeConstructed, "start failure became ready or never drained")
          console.log("actual catalog QProcess start failure refused")
          Qt.quit()
          break
        }
        if (!root.catalog || !root.catalog.ready || root.catalog.refreshing) break
        root.assert(root.catalog.nativeConstructed && root.catalog.snapshot.entries.length === 0,
          "actual command did not publish empty ready catalog")
        if (Quickshell.env("CATALOG_MASKED_SIGNALS") === "1") {
          root.mode = "hard"; root.stage = 7; break
        }
        root.mode = "failure"; root.stage = 1; break
      case 1:
        if (root.catalog.refreshing) break
        root.assert(!root.catalog.ready && root.catalog.errorCode === "read-failed", "failed IPC was published")
        root.mode = "happy"; root.stage = 2; break
      case 2:
        if (!root.catalog.ready || root.catalog.refreshing) break
        root.mode = "cancel"; root.stage = 3; break
      case 3:
        if (!root.started("cancel")) break
        root.catalog.backend.cancel()
        root.stage = 4; break
      case 4:
        if (root.catalog.refreshing) break
        root.assert(!root.catalog.ready, "cancelled command published")
        root.mode = "owner"; root.stage = 5; break
      case 5:
        if (!root.started("owner")) break
        root.owner = secondOwner
        root.mode = "happy"
        root.stage = 6; break
      case 6:
        if (!root.catalog.ready || root.catalog.refreshing) break
        root.mode = "hard"; root.stage = 7; break
      case 7:
        if (!root.started("hard")) break
        root.catalog.backend.forceStop()
        root.stage = 8; break
      case 8:
        if (root.catalog.refreshing) break
        root.assert(!root.catalog.ready, "hard-killed command published")
        root.mode = "destroy"; root.stage = 9; break
      case 9:
        if (!root.started("destroy")) break
        catalogLoader.active = false
        root.stage = 10; break
      case 10:
        root.assert(root.catalog === null, "catalog destruction failed")
        console.log("actual catalog QProcess cancellation/drain passed; inert IPC replacement")
        Qt.quit()
      }
    }
  }
  Timer { interval: 9000; running: true; onTriggered: root.assert(false, "deadline") }
}
