function normalizeDesktopId(value) {
  var id = String(value || "").trim()
  if (id.slice(-8).toLowerCase() === ".desktop") id = id.slice(0, -8)
  if (!id || id.length > 255) return ""
  if (/[\x00-\x1f\x7f/\\]/.test(id)) return ""
  return id
}

function idKey(value) {
  return "$" + normalizeDesktopId(value)
}

function normalizeIdList(values, maxItems) {
  if (!Array.isArray(values)) return []
  var limit = Math.max(0, Number(maxItems) || 128)
  var result = []
  var seen = ({})
  for (var i = 0; i < values.length && result.length < limit; i++) {
    var id = normalizeDesktopId(values[i])
    var key = idKey(id)
    if (!id || seen[key]) continue
    seen[key] = true
    result.push(id)
  }
  return result
}

function idSet(values) {
  var result = ({})
  var normalized = normalizeIdList(values, 4096)
  for (var i = 0; i < normalized.length; i++) result[idKey(normalized[i])] = true
  return result
}

function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
  return String((entry && entry.genericName) || "")
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function")
      return entry.keywords.join(" ")
  } catch (error) {
  }
  return ""
}

function entrySearchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id]
    .join(" ").toLowerCase()
}

function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

function entryAcronym(entry) {
  var values = words([
    entry && entry.name,
    entry && entry.genericName,
    keywordText(entry),
    entry && entry.id
  ].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

function termMatches(entry, term) {
  if (!term) return true
  var id = normalizeDesktopId(entry && entry.id).toLowerCase()
  var name = entryName(entry).toLowerCase()
  var haystack = entrySearchText(entry)
  if (name.indexOf(term) >= 0 || id.indexOf(term) >= 0 || haystack.indexOf(term) >= 0)
    return true
  return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

function allTermsMatch(entry, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(entry, terms[i])) return false
  }
  return true
}

function fuzzyScore(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  if (!allTermsMatch(entry, q)) return -1

  var name = entryName(entry).toLowerCase()
  var id = normalizeDesktopId(entry && entry.id).toLowerCase()
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 10000 - name.length
  if (directId === 0) return 9500 - id.length
  if (directName > 0) return 8000 - directName * 10 - name.length
  if (directId > 0) return 7600 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  var acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length
  return 4000 - name.length
}

function candidateRows(values) {
  var result = []
  var source = values && typeof values.length === "number" ? values : []
  for (var i = 0; i < source.length; i++) {
    var entry = source[i]
    var id = normalizeDesktopId(entry && entry.id)
    var name = entryName(entry).trim()
    if (!entry || entry.noDisplay || !id || !name) continue
    result.push({
      id: id,
      name: name,
      genericName: entrySubtext(entry),
      comment: String(entry.comment || ""),
      icon: String(entry.icon || ""),
      entry: entry,
      duplicateKey: id.toLowerCase() + "\u0000" + name.toLowerCase()
    })
  }

  result.sort(function(a, b) {
    if (a.duplicateKey < b.duplicateKey) return -1
    if (a.duplicateKey > b.duplicateKey) return 1
    return 0
  })

  return result
}

function sortedEntries(values, query, favoriteIds, hiddenIds, includeHidden) {
  var q = String(query || "").trim()
  var favorites = normalizeIdList(favoriteIds, 4096)
  var favoriteOrder = ({})
  for (var i = 0; i < favorites.length; i++) favoriteOrder[idKey(favorites[i])] = i
  var hidden = idSet(hiddenIds)
  var candidates = candidateRows(values)
  var rows = []

  for (var j = 0; j < candidates.length; j++) {
    var row = candidates[j]
    var key = idKey(row.id)
    if (!includeHidden && hidden[key]) continue
    var score = fuzzyScore(row.entry, q)
    if (score < 0) continue
    row.favorite = favoriteOrder[key] !== undefined
    row.favoriteOrder = row.favorite ? favoriteOrder[key] : 2147483647
    row.hidden = hidden[key] === true
    row.score = score
    rows.push(row)
  }

  rows.sort(function(a, b) {
    if (a.favorite !== b.favorite) return a.favorite ? -1 : 1
    if (a.favorite && a.favoriteOrder !== b.favoriteOrder)
      return a.favoriteOrder - b.favoriteOrder
    if (q && a.score !== b.score) return b.score - a.score
    var aName = a.name.toLowerCase()
    var bName = b.name.toLowerCase()
    if (aName < bName) return -1
    if (aName > bName) return 1
    if (a.id < b.id) return -1
    if (a.id > b.id) return 1
    return 0
  })
  var deduplicated = []
  var seen = ({})
  for (var k = 0; k < rows.length; k++) {
    var rowKey = idKey(rows[k].id)
    if (seen[rowKey]) continue
    seen[rowKey] = true
    deduplicated.push(rows[k])
  }
  return deduplicated
}
