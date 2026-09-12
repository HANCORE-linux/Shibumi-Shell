pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "QuoteDefaults.js" as QuoteDefaults
import "ReactorModel.js" as ReactorModel

Item {
  id: root

  property bool backendEnabled: true
  property bool runtimeProbesEnabled: true
  readonly property bool active: backendEnabled
  readonly property string quotesPath: Quickshell.env("HOME")
    + "/.config/shibumi/quotes.txt"
  property var quotes: QuoteDefaults.values()
  property int currentIndex: -1
  property int serial: 0
  property int eventCount: 0
  property bool armed: false

  signal eventRaised(var event)
  signal cleared()

  visible: false
  width: 0
  height: 0

  function publishNext() {
    if (!active || quotesReader.busy || quotes.length === 0) return false
    currentIndex = (currentIndex + 1) % quotes.length
    const choices = []
    for (let offset = 0; offset < quotes.length && choices.length < 64; offset++) {
      const entry = quotes[(currentIndex + offset) % quotes.length]
      const quote = ReactorModel.sanitize(entry.quote, 160)
      const author = ReactorModel.sanitize(entry.author, 36)
      if (quote) choices.push({ quote: quote, author: author })
    }
    if (choices.length === 0) return false
    const selected = choices[0]
    eventCount++
    eventRaised({
      serial: ++serial,
      timestamp: Date.now(),
      kind: "text",
      direction: 1,
      left: selected.quote,
      right: selected.author ? "-" + selected.author : "",
      choices: choices,
      profile: "quote",
      screen: "",
      count: 1,
      gain: 1
    })
    return true
  }

  function reloadQuotes() {
    if (!active) return false
    let parsed = []
    try { if (quotesReader.available) parsed = ReactorModel.parseQuotes(quotesReader.text) }
    catch (_error) {}
    quotes = parsed.length > 0 ? parsed : QuoteDefaults.values()
    currentIndex = -1
    if (armed) {
      cleared()
      cycle.interval = 250
      cycle.restart()
    }
    return true
  }

  function runTest(kindValue, _argumentValue) {
    if (!active) return false
    const kind = String(kindValue || "").toLowerCase()
    if (kind === "clear") {
      cleared()
      return true
    }
    if (kind === "quote" || kind === "next" || kind === "text")
      return publishNext()
    return false
  }

  BoundedTextSource {
    id: quotesReader
    kind: "quotes"
    active: root.runtimeProbesEnabled && root.active
    onUpdated: root.reloadQuotes()
  }

  Timer {
    id: cycle
    interval: 450
    onTriggered: {
      if (!root.active || !root.runtimeProbesEnabled) return
      root.armed = true
      root.publishNext()
      interval = 16000
      restart()
    }
  }

  function syncCycle() {
    if (active && runtimeProbesEnabled) {
      cycle.interval = 450
      cycle.start()
    } else {
      cycle.stop()
      armed = false
    }
  }
  onActiveChanged: syncCycle()
  onRuntimeProbesEnabledChanged: syncCycle()
  Component.onCompleted: syncCycle()
}
