pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "SearchEngine.js" as SearchEngine

Item {
  id: root

  required property var controller
  property var entries: []
  property alias text: searchInput.text
  property string placeholder: "Search…"
  property string hint: ""
  property int suggestionLimit: 3
  property string popupStyle: "global"
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool suggestionsSuppressed: true
  property int activeSuggestionIndex: -1
  readonly property var suggestions:
    !suggestionsSuppressed
      ? SearchEngine.completions(entries, searchInput.text, suggestionLimit)
      : []
  readonly property bool suggestionsVisible: suggestions.length > 0
  readonly property bool catalogPopup: popupStyle === "catalog"
  readonly property real suggestionPopupHeight: suggestionsVisible
    ? suggestions.length * Commons.Style.space(34) + 2 : 0
  readonly property real reservedPopupHeight: suggestionsVisible
    ? Commons.Style.space(4) + suggestionPopupHeight : 0
  readonly property var activeSuggestion: suggestions.length > 0
    ? suggestions[activeSuggestionIndex >= 0 ? activeSuggestionIndex : 0]
    : null
  readonly property string ghostText:
    SearchEngine.ghostText(searchInput.text, activeSuggestion)
  readonly property bool inputActiveFocus: searchInput.activeFocus
  signal edited(string value)
  signal completionAccepted(var completion)

  z: suggestionsVisible ? 80 : 0
  implicitHeight: Commons.Style.space(34)

  function forceInputFocus() {
    suggestionsSuppressed = false
    searchInput.forceActiveFocus()
  }

  function clear() {
    searchInput.text = ""
    activeSuggestionIndex = -1
    suggestionsSuppressed = true
  }

  function blur() {
    activeSuggestionIndex = -1
    suggestionsSuppressed = true
    searchInput.focus = false
    return true
  }

  function moveSuggestion(offset) {
    if (suggestions.length === 0) return false
    const base = activeSuggestionIndex >= 0 ? activeSuggestionIndex : 0
    activeSuggestionIndex = (
      base + Number(offset || 0) + suggestions.length) % suggestions.length
    return true
  }

  function acceptSuggestion(index) {
    if (suggestions.length === 0) return false
    const requested = Number(index)
    const selected = suggestions[
      requested >= 0 && requested < suggestions.length ? requested : 0]
    const target = SearchEngine.completionTarget(selected)
    if (target === "") return false
    searchInput.text = target
    searchInput.cursorPosition = searchInput.length
    activeSuggestionIndex = -1
    suggestionsSuppressed = true
    completionAccepted(selected)
    return true
  }

  function handleEscape() {
    if (suggestionsVisible) {
      activeSuggestionIndex = -1
      suggestionsSuppressed = true
      return "suggestions"
    }
    searchInput.text = ""
    blur()
    edited("")
    return "clear"
  }

  IconText {
    id: searchGlyph
    anchors.left: parent.left
    anchors.leftMargin: Commons.Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: "search"
    color: root.foreground
    opacity: searchInput.activeFocus ? 0.82 : 0.42
    font.pixelSize: Commons.Style.space(17) * root.uiScale
    fill: 0
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.IBeamCursor
    onClicked: searchInput.forceActiveFocus()
  }

  Text {
    anchors.left: searchInput.left
    anchors.right: searchInput.right
    anchors.verticalCenter: parent.verticalCenter
    visible: searchInput.text === ""
    text: root.placeholder
    color: root.foreground
    opacity: 0.34
    elide: Text.ElideRight
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
  }

  Text {
    anchors.fill: searchInput
    verticalAlignment: Text.AlignVCenter
    visible: root.ghostText !== "" && searchInput.text !== ""
    text: root.ghostText
    color: root.foreground
    opacity: 0.30
    elide: Text.ElideRight
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
  }

  TextInput {
    id: searchInput
    anchors.left: parent.left
    anchors.right: trailingAction.left
    anchors.leftMargin: Commons.Style.space(36)
    anchors.rightMargin: Commons.Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    color: root.foreground
    selectionColor: Commons.Util.alpha(root.accent, 0.34)
    selectedTextColor: root.foreground
    selectByMouse: true
    clip: true
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.bodySmall * root.uiScale

    onTextEdited: {
      root.suggestionsSuppressed = false
      root.activeSuggestionIndex = -1
      root.edited(text)
    }
    onActiveFocusChanged: {
      root.activeSuggestionIndex = -1
      root.suggestionsSuppressed = !activeFocus
    }

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.handleEscape()
        event.accepted = true
        return
      }
      if (root.suggestionsVisible
          && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
        root.moveSuggestion(event.key === Qt.Key_Down ? 1 : -1)
        event.accepted = true
        return
      }
      const accepts = event.key === Qt.Key_Tab
        || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || (event.key === Qt.Key_Right
          && searchInput.cursorPosition === searchInput.length)
      if (root.suggestionsVisible && accepts) {
        root.acceptSuggestion(root.activeSuggestionIndex)
        event.accepted = true
      }
    }
  }

  Item {
    id: trailingAction
    anchors.right: parent.right
    anchors.rightMargin: Commons.Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(clearAction.width, hintLabel.width)
    height: parent.height

    Text {
      id: hintLabel
      anchors.centerIn: parent
      visible: searchInput.text === "" && root.hint !== ""
      text: root.hint
      color: root.foreground
      opacity: 0.28
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
      font.letterSpacing: 0.8
    }

    IconText {
      id: clearAction
      anchors.centerIn: parent
      visible: searchInput.text !== ""
      text: "close"
      color: root.foreground
      opacity: clearPointer.containsMouse ? 0.88 : 0.42
      font.pixelSize: Commons.Style.space(16) * root.uiScale
      fill: 0

      MouseArea {
        id: clearPointer
        anchors.fill: parent
        anchors.margins: -Commons.Style.space(7)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.clear()
          searchInput.forceActiveFocus()
          root.edited("")
        }
      }
    }
  }

  Rectangle {
    id: suggestionPopup
    visible: root.suggestionsVisible
    anchors.top: parent.bottom
    anchors.topMargin: Commons.Style.space(4)
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.suggestionPopupHeight
    z: 90
    radius: root.controller.controlRadius
    color: Qt.rgba(
      root.controller.marketPanel.r,
      root.controller.marketPanel.g,
      root.controller.marketPanel.b,
      1)
    border.width: 1
    border.color: root.controller.controlBorderColor
    clip: true

    Column {
      anchors.fill: parent
      anchors.margins: 1

      Repeater {
        id: suggestionRepeater
        model: root.suggestions

        delegate: Rectangle {
          id: suggestionRow
          required property var modelData
          required property int index
          width: parent.width
          height: Commons.Style.space(34)
          color: suggestionRow.index === root.activeSuggestionIndex
            || suggestionPointer.containsMouse
            ? root.controller.controlHoverFillColor : "transparent"

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            visible: suggestionRow.index < suggestionRepeater.count - 1
            color: root.controller.dividerColor
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Commons.Style.space(11)
            anchors.rightMargin: Commons.Style.space(9)
            spacing: Commons.Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - suggestionMeta.implicitWidth
                - parent.spacing
              text: suggestionRow.modelData.label
              color: suggestionRow.index === root.activeSuggestionIndex
                || suggestionPointer.containsMouse
                ? root.accent : root.foreground
              elide: Text.ElideRight
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
              font.weight: Font.Medium
            }

            Text {
              id: suggestionMeta
              anchors.verticalCenter: parent.verticalCenter
              text: String(suggestionRow.modelData.type || "").toUpperCase()
                + (suggestionRow.modelData.count > 1
                  ? " · " + suggestionRow.modelData.count : "")
                + " · TAB"
              color: root.foreground
              opacity: 0.46
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.caption * root.uiScale
              font.weight: Font.DemiBold
              font.letterSpacing: 0.35
            }
          }

          MouseArea {
            id: suggestionPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.activeSuggestionIndex = suggestionRow.index
            onClicked: root.acceptSuggestion(suggestionRow.index)
          }
        }
      }
    }
  }
}
