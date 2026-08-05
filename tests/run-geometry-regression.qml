import QtQuick
import "../core/RunGeometry.js" as RunGeometry

QtObject {
  function fail(message) {
    console.error("run-geometry-regression:", message)
    Qt.exit(1)
  }

  function same(actual, expected) {
    return JSON.stringify(actual) === JSON.stringify(expected)
  }

  Component.onCompleted: {
    const groups = [
      { index: 0, left: 0, right: 40 },
      { index: 1, left: 62, right: 102 },
      { index: 4, left: 108, right: 138 }
    ]
    const base = {
      width: 300,
      padding: 4,
      sections: [{
        x: 4,
        groups: groups,
        splits: [false, false, false, false, false, false]
      }],
      left: { x: 4, width: 138 },
      center: { x: 170, width: 20 },
      right: { x: 220, width: 76 },
      boundaries: [false, false]
    }

    const continuous = RunGeometry.compute(base)
    if (!same(continuous, [{ x: 0, width: 300 }]))
      fail("no-split run must remain continuous")

    const within = JSON.parse(JSON.stringify(base))
    within.sections[0].splits[0] = true
    const withinRuns = RunGeometry.compute(within)
    if (!same(withinRuns, [
      { x: 0, width: 48 },
      { x: 62, width: 238 }
    ])) fail("within-section cut geometry")

    const dormant = JSON.parse(JSON.stringify(base))
    dormant.sections[0].splits[1] = true
    if (!same(RunGeometry.compute(dormant), continuous))
      fail("split next to an absent slot must remain dormant")

    const visibleBoundary = JSON.parse(JSON.stringify(base))
    visibleBoundary.sections[0].splits[3] = true
    visibleBoundary.sections[0].groups[2].left = 124
    visibleBoundary.sections[0].groups[2].right = 154
    const visibleBoundaryRuns = RunGeometry.compute(visibleBoundary)
    if (!same(visibleBoundaryRuns, [
      { x: 0, width: 110 },
      { x: 124, width: 176 }
    ])) return fail("boundary immediately before the next visible slot must cut")

    const boundaries = JSON.parse(JSON.stringify(base))
    boundaries.boundaries = [true, true]
    const boundaryRuns = RunGeometry.compute(boundaries)
    if (!same(boundaryRuns, [
      { x: 0, width: 146 },
      { x: 166, width: 28 },
      { x: 216, width: 84 }
    ])) fail("boundary cut geometry")

    const absentCenter = JSON.parse(JSON.stringify(base))
    absentCenter.center = null
    absentCenter.boundaries = [true, true]
    const merged = RunGeometry.compute(absentCenter)
    if (!same(merged, [
      { x: 0, width: 146 },
      { x: 216, width: 84 }
    ])) fail("empty-center boundaries must merge")

    const emptyCenter = JSON.parse(JSON.stringify(base))
    emptyCenter.center = { x: 170, width: 0 }
    emptyCenter.boundaries = [true, false]
    const singleEmptyCenter = RunGeometry.compute(emptyCenter)
    if (!same(singleEmptyCenter, [
      { x: 0, width: 146 },
      { x: 166, width: 134 }
    ])) fail("single boundary must retain the empty center anchor")

    const clipped = RunGeometry.compute({
      width: 100,
      sections: [],
      left: { x: 70, width: 20 },
      center: { x: 120, width: 20 },
      boundaries: [true, false]
    })
    if (!same(clipped, [{ x: 0, width: 94 }]))
      fail("out-of-range cuts must clip to the run frame")

    if (!same(RunGeometry.compute(null), [])
        || !same(RunGeometry.compute({ width: -1 }), []))
      fail("malformed geometry must fail closed")

    console.log("run geometry regression passed")
    Qt.exit(0)
  }
}
