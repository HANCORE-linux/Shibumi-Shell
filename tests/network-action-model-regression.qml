import QtQuick
import Quickshell
import "network/NetworkActionModel.js" as Model

ShellRoot {
  id: root

  function fail(message) {
    console.error("network-action-model-regression:", message)
    Qt.exit(1)
  }

  function row(id, values) {
    return Object.assign({ id: id }, values || ({}))
  }

  function pending(kind, entityId, deviceId, relatedId, generation, target) {
    return {
      kind: kind,
      entityId: entityId,
      deviceId: deviceId,
      relatedEntityId: relatedId || "",
      dispatchGeneration: generation,
      observedGeneration: generation,
      targetEnabled: target === undefined ? null : target
    }
  }

  function view(generation, devices, networks, profiles, radio) {
    const networkRows = networks.map(source => {
      const value = Object.assign({
        schemaVersion: 1, deviceId: "", ssid: "N", security: "open",
        connected: false, known: false, state: "disconnected",
        stateChanging: false, signal: 50, profileCount: 0,
        validProfileCount: 0, canConnect: true, canConnectWithPsk: false,
        canDisconnect: false, canForget: false, ambiguous: false,
        generation: generation
      }, source, { generation: generation })
      if (!Object.prototype.hasOwnProperty.call(source, "state"))
        value.state = value.connected ? "connected" : "disconnected"
      return value
    })
    const deviceRows = devices.map(source => {
      let connected = source.connected === true
      for (let index = 0; index < networkRows.length; index++) {
        if (networkRows[index].deviceId === source.id
            && networkRows[index].connected) connected = true
      }
      return Object.assign({
        schemaVersion: 1, type: "wifi", name: "wlan-model",
        address: "AA:BB:CC:DD:EE:40", connected: connected,
        state: connected ? "connected" : "disconnected", managed: true,
        autoconnect: true, ambiguous: false, generation: generation
      }, source, { connected: connected,
        state: connected ? "connected" : "disconnected",
        generation: generation })
    })
    const profileRows = profiles.map(source => Object.assign({
      schemaVersion: 1,
      uuid: "11111111-1111-4111-8111-111111111111",
      deviceId: "", networkId: "", ssid: "N", name: "Saved",
      security: "unknown", lastSuccessful: 0, canConnect: true,
      canForget: true, ambiguous: false, generation: generation
    }, source, { generation: generation }))
    const radioRow = Object.assign({
      schemaVersion: 1, available: true, hardwareEnabled: true,
      enabled: true, generation: generation
    }, radio, { generation: generation })
    return {
      available: true,
      degraded: false,
      generation: generation,
      devices: deviceRows,
      networks: networkRows,
      profiles: profileRows,
      radio: radioRow
    }
  }

  Component.onCompleted: Qt.callLater(function() {
    const radioId = 'shibumi-network-v1:["radio","wifi"]'
    const deviceId = 'shibumi-network-v1:["device","wifi","mac","AA"]'
    const networkId = 'shibumi-network-v1:["network","N"]'
    const profileId = 'shibumi-network-v1:["profile","P"]'
    const actionOne = Model.actionId(1, 1)
    const actionTwo = Model.actionId(1, 2)
    if (!actionOne || actionOne === actionTwo
        || Model.actionId(0, 1) !== "" || Model.actionId(1, -1) !== "")
      return fail("action IDs are not stable unique tuples")

    const accepted = {
      ok: true, code: "accepted", message: "", entityId: networkId,
      generation: 4
    }
    if (!Model.validDispatchResult(accepted, networkId)
        || !Model.validDispatchResult(Object.assign({}, accepted, {
          message: "A".repeat(Model.MaxMessageBytes)
        }), networkId)
        || !Model.validDispatchResult(Object.assign({}, accepted, {
          message: "é".repeat(Model.MaxMessageBytes / 2)
        }), networkId)
        || Model.validDispatchResult(Object.assign({}, accepted, {
          code: "unavailable"
        }), networkId)
        || Model.validDispatchResult(Object.assign({}, accepted, {
          extra: true
        }), networkId)
        || Model.validDispatchResult(Object.assign({}, accepted, {
          message: "A".repeat(Model.MaxMessageBytes + 1)
        }), networkId)
        || Model.validDispatchResult(Object.assign({}, accepted, {
          message: "é".repeat(Model.MaxMessageBytes / 2 + 1)
        }), networkId)
        || Model.validDispatchResult(Object.assign({}, accepted, {
          message: "\ud800"
        }), networkId))
      return fail("dispatch result boundary is permissive")

    const radio = {
      id: radioId, available: true, hardwareEnabled: true,
      enabled: true, generation: 4
    }
    const devices = [row(deviceId, {
      connected: false, ambiguous: false, state: "disconnected"
    })]
    const disconnected = row(networkId, {
      deviceId: deviceId, connected: false, state: "disconnected",
      stateChanging: false, canConnect: true, canConnectWithPsk: true,
      canDisconnect: false, ambiguous: false
    })
    const connected = row(networkId, {
      deviceId: deviceId, connected: true, state: "connected",
      stateChanging: false, canConnect: false, canConnectWithPsk: false,
      canDisconnect: true, ambiguous: false
    })
    const profile = row(profileId, {
      deviceId: deviceId, networkId: networkId, canConnect: true,
      canForget: true, ambiguous: false
    })

    if (!Model.actionContext("wifi-disable", radioId, radio, [], [])
        || Model.actionContext("wifi-enable", radioId, radio, [], []) !== null
        || !Model.actionContext("connect", networkId, radio,
          [disconnected], [])
        || !Model.actionContext("connect-with-psk", networkId, radio,
          [disconnected], [])
        || Model.actionContext("connect", networkId, radio,
          [Object.assign({}, disconnected, { stateChanging: true })], [])
          !== null
        || Model.actionContext("connect", networkId, radio,
          [Object.assign({}, disconnected, { canConnect: false })], []) !== null
        || Model.actionContext("connect-with-psk", networkId, radio,
          [Object.assign({}, disconnected, { canConnectWithPsk: false })], [])
          !== null
        || Model.actionContext("connect", networkId, radio,
          [disconnected, disconnected], []) !== null
        || Model.actionContext("disconnect", networkId, radio,
          [disconnected], []) !== null
        || Model.actionContext("disconnect", networkId, radio,
          [Object.assign({}, connected, { stateChanging: true })], []) !== null
        || Model.actionContext("disconnect", networkId, radio,
          [Object.assign({}, connected, { canDisconnect: false })], []) !== null
        || !Model.actionContext("connect-profile", profileId, radio,
          [disconnected], [profile])
        || Model.actionContext("connect-profile", profileId, radio,
          [disconnected], [Object.assign({}, profile, { canConnect: false })])
          !== null
        || Model.actionContext("forget-profile", profileId, radio,
          [disconnected], [Object.assign({}, profile, { canForget: false })])
          !== null
        || Model.actionContext("forget-profile", profileId, radio,
          [Object.assign({}, disconnected, { stateChanging: true })], [profile])
          !== null)
      return fail("action context preconditions are wrong")

    let result = Model.reconcile(
      pending("connect", networkId, deviceId, "", 4),
      view(4, devices, [disconnected], [], radio))
    if (result.terminal) return fail("connect completed before observation")
    result = Model.reconcile(
      pending("connect", networkId, deviceId, "", 4),
      view(4, devices, [connected], [], radio))
    if (result.terminal)
      return fail("same-generation connected row completed connect")
    result = Model.reconcile(
      pending("connect", networkId, deviceId, "", 4),
      view(5, devices, [connected], [], radio))
    if (!result.terminal || !result.success || result.code !== "completed")
      return fail("connected row did not complete connect")
    const changingConnected = Object.assign({}, connected, {
      stateChanging: true
    })
    result = Model.reconcile(
      pending("connect", networkId, deviceId, "", 4),
      view(5, devices, [changingConnected], [], radio))
    if (result.terminal)
      return fail("intermediate connected row completed connect")
    const replayPending = pending(
      "connect", networkId, deviceId, "", 4)
    replayPending.observedGeneration = 6
    result = Model.reconcile(replayPending,
      view(5, devices, [connected], [], radio))
    if (!result.terminal || result.success || result.code !== "invalid")
      return fail("older observed topology completed connect")

    result = Model.reconcile(
      pending("disconnect", networkId, deviceId, "", 4),
      view(4, devices, [disconnected], [], radio))
    if (result.terminal)
      return fail("same-generation disconnected row completed disconnect")
    result = Model.reconcile(
      pending("disconnect", networkId, deviceId, "", 4),
      view(4, devices, [], [], radio))
    if (result.terminal)
      return fail("same-generation disappearance completed disconnect")
    result = Model.reconcile(
      pending("disconnect", networkId, deviceId, "", 4),
      view(5, devices, [], [], radio))
    if (!result.terminal || !result.success)
      return fail("authoritative disconnect was not completed")

    result = Model.reconcile(
      pending("connect-profile", profileId, deviceId, networkId, 4),
      view(4, devices, [connected], [profile], radio))
    if (result.terminal)
      return fail("same-generation profile state completed connect")
    result = Model.reconcile(
      pending("connect-profile", profileId, deviceId, networkId, 4),
      view(5, devices, [connected], [profile], radio))
    if (!result.terminal || !result.success)
      return fail("profile connection did not follow related network")
    result = Model.reconcile(
      pending("connect-profile", profileId, deviceId, networkId, 4),
      view(5, devices, [connected], [], radio))
    if (!result.terminal || result.success)
      return fail("missing profile completed profile connect")

    result = Model.reconcile(
      pending("forget-profile", profileId, deviceId, networkId, 4),
      view(4, devices, [disconnected], [], radio))
    if (result.terminal)
      return fail("same-generation profile absence completed forget")
    result = Model.reconcile(
      pending("forget-profile", profileId, deviceId, networkId, 4),
      view(5, devices, [disconnected], [], radio))
    if (!result.terminal || !result.success)
      return fail("profile removal did not complete forget")
    result = Model.reconcile(
      pending("forget-profile", profileId, deviceId, networkId, 4),
      view(5, devices, [], [], radio))
    if (result.terminal)
      return fail("access-point disappearance completed profile forget")

    result = Model.reconcile(
      pending("wifi-disable", radioId, "", "", 4, false),
      view(4, devices, [], [], Object.assign({}, radio, { enabled: false })))
    if (result.terminal)
      return fail("same-generation radio state completed action")
    result = Model.reconcile(
      pending("wifi-disable", radioId, "", "", 4, false),
      view(5, devices, [], [], Object.assign({}, radio, { enabled: false })))
    if (!result.terminal || !result.success)
      return fail("radio target did not complete")

    const asciiSsidBoundary = view(5, devices, [Object.assign({}, connected, {
      ssid: "A".repeat(32)
    })], [], radio)
    const unicodeSsidBoundary = view(5, devices, [Object.assign({}, connected, {
      ssid: "é".repeat(16)
    })], [], radio)
    if (!Model.validView(asciiSsidBoundary)
        || !Model.validView(unicodeSsidBoundary))
      return fail("valid topology string boundary was rejected")
    const staleRowView = view(5, devices, [connected], [], radio)
    staleRowView.networks[0].generation = 4
    const oversizedSsidView = view(5, devices, [Object.assign({}, connected, {
      ssid: "A".repeat(33)
    })], [], radio)
    const multibyteSsidView = view(5, devices, [Object.assign({}, connected, {
      ssid: "é".repeat(17)
    })], [], radio)
    const malformedSsidView = view(5, devices, [Object.assign({}, connected, {
      ssid: "\ud800"
    })], [], radio)
    const oversizedNameView = view(5, devices, [connected], [], radio)
    oversizedNameView.devices[0].name = "A".repeat(65)
    const failures = [
      Model.reconcile(pending("connect", networkId, deviceId, "", 4), null),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        Object.assign(view(5, devices, [connected], [], radio), {
          available: false
        })),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        view(5, [], [connected], [], radio)),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        view(3, devices, [connected], [], radio)),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        view(5, devices, [connected, connected], [], radio)),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        staleRowView),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        oversizedSsidView),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        multibyteSsidView),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        malformedSsidView),
      Model.reconcile(pending("connect", networkId, deviceId, "", 4),
        oversizedNameView)
    ]
    for (let index = 0; index < failures.length; index++) {
      if (!failures[index].terminal || failures[index].success)
        return fail("fail-closed reconciliation case passed: " + index)
    }

    const publicSnapshot = {
      schemaVersion: 1,
      phase: "pending",
      actionId: actionOne,
      kind: "connect",
      entityId: networkId,
      relatedEntityId: "",
      targetEnabled: null,
      code: "pending",
      message: "",
      dispatchGeneration: 4,
      observedGeneration: 5,
      generation: 2
    }
    if (!Model.validPublicSnapshot(publicSnapshot)
        || !Model.clonePublicSnapshot(publicSnapshot))
      return fail("valid public action snapshot was rejected")
    const malformed = [
      Object.assign({}, publicSnapshot, { extra: true }),
      Object.assign({}, publicSnapshot, { actionId: "forged" }),
      Object.assign({}, publicSnapshot, { kind: "secret-connect" }),
      Object.assign({}, publicSnapshot, { entityId: "forged" }),
      Object.assign({}, publicSnapshot, { code: "accepted" }),
      Object.assign({}, publicSnapshot, { dispatchGeneration: -1 }),
      Object.assign({}, publicSnapshot, {
        message: "A".repeat(Model.MaxMessageBytes + 1)
      })
    ]
    for (let index = 0; index < malformed.length; index++) {
      if (Model.validPublicSnapshot(malformed[index]))
        return fail("malformed public action snapshot accepted: " + index)
    }

    console.log("network action model regression passed")
    Qt.exit(0)
  })
}
