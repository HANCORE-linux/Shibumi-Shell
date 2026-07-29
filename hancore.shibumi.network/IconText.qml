import QtQuick

Text {
  id: root

  property real fill: 0
  renderType: Text.QtRendering
  font.family: "Material Symbols Rounded"
  font.variableAxes: ({ "FILL": root.fill })
}
