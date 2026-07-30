import QtQuick
import Quickshell
import qs.Commons as Commons

QtObject {
  id: root

  property var detachedRunner: null
  property var pickerRouter: null

  function validAction(value) {
    const action = String(value || "").trim()
    return action.length > 0 && action.length <= 8192 && action.indexOf("\u0000") < 0
      ? action : ""
  }

  function pickerMode(action) {
    if (/(^|[^A-Za-z0-9._-])omarchy-theme-bg-switcher([^A-Za-z0-9._-]|$)/
        .test(action))
      return "wallpaper"
    if (/(^|[^A-Za-z0-9._-])omarchy-theme-switcher([^A-Za-z0-9._-]|$)/
        .test(action))
      return "theme"
    return ""
  }

  function routePicker(action) {
    const mode = pickerMode(action)
    if (!mode || !pickerRouter) return false
    if (typeof pickerRouter.routeOmarchyAction === "function")
      return pickerRouter.routeOmarchyAction(mode, null) === "handled"
    return typeof pickerRouter.openMode === "function"
      && pickerRouter.openMode(mode, null) === true
  }

  function runAction(value) {
    const action = validAction(value)
    if (!action) return false
    // Omarchy menu entries retain their authoritative shell action as the
    // fallback. When the Shibumi picker service is available, its configured
    // provider owns the open instead; "omarchy" delegates back to Quattro.
    if (routePicker(action)) return true
    if (typeof detachedRunner === "function") detachedRunner(action)
    else if (typeof Commons.Util.execDetached === "function")
      Commons.Util.execDetached(action)
    else Quickshell.execDetached(["bash", "-lc", action])
    return true
  }

  function launchApplication(entry) {
    if (!entry || typeof entry.execute !== "function") return false
    entry.execute()
    return true
  }
}
