.pragma library

function maximumQueryLength() { return 160 }

function boundedText(value, optional) {
  if ((value === undefined || value === null) && optional) return ""
  if (typeof value !== "string" || value.length > maximumQueryLength()
      || /[\x00-\x1f\x7f-\x9f<>\u061c\u200e\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069]/.test(value)) return null
  // JSON can contain escaped unpaired UTF-16 surrogates even in valid UTF-8.
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff) {
      var next = value.charCodeAt(++i)
      if (!(next >= 0xdc00 && next <= 0xdfff)) return null
    } else if (code >= 0xdc00 && code <= 0xdfff) return null
  }
  return value.replace(/^\s+|\s+$/g, "")
}

function normalized(value) {
  var text = boundedText(value, true)
  return text === null ? "" : text.toLowerCase()
}

function coordinate(value, maximum) {
  return typeof value === "number" && isFinite(value)
    && value >= -maximum && value <= maximum
}

// Do not turn obvious test/placeholder input into a real saved location just
// because GeoNames happens to contain an alias or low-quality row for it.
function isMeaningfulQuery(value) {
  var query = normalized(value).replace(/[\s,._-]/g, "")
  if (query.length < 2) return false
  return !(query.length >= 3 && /^(.)\1+$/.test(query))
}

// Open-Meteo geocoding response -> compact validated rows. The character cap
// is a parser budget, NOT a transfer-time byte bound for StdioCollector.
function parseGeocodingResults(raw, query) {
  try {
    if (typeof raw !== "string" || raw.length === 0 || raw.length > 65536) return []
    if (query !== undefined && !isMeaningfulQuery(query)) return []
    var data = JSON.parse(raw)
    if (!data || typeof data !== "object" || Array.isArray(data)
        || (data.error !== undefined && data.error !== false)) return []
    var results = data.results
    if (!Array.isArray(results) || results.length > 5) return []

    var countrySuggestions = []
    var suggestions = []
    for (var index = 0; index < results.length; index++) {
      var result = results[index]
      // Preserve the existing invalid-row filtering, but never publish a row
      // containing coercible/non-finite coordinates or unbounded/markup text.
      if (!result || typeof result !== "object" || Array.isArray(result)
          || !coordinate(result.latitude, 90) || !coordinate(result.longitude, 180)) continue
      var name = boundedText(result.name, false)
      var country = boundedText(result.country, true)
      var admin = boundedText(result.admin1, true)
      var featureCode = boundedText(result.feature_code, true)
      var countryCode = boundedText(result.country_code, true)
      if (!name || country === null || admin === null || featureCode === null || countryCode === null
          || !/^[A-Z0-9]{0,8}$/.test(featureCode) || !/^([A-Z]{2})?$/.test(countryCode)) continue
      if (featureCode !== "" && !/^(PPL|PCL)/.test(featureCode)) continue
      var isCountry = /^PCL/.test(featureCode)
      var region = isCountry
        ? "Country" + (countryCode ? " · " + countryCode : "")
        : [admin, country].filter(function(part) { return !!part }).join(", ")
      var suggestion = {
        name: name,
        description: region,
        latitude: result.latitude,
        longitude: result.longitude,
        featureCode: featureCode,
        countryCode: countryCode
      }
      if (isCountry && normalized(result.name) === normalized(query))
        countrySuggestions.push(suggestion)
      else
        suggestions.push(suggestion)
    }
    return countrySuggestions.concat(suggestions)
  } catch (_error) {
    return []
  }
}

// Prefer the highlighted geocoded result. A raw name remains a valid wttr.in
// fallback when Open-Meteo has no match or is temporarily unavailable.
function locationCommit(text, suggestions, selectedIndex) {
  var name = boundedText(text, false)
  if (name === null) return null
  if (name === "")
    return { name: "", latitude: null, longitude: null }

  var choices = suggestions === undefined ? [] : suggestions
  if (!Array.isArray(choices) || choices.length > 5) return null
  var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0,
    choices.length - 1))
  var suggestion = choices[index]
  if (choices.length > 0) {
    if (!suggestion || typeof suggestion !== "object" || Array.isArray(suggestion)) return null
    var selectedName = boundedText(suggestion.name, false)
    if (!selectedName || !coordinate(suggestion.latitude, 90)
        || !coordinate(suggestion.longitude, 180)) return null
    return { name: selectedName, latitude: suggestion.latitude, longitude: suggestion.longitude }
  }
  return isMeaningfulQuery(name) ? { name: name, latitude: null, longitude: null } : null
}
