import QtQuick
import "../menu/GuardModel.js" as GuardModel
import "../menu/MenuModel.js" as MenuModel
import "../menu/ProcessResult.js" as ProcessResult
import "../menu/ProviderModel.js" as ProviderModel

QtObject {
  function fail(message) {
    console.error("menu-runtime-model-regression: " + message)
    const codes = {
      "guards do not initialize fail-closed": 11,
      "guard script generation or shell quoting": 12,
      "guard result validation": 13,
      "provider allowlist": 14,
      "provider timeout contract": 15,
      "font provider rows or current marker": 16,
      "provider action shell quoting": 17,
      "provider duplicate id handling": 18,
      "provider control character filtering": 19,
      "power profile provider rows": 20,
      "process result classification": 21
    }
    Qt.exit(codes[message] || 1)
  }

  Component.onCompleted: {
    const parsed = MenuModel.parseMenuJsonc(`{
      "root": { "label": "Go" },
      "safe.visible": { "parent": "root", "label": "Visible", "when": "true", "checked": "true" },
      "safe.hidden": { "parent": "root", "label": "Hidden", "when": "false" },
      "safe.quote": { "parent": "root", "label": "Quote", "when": "printf '%s' \\\"a'b\\\" >/dev/null" }
    }`)
    const model = MenuModel.mergeMenuSources(parsed.items, [])
    const initial = GuardModel.initialState(model)
    if (initial.guardCount !== 4
        || initial.whenResults["$safe.visible"] !== false
        || initial.checkedResults["$safe.visible"] !== false)
      return fail("guards do not initialize fail-closed")

    const script = GuardModel.scriptFor(model)
    if (!script.includes("safe.visible:w:1") || !script.includes("'\\''"))
      return fail("guard script generation or shell quoting")

    const results = GuardModel.parseOutput(model,
      "safe.visible:w:1\nsafe.visible:c:1\nsafe.hidden:w:0\n"
      + "forged.item:w:1\nsafe.visible:x:1\nsafe.quote:w:1\nmalformed\n")
    if (results.whenResults["$safe.visible"] !== true
        || results.checkedResults["$safe.visible"] !== true
        || results.whenResults["$safe.hidden"] !== false
        || results.whenResults["$safe.quote"] !== true
        || results.whenResults["$forged.item"] !== undefined)
      return fail("guard result validation")

    if (!ProcessResult.succeeded(0, 0)
        || ProcessResult.succeeded(1, 0)
        || ProcessResult.succeeded(0, 1)
        || ProcessResult.succeeded(143, 1))
      return fail("process result classification")

    if (ProviderModel.commandFor("unreviewed-provider").length !== 0)
      return fail("provider allowlist")
    const fontCommand = ProviderModel.commandFor("fonts")
    const powerCommand = ProviderModel.commandFor("power-profiles")
    if (fontCommand[0] !== "timeout" || powerCommand[0] !== "timeout"
        || fontCommand[2] !== "5s" || powerCommand[2] !== "5s")
      return fail("provider timeout contract")

    const fonts = ProviderModel.rows("fonts", "style.font",
      "JetBrains Mono\tJetBrains Mono\tJetBrains Mono\n"
      + "O'Brien Font\tO'Brien Font\tJetBrains Mono\n"
      + "Duplicate\tSame Value\tJetBrains Mono\n"
      + "Duplicate 2\tSame Value\tJetBrains Mono\n"
      + "Bad" + String.fromCharCode(1) + "Label\tSafe\tJetBrains Mono\n")
    if (fonts.length !== 5 || fonts[0].raw.icon !== "✓")
      return fail("font provider rows or current marker")
    if (fonts[1].raw.action !== "omarchy-font-set 'O'\\''Brien Font'")
      return fail("provider action shell quoting")
    if (fonts[2].id === fonts[3].id || !fonts[3].id.endsWith("-2"))
      return fail("provider duplicate id handling")
    if (fonts[4].raw.label.indexOf(String.fromCharCode(1)) >= 0)
      return fail("provider control character filtering")

    const powers = ProviderModel.rows("power-profiles", "setup.power",
      "balanced\tbalanced\tperformance\nperformance\tperformance\tperformance\n")
    if (powers.length !== 2 || powers[1].raw.icon !== "✓"
        || powers[0].raw.action !== "powerprofilesctl set 'balanced'")
      return fail("power profile provider rows")

    console.log("menu runtime model regression passed")
    Qt.exit(0)
  }
}
