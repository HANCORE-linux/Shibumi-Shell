import QtQuick
import Quickshell
import "services" as Services

ShellRoot {
  id: root
  property var receivedEvent: null

  QtObject {
    id: fakeBar
    property int reactorMode: 8
  }

  Services.QuoteService {
    id: quoteService
    bar: fakeBar
  }

  Connections {
    target: quoteService
    function onEventRaised(event) { root.receivedEvent = event }
  }

  Timer {
    interval: 1200
    running: true
    onTriggered: {
      if (!quoteService.armed || !root.receivedEvent
          || root.receivedEvent.profile !== "quote"
          || root.receivedEvent.kind !== "text"
          || String(root.receivedEvent.left || "") === ""
          || quoteService.eventCount !== 1) {
        console.error("quote service smoke failed")
        Qt.exit(1)
        return
      }
      console.log("quote service smoke passed")
      Qt.exit(0)
    }
  }
}
