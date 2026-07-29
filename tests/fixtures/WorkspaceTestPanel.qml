import QtQuick

Item {
  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var workspaceService
  readonly property bool ready: anchorItem !== null && bar !== null
    && ownerWidget !== null && workspaceService !== null
}
