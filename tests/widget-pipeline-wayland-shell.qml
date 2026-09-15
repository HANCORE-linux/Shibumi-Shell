pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Inert user-plugin payload loaded by the unchanged native Omarchy ShellRoot.
// It owns no service, process, platform singleton, panel, or network access.
Item {
  id: root

  property var bar: null
  property var settings: ({})
  property string moduleName: ""
  property string hostGroupId: ""
  property real availableWidth: 0
  readonly property bool widgetPipelineMarker: true
  property bool readyReported: false
  property string readyOutputName: ""
  readonly property var containingWindow: root.QsWindow ? root.QsWindow.window : null
  readonly property string outputName: containingWindow && containingWindow.screen
    ? String(containingWindow.screen.name || "") : ""
  readonly property string observedStyle: bar && bar.visualTokens
    ? String(bar.visualTokens.shellStyle || "") : ""
  readonly property bool mappedOnValidOutput: !!containingWindow
    && containingWindow.backingWindowVisible && outputName !== ""
    && containingWindow.screen.width > 0 && containingWindow.screen.height > 0
  onModuleNameChanged: Qt.callLater(reportReady)
  onOutputNameChanged: Qt.callLater(reportReady)
  onObservedStyleChanged: Qt.callLater(reportReady)
  onMappedOnValidOutputChanged: Qt.callLater(reportReady)

  implicitWidth: 44
  implicitHeight: 24
  visible: true

  Rectangle {
    anchors.fill: parent
    radius: 5
    color: "#88aaff"
  }

  function reportReady() {
    if (readyReported || moduleName !== "hancore.shibumi.cpu"
        || observedStyle !== "notch" || !mappedOnValidOutput) return
    readyOutputName = outputName
    readyReported = true
    console.info("PIPELINE_NATIVE_MARKER_READY id=" + moduleName
      + " screen=" + outputName + " style=" + observedStyle)
  }

  // WidgetSlot injects the production Bar from Loader.onLoaded, after this
  // component's completion handler. Observe its actual mapped window through
  // existing property notifications, with one report per marker instance.
  Component.onCompleted: Qt.callLater(reportReady)
  Component.onDestruction:
    console.info("PIPELINE_NATIVE_MARKER_DESTROYED id=hancore.shibumi.cpu screen="
      + readyOutputName)
}
