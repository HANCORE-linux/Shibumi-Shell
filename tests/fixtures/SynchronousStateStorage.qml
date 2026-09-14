import QtQuick
import "ShibumiConfig.js" as Config

// Presentation-only fixture substituted for StateStorage before Qt starts.
// Complete synchronous in-memory backend: no FileView, native API or fallback.
// Async persistence/admission is tested by state-service/state-storage gates and
// the pinned native fixture, not by this long-running UI presentation matrix.
Item {
  id: root
  required property var host
  required property var authorityToken
  required property string omarchyPath
  readonly property bool ready: !!host
  readonly property bool pending: false
  readonly property var value: Config.normalize(host ? host.shellConfig.bar.shibumi : null)
  readonly property var requestedValue: host
    && "requestedStateOverride" in host && host.requestedStateOverride
    ? Config.normalize(host.requestedStateOverride) : value
  property string writeStatus: "idle"
  property int requestSerial: 0
  signal settled(int throughSerial, string result)
  function draft() { return JSON.parse(JSON.stringify(value)) }
  function queue(next) {
    if (!host || typeof host.mutateShellConfig !== "function") return false
    requestSerial++
    host.mutateShellConfig(function(config) {
      config.bar.shibumi = JSON.parse(JSON.stringify(next))
    })
    writeStatus = "confirmed"
    settled(requestSerial, "confirmed")
    return true
  }
}
