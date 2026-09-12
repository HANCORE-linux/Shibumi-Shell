import QtQuick
import Quickshell
import "network/NetworkModel.js" as NetworkModel
import "network/NetworkSpeedTestModel.js" as Model

ShellRoot {
  id: root

  function fail(message) {
    console.error("network-speed-test-model-regression:", message)
    Qt.exit(1)
  }

  function connection(addresses) {
    const uuid = "11111111-1111-4111-8111-111111111111"
    const hardware = "02:00:00:00:00:01"
    return {
      schemaVersion: 1,
      connected: true,
      connectionUuid: uuid,
      connectionName: "Wired",
      kind: "wired",
      interfaceName: "eth0",
      hardwareAddress: hardware,
      metered: "no",
      addresses: addresses,
      gateways: [{ family: "ipv4", address: "192.0.2.1" }],
      dnsServers: [],
      dnsDomains: [],
      rxBytes: 0,
      txBytes: 0,
      sampleMonotonicMs: 1,
      activeConnections: [{ uuid: uuid, kind: "wired",
        interfaceName: "eth0", hardwareAddress: hardware }],
      wifi: {
        ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0
      },
      wired: { speedMbps: 1000, carrier: true },
      id: NetworkModel.connectionId(uuid),
      deviceId: NetworkModel.deviceId("wired", hardware, "eth0"),
      downloadBytesPerSecond: 0,
      uploadBytesPerSecond: 0,
      generation: 1
    }
  }

  function measurement(direction, bytes, elapsed, monotonic) {
    return {
      schemaVersion: 1,
      direction: direction,
      endpoint: "speed.cloudflare.com",
      interfaceName: "eth0",
      interfaceIndex: 7,
      sourceAddress: "192.0.2.10",
      runToken: "1:7:9",
      bytesTransferred: bytes,
      elapsedMs: elapsed,
      sampleMonotonicMs: monotonic
    }
  }

  function record(snapshot) {
    // Keep the same canonical lexical key ordering as the native helper.
    return {
      event: "result",
      schemaVersion: 1,
      sequence: 1,
      snapshot: {
        bytesTransferred: snapshot.bytesTransferred,
        direction: snapshot.direction,
        elapsedMs: snapshot.elapsedMs,
        endpoint: snapshot.endpoint,
        interfaceIndex: snapshot.interfaceIndex,
        interfaceName: snapshot.interfaceName,
        runToken: snapshot.runToken,
        sampleMonotonicMs: snapshot.sampleMonotonicMs,
        schemaVersion: snapshot.schemaVersion,
        sourceAddress: snapshot.sourceAddress
      }
    }
  }

  Component.onCompleted: Qt.callLater(function() {
    const telemetry = connection([
      { family: "ipv6", address: "fe80::1", prefix: 64 },
      { family: "ipv4", address: "192.0.2.10", prefix: 24 }
    ])
    const input = Model.testInput(telemetry)
    if (!input || input.sourceAddress !== "192.0.2.10"
        || input.interfaceName !== "eth0" || input.kind !== "wired")
      return fail("valid primitive telemetry input was rejected")
    if (Model.inputFingerprint(input) === "")
      return fail("valid input has no identity fingerprint")

    const forged = Object.assign({}, telemetry, { deviceId: "forged" })
    const noSource = connection([
      { family: "ipv6", address: "fe80::1", prefix: 64 }
    ])
    if (!Model.validSourceAddress("100::1")
        || !Model.validSourceAddress("64:ff9b:1::1")
        || !Model.validSourceAddress("::ffff:201")
        || !Model.validSourceAddress("::ffff:0:c000:201"))
      return fail("bounded reserved IPv6 source policy diverged")
    if (Model.testInput(forged) !== null
        || Model.testInput(noSource) !== null
        || Model.validSourceAddress("127.0.0.1")
        || Model.validSourceAddress("169.254.1.2")
        || Model.validSourceAddress("224.0.0.1")
        || Model.validSourceAddress("::1")
        || Model.validSourceAddress("fe80::1")
        || Model.validSourceAddress("::ffff:c000:201")
        || Model.validSourceAddress("2001:4860:4860::8888%eth0"))
      return fail("unsafe speed-test route input was accepted")

    const down = measurement("down", 12500000, 1000, 100)
    const up = measurement("up", 6250000, 1000, 200)
    const line = JSON.stringify(record(down))
    const parsed = Model.parseLine(line)
    if (!parsed.ok || parsed.snapshot.bytesTransferred !== 12500000)
      return fail("canonical worker result was rejected: " + parsed.code)

    const malformed = [
      " " + line,
      line + " ",
      "{\"event\":\"result\",\"event\":\"result\"}",
      JSON.stringify({ schemaVersion: 1 }),
      JSON.stringify(record(Object.assign({}, down, { direction: "side" }))),
      JSON.stringify(record(Object.assign({}, down, {
        endpoint: "attacker.invalid"
      }))),
      JSON.stringify(record(Object.assign({}, down, {
        interfaceName: "abcdefghijklmnop"
      }))),
      JSON.stringify(record(Object.assign({}, down, {
        sourceAddress: "127.0.0.1"
      }))),
      JSON.stringify(record(Object.assign({}, down, { interfaceIndex: 0 }))),
      JSON.stringify(record(Object.assign({}, down, { runToken: "stale" }))),
      JSON.stringify(record(Object.assign({}, down, {
        bytesTransferred: Model.MaxDownloadBytes + 1
      }))),
      JSON.stringify(record(Object.assign({}, down, { elapsedMs: 0 }))),
      "{\"value\":\"" + "A".repeat(Model.MaxProtocolLine) + "\"}"
    ]
    for (let index = 0; index < malformed.length; index++) {
      if (Model.parseLine(malformed[index]).ok)
        return fail("malformed worker record accepted: " + index)
    }

    const combined = Model.result(input, 7, "1:7:9", down, up)
    if (!combined || combined.downloadMbps !== 100
        || combined.uploadMbps !== 50
        || combined.completedMonotonicMs !== 200)
      return fail("valid phase results were not combined")
    const overSpeed = measurement(
      "down", Model.MaxDownloadBytes, 1, 100)
    if (!Model.validMeasurement(overSpeed)
        || Model.result(input, 7, "1:7:9", overSpeed, up) !== null
        || Model.result(input, 7, "1:7:10", down, up) !== null
        || Model.result(input, 7, "1:7:9", down,
          Object.assign({}, up, { runToken: "1:6:8" })) !== null
        || Model.result(input, 7, "1:7:9", down,
          Object.assign({}, up, { interfaceIndex: 8 })) !== null
        || Model.result(input, 7, "1:7:9", down,
          Object.assign({}, up, { sampleMonotonicMs: 100 })) !== null
        || Model.result(input, 7, "1:7:9", down,
          Object.assign({}, up, { sourceAddress: "192.0.2.11" })) !== null)
      return fail("unsafe, replayed, or route-mismatched result was accepted")

    combined.schemaVersion = 1
    combined.generation = 9
    if (!Model.validPublicResult(combined)
        || !Model.clonePublicResult(combined))
      return fail("valid public result was rejected")
    const badPublic = [
      Object.assign({}, combined, { extra: true }),
      Object.assign({}, combined, { runId: 0 }),
      Object.assign({}, combined, { connectionId: "forged" }),
      Object.assign({}, combined, { generation: -1 }),
      Object.assign({}, combined, { downloadBytes: 0 }),
      Object.assign({}, combined, { downloadMbps: -1 }),
      Object.assign({}, combined, { downloadMbps: 99 })
    ]
    for (let index = 0; index < badPublic.length; index++) {
      if (Model.validPublicResult(badPublic[index]))
        return fail("malformed public result accepted: " + index)
    }

    console.log("network speed-test model regression passed")
    Qt.exit(0)
  })
}
