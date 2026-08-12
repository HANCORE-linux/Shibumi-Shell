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

function isPlainObject(value) {
  return value && typeof value === "object" && !Array.isArray(value)
}

function isNonNegativeRecordNumber(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && Math.floor(value) === value && value <= 9007199254740991
}

function validOptionalString(record, key) {
  return record[key] === undefined || typeof record[key] === "string"
}

function validTimestamp(value) {
  if (typeof value !== "string") return false
  var match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$/.exec(value)
  if (!match) return false
  var year = Number(match[1])
  var month = Number(match[2])
  var day = Number(match[3])
  var hour = Number(match[4])
  var minute = Number(match[5])
  var second = Number(match[6])
  var offsetHour = match[7] === undefined ? 0 : Number(match[7])
  var offsetMinute = match[8] === undefined ? 0 : Number(match[8])
  var daysInMonth = month >= 1 && month <= 12
    ? new Date(Date.UTC(year, month, 0)).getUTCDate() : 0
  return day >= 1 && day <= daysInMonth
    && hour <= 23 && minute <= 59 && second <= 59
    && offsetHour <= 23 && offsetMinute <= 59
    && isFinite(Date.parse(value))
}

function validRecordShape(record, expectedId) {
  if (!isPlainObject(record)
      || record.schemaVersion !== 1
      || typeof record.id !== "string"
      || record.id !== String(expectedId || "")
      || typeof record.name !== "string"
      || record.name.length === 0
      || typeof record.ready !== "boolean"
      || !validTimestamp(record.updatedAt)
      || !Array.isArray(record.limits)
      || !isPlainObject(record.modelUsage)
      || !validOptionalString(record, "tierLabel")
      || !validOptionalString(record, "usageStatusText")
      || !validOptionalString(record, "authHelpText")) return false
  var counters = ["todayPrompts", "todaySessions", "todayTotalTokens",
    "totalPrompts", "totalSessions", "activeDays"]
  for (var index = 0; index < counters.length; index++) {
    if (!isNonNegativeRecordNumber(record[counters[index]])) return false
  }
  return true
}

function hasDisplayData(record, limits) {
  // All-time counters establish that this fresh record represents an actually
  // used provider, but they are never copied into Shibumi's current model rows.
  return limits.length > 0
    || nonNegativeNumber(record.todayPrompts) > 0
    || nonNegativeNumber(record.todaySessions) > 0
    || nonNegativeNumber(record.todayTotalTokens) > 0
    || nonNegativeNumber(record.totalPrompts) > 0
    || nonNegativeNumber(record.totalSessions) > 0
    || nonNegativeNumber(record.activeDays) > 0
}

function freshUpdatedAt(value, nowMs) {
  var updatedAt = boundedString(value, "")
  var updatedAtMs = Date.parse(updatedAt)
  if (updatedAt === "" || !validTimestamp(updatedAt)
      || !isFinite(updatedAtMs)) return ""
  var currentMs = finiteNumber(nowMs, Date.now())
  // Agent records are regenerated at least every few minutes. Keep a generous
  // full-day grace period for suspended systems, but never revive historical
  // files merely because they still contain all-time model totals.
  if (updatedAtMs < currentMs - 24 * 60 * 60 * 1000
      || updatedAtMs > currentMs) return ""
  return updatedAt
}

function limitSnapshot(limits, index) {
  var limit = index >= 0 && index < limits.length ? limits[index] : null
  if (!isPlainObject(limit)
      || typeof limit.label !== "string"
      || typeof limit.percent !== "number"
      || !isFinite(limit.percent) || limit.percent < 0 || limit.percent > 1
      || typeof limit.resetsAt !== "string"
      || (limit.resetsAt !== "" && !validTimestamp(limit.resetsAt)))
    return null
  return {
    label: boundedString(limit.label,
      index === 0 ? "Primary" : "Secondary"),
    percent: limit.percent,
    resetsAt: boundedString(limit.resetsAt, "")
  }
}

function parseRecord(raw, expectedId, nowMs) {
  var text = String(raw || "")
  if (text.length === 0 || text.length > 2 * 1024 * 1024) return null
  var record
  try {
    record = JSON.parse(text)
  } catch (_error) {
    return null
  }
  if (!validRecordShape(record, expectedId)) return null

  var updatedAt = freshUpdatedAt(record.updatedAt, nowMs)
  if (updatedAt === "") return null

  var rawLimits = record.limits
  if (rawLimits.length > 16) return null
  var limits = []
  for (var index = 0; index < rawLimits.length; index++) {
    var limit = limitSnapshot(rawLimits, index)
    if (!limit) return null
    if (limits.length < 2) limits.push(limit)
  }
  if (!hasDisplayData(record, limits)) return null

  var primary = limits.length > 0 ? limits[0] : null
  var secondary = limits.length > 1 ? limits[1] : null
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
    updatedAtMs: Date.parse(updatedAt),
    expiresAtMs: Date.parse(updatedAt) + 24 * 60 * 60 * 1000,
    refreshing: false,
    backend: "omarchy.agents"
  }
}
