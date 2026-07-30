import QtQuick
import Quickshell
import "menu" as AppMenu

ShellRoot {
  id: root

  property int attempts: 0
  property int phase: 0
  property var capturedAction: null
  property string routedPickerMode: ""
  property bool pickerRouteAvailable: true

  function fail(message) {
    console.error("app menu runtime smoke failed: " + message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeEntry
    property int executeCount: 0
    function execute() { executeCount++ }
  }

  QtObject {
    id: fakePickerRouter
    function routeOmarchyAction(mode, _screen) {
      root.routedPickerMode = mode
      return root.pickerRouteAvailable ? "handled" : "unavailable"
    }
  }

  AppMenu.AppMenuService {
    id: service
    omarchyPath: Quickshell.env("OMARCHY_PATH")
  }

  AppMenu.MenuActions {
    id: actions
    pickerRouter: fakePickerRouter
    detachedRunner: function(command) { root.capturedAction = command }
  }

  Timer {
    id: setupTimer
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.attempts++
      if (root.attempts > 200) return root.fail("Quattro source setup timed out")
      if (!service.menuReady) return
      stop()
      root.startRuntimeChecks()
    }
  }

  Timer {
    id: poller
    interval: 20
    repeat: true
    onTriggered: root.checkProgress()
  }

  function startRuntimeChecks() {
    attempts = 0
    phase = 1
    service.replaceMenuTexts(`{
      "root": { "label": "Go" },
      "visible": { "parent": "root", "label": "Visible", "when": "true", "checked": "true" },
      "quoted": { "parent": "root", "label": "Quoted", "when": "test \\\"O'Brien\\\" = \\\"O'Brien\\\"" },
      "hidden": { "parent": "root", "label": "Hidden", "when": "false" },
      "font": { "parent": "root", "label": "Font", "provider": "fonts" },
      "power": { "parent": "root", "label": "Power", "provider": "power-profiles" },
      "unsupported": { "parent": "root", "label": "Unsupported", "provider": "arbitrary" }
    }`, "")
    if (service.guardStatus !== "running" && service.guardStatus !== "queued")
      return fail("automatic guard process did not start")
    poller.start()
  }

  function checkProgress() {
    attempts++
    if (attempts > 250)
      return fail("runtime operations timed out: " + JSON.stringify(service.debugState())
        + ", font=" + service.providerStatus("font")
        + ", power=" + service.providerStatus("power"))
    if (phase === 2) {
      if (service.guardStatus === "running" || service.guardStatus === "queued"
          || service.guardStatus === "pending") return
      if (service.guardStatus !== "error" || service.guardsReady)
        return fail("failed guard process was not reported fail-closed: "
          + JSON.stringify(service.debugState()))
      if (service.menuChildren("root").some(row => row.id === "must-hide"))
        return fail("failed guard process exposed a guarded row")
      return finishRuntimeChecks()
    }
    if (!service.guardsReady) return

    if (service.providerStatus("font") === "idle") {
      const rootRows = service.menuChildren("root")
      const ids = rootRows.map(row => row.id)
      if (ids.indexOf("visible") < 0 || ids.indexOf("quoted") < 0
          || ids.indexOf("hidden") >= 0)
        return fail("guard visibility result")
      const visible = service.menuItem("visible")
      const visibleRows = rootRows.filter(row => row.id === visible.id)
      if (visibleRows.length !== 1 || !visibleRows[0].checkedState)
        return fail("guard checked result")
      if (service.loadProvider("unsupported") !== "unsupported")
        return fail("unsupported provider did not fail closed")
      service.loadProvider("font")
      service.loadProvider("power")
      return
    }

    if (service.providerStatus("font") !== "loaded"
        || service.providerStatus("power") !== "loaded") return

    const fonts = service.menuChildren("font")
    const powers = service.menuChildren("power")
    if (fonts.length !== 3 || powers.length !== 3)
      return fail("provider output was not integrated")
    if (!fonts.some(row => row.label === "JetBrains Mono" && row.icon === "✓"))
      return fail("font provider current marker")
    if (!fonts.some(row => row.label === "O'Brien Font"
        && row.action === "omarchy-font-set 'O'\\''Brien Font'"))
      return fail("font provider action quoting")
    if (!powers.some(row => row.label === "performance" && row.icon === "✓"))
      return fail("power provider current marker")

    if (phase === 1) {
      phase = 2
      attempts = 0
      service.replaceMenuTexts(`{
        "root": { "label": "Go" },
        "must-hide": { "parent": "root", "label": "Hidden on failure", "when": "kill -TERM $$" }
      }`, "")
      return
    }
  }

  function finishRuntimeChecks() {
    if (!actions.runAction("printf shibumi-runtime-smoke")
        || capturedAction !== "printf shibumi-runtime-smoke")
      return fail("action adapter dispatch")
    capturedAction = null
    if (!actions.runAction(
          'theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set "$theme"')
        || routedPickerMode !== "theme" || capturedAction !== null)
      return fail("theme action did not use configured picker route")
    if (!actions.runAction(
          'background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set "$background"')
        || routedPickerMode !== "wallpaper" || capturedAction !== null)
      return fail("wallpaper action did not use configured picker route")
    pickerRouteAvailable = false
    const fallbackAction = "omarchy-theme-switcher"
    if (!actions.runAction(fallbackAction)
        || capturedAction !== fallbackAction)
      return fail("unavailable picker route did not retain Omarchy fallback")
    if (actions.runAction("") || actions.runAction("bad\u0000action"))
      return fail("action adapter input validation")
    if (!actions.launchApplication(fakeEntry) || fakeEntry.executeCount !== 1)
      return fail("DesktopEntry launch dispatch")
    if (actions.launchApplication(null))
      return fail("invalid DesktopEntry dispatch")

    poller.stop()
    console.log("app menu runtime smoke passed")
    Qt.quit()
  }
}
