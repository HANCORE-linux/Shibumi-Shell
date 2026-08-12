pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../menu" as Menu

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.ai"
  manageIpc: false
  property url panelSource: Qt.resolvedUrl("AiUsagePanel.qml")
  readonly property var aiService: bar ? bar.aiUsageService : null
  readonly property var provider: aiService ? aiService.selectedProvider : null
  readonly property string providerId: provider
    ? String(provider.providerId || "") : ""
  readonly property int usagePercent: aiService
    ? aiService.usagePercent(provider) : -1
  readonly property int steppedPercent: usagePercent < 0
    ? 0 : Math.round(usagePercent / 5) * 5
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property var interactionTarget: actionButton
  readonly property bool panelLoaded: panelLoader.item !== null
  readonly property var panelItem: panelLoader.item
  readonly property string tooltipText: aiService
    ? aiService.tooltipText() : "No AI usage providers detected"

  visible: aiService && aiService.providers.length > 0
  implicitWidth: visible ? (bar && bar.vertical
    ? bar.barSize : aiSurface.implicitWidth) : 0
  implicitHeight: visible ? (bar ? bar.barSize : Commons.Style.space(35)) : 0

  function syncPanelLoader() {
    if (!opened) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(panelSource, {
      anchorItem: aiSurface,
      bar: root.bar,
      ownerWidget: root,
      aiService: root.aiService
    })
  }

  function childPanelWidget(pluginId) {
    const id = String(pluginId || "")
    return id === moduleName || id === "omarchy.agents"
      || id === "omarchy.model-usage" ? root : null
  }

  onOpenedChanged: syncPanelLoader()

  Item {
    id: aiSurface
    anchors.centerIn: parent
    implicitWidth: root.bar && root.bar.vertical
      ? root.bar.barSize : contentRow.implicitWidth + 2 * (root.tokens ? root.tokens.pillPaddingX : 9)
    implicitHeight: root.tokens ? root.tokens.slotHeight : Commons.Style.space(28)
    width: implicitWidth
    height: implicitHeight

    PillSurface {
      anchors.fill: parent
      anchors.topMargin: root.tokens
        ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
      anchors.bottomMargin: root.tokens
        ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
      bar: root.bar
    }

    Ui.WidgetButton {
      id: actionButton
      anchors.fill: parent
      bar: root.bar
      text: " "
      keepSpace: true
      horizontalMargin: 0
      verticalPadding: 0
      fixedWidth: aiSurface.width
      fixedHeight: aiSurface.height
      tooltipText: root.tooltipText
      onPressed: function(button) {
        if (!root.aiService) return
        if (button === Qt.RightButton) root.aiService.refreshAll(true)
        else if (button === Qt.MiddleButton) root.aiService.cycleTool(1)
        else root.toggle()
      }
      onWheelMoved: function(delta) {
        if (root.aiService) root.aiService.cycleTool(delta > 0 ? -1 : 1)
      }
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: root.tokens ? root.tokens.compactGap : Commons.Style.space(5)

      Item {
        id: providerIcon
        anchors.verticalCenter: parent.verticalCenter
        width: root.providerId === "opencode" ? 20
          : root.providerId === "codex" ? 14 : 15
        height: root.providerId === "opencode" ? 12
          : root.providerId === "codex" ? 14 : 15

        Item {
          anchors.centerIn: parent
          width: 15
          height: 15
          visible: root.providerId === "claude"

          Text {
            anchors.centerIn: parent
            text: "\udb85\ude7a"
            color: root.bar ? Qt.rgba(root.bar.foreground.r,
              root.bar.foreground.g, root.bar.foreground.b, 0.25)
              : Commons.Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: 14
            renderType: Text.QtRendering
          }

          Item {
            width: parent.width
            height: root.steppedPercent > 0
              ? Math.min(parent.height, Math.max(parent.height * root.steppedPercent / 100,
                  parent.height * 0.25)) : 0
            anchors.bottom: parent.bottom
            clip: true
            Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            Text {
              width: providerIcon.width
              height: providerIcon.height
              anchors.bottom: parent.bottom
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: "\udb85\ude7a"
              color: root.bar ? root.bar.urgent : Commons.Color.urgent
              font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: 14
              renderType: Text.QtRendering
            }
          }
        }

        Item {
          anchors.fill: parent
          visible: root.providerId === "codex" || root.providerId === "opencode"

          Menu.TintedImage {
            anchors.fill: parent
            source: root.providerId === "opencode"
              ? Qt.resolvedUrl("../assets/opencode-mark.svg")
              : Qt.resolvedUrl("../assets/codex.svg")
            sourceSize: root.providerId === "opencode"
              ? Qt.size(20, 12) : Qt.size(56, 56)
            smooth: root.providerId !== "opencode"
            mipmap: root.providerId !== "opencode"
            tint: root.bar ? Qt.rgba(root.bar.foreground.r,
              root.bar.foreground.g, root.bar.foreground.b,
              root.providerId === "codex" ? 0.65 : 0.5)
              : Commons.Color.foreground
          }

          Item {
            width: parent.width
            height: root.steppedPercent > 0
              ? Math.min(parent.height, Math.max(parent.height * root.steppedPercent / 100,
                  parent.height * 0.22)) : 0
            anchors.bottom: parent.bottom
            clip: true
            Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            Menu.TintedImage {
              width: providerIcon.width
              height: providerIcon.height
              anchors.bottom: parent.bottom
              source: root.providerId === "opencode"
                ? Qt.resolvedUrl("../assets/opencode-mark.svg")
                : Qt.resolvedUrl("../assets/codex.svg")
              sourceSize: root.providerId === "opencode"
                ? Qt.size(20, 12) : Qt.size(56, 56)
              smooth: root.providerId !== "opencode"
              mipmap: root.providerId !== "opencode"
              tint: root.bar ? root.bar.urgent : Commons.Color.urgent
            }
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.usagePercent >= 0
          ? String(root.usagePercent).padStart(2, "0") + "%" : "··"
        color: root.bar ? Qt.rgba(root.bar.foreground.r,
          root.bar.foreground.g, root.bar.foreground.b, 0.88)
          : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: 12
        renderType: Text.NativeRendering
      }
    }
  }

  Loader {
    id: panelLoader
  }
}
