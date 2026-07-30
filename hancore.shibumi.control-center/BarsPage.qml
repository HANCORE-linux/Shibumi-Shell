pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool motionActive: false
  readonly property bool ready: true
  readonly property string activeShell: String(
    controller.activeShell || "shibumi")
  readonly property string selectedShell: root.activeShell === "shibumi"
    ? "omarchy" : "shibumi"
  readonly property bool switching: controller.switchPhase === "queued"
    || controller.switchPhase === "snapshot"
    || controller.switchPhase === "apply"
    || controller.switchPhase === "verify"

  implicitHeight: Commons.Style.space(644)

  function shellTitle(id) {
    return id === "shibumi" ? "SHIBUMI" : "OMARCHY"
  }

  function requestSelected() {
    if (!switching) controller.switchShell(selectedShell)
  }

  function switchPhaseRank() {
    if (controller.switchPhase === "snapshot") return 1
    if (controller.switchPhase === "apply") return 2
    if (controller.switchPhase === "verify") return 3
    return 0
  }

  Keys.onLeftPressed: function(event) {
    event.accepted = true
  }
  Keys.onRightPressed: function(event) {
    event.accepted = true
  }
  Keys.onReturnPressed: function(event) {
    requestSelected()
    event.accepted = true
  }
  Keys.onEnterPressed: function(event) {
    requestSelected()
    event.accepted = true
  }

  Column {
    anchors.fill: parent
    spacing: Commons.Style.space(8)

    PageHeaderHero {
      controller: root.controller
      active: root.motionActive
      pageKey: "bars"
      eyebrow: "SHELL CONTINUITY"
      title: "Bars"
      description: "Switch through a guarded snapshot, apply and verify route."
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
    }

    Row {
      width: parent.width
      height: Commons.Style.space(32)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "SAFE HANDOFF"
        color: root.foreground
        opacity: 0.52
        font.family: root.controller.bar
          ? root.controller.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1.6
      }

      Item { width: parent.width - parent.children[0].width
          - switchAction.width; height: 1 }

      Rectangle {
        id: switchAction
        width: Commons.Style.space(154)
        height: Commons.Style.space(28)
        color: switchPointer.containsMouse
          ? root.controller.controlHoverFillColor : "transparent"
        border.color: root.switching
          ? Commons.Util.alpha(root.foreground, 0.18)
          : root.controller.dividerColor
        border.width: 1
        radius: root.controller.controlRadius

        Text {
          anchors.centerIn: parent
          text: root.switching ? "Switching …"
            : "Switch to " + (root.selectedShell === "shibumi"
              ? "Shibumi" : "Omarchy")
          color: root.switching ? root.foreground : root.accent
          opacity: root.switching ? 0.46 : 1
          font.family: Commons.Style.font.menuFamily
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        }

        MouseArea {
          id: switchPointer
          anchors.fill: parent
          enabled: !root.switching
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.requestSelected()
        }
      }
    }

    Item {
      id: canvas
      width: parent.width
      height: Commons.Style.space(292)

      Rectangle {
        id: continuityLine
        x: leftProfile.x + leftProfile.width - Commons.Style.space(2)
        y: Commons.Style.space(144)
        width: rightProfile.x - x + Commons.Style.space(2)
        height: 1
        color: root.controller.dividerColor

        Repeater {
          model: [0, 1]

          Rectangle {
            required property int index
            x: index === 0 ? -width / 2 : continuityLine.width - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(7)
            height: width
            radius: width / 2
            color: root.accent
            opacity: 0.82
          }
        }

        Rectangle {
          width: root.activeShell === "shibumi"
            ? parent.width * 0.08 : parent.width
          height: 1
          color: root.accent

          Behavior on width {
            NumberAnimation {
              duration: 360
              easing.type: Easing.OutCubic
            }
          }
        }
      }

      Repeater {
        model: [
          { label: "SNAPSHOT", ratio: 0.25 },
          { label: "APPLY", ratio: 0.50 },
          { label: "VERIFY", ratio: 0.75 }
        ]

        delegate: Item {
          required property var modelData
          required property int index
          readonly property bool current:
            root.switching && root.switchPhaseRank() === index + 1
          readonly property bool reached: root.switching
            ? root.switchPhaseRank() > index + 1
            : root.activeShell === "omarchy"
          x: continuityLine.x + continuityLine.width * modelData.ratio
            - width / 2
          y: continuityLine.y - Commons.Style.space(5)
          width: Commons.Style.space(18)
          height: Commons.Style.space(34)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Commons.Style.space(9)
            height: width
            radius: width / 2
            color: parent.current
              ? root.accent
              : parent.reached
                ? Commons.Util.alpha(root.accent, 0.24)
                : root.controller.controlFillColor
            border.width: 1
            border.color: parent.current || parent.reached
              ? root.accent : root.controller.dividerColor
          }

          Text {
            anchors.top: parent.top
            anchors.topMargin: Commons.Style.space(13)
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.modelData.label
            color: parent.current ? root.accent : root.foreground
            opacity: parent.current ? 1 : parent.reached ? 0.7 : 0.38
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
            font.letterSpacing: 0.7
          }
        }
      }

      ShellProfile {
        id: leftProfile
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        shellId: "shibumi"
        active: root.activeShell === shellId
        title: "SHIBUMI"
        subtitle: active ? "ACTIVE" : "AVAILABLE"
        previewCount: Number(root.controller.shibumiPluginCount || 0)
      }

      ShellProfile {
        id: rightProfile
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        shellId: "omarchy"
        active: root.activeShell === shellId
        title: "OMARCHY"
        subtitle: active ? "ACTIVE" : "AVAILABLE"
        previewCount: Math.max(0,
          Number(root.controller.nativePluginCount || 0))
      }
    }

    Rectangle {
      width: parent.width
      height: Commons.Style.space(92)
      color: "transparent"
      border.color: root.controller.dividerColor
      border.width: 1
      radius: root.controller.controlRadius

      Row {
        anchors.fill: parent
        anchors.margins: Commons.Style.space(14)

        LedgerValue {
          width: parent.width / 3
          height: parent.height
          glyph: "person"
          label: "USER EXTRAS"
          value: root.controller.preservedExtraCount + " PRESERVED"
        }

        LedgerValue {
          width: parent.width / 3
          height: parent.height
          glyph: "tune"
          label: "SETTINGS"
          value: "RETAINED"
          divided: true
        }

        LedgerValue {
          width: parent.width / 3
          height: parent.height
          glyph: "shield"
          label: "ROLLBACK"
          value: root.controller.switchPhase === "error"
            ? "RECOVERY READY" : "ARMED"
          divided: true
        }
      }
    }

  }

  component ShellProfile: Rectangle {
    id: profile
    required property string shellId
    required property bool active
    required property string title
    required property string subtitle
    required property int previewCount
    width: Commons.Style.space(214)
    height: Commons.Style.space(190)
    color: profilePointer.containsMouse
      ? root.controller.controlHoverFillColor : "transparent"
    border.color: active ? root.accent : root.controller.dividerColor
    border.width: 1
    radius: root.controller.controlRadius

    Column {
      anchors.fill: parent
      anchors.margins: Commons.Style.space(18)
      spacing: Commons.Style.space(9)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: profile.title
        color: root.foreground
        font.family: root.controller.bar
          ? root.controller.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.heading * root.uiScale
        font.letterSpacing: 2.5
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: profile.subtitle
        color: profile.active ? root.accent : root.foreground
        opacity: profile.active ? 1 : 0.44
        font.family: root.controller.bar
          ? root.controller.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1.5
      }

      Item { width: 1; height: Commons.Style.space(7) }

      Rectangle {
        width: parent.width
        height: Commons.Style.space(34)
        color: "transparent"
        border.color: profile.active
          ? Commons.Util.alpha(root.accent, 0.72)
          : root.controller.dividerColor
        border.width: 1
        radius: root.controller.controlRadius

        Row {
          anchors.fill: parent
          anchors.margins: Commons.Style.space(4)
          spacing: Commons.Style.space(4)

          Repeater {
            model: [
              { glyph: "apps", label: "MENU", weight: 0.27 },
              { glyph: "grid_view", label: "SPACES", weight: 0.38 },
              { glyph: "schedule", label: "TIME", weight: 0.35 }
            ]

            Rectangle {
              required property var modelData
              width: (parent.width - parent.spacing * 2)
                * modelData.weight
              height: parent.height
              radius: Math.max(1, root.controller.controlRadius - 1)
              color: profile.active
                ? Commons.Util.alpha(root.accent, 0.08)
                : root.controller.controlFillColor
              border.color: profile.active
                ? Commons.Util.alpha(root.accent, 0.28)
                : root.controller.dividerColor
              border.width: 1

              Row {
                anchors.centerIn: parent
                spacing: Commons.Style.space(2)

                IconText {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.glyph
                  color: profile.active ? root.accent : root.foreground
                  opacity: profile.active ? 0.9 : 0.48
                  font.pixelSize: Commons.Style.space(9) * root.uiScale
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: root.foreground
                  opacity: profile.active ? 0.72 : 0.4
                  font.family: Commons.Style.font.menuFamily
                  font.pixelSize: Commons.Style.space(6) * root.uiScale
                  font.letterSpacing: 0.5
                }
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: profile.previewCount + " PLUGINS"
        color: root.foreground
        opacity: 0.42
        font.family: root.controller.bar
          ? root.controller.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1.1
      }
    }

    MouseArea {
      id: profilePointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: profile.active ? Qt.ArrowCursor : Qt.PointingHandCursor
      onClicked: {
        if (!profile.active && !root.switching)
          root.controller.switchShell(profile.shellId)
      }
    }
  }

  component LedgerValue: Item {
    id: ledger
    required property string glyph
    required property string label
    required property string value
    property bool divided: false

    Rectangle {
      visible: ledger.divided
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 1
      height: parent.height * 0.72
      color: root.controller.dividerColor
    }

    Row {
      anchors.centerIn: parent
      spacing: Commons.Style.space(12)

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: ledger.glyph
        color: root.foreground
        opacity: 0.82
        font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
        fill: 0
      }

      Column {
        spacing: Commons.Style.space(3)

        Text {
          text: ledger.label
          color: root.foreground
          font.family: root.controller.bar
            ? root.controller.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
          font.letterSpacing: 1.2
        }

        Text {
          text: ledger.value
          color: root.foreground
          opacity: 0.46
          font.family: root.controller.bar
            ? root.controller.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.letterSpacing: 1.1
        }
      }
    }
  }

  component CommandHint: Row {
    id: hint
    required property string keyText
    required property string label
    spacing: Commons.Style.space(7)
    width: childrenRect.width

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: keyLabel.implicitWidth + Commons.Style.space(12)
      height: Commons.Style.space(24)
      color: "transparent"
      border.color: root.controller.dividerColor
      border.width: 1
      radius: 1

      Text {
        id: keyLabel
        anchors.centerIn: parent
        text: hint.keyText
        color: root.foreground
        font.family: root.controller.bar
          ? root.controller.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: hint.label
      color: root.foreground
      opacity: 0.48
      font.family: root.controller.bar
        ? root.controller.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.letterSpacing: 1.1
    }
  }
}
