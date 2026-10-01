import QtQuick
import QtQuick.Window

// Paint coordinates only: never change the owning slot, advance or input box.
QtObject {
  id: root

  required property Item target
  // Metrics only, never a painted font/texture scale. Small-size integer font
  // bounds can include a blank row; retain outline precision before snapping.
  readonly property int metricScale: 64
  property Item axisItem: {
    // Embedded native widgets can retain a taller line box than their host.
    // Prefer the owning module slot's axis over that nested line box.
    let owner = target
    for (let item = target.parent; item; item = item.parent) {
      if (item.moduleName !== undefined && item.bar !== undefined) owner = item
    }
    return owner
  }
  readonly property bool enabled: !axisItem || axisItem.bar === undefined
    || !axisItem.bar || !axisItem.bar.vertical
  readonly property real dpr: target.Window.window
    ? target.Window.window.devicePixelRatio : 1
  readonly property point origin: {
    for (let item = target.parent; item; item = item.parent) {
      void(item.x); void(item.y); void(item.width); void(item.height)
      void(item.scale); void(item.rotation)
      if (item.inkOffsetX !== undefined) void(item.inkOffsetX)
      if (item.inkOffsetY !== undefined) void(item.inkOffsetY)
    }
    return target.parent
      ? target.parent.mapToItem(null, target.x, target.y)
      : Qt.point(target.x, target.y)
  }
  readonly property real centerY: {
    void(origin)
    if (!axisItem || axisItem === target || !target.parent) return target.height / 2
    const tokens = axisItem.bar ? axisItem.bar.visualTokens : null
    const pill = tokens && tokens.shellStyle === "shibumi"
    const height = pill ? Math.min(axisItem.height, tokens.pillHeight) : axisItem.height
    const inset = (axisItem.height - height) / 2
    const top = axisItem.mapToItem(null, 0, inset).y * dpr
    const bottom = axisItem.mapToItem(null, 0, inset + height).y * dpr
    // Antialiased pills cover their edge pixels; the bar is clipped to its
    // physical surface. Align to that raster span, not a fractional line box.
    const first = pill ? Math.floor(top + 1e-7) : Math.round(top)
    const end = pill ? Math.ceil(bottom - 1e-7) : Math.round(bottom)
    return target.parent.mapFromItem(null, 0, (first + end) / (2 * dpr)).y - target.y
  }

  function caption(text) {
    const capitals = String(text || "").match(/[A-Z0-9]/g)
    return capitals ? capitals.join("") : "H0"
  }

  function baselineFor(bounds, scale) {
    return snapY(centerY - (bounds.y + bounds.height / 2) / (scale || metricScale))
  }

  function textTop(baseline, offset) {
    // Snap the Text origin too. At half-pixel ascents the native scene graph
    // otherwise rounds origin and ascent separately, adding a physical row.
    return baseline - Math.round(offset * dpr) / dpr
  }

  function rasterExtent(value) {
    return Math.round(value * dpr) / dpr
  }

  function rectangleY(height) {
    return snapY(centerY - height / 2)
  }

  function snapX(value) {
    return Math.round((origin.x + value) * dpr) / dpr - origin.x
  }

  function snapY(value) {
    return Math.round((origin.y + value) * dpr) / dpr - origin.y
  }
}
