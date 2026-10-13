pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var telemetry
  readonly property var usageRing: memoryRing
  readonly property var hardwareInfoView: hardwareInfo
  property QtObject sweepSource: null
  property bool cacheSelected: true
  property bool compactSelected: true
  readonly property bool sweepAvailable: !!telemetry && typeof telemetry.startMemorySweep === "function"
  readonly property bool sweepVisible: sweepAvailable && sweepSource === telemetry
  readonly property bool sweepRunning: sweepAvailable && telemetry.memorySweepRunning === true
  readonly property string sweepError: sweepAvailable ? String(telemetry.memorySweepError || "") : ""
  function gib(value) { return typeof value === "number" && value >= 0 ? (value / 1024).toFixed(1) + " GiB" : "—" }

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  padding: 12
  contentWidth: fittedContentWidth(320)
  contentHeight: fittedContentHeight(panelColumn.implicitHeight)

  property var acquiredTelemetry: null
  function syncHardwareLease() {
    const next = open ? telemetry : null
    if (acquiredTelemetry === next) return
    if (acquiredTelemetry) acquiredTelemetry.release("memoryPanel")
    acquiredTelemetry = next
    if (next) next.acquire("memoryPanel")
  }
  onTelemetryChanged: syncHardwareLease()
  onOpenChanged: { syncHardwareLease(); if (!open) sweepSource = null }
  Component.onCompleted: syncHardwareLease()
  Component.onDestruction: if (acquiredTelemetry) acquiredTelemetry.release("memoryPanel")

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }

    Column {
      id: panelColumn
      width: parent.width
      spacing: 8

      Item {
        width: parent.width
        height: 24

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: panel.sweepVisible ? "MEMORY / SWEEP" : "MEMORY"
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 13
          font.letterSpacing: 2
          font.weight: Font.Medium
          renderType: Text.NativeRendering
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "\u2715"
          color: closeMouse.containsMouse
            ? panel.controlAccent : panel.controlMuted
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 12
          renderType: Text.NativeRendering

          Behavior on color { ColorAnimation { duration: 120 } }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.ownerWidget.close()
          }
        }
      }

      Text {
        id: hardwareInfo
        width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
        text: panel.telemetry ? panel.telemetry.memoryHardwareInfo : ""
        visible: text.length > 0
        color: panel.controlMutedHigh; renderType: Text.NativeRendering
        font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
          panel.bar.foreground.b, 0.18) : Commons.Color.popups.border
      }

      Row {
        visible: !panel.sweepVisible
        width: parent.width
        height: memoryRing.height
        spacing: Commons.Style.space(16)

        // Panel-local dimensions and colors; MemoryRing's bar defaults stay intact.
        MemoryRing {
          id: memoryRing
          width: Commons.Style.space(80)
          height: width
          percent: panel.telemetry ? panel.telemetry.memPercent : 0
          foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          accent: panel.bar ? panel.bar.urgent : Commons.Color.accent
          water: true
          panelOpen: panel.open
        }

        Grid {
          width: parent.width - memoryRing.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          columns: 2; columnSpacing: Commons.Style.space(8); rowSpacing: Commons.Style.space(8)
          MemoryStatRow { width: (parent.width - parent.columnSpacing) / 2; label: "Usage"; value: memoryRing.percent + "%"; bar: panel.bar }
          MemoryStatRow {
            width: (parent.width - parent.columnSpacing) / 2
            label: "Used"
            value: (panel.telemetry ? panel.telemetry.memUsedGiB : 0).toFixed(1) + " GiB"
            bar: panel.bar
          }
          MemoryStatRow {
            width: (parent.width - parent.columnSpacing) / 2
            label: "Available"
            value: ((panel.telemetry ? panel.telemetry.memAvailableMiB : 0) / 1024).toFixed(1) + " GiB"
            bar: panel.bar
          }
          MemoryStatRow {
            width: (parent.width - parent.columnSpacing) / 2
            label: "Total"
            value: (panel.telemetry ? panel.telemetry.memTotalGiB : 0).toFixed(1) + " GiB"
            bar: panel.bar
          }
        }
      }

      Rectangle {
        visible: !panel.sweepVisible
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Column {
        visible: panel.sweepVisible
        width: parent.width
        height: 50
        SweepChoice {
          label: "Page cache"; value: panel.gib(panel.telemetry ? panel.telemetry.memCachedMiB + panel.telemetry.memBuffersMiB : -1)
          detail: "no guaranteed gain"; checked: panel.cacheSelected
          onToggled: panel.cacheSelected = !panel.cacheSelected
        }
        SweepChoice {
          label: "Compact memory"; value: "—"; detail: "no size estimate"
          checked: panel.compactSelected
          onToggled: panel.compactSelected = !panel.compactSelected
        }
      }
      SweepLabel {
        visible: panel.sweepVisible
        width: parent.width; height: 13; font.pixelSize: 10
        text: "Available: " + panel.gib(panel.sweepAvailable && panel.telemetry.memorySweepBeforeMiB >= 0
          ? panel.telemetry.memorySweepBeforeMiB : panel.telemetry ? panel.telemetry.memAvailableMiB : -1)
          + " → " + panel.gib(panel.sweepAvailable ? panel.telemetry.memorySweepAfterMiB : -1)
      }
      SweepLabel {
        visible: panel.sweepVisible
        width: parent.width; height: 10; font.pixelSize: 9
        text: panel.sweepError || (panel.sweepRunning ? "Authorizing / sweeping…" : "One authorization in the Omarchy dialog · no terminal")
        color: panel.sweepError ? panel.controlAccent : panel.controlMutedHigh
        elide: Text.ElideRight
      }
      Row {
        width: parent.width; height: 28; spacing: 8
        MemoryAction {
          label: panel.sweepVisible ? "Back" : "Open btop"
          onTriggered: {
            if (panel.sweepVisible) panel.sweepSource = null
            else { panel.ownerWidget.close(); panel.ownerWidget.openSystemMonitor() }
          }
        }
        MemoryAction {
          label: "Sweep"
          enabled: panel.sweepAvailable && (!panel.sweepVisible || (!panel.sweepRunning
            && (panel.cacheSelected || panel.compactSelected)))
          onTriggered: {
            if (!panel.sweepAvailable) return
            if (!panel.sweepVisible) {
              panel.telemetry.clearMemorySweepResult()
              panel.cacheSelected = true; panel.compactSelected = true
              panel.sweepSource = panel.telemetry
            } else panel.telemetry.startMemorySweep(panel.cacheSelected, panel.compactSelected)
          }
        }
      }
    }
  }

  component SweepLabel: Text {
    color: panel.controlForeground
    font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: 11
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
  }

  component SweepChoice: Item {
    id: choice
    required property string label
    required property string value
    required property string detail
    required property bool checked
    signal toggled()
    width: parent.width; height: 25
    enabled: !panel.sweepRunning
    Rectangle {
      y: 2; width: 12; height: 12
      radius: Math.min(height / 2, panel.controlRadius)
      color: choice.checked ? panel.controlAccent : panel.controlFillColor
      border.width: 1; border.color: choice.checked ? panel.controlAccent : panel.controlBorderColor
      SweepLabel { anchors.centerIn: parent; text: choice.checked ? "✓" : ""; font.pixelSize: 10; color: panel.bar ? panel.bar.background : Commons.Color.background }
    }
    SweepLabel { x: 20; width: parent.width - 88; text: choice.label; elide: Text.ElideRight }
    SweepLabel { anchors.right: parent.right; text: choice.value }
    SweepLabel { x: 20; y: 13; width: parent.width - 20; text: choice.detail; font.pixelSize: 9; color: panel.controlMutedHigh; elide: Text.ElideRight }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: choice.toggled() }
  }

  component MemoryAction: Rectangle {
    id: action
    required property string label
    signal triggered()
    width: (parent.width - 8) / 2; height: 28
    radius: panel.renderedSurfaceRadius
    opacity: enabled ? 1 : 0.45
    color: actionMouse.containsMouse ? panel.controlPrimaryHoverColor
      : panel.bar ? panel.bar.urgent : Commons.Color.accent
    Behavior on color { ColorAnimation { duration: 120 } }
    SweepLabel { anchors.centerIn: parent; text: action.label; color: panel.bar ? panel.bar.background : Commons.Color.background }
    MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: action.triggered() }
  }

  component MemoryStatRow: Item {
    required property string label
    required property string value
    required property var bar
    implicitHeight: valueText.height + Commons.Style.space(3) + labelText.height

    Text {
      id: labelText
      y: valueText.height + Commons.Style.space(3); width: parent.width
      text: parent.label.toUpperCase()
      color: parent.bar ? Qt.rgba(parent.bar.foreground.r, parent.bar.foreground.g,
        parent.bar.foreground.b, 0.65) : Commons.Color.foreground
      font.family: parent.bar ? parent.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      renderType: Text.NativeRendering
    }
    Text {
      id: valueText
      width: parent.width
      text: parent.value
      color: parent.bar ? parent.bar.foreground : Commons.Color.foreground
      font.family: parent.bar ? parent.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.subtitle
      renderType: Text.NativeRendering
    }
  }
}
