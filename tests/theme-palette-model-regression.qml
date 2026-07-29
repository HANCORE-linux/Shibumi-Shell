import QtQuick
import "../services/ThemePaletteModel.js" as ThemePaletteModel

QtObject {
  function fail(message) {
    console.error("theme-palette-model-regression:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    const complete = ThemePaletteModel.parse([
      'red = "#010101"',
      'green = "#020202"',
      'yellow = "#030303"',
      'blue = "#040404"',
      'magenta = "#050505"',
      'cyan = "#060606"',
      'bright_fg = "#070707"',
      'light_fg = "#171717"',
      'color1 = "#111111"',
      'green = "#112233"',
      'yellow = "#445566"',
      'color2 = "#778899"',
      'color3 = "#aabbcc"',
      'color4 = "#444444"',
      'color5 = "#555555"',
      'color6 = "#666666"',
      'color7 = "#777777"',
      'color8 = "#888888"'
    ].join("\n"))
    if (complete.color01 !== "#111111"
        || complete.color02 !== "#778899"
        || complete.color03 !== "#aabbcc"
        || complete.color04 !== "#444444"
        || complete.color05 !== "#555555"
        || complete.color06 !== "#666666"
        || complete.color07 !== "#777777"
        || complete.color08 !== "#888888")
      return fail("complete palette key precedence")

    const named = ThemePaletteModel.parse(
      "red = '#010203'\nblue = #040506\nlight_fg = '#070809'\n"
        + "bright_black = '#08090a'\ninvalid = command")
    if (named.color01 !== "#010203" || named.color04 !== "#040506"
        || named.color07 !== "#070809" || named.color08 !== "#08090a")
      return fail("named Quattro palette aliases")

    const malformed = ThemePaletteModel.parse(
      'color1 = "$(touch /tmp/unsafe)"\ncolor7 = "red"\ncolor8 = "black"')
    if (malformed.color01 !== "" || malformed.color07 !== ""
        || malformed.color08 !== "")
      return fail("malformed colors must fail closed")

    const oversized = ThemePaletteModel.parse(
      "ignored = 1\n".repeat(6000) + 'color7 = "#abcdef"')
    if (oversized.color07 !== "")
      return fail("oversized palette input must be bounded")

    if (ThemePaletteModel.selection("color06") !== "color06"
        || ThemePaletteModel.selection("color08") !== "color08"
        || ThemePaletteModel.selection("foreground") !== "foreground"
        || ThemePaletteModel.selection("red") !== "color01"
        || ThemePaletteModel.selection("accent") !== "color01"
        || ThemePaletteModel.selection("green") !== "color02"
        || ThemePaletteModel.selection("yellow") !== "color03"
        || ThemePaletteModel.selection("unsafe") !== "color01")
      return fail("selection normalization")

    console.log("theme palette model regression passed")
    Qt.exit(0)
  }
}
