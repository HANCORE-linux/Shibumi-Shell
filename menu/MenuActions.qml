import QtQuick
import Quickshell
import qs.Commons as Commons

QtObject {
  id: root

  property var detachedRunner: null

  function validAction(value) {
    const action = String(value || "").trim()
    return action.length > 0 && action.length <= 8192 && action.indexOf("\u0000") < 0
      ? action : ""
  }

  function runAction(value) {
    const action = validAction(value)
    if (!action) return false
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
