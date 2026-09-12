import QtQuick
import Quickshell
import "network/NetworkModel.js" as NetworkModel
import "network/NetworkReachabilityModel.js" as Model

ShellRoot {
  id: root

  function fail(message) {
    console.error("network-reachability-model-regression:", message)
    Qt.exit(1)
  }

  function endpoint(status, latency) {
    return { status: status, latencyMs: latency }
  }

  function probe(interfaceName, gateway, router, internet, monotonic) {
    return {
      schemaVersion: 1,
      interfaceName: interfaceName,
      gateway: gateway,
      internetTarget: "1.1.1.1",
      sampleMonotonicMs: monotonic,
      router: router,
      internet: internet
    }
  }

  function record(snapshot) {
    return {
      schemaVersion: 1,
      event: "snapshot",
      sequence: 1,
      snapshot: snapshot
    }
  }

  function connection(interfaceName) {
    const uuid = "11111111-1111-4111-8111-111111111111"
    const hardware = "02:00:00:00:00:01"
    return {
      schemaVersion: 1,
      connected: true,
      connectionUuid: uuid,
      connectionName: "Wired",
      kind: "wired",
      interfaceName: interfaceName,
      hardwareAddress: hardware,
      metered: "no",
      addresses: [{ family: "ipv4", address: "192.0.2.10", prefix: 24 }],
      gateways: [{ family: "ipv4", address: "192.0.2.1" }],
      dnsServers: [],
      dnsDomains: [],
      rxBytes: 0,
      txBytes: 0,
      sampleMonotonicMs: 1,
      activeConnections: [{ uuid: uuid, kind: "wired",
        interfaceName: interfaceName, hardwareAddress: hardware }],
      wifi: {
        ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0
      },
      wired: { speedMbps: 1000, carrier: true },
      id: NetworkModel.connectionId(uuid),
      deviceId: NetworkModel.deviceId("wired", hardware, interfaceName)
    }
  }

  Component.onCompleted: Qt.callLater(function() {
    const valid = probe(
      "eth0", "192.0.2.1", endpoint("reply", 1.25),
      endpoint("timeout", null), 100)
    const line = JSON.stringify(record(valid))
    const parsed = Model.parseLine(line)
    if (!parsed.ok || parsed.snapshot.interfaceName !== "eth0")
      return fail("canonical snapshot was rejected")
    const malformed = [
      " " + line,
      line + " ",
      "{\"event\":\"snapshot\",\"event\":\"snapshot\"}",
      "{\"schemaVersion\":1}",
      JSON.stringify(record(Object.assign({}, valid, { extra: true }))),
      JSON.stringify(record(Object.assign({}, valid, {
        interfaceName: "abcdefghijklmnop"
      }))),
      JSON.stringify(record(Object.assign({}, valid, {
        gateway: "192.0.2.01"
      }))),
      JSON.stringify(record(Object.assign({}, valid, {
        internetTarget: "8.8.8.8"
      }))),
      JSON.stringify(record(Object.assign({}, valid, {
        router: endpoint("reply", null)
      }))),
      JSON.stringify(record(Object.assign({}, valid, {
        internet: endpoint("skipped", null)
      }))),
      JSON.stringify(record(Object.assign({}, valid, {
        sampleMonotonicMs: -1
      }))),
      "{\"value\":\"" + "A".repeat(Model.MaxProtocolLine) + "\"}"
    ]
    for (let index = 0; index < malformed.length; index++) {
      if (Model.parseLine(malformed[index]).ok)
        return fail("malformed protocol case accepted: " + index)
    }

    const source = connection("eth0")
    const route = Model.routeInput(source)
    if (!route || route.gateway !== "192.0.2.1")
      return fail("valid telemetry route was rejected")
    const forged = Object.assign({}, source, { deviceId: "forged" })
    if (Model.routeInput(forged) !== null
        || Model.routeInput(connection("abcdefghijklmnop")) !== null)
      return fail("forged telemetry identity was accepted")

    let history = null
    for (let value = 1; value <= 30; value++) {
      const internet = value % 4 === 0
        ? endpoint("timeout", null) : endpoint("reply", value)
      history = Model.nextHistory(history, route, probe(
        "eth0", "192.0.2.1", endpoint("reply", value), internet, value))
      if (!history) return fail("valid history sample was rejected")
    }
    if (history.routerSamples.length !== Model.HistoryLimit
        || history.internetSamples.length !== Model.HistoryLimit
        || history.internetPacketLossPercent !== 25
        || Math.abs(history.internetLatencyMs - 27.4) > 0.0001)
      return fail("bounded history aggregate was wrong")
    for (const replayTime of [30, 29]) {
      if (Model.nextHistory(history, route, probe(
          "eth0", "192.0.2.1", endpoint("reply", 31),
          endpoint("reply", 31), replayTime)) !== null)
        return fail("replayed monotonic timestamp was accepted")
    }

    const changedRoute = {
      connectionId: route.connectionId,
      deviceId: route.deviceId,
      interfaceName: route.interfaceName,
      gateway: "192.0.2.254",
      internetTarget: route.internetTarget
    }
    const reset = Model.nextHistory(history, changedRoute, probe(
      "eth0", "192.0.2.254", endpoint("reply", 3),
      endpoint("reply", 4), 1000))
    if (!reset || reset.routerSamples.length !== 1
        || reset.internetSamples.length !== 1)
      return fail("route change did not reset model history")

    const publicSnapshot = Model.cloneHistory(reset)
    publicSnapshot.schemaVersion = 1
    publicSnapshot.generation = 7
    if (!Model.validPublicSnapshot(publicSnapshot)
        || !Model.clonePublicSnapshot(publicSnapshot))
      return fail("valid public reachability snapshot was rejected")
    const badPublic = [
      Object.assign({}, publicSnapshot, { extra: true }),
      Object.assign({}, publicSnapshot, { generation: -1 }),
      Object.assign({}, publicSnapshot, { connectionId: "forged" }),
      Object.assign({}, publicSnapshot, { deviceId: "forged" }),
      Object.assign({}, publicSnapshot, { routerLatencyMs: 99 }),
      Object.assign({}, publicSnapshot, { internetPacketLossPercent: 99 }),
      Object.assign({}, publicSnapshot, { routerStatus: "timeout" }),
      Object.assign({}, publicSnapshot, { internetStatus: "skipped" }),
      Object.assign({}, publicSnapshot, { internetSamples: [] })
    ]
    for (let index = 0; index < badPublic.length; index++) {
      if (Model.validPublicSnapshot(badPublic[index]))
        return fail("malformed public projection accepted: " + index)
    }

    if (Model.nextHistory(reset, changedRoute, probe(
        "eth0", "192.0.2.254", endpoint("error", null),
        endpoint("reply", 4), 1001)) !== null)
      return fail("probe infrastructure error was counted as reachability")

    const noGateway = Object.assign({}, changedRoute, { gateway: "" })
    const skipped = Model.nextHistory(null, noGateway, probe(
      "eth0", "", endpoint("skipped", null), endpoint("reply", 5), 1002))
    if (!skipped || skipped.routerSamples.length !== 0
        || skipped.routerLatencyMs !== -1)
      return fail("gateway-free route was malformed")

    console.log("network reachability model regression passed")
    Qt.exit(0)
  })
}
