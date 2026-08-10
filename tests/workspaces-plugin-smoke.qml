import QtQuick
import Quickshell
import "workspaces" as Workspaces

ShellRoot {
  id: root

  property int phase: 0
  property int geometryWaits: 0
  property int animationWaits: 0
  property real preInterruptX: 0
  property real oldPacmanTargetX: 0

  function fail(message) {
    console.error("workspace-widget-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: paletteState
    function paletteColor(id) {
      if (id === "color03") return "#d4a72c"
      if (id === "color06") return "#45a8a0"
      if (id === "color01") return "#d84a5b"
      return "#e8e8e8"
    }
  }

  QtObject {
    id: fakeShell
    function serviceFor(id) {
      if (id === "hancore.shibumi.workspaces") return workspaceState
      if (id === "hancore.shibumi.state") return paletteState
      return null
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
      shellStyle: "full",
      v2Shell: true,
      pillHeight: 24,
      pillRadius: 12,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      contentGap: 5,
      labelSize: 12,
      ink: fakeBar.foreground,
      seal: fakeBar.urgent,
      paper: fakeBar.background,
      presentation: ({ radius: "large" }),
      workspacePillPadding: function(style) { return style === "numbers" ? 2 : 4 },
      widgetHasFill: function(settings) {
        return settings && settings.color === "color01"
      },
      widgetFillColor: function(settings) {
        return settings && settings.color === "color01"
          ? paletteState.paletteColor("color01") : "transparent"
      },
      widgetSurfaceOpacity: function(settings) {
        return settings && settings.surfaceOpacity !== undefined
          ? Number(settings.surfaceOpacity) : 1
      },
      widgetContentColor: function(settings, fallback) {
        return settings && settings.color === "color01"
          && settings.tone === "background" ? fakeBar.background : fallback
      }
    })
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var layoutController: ({ v2Mode: true })
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

  QtObject {
    id: persistFiveState
    property var config: ({
      workspace: ({ version: 1, mode: "5", style: "numbers" })
    })
  }

  Workspaces.WorkspaceService {
    id: occupiedOutsidePersistState
    stateService: persistFiveState
    actionAdapter: actions
    focusedWorkspaceSource: ({ id: 2 })
    workspaceSource: [
      { id: 2, toplevels: { values: [{}] } },
      { id: 7, toplevels: { values: [{}] } }
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
            || occupiedOutsidePersistState.visibleWorkspaceIds.join(",")
              !== "1,2,3,4,5,7"
            || widget.renderedWorkspaceCount !== 6
            || secondWidget.renderedWorkspaceCount !== 6
            || widget.workspaceService !== secondWidget.workspaceService
            || widget.panelLoaded || secondWidget.panelLoaded)
          return root.fail("initial service/widget contract")
        if (widget.workspacePadding !== 2 || Math.round(widget.implicitWidth) !== 161)
          return root.fail("V1 numbers presentation geometry")
        if (widget.numberMarkerRadius !== 10
            || widget.frameMarkerRadius !== 5)
          return root.fail("V2 fixed marker radius contract")
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
          return root.fail("Frame workspace preference")
      } else if (root.phase === 3) {
        if (widget.workspaceStyle !== "rings"
            || Math.round(widget.implicitWidth) !== 51) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V2 Frame presentation geometry: " + widget.implicitWidth)
        }
        root.geometryWaits = 0
        if (!workspaceState.setPreference("style", "aurora"))
          return root.fail("Aurora workspace preference")
      } else if (root.phase === 4) {
        if (widget.workspaceStyle !== "aurora"
            || Math.round(widget.implicitWidth) !== 58) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V2 Aurora presentation geometry: " + widget.implicitWidth)
        }
        root.geometryWaits = 0
        if (!workspaceState.setPreference("style", "pacman"))
          return root.fail("Pacman workspace preference")
      } else if (root.phase === 5) {
        if (widget.workspaceStyle !== "pacman"
            || widget.renderStyle !== "pacman"
            || Math.round(widget.implicitWidth) !== 54
            || String(widget.pacmanActiveColor).toLowerCase() !== "#d4a72c"
            || String(widget.pacmanOccupiedColor).toLowerCase() !== "#88bbee"
            || String(widget.pacmanEmptyColor).toLowerCase() !== "#88bbee"
            || String(widget.pacmanHoverColor).toLowerCase() !== "#88bbee") {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V2 Pacman presentation geometry: " + widget.implicitWidth)
        }
        root.geometryWaits = 0
        workspaceState.focusedWorkspaceSource = ({ id: 2 })
      } else if (root.phase === 6) {
        if (!widget.pacmanTraveling
            || widget.pacmanTargetWorkspaceId !== 2
            || widget.pacmanTravelDirection !== -1
            || widget.pacmanTravelSteps !== 1
            || widget.pacmanTravelDuration !== 420
            || widget.pacmanEatDuration !== 240
            || widget.pacmanBiteCount !== 3)
          return root.fail("Pacman eat animation did not start")
      } else if (root.phase === 7) {
        if (widget.pacmanTraveling) {
          root.animationWaits++
          if (root.animationWaits < 12) return
          return root.fail("Pacman eat animation did not finish")
        }
        if (widget.pacmanTargetWorkspaceId !== -1
            || widget.pacmanMouthClosure !== 0
            || widget.pacmanEatProgress !== 0)
          return root.fail("Pacman animation retained completed state")
        root.animationWaits = 0
        const v1Tokens = Object.assign({}, fakeBar.visualTokens)
        v1Tokens.shellStyle = "shibumi"
        v1Tokens.v2Shell = false
        fakeBar.visualTokens = v1Tokens
        widget.settings = ({
          color: "color01",
          colorMode: "border",
          tone: "background",
          surfaceOpacity: 0.6
        })
        fakeBar.layoutController = ({ v2Mode: false })
      } else if (root.phase === 8) {
        if (widget.workspaceStyle !== "pacman"
            || widget.renderStyle !== "pacman"
            || !widget.v1CustomToneActive
            || !Qt.colorEqual(widget.pacmanActiveColor, fakeBar.background)
            || !Qt.colorEqual(widget.pacmanOccupiedColor, fakeBar.background)
            || Math.round(widget.implicitWidth) !== 54) {
          root.geometryWaits++
          if (root.geometryWaits < 10) return
          return root.fail("V1 Pacman presentation geometry: "
            + widget.implicitWidth)
        }
        root.geometryWaits = 0
        workspaceState.focusedWorkspaceSource = ({ id: 8 })
      } else if (root.phase === 9) {
        if (!widget.pacmanTraveling
            || widget.pacmanTargetWorkspaceId !== 8
            || widget.pacmanTravelDirection !== 1)
          return root.fail("V1 Pacman animation did not start: "
            + JSON.stringify({
              focused: widget.focusedWorkspaceId,
              lastFocused: widget.pacmanLastFocusedWorkspaceId,
              sourceX: widget.pacmanCenterX(2),
              targetX: widget.pacmanCenterX(8),
              displayed: widget.displayedWorkspaceIds,
              target: widget.pacmanTargetWorkspaceId,
              direction: widget.pacmanTravelDirection
            }))
        root.preInterruptX = widget.pacmanTravelX
        root.oldPacmanTargetX = widget.pacmanTravelTargetX
        workspaceState.focusedWorkspaceSource = ({ id: 2 })
      } else if (root.phase === 10) {
        if (!widget.pacmanTraveling
            || widget.pacmanTargetWorkspaceId !== 2
            || widget.pacmanTravelDirection !== -1
            || Math.abs(widget.pacmanTravelFromX - root.preInterruptX) > 2
            || Math.abs(widget.pacmanTravelFromX - root.oldPacmanTargetX) < 2)
          return root.fail("interrupted Pacman animation jumped to its old target")
        const smallTokens = Object.assign({}, fakeBar.visualTokens)
        smallTokens.presentation = ({ radius: "small" })
        fakeBar.visualTokens = smallTokens
        if (!workspaceState.setPreference("style", "rings"))
          return root.fail("V1 Frame workspace preference")
      } else if (root.phase === 11) {
        if (widget.renderStyle !== "rings"
            || widget.pacmanTraveling
            || widget.numberMarkerRadius !== 5
            || widget.frameMarkerRadius !== 6)
          return root.fail("V1 Radius 6 marker contract")
        const largeTokens = Object.assign({}, fakeBar.visualTokens)
        largeTokens.presentation = ({ radius: "large" })
        fakeBar.visualTokens = largeTokens
      } else if (root.phase === 12) {
        if (widget.renderStyle !== "rings"
            || widget.numberMarkerRadius !== 10
            || widget.frameMarkerRadius !== 9)
          return root.fail("V1 Radius 12 marker contract")
        widget.settings = ({})
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
