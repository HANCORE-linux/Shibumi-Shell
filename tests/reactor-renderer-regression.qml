import QtQuick
import "../styles/shibumi" as ShibumiStyle

Item {
  id: root
  width: 800
  height: 32

  QtObject {
    id: fakeBar
    property color urgent: "#ff3366"
  }

  QtObject {
    id: fakeService
    signal eventRaised(var event)
    signal cleared()
  }

  ShibumiStyle.ReactorEventLayer {
    id: renderer
    anchors.fill: parent
    bar: fakeBar
    service: fakeService
    screenName: "DP-1"
    runs: [
      { x: 0, width: 180 },
      { x: 390, width: 40 },
      { x: 620, width: 180 }
    ]
  }

  function fail(message) {
    console.error("reactor-renderer-regression:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    if (!renderer.active || !renderer.accepts({ screen: "DP-1" })
        || renderer.accepts({ screen: "DP-2" }))
      return fail("screen filtering changed")

    fakeService.eventRaised({
      serial: 1, kind: "text", left: "OTHER", right: "SCREEN",
      profile: "short", screen: "DP-2"
    })
    if (renderer.pulses.length !== 0)
      return fail("foreign-screen event was accepted")

    fakeService.eventRaised({
      serial: 2, kind: "text", left: "LOCAL", right: "SCREEN",
      profile: "quote", screen: "DP-1",
      choices: [
        {
          quote: "THIS QUOTE IS FAR TOO LONG TO FIT IN THE AVAILABLE GAP AS A READABLE TWO LINE MESSAGE AND MUST BE SKIPPED",
          author: "TOO LONG"
        },
        { quote: "FIT", author: "OK" }
      ]
    })
    if (renderer.pulses.length !== 1 || !renderer.pulses[0].quote
        || renderer.pulses[0].life !== 12600)
      return fail("local quote event was not normalized")

  }

  Timer {
    interval: 250
    running: true
    onTriggered: {
      if (!renderer.pulses[0].grid
          || renderer.pulses[0].grid.selectedQuote !== "FIT"
          || renderer.pulses[0].grid.selectedAuthor !== "-OK")
        return root.fail("quote fit did not skip an oversized candidate")
      fakeService.cleared()
      if (renderer.pulses.length !== 0)
        return root.fail("renderer clear did not release pulses")
      console.log("reactor renderer regression passed")
      Qt.exit(0)
    }
  }
}
