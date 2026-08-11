pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "core" as Core

ShellRoot {
  id: root

  readonly property bool requestedV2:
    Quickshell.env("SHIBUMI_TEST_V2") === "1"
  readonly property bool requestedEditing:
    Quickshell.env("SHIBUMI_TEST_EDITING") === "1"
  readonly property bool requestedVertical:
    Quickshell.env("SHIBUMI_TEST_VERTICAL") === "1"
  property int createdSurfaces: 0
  property int readySurfaces: 0
  property int destroyedSurfaces: 0

  QtObject {
    id: fakeController
    function groupLocation(groupId) { return null }
  }

  QtObject {
    id: fakeTokens
    readonly property int invalidDropDuration: 1
    readonly property int returnCleanupDuration: 1
    readonly property int pillRadius: 8
    readonly property int panelBorderWidth: 0
    readonly property color panelBorder: "transparent"
    readonly property color panelBackground: "transparent"
  }

  QtObject {
    id: fakeStyle
    readonly property Component barSurfaceComponent: testSurface
    readonly property Component tooltipSurfaceComponent: testTooltip
    readonly property int tooltipGap: 0
  }

  QtObject {
    id: fakeBar
    readonly property bool hostReady: true
    readonly property bool styleReady: true
    readonly property bool barHidden: false
    readonly property bool vertical: root.requestedVertical
    readonly property string position: "top"
    readonly property int barSize: 32
    readonly property int barExclusiveSize: 32
    readonly property var layoutController: fakeController
    readonly property var visualTokens: fakeTokens
    readonly property var activeStyle: fakeStyle
    readonly property color urgent: "#88aaff"
    readonly property color foreground: "#eeeeee"
    readonly property bool tooltipShown: false
    readonly property var tooltipTarget: null
    property string tooltipText: ""

    function registerLayoutSession(session) {}
    function unregisterLayoutSession(session) {}
    function releasePopoutsForScreen(screenName) {}
    function connectedPanelForScreen(screenName) {
      return ({
        owner: null,
        screenName: String(screenName || ""),
        reveal: 0,
        hostCaret: false,
        x: 0,
        cardX: 0,
        cardY: 0,
        cardWidth: 0,
        cardHeight: 0
      })
    }
    function targetBelongsToWindow(target, window) { return false }
  }

  Component {
    id: testSurface

    Item {
      property var layoutSession: null
      property string screenName: ""

      SectionHost {
        id: sectionHost
        anchors.fill: parent
        externalMode: true
        requestedV2: root.requestedV2
        requestedEditing: root.requestedEditing
        requestedVertical: root.requestedVertical
        onReady: {
          root.readySurfaces++
          console.log("P0_WAYLAND_SURFACE_READY count="
            + root.readySurfaces + " screen=" + screenName)
        }
      }

      Component.onCompleted: {
        root.createdSurfaces++
        console.log("P0_WAYLAND_SURFACE_CREATED count="
          + root.createdSurfaces + " screen=" + screenName)
      }
      Component.onDestruction: {
        root.destroyedSurfaces++
        console.log("P0_WAYLAND_SURFACE_DESTROYED count="
          + root.destroyedSurfaces + " screen=" + screenName)
      }
    }
  }

  Component {
    id: testTooltip
    Item {}
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      Core.BarPanel {
        required property var modelData
        bar: fakeBar
        screen: modelData
      }
    }
  }

  Timer {
    interval: 30000
    running: true
    onTriggered: {
      console.error("P0_WAYLAND_HARNESS_ERROR watchdog created="
        + root.createdSurfaces + " ready=" + root.readySurfaces
        + " destroyed=" + root.destroyedSurfaces)
      Qt.exit(1)
    }
  }

  Component.onCompleted: console.log("P0_WAYLAND_READY v2="
    + requestedV2 + " editing=" + requestedEditing
    + " vertical=" + requestedVertical)
}
