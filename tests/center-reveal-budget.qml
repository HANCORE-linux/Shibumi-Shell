import QtQuick
QtObject {
  required property var workspace
  required property var center
  property var shown: ({})
  function hide() {
    shown = ({budget: center.availableWidth, stage: center.stage})
    workspace.visible = false
  }
  function checkReveal() {
    const hiddenBudget = center.availableWidth
    workspace.visible = true
    center.updateStage()
    const budget = typeof center.responsiveWidthProvider === "function" ? center.responsiveWidthProvider() : center.availableWidth
    const passed = budget < hiddenBudget && center.stage === shown.stage
    console[passed ? "log" : "error"]("center reveal budget " + (passed ? "passed" : "failed"), hiddenBudget, shown.budget, budget, center.stage)
    return passed
  }
}
