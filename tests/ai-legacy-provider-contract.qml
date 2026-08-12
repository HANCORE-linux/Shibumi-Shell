pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

ShellRoot {
  id: root

  property int loadedCount: 0

  function fail(message) {
    console.error("ai-legacy-provider-contract:", message)
    Qt.exit(1)
  }

  function validate(item, expectedId) {
    if (!item || String(item.providerId || "") !== expectedId
        || !("providerName" in item) || !("enabled" in item)
        || !("ready" in item) || !("refreshing" in item)
        || !("rateLimitPercent" in item) || !("rateLimitLabel" in item)
        || !("rateLimitResetAt" in item)
        || !("secondaryRateLimitPercent" in item)
        || !("secondaryRateLimitLabel" in item)
        || !("secondaryRateLimitResetAt" in item)
        || !("todayTotalTokens" in item)
        || !("tierLabel" in item) || !("usageStatusText" in item)
        || typeof item.refresh !== "function")
      return false
    item.enabled = false
    return true
  }

  Loader {
    source: Quickshell.env("SHIBUMI_TEST_LEGACY_CLAUDE_SOURCE")
    onLoaded: {
      if (!root.validate(item, "claude"))
        return root.fail("Claude provider contract")
      root.loadedCount++
    }
  }

  Loader {
    source: Quickshell.env("SHIBUMI_TEST_LEGACY_CODEX_SOURCE")
    onLoaded: {
      if (!root.validate(item, "codex"))
        return root.fail("Codex provider contract")
      root.loadedCount++
    }
  }

  Timer {
    property int attempts: 0
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      attempts++
      if (root.loadedCount === 2) {
        stop()
        console.log("AI legacy provider contract passed")
        Qt.quit()
      } else if (attempts >= 60) {
        stop()
        root.fail("provider load timeout")
      }
    }
  }
}
