pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText

  readonly property var reactorOptions: [
    { value: 0, label: "Off" },
    { value: 1, label: "Stream" },
    { value: 5, label: "Stream 2" },
    { value: 2, label: "Surge" },
    { value: 6, label: "Surge 2" },
    { value: 3, label: "Bolt" },
    { value: 4, label: "Bolt 2" },
    { value: 7, label: "Reactor" },
    { value: 8, label: "Quotes" }
  ]
  readonly property bool ready: reactorRepeater.count
    === reactorOptions.length && slotRegionRepeater.count === 3

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(8)

  Text {
    text: "LAYOUT ENGINE"
    color: root.accent
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Bold
    font.letterSpacing: 1.8
  }

  Text {
    text: "layout"
    color: root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.space(24) * root.uiScale
    font.weight: Font.Bold
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    visible: root.controller.v2LayoutActive !== true

    SectionLabel { text: "SPLIT & MERGE" }

    Text {
      width: parent.width
      text: "Split islands and animated gaps belong to the Shibumi V1 shell."
      color: root.foreground
      opacity: 0.54
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }

    Row {
      width: parent.width
      spacing: Commons.Style.space(8)

      CompactSettingChoice {
        width: (parent.width - parent.spacing) / 2
        controller: root.controller
        label: "Split all"
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setAllSplits(true)
      }

      CompactSettingChoice {
        width: (parent.width - parent.spacing) / 2
        controller: root.controller
        label: "Merge all"
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setAllSplits(false)
      }
    }

    CompactSettingChoice {
      width: parent.width
      controller: root.controller
      label: "Restore V1 layout"
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      onClicked: root.controller.resetBarLayout()
    }
  }

  Column {
    width: parent.width
    visible: root.controller.v2LayoutActive === true
    spacing: Commons.Style.space(8)

    Rectangle {
      width: parent.width
      height: 1
      color: root.controller.dividerColor
    }

    SectionLabel { text: "V2 LAYOUT" }

    Text {
      width: parent.width
      text: "Full, Fit, Dock and Notch use slots and manual separators. "
        + "V1 split islands, merge and gap animations do not apply."
      color: root.foreground
      opacity: 0.54
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }

    CompactSettingChoice {
      width: parent.width
      controller: root.controller
      label: "Edit separators on bar"
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      onClicked: root.controller.beginBarEditing()
    }

    CompactSettingChoice {
      width: parent.width
      controller: root.controller
      label: "Restore V2 layout"
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      onClicked: root.controller.resetBarLayout()
    }

    Text {
      width: parent.width
      text: "Click a dot between widgets to add or remove a divider. Esc exits."
      color: root.foreground
      opacity: 0.54
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }

    Repeater {
      id: slotRegionRepeater
      model: [
        { id: "left", label: "Left", min: 10, max: 13 },
        { id: "center", label: "Center", min: 1, max: 4 },
        { id: "right", label: "Right", min: 7, max: 13 }
      ]

      delegate: Row {
        required property var modelData
        readonly property int slotCount:
          root.controller.v2LayoutSlots
          && Array.isArray(root.controller.v2LayoutSlots[modelData.id])
            ? root.controller.v2LayoutSlots[modelData.id].length : 0
        readonly property int emptyCount:
          root.controller.v2LayoutSlots
          && Array.isArray(root.controller.v2LayoutSlots[modelData.id])
            ? root.controller.v2LayoutSlots[modelData.id].filter(
              function(value) { return String(value || "") === "" }).length
            : 0
        width: parent.width
        spacing: Commons.Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - removeSlot.width - addSlot.width
            - parent.spacing * 2
          text: modelData.label + "  ·  " + parent.slotCount
            + " / " + modelData.max
          color: root.foreground
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        }

        CompactSettingChoice {
          id: removeSlot
          width: Commons.Style.space(74)
          controller: root.controller
          label: "Remove"
          enabled: parent.slotCount > parent.modelData.min
            && parent.emptyCount > 0
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          onClicked: root.controller.removeV2Slot(parent.modelData.id)
        }

        CompactSettingChoice {
          id: addSlot
          width: Commons.Style.space(58)
          controller: root.controller
          label: "Add"
          enabled: parent.slotCount < parent.modelData.max
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          onClicked: root.controller.addV2Slot(parent.modelData.id)
        }
      }
    }
  }

  Rectangle {
    visible: root.controller.v2LayoutActive !== true
    width: parent.width
    height: 1
    color: root.controller.dividerColor
  }

  SectionLabel {
    visible: root.controller.v2LayoutActive !== true
    text: "GAP ANIMATION"
  }

  Grid {
    visible: root.controller.v2LayoutActive !== true
    width: parent.width
    columns: 3
    columnSpacing: Commons.Style.space(4)
    rowSpacing: Commons.Style.space(6)

    Repeater {
      id: reactorRepeater
      model: root.reactorOptions

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.columnSpacing * 2) / 3
        controller: root.controller
        label: modelData.label
        selected: root.controller.reactorMode === modelData.value
        foreground: root.foreground
        accent: root.accent
        fontSize: Commons.Style.font.caption * root.uiScale
        horizontalPadding: Commons.Style.space(3)
        onClicked: root.controller.setReactorMode(modelData.value)
      }
    }
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.58
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Medium
    font.letterSpacing: 1
  }
}
