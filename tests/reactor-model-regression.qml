import QtQuick
import "../services/QuoteDefaults.js" as QuoteDefaults
import "../services/ReactorModel.js" as ReactorModel

Item {
  function fail(message) {
    console.error("reactor-model-regression:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    if (ReactorModel.sanitize("Héllo — ß", 64) !== "HELLO - SS")
      return fail("text sanitization changed")
    if (ReactorModel.workspaceLabel(0) !== "EMPTY"
        || ReactorModel.workspaceLabel(1) !== "1 APP"
        || ReactorModel.workspaceLabel(3) !== "3 APPS")
      return fail("workspace labels changed")
    if (ReactorModel.parseAddress("0xABCDEF,kitty,title") !== "abcdef")
      return fail("Hyprland address parsing changed")

    const now = 2000000
    const valid = ReactorModel.parseExternal(
      "1999000\tBuild ready\tCI", 1998000, now)
    if (!valid || valid.left !== "BUILD READY" || valid.right !== "CI")
      return fail("valid external event was rejected")
    if (ReactorModel.parseExternal("1999000\told\tCI", 1999000, now))
      return fail("replayed external event was accepted")
    if (ReactorModel.parseExternal("2400001\tfuture\tCI", 0, now))
      return fail("future external event was accepted")
    if (ReactorModel.parseExternal("invalid\tbad\tCI", 0, now))
      return fail("malformed external event was accepted")

    let events = []
    for (let index = 0; index < 20; index++)
      events = ReactorModel.boundedAppend(events, { serial: index }, 8)
    if (events.length !== 8 || events[0].serial !== 12
        || events[7].serial !== 19)
      return fail("event history is not bounded")
    if (ReactorModel.profile("unsafe") !== "long")
      return fail("invalid event profile did not fail closed")
    if (ReactorModel.profile("quote") !== "quote")
      return fail("quote event profile was rejected")

    const quotes = ReactorModel.parseQuotes([
      "# comment",
      "Do great work. | Ada",
      "Second line",
      "  | ignored"
    ].join("\n"))
    if (quotes.length !== 2
        || quotes[0].quote !== "DO GREAT WORK."
        || quotes[0].author !== "ADA"
        || quotes[1].author !== "")
      return fail("quote parsing changed")
    if (QuoteDefaults.values().length !== 29)
      return fail("V1 default quote set is incomplete")

    console.log("reactor model regression passed")
    Qt.exit(0)
  }
}
