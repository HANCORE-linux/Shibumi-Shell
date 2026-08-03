pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import "WorkspaceModel.js" as WorkspaceModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var stateService: shell && typeof shell.serviceFor === "function"
    ? shell.serviceFor("hancore.shibumi.state") : null
  property var actionAdapter: workspaceActions
  property var config: stateService && stateService.config
    ? stateService.config.workspace : ({})
  property var workspaceSource: Hyprland.workspaces.values || []
  property var focusedWorkspaceSource: Hyprland.focusedWorkspace
  readonly property int focusedId: WorkspaceModel.positiveId(
    focusedWorkspaceSource ? focusedWorkspaceSource.id : 0)
  readonly property var entries: WorkspaceModel.snapshot(
    workspaceSource, focusedId)
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
    return actionAdapter
      && typeof actionAdapter.focusWorkspace === "function"
      ? actionAdapter.focusWorkspace(id) : false
  }

  function setPreference(name, value) {
    const key = String(name || "")
    const next = String(value || "")
    if (key === "mode" && ["10", "5", "active"].indexOf(next) < 0)
      return false
    if (key === "style"
        && ["default", "numbers", "magic", "kanji", "rings", "aurora", "pacman"]
          .indexOf(next) < 0) return false
    if (key !== "mode" && key !== "style") return false
    return stateService
      && typeof stateService.setWorkspacePreference === "function"
      ? stateService.setWorkspacePreference(key, next) : false
  }

  WorkspaceActions { id: workspaceActions }
}
