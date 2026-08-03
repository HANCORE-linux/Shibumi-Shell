import QtQuick
import QtTest
import "../services/WorkspaceModel.js" as WorkspaceModel

TestCase {
  name: "WorkspaceModel"

  function workspaceEntries() {
    return WorkspaceModel.snapshot([
      { id: -99, toplevels: { values: [{}] } },
      { id: 8, toplevels: { values: [{}, {}] } },
      { id: 2, toplevels: { values: [{}] } },
      { id: 8, toplevels: { values: [{}] } },
      { id: 12, toplevels: { values: [{}] } },
      { id: "bad", toplevels: { values: [{}] } }
    ], 6)
  }

  function test_snapshot() {
    const entries = workspaceEntries()
    compare(entries.map(function(entry) { return entry.id }), [2, 6, 8, 12])
    compare(entries[2].windowCount, 2)
    verify(entries[2].occupied)
    verify(entries[3].occupied)
    verify(entries[1].focused)
    verify(!entries[1].occupied)
  }

  function test_visibleIds() {
    const entries = workspaceEntries()
    compare(WorkspaceModel.visibleIds("5", entries, 6),
      [1, 2, 3, 4, 5, 6, 8, 12])
    compare(WorkspaceModel.visibleIds("10", entries, 2),
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12])
    compare(WorkspaceModel.visibleIds("active", entries, 6), [2, 6, 8, 12])
    compare(WorkspaceModel.visibleIds("unsafe", [], 0),
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  }

  function test_stateFor() {
    const entries = workspaceEntries()
    const focused = WorkspaceModel.stateFor(6, entries, 6)
    const empty = WorkspaceModel.stateFor(5, entries, 6)
    verify(focused.focused)
    compare(focused.windowCount, 0)
    verify(!empty.focused)
    verify(!empty.occupied)
  }
}
