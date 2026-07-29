import QtQuick
import "../hancore.shibumi.media/CavaThemeModel.js" as CavaThemeModel

QtObject {
  function fail(message) {
    console.error("cava-theme-model-regression:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    const kanso = CavaThemeModel.parse([
      "[color]",
      "gradient = 1",
      "gradient_count = 8",
      "gradient_color_1 = '#8ba4b0'",
      "gradient_color_2 = '#8a9a7b'",
      "gradient_color_3 = '#87a987'",
      "gradient_color_4 = '#c4b28a'",
      "gradient_color_5 = '#e6c384'",
      "gradient_color_6 = '#c4b28a'",
      "gradient_color_7 = '#c4746e'",
      "gradient_color_8 = '#e46876'"
    ].join("\n"))
    if (kanso.length !== 8 || kanso[0] !== "#8ba4b0"
        || kanso[7] !== "#e46876") return fail("eight-color gradient")

    const inferred = CavaThemeModel.parse([
      "gradient=true",
      "gradient_color_1='#010203'",
      "gradient_color_2='#040506'",
      "gradient_color_3='#070809'"
    ].join("\n"))
    if (inferred.join(",") !== "#010203,#040506,#070809")
      return fail("inferred gradient count")

    const solid = CavaThemeModel.parse(
      "gradient=0\nforeground='#112233'")
    if (solid.length !== 1 || solid[0] !== "#112233")
      return fail("solid foreground")

    const malformed = CavaThemeModel.parse([
      "gradient=1",
      "gradient_count=3",
      "gradient_color_1='#010203'",
      "gradient_color_2='$(touch /tmp/unsafe)'",
      "gradient_color_3='#070809'"
    ].join("\n"))
    if (malformed.length !== 0) return fail("malformed gradient must fail closed")

    const oversized = CavaThemeModel.parse(
      "ignored=1\n".repeat(6000) + "gradient=1\ngradient_color_1='#ffffff'")
    if (oversized.length !== 0) return fail("bounded input")

    console.log("cava theme model regression passed")
    Qt.exit(0)
  }
}
