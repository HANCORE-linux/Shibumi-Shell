pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/lib/presentation" as Presentation

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.ai"
  manageIpc: false
  Presentation.HostTokens { id: hostTokens; bar: root.bar }
  property url panelSource: Qt.resolvedUrl("AiUsagePanel.qml")
  property var aiServiceOverride: null
  readonly property var aiService: aiServiceOverride
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("hancore.shibumi.ai") : null)
  readonly property var provider: aiService ? aiService.selectedProvider : null
  readonly property string providerId: provider
    ? String(provider.providerId || "") : ""
  readonly property int usagePercent: aiService
    ? aiService.usagePercent(provider) : -1
  readonly property int steppedPercent: usagePercent < 0
    ? 0 : Math.round(usagePercent / 5) * 5
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  // Preserve the source ink -> seal treatment while appearance is inherited.
  // Any explicit V1 or V2 fill uses one contrast-aware tone for both layers.
  readonly property bool customFillActive: !!(tokens
    && typeof tokens.widgetHasFill === "function"
    && tokens.widgetHasFill(settings))
  readonly property color defaultUsageIconColor: bar
    ? bar.urgent : Commons.Color.accent
  readonly property color widgetInk: customFillActive && tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings, defaultUsageIconColor)
    : defaultUsageIconColor
  readonly property color baseIconColor: customFillActive
    ? widgetInk : tokens && tokens.ink !== undefined
      ? tokens.ink : (bar ? bar.foreground : Commons.Color.foreground)
  readonly property color usageIconColor: widgetInk
  readonly property real baseIconOpacity: customFillActive ? 0.65
    : providerId === "claude" ? 0.25
      : providerId === "codex" ? 0.65 : 0.5
  readonly property bool claudeLayersAligned:
    Math.abs(claudeGlyphBase.x
      - (claudeUsageClip.x + claudeUsageGlyph.x)) < 0.01
    && Math.abs(claudeGlyphBase.y
      - (claudeUsageClip.y + claudeUsageGlyph.y)) < 0.01
    && claudeGlyphBase.width === claudeUsageGlyph.width
    && claudeGlyphBase.height === claudeUsageGlyph.height
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  readonly property int providerIconSlotWidth: 20
  readonly property int providerIconSlotHeight: 16
  readonly property int claudeGlyphPixelSize: 15
  readonly property int providerGlyphWidth: providerId === "opencode" ? 15
    : providerId === "codex" ? 14 : 15
  readonly property int providerGlyphHeight: providerId === "opencode" ? 10
    : providerId === "codex" ? 14 : 15
  readonly property int providerGlyphHorizontalOffset: 0
  readonly property int providerContentHorizontalOffset:
    providerId === "codex" && displayMode !== "text" ? -1 : 0
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

    Presentation.PillSurface {
      tokenSource: root.tokens
      settings: root.settings
      v1AppearanceEnabled: true
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

    Presentation.InkRow {
      id: contentRow
      boundLastAdvance: root.tokens.v2Shell === true
      optical: !root.bar || !root.bar.vertical
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.providerContentHorizontalOffset
      spacing: root.tokens ? root.tokens.compactGap : Commons.Style.space(5)

      Item {
        id: providerIcon
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        width: root.providerIconSlotWidth
        height: root.providerIconSlotHeight
        readonly property real inkLeft: providerGlyph.x + (root.providerId === "claude"
          ? claudeGlyphBase.x + claudeGlyphBase.inkLeft : 0)
        readonly property real inkRight: providerGlyph.x + (root.providerId === "claude"
          ? claudeGlyphBase.x + claudeGlyphBase.inkRight : providerGlyph.width)

        Item {
          id: providerGlyph
          anchors.centerIn: parent
          anchors.horizontalCenterOffset: root.providerGlyphHorizontalOffset
          width: root.providerGlyphWidth
          height: root.providerGlyphHeight

          Item {
            id: claudeIcon
            anchors.fill: parent
            visible: root.providerId === "claude"

            Presentation.BarGlyph {
              id: claudeGlyphBase
              // Keep the original advance/line box for both aligned layers.
              optical: !root.bar || !root.bar.vertical
              anchors.centerIn: parent
              text: "\udb85\ude7a"
              color: Qt.rgba(root.baseIconColor.r,
                root.baseIconColor.g, root.baseIconColor.b,
                root.baseIconOpacity)
              font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: root.claudeGlyphPixelSize
              renderType: Text.QtRendering
            }

            Item {
              id: claudeUsageClip
              width: parent.width
              height: root.steppedPercent > 0
                ? Math.min(parent.height, Math.max(parent.height * root.steppedPercent / 100,
                    parent.height * 0.25)) : 0
              anchors.bottom: parent.bottom
              clip: true
              Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

              Presentation.BarGlyph {
                id: claudeUsageGlyph
                optical: !root.bar || !root.bar.vertical
                x: claudeGlyphBase.x
                y: claudeGlyphBase.y - claudeUsageClip.y
                width: claudeGlyphBase.width
                height: claudeGlyphBase.height
                text: "\udb85\ude7a"
                color: root.usageIconColor
                font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
                font.pixelSize: root.claudeGlyphPixelSize
                renderType: Text.QtRendering
              }
            }
          }

          OpenCodeUsageIcon {
            anchors.fill: parent
            visible: root.providerId === "opencode"
            baseColor: root.baseIconColor
            fillColor: root.usageIconColor
            baseOpacity: root.baseIconOpacity
            usageFraction: root.steppedPercent > 0
              ? Math.min(1, Math.max(root.steppedPercent / 100, 0.22)) : 0
          }

          Item {
            id: providerImage
            anchors.fill: parent
            visible: root.providerId === "codex"
            Presentation.BarInk { id: imageInk; target: providerImage }
            transform: Translate {
              x: imageInk.enabled ? imageInk.snapX(0) : 0
              y: imageInk.enabled ? imageInk.rectangleY(providerImage.height) : 0
            }

            TintedImage {
              anchors.fill: parent
              source: root.providerId === "opencode"
                ? Qt.resolvedUrl("assets/opencode-mark.svg")
                : Qt.resolvedUrl("assets/codex.svg")
              sourceSize: root.providerId === "opencode"
                ? Qt.size(20, 12) : Qt.size(56, 56)
              smooth: root.providerId !== "opencode"
              mipmap: root.providerId !== "opencode"
              tint: Qt.rgba(root.baseIconColor.r,
                root.baseIconColor.g, root.baseIconColor.b,
                root.baseIconOpacity)
            }

            Item {
              width: parent.width
              height: root.steppedPercent > 0
                ? Math.min(parent.height, Math.max(parent.height * root.steppedPercent / 100,
                    parent.height * 0.22)) : 0
              anchors.bottom: parent.bottom
              clip: true
              Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

              TintedImage {
                width: providerGlyph.width
                height: providerGlyph.height
                anchors.bottom: parent.bottom
                source: root.providerId === "opencode"
                  ? Qt.resolvedUrl("assets/opencode-mark.svg")
                  : Qt.resolvedUrl("assets/codex.svg")
                sourceSize: root.providerId === "opencode"
                  ? Qt.size(20, 12) : Qt.size(56, 56)
                smooth: root.providerId !== "opencode"
                mipmap: root.providerId !== "opencode"
                tint: root.usageIconColor
              }
            }
          }
        }
      }

      Presentation.IconText {
        barText: true
        visible: root.displayMode !== "icon"
        anchors.verticalCenter: parent.verticalCenter
        text: root.usagePercent >= 0
          ? String(root.usagePercent).padStart(2, "0") + "%" : "··"
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }

  // The original pixel mark, rasterized at its native grid before nearest sampling.
  component OpenCodeUsageIcon: Item {
    id: iconRoot
    required property color baseColor
    required property color fillColor
    required property real baseOpacity
    required property real usageFraction

    Presentation.BarInk { id: placement; target: iconRoot }
    Item {
      id: paint
      width: Math.round(iconRoot.width * placement.dpr) / placement.dpr
      height: Math.round(width * placement.dpr * 14 / 22) / placement.dpr
      x: placement.snapX((iconRoot.width - width) / 2)
      y: placement.rectangleY(height)

      Image {
        id: mark
        anchors.fill: parent
        visible: false
        source: Qt.resolvedUrl("assets/opencode-mark.svg")
        // Qt scales SVG requests by DPR before rasterizing them.
        sourceSize: Qt.size(Math.max(1, Math.round(22 / placement.dpr)),
          Math.max(1, Math.round(14 / placement.dpr)))
        fillMode: Image.Stretch
        smooth: false
        mipmap: false
      }
      MultiEffect {
        anchors.fill: parent
        source: mark
        colorization: 1
        colorizationColor: Qt.rgba(iconRoot.baseColor.r, iconRoot.baseColor.g, iconRoot.baseColor.b, 1)
        opacity: iconRoot.baseColor.a * iconRoot.baseOpacity
      }
      Item {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.round(parent.height * iconRoot.usageFraction * placement.dpr) / placement.dpr
        clip: true
        Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        MultiEffect {
          anchors.bottom: parent.bottom
          width: paint.width
          height: paint.height
          source: mark
          colorization: 1
          colorizationColor: Qt.rgba(iconRoot.fillColor.r, iconRoot.fillColor.g, iconRoot.fillColor.b, 1)
          opacity: iconRoot.fillColor.a
        }
      }
    }
  }

  Loader {
    id: panelLoader
  }
}
