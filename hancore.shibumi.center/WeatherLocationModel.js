.pragma library

function normalized(value) {
  return String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
}

// Do not turn obvious test/placeholder input into a real saved location just
// because GeoNames happens to contain an alias or low-quality row for it.
function isMeaningfulQuery(value) {
  var query = normalized(value).replace(/[\s,._-]/g, "")
  if (query.length < 2) return false
  return !(query.length >= 3 && /^(.)\1+$/.test(query))
}

// Open-Meteo geocoding response -> compact rows for the location picker.
function parseGeocodingResults(raw, query) {
  try {
    if (query !== undefined && !isMeaningfulQuery(query)) return []
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results
    if (!results || !results.length) return []

    var countrySuggestions = []
    var suggestions = []
    for (var index = 0; index < results.length; index++) {
      var result = results[index]
      if (!result || !result.name || result.latitude === undefined
          || result.longitude === undefined) continue
      var featureCode = String(result.feature_code || "")
      if (featureCode !== "" && !/^(PPL|PCL)/.test(featureCode)) continue
      var country = String(result.country || "")
      var isCountry = /^PCL/.test(featureCode)
      var region = isCountry
        ? "Country" + (result.country_code
          ? " · " + String(result.country_code) : "")
        : [result.admin1, country].filter(
            function(part) { return !!part }).join(", ")
      var suggestion = {
        name: String(result.name),
        description: region,
        latitude: result.latitude,
        longitude: result.longitude,
        featureCode: featureCode,
        countryCode: String(result.country_code || "")
      }
      if (isCountry && normalized(result.name) === normalized(query))
        countrySuggestions.push(suggestion)
      else
        suggestions.push(suggestion)
    }
    return countrySuggestions.concat(suggestions).slice(0, 5)
  } catch (_error) {
    return []
  }
}

// Prefer the highlighted geocoded result. A raw name remains a valid wttr.in
// fallback when Open-Meteo has no match or is temporarily unavailable.
function locationCommit(text, suggestions, selectedIndex) {
  var name = String(text || "").replace(/^\s+|\s+$/g, "")
  if (name === "")
    return { name: "", latitude: null, longitude: null }

  var choices = suggestions || []
  var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0,
    choices.length - 1))
  var suggestion = choices[index]
  if (suggestion) return suggestion
  return { name: name, latitude: null, longitude: null }
}
