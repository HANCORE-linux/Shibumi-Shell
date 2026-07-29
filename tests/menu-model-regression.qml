import QtQuick
import "../menu/MenuModel.js" as MenuModel

QtObject {
  function fail(message) {
    throw new Error("menu-model-regression: " + message)
  }

  Component.onCompleted: {
    const defaults = MenuModel.parseMenuJsonc(`{
      // Dotted hierarchy and trailing commas.
      "style": { "icon": "S", "label": "Style" },
      "style.theme": {
        "icon": "T",
        "label": "Theme",
        "aliases": ["themes", "theme"],
        "keywords": "colors colors appearance",
        "action": "open https://example.com/a//b",
      },
      /* Runtime metadata is retained, not executed by the parser. */
      "setup.power": {
        "label": "Power",
        "provider": "power-profiles",
        "when": "powerprofilesctl list",
        "checked": "test current",
      },
      "bad/path": { "label": "Unsafe" },
    }`)
    if (!defaults.ok || defaults.items.length !== 3)
      return fail("JSONC parse, validation, or comments in strings")

    const user = MenuModel.parseMenuJsonc(`{
      "style.theme": { "label": "Theme picker" },
      "personal": { "label": "Personal" },
      "personal.notes": { "label": "Notes", "action": "open-notes" },
    }`)
    if (!user.ok) return fail("user source parse")

    const model = MenuModel.mergeMenuSources(defaults.items, user.items)
    const theme = MenuModel.item(model, "style.theme")
    if (!theme || theme.label !== "Theme picker" || theme.icon !== "T"
        || theme.action !== "open https://example.com/a//b")
      return fail("partial user override")
    if (theme.parent !== "style" || theme.kind !== "action")
      return fail("dotted parent or action kind")
    if (theme.keywords !== "colors appearance")
      return fail("keyword normalization")
    if (MenuModel.resolveRoute(model, "themes") !== "style.theme")
      return fail("alias route resolution")
    if (MenuModel.resolveRoute(model, "missing.route") !== "missing.route")
      return fail("valid unknown route passthrough")
    if (MenuModel.resolveRoute(model, "bad/route") !== "root")
      return fail("unsafe route fallback")

    const power = MenuModel.item(model, "setup.power")
    if (!power || power.provider !== "power-profiles"
        || !power.when || !power.checked)
      return fail("provider and guard metadata")
    const hiddenPower = MenuModel.children(model, "setup", ({ "$setup.power": false }), ({}))
    if (hiddenPower.length !== 0) return fail("visibility result")
    if (MenuModel.children(model, "setup", ({}), ({})).length !== 0)
      return fail("missing visibility result is not fail-closed")
    const checkedPower = MenuModel.children(model, "setup", ({ "$setup.power": true }), ({ "$setup.power": true }))
    if (checkedPower.length !== 1 || !checkedPower[0].checkedState)
      return fail("checked result")

    const malformed = MenuModel.parseMenuJsonc('{ "broken": [ }')
    if (malformed.ok || malformed.items.length !== 0 || malformed.error !== "invalid-jsonc")
      return fail("malformed source fail-closed")

    const empty = MenuModel.parseMenuJsonc("")
    if (!empty.ok || empty.items.length !== 0)
      return fail("empty optional source")

    const clearAction = MenuModel.parseMenuJsonc('{ "style.theme": { "action": "" } }')
    const cleared = MenuModel.mergeMenuSources(defaults.items, clearAction.items)
    if (MenuModel.item(cleared, "style.theme").kind !== "menu")
      return fail("explicit field clearing")

    console.log("menu model regression passed")
    Qt.exit(0)
  }
}
