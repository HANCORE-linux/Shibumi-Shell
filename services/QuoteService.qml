pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "QuoteDefaults.js" as QuoteDefaults
import "ReactorModel.js" as ReactorModel

Item {
  id: root

  required property var bar
  readonly property bool active: bar && bar.reactorMode === 8
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
    if (!active || quotes.length === 0) return false
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
    let parsed = []
    try { parsed = ReactorModel.parseQuotes(quotesReader.text()) }
    catch (_error) {}
    if (parsed.length === 0) return false
    quotes = parsed
    currentIndex = -1
    if (armed) {
      cleared()
      cycle.interval = 250
      cycle.restart()
    }
    return true
  }

  function runTest(kindValue, _argumentValue) {
    const kind = String(kindValue || "").toLowerCase()
    if (kind === "clear") {
      cleared()
      return true
    }
    if (kind === "quote" || kind === "next" || kind === "text")
      return publishNext()
    return false
  }

  FileView {
    id: quotesReader
    path: root.quotesPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.reloadQuotes()
  }

  Timer {
    id: cycle
    interval: 450
    onTriggered: {
      root.armed = true
      root.publishNext()
      interval = 16000
      restart()
    }
  }

  Component.onCompleted: cycle.start()
}
