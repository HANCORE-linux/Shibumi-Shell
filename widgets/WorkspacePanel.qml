pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var workspaceService
  property int cursorIndex: workspaceService.entries.length > 0 ? 0 : -1
  readonly property var rows: workspaceService.entries
  readonly property int renderedRowCount: panelContent.renderedRowCount
  readonly property bool controlsFitWidth: panelContent.controlsFitWidth

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: panelContent.focusTarget
  gap: 8
  padding: 12
  contentWidth: fittedContentWidth(240)
  contentHeight: fittedContentHeight(panelContent.implicitHeight)

  function focusedRowIndex() {
    for (let index = 0; index < rows.length; index++) {
      if (rows[index] && rows[index].focused === true) return index
    }
    return rows.length > 0 ? 0 : -1
  }

  function moveCursor(delta) {
    if (rows.length === 0) {
      cursorIndex = -1
      return false
    }
    cursorIndex = (Math.max(0, cursorIndex) + delta + rows.length) % rows.length
    panelContent.positionAt(cursorIndex)
    return true
  }

  function activateCursor() {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return false
    const focused = workspaceService.focusWorkspace(rows[cursorIndex].id)
    if (focused) ownerWidget.close()
    return focused
  }

  onRowsChanged: {
    if (rows.length === 0) cursorIndex = -1
    else cursorIndex = Math.max(0, Math.min(cursorIndex, rows.length - 1))
  }
  onOpenChanged: if (open) cursorIndex = focusedRowIndex()

  WorkspacePanelContent {
    id: panelContent
    anchors.fill: parent
    controller: panel
  }
}
