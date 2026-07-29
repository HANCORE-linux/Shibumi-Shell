import QtQuick
import "../menu/AppIndex.js" as AppIndex

QtObject {
  function fail(message) {
    throw new Error("app-index-regression: " + message)
  }

  function ids(rows) {
    return rows.map(function(row) { return row.id }).join(",")
  }

  function rowForId(rows, id) {
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].id === id) return rows[i]
    }
    return null
  }

  Component.onCompleted: {
    const values = [
      { id: "org.example.Terminal.desktop", name: "Terminal", genericName: "Shell", comment: "Command line", keywords: ["console"], icon: "terminal" },
      { id: "org.example.Editor", name: "Code Editor", genericName: "Text Editor", comment: "Write code", keywords: ["development"], icon: "editor" },
      { id: "org.example.Browser", name: "Web Browser", genericName: "Internet", comment: "Browse the web", keywords: ["network"], icon: "browser" },
      { id: "org.example.Hidden", name: "Hidden App", icon: "hidden" },
      { id: "org.example.NoDisplay", name: "Private Helper", noDisplay: true },
      { id: "org.example.Editor.desktop", name: "Alternate Editor", icon: "alternate" },
      { id: "bad/path.desktop", name: "Unsafe" },
      { id: "", name: "Missing Id" }
    ]

    if (AppIndex.normalizeDesktopId("org.example.App.desktop") !== "org.example.App")
      return fail("desktop suffix normalization")
    if (AppIndex.normalizeDesktopId("bad/path.desktop") !== "")
      return fail("unsafe desktop id")
    const normalized = AppIndex.normalizeIdList([
      "org.example.Editor.desktop", "org.example.Editor", "", "bad/path"
    ], 10)
    if (normalized.join(",") !== "org.example.Editor") return fail("id list normalization")

    const base = AppIndex.sortedEntries(
      values, "", ["org.example.Browser", "org.example.Editor"], ["org.example.Hidden"], false)
    if (ids(base) !== "org.example.Browser,org.example.Editor,org.example.Terminal")
      return fail("favorite order, hidden filter, or deduplication")
    if (base[1].name !== "Alternate Editor")
      return fail("duplicate selection is not deterministic")

    const withHidden = AppIndex.sortedEntries(
      values, "", [], ["org.example.Hidden"], true)
    const hiddenRow = rowForId(withHidden, "org.example.Hidden")
    if (!hiddenRow || !hiddenRow.hidden)
      return fail("include-hidden mode")

    const listLike = ({ 0: values[0], 1: values[1], length: 2 })
    if (ids(AppIndex.sortedEntries(listLike, "", [], [], false))
        !== "org.example.Editor,org.example.Terminal")
      return fail("QML list-like source")

    const reservedId = [{ id: "__proto__", name: "Prototype App" }]
    if (ids(AppIndex.sortedEntries(reservedId, "", ["__proto__"], [], false)) !== "__proto__")
      return fail("reserved object-key desktop id")

    if (ids(AppIndex.sortedEntries(values, "shell", [], [], false)) !== "org.example.Terminal")
      return fail("generic-name search")
    if (ids(AppIndex.sortedEntries(values, "write code", [], [], false)) !== "org.example.Editor")
      return fail("multi-term search")
    if (ids(AppIndex.sortedEntries(values, "web", [], [], false)) !== "org.example.Browser")
      return fail("name-prefix search")
    if (ids(AppIndex.sortedEntries(values, "e", ["org.example.Browser"], [], false)).split(",")[0]
        !== "org.example.Browser")
      return fail("favorite priority during search")
    if (AppIndex.sortedEntries(values, "does-not-exist", [], [], false).length !== 0)
      return fail("non-match search")

    const reversed = AppIndex.sortedEntries(values.slice().reverse(), "", [], ["org.example.Hidden"], false)
    if (ids(reversed) !== "org.example.Editor,org.example.Terminal,org.example.Browser")
      return fail("input-order-independent result")

    console.log("app index regression passed")
    Qt.exit(0)
  }
}
