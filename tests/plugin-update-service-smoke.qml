pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "control" as Control

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("plugin-update-service-smoke:", message)
    Qt.exit(1)
  }

  Control.PluginUpdateService {
    id: service
    timeoutSeconds: 1
  }

  Control.PluginUpdateService {
    id: statusProbe
    timeoutSeconds: 1
  }

  Timer {
    interval: 40
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        statusProbe.checked = true
        statusProbe.updateCount = 0
        if (statusProbe.shortStatusText !== "0 available")
          return root.fail("zero-update text is ambiguous")
        statusProbe.updateCount = 1
        if (statusProbe.shortStatusText !== "1 available")
          return root.fail("singular update text is ambiguous")
        statusProbe.updateCount = 2
        if (statusProbe.shortStatusText !== "2 available")
          return root.fail("plural update text is ambiguous")
        statusProbe.checked = false
        if (statusProbe.shortStatusText !== "not checked")
          return root.fail("unchecked text is ambiguous")
        statusProbe.error = "fixture"
        if (statusProbe.shortStatusText !== "check failed")
          return root.fail("failure text is ambiguous")

        service.observePluginRevision(0, false)
        service.consumerCount = 1
        if (!service.check(true))
          return root.fail("valid scan did not start")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!service.running) {
          if (root.ticks > 20)
            return root.fail("valid scan finished before invalidation")
          return
        }
        if (root.ticks < 3) return
        service.invalidate(false)
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (service.running) return
        if (service.checked || service.updateCount !== 0
            || service.checkedCount !== 0 || service.unmanagedCount !== 0
            || service.failedCount !== 0 || service.error !== ""
            || service.checkedAt !== 0
            || service.shortStatusText !== "not checked")
          return root.fail("invalidated in-flight scan was published: checked="
            + service.checked + " updates=" + service.updateCount
            + " checkedCount=" + service.checkedCount
            + " unmanaged=" + service.unmanagedCount
            + " failed=" + service.failedCount + " error=" + service.error
            + " checkedAt=" + service.checkedAt
            + " invalidation=" + service.invalidationEpoch
            + " scan=" + service.scanEpoch
            + " shortStatus=" + service.shortStatusText)
        if (!service.check(false))
          return root.fail("invalidated scan did not refresh")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (service.running) return
        if (!service.checked || service.checkedAt <= 0
            || service.updateCount !== 2
            || service.shortStatusText !== "2 available")
          return root.fail("refreshed partial scan was not cached")
        if (service.check(false))
          return root.fail("fresh scan bypassed the five-minute cache")
        if (service.observePluginRevision(0, false)
            || !service.checked || service.checkedAt <= 0)
          return root.fail("unchanged registry revision invalidated fresh data")
        if (!service.observePluginRevision(1, false)
            || !service.checked || service.checkedAt !== 0)
          return root.fail("closed-panel registry change did not invalidate cache")
        if (!service.invalidate(true))
          return root.fail("invalid-data scan did not start")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (service.running) return
        if (service.checked || service.error
            !== "Plugin update check returned invalid data"
            || service.shortStatusText !== "check failed")
          return root.fail("duplicate machine fields were not rejected")
        if (!service.invalidate(true))
          return root.fail("timeout scan did not start")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (service.running) return
        if (service.checked || service.error
            !== "Plugin update check timed out"
            || service.shortStatusText !== "check failed")
          return root.fail("bounded scan timeout was not reported")
        if (!service.invalidate(true))
          return root.fail("large-count scan did not start")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (service.running) return
        if (!service.checked || service.updateCount !== 120
            || service.checkedCount !== 120
            || service.shortStatusText !== "120 available"
            || service.error !== "")
          return root.fail("large update count was not preserved in status text")
        service.clearResult()
        if (!service.check(true))
          return root.fail("cancellation scan did not start")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (!service.running) return
        if (root.ticks < 3) return
        if (!service.releaseConsumer() || service.consumerCount !== 0)
          return root.fail("last consumer did not request scanner cancellation")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 8) {
        if (service.running) return
        if (service.checked || service.updateCount !== 0
            || service.checkedAt !== 0 || service.error !== "")
          return root.fail("closed catalog published the cancelled scan")
        service.consumerCount = 1
        service.scheduleRerun()
        if (!service.releaseConsumer() || service.consumerCount !== 0)
          return root.fail("pending rerun consumer did not close")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (root.ticks < 3) return
        if (service.running || service.rerunRequested)
          return root.fail("closed catalog started a deferred rerun")
        stop()
        console.log("plugin update service smoke passed")
        Qt.quit()
      }

      if (root.ticks > 200)
        root.fail("state transition timed out in phase " + root.phase)
    }
  }
}
