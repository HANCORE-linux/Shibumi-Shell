// Explicit fixture window replacement, not stock-bar UI coverage.
import QtQuick
import Quickshell.Io
Item {
  id: root
  property string omarchyPath: ""
  property var barWidgetRegistry: null
  property var barConfig: null
  property var shell: null
  property var manifest: null
  property bool barHidden: false
  property int barSize: 28
  property string position: "top"
  property string fontFamily: "sans-serif"
  IpcHandler {
    target: "native-stock-probe"
    function status(): string {
      // This native first-party stub receives the actual root, unlike the
      // third-party State facade being tested. The stock loader can complete
      // before its manifest is discovered. Report root ownership separately:
      // same-engine bar transitions are not the production restart boundary.
      return JSON.stringify({ready: root.omarchyPath !== "" && root.shell !== null
        && root.shell.activeBarId === "omarchy.bar"
        && root.barConfig !== null && root.barConfig.id === "omarchy.bar",
        publishedOwner: root.shell !== null && root.shell.bar === root})
    }
  }
}
