import QtQuick
import Quickshell
import "workspaces" as Workspaces

ShellRoot {
  id: root

  property int phase: 0
  property int geometryWaits: 0

  function fail(message) {
    console.error("workspace-widget-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeShell
    function serviceFor(id) {
      return id === "hancore.shibumi.workspaces" ? workspaceState : null
    }
  }

  QtObject {
    id: preferenceState
    property var config: ({ workspace: fakeBar.workspaceConfig })
    function setWorkspacePreference(name, value) {
      const next = JSON.parse(JSON.stringify(fakeBar.workspaceConfig))
      next[name] = value
      fakeBar.workspaceConfig = next
      config = ({ workspace: next })
      return true
    }
  }

  QtObject {
    id: commandRecorder
    function run(command) {
      fakeBar.lastCommand = command.slice()
      return true
    }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 28
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#e8e8e8"
    property color barForeground: foreground
    property color background: "#181818"
    property color urgent: "#88bbee"
    property var visualTokens: ({
      pillHeight: 24,
      pillRadius: 12,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      contentGap: 5,
      labelSize: 12,
      presentation: ({ radius: "large" }),
      workspacePillPadding: function(style) { return style === "numbers" ? 2 : 4 }
    })
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var workspaceConfig: ({ version: 1, mode: "5", style: "numbers" })
    property var shell: fakeShell
    property var lastCommand: []

    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
  }

  Workspaces.WorkspaceActions {
    id: actions
    commandRunner: commandRecorder
  }

  Workspaces.WorkspaceService {
    id: workspaceState
    stateService: preferenceState
    actionAdapter: actions
    focusedWorkspaceSource: ({ id: 8 })
    workspaceSource: [
      { id: 2, toplevels: { values: [{}] } },
      { id: 8, toplevels: { values: [{}, {}] } },
      { id: -1, toplevels: { values: [{}] } }
    ]
  }

  Workspaces.BarWidget {
    id: widget
    bar: fakeBar
    settings: ({})
    panelSource: Qt.resolvedUrl("WorkspaceTestPanel.qml")
  }

  Workspaces.BarWidget {
    id: secondWidget
    bar: fakeBar
    settings: ({})
    panelSource: Qt.resolvedUrl("WorkspaceTestPanel.qml")
  }

  Timer {
    interval: 60
    repeat: true
    running: true
    onTriggered: {
      if (root.phase === 0) {
        if (workspaceState.entries.length !== 2
            || workspaceState.visibleWorkspaceIds.join(",") !== "1,2,3,4,5,8"
            || widget.renderedWorkspaceCount !== 6
            || secondWidget.renderedWorkspaceCount !== 6
            || widget.workspaceService !== secondWidget.workspaceService
            || widget.panelLoaded || secondWidget.panelLoaded)
          return root.fail("initial service/widget contract")
        if (widget.workspacePadding !== 2 || Math.round(widget.implicitWidth) !== 161)
          return root.fail("V1 numbers presentation geometry")
        if (!widget.activateWorkspace(8)
            || fakeBar.lastCommand.join("|")
              !== "hyprctl|dispatch|hl.dsp.focus({ workspace = \"8\" })")
          return root.fail("validated workspace dispatch")
        if (widget.workspaceTooltip(8)
            !== "Workspace 8 · 2 windows · Right-click for workspace panel")
          return root.fail("workspace tooltip contract")
        if (!actions.focusWorkspace(9999)
            || fakeBar.lastCommand.join("|")
              !== "hyprctl|dispatch|hl.dsp.focus({ workspace = \"9999\" })")
          return root.fail("workspace dispatch upper bound")
        fakeBar.lastCommand = []
        if (actions.focusWorkspace(-1) || actions.focusWorkspace(1.5)
            || actions.focusWorkspace(10000)
            || actions.focusWorkspace("1; reboot")
            || fakeBar.lastCommand.length !== 0)
          return root.fail("invalid workspace dispatch was not rejected")
        if (!workspaceState.setPreference("style", "magic")
            || !workspaceState.setPreference("mode", "active")
            || fakeBar.workspaceConfig.style !== "magic"
            || fakeBar.workspaceConfig.mode !== "active"
            || workspaceState.setPreference("mode", "unsafe"))
          return root.fail("workspace preference persistence")
        widget.open()
      } else if (root.phase === 1) {
        if (widget.workspaceStyle !== "magic"
            || workspaceState.visibleWorkspaceIds.join(",") !== "2,8"
            || widget.renderedWorkspaceCount !== 2)
          return root.fail("reactive workspace presentation")
        if (widget.workspacePadding !== 4 || Math.round(widget.implicitWidth) !== 51) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V1 magic presentation geometry: " + widget.implicitWidth)
        }
        root.geometryWaits = 0
        if (!widget.opened || !widget.panelLoaded || !widget.panelLoaderReady)
          return root.fail("lazy workspace panel open")
        if (secondWidget.opened || secondWidget.panelLoaded)
          return root.fail("screen-local workspace panel isolation")
        widget.close()
        if (!workspaceState.setPreference("style", "kanji")
            || workspaceState.setPreference("style", "unsafe"))
          return root.fail("Kanji workspace preference")
      } else if (root.phase === 2) {
        if (widget.workspaceStyle !== "kanji"
            || Math.round(widget.implicitWidth) !== 57) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V2 Kanji presentation geometry: " + widget.implicitWidth)
        }
        root.geometryWaits = 0
        if (!workspaceState.setPreference("style", "rings"))
          return root.fail("Rings workspace preference")
      } else if (root.phase === 3) {
        if (widget.workspaceStyle !== "rings"
            || Math.round(widget.implicitWidth) !== 49) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V2 Rings presentation geometry: " + widget.implicitWidth)
        }
        root.geometryWaits = 0
        if (!workspaceState.setPreference("style", "frame"))
          return root.fail("Frame workspace preference")
      } else if (root.phase === 4) {
        if (widget.workspaceStyle !== "frame"
            || Math.round(widget.implicitWidth) !== 51) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("embedded V2 Frame presentation geometry: "
            + widget.implicitWidth)
        }
        root.geometryWaits = 0
        if (!workspaceState.setPreference("style", "aurora"))
          return root.fail("Aurora workspace preference")
      } else if (root.phase === 5) {
        if (widget.workspaceStyle !== "aurora"
            || Math.round(widget.implicitWidth) !== 69) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V2 Aurora presentation geometry: " + widget.implicitWidth)
        }
        root.geometryWaits = 0
        if (!workspaceState.setPreference("style", "aurora-streak"))
          return root.fail("Aurora streak workspace preference")
      } else if (root.phase === 6) {
        if (widget.workspaceStyle !== "aurora-streak"
            || Math.round(widget.implicitWidth) !== 58) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("embedded V2 Aurora streak presentation geometry: "
            + widget.implicitWidth)
        }
        root.geometryWaits = 0
        if (!workspaceState.setPreference("style", "default")
            || !workspaceState.setPreference("mode", "10"))
          return root.fail("workspace presentation reset")
      } else {
        if (widget.opened || widget.panelLoaded
            || secondWidget.opened || secondWidget.panelLoaded
            || widget.workspaceStyle !== "default"
            || workspaceState.visibleWorkspaceIds.length !== 10
            || widget.renderedWorkspaceCount !== 10)
          return root.fail("lazy workspace panel close")
        if (widget.workspacePadding !== 4 || Math.round(widget.implicitWidth) !== 229) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V1 default presentation geometry: " + widget.implicitWidth)
        }
        stop()
        console.log("workspaces plugin smoke passed")
        Qt.quit()
      }
      root.phase++
    }
  }
}
