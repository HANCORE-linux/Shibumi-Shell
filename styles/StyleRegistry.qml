import QtQml

QtObject {
  id: root

  property string requestedId: "shibumi"
  readonly property var availableIds: ["shibumi"]
  readonly property string resolvedId: hasStyle(requestedId)
    ? normalizeId(requestedId)
    : "shibumi"
  readonly property url source: sourceFor(resolvedId)
  readonly property bool fallbackUsed: normalizeId(requestedId) !== resolvedId

  function normalizeId(value) {
    return String(value || "").trim().toLowerCase()
  }

  function hasStyle(value) {
    return availableIds.indexOf(normalizeId(value)) !== -1
  }

  function displayName(value) {
    switch (normalizeId(value)) {
    case "shibumi": return "Shibumi"
    default: return ""
    }
  }

  function sourceFor(value) {
    switch (normalizeId(value)) {
    case "shibumi": return Qt.resolvedUrl("shibumi/Style.qml")
    default: return ""
    }
  }
}
