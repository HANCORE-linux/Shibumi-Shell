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
  property string expandedCheckId: ""
  property string copiedCheckId: ""

  readonly property var report: controller.healthReport || ({
    generatedEpoch: 0,
    overall: "loading",
    summary: "Not checked yet",
    checks: []
  })
  readonly property var checks: Array.isArray(report.checks)
    ? report.checks : []
  readonly property var attentionChecks: checks.filter(function(check) {
    return check.status === "error" || check.status === "warning"
  })
  readonly property var runtimeChecks: checks.filter(function(check) {
    return check.status !== "error" && check.status !== "warning"
      && ["runtime-errors", "bar-runtime", "managed-plugins"]
        .indexOf(String(check.id || "")) >= 0
  })
  readonly property bool ready: attentionRepeater.count
    === attentionChecks.length && runtimeRepeater.count === runtimeChecks.length
  readonly property bool busy: controller.healthRunning === true
  readonly property int statusColumnWidth: 62
  readonly property int rowHorizontalPadding: 10
  readonly property string installedShibumiVersion: {
    for (let index = 0; index < checks.length; index++) {
      if (String(checks[index].id || "") !== "versions") continue
      const value = String(checks[index].value || "").split(" · ")[0]
      return value === "" ? "Checking …" : value
    }
    return "Checking …"
  }
  readonly property string installChannelLabel: report.installOrigin === "package"
    ? "ARCH PACKAGE" : report.installOrigin === "checkout"
      ? "SOURCE CHECKOUT" : "CHECKING …"

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(6)

  function overallLabel() {
    if (busy) return controller.healthFetching ? "Checking updates …" : "Checking …"
    if (report.overall === "error") return "Action needed"
    if (report.overall === "warning") return "Review recommended"
    if (report.overall === "healthy") return "Healthy"
    return "Not checked"
  }

  function statusGlyph(status) {
    if (status === "error") return "×"
    if (status === "warning") return "!"
    if (status === "ok" || status === "healthy") return "✓"
    return "·"
  }

  function statusLabel(status) {
    if (status === "error") return "ERROR"
    if (status === "warning") return "REVIEW"
    if (status === "ok") return "PASS"
    return "INFO"
  }

  function statusColor(status) {
    if (status === "error")
      return controller.accentColor("color01")
    if (status === "ok" || status === "healthy")
      return controller.accentColor("color03")
    if (status === "warning") return accent
    return foreground
  }

  function summaryLabel() {
    const errors = checks.filter(function(check) {
      return check.status === "error"
    }).length
    const warnings = checks.filter(function(check) {
      return check.status === "warning"
    }).length
    const passed = checks.filter(function(check) {
      return check.status === "ok"
    }).length
    const parts = []
    if (errors > 0) parts.push(errors + (errors === 1 ? " error" : " errors"))
    if (warnings > 0)
      parts.push(warnings + (warnings === 1 ? " warning" : " warnings"))
    if (passed > 0) parts.push(passed + " checks passed")
    return parts.length > 0 ? parts.join("  ·  ") : "Not checked yet"
  }

  function generatedLabel() {
    const epoch = Number(report.generatedEpoch || 0)
    if (epoch <= 0) return "No report yet"
    return "Checked " + Qt.formatDateTime(new Date(epoch * 1000), "HH:mm")
  }

  function checkDetail(check) {
    const lines = []
    if (String(check.status || "") === "error")
      lines.push("Code: " + diagnosticCode(check))
    if (String(check.detail || "") !== "") lines.push(String(check.detail))
    if (String(check.component || "") !== "")
      lines.push("Component: " + String(check.component))
    if (String(check.action || "") !== "")
      lines.push("Next: " + String(check.action))
    return lines.join("\n")
  }

  function diagnosticCode(check) {
    return "SHIBUMI-HEALTH/" + String(check.id || "UNKNOWN")
      .toUpperCase().replace(/[^A-Z0-9_-]/g, "-")
  }

  function diagnosticReport(check) {
    const fields = [
      "Code: " + diagnosticCode(check),
      "Status: " + String(check.status || "unknown"),
      "Check: " + String(check.label || "Unknown check"),
      "Result: " + String(check.value || ""),
      "Version: Shibumi " + installedShibumiVersion
    ]
    if (String(check.component || "") !== "")
      fields.push("Component: " + String(check.component))
    if (String(check.detail || "") !== "")
      fields.push("Detail: " + String(check.detail))
    if (String(check.action || "") !== "")
      fields.push("Suggested action: " + String(check.action))
    return fields.join("\n")
  }

  function copyDiagnostic(check) {
    clipboardBridge.text = diagnosticReport(check)
    clipboardBridge.selectAll()
    clipboardBridge.copy()
    clipboardBridge.deselect()
    copiedCheckId = String(check.id || "")
    copiedReset.restart()
  }

  function diagnosticIssueUrl(check) {
    const title = "[Health] " + diagnosticCode(check) + " · "
      + String(check.label || "Runtime error")
    const body = "<!-- Generated by Shibumi Health -->\n\n```text\n"
      + diagnosticReport(check) + "\n```\n\nWhat happened:\n"
    return "https://github.com/HANCORE-linux/Shibumi-Shell/issues/new?title="
      + encodeURIComponent(title) + "&body=" + encodeURIComponent(body)
  }

  function openDiagnosticIssue(check) {
    Qt.openUrlExternally(diagnosticIssueUrl(check))
  }

  TextEdit {
    id: clipboardBridge
    visible: false
    readOnly: true
  }

  Timer {
    id: copiedReset
    interval: 1800
    onTriggered: root.copiedCheckId = ""
  }

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "health"
    eyebrow: "RUNTIME DIAGNOSTICS"
    title: "Health"
    description: "Runtime errors, lifecycle and installation status."
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  Rectangle {
    width: parent.width
    height: Commons.Style.space(29)
    radius: root.controller.controlRadius
    color: root.controller.controlFillColor
    border.width: 0

    Row {
      anchors.fill: parent
      anchors.leftMargin: 0
      anchors.rightMargin: Commons.Style.space(10)
      spacing: Commons.Style.space(8)

      Text {
        width: Commons.Style.space(54)
        anchors.verticalCenter: parent.verticalCenter
        text: "VERSION"
        color: root.accent
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
      }

      Text {
        width: parent.width - Commons.Style.space(54)
          - installChannel.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        text: "Shibumi " + root.installedShibumiVersion
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        font.weight: Font.Medium
      }

      Text {
        id: installChannel
        anchors.verticalCenter: parent.verticalCenter
        text: root.installChannelLabel
        color: root.foreground
        opacity: 0.46
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
      }
    }
  }

  Rectangle {
    width: parent.width
    implicitHeight: summaryContent.implicitHeight + Commons.Style.space(20)
    radius: root.controller.controlRadius
    color: root.controller.controlFillColor
    border.width: root.controller.controlBorderWidth
    border.color: root.report.overall === "error"
      ? root.statusColor("error") : root.controller.controlBorderColor

    Row {
      id: summaryContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Commons.Style.space(12)
      anchors.rightMargin: Commons.Style.space(12)
      spacing: Commons.Style.space(10)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(34)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: root.statusColor(root.report.overall)

        Text {
          anchors.centerIn: parent
          text: root.busy ? "…" : root.statusGlyph(root.report.overall)
          color: root.statusColor(root.report.overall)
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.space(18) * root.uiScale
          font.weight: Font.DemiBold
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - parent.spacing * 3
          - Commons.Style.space(34) - runChecks.width - checkUpdates.width
        spacing: Commons.Style.space(2)

        Text {
          width: parent.width
          text: root.overallLabel()
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.body * root.uiScale
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: root.summaryLabel() + "  ·  " + root.generatedLabel()
          color: root.foreground
          opacity: 0.56
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
        }
      }

      CompactSettingChoice {
        id: runChecks
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(94)
        controller: root.controller
        label: root.busy && !root.controller.healthFetching
          ? "Checking …" : "Run checks"
        enabled: !root.busy
        primary: true
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.runHealthChecks(false)
      }

      CompactSettingChoice {
        id: checkUpdates
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(108)
        controller: root.controller
        label: root.busy && root.controller.healthFetching
          ? "Fetching …" : "Check updates"
        enabled: !root.busy
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.runHealthChecks(true)
      }
    }
  }

  Rectangle {
    width: parent.width
    implicitHeight: failureText.implicitHeight + Commons.Style.space(12)
    visible: String(root.controller.healthFailure || "") !== ""
    radius: root.controller.controlRadius
    color: Commons.Util.alpha(root.statusColor("error"), 0.08)
    border.width: 1
    border.color: Commons.Util.alpha(root.statusColor("error"), 0.48)

    Text {
      id: failureText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Commons.Style.space(9)
      anchors.rightMargin: Commons.Style.space(9)
      text: String(root.controller.healthFailure || "")
      color: root.statusColor("error")
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }
  }

  SectionLabel {
    visible: root.attentionChecks.length > 0
    text: "ATTENTION  ·  " + root.attentionChecks.length
  }

  Repeater {
    id: attentionRepeater
    model: root.attentionChecks
    delegate: HealthCheckRow {
      required property var modelData
      width: root.width
      check: modelData
      interactive: true
    }
  }

  SectionLabel {
    visible: root.runtimeChecks.length > 0
    text: "RUNTIME"
  }

  Repeater {
    id: runtimeRepeater
    model: root.runtimeChecks
    delegate: HealthCheckRow {
      required property var modelData
      width: root.width
      check: modelData
      interactive: false
    }
  }

  Text {
    width: parent.width
    text: "Read-only · details appear only when action is needed"
    color: root.foreground
    opacity: 0.38
    horizontalAlignment: Text.AlignHCenter
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.58
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Medium
    font.letterSpacing: 1
  }

  component HealthCheckRow: Rectangle {
    id: checkRow

    required property var check
    property bool interactive: false
    readonly property string extra: root.checkDetail(check)
    readonly property bool expanded: interactive && root.expandedCheckId
      === String(check.id || "")
    readonly property bool reportable: String(check.status || "") === "error"

    implicitHeight: rowContent.implicitHeight + Commons.Style.space(14)
    radius: root.controller.controlRadius
    color: interactive
      ? (rowPointer.containsMouse && extra !== ""
          ? root.controller.controlHoverFillColor
          : root.controller.controlFillColor)
      : "transparent"
    border.width: interactive ? root.controller.controlBorderWidth : 0
    border.color: interactive
      && (check.status === "error" || check.status === "warning")
        ? Commons.Util.alpha(root.statusColor(check.status), 0.58)
        : root.controller.controlBorderColor
    activeFocusOnTab: interactive && extra !== ""
    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: String(check.label || "Health check") + ", "
      + root.statusLabel(String(check.status || "info"))

    Column {
      id: rowContent
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: root.rowHorizontalPadding
      width: Math.max(1, checkRow.width - root.rowHorizontalPadding * 2)
      spacing: Commons.Style.space(5)
      z: 1

      Row {
        width: parent.width
        height: Commons.Style.space(25)
        spacing: Commons.Style.space(8)

        Text {
          width: Commons.Style.space(14)
          height: parent.height
          text: root.statusGlyph(String(checkRow.check.status || "info"))
          color: root.statusColor(String(checkRow.check.status || "info"))
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.body * root.uiScale
          font.weight: Font.DemiBold
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Commons.Style.space(14)
            - statusText.width - parent.spacing * 2
          spacing: 0

          Text {
            width: parent.width
            text: String(checkRow.check.label || "Check")
            color: root.foreground
            elide: Text.ElideRight
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
            font.weight: Font.Medium
          }

          Text {
            width: parent.width
            text: String(checkRow.check.value || "")
            color: root.foreground
            opacity: 0.52
            elide: Text.ElideRight
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
          }
        }

        Text {
          id: statusText
          width: root.statusColumnWidth
          anchors.verticalCenter: parent.verticalCenter
          text: root.statusLabel(String(checkRow.check.status || "info"))
            + (checkRow.interactive && checkRow.extra !== ""
              ? (checkRow.expanded ? "  ▾" : "  ▸") : "")
          color: root.statusColor(String(checkRow.check.status || "info"))
          opacity: checkRow.check.status === "info" ? 0.58 : 0.9
          horizontalAlignment: Text.AlignLeft
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
          font.letterSpacing: 0.6
        }
      }

      Text {
        width: parent.width
        visible: checkRow.expanded && checkRow.extra !== ""
        text: checkRow.extra
        color: root.foreground
        opacity: 0.62
        wrapMode: Text.WordWrap
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        lineHeight: 1.15
      }

      Row {
        width: parent.width
        visible: checkRow.expanded && checkRow.reportable
        spacing: Commons.Style.space(6)

        Text {
          width: parent.width - openIssue.width - copyReport.width
            - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          text: root.diagnosticCode(checkRow.check)
          color: root.statusColor("error")
          opacity: 0.72
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.Medium
          font.letterSpacing: 0.4
        }

        CompactSettingChoice {
          id: copyReport
          width: Commons.Style.space(62)
          controller: root.controller
          label: root.copiedCheckId === String(checkRow.check.id || "")
            ? "Copied" : "Copy"
          foreground: root.foreground
          accent: root.statusColor("error")
          uiScale: root.uiScale
          onClicked: root.copyDiagnostic(checkRow.check)
        }

        CompactSettingChoice {
          id: openIssue
          width: Commons.Style.space(90)
          controller: root.controller
          label: "Open issue"
          primary: true
          foreground: root.foreground
          accent: root.statusColor("error")
          uiScale: root.uiScale
          onClicked: root.openDiagnosticIssue(checkRow.check)
        }
      }
    }

    MouseArea {
      id: rowPointer
      anchors.fill: parent
      enabled: checkRow.interactive && checkRow.extra !== ""
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.expandedCheckId = checkRow.expanded
        ? "" : String(checkRow.check.id || "")
    }

    Keys.onReturnPressed: if (interactive && extra !== "")
      root.expandedCheckId = expanded ? "" : String(check.id || "")
    Keys.onSpacePressed: if (interactive && extra !== "")
      root.expandedCheckId = expanded ? "" : String(check.id || "")
  }
}
