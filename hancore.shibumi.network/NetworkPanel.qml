pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var networkService

  property bool savedOnly: false
  property bool speedDetailsVisible: false
  property string expandedKey: ""
  property string passwordKey: ""
  property string passwordText: ""
  property string identityText: ""
  property var credentialDisplayNetworks: []
  property string credentialSsid: ""
  property var credentialSecurity: null
  property string credentialError: ""
  property Item credentialEditor: null
  property string pendingForgetKey: ""
  property int cursorIndex: -1
  readonly property bool wifiControlsVisible: networkService
    && networkService.wifiAvailable === true
  readonly property var displayNetworks: filteredNetworks()
  readonly property var presentedNetworks: passwordKey !== ""
    ? credentialDisplayNetworks : displayNetworks
  readonly property bool credentialEditorFocused: !!(credentialEditor
    && credentialEditor.activeFocus)
  readonly property bool panelKeyboardFocusActive: keyCatcher.activeFocus
  readonly property int savedCount: {
    let count = 0
    const rows = networkService ? networkService.networks : []
    for (let i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].known === true) count++
    }
    return count
  }

  owner: ownerWidget
  open: ownerWidget.opened && networkService && networkService.ready
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(380))
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    Commons.Style.space(680))

  function filteredNetworks() {
    const result = []
    if (!wifiControlsVisible) return result
    const rows = networkService ? networkService.networks : []
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i]
      if (!row) continue
      if (savedOnly ? row.known === true : row.visible !== false) result.push(row)
    }
    return result
  }

  function entryKey(entry) { return entry ? String(entry.entryKey || "") : "" }
  function canForget(entry) { return !!entry && entry.known === true }

  function signalIcon(value) {
    const signal = Number(value || 0)
    if (signal <= 0) return "\uE1DA"
    if (signal < 22) return "\uEBE4"
    if (signal < 44) return "\uEBD6"
    if (signal < 66) return "\uEBE1"
    return "\uF065"
  }

  function statusText() {
    if (!networkService.backendAvailable) return "NetworkManager unavailable"
    if (wifiControlsVisible && !networkService.wifiEnabled
        && networkService.kind === "disconnected")
      return "Wi-Fi disabled"
    if (networkService.kind === "wifi") return networkService.label || "Wi-Fi connected"
    if (networkService.kind === "ethernet") return ethernetAddress()
    return "Offline"
  }

  function ethernetAddress() {
    const info = networkService.info || ({})
    if (!info.ip) return networkService.label || "Ethernet connected"
    return String(info.ip) + (info.prefix ? "/" + info.prefix : "")
  }

  function statusMeta() {
    const info = networkService.info || ({})
    const fields = []
    if (networkService.kind === "wifi") fields.push("Wi-Fi")
    else if (networkService.kind === "ethernet") fields.push("Ethernet")
    if (info.iface) fields.push(String(info.iface))
    if (networkService.kind !== "ethernet" && info.ip)
      fields.push(String(info.ip) + (info.prefix ? "/" + info.prefix : ""))
    if (networkService.kind === "wifi" && networkService.signalStrength >= 0)
      fields.push(networkService.signalStrength + "% signal")
    return fields.join(" · ")
  }

  function frequencyText() {
    const raw = String((networkService.info || ({})).freq || "").trim()
    if (!raw) return ""
    return /[a-z]/i.test(raw) ? raw : raw + " MHz"
  }

  function linkSpeedText() {
    const info = networkService.info || ({})
    if (networkService.kind === "wifi") return String(info.bitrate || "").trim()
    const raw = String(info.speed || "").trim()
    if (!raw) return ""
    const speed = Number(raw)
    if (!isFinite(speed) || speed <= 0) return raw
    return speed >= 1000
      ? (speed / 1000).toFixed(speed % 1000 === 0 ? 0 : 1) + " Gbit/s"
      : speed + " Mbit/s"
  }

  function metadata(entry) {
    if (!entry) return ""
    const fields = [String(entry.securityLabel || "Unknown")]
    if (entry.visible !== false) fields.push("Signal " + Math.round(entry.signal || 0) + "%")
    if (entry.known) fields.push("Saved")
    if (entry.visible === false) fields.push("Not currently visible")
    return fields.join(" · ")
  }

  function toggleExpanded(entry) {
    const key = entryKey(entry)
    expandedKey = expandedKey === key ? "" : key
    if (expandedKey !== key || passwordKey !== key) clearPassword()
  }

  function clearPassword() {
    const restorePanelFocus = passwordKey !== "" && open
    passwordKey = ""
    passwordText = ""
    identityText = ""
    credentialDisplayNetworks = []
    credentialSsid = ""
    credentialSecurity = null
    credentialError = ""
    credentialEditor = null
    if (restorePanelFocus) requestPanelKeyboardFocus(keyCatcher)
  }

  function openPassword(entry) {
    credentialDisplayNetworks = displayNetworks.slice()
    credentialSsid = String(entry && entry.ssid || "")
    credentialSecurity = entry ? entry.security : null
    credentialError = ""
    expandedKey = entryKey(entry)
    passwordKey = expandedKey
    passwordText = ""
    identityText = ""
  }

  function currentCredentialRow() {
    let result = null
    let count = 0
    const rows = displayNetworks
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i]
      if (!row || row.visible === false
          || String(row.ssid || "") !== credentialSsid
          || row.security !== credentialSecurity) continue
      result = row
      count++
    }
    return count === 1 ? result : null
  }

  function evaluateCredentialCompletion() {
    if (passwordKey === "") return
    const current = currentCredentialRow()
    if (current && current.connected === true) clearPassword()
  }

  function requestPanelKeyboardFocus(target) {
    if (!open || !target) return
    if (typeof requestKeyboardFocus === "function") {
      requestKeyboardFocus(target)
      return
    }
    Qt.callLater(function() {
      if (panel.open && target) target.forceActiveFocus()
    })
  }

  function registerCredentialEditor(editor) {
    if (!editor) return
    credentialEditor = editor
    requestPanelKeyboardFocus(editor)
  }

  function credentialEditorFocusChanged(editor, active) {
    if (!editor) return
    if (active) {
      credentialEditor = editor
      return
    }
    Qt.callLater(function() {
      if (panel.open && panel.passwordKey !== ""
          && panel.credentialEditor === editor && editor.visible
          && !editor.activeFocus && keyCatcher.activeFocus)
        panel.requestPanelKeyboardFocus(editor)
    })
  }

  function openNetworkSettings() {
    ownerWidget.close()
    if (bar && typeof bar.run === "function")
      bar.run("omarchy-launch-or-focus-tui nmtui")
  }

  function needsCredentials(entry) {
    return !!entry && !entry.known
      && (entry.securityKind === "psk"
        || entry.securityKind === "enterprise")
  }

  function needsNetworkSettings(entry) {
    return !!entry && !entry.known && !needsCredentials(entry)
      && entry.securityKind !== "open"
  }

  function runPrimary(entry) {
    if (!entry || networkService.busy) return
    if (entry.connected) {
      networkService.disconnect(entry)
      return
    }
    if (needsCredentials(entry)) {
      openPassword(entry)
      return
    }
    if (needsNetworkSettings(entry)) {
      openNetworkSettings()
      return
    }
    networkService.connect(entry)
  }

  function submitPassword(entry) {
    if (!entry || !passwordText || networkService.busy) return false
    let accepted = false
    if (entry.securityKind === "enterprise") {
      if (!identityText) return false
      accepted = networkService.connectEnterprise(
        entry, identityText, passwordText)
    } else {
      accepted = networkService.connectWithPassphrase(entry, passwordText)
    }
    if (!accepted)
      credentialError = "Network changed. Select it again."
    return accepted
  }

  function requestForget(entry) {
    const key = entryKey(entry)
    if (!key || !canForget(entry)) return
    if (pendingForgetKey === key) {
      pendingForgetKey = ""
      forgetTimer.stop()
      networkService.forget(entry)
      return
    }
    pendingForgetKey = key
    forgetTimer.restart()
  }

  function moveCursor(delta) {
    if (displayNetworks.length === 0) {
      cursorIndex = -1
      return
    }
    cursorIndex = Math.max(0, Math.min(displayNetworks.length - 1,
      cursorIndex < 0 ? (delta > 0 ? 0 : displayNetworks.length - 1)
        : cursorIndex + delta))
  }

  function activateCursor() {
    if (cursorIndex < 0 || cursorIndex >= displayNetworks.length) return
    toggleExpanded(displayNetworks[cursorIndex])
  }

  onSavedOnlyChanged: {
    expandedKey = ""
    clearPassword()
    cursorIndex = displayNetworks.length > 0 ? 0 : -1
  }

  onDisplayNetworksChanged: {
    if (cursorIndex >= displayNetworks.length) cursorIndex = displayNetworks.length - 1
    if (displayNetworks.length === 0) cursorIndex = -1
    if (passwordKey !== "")
      Qt.callLater(function() { panel.evaluateCredentialCompletion() })
  }

  onOpenChanged: {
    if (open) {
      speedDetailsVisible = networkService.speedTestRunning
      cursorIndex = displayNetworks.length > 0 ? 0 : -1
    } else {
      savedOnly = false
      expandedKey = ""
      pendingForgetKey = ""
      speedDetailsVisible = false
      clearPassword()
      forgetTimer.stop()
    }
  }

  property Connections networkConnections: Connections {
    target: panel.networkService

    function onActionKindChanged() {
      if (!panel.networkService || panel.networkService.actionKind !== ""
          || panel.passwordKey === "") return
      Qt.callLater(function() { panel.evaluateCredentialCompletion() })
    }
  }

  property Timer forgetTimer: Timer {
    id: forgetTimer
    interval: 5000
    onTriggered: panel.pendingForgetKey = ""
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: panel.passwordKey !== ""
    onActiveFocusChanged: {
      if (activeFocus && panel.passwordKey !== ""
          && panel.credentialEditor) Qt.callLater(function() {
        if (keyCatcher.activeFocus && panel.open
            && panel.passwordKey !== "" && panel.credentialEditor)
          panel.requestPanelKeyboardFocus(panel.credentialEditor)
      })
    }
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }
    onMoveRequested: function(_dx, dy) {
      if (dy !== 0) panel.moveCursor(dy)
    }
    onActivateRequested: panel.activateCursor()

    Flickable {
      id: scroller
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: scroller.width
        spacing: Commons.Style.space(8)

        Row {
          width: parent.width
          spacing: Commons.Style.space(4)

          Text {
            width: parent.width - headerActions.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: "Network"
            color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.heading
            font.letterSpacing: 2
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          Row {
            id: headerActions
            spacing: Commons.Style.space(2)

            IconAction {
              visible: panel.wifiControlsVisible
              icon: panel.networkService.scanning ? "sync" : "refresh"
              tooltip: "Rescan Wi-Fi"
              enabled: panel.networkService.wifiAvailable
                && panel.networkService.wifiEnabled
              onClicked: panel.networkService.refresh(true)
            }

            IconAction {
              icon: "close"
              tooltip: "Close"
              onClicked: panel.ownerWidget.close()
            }
          }
        }

        Ui.PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Commons.Style.space(3)

          Row {
            width: parent.width
            spacing: Commons.Style.space(8)

            Item {
              visible: panel.networkService.kind === "ethernet"
              anchors.verticalCenter: parent.verticalCenter
              width: 20
              height: 20

              Image {
                id: ethernetIconSource
                anchors.fill: parent
                visible: false
                source: Qt.resolvedUrl("lan.svg")
                sourceSize: Qt.size(20, 20)
                fillMode: Image.PreserveAspectFit
                smooth: false
                mipmap: false
              }

              MultiEffect {
                anchors.fill: parent
                source: ethernetIconSource
                colorization: 1
                colorizationColor: panel.bar
                  ? panel.bar.urgent : Commons.Color.accent
              }
            }

            IconText {
              visible: panel.networkService.kind !== "ethernet"
              anchors.verticalCenter: parent.verticalCenter
              text: panel.networkService.kind === "wifi"
                ? panel.signalIcon(panel.networkService.signalStrength)
                : "\uE2C1"
              color: panel.bar ? panel.bar.urgent : Commons.Color.accent
              font.pixelSize: Commons.Style.font.heading
              font.hintingPreference: Font.PreferFullHinting
              renderType: Text.NativeRendering
              fill: 1
            }

            Text {
              width: parent.width - x
              anchors.verticalCenter: parent.verticalCenter
              text: panel.statusText()
              color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.body
              font.weight: Font.Medium
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: panel.statusMeta()
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Commons.Style.space(6)
          rowSpacing: Commons.Style.space(4)

          DetailCell {
            width: (contentColumn.width - parent.columnSpacing) / 2
            label: "PING"
            value: panel.networkService.internetPingLatency >= 0
              ? panel.networkService.formatPing(panel.networkService.internetPingLatency)
              : "--"
          }
          DetailCell {
            width: (contentColumn.width - parent.columnSpacing) / 2
            label: "GATEWAY"
            value: String(panel.networkService.info.gateway || "--")
          }
          DetailCell {
            width: (contentColumn.width - parent.columnSpacing) / 2
            label: "DOWNLOAD"
            value: panel.networkService.formatRate(panel.networkService.downloadRate)
          }
          DetailCell {
            width: (contentColumn.width - parent.columnSpacing) / 2
            label: "UPLOAD"
            value: panel.networkService.formatRate(panel.networkService.uploadRate)
          }
          DetailCell {
            width: (contentColumn.width - parent.columnSpacing) / 2
            visible: panel.frequencyText() !== ""
            label: "FREQUENCY"
            value: panel.frequencyText()
          }
          DetailCell {
            width: (contentColumn.width - parent.columnSpacing) / 2
            visible: panel.linkSpeedText() !== ""
            label: "LINK SPEED"
            value: panel.linkSpeedText()
          }
        }

        Ui.PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Commons.Style.space(6)

          Row {
            width: parent.width

            SectionLabel {
              width: parent.width - speedButton.width
              anchors.verticalCenter: parent.verticalCenter
              text: "SPEED TEST"
            }

            PanelButton {
              id: speedButton
              width: Commons.Style.space(86)
              label: panel.networkService.speedTestRunning ? "Running..." : "Run test"
              enabled: !panel.networkService.speedTestRunning
                && panel.networkService.kind !== "disconnected"
              onClicked: {
                panel.speedDetailsVisible = true
                panel.networkService.runSpeedTest()
              }
            }
          }

          Row {
            width: parent.width
            spacing: Commons.Style.space(6)
            visible: panel.speedDetailsVisible

            DetailCell {
              width: (parent.width - 2 * parent.spacing) / 3
              label: "PING"
              value: panel.networkService.speedTestRunning
                && panel.networkService.speedTestPhase === "down" ? "Testing..."
                : panel.networkService.formatPing(panel.networkService.internetPingLatency)
            }
            DetailCell {
              width: (parent.width - 2 * parent.spacing) / 3
              label: "DOWNLOAD"
              value: panel.networkService.speedTestRunning
                && panel.networkService.speedTestPhase === "down" ? "Testing..."
                : panel.networkService.formatSpeed(panel.networkService.speedTestDownloadMbps)
            }
            DetailCell {
              width: (parent.width - 2 * parent.spacing) / 3
              label: "UPLOAD"
              value: panel.networkService.speedTestRunning
                && panel.networkService.speedTestPhase === "up" ? "Testing..."
                : panel.networkService.formatSpeed(panel.networkService.speedTestUploadMbps)
            }
          }

          Text {
            width: parent.width
            visible: panel.speedDetailsVisible
              && panel.networkService.speedTestError !== ""
            text: panel.networkService.speedTestError
            color: panel.bar ? panel.bar.urgent : Commons.Color.accent
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            wrapMode: Text.Wrap
          }
        }

        Ui.PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Commons.Style.space(5)

          SectionLabel { text: "DNS" }

          Row {
            width: parent.width
            spacing: Commons.Style.space(4)

            Repeater {
              model: panel.networkService.dnsProviders

              PanelButton {
                required property var modelData
                width: (contentColumn.width - 3 * Commons.Style.space(4)) / 4
                label: String(modelData)
                current: panel.networkService.dnsProvider === String(modelData)
                onClicked: {
                  panel.networkService.setDns(String(modelData))
                  if (String(modelData) === "Custom") panel.ownerWidget.close()
                }
              }
            }
          }
        }

        Ui.PanelSeparator {
          width: parent.width
          visible: panel.wifiControlsVisible
        }

        Row {
          width: parent.width
          height: Commons.Style.space(24)
          visible: panel.wifiControlsVisible

          Text {
            width: parent.width - wifiToggle.width
            anchors.verticalCenter: parent.verticalCenter
            text: "Wi-Fi"
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            renderType: Text.NativeRendering
          }

          PanelButton {
            id: wifiToggle
            width: Commons.Style.space(50)
            height: Commons.Style.space(22)
            label: panel.networkService.wifiEnabled ? "ON" : "OFF"
            current: panel.networkService.wifiEnabled
            enabled: panel.networkService.backendAvailable
            onClicked: panel.networkService.toggleWifi()
          }
        }

        Row {
          width: parent.width
          spacing: Commons.Style.space(4)
          visible: panel.wifiControlsVisible

          PanelButton {
            width: (parent.width - parent.spacing) / 2
            label: "Available"
            current: !panel.savedOnly
            onClicked: {
              panel.savedOnly = false
              panel.networkService.refresh(true)
            }
          }

          PanelButton {
            width: (parent.width - parent.spacing) / 2
            label: "Saved" + (panel.savedCount > 0 ? " (" + panel.savedCount + ")" : "")
            current: panel.savedOnly
            onClicked: panel.savedOnly = true
          }
        }

        Row {
          width: parent.width
          visible: panel.wifiControlsVisible

          SectionLabel {
            width: parent.width - scanState.width
            text: panel.savedOnly ? "SAVED NETWORKS" : "AVAILABLE NETWORKS"
          }

          Text {
            id: scanState
            text: panel.networkService.scanning ? "Scanning..." : ""
            color: panel.bar ? panel.bar.urgent : Commons.Color.accent
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
          }
        }

        Column {
          width: parent.width
          spacing: Commons.Style.space(3)
          visible: panel.wifiControlsVisible

          Repeater {
            // Scanner/signal updates replace the service's JS array. Keep the
            // delegate containing an active credential editor alive until the
            // editor closes, while actions still revalidate against live rows.
            model: panel.presentedNetworks

            Ui.CursorSurface {
              id: networkRow
              required property var modelData
              required property int index
              readonly property string key: panel.entryKey(modelData)
              readonly property bool expanded: panel.expandedKey === key
              readonly property bool passwordOpen: panel.passwordKey === key
              readonly property bool enterpriseCredentials:
                modelData.securityKind === "enterprise"
              readonly property bool actionRunning:
                panel.networkService.actionSsid === String(modelData.ssid || "")
                || (modelData.profileUuid && panel.networkService.busy)
              width: contentColumn.width
              height: rowColumn.implicitHeight + Commons.Style.space(12)
              radius: panel.controlRadius
              hasCursor: panel.cursorIndex === index
              current: modelData.connected === true
              bordered: expanded
              foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
              accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

              Column {
                id: rowColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Commons.Style.space(8)
                anchors.rightMargin: Commons.Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Commons.Style.space(5)

                Row {
                  width: parent.width
                  spacing: Commons.Style.space(7)

                  IconText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: networkRow.modelData.visible === false ? "bookmark"
                      : panel.signalIcon(networkRow.modelData.signal)
                    color: panel.bar ? (networkRow.modelData.connected
                      ? panel.bar.urgent : panel.bar.foreground) : Commons.Color.accent
                    opacity: networkRow.modelData.visible === false ? 0.58 : 1
                    font.pixelSize: Commons.Style.font.body
                    fill: 1
                  }

                  Text {
                    width: parent.width - x - expandIcon.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(networkRow.modelData.ssid || "Hidden network")
                    color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
                    font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.body
                    font.weight: networkRow.modelData.connected ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                  }

                  IconText {
                    id: expandIcon
                    anchors.verticalCenter: parent.verticalCenter
                    text: networkRow.expanded ? "expand_less" : "expand_more"
                    color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
                    opacity: 0.55
                    font.pixelSize: Commons.Style.font.body
                    fill: 1
                  }
                }

                Text {
                  width: parent.width
                  visible: networkRow.expanded
                  text: panel.metadata(networkRow.modelData)
                  color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
                    panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
                    : Commons.Color.foreground
                  font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                  font.pixelSize: Commons.Style.font.caption
                  wrapMode: Text.Wrap
                  renderType: Text.NativeRendering
                }

                Text {
                  width: parent.width
                  visible: networkRow.expanded
                    && panel.networkService.failureSsid === networkRow.modelData.ssid
                    && panel.networkService.failureReason !== ""
                  text: panel.networkService.failureReason
                  color: panel.bar ? panel.bar.urgent : Commons.Color.accent
                  font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                  font.pixelSize: Commons.Style.font.caption
                  wrapMode: Text.Wrap
                }

                Text {
                  width: parent.width
                  visible: networkRow.expanded
                    && panel.networkService.profileError !== ""
                    && networkRow.modelData.profileUuid !== ""
                  text: panel.networkService.profileError
                  color: panel.bar ? panel.bar.urgent : Commons.Color.accent
                  font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                  font.pixelSize: Commons.Style.font.caption
                  wrapMode: Text.Wrap
                }

                Row {
                  width: parent.width
                  spacing: Commons.Style.space(5)
                  visible: networkRow.expanded && !networkRow.passwordOpen

                  PanelButton {
                    width: parent.width - (forgetButton.visible
                      ? forgetButton.width + parent.spacing : 0)
                    label: networkRow.actionRunning
                      ? (networkRow.modelData.connected ? "Disconnecting..." : "Connecting...")
                      : networkRow.modelData.connected ? "Disconnect"
                      : panel.needsNetworkSettings(networkRow.modelData)
                        ? "Open network settings" : "Connect"
                    enabled: !panel.networkService.busy
                    onClicked: panel.runPrimary(networkRow.modelData)
                  }

                  PanelButton {
                    id: forgetButton
                    visible: panel.canForget(networkRow.modelData)
                    width: Commons.Style.space(92)
                    label: panel.pendingForgetKey === networkRow.key
                      ? "Confirm" : "Forget"
                    urgent: true
                    onClicked: panel.requestForget(networkRow.modelData)
                  }
                }

                Column {
                  width: parent.width
                  spacing: Commons.Style.space(5)
                  visible: networkRow.passwordOpen

                  TextField {
                    id: identityField
                    width: parent.width
                    height: Commons.Style.space(30)
                    visible: networkRow.passwordOpen
                      && networkRow.enterpriseCredentials
                    text: panel.identityText
                    placeholderText: "Identity (user@domain)"
                    color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
                    placeholderTextColor: panel.bar ? Qt.rgba(panel.bar.foreground.r,
                      panel.bar.foreground.g, panel.bar.foreground.b, 0.42)
                      : Commons.Color.foreground
                    font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.body
                    selectByMouse: true
                    onTextChanged: panel.identityText = text
                    onAccepted: passwordField.forceActiveFocus()
                    Keys.onEscapePressed: panel.clearPassword()
                    onActiveFocusChanged:
                      panel.credentialEditorFocusChanged(identityField,
                        activeFocus)
                    onVisibleChanged: {
                      if (visible) panel.registerCredentialEditor(identityField)
                      else if (panel.credentialEditor === identityField)
                        panel.credentialEditor = null
                    }
                    Component.onCompleted: if (visible)
                      panel.registerCredentialEditor(identityField)
                    Component.onDestruction: if (panel.credentialEditor === identityField)
                      panel.credentialEditor = null
                    background: Rectangle {
                      radius: panel.controlRadius
                      color: identityField.activeFocus
                        ? panel.controlHoverFillColor : panel.controlFillColor
                      border.width: panel.controlBorderWidth
                      border.color: identityField.activeFocus
                        ? panel.controlHoverBorderColor
                        : panel.controlBorderColor
                    }
                  }

                  Text {
                    width: parent.width
                    visible: panel.credentialError !== ""
                    text: panel.credentialError
                    color: panel.bar ? panel.bar.urgent : Commons.Color.accent
                    font.family: panel.bar
                      ? panel.bar.fontFamily : Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.caption
                    wrapMode: Text.Wrap
                  }

                  Row {
                    width: parent.width
                    spacing: Commons.Style.space(5)

                    TextField {
                      id: passwordField
                      width: parent.width - connectPassword.width - cancelPassword.width
                        - 2 * parent.spacing
                      height: Commons.Style.space(30)
                      visible: networkRow.passwordOpen
                      text: panel.passwordText
                      placeholderText: networkRow.enterpriseCredentials
                        ? "Enterprise password" : "Wi-Fi password"
                      echoMode: TextInput.Password
                      color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
                      placeholderTextColor: panel.bar ? Qt.rgba(panel.bar.foreground.r,
                        panel.bar.foreground.g, panel.bar.foreground.b, 0.42)
                        : Commons.Color.foreground
                      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                      font.pixelSize: Commons.Style.font.body
                      selectByMouse: true
                      onTextChanged: panel.passwordText = text
                      onAccepted: panel.submitPassword(networkRow.modelData)
                      Keys.onEscapePressed: panel.clearPassword()
                      onActiveFocusChanged:
                        panel.credentialEditorFocusChanged(passwordField,
                          activeFocus)
                      onVisibleChanged: {
                        if (visible && !networkRow.enterpriseCredentials)
                          panel.registerCredentialEditor(passwordField)
                        else if (!visible
                            && panel.credentialEditor === passwordField)
                          panel.credentialEditor = null
                      }
                      Component.onCompleted: if (visible
                          && !networkRow.enterpriseCredentials)
                        panel.registerCredentialEditor(passwordField)
                      Component.onDestruction: if (panel.credentialEditor === passwordField)
                        panel.credentialEditor = null
                      background: Rectangle {
                        radius: panel.controlRadius
                        color: passwordField.activeFocus
                          ? panel.controlHoverFillColor : panel.controlFillColor
                        border.width: panel.controlBorderWidth
                        border.color: passwordField.activeFocus
                          ? panel.controlHoverBorderColor
                          : panel.controlBorderColor
                      }
                    }

                    PanelButton {
                      id: connectPassword
                      width: Commons.Style.space(66)
                      label: panel.networkService.busy ? "Wait" : "Connect"
                      enabled: panel.passwordText !== ""
                        && (!networkRow.enterpriseCredentials
                          || panel.identityText !== "")
                        && panel.credentialError === ""
                        && !panel.networkService.busy
                      onClicked: panel.submitPassword(networkRow.modelData)
                    }

                    PanelButton {
                      id: cancelPassword
                      width: Commons.Style.space(54)
                      label: "Cancel"
                      onClicked: panel.clearPassword()
                    }
                  }
                }
              }

              MouseArea {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: Commons.Style.space(34)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: panel.cursorIndex = networkRow.index
                onClicked: panel.toggleExpanded(networkRow.modelData)
              }
            }
          }

          Text {
            width: parent.width
            visible: panel.wifiControlsVisible
              && panel.displayNetworks.length === 0
            text: panel.savedOnly
              ? (panel.networkService.profilesLoaded
                ? "No saved networks" : "Loading saved networks...")
              : panel.networkService.wifiEnabled
                ? "No networks found" : "Wi-Fi is disabled"
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            horizontalAlignment: Text.AlignHCenter
            topPadding: Commons.Style.space(10)
            bottomPadding: Commons.Style.space(10)
          }
        }

        PanelButton {
          width: parent.width
          label: "Network settings"
          primary: true
          onClicked: panel.openNetworkSettings()
        }
      }
    }
  }

  component SectionLabel: Text {
    color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
      panel.bar.foreground.g, panel.bar.foreground.b, 0.52)
      : Commons.Color.foreground
    font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    font.letterSpacing: 1
    renderType: Text.NativeRendering
  }

  component DetailCell: Column {
    property string label: ""
    property string value: ""
    spacing: Commons.Style.space(1)

    Text {
      width: parent.width
      text: parent.label
      color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
        panel.bar.foreground.g, panel.bar.foreground.b, 0.45)
        : Commons.Color.foreground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      font.letterSpacing: 0.6
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    Text {
      width: parent.width
      text: parent.value
      color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.body
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }
  }

  component PanelButton: Rectangle {
    id: button
    property string label: ""
    property bool current: false
    property bool primary: false
    property bool urgent: false
    signal clicked()
    readonly property bool hovered: buttonMouse.containsMouse && enabled
    readonly property color actionColor: panel.bar
      ? panel.bar.urgent : Commons.Color.accent
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    opacity: enabled ? 1 : 0.42
    color: primary
      ? (hovered ? panel.controlPrimaryHoverColor : actionColor)
      : current ? panel.controlActiveFillColor
        : hovered ? panel.controlHoverFillColor : panel.controlFillColor
    border.width: primary ? 0 : panel.controlBorderWidth
    border.color: current || hovered
      ? actionColor : panel.controlBorderColor

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      width: parent.width - Commons.Style.space(8)
      text: button.label
      color: !button.enabled
        ? Qt.rgba(panel.controlForeground.r, panel.controlForeground.g,
          panel.controlForeground.b, 0.35)
        : button.primary ? (panel.shibumiTokens
          ? panel.shibumiTokens.paper : Commons.Color.background)
        : button.current || button.hovered || button.urgent && button.hovered
          ? button.actionColor : panel.controlForeground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      font.weight: button.current ? Font.Medium : Font.Normal
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: button.enabled
      cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: button.clicked()
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    property bool accentAction: false
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

    IconText {
      anchors.centerIn: parent
      text: action.icon
      color: !action.enabled
        ? Qt.rgba(action.foreground.r, action.foreground.g, action.foreground.b, 0.3)
        : action.accentAction && panel.bar ? panel.bar.urgent : action.foreground
      font.pixelSize: Commons.Style.font.body
      fill: action.accentAction ? 1 : 0
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: action.enabled
      cursorShape: action.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
