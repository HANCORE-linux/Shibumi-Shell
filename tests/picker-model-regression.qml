import QtQuick
import "../services/PickerModel.js" as PickerModel

QtObject {
  function fail(message) {
    console.error("picker-model-regression:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    const rows = [
      "/a.png\t/cache/a.jpg\tAlpha\t/themes/a\t1",
      "/b.png\t/cache/b.jpg\tBeta\t/themes/b\t0",
      "/a.png\t/cache/duplicate.jpg\tDuplicate\t/themes/a\t1"
    ].join("\n")
    const entries = PickerModel.parseRows(rows)
    if (entries.length !== 2 || entries[0].label !== "Alpha"
        || !entries[0].thumbnailReady || entries[1].thumbnailReady)
      return fail("row parsing/de-duplication")
    const filtered = PickerModel.filtered(entries, "bet")
    if (filtered.length !== 1 || filtered[0].sourcePath !== "/b.png")
      return fail("filtering")
    if (PickerModel.indexForSource(entries, "/b.png") !== 1
        || PickerModel.clampIndex(8, 2) !== 1
        || PickerModel.clampIndex(-2, 2) !== 0)
      return fail("selection helpers")
    const ready = PickerModel.replaceThumbnailReady(entries, "/cache/b.jpg")
    if (!ready[1].thumbnailReady || entries[1].thumbnailReady)
      return fail("immutable thumbnail update")
    console.log("picker model regression passed")
    Qt.exit(0)
  }
}
