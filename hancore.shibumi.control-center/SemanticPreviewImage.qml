pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var controller
  property string routeId: "bars"
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool compact: false
  readonly property var workspacePreviewOptions: [
    { value: "default", label: "Default" },
    { value: "numbers", label: "Numbers" },
    { value: "magic", label: "Magic" },
    { value: "rings", label: "Frame" }
  ]
  readonly property var iconPreviewOptions: [
    { label: "Launcher", glyph: "apps", mode: "WORDMARK" },
    { label: "Volume", glyph: "volume_up", mode: "ICON + TEXT" },
    { label: "Clock", glyph: "schedule", mode: "TEXT" },
    { label: "Network", glyph: "wifi", mode: "ICON" },
    { label: "Battery", glyph: "battery_5_bar", mode: "ICON + TEXT" },
    { label: "Media", glyph: "music_note", mode: "FULL" }
  ]
  readonly property var pickerPreviewOptions: [
    { value: "carousel", label: "Carousel" },
    { value: "tanzaku", label: "Tanzaku" },
    { value: "hearthstone", label: "Hearthstone" }
  ]
  readonly property var compactWorkspacePreviewOptions: {
    const selected = String(controller.workspaceConfig.style || "default")
    const matches = workspacePreviewOptions.filter(function(option) {
      return option.value === selected
    })
    return matches.length > 0 ? [matches[0]] : [workspacePreviewOptions[0]]
  }
  readonly property var compactPickerPreviewOptions: {
    const configured = String(controller.imagePickerStyle || "carousel")
    const selected = configured === "omarchy" ? "carousel" : configured
    const matches = pickerPreviewOptions.filter(function(option) {
      return option.value === selected
    })
    return matches.length > 0 ? [matches[0]] : [pickerPreviewOptions[0]]
  }
  readonly property var pluginPreviewOptions: {
    const entries = controller && Array.isArray(controller.pluginEntries)
      ? controller.pluginEntries : []
    if (entries.length > 0) return entries.slice(0, 4)
    return [
      { name: "Weather", provider: "Omarchy", glyph: "cloud", enabled: true },
      { name: "System", provider: "Shibumi", glyph: "monitor_heart", enabled: true },
      { name: "Pomodoro", provider: "Community", glyph: "timer", enabled: false },
      { name: "Docker", provider: "Community", glyph: "deployed_code", enabled: false }
    ]
  }
  readonly property var healthPreviewChecks: {
    const report = controller && controller.healthReport
      ? controller.healthReport : ({ checks: [] })
    const checks = Array.isArray(report.checks) ? report.checks.slice() : []
    checks.sort(function(left, right) {
      const rank = { error: 0, warning: 1, ok: 2, healthy: 2 }
      return (rank[String(left.status || "")] ?? 3)
        - (rank[String(right.status || "")] ?? 3)
    })
    if (checks.length > 0) return checks.slice(0, 4)
    return [
      { label: "Shell runtime", value: "Responsive", status: "ok" },
      { label: "Manifests", value: "24 / 24", status: "ok" },
      { label: "Host contract", value: "Compatible", status: "ok" },
      { label: "Configuration", value: "No errors", status: "ok" }
    ]
  }
  readonly property int healthPreviewErrorCount:
    healthPreviewChecks.filter(function(check) {
      return String(check.status || "") === "error"
    }).length
  readonly property int healthPreviewWarningCount:
    healthPreviewChecks.filter(function(check) {
      return String(check.status || "") === "warning"
    }).length
  readonly property string semanticRoute: {
    const route = String(routeId || "").split(":")[0]
    if (route === "quick" || route === "layout") return "bars"
    if (route === "functions") return "appearance"
    if (route === "preferences") return "health"
    return route
  }

  function previewStatusColor(status) {
    if (status === "error") return controller.accentColor("color01")
    if (status === "ok" || status === "healthy")
      return controller.accentColor("color03")
    return accent
  }

  function previewStatusGlyph(status) {
    if (status === "error") return "×"
    if (status === "warning") return "!"
    if (status === "ok" || status === "healthy") return "✓"
    return "·"
  }

  Canvas {
    id: preview
    anchors.fill: parent
    visible: ["logo", "pickers", "workspaces", "appearance", "plugins",
      "health"].indexOf(root.semanticRoute) < 0
    antialiasing: true
    renderStrategy: Canvas.Threaded

    function rounded(context, x, y, w, h, r) {
      const radius = Math.min(r, w / 2, h / 2)
      context.beginPath()
      context.moveTo(x + radius, y)
      context.lineTo(x + w - radius, y)
      context.quadraticCurveTo(x + w, y, x + w, y + radius)
      context.lineTo(x + w, y + h - radius)
      context.quadraticCurveTo(x + w, y + h, x + w - radius, y + h)
      context.lineTo(x + radius, y + h)
      context.quadraticCurveTo(x, y + h, x, y + h - radius)
      context.lineTo(x, y + radius)
      context.quadraticCurveTo(x, y, x + radius, y)
      context.closePath()
    }

    function strokeBox(context, x, y, w, h, r, alpha) {
      rounded(context, x, y, w, h, r)
      context.fillStyle = Commons.Util.alpha(root.foreground, alpha * 0.32)
      context.fill()
      context.strokeStyle = Commons.Util.alpha(root.foreground, alpha)
      context.lineWidth = 1
      context.stroke()
    }

    function moduleBlock(context, x, y, w, h, accented) {
      rounded(context, x, y, w, h, Math.min(2.5, h / 2))
      context.fillStyle = accented
        ? root.accent : Commons.Util.alpha(root.foreground, 0.52)
      context.fill()
    }

    function moduleDot(context, x, y, radius, accented) {
      context.beginPath()
      context.arc(x, y, radius, 0, Math.PI * 2)
      context.fillStyle = accented
        ? root.accent : Commons.Util.alpha(root.foreground, 0.48)
      context.fill()
    }

    function edgeLine(context, y, x1, x2) {
      context.strokeStyle = Commons.Util.alpha(root.foreground, 0.14)
      context.lineWidth = 1
      context.beginPath()
      context.moveTo(x1, y)
      context.lineTo(x2, y)
      context.stroke()
    }

    function notchSurface(context, x, y, w, h, alpha) {
      const wing = Math.min(24, w * 0.08)
      const inset = wing + 12
      context.beginPath()
      context.moveTo(x, y)
      context.lineTo(x + w, y)
      context.bezierCurveTo(
        x + w - wing, y, x + w - wing, y + h, x + w - inset, y + h)
      context.lineTo(x + inset, y + h)
      context.bezierCurveTo(x + wing, y + h, x + wing, y, x, y)
      context.closePath()
      context.fillStyle = Commons.Util.alpha(root.foreground, alpha * 0.32)
      context.fill()
      context.strokeStyle = Commons.Util.alpha(root.foreground, alpha)
      context.lineWidth = 1
      context.stroke()
    }

    onPaint: {
      const context = getContext("2d")
      context.reset()
      context.clearRect(0, 0, width, height)
      const w = width
      const h = height
      const mid = h / 2
      const route = root.semanticRoute
      context.lineCap = "round"

      if (route === "bars") {
        const left = w * 0.10
        const shellW = w * 0.80
        const topY = mid - 43
        edgeLine(context, topY - 5, w * 0.06, w * 0.94)
        strokeBox(context, left, topY, shellW * 0.34, 18, 9, 0.44)
        strokeBox(context, left + shellW * 0.39, topY,
          shellW * 0.20, 18, 9, 0.30)
        strokeBox(context, left + shellW * 0.64, topY,
          shellW * 0.36, 18, 9, 0.30)
        moduleBlock(context, left + 10, topY + 6, shellW * 0.08, 6, true)
        moduleDot(context, w * 0.50, topY + 9, 2.6, true)

        const notchY = mid - 9
        edgeLine(context, notchY - 5, w * 0.06, w * 0.94)
        notchSurface(context, left + w * 0.04, notchY,
          shellW - w * 0.08, 20, 0.52)
        moduleBlock(context, left + w * 0.13, notchY + 7,
          shellW * 0.13, 6, false)
        moduleBlock(context, w * 0.68, notchY + 7,
          shellW * 0.12, 6, true)

        const hostY = mid + 26
        edgeLine(context, hostY - 5, w * 0.06, w * 0.94)
        strokeBox(context, left, hostY, shellW, 20, 2, 0.34)
        moduleBlock(context, left + 10, hostY + 7,
          shellW * 0.15, 6, false)
        for (let index = 0; index < 4; index++)
          moduleDot(context, w * 0.46 + index * 10, hostY + 10,
            index === 0 ? 2.7 : 1.9, index === 0)
        moduleBlock(context, w * 0.73, hostY + 7,
          shellW * 0.11, 6, false)
      } else if (route === "bar-v1") {
        const y = mid - 12
        const shellHeight = 24
        const segments = [
          { x: w * 0.08, width: w * 0.30 },
          { x: w * 0.43, width: w * 0.14 },
          { x: w * 0.62, width: w * 0.30 }
        ]
        edgeLine(context, y - 7, w * 0.04, w * 0.96)
        for (let index = 0; index < segments.length; index++) {
          const segment = segments[index]
          strokeBox(context, segment.x, y, segment.width, shellHeight, 12,
            index === 0 ? 0.68 : 0.38)
        }
        moduleBlock(context, w * 0.105, mid - 4, w * 0.055, 8, false)
        moduleBlock(context, w * 0.177, mid - 4, w * 0.035, 8, false)
        moduleBlock(context, w * 0.228, mid - 4, w * 0.07, 8, true)
        moduleDot(context, w * 0.50, mid, 3.2, true)
        moduleBlock(context, w * 0.655, mid - 4, w * 0.045, 8, false)
        moduleBlock(context, w * 0.716, mid - 4, w * 0.075, 8, false)
        moduleDot(context, w * 0.825, mid, 3, false)
        moduleBlock(context, w * 0.85, mid - 4, w * 0.035, 8, false)
      } else if (route === "bar-v2"
          || route.indexOf("bar-v2-") === 0) {
        const v2Style = route.indexOf("bar-v2-") === 0
          ? route.slice("bar-v2-".length) : "full"
        const y = mid - 13
        const inset = v2Style === "fit" ? w * 0.08
          : v2Style === "dock" || v2Style === "notch" ? w * 0.13
            : w * 0.05
        const shellWidth = w - inset * 2
        edgeLine(context, y - 7, w * 0.04, w * 0.96)
        if (v2Style === "notch")
          notchSurface(context, inset, y, shellWidth, 26, 0.58)
        else
          strokeBox(context, inset, y, shellWidth, 26,
            v2Style === "full" ? 2 : v2Style === "fit" ? 6 : 10, 0.58)
        const contentInset = v2Style === "notch" ? inset + w * 0.09 : inset
        const contentWidth = v2Style === "notch"
          ? shellWidth - w * 0.18 : shellWidth
        moduleBlock(context, contentInset + contentWidth * 0.03,
          mid - 4, contentWidth * 0.08, 8, false)
        moduleBlock(context, contentInset + contentWidth * 0.13,
          mid - 4, contentWidth * 0.055, 8, false)
        moduleBlock(context, contentInset + contentWidth * 0.205,
          mid - 4, contentWidth * 0.09, 8, true)
        for (let index = 0; index < 5; index++)
          moduleDot(context, w * 0.45 + index * w * 0.025, mid,
            index === 2 ? 3.2 : 2.1, index === 2)
        moduleBlock(context, contentInset + contentWidth * 0.69,
          mid - 4, contentWidth * 0.07, 8, false)
        moduleBlock(context, contentInset + contentWidth * 0.78,
          mid - 4, contentWidth * 0.10, 8, false)
        moduleDot(context, contentInset + contentWidth * 0.915,
          mid, 3, false)
      } else if (route === "bar-omarchy") {
        const y = mid - 13
        edgeLine(context, y - 7, w * 0.04, w * 0.96)
        strokeBox(context, w * 0.05, y, w * 0.90, 26, 2, 0.42)
        moduleBlock(context, w * 0.08, mid - 4, w * 0.12, 8, false)
        moduleDot(context, w * 0.232, mid, 3.2, true)
        for (let index = 0; index < 4; index++)
          moduleDot(context, w * 0.45 + index * w * 0.033, mid,
            index === 0 ? 3.2 : 2.1, index === 0)
        moduleBlock(context, w * 0.69, mid - 4, w * 0.055, 8, false)
        moduleDot(context, w * 0.78, mid, 2.8, false)
        moduleBlock(context, w * 0.81, mid - 4, w * 0.055, 8, false)
        moduleDot(context, w * 0.895, mid, 2.8, false)
      } else {
        for (let index = 0; index < 4; index++) {
          context.strokeStyle = index === 1
            ? root.accent : Commons.Util.alpha(root.foreground, 0.25)
          context.lineWidth = index === 1 ? 2 : 1
          context.beginPath()
          context.moveTo(w * 0.24, mid - 25 + index * 17)
          context.lineTo(w * (0.60 + index * 0.035),
            mid - 25 + index * 17)
          context.stroke()
          context.fillStyle = index === 1
            ? root.accent : Commons.Util.alpha(root.foreground, 0.32)
          context.beginPath()
          context.arc(w * 0.72, mid - 25 + index * 17,
            index === 1 ? 4 : 3, 0, Math.PI * 2)
          context.fill()
        }
      }
    }

    Connections {
      target: root
      function onSemanticRouteChanged() { preview.requestPaint() }
      function onForegroundChanged() { preview.requestPaint() }
      function onAccentChanged() { preview.requestPaint() }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()
  }

  WorkspaceMarkerPreviewCard {
    visible: root.compact && root.semanticRoute === "workspaces"
    anchors.centerIn: parent
    width: Math.min((parent.width - 4) / 0.72, 154)
    scale: 0.72
    controller: root.controller
    styleValue: String(root.compactWorkspacePreviewOptions[0].value)
    label: String(root.compactWorkspacePreviewOptions[0].label)
    foreground: root.foreground
    accent: root.accent
    uiScale: 0.82
    enabled: false
  }

  Rectangle {
    visible: root.compact && root.semanticRoute === "appearance"
    anchors.centerIn: parent
    width: Math.min(parent.width - 4, 116)
    height: Math.min(parent.height - 4, 46)
    radius: root.controller.controlRadius
    color: root.controller.controlHoverFillColor
    border.width: Math.max(1, root.controller.controlBorderWidth)
    border.color: root.accent

    Row {
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 6
      spacing: 7

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        text: root.iconPreviewOptions[1].glyph
        color: root.accent
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Commons.Style.font.iconLarge * 0.78
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x
        spacing: 0

        Text {
          width: parent.width
          text: root.iconPreviewOptions[1].label
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * 0.72
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: root.iconPreviewOptions[1].mode
          color: root.accent
          opacity: 0.82
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * 0.60
        }
      }
    }
  }

  Rectangle {
    id: compactPluginCard
    readonly property var plugin: root.pluginPreviewOptions.length > 0
      ? root.pluginPreviewOptions[0] : ({})
    visible: root.compact && root.semanticRoute === "plugins"
    anchors.centerIn: parent
    width: Math.min(parent.width - 4, 116)
    height: Math.min(parent.height - 4, 48)
    radius: root.controller.controlRadius
    color: root.controller.controlFillColor
    border.width: root.controller.controlBorderWidth
    border.color: root.controller.controlBorderColor

    Row {
      anchors.fill: parent
      anchors.margins: 6
      spacing: 7

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 29
        height: width
        radius: Math.max(2, root.controller.controlRadius - 1)
        color: Commons.Util.alpha(root.accent, 0.08)
        border.width: 1
        border.color: Commons.Util.alpha(root.accent, 0.28)

        IconText {
          anchors.centerIn: parent
          text: String(compactPluginCard.plugin.glyph || "extension")
          color: root.accent
          font.pixelSize: Commons.Style.space(17)
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x
        spacing: 0

        Text {
          width: parent.width
          text: String(compactPluginCard.plugin.name || "Plugin")
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * 0.70
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: String(compactPluginCard.plugin.provider
            || "Community").toUpperCase()
          color: compactPluginCard.plugin.enabled === true
            ? root.controller.accentColor("color03") : root.foreground
          opacity: compactPluginCard.plugin.enabled === true ? 0.86 : 0.42
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * 0.56
        }
      }
    }
  }

  Rectangle {
    id: compactHealthCard
    readonly property var check: root.healthPreviewChecks.length > 0
      ? root.healthPreviewChecks[0] : ({})
    visible: root.compact && root.semanticRoute === "health"
    anchors.centerIn: parent
    width: Math.min(parent.width - 4, 116)
    height: Math.min(parent.height - 4, 43)
    radius: root.controller.controlRadius
    color: root.controller.controlFillColor
    border.width: root.controller.controlBorderWidth
    border.color: String(check.status || "") === "error"
      ? root.previewStatusColor("error")
      : root.controller.controlBorderColor

    Row {
      anchors.fill: parent
      anchors.leftMargin: 7
      anchors.rightMargin: 6
      spacing: 6

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 11
        text: root.previewStatusGlyph(String(compactHealthCard.check.status || ""))
        color: root.previewStatusColor(String(compactHealthCard.check.status || ""))
        horizontalAlignment: Text.AlignHCenter
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.body * 0.72
        font.weight: Font.Bold
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x
        spacing: 0

        Text {
          width: parent.width
          text: String(compactHealthCard.check.label || "Health check")
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * 0.68
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: String(compactHealthCard.check.value || "")
          color: root.foreground
          opacity: 0.44
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * 0.56
        }
      }
    }
  }

  PickerPreviewCard {
    visible: root.compact && root.semanticRoute === "pickers"
    anchors.centerIn: parent
    width: Math.min((parent.width - 4) / 0.62, 184)
    scale: 0.62
    controller: root.controller
    styleValue: String(root.compactPickerPreviewOptions[0].value)
    label: String(root.compactPickerPreviewOptions[0].label)
    selectedValue: String(root.compactPickerPreviewOptions[0].value)
    foreground: root.foreground
    accent: root.accent
    uiScale: 0.78
    enabled: false
  }

  Rectangle {
    id: compactLogoCard
    readonly property bool iconMode: root.controller.launcherConfig
      && String(root.controller.launcherConfig.mode || "text") === "icon"
    visible: root.compact && root.semanticRoute === "logo"
    anchors.centerIn: parent
    width: Math.min(parent.width - 4, 116)
    height: Math.min(parent.height - 4, 46)
    radius: root.controller.controlRadius
    color: root.controller.controlHoverFillColor
    border.width: Math.max(1, root.controller.controlBorderWidth)
    border.color: root.accent

    WordmarkPreview {
      visible: !compactLogoCard.iconMode
      anchors.centerIn: parent
      width: parent.width - 14
      height: 25
      value: root.controller.launcherConfig
        ? String(root.controller.launcherConfig.text || "shibumi") : "shibumi"
      foreground: root.foreground
      fontFamily: root.controller.marketFont
    }

    Image {
      visible: compactLogoCard.iconMode
      anchors.centerIn: parent
      width: 26
      height: 26
      source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }
  }

  Grid {
    visible: root.semanticRoute === "workspaces" && !root.compact
    anchors.centerIn: parent
    width: Math.min(parent.width - 18, 242)
    height: 68 * 2 + rowSpacing
    columns: 2
    columnSpacing: 7
    rowSpacing: 7

    Repeater {
      model: root.workspacePreviewOptions

      delegate: WorkspaceMarkerPreviewCard {
        required property var modelData
        width: (parent.width - parent.columnSpacing) / 2
        controller: root.controller
        styleValue: modelData.value
        label: modelData.label
        foreground: root.foreground
        accent: root.accent
        uiScale: 0.82
        enabled: false
      }
    }
  }

  Grid {
    visible: root.semanticRoute === "appearance" && !root.compact
    anchors.centerIn: parent
    width: Math.min(parent.width - 18, 242)
    height: 52 * 3 + rowSpacing * 2
    columns: 2
    columnSpacing: 7
    rowSpacing: 7

    Repeater {
      model: root.iconPreviewOptions

      delegate: Rectangle {
        required property var modelData
        required property int index
        width: (parent.width - parent.columnSpacing) / 2
        height: 52
        radius: root.controller.controlRadius
        color: index === 1
          ? root.controller.controlHoverFillColor
          : root.controller.controlFillColor
        border.width: index === 1
          ? Math.max(1, root.controller.controlBorderWidth)
          : root.controller.controlBorderWidth
        border.color: index === 1
          ? root.accent : root.controller.controlBorderColor

        Row {
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 6
          spacing: 7

          IconText {
            anchors.verticalCenter: parent.verticalCenter
            width: 23
            text: modelData.glyph
            color: index === 1 ? root.accent : root.foreground
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Commons.Style.font.iconLarge * 0.82
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x
            spacing: 1

            Text {
              width: parent.width
              text: modelData.label
              color: root.foreground
              elide: Text.ElideRight
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.caption * 0.82
              font.weight: Font.DemiBold
            }

            Text {
              width: parent.width
              text: modelData.mode
              color: index === 1 ? root.accent : root.foreground
              opacity: index === 1 ? 0.9 : 0.46
              elide: Text.ElideRight
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.caption * 0.68
              font.letterSpacing: 0.3
            }
          }
        }
      }
    }
  }

  Grid {
    visible: root.semanticRoute === "plugins" && !root.compact
    anchors.centerIn: parent
    width: Math.min(parent.width - 18, 242)
    height: 108 * 2 + rowSpacing
    columns: 2
    columnSpacing: 7
    rowSpacing: 7

    Repeater {
      model: root.pluginPreviewOptions

      delegate: Rectangle {
        required property var modelData
        width: (parent.width - parent.columnSpacing) / 2
        height: 108
        radius: root.controller.controlRadius
        color: root.controller.controlFillColor
        border.width: root.controller.controlBorderWidth
        border.color: root.controller.controlBorderColor
        clip: true

        Rectangle {
          id: pluginArtwork
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 59
          color: Commons.Util.alpha(root.accent, 0.055)

          Repeater {
            model: 5
            Rectangle {
              required property int index
              x: index * pluginArtwork.width / 4
              width: 1
              height: pluginArtwork.height
              color: Commons.Util.alpha(root.accent, 0.08)
            }
          }

          IconText {
            anchors.centerIn: parent
            text: String(modelData.glyph || "extension")
            color: root.accent
            font.pixelSize: Commons.Style.space(25)
          }

          Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            width: 7
            height: width
            radius: width / 2
            color: modelData.enabled === true
              ? root.controller.accentColor("color03")
              : Commons.Util.alpha(root.foreground, 0.28)
          }
        }

        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: pluginArtwork.bottom
          anchors.leftMargin: 7
          anchors.rightMargin: 7
          anchors.topMargin: 7
          spacing: 2

          Text {
            width: parent.width
            text: String(modelData.name || "Plugin")
            color: root.foreground
            elide: Text.ElideRight
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * 0.78
            font.weight: Font.DemiBold
          }

          Text {
            width: parent.width
            text: String(modelData.provider || "Community").toUpperCase()
            color: root.foreground
            opacity: 0.42
            elide: Text.ElideRight
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * 0.62
            font.letterSpacing: 0.4
          }
        }
      }
    }
  }

  Column {
    visible: root.semanticRoute === "health" && !root.compact
    anchors.centerIn: parent
    width: Math.min(parent.width - 18, 242)
    spacing: 6

    Rectangle {
      width: parent.width
      height: 34
      radius: root.controller.controlRadius
      color: root.controller.controlHoverFillColor
      border.width: root.controller.controlBorderWidth
      border.color: root.healthPreviewErrorCount > 0
        ? root.previewStatusColor("error")
        : root.healthPreviewWarningCount > 0
          ? root.previewStatusColor("warning")
          : root.controller.controlBorderColor

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: "RUNTIME HEALTH"
        color: root.foreground
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * 0.76
        font.weight: Font.DemiBold
        font.letterSpacing: 0.7
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: root.healthPreviewErrorCount > 0
          ? "ACTION NEEDED"
          : root.healthPreviewWarningCount > 0 ? "REVIEW" : "HEALTHY"
        color: root.healthPreviewErrorCount > 0
          ? root.previewStatusColor("error")
          : root.healthPreviewWarningCount > 0
            ? root.previewStatusColor("warning")
            : root.previewStatusColor("ok")
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * 0.68
        font.weight: Font.Bold
      }
    }

    Repeater {
      model: root.healthPreviewChecks

      delegate: Rectangle {
        required property var modelData
        width: parent.width
        height: 37
        radius: root.controller.controlRadius
        color: root.controller.controlFillColor
        border.width: root.controller.controlBorderWidth
        border.color: String(modelData.status || "") === "error"
          ? root.previewStatusColor("error")
          : root.controller.controlBorderColor

        Row {
          anchors.fill: parent
          anchors.leftMargin: 9
          anchors.rightMargin: 9
          spacing: 7

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 13
            text: root.previewStatusGlyph(String(modelData.status || ""))
            color: root.previewStatusColor(String(modelData.status || ""))
            horizontalAlignment: Text.AlignHCenter
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.body * 0.78
            font.weight: Font.Bold
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x
            spacing: 0

            Text {
              width: parent.width
              text: String(modelData.label || "Health check")
              color: root.foreground
              elide: Text.ElideRight
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.caption * 0.73
              font.weight: Font.DemiBold
            }

            Text {
              width: parent.width
              text: String(modelData.value || "")
              color: root.foreground
              opacity: 0.45
              elide: Text.ElideRight
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.caption * 0.64
            }
          }
        }
      }
    }
  }

  Column {
    visible: root.semanticRoute === "pickers" && !root.compact
    anchors.centerIn: parent
    width: Math.min(parent.width - 20, 230)
    height: 82 * 3 + spacing * 2
    spacing: 7

    Repeater {
      model: root.pickerPreviewOptions

      delegate: PickerPreviewCard {
        required property var modelData
        width: parent.width
        controller: root.controller
        styleValue: modelData.value
        label: modelData.label
        selectedValue: root.controller.imagePickerStyle === "omarchy"
          ? "carousel" : root.controller.imagePickerStyle
        foreground: root.foreground
        accent: root.accent
        uiScale: 0.82
        enabled: false
      }
    }
  }

  Row {
    visible: root.semanticRoute === "logo" && !root.compact
    anchors.centerIn: parent
    width: Math.min(parent.width - 20, 250)
    height: 68
    spacing: 9

    Rectangle {
      width: (parent.width - parent.spacing) / 2
      height: parent.height
      radius: root.controller.controlRadius
      color: root.controller.controlHoverFillColor
      border.width: Math.max(1, root.controller.controlBorderWidth)
      border.color: root.accent

      WordmarkPreview {
        anchors.centerIn: parent
        width: parent.width - 18
        height: 30
        value: "shibumi"
        foreground: root.foreground
        fontFamily: root.controller.marketFont
      }
    }

    Rectangle {
      width: (parent.width - parent.spacing) / 2
      height: parent.height
      radius: root.controller.controlRadius
      color: root.controller.controlFillColor
      border.width: root.controller.controlBorderWidth
      border.color: root.controller.controlBorderColor

      Image {
        anchors.centerIn: parent
        width: 30
        height: 30
        source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
      }
    }
  }
}
