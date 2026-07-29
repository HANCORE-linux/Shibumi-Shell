pragma ComponentBehavior: Bound

import QtQuick

Item {
  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var powerService
  readonly property bool open: ownerWidget.opened
  readonly property bool ready: anchorItem !== null && bar !== null
    && ownerWidget !== null && powerService !== null

  function syncPopout() {
    if (open) bar.requestPopout(ownerWidget)
    else bar.releasePopout(ownerWidget)
  }

  onOpenChanged: syncPopout()
  Component.onCompleted: syncPopout()
  Component.onDestruction: bar.releasePopout(ownerWidget)
}
