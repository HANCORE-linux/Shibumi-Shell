pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "." as Shibumi

Item {
  id: root

  property var bar: null

  Shibumi.VisualTokens {
    id: tokens
    bar: root.bar
  }

  readonly property int contractVersion: 1
  readonly property string styleId: "shibumi"
  readonly property string displayName: "Shibumi"
  readonly property int sizeHorizontal: tokens.barHeight
  readonly property int sizeVertical: Commons.Style.bar.sizeVertical
  readonly property int exclusiveSizeHorizontal: tokens.exclusiveHeight
  readonly property int tooltipGap: Commons.Style.space(6)
  readonly property int colorTransitionDuration: tokens.colorDuration
  readonly property string fontFamily: tokens.fontFamily
  readonly property color foreground: tokens.ink
  readonly property color barForeground: tokens.ink
  readonly property color background: tokens.barBackground
  readonly property color urgent: tokens.seal
  readonly property var visualTokens: tokens
  readonly property Component barSurfaceComponent: barSurface
  readonly property Component tooltipSurfaceComponent: tooltipSurface

  visible: false
  width: 0
  height: 0

  Component {
    id: barSurface

    Shibumi.BarSurface { bar: root.bar }
  }

  Component {
    id: tooltipSurface

    Shibumi.TooltipSurface { bar: root.bar }
  }
}
