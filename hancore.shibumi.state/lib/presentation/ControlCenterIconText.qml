import QtQuick

Text {
  id: root

  property real fill: 0
  property real iconWeight: 500
  renderType: Text.QtRendering
  font.family: "Material Symbols Sharp"
  font.hintingPreference: Font.PreferFullHinting
  font.variableAxes: ({
    "FILL": root.fill,
    "wght": root.iconWeight
  })
}
