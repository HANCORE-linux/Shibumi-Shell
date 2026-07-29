import QtQuick
import "../core/PanelRouting.js" as PanelRouting

Item {
  id: root
  visible: false
  width: 0
  height: 0

  QtObject {
    id: directPanel
    property bool opened: false
    function open() { opened = true }
    function close() { opened = false }
  }

  QtObject {
    id: secondDirectPanel
    property bool opened: false
    function open() { opened = true }
    function close() { opened = false }
  }

  QtObject {
    id: childPanel
    property bool opened: false
    function open() { opened = true }
    function close() { opened = false }
  }

  QtObject {
    id: center
    function childPanelWidget(id) {
      return id === "omarchy.weather" ? childPanel : null
    }
  }

  QtObject { id: malformedChild }

  QtObject {
    id: malformedCenter
    function childPanelWidget(_id) { return malformedChild }
  }

  function fail(message) {
    console.error("panel-routing-regression:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    const slots = [
      { moduleName: "omarchy.network", activeItem: directPanel, screenName: "DP-1" },
      { moduleName: "hancore.shibumi.center", activeItem: center, screenName: "DP-1" },
      { moduleName: "omarchy.network", activeItem: secondDirectPanel, screenName: "HDMI-A-1" }
    ]
    if (PanelRouting.findPanelWidget(slots, "omarchy.network") !== directPanel
        || PanelRouting.findPanelWidget(slots, "omarchy.weather") !== childPanel
        || PanelRouting.findPanelWidget(slots, "missing") !== null) {
      fail("direct/nested resolution")
      return
    }
    if (PanelRouting.findPanelWidgetForScreen(
          slots, "omarchy.network", "HDMI-A-1") !== secondDirectPanel
        || PanelRouting.findPanelWidgetForScreen(
          slots, "omarchy.network", "DP-1") !== directPanel
        || PanelRouting.findPanelWidgetForScreen(
          slots, "omarchy.network", "missing") !== directPanel) {
      fail("screen-aware routing")
      return
    }
    const panels = PanelRouting.panelWidgets(slots, "omarchy.network")
    if (panels.length !== 2 || panels[0] !== directPanel
        || panels[1] !== secondDirectPanel) {
      fail("panel enumeration")
      return
    }
    if (PanelRouting.findPanelWidget([
          { moduleName: "hancore.shibumi.center", activeItem: malformedCenter }
        ], "omarchy.weather") !== null) {
      fail("malformed child accepted")
      return
    }
    console.log("panel routing regression passed")
    Qt.exit(0)
  }
}
