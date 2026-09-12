import QtQuick
import Quickshell
import "network/NetworkEnterpriseModel.js" as Model

ShellRoot {
  id: root

  function fail(message) {
    console.error("network-enterprise-model-regression:", message)
    Qt.exit(1)
  }

  function credentials(changes) {
    return Object.assign({
      method: "peap-mschapv2",
      identity: "user@example.test",
      password: "transient enterprise secret",
      serverDomain: "radius.example.test"
    }, changes || {})
  }

  function descriptor(changes) {
    return Object.assign({
      deviceId: 'shibumi-network-v1:["device",["wifi","AA","wlan0"]]',
      entityId: 'shibumi-network-v1:["network",["device","Corp","wpa2-eap"]]',
      generation: 7,
      hardwareAddress: "02:00:00:00:00:01",
      interfaceName: "wlan0",
      security: "wpa2-eap",
      ssidHex: "436F7270"
    }, changes || {})
  }

  Component.onCompleted: Qt.callLater(function() {
    const valid = Model.credentialsData(credentials())
    if (!valid.ok || valid.credentials.method !== "peap-mschapv2"
        || valid.credentials.serverDomain !== "radius.example.test")
      return fail("valid PEAP credentials were rejected")
    const normalized = Model.credentialsData(credentials({
      serverDomain: "RADIUS.Example.Test"
    }))
    if (!normalized.ok
        || normalized.credentials.serverDomain !== "radius.example.test")
      return fail("server domain was not normalized safely")
    const opaquePassword = " secret\twith\nintentional whitespace "
    const spacedPassword = Model.credentialsData(credentials({
      password: opaquePassword
    }))
    if (!spacedPassword.ok
        || spacedPassword.credentials.password !== opaquePassword)
      return fail("opaque password whitespace was not preserved")

    let reads = 0
    const oneRead = {
      method: "peap-mschapv2",
      identity: "user@example.test",
      password: "secret",
      serverDomain: "radius.example.test"
    }
    Object.defineProperty(oneRead, "password", {
      enumerable: true,
      get: function() {
        reads++
        if (reads > 1) throw new Error("password read twice")
        return "secret"
      }
    })
    const parsedOneRead = Model.credentialsData(oneRead)
    if (!parsedOneRead.ok || reads !== 1)
      return fail("credential getter was evaluated more than once")

    const malformed = [
      null,
      [],
      credentials({ extra: true }),
      credentials({ method: "ttls-pap" }),
      credentials({ identity: "" }),
      credentials({ identity: " bad" }),
      credentials({ identity: "bad\nidentity" }),
      credentials({ identity: "\ud800" }),
      credentials({ password: "" }),
      credentials({ password: "bad\u0000password" }),
      credentials({ password: "\udfff" }),
      credentials({ serverDomain: "example" }),
      credentials({ serverDomain: "*.example.test" }),
      credentials({ serverDomain: "radius.example.test." }),
      credentials({ serverDomain: "-radius.example.test" })
    ]
    for (let index = 0; index < malformed.length; index++) {
      if (Model.credentialsData(malformed[index]).ok)
        return fail("malformed credential accepted: " + index)
    }

    const validDescriptor = descriptor()
    if (!Model.validDescriptor(validDescriptor)
        || Model.validDescriptor(descriptor({ extra: true }))
        || Model.validDescriptor(descriptor({ generation: -1 }))
        || Model.validDescriptor(descriptor({ interfaceName: "../../wlan0" }))
        || Model.validDescriptor(descriptor({ security: "wpa-eap" }))
        || Model.validDescriptor(descriptor({ security: "wpa3-suite-b-192" }))
        || Model.validDescriptor(descriptor({ ssidHex: "0" })))
      return fail("Enterprise descriptor boundary is inconsistent")

    const token = "shibumi-enterprise-v1:[1,2]"
    const line = Model.payloadLine(validDescriptor, credentials(), token)
    if (line === "" || line.length > Model.MaxPayloadBytes)
      return fail("valid bounded payload was rejected")
    const payload = JSON.parse(line)
    if (JSON.stringify(payload) !== line
        || payload.password !== "transient enterprise secret"
        || payload.serverDomain !== "radius.example.test"
        || payload.requestToken !== token)
      return fail("canonical stdin payload changed")
    if (Model.payloadLine(validDescriptor, credentials(), "stale") !== ""
        || Model.payloadLine(descriptor({ security: "leap" }),
          credentials(), token) !== "")
      return fail("unsupported payload crossed the boundary")

    const result = {
      ok: true, code: "accepted", message: "",
      entityId: validDescriptor.entityId,
      generation: 7,
      descriptor: validDescriptor
    }
    if (!Model.descriptorResult(
        result, validDescriptor.entityId, validDescriptor.generation)
        || Model.descriptorResult(Object.assign({}, result, {
          descriptor: descriptor({ generation: 8 })
        }), validDescriptor.entityId, validDescriptor.generation))
      return fail("descriptor result generation was not pinned")

    const completion = {
      deviceId: validDescriptor.deviceId,
      entityId: validDescriptor.entityId,
      generation: 7,
      hardwareAddress: "02:00:00:00:00:01",
      interfaceName: "wlan0",
      requestToken: token,
      sampleMonotonicMs: 1000,
      schemaVersion: 1,
      security: "wpa2-eap",
      ssidHex: "436F7270",
      status: "connected"
    }
    const completionRecord = {
      event: "completion", schemaVersion: 1, sequence: 1,
      snapshot: completion
    }
    const completionLine = JSON.stringify(completionRecord)
    const completionArgs = [token, "436F7270",
      validDescriptor.deviceId, validDescriptor.entityId, 7,
      "02:00:00:00:00:01", "wlan0", "wpa2-eap"]
    if (!Model.parseCompletionLine(completionLine).ok
        || !Model.completionMatches.apply(
          null, [completion].concat(completionArgs))
        || Model.parseCompletionLine(completionLine + " ").ok)
      return fail("valid Enterprise completion identity was rejected")
    const completionMutations = [
      { requestToken: "shibumi-enterprise-v1:[1,3]" },
      { ssidHex: "4F74686572" },
      { deviceId: 'shibumi-network-v1:["device",["other"]]' },
      { entityId: 'shibumi-network-v1:["network",["other"]]' },
      { generation: 8 },
      { hardwareAddress: "02:00:00:00:00:02" },
      { hardwareAddress: "00:00:00:00:00:00" },
      { interfaceName: "wlan1" },
      { security: "wpa-eap" }
    ]
    for (let index = 0; index < completionMutations.length; index++) {
      const changed = Object.assign({}, completion, completionMutations[index])
      if (Model.completionMatches.apply(
          null, [changed].concat(completionArgs)))
        return fail("mutated completion identity accepted: " + index)
    }

    const dispatch = Model.dispatchResult(
      true, "accepted", validDescriptor.entityId, 7)
    if (!dispatch.ok || dispatch.code !== "accepted"
        || "password" in dispatch || "identity" in dispatch)
      return fail("dispatch result exposed credentials")

    console.log("network enterprise model regression passed")
    Qt.exit(0)
  })
}
