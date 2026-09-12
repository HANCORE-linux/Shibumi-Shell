pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import "WorkspaceModel.js" as WorkspaceModel
import "../hancore.shibumi.state/runtime" as SuiteRuntime

Item {
  id: root

  property var shell: null
  property var manifest: null
  SuiteRuntime.HostShell { id: suiteShell; host: root.shell }
  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.workspaces"
    implementationVersion: "0.1.1-beta.13"
    owner: root
    host: root.shell
    manifest: root.manifest
  }
  // Wiring admission is not native Hyprland connection readiness.
  readonly property bool backendAdmitted: runtimeProvider.registered
  property var stateService: suiteShell.serviceFor("hancore.shibumi.state")
  // An explicit fake replaces models AND actions; incomplete fakes never
  // fall through to Hyprland or the native action adapter.
  property var backendOverride: null
  property var config: stateService && stateService.config
    ? stateService.config.workspace : ({})
  readonly property int focusedId: backend.focusedId
  readonly property var entries: backend.entries
  readonly property string mode: config && ["10", "5", "active"].indexOf(
    String(config.mode || "")) !== -1 ? String(config.mode) : "10"
  readonly property string style: config
    && ["default", "numbers", "magic", "kanji", "rings", "aurora", "pacman"].indexOf(
      String(config.style || "")) !== -1 ? String(config.style) : "default"
  readonly property var visibleWorkspaceIds: WorkspaceModel.visibleIds(
    mode, entries, focusedId)

  visible: false
  width: 0
  height: 0

  function workspaceState(id) {
    return WorkspaceModel.stateFor(id, entries, focusedId)
  }

  function focusWorkspace(id) {
    if (!backendAdmitted) return false
    let target
    try { target = Number(id) } catch (error) { return false }
    if (!Number.isInteger(target) || target <= 0 || target > 9999) return false
    if (backendOverride !== null) {
      const record = backend.recordFor(backendOverride)
      if (!record || record.owner !== backendOverride || !backendAdmitted) return false
      try { return record.action.call(record.owner, target) === true }
      catch (error) { return false }
    }
    if (!backendAdmitted) return false
    return workspaceActions.focusWorkspace(target)
  }

  function setPreference(name, value) {
    if (!backendAdmitted) return false
    let key, next
    try { key = String(name || ""); next = String(value || "") }
    catch (error) { return false }
    if (key === "mode" && ["10", "5", "active"].indexOf(next) < 0)
      return false
    if (key === "style"
        && ["default", "numbers", "magic", "kanji", "rings", "aurora", "pacman"]
          .indexOf(next) < 0) return false
    if (key !== "mode" && key !== "style") return false
    if (!backendAdmitted) return false
    return stateService
      && typeof stateService.setWorkspacePreference === "function"
      ? stateService.setWorkspacePreference(key, next) : false
  }

  QtObject {
    id: backend
    readonly property bool overridden: root.backendOverride !== null
    readonly property var record: recordFor(root.backendOverride)
    readonly property var workspaces: !overridden && root.backendAdmitted
      ? Hyprland.workspaces.values || [] : []
    readonly property var focused: !overridden && root.backendAdmitted
      ? Hyprland.focusedWorkspace : null
    readonly property int focusedId: overridden ? record ? record.focusedId : 0
      : WorkspaceModel.positiveId(focused ? focused.id : 0)
    readonly property var entries: overridden ? record ? record.entries : []
      : WorkspaceModel.snapshot(workspaces, focusedId)
    function recordFor(value) {
      try {
        if (!value || typeof value !== "object") return null
        const sources = value.workspaces
        const focused = value.focusedWorkspace
        const action = value.focusWorkspace
        if (!Array.isArray(sources) || sources.length > 10000 || typeof action !== "function"
            || (focused !== null && (!focused || typeof focused !== "object"))) return null
        const focusValue = focused === null ? 0 : Number(focused.id)
        if (!Number.isInteger(focusValue)) return null
        const focusId = WorkspaceModel.positiveId(focusValue)
        const rows = WorkspaceModel.snapshot(sources, focusId)
        if (rows.some(function(row) { return !Number.isInteger(row.windowCount) || row.windowCount < 0 })) return null
        return {owner: value, entries: rows, focusedId: focusId, action: action}
      } catch (error) { return null }
    }
  }
  WorkspaceActions { id: workspaceActions }
}
