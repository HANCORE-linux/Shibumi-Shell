import QtQuick
import "../core/ResponsiveLayout.js" as ResponsiveLayout

Item {
  visible: false

  function fail(message) {
    console.error("responsive-layout-regression:", message)
    Qt.exit(1)
  }

  function expectVisible(stage, visibleIds, hiddenIds) {
    for (var i = 0; i < visibleIds.length; i++) {
      if (!ResponsiveLayout.groupVisibleAtStage(visibleIds[i], stage))
        return false
    }
    for (var j = 0; j < hiddenIds.length; j++) {
      if (ResponsiveLayout.groupVisibleAtStage(hiddenIds[j], stage))
        return false
    }
    return true
  }

  Component.onCompleted: {
    if (!expectVisible(1, ["G1", "G4", "G8"], ["G7", "G9", "G10"])
        || !expectVisible(2, ["G1", "G8", "G11"],
          ["G4", "G5", "G7", "G9", "G10"])
        || !expectVisible(3, ["G1", "G2", "G6", "G8", "G11", "G14"],
          ["G3", "G4", "G5", "G7", "G9", "G10", "G12", "G13", "G15"])) {
      fail("V1 group priority")
      return
    }

    const widths = [1000, 850, 650, 500]
    var stage = ResponsiveLayout.nextNarrowStage(0, 900, widths)
    if (stage !== 1) { fail("normal to compact"); return }
    stage = ResponsiveLayout.nextNarrowStage(stage, 700, widths)
    if (stage !== 2) { fail("compact to portrait"); return }
    stage = ResponsiveLayout.nextNarrowStage(stage, 550, widths)
    if (stage !== 3) { fail("portrait to emergency"); return }
    stage = ResponsiveLayout.nextNarrowStage(stage, 699, widths)
    if (stage !== 2) { fail("emergency hysteresis release"); return }
    stage = ResponsiveLayout.nextNarrowStage(stage, 899, widths)
    if (stage !== 1) { fail("portrait hysteresis release"); return }
    stage = ResponsiveLayout.nextNarrowStage(stage, 1049, widths)
    if (stage !== 0) { fail("compact hysteresis release"); return }
    stage = ResponsiveLayout.nextNarrowStage(0, 1000, widths)
    if (stage !== 0) { fail("exact full-width fit"); return }
    stage = ResponsiveLayout.nextNarrowStage(0, 999, widths)
    if (stage !== 1) { fail("real full-width overflow"); return }
    stage = ResponsiveLayout.nextNarrowStage(stage, 1000, widths)
    if (stage !== 0) { fail("exact full-width recovery"); return }

    const compactCenter = ResponsiveLayout.centerAvailableWidth(
      true, 1920, 5, 4, 300, 400, 12, 100)
    if (compactCenter !== 1178) {
      fail("compact center budget follows the content-driven shell")
      return
    }
    const fullCenter = ResponsiveLayout.centerAvailableWidth(
      false, 1920, 5, 4, 300, 400, 12, 812)
    if (fullCenter !== 812) {
      fail("full center budget ignores measured geometry")
      return
    }

    console.log("responsive layout regression passed")
    Qt.exit(0)
  }
}
