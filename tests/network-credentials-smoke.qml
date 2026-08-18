pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Networking
import "network" as Network
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property int focusProbeStage: 0
  property int focusRequestCountBeforeLoss: 0
  property var focusEditor: null
  property var stalePskEntry: null
  property var staleEnterpriseEntry: null
  property var staleProfileEntry: null

  function fail(message) {
    console.error("network-credentials-smoke:", message)
    Qt.exit(1)
  }

  function entryFor(ssid) {
    return entryForService(service, ssid, "")
  }

  function entryForService(targetService, ssid, kind) {
    const rows = targetService ? targetService.networks : []
    for (let i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].visible !== false
          && rows[i].ssid === ssid
          && (!kind || rows[i].securityKind === kind)) return rows[i]
    }
    return null
  }

  function savedProfileRow(rows, uuid) {
    for (let i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].visible === false
          && rows[i].profileUuid === uuid) return rows[i]
    }
    return null
  }

  function visibleProfileRows(rows, ssid) {
    const result = []
    for (let i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].visible !== false && rows[i].ssid === ssid)
        result.push(rows[i])
    }
    return result
  }

  function visibleProfileRow(rows, ssid, kind) {
    const visibleRows = visibleProfileRows(rows, ssid)
    for (let i = 0; i < visibleRows.length; i++) {
      if (visibleRows[i].securityKind === kind) return visibleRows[i]
    }
    return null
  }

  Item {
    id: fakeBar
    visible: false
    width: 0
    height: 0
    property bool vertical: false
    property int barSize: 35
    property int sizeHorizontal: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var shell: null
    property var visualTokens: null
    property string lastRun: ""

    function registeredWidgetSource(_id) { return "" }
    function registeredWidgetComponent(_id) { return null }
    function widgetSettings(_group, _module) { return ({}) }
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function publishConnectedPanel(_owner, _screenName, _x, _reveal) {}
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return false }
    function run(command) { lastRun = String(command || "") }
  }

  Item { id: anchor; width: 24; height: 24 }

  Item {
    id: ownerWidget
    property bool opened: false
    property int closeCount: 0
    function close() { opened = false; closeCount++ }
    function switchPanel(_direction) { return false }
  }

  Component {
    id: backendComponent
    Fixtures.NetworkTestPanel {}
  }

  Network.Service {
    id: service
    bar: fakeBar
    panelComponent: backendComponent
  }

  Network.Service {
    id: unavailableProfileConnectService
    bar: fakeBar
    panelComponent: null
  }

  Network.Service {
    id: unavailableProfileForgetService
    bar: fakeBar
    panelComponent: null
  }

  Network.Service {
    id: profiledVisibleConnectService
    bar: fakeBar
    panelComponent: backendComponent
  }

  Network.Service {
    id: profiledVisibleForgetService
    bar: fakeBar
    panelComponent: backendComponent
  }

  Window {
    id: focusWindow
    width: 640
    height: 720
    visible: true

    Network.NetworkPanel {
      id: panel
      anchorItem: anchor
      bar: fakeBar
      ownerWidget: ownerWidget
      networkService: service
    }

    Item {
      id: focusThief
      width: 1
      height: 1
    }
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (!service.ready || !service.backend || root.ticks < 2) return
        service.backend.wifiNetworks = [
          {
            connected: false,
            known: false,
            ssid: "Open Fixture",
            signal: 52,
            security: WifiSecurityType.Open
          },
          {
            connected: false,
            known: false,
            ssid: "PSK Fixture",
            signal: 71,
            security: WifiSecurityType.Wpa2Psk
          },
          {
            connected: false,
            known: false,
            ssid: "SAE Fixture",
            signal: 69,
            security: WifiSecurityType.Sae
          },
          {
            connected: false,
            known: false,
            ssid: "Enterprise Fixture",
            signal: 65,
            security: WifiSecurityType.Wpa2Eap
          },
          {
            connected: false,
            known: false,
            ssid: "OWE Fixture",
            signal: 63,
            security: WifiSecurityType.Owe
          },
          {
            connected: false,
            known: false,
            ssid: "Suite B Fixture",
            signal: 62,
            security: WifiSecurityType.Wpa3SuiteB192
          },
          {
            connected: false,
            known: false,
            ssid: "LEAP Fixture",
            signal: 60,
            security: WifiSecurityType.Leap
          },
          {
            connected: true,
            known: true,
            ssid: "Connected Fixture",
            signal: 82,
            security: WifiSecurityType.Wpa2Psk
          },
          {
            connected: false,
            known: true,
            ssid: "Known Fixture",
            signal: 58,
            security: WifiSecurityType.Wpa2Psk
          }
        ]
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        const open = root.entryFor("Open Fixture")
        const psk = root.entryFor("PSK Fixture")
        const sae = root.entryFor("SAE Fixture")
        const enterprise = root.entryFor("Enterprise Fixture")
        const owe = root.entryFor("OWE Fixture")
        const suiteB = root.entryFor("Suite B Fixture")
        const leap = root.entryFor("LEAP Fixture")
        const connected = root.entryFor("Connected Fixture")
        const known = root.entryFor("Known Fixture")
        if (!open || !psk || !sae || !enterprise || !owe || !suiteB || !leap
            || !connected || !known) return
        if (open.network !== undefined || psk.network !== undefined
            || sae.network !== undefined || enterprise.network !== undefined
            || owe.network !== undefined || suiteB.network !== undefined
            || leap.network !== undefined || connected.network !== undefined
            || known.network !== undefined)
          return root.fail("view snapshots retain backend network objects")

        if (root.focusProbeStage === 0) {
          if (!service.connect(open)
              || service.backend.knownConnectCount !== 1
              || service.backend.knownConnectSsid !== "Open Fixture"
              || service.connect(psk))
            return root.fail("primitive open/protected connect routing")
          ownerWidget.opened = true
          panel.runPrimary(psk)
          if (panel.passwordKey !== psk.entryKey
              || panel.expandedKey !== psk.entryKey)
            return root.fail("PSK row did not open the existing password editor")
          root.focusProbeStage = 1
          root.ticks = 0
          return
        }

        if (root.focusProbeStage === 1) {
          if (!panel.credentialEditor || root.ticks < 1) return
          if (!panel.credentialEditorFocused)
            return root.fail("credential editor did not acquire active focus")
          root.focusEditor = panel.credentialEditor
          const credentialRows = panel.presentedNetworks
          panel.passwordText = "focus-probe"
          const refreshedRows = service.backend.wifiNetworks.slice()
          refreshedRows[1] = {
            connected: false,
            known: false,
            ssid: "PSK Fixture",
            signal: 70,
            security: WifiSecurityType.Wpa2Psk
          }
          service.backend.wifiNetworks = refreshedRows
          if (panel.presentedNetworks !== credentialRows)
            return root.fail("credential row model was replaced during editing")
          root.focusProbeStage = 2
          root.ticks = 0
          return
        }

        if (root.focusProbeStage === 2) {
          if (root.ticks < 1) return
          if (panel.credentialEditor !== root.focusEditor
              || !panel.credentialEditorFocused
              || panel.passwordText !== "focus-probe"
              || panel.passwordKey !== psk.entryKey)
            return root.fail("credential editor lost identity or focus on refresh")
          root.focusRequestCountBeforeLoss = panel.focusRequestCount
          focusThief.forceActiveFocus()
          root.focusProbeStage = 3
          root.ticks = 0
          return
        }

        if (root.focusProbeStage === 3) {
          if (root.ticks < 1) return
          if (!focusThief.activeFocus || panel.credentialEditorFocused
              || panel.focusRequestCount
                !== root.focusRequestCountBeforeLoss)
            return root.fail("credential editor stole intentional focus")
          panel.focusTarget.forceActiveFocus()
          root.focusProbeStage = 4
          root.ticks = 0
          return
        }

        if (root.focusProbeStage === 4) {
          if (root.ticks < 1) return
          if (panel.credentialEditor !== root.focusEditor
              || !panel.credentialEditorFocused
              || panel.focusRequestCount
                <= root.focusRequestCountBeforeLoss)
            return root.fail("credential editor did not recover panel focus")
          panel.passwordText = "psk-secret"
          if (!panel.submitPassword(psk)
              || service.backend.pskConnectCount !== 1
              || service.backend.pskSsid !== "PSK Fixture"
              || service.backend.pskPassphrase !== "psk-secret")
            return root.fail("primitive PSK credential forwarding")
          panel.clearPassword()
          root.focusProbeStage = 5
          root.ticks = 0
          return
        }

        if (root.ticks < 1) return
        if (root.focusProbeStage !== 5 || !panel.panelKeyboardFocusActive)
          return root.fail("panel keyboard focus was not restored after credentials")

        panel.runPrimary(sae)
        panel.passwordText = "sae-secret"
        panel.submitPassword(sae)
        if (panel.passwordKey !== sae.entryKey
            || service.backend.pskConnectCount !== 2
            || service.backend.pskSsid !== "SAE Fixture"
            || service.backend.pskPassphrase !== "sae-secret")
          return root.fail("primitive WPA3/SAE credential forwarding")

        panel.clearPassword()
        panel.runPrimary(enterprise)
        panel.identityText = "user@example.test"
        panel.passwordText = "enterprise-secret"
        panel.submitPassword(enterprise)
        if (panel.passwordKey !== enterprise.entryKey
            || service.backend.enterpriseConnectCount !== 1
            || service.backend.enterpriseSsid !== "Enterprise Fixture"
            || service.backend.enterpriseIdentity !== "user@example.test"
            || service.backend.enterprisePassphrase !== "enterprise-secret")
          return root.fail("primitive enterprise credential forwarding")

        if (!service.disconnect(connected)
            || service.backend.disconnectRowCount !== 1
            || service.backend.disconnectSsid !== "Connected Fixture")
          return root.fail("primitive connected-row disconnect routing")
        if (!service.forget(known)
            || service.backend.forgetCount !== 1
            || service.backend.forgetSsid !== "Known Fixture")
          return root.fail("primitive known-row forget routing")

        panel.runPrimary(owe)
        if (ownerWidget.closeCount !== 1
            || fakeBar.lastRun !== "omarchy-launch-or-focus-tui nmtui"
            || !panel.needsNetworkSettings(owe)
            || suiteB.securityKind !== "unsupported"
            || leap.securityKind !== "unsupported"
            || !panel.needsNetworkSettings(suiteB)
            || !panel.needsNetworkSettings(leap))
          return root.fail("unsupported primitive security settings routing")

        const personalUuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        const enterpriseUuid = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        const profileSet = [
          {
            uuid: personalUuid,
            ssid: "Dual Profile",
            lastSuccessful: 20,
            keyManagement: "wpa-psk"
          },
          {
            uuid: enterpriseUuid,
            ssid: "Dual Profile",
            lastSuccessful: 10,
            keyManagement: "wpa-eap"
          }
        ]
        const mappedPersonal = service.mergedNetworks([{
          connected: false,
          known: true,
          ssid: "Dual Profile",
          signal: 70,
          security: WifiSecurityType.Wpa2Psk
        }], profileSet)
        const mappedEnterprise = service.mergedNetworks([{
          connected: false,
          known: true,
          ssid: "Dual Profile",
          signal: 68,
          security: WifiSecurityType.Wpa2Eap
        }], profileSet)
        if (!mappedPersonal[0] || mappedPersonal[0].profileUuid !== personalUuid
            || !root.savedProfileRow(mappedPersonal, enterpriseUuid)
            || !mappedEnterprise[0]
            || mappedEnterprise[0].profileUuid !== enterpriseUuid
            || !root.savedProfileRow(mappedEnterprise, personalUuid))
          return root.fail("heterogeneous saved profiles matched by SSID only")
        const ambiguousProfiles = service.mergedNetworks([{
          connected: false,
          known: true,
          ssid: "Ambiguous Profile",
          signal: 66,
          security: WifiSecurityType.Wpa2Psk
        }], [
          {
            uuid: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            ssid: "Ambiguous Profile",
            keyManagement: "wpa-psk"
          },
          {
            uuid: "dddddddd-dddd-dddd-dddd-dddddddddddd",
            ssid: "Ambiguous Profile",
            keyManagement: "wpa-psk"
          }
        ])
        if (!ambiguousProfiles[0] || ambiguousProfiles[0].profileUuid !== ""
            || !root.savedProfileRow(ambiguousProfiles,
              "cccccccc-cccc-cccc-cccc-cccccccccccc")
            || !root.savedProfileRow(ambiguousProfiles,
              "dddddddd-dddd-dddd-dddd-dddddddddddd"))
          return root.fail("ambiguous saved profiles were assigned or hidden")

        const suiteUuid = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
        const genericEapUuid = "ffffffff-ffff-ffff-ffff-ffffffffffff"
        const suiteProfiles = service.mergedNetworks([{
          connected: false,
          known: true,
          ssid: "Suite Profile",
          signal: 64,
          security: WifiSecurityType.Wpa3SuiteB192
        }], [
          {
            uuid: genericEapUuid,
            ssid: "Suite Profile",
            keyManagement: "wpa-eap"
          },
          {
            uuid: suiteUuid,
            ssid: "Suite Profile",
            keyManagement: "wpa-eap-suite-b-192"
          }
        ])
        const leapUuid = "12121212-1212-1212-1212-121212121212"
        const dynamicWepUuid = "34343434-3434-3434-3434-343434343434"
        const leapProfiles = service.mergedNetworks([{
          connected: false,
          known: true,
          ssid: "LEAP Profile",
          signal: 59,
          security: WifiSecurityType.Leap
        }], [
          {
            uuid: dynamicWepUuid,
            ssid: "LEAP Profile",
            keyManagement: "ieee8021x",
            authAlgorithm: "open"
          },
          {
            uuid: leapUuid,
            ssid: "LEAP Profile",
            keyManagement: "ieee8021x",
            authAlgorithm: "leap"
          }
        ])
        if (!suiteProfiles[0] || suiteProfiles[0].profileUuid !== suiteUuid
            || !root.savedProfileRow(suiteProfiles, genericEapUuid)
            || !leapProfiles[0] || leapProfiles[0].profileUuid !== leapUuid
            || !root.savedProfileRow(leapProfiles, dynamicWepUuid))
          return root.fail("Suite B or LEAP profiles matched a generic mode")

        const openUuid = "45454545-4545-4545-4545-454545454545"
        const wepUuid = "67676767-6767-6767-6767-676767676767"
        const openWepProfiles = service.mergedNetworks([
          {
            connected: false,
            known: true,
            ssid: "Open WEP Profile",
            signal: 61,
            security: WifiSecurityType.Open
          },
          {
            connected: false,
            known: true,
            ssid: "Open WEP Profile",
            signal: 57,
            security: WifiSecurityType.StaticWep
          }
        ], [
          {
            uuid: openUuid,
            ssid: "Open WEP Profile",
            keyManagement: "open"
          },
          {
            uuid: wepUuid,
            ssid: "Open WEP Profile",
            keyManagement: "none"
          }
        ])
        const openProfile = root.visibleProfileRow(openWepProfiles,
          "Open WEP Profile", "open")
        const wepProfile = root.visibleProfileRow(openWepProfiles,
          "Open WEP Profile", "wep")
        const mismatchedWep = service.mergedNetworks([{
          connected: false,
          known: false,
          ssid: "Open Only Profile",
          signal: 55,
          security: WifiSecurityType.Open
        }], [{
          uuid: wepUuid,
          ssid: "Open Only Profile",
          keyManagement: "none"
        }])
        const mismatchedOpen = root.visibleProfileRow(mismatchedWep,
          "Open Only Profile", "open")
        if (!openProfile || openProfile.profileUuid !== openUuid
            || !wepProfile || wepProfile.profileUuid !== wepUuid
            || !mismatchedOpen || mismatchedOpen.profileUuid !== ""
            || !root.savedProfileRow(mismatchedWep, wepUuid)
            || service.profileSecurityLabel("open", "") !== "Open profile"
            || service.profileSecurityLabel("none", "") !== "WEP profile")
          return root.fail("open and static WEP profiles were conflated")

        const personalVariantUuid =
          "78787878-7878-7878-7878-787878787878"
        const personalVariantProfiles = service.mergedNetworks([
          {
            connected: false,
            known: true,
            ssid: "Personal Variants",
            signal: 72,
            security: WifiSecurityType.WpaPsk
          },
          {
            connected: false,
            known: true,
            ssid: "Personal Variants",
            signal: 68,
            security: WifiSecurityType.Wpa2Psk
          }
        ], [{
          uuid: personalVariantUuid,
          ssid: "Personal Variants",
          keyManagement: "wpa-psk"
        }])
        const enterpriseVariantUuid =
          "89898989-8989-8989-8989-898989898989"
        const enterpriseVariantProfiles = service.mergedNetworks([
          {
            connected: false,
            known: true,
            ssid: "Enterprise Variants",
            signal: 67,
            security: WifiSecurityType.WpaEap
          },
          {
            connected: false,
            known: true,
            ssid: "Enterprise Variants",
            signal: 64,
            security: WifiSecurityType.Wpa2Eap
          }
        ], [{
          uuid: enterpriseVariantUuid,
          ssid: "Enterprise Variants",
          keyManagement: "wpa-eap"
        }])
        const personalVariants = root.visibleProfileRows(
          personalVariantProfiles, "Personal Variants")
        const enterpriseVariants = root.visibleProfileRows(
          enterpriseVariantProfiles, "Enterprise Variants")
        if (personalVariants.length !== 2
            || personalVariants[0].profileUuid !== ""
            || personalVariants[1].profileUuid !== ""
            || !root.savedProfileRow(personalVariantProfiles,
              personalVariantUuid)
            || enterpriseVariants.length !== 2
            || enterpriseVariants[0].profileUuid !== ""
            || enterpriseVariants[1].profileUuid !== ""
            || !root.savedProfileRow(enterpriseVariantProfiles,
              enterpriseVariantUuid))
          return root.fail("one saved profile was assigned to multiple variants")

        const duplicateVisibleUuid =
          "56565656-5656-5656-5656-565656565656"
        const duplicateVisibleProfiles = service.mergedNetworks([
          {
            connected: false,
            known: true,
            ssid: "Duplicate Visible",
            signal: 70,
            security: WifiSecurityType.Wpa2Psk
          },
          {
            connected: false,
            known: true,
            ssid: "Duplicate Visible",
            signal: 45,
            security: WifiSecurityType.Wpa2Psk
          }
        ], [{
          uuid: duplicateVisibleUuid,
          ssid: "Duplicate Visible",
          keyManagement: "wpa-psk"
        }])
        const duplicateVisibleRows = root.visibleProfileRows(
          duplicateVisibleProfiles, "Duplicate Visible")
        if (duplicateVisibleRows.length !== 2
            || duplicateVisibleRows[0].profileUuid !== ""
            || duplicateVisibleRows[1].profileUuid !== ""
            || !root.savedProfileRow(duplicateVisibleProfiles,
              duplicateVisibleUuid))
          return root.fail("duplicate visible identity consumed its saved profile")

        if (unavailableProfileConnectService.ready
            || unavailableProfileForgetService.ready
            || !unavailableProfileConnectService.connect({
              profileUuid: "11111111-1111-1111-1111-111111111111",
              ssid: "Saved Fixture",
              visible: false
            })
            || !unavailableProfileForgetService.forget({
              profileUuid: "22222222-2222-2222-2222-222222222222",
              ssid: "Saved Fixture",
              known: true,
              visible: false
            }))
          return root.fail("saved profile actions require the visual backend")

        root.stalePskEntry = psk
        root.staleEnterpriseEntry = enterprise
        root.staleProfileEntry = {
          connected: false,
          known: true,
          ssid: "PSK Fixture",
          signal: 71,
          security: WifiSecurityType.Wpa2Psk,
          securityKind: "psk",
          visible: true,
          profileUuid: "33333333-3333-3333-3333-333333333333"
        }
        service.backend.wifiNetworks = [
          {
            connected: false,
            known: false,
            ssid: "PSK Fixture",
            signal: 71,
            security: WifiSecurityType.Wpa2Psk
          },
          {
            connected: false,
            known: false,
            ssid: "PSK Fixture",
            signal: 42,
            security: WifiSecurityType.Wpa2Psk
          }
        ]
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (root.ticks < 2) return
        const pskCount = service.backend.pskConnectCount
        if (service.connectWithPassphrase(root.stalePskEntry, "ambiguous")
            || service.backend.pskConnectCount !== pskCount)
          return root.fail("duplicate SSID/security identity was not rejected")
        service.backend.wifiNetworks = [
          {
            connected: false,
            known: false,
            ssid: "PSK Fixture",
            signal: 71,
            security: WifiSecurityType.Wpa2Psk
          },
          {
            connected: false,
            known: false,
            ssid: "PSK Fixture",
            signal: 63,
            security: WifiSecurityType.Wpa2Eap
          }
        ]
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (root.ticks < 2) return
        const pskCount = service.backend.pskConnectCount
        if (service.connectWithPassphrase(root.stalePskEntry, "heterogeneous")
            || service.backend.pskConnectCount !== pskCount)
          return root.fail("heterogeneous duplicate SSID was not rejected")
        service.backend.wifiNetworks = [{
          connected: false,
          known: false,
          ssid: "PSK Fixture",
          signal: 71,
          security: WifiSecurityType.Wpa2Eap
        }]
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (root.ticks < 2) return
        const pskCount = service.backend.pskConnectCount
        if (service.connectWithPassphrase(root.stalePskEntry, "changed")
            || service.backend.pskConnectCount !== pskCount
            || service.connectWithPassphrase(root.stalePskEntry, "")
            || service.connect(root.staleProfileEntry)
            || service.forget(root.staleProfileEntry))
          return root.fail("stale changed-security identity was not rejected")
        service.backend.wifiNetworks = [{
          connected: false,
          known: true,
          ssid: "PSK Fixture",
          signal: 70,
          security: WifiSecurityType.Wpa2Psk
        }]
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (root.ticks < 2) return
        const pskCount = service.backend.pskConnectCount
        panel.openPassword(root.stalePskEntry)
        panel.passwordText = "obsolete"
        if (service.connectWithPassphrase(root.stalePskEntry, "known")
            || service.backend.pskConnectCount !== pskCount
            || panel.submitPassword(root.stalePskEntry)
            || panel.credentialError === "")
          return root.fail("newly known credential target was not rejected")
        panel.clearPassword()
        service.backend.wifiNetworks = [
          {
            connected: false,
            known: false,
            ssid: "PSK Fixture",
            signal: 70,
            security: WifiSecurityType.Wpa2Psk
          },
          {
            connected: false,
            known: false,
            ssid: "Enterprise Fixture",
            signal: 65,
            security: WifiSecurityType.Wpa2Eap
          }
        ]
        service.savedProfiles = [
          {
            uuid: "90909090-9090-9090-9090-909090909090",
            ssid: "PSK Fixture",
            keyManagement: "wpa-psk"
          },
          {
            uuid: "abababab-abab-abab-abab-abababababab",
            ssid: "Enterprise Fixture",
            keyManagement: "wpa-eap"
          }
        ]
        const enterpriseCount = service.backend.enterpriseConnectCount
        panel.openPassword(root.stalePskEntry)
        panel.passwordText = "profile-loaded"
        if (service.connectWithPassphrase(root.stalePskEntry, "profile-loaded")
            || service.connectEnterprise(root.staleEnterpriseEntry,
              "user@example.test", "profile-loaded")
            || service.backend.pskConnectCount !== pskCount
            || service.backend.enterpriseConnectCount !== enterpriseCount
            || panel.submitPassword(root.stalePskEntry)
            || panel.credentialError === "")
          return root.fail("newly loaded saved profiles did not reject credentials")
        panel.clearPassword()
        service.savedProfiles = []
        service.backend.wifiNetworks = [{
          connected: true,
          known: true,
          ssid: "Enterprise Fixture",
          signal: 65,
          security: WifiSecurityType.Wpa2Eap
        }]
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (root.ticks < 2) return
        const enterpriseCount = service.backend.enterpriseConnectCount
        if (service.connectEnterprise(root.staleEnterpriseEntry,
            "user@example.test", "obsolete")
            || service.backend.enterpriseConnectCount !== enterpriseCount)
          return root.fail("newly connected enterprise target was not rejected")
        service.backend.wifiNetworks = [{
          connected: false,
          known: false,
          ssid: "Completion Fixture",
          signal: 69,
          security: WifiSecurityType.Wpa2Psk
        }]
        root.phase = 7
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (root.ticks < 2) return
        const completion = root.entryFor("Completion Fixture")
        if (!completion) return
        panel.openPassword(completion)
        panel.passwordText = "completion-secret"
        service.backend.actionSsid = "Completion Fixture"
        service.backend.actionKind = "connect"
        service.backend.actionKind = ""
        if (panel.passwordKey === "")
          return root.fail("credential editor closed before refreshed success state")
        root.phase = 8
        root.ticks = 0
        return
      }

      if (root.phase === 8) {
        if (root.ticks < 2) return
        if (panel.passwordKey === "")
          return root.fail("out-of-order action completion closed stale editor")
        service.backend.wifiNetworks = [{
          connected: true,
          known: true,
          ssid: "Completion Fixture",
          signal: 69,
          security: WifiSecurityType.Wpa2Psk
        }]
        root.phase = 9
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (root.ticks < 2) return
        if (panel.passwordKey !== "" || !panel.panelKeyboardFocusActive)
          return root.fail("refreshed connection did not close and restore focus")
        const dualRows = [
          {
            connected: false,
            known: true,
            ssid: "Dual Profile",
            signal: 71,
            security: WifiSecurityType.Wpa2Psk
          },
          {
            connected: false,
            known: true,
            ssid: "Dual Profile",
            signal: 68,
            security: WifiSecurityType.Wpa2Eap
          }
        ]
        const dualProfiles = [
          {
            uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            ssid: "Dual Profile",
            keyManagement: "wpa-psk"
          },
          {
            uuid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            ssid: "Dual Profile",
            keyManagement: "wpa-eap"
          }
        ]
        if (!profiledVisibleConnectService.ready
            || !profiledVisibleConnectService.backend
            || !profiledVisibleForgetService.ready
            || !profiledVisibleForgetService.backend) return
        profiledVisibleConnectService.savedProfiles = dualProfiles
        profiledVisibleForgetService.savedProfiles = dualProfiles
        profiledVisibleConnectService.backend.wifiNetworks = dualRows
        profiledVisibleForgetService.backend.wifiNetworks = dualRows
        root.phase = 10
        root.ticks = 0
        return
      }

      if (root.phase === 10) {
        if (root.ticks < 2) return
        const personal = root.entryForService(profiledVisibleConnectService,
          "Dual Profile", "psk")
        const enterprise = root.entryForService(profiledVisibleForgetService,
          "Dual Profile", "enterprise")
        if (!personal || !enterprise
            || personal.profileUuid
              !== "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
            || enterprise.profileUuid
              !== "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
            || !profiledVisibleConnectService.connect(personal)
            || !profiledVisibleForgetService.forget(enterprise))
          return root.fail("security-matched visible profile UUID actions failed")
        console.log("network credentials smoke passed")
        stop()
        Qt.quit()
      }
    }
  }
}
