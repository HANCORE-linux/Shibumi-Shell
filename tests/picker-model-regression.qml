import QtQuick
import QtTest
import "../services/PickerModel.js" as PickerModel

TestCase {
  name: "PickerModel"

  function test_modelContract() {
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
    if (PickerModel.mediaLabel(
          "/Pictures/screenshot-2026-07-30_12-12-08.png")
        !== "2026-07-30  12:12"
        || PickerModel.mediaLabel(
          "/Videos/screenrecording-2026-07-30-12-14-16.mp4")
        !== "2026-07-30  12:14"
        || PickerModel.mediaLabel("/Videos/custom capture.webm")
        !== "custom capture")
      return fail("V1 media label formatting")
    const equivalent = PickerModel.parseRows(rows)
    if (!PickerModel.entriesEqual(entries, equivalent))
      return fail("equivalent entry lists")
    equivalent[1].thumbnailReady = true
    if (PickerModel.entriesEqual(entries, equivalent))
      return fail("thumbnail readiness difference")
    const ready = PickerModel.replaceThumbnailReady(entries, "/cache/b.jpg")
    if (!ready[1].thumbnailReady || entries[1].thumbnailReady)
      return fail("immutable thumbnail update")
    if (PickerModel.replaceThumbnailReady(ready, "/cache/b.jpg") !== ready
        || PickerModel.replaceThumbnailReady(ready, "/cache/missing.jpg") !== ready)
      return fail("no-op thumbnail update changed array identity")
  }
}
