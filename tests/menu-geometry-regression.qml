import QtQuick
import "../menu/MenuGeometry.js" as MenuGeometry

QtObject {
  function fail(message) {
    throw new Error("menu-geometry-regression: " + message)
  }

  Component.onCompleted: {
    const width = 2560
    const height = 1440
    const cardWidth = 260
    const cardHeight = 500
    const gap = 5
    const barSize = 30

    if (MenuGeometry.cardX("top", width, cardWidth, gap, barSize, 248) !== 248
        || MenuGeometry.cardY("top", height, cardHeight, gap, barSize) !== 35)
      return fail("top position")
    if (MenuGeometry.cardX("bottom", width, cardWidth, gap, barSize, 248) !== 248
        || MenuGeometry.cardY("bottom", height, cardHeight, gap, barSize) !== 905)
      return fail("bottom position")
    if (MenuGeometry.cardX("left", width, cardWidth, gap, barSize, 248) !== 35
        || MenuGeometry.cardY("left", height, cardHeight, gap, barSize) !== 5)
      return fail("left position")
    if (MenuGeometry.cardX("right", width, cardWidth, gap, barSize, 248) !== 2265
        || MenuGeometry.cardY("right", height, cardHeight, gap, barSize) !== 5)
      return fail("right position")
    if (MenuGeometry.cardX("top", 240, 230, gap, barSize, 248) !== 5
        || MenuGeometry.cardY("bottom", 320, 300, gap, barSize) !== 5)
      return fail("small-surface clamping")

    console.log("menu geometry regression passed")
    Qt.exit(0)
  }
}
