import QtQuick

Item {
  visible: false
  property var providerSettings: ({})
  property bool enabled: false
  property string providerId: "codex"
  property string providerName: "Legacy Codex"
  property bool ready: true
  property real rateLimitPercent: 0.2
  property string rateLimitLabel: "Weekly (7-day)"
  property string rateLimitResetAt: ""
  property real secondaryRateLimitPercent: -1
  property string secondaryRateLimitLabel: ""
  property string secondaryRateLimitResetAt: ""
  property real todayTotalTokens: 20
  property real windowTokens: 0
  property real hourlyTokens: 0
  property var models: []
  property string tierLabel: "Legacy"
  property string usageStatusText: ""
  property string authHelpText: ""
  property string latestModel: ""
  property bool refreshing: false
  property int refreshCount: 0
  function refresh(_force) { refreshCount++; usageStatusText = "refreshed" }
}
