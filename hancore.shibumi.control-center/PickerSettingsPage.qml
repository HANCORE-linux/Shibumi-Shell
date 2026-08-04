pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool motionActive: false
  readonly property bool ready: imagePickerRepeater.count === 3
    && mediaPickerRepeater.count === 3
  readonly property int previewCardCount:
    imagePickerRepeater.count + mediaPickerRepeater.count

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "pickers"
    eyebrow: "MEDIA ROUTING"
    title: "Pickers"
    description: "Choose the visual browser used for images and captured media."
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  Separator {}
  SectionLabel { text: "THEMES & WALLPAPERS" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(7)

    Repeater {
      id: imagePickerRepeater
      model: [
        { value: "omarchy", label: "Omarchy · Default" },
        { value: "tanzaku", label: "Tanzaku" },
        { value: "hearthstone", label: "Hearthstone" }
      ]

      delegate: PickerPreviewCard {
        required property var modelData
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: modelData.label
        styleValue: modelData.value
        selectedValue: root.controller.imagePickerStyle
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onChosen: function(styleValue) {
          root.controller.setImagePickerStyle(styleValue)
        }
      }
    }
  }

  SectionLabel { text: "SCREENSHOTS & VIDEOS" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(7)

    Repeater {
      id: mediaPickerRepeater
      model: [
        { value: "carousel", label: "Carousel · Default" },
        { value: "tanzaku", label: "Tanzaku" },
        { value: "hearthstone", label: "Hearthstone" }
      ]

      delegate: PickerPreviewCard {
        required property var modelData
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: modelData.label
        styleValue: modelData.value
        selectedValue: root.controller.mediaPickerStyle
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onChosen: function(styleValue) {
          root.controller.setMediaPickerStyle(styleValue)
        }
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

  component Separator: Rectangle {
    width: root.width
    height: 1
    color: root.controller.dividerColor
  }
}
