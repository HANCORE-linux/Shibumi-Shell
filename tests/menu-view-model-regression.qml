import QtQuick
import "../menu/MenuModel.js" as MenuModel
import "../menu/MenuViewModel.js" as MenuViewModel

QtObject {
  function fail(message) {
    throw new Error("menu-view-model-regression: " + message)
  }

  Component.onCompleted: {
    const source = MenuModel.parseMenuJsonc(`{
      "apps": { "label": "Apps", "icon": "A", "action": "official-launcher" },
      "style": { "label": "Style", "icon": "S" },
      "style.theme": { "label": "Theme", "keywords": "colors", "action": "theme" },
      "style.font": { "label": "Font", "provider": "fonts" },
      "setup": { "label": "Setup", "when": "true" },
      "setup.browser": { "label": "Browser", "checked": "true", "action": "browser" },
      "hidden": { "label": "Hidden", "when": "false", "action": "hidden" }
    }`)
    const model = MenuModel.mergeMenuSources(source.items, [])
    const whenResults = ({ "$setup": true, "$hidden": false })
    const checkedResults = ({ "$setup.browser": true })

    const rootRows = MenuViewModel.routeRows(
      model, "root", "", whenResults, checkedResults, 256)
    if (rootRows.length !== 3 || rootRows.some(row => row.id === "hidden"))
      return fail("root visibility")
    const apps = rootRows.filter(row => row.id === "apps")[0]
    if (!apps || apps.kind !== "menu" || apps.target !== "apps")
      return fail("integrated apps route")

    const styleRows = MenuViewModel.routeRows(
      model, "style", "", whenResults, checkedResults, 256)
    if (styleRows.length !== 2 || styleRows[0].detail !== "")
      return fail("direct children")

    const searched = MenuViewModel.routeRows(
      model, "root", "colors", whenResults, checkedResults, 256)
    if (searched.length !== 1 || searched[0].id !== "style.theme"
        || searched[0].section !== "drilldown" || searched[0].detail !== "Style")
      return fail("descendant search")

    const setupRows = MenuViewModel.routeRows(
      model, "setup", "", whenResults, checkedResults, 256)
    if (setupRows.length !== 1 || !setupRows[0].checkedState)
      return fail("checked state")
    if (MenuViewModel.routeRows(model, "root", "", ({}), ({}), 256)
        .some(row => row.id === "setup" || row.id === "hidden"))
      return fail("missing guards are not fail-closed")

    const providers = MenuViewModel.providerIds(model, "root", "font")
    if (providers.length !== 1 || providers[0] !== "style.font")
      return fail("search provider discovery")

    console.log("menu view model regression passed")
    Qt.exit(0)
  }
}
