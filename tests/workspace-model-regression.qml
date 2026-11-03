import QtQuick
import QtTest
import "../hancore.shibumi.workspaces/WorkspaceModel.js" as WorkspaceModel

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

  function test_monitorBlocks() {
    compare(WorkspaceModel.readBlocks("0\teDP-1\tpanel\n1\tDP-1\texternal\n2\t\tunplugged\n"),
      {"eDP-1": 0, "DP-1": 1})
    compare(WorkspaceModel.readBlocks("bad\tDP-1\tid\n-1\tDP-2\tid\n999\tDP-3\tid\n"), {})
    const rows = [{id: 2, monitor: {name: "eDP-1"}},
      {id: 12, monitor: {name: "DP-1"}}, {id: 19, monitor: {name: "DP-1"}},
      {id: 22, monitor: {name: "DP-1"}}, {id: -99, monitor: {name: "DP-1"}}]
    compare(WorkspaceModel.monitorIds("10", rows, 1, "DP-1", 12),
      [11,12,13,14,15,16,17,18,19,20,22])
    compare(WorkspaceModel.monitorIds("5", rows, 1, "DP-1", 12),
      [11,12,13,14,15,19,22])
    compare(WorkspaceModel.monitorIds("active", rows, 1, "DP-1", 12), [12,19,22])
    // An unplugged output's active guest must not redefine the receiving block.
    compare(WorkspaceModel.monitorIds("5", rows, 0, "eDP-1", 22), [1,2,3,4,5])
    rows[3] = {id: 6, monitor: {name: "eDP-1"}}
    compare(WorkspaceModel.monitorIds("5", rows, 0, "eDP-1", 6), [1,2,3,4,5,6])
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
