import QtQuick
import Quickshell
import Quickshell.Io
import "owners/audio" as AudioOwner
import "owners/state" as StateOwner

ShellRoot {
  id: root

  property int stage: 0
  property int conformingLoads: 0
  property bool complete: false
  readonly property url conformingUrl:
    Qt.resolvedUrl("fixtures/third-party-integration/conforming/Service.qml")

  QtObject {
    id: fakeBar
    property int audioOpenCalls: 0
    function summonBarWidget(id) {
      if (id === "omarchy.audio") audioOpenCalls++
      return id === "omarchy.audio"
    }
    function hideBarWidget(id) { return id === "omarchy.audio" }
    function isBarWidgetOpen(_id) { return false }
  }

  QtObject {
    id: fakeShell
    property var bar: fakeBar
    property var shellConfig: ({ bar: ({ shibumi: ({}) }) })
    function mutateShellConfig(mutator) {
      const next = JSON.parse(JSON.stringify(shellConfig))
      mutator(next)
      shellConfig = next
    }
  }

  AudioOwner.Service {
    shell: fakeShell
    manifest: ({ id: "hancore.shibumi.audio" })
  }

  StateOwner.Service {
    shell: fakeShell
    omarchyPath: ""
    manifest: ({
      id: "hancore.shibumi.state",
      __sourceDir: Qt.resolvedUrl("owners/state").toString().replace(/^file:\/\//, "")
    })
  }

  Loader { id: pluginLoader }

  function loadConforming() {
    pluginLoader.setSource(conformingUrl, {
      shell: fakeShell,
      manifest: ({ id: "example.shibumi-test.conforming" })
    })
  }

  Component.onCompleted: loadConforming()

  Timer {
    interval: 25
    repeat: true
    running: !root.complete
    onTriggered: {
      if (root.stage === 0) {
        if (!pluginLoader.item) return
        root.conformingLoads++
        console.log("third-party conforming host load", root.conformingLoads)
        pluginLoader.source = ""
        root.stage = 1
        return
      }
      if (root.stage === 1 && !pluginLoader.item) {
        if (root.conformingLoads < 3) {
          root.loadConforming()
          root.stage = 0
        } else {
          root.complete = true
          console.log("third-party integration host lifecycle ready")
        }
      }
    }
  }

  IpcHandler {
    target: "third-party-integration-test"
    function state(): string {
      return (root.complete ? "complete" : "running") + ":"
        + root.conformingLoads + ":" + fakeBar.audioOpenCalls
    }
  }
}
