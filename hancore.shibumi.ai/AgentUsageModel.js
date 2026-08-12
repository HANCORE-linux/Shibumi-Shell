.pragma library

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function nonNegativeNumber(value) {
  return Math.max(0, finiteNumber(value, 0))
}

function boundedString(value, fallback) {
  var text = String(value === undefined || value === null
    ? fallback || "" : value)
  return text.length > 512 ? text.slice(0, 512) : text
}

function hasDisplayData(record, limits) {
  return limits.length > 0
    || nonNegativeNumber(record.todayPrompts) > 0
    || nonNegativeNumber(record.todaySessions) > 0
    || nonNegativeNumber(record.todayTotalTokens) > 0
}

function limitSnapshot(limits, index) {
  var limit = index >= 0 && index < limits.length ? limits[index] : null
  if (!limit || typeof limit !== "object") return null
  var percent = finiteNumber(limit.percent, -1)
  if (percent < 0) return null
  return {
    label: boundedString(limit.label, index === 0 ? "Primary" : "Secondary"),
    percent: percent,
    resetsAt: boundedString(limit.resetsAt, "")
  }
}

function parseRecord(raw, expectedId) {
  var text = String(raw || "")
  if (text.length === 0 || text.length > 2 * 1024 * 1024) return null
  var record
  try {
    record = JSON.parse(text)
  } catch (_error) {
    return null
  }
  if (!record || typeof record !== "object" || Array.isArray(record)
      || Number(record.schemaVersion) !== 1
      || String(record.id || "") !== String(expectedId || "")) return null

  var rawLimits = Array.isArray(record.limits) ? record.limits : []
  var limits = []
  for (var index = 0; index < rawLimits.length && limits.length < 2; index++) {
    var limit = limitSnapshot(rawLimits, index)
    if (limit) limits.push(limit)
  }
  if (!hasDisplayData(record, limits)) return null

  var primary = limits.length > 0 ? limits[0] : null
  var secondary = limits.length > 1 ? limits[1] : null
  var updatedAt = boundedString(record.updatedAt, "")
  if (updatedAt !== "" && !isFinite(Date.parse(updatedAt))) updatedAt = ""

  return {
    providerId: boundedString(record.id, ""),
    providerName: boundedString(record.name, record.id),
    ready: record.ready === true,
    rateLimitPercent: primary ? primary.percent : -1,
    rateLimitLabel: primary ? primary.label : "",
    rateLimitResetAt: primary ? primary.resetsAt : "",
    secondaryRateLimitPercent: secondary ? secondary.percent : -1,
    secondaryRateLimitLabel: secondary ? secondary.label : "",
    secondaryRateLimitResetAt: secondary ? secondary.resetsAt : "",
    todayTotalTokens: nonNegativeNumber(record.todayTotalTokens),
    todayPrompts: nonNegativeNumber(record.todayPrompts),
    todaySessions: nonNegativeNumber(record.todaySessions),
    totalPrompts: nonNegativeNumber(record.totalPrompts),
    totalSessions: nonNegativeNumber(record.totalSessions),
    activeDays: nonNegativeNumber(record.activeDays),
    windowTokens: 0,
    hourlyTokens: 0,
    // Keep the existing Shibumi presentation stable. Omarchy's agents record
    // exposes all-time model aggregates, while the current panel's model rows
    // are explicitly labeled as recent activity.
    models: [],
    tierLabel: boundedString(record.tierLabel, ""),
    usageStatusText: boundedString(record.usageStatusText, ""),
    authHelpText: boundedString(record.authHelpText, ""),
    latestModel: "",
    updatedAt: updatedAt,
    refreshing: false,
    backend: "omarchy.agents"
  }
}
