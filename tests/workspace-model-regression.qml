import QtQuick
import "../services/WorkspaceModel.js" as WorkspaceModel

QtObject {
  function fail(message) {
    console.error("workspace-model-regression:", message)
    Qt.exit(1)
  }

  function same(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  Component.onCompleted: {
    const workspaces = [
      { id: -99, toplevels: { values: [{}] } },
      { id: 8, toplevels: { values: [{}, {}] } },
      { id: 2, toplevels: { values: [{}] } },
      { id: 8, toplevels: { values: [{}] } },
      { id: "bad", toplevels: { values: [{}] } }
    ]
    const entries = WorkspaceModel.snapshot(workspaces, 6)
    if (!same(entries.map(entry => entry.id), [2, 6, 8]))
      fail("snapshot did not sort, sanitize, and include focus")
    if (entries[2].windowCount !== 2 || !entries[2].occupied
        || !entries[1].focused || entries[1].occupied)
      fail("snapshot state is incorrect")

    if (!same(WorkspaceModel.visibleIds("5", entries, 6), [1, 2, 3, 4, 5, 6]))
      fail("persist-5 did not append focused workspace")
    if (!same(WorkspaceModel.visibleIds("10", entries, 2),
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
      fail("persist-10 changed for in-range focus")
    if (!same(WorkspaceModel.visibleIds("active", entries, 6), [2, 6, 8]))
      fail("active mode did not expose actual positive workspaces")
    if (!same(WorkspaceModel.visibleIds("unsafe", [], 0),
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
      fail("invalid mode did not fail to persist-10")

    const focused = WorkspaceModel.stateFor(6, entries, 6)
    const empty = WorkspaceModel.stateFor(5, entries, 6)
    if (!focused.focused || focused.windowCount !== 0
        || empty.focused || empty.occupied)
      fail("per-workspace state is incorrect")

    console.log("workspace model regression passed")
    Qt.exit(0)
  }
}
