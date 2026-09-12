pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import "workspaces" as Workspaces
import "memory" as Memory
import "geometry" as Geometry

ShellRoot {
  id: root
  property int caseIndex: 0
  property int frames: 0
  property int startFrame: 0
  property int ticks: 0
  property int mismatches: 0
  property bool capturing: false
  property var capture: null
  property var sample: null
  property int sourceBarSize: 34
  readonly property var cases: {
    const values = []
    for (const height of [34, 35, 36])
      for (const radius of ["large", "small"])
        for (const border of [true, false])
          for (const position of ["top", "bottom"])
            values.push({form: "shibumi", barSize: height, radius: radius, border: border, position: position})
    for (const form of ["full", "fit", "dock", "notch"])
      for (const position of ["top", "bottom"])
        values.push({form: form, barSize: 0, radius: "large", border: true, position: position})
    return values
  }
  function check(value, message) {
    if (value) return
    console.error("workspaces-geometry:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  QtObject {
    id: state
    property var config: ({presentation: {shellStyle: "shibumi", radius: "large", shadow: false}})
    readonly property color selectedColor: "white"
    function paletteColor(id) { return "white" }
    function paletteContrastColor(id) { return "black" }
  }
  QtObject {
    id: workspace
    property var visibleWorkspaceIds: [1, 2, 3, 4, 5]
    property var entries: []
    property string style: "numbers"
    function workspaceState(id) { return {id: id, focused: id === 1, occupied: false, windowCount: 0} }
    function focusWorkspace(id) { return false }
  }
  QtObject {
    id: memory
    property int memPercent: 42
    property real memUsedGiB: 8
    property real memTotalGiB: 16
    function acquire(kind) {}
    function release(kind) {}
  }
  QtObject { id: telemetry; readonly property var system: memory }
  QtObject {
    id: host
    function serviceFor(id) {
      if (id === "hancore.shibumi.state") return state
      if (id === "hancore.shibumi.workspaces") return workspace
      if (id === "hancore.shibumi.telemetry") return telemetry
      return null
    }
  }
  QtObject {
    id: fakeBar
    property var shell: host
    property bool vertical: false
    property string position: "top"
    readonly property int barSize: root.sourceBarSize || visualTokens.barHeight
    property string fontFamily: "monospace"
    property color background: "black"
    property color foreground: "white"
    readonly property color barForeground: foreground
    property color urgent: "white"
    property bool foregroundAnimationEnabled: false
    readonly property var visualTokens: tokens
    readonly property var layoutController: ({v2Mode: tokens.v2Shell})
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
  }
  Geometry.VisualTokens { id: tokens; bar: fakeBar }
  Window {
    id: window
    width: 640; height: 80
    visible: true
    color: "transparent"
    onFrameSwapped: root.frames++
    Item {
      id: preview
      width: 640; height: 70
      // Source-derived V1 embedding: 32px group, centered 28px slot;
      // island origin 3px Top / 0px Bottom. This is not a full BarSurface test.
      Item {
        id: workspaceGroup
        x: 8; y: fakeBar.position === "top" ? tokens.islandOffsetY : 0
        width: 320; height: tokens.islandHeight
        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width; height: tokens.slotHeight
          Workspaces.BarWidget {
            id: workspaceWidget
            height: parent.height; width: implicitWidth
            bar: fakeBar
            settings: ({color: "color04", colorMode: "fill", surfaceOpacity: 1})
          }
        }
      }
      Item {
        x: 380; y: workspaceGroup.y
        width: 240; height: tokens.islandHeight
        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width; height: tokens.slotHeight
          Memory.BarWidget {
            id: memoryWidget
            height: parent.height; width: implicitWidth
            bar: fakeBar
            settings: ({color: "color04", colorMode: "fill", surfaceOpacity: 1})
          }
        }
      }
    }
    Rectangle { id: pulse; y: 76; width: 1; height: 1; color: "white" }
  }
  // Inspect only children of these explicitly owned fixture widgets.
  function pillFor(widget) {
    const found = []
    for (const surface of widget.children) {
      for (const child of surface.children) {
        if ("v1AppearanceEnabled" in child && child.v1AppearanceEnabled === true
            && "renderedSurfaceCount" in child) found.push(child)
      }
    }
    check(found.length === 1, "ambiguous owned pill")
    return found[0]
  }
  function bounds(item) {
    const point = item.mapToItem(preview, 0, 0)
    return {x: point.x, y: point.y, width: item.width, height: item.height,
      bottom: point.y + item.height, radius: item.tokens.pillRadius,
      border: item.tokens.pillBorderWidth, surfaces: item.renderedSurfaceCount,
      parentHeight: item.parent.height}
  }
  function finishCase() {
    caseIndex++
    if (caseIndex === cases.length) {
      check(mismatches === 0, "V1 G2 and reference pill bounds differ")
      console.log("workspaces geometry regression passed")
      Qt.exit(0)
      return
    }
    const next = cases[caseIndex]
    fakeBar.position = next.position
    sourceBarSize = next.barSize
    state.config = {presentation: {shellStyle: next.form, radius: next.radius, v1Border: next.border, shadow: false}}
    capturing = false
    startFrame = frames
  }
  Canvas {
    id: pixels
    parent: window.contentItem
    width: 640; height: 70
    visible: false
    onImageLoaded: analyze()
    function analyze() {
      if (!root.capture || !isImageLoaded(root.capture.url)) return
      const context = getContext("2d")
      context.clearRect(0, 0, width, height)
      context.drawImage(root.capture.url, 0, 0, width, height)
      function extent(rect) {
        const column = context.getImageData(Math.floor(rect.x + rect.width / 2), 0, 1, height).data
        let first = -1, last = -1
        for (let y = 0; y < height; y++) {
          if (column[y * 4 + 3] > 127) {
            if (first < 0) first = y
            last = y
          }
        }
        return {first: first, last: last}
      }
      root.sample.workspacePixels = extent(root.sample.workspace)
      root.sample.referencePixels = extent(root.sample.reference)
      console.log("G2_MEASURE", JSON.stringify(root.sample))
      if (!tokens.v2Shell) {
        const a = root.sample.workspace, b = root.sample.reference
        root.check(tokens.pillHeight === 24 && b.height === 24
          && a.surfaces === 1 && b.surfaces === 1
          && root.sample.workspacePixels.first === a.y
          && root.sample.workspacePixels.last === a.bottom - 1
          && root.sample.referencePixels.first === b.y
          && root.sample.referencePixels.last === b.bottom - 1,
          "V1 rendered pixels missing or not matching measured bounds")
        if (Math.abs(a.y - b.y) > 0.0001 || a.height !== b.height
            || a.bottom !== b.bottom || a.border !== b.border || a.radius !== b.radius
            || root.sample.workspacePixels.first !== root.sample.referencePixels.first
            || root.sample.workspacePixels.last !== root.sample.referencePixels.last)
          root.mismatches++
      } else {
        const a = root.sample.workspace
        const margin = Math.round((a.parentHeight - tokens.pillHeight) / 2)
        root.check(a.parentHeight === tokens.barHeight
          && a.height === a.parentHeight - 2 * margin
          && a.surfaces === 0 && root.sample.reference.surfaces === 0
          && workspaceWidget.numberMarkerRadius === 10 && workspaceWidget.frameMarkerRadius === 5,
          "V2 workspace geometry or native-pill suppression changed")
      }
      unloadImage(root.capture.url)
      root.capture = null
      root.finishCase()
    }
  }
  Timer {
    interval: 30; repeat: true; running: true
    onTriggered: {
      root.check(++root.ticks < 180, "render deadline frames=" + root.frames
        + " capturing=" + root.capturing + " canvas=" + pixels.available
        + " image=" + (root.capture ? pixels.isImageLoaded(root.capture.url) : false))
      pulse.x = pulse.x === 0 ? 1 : 0
      if (root.capturing || root.frames < root.startFrame + 3) return
      root.capturing = true
      root.sample = {form: tokens.shellStyle, position: fakeBar.position, barSize: fakeBar.barSize,
        workspace: root.bounds(root.pillFor(workspaceWidget)),
        reference: root.bounds(root.pillFor(memoryWidget))}
      root.check(preview.grabToImage(function(result) {
        root.capture = result
        pixels.loadImage(result.url)
        // image:// grabs may be cached synchronously and emit no imageLoaded.
        Qt.callLater(pixels.analyze)
      }), "owned preview capture refused")
    }
  }
}
