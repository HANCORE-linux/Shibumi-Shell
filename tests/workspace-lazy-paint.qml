import QtQuick
QtObject {
  required property var workspace
  function check() {
    const pending = [workspace], seen = []
    let inks = 0
    while (pending.length) {
      const object = pending.pop()
      if (!object || seen.indexOf(object) >= 0) continue
      seen.push(object)
      if (object.target && typeof object.snapX === "function") inks++
      for (const child of Array.from(object.children || [])) pending.push(child)
      for (const child of Array.from(object.data || [])) pending.push(child)
    }
    const expected = ({default:2,numbers:2,magic:1,kanji:1,rings:1,aurora:1,pacman:0})[workspace.renderStyle] * workspace.renderedWorkspaceCount
    const passed = workspace.renderedWorkspaceCount > 0 && inks === expected
    console[passed ? "log" : "error"]("#73 lazy paint regression " + (passed ? "passed" : "failed"), inks, expected)
    return passed
  }
}
