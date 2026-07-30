.pragma library

function normalize(value) {
  return String(value || "").trim().toLocaleLowerCase()
}

function words(value) {
  return normalize(value).split(/[^a-z0-9@._+-]+/).filter(Boolean)
}

function fuzzyScore(queryValue, candidateValue) {
  const query = normalize(queryValue)
  const candidate = normalize(candidateValue)
  if (query === "" || candidate === "") return Number.POSITIVE_INFINITY
  const contiguous = candidate.indexOf(query)
  if (contiguous >= 0) return contiguous
  let previous = -1
  let gaps = 0
  for (let index = 0; index < query.length; index++) {
    const position = candidate.indexOf(query.charAt(index), previous + 1)
    if (position < 0) return Number.POSITIVE_INFINITY
    if (previous >= 0) gaps += position - previous - 1
    previous = position
  }
  return 100 + gaps
}

function uniqueStrings(values) {
  const result = []
  for (let index = 0; index < values.length; index++) {
    const value = String(values[index] || "").trim()
    if (value !== "" && result.indexOf(value) < 0) result.push(value)
  }
  return result
}

function entryTags(entry) {
  const tags = Array.isArray(entry.searchTags) ? entry.searchTags : []
  return uniqueStrings(tags.concat(
    Array.isArray(entry.kinds) ? entry.kinds : []))
}

function primaryEntryFields(entry) {
  return [
    { value: entry.name, weight: 0 },
    { value: entry.id, weight: 7 },
    { value: entry.provider, weight: 12 },
    { value: entry.author, weight: 15 },
    { value: entry.category, weight: 17 },
    { value: entryTags(entry).join(" "), weight: 20 }
  ]
}

function entryFields(entry, includeDescription) {
  const fields = primaryEntryFields(entry)
  if (includeDescription === true)
    fields.push({ value: entry.description, weight: 28 })
  return fields
}

function directTokenScore(token, candidateValue) {
  const candidate = normalize(candidateValue)
  if (candidate === "") return Number.POSITIVE_INFINITY
  const position = candidate.indexOf(token)
  if (position >= 0) return position
  if (token.length > 1) return Number.POSITIVE_INFINITY
  const candidates = words(candidate)
  for (let index = 0; index < candidates.length; index++) {
    if (candidates[index].startsWith(token)) return index
  }
  return Number.POSITIVE_INFINITY
}

function directEntryScore(entry, queryValue, includeDescription) {
  const tokens = words(queryValue)
  if (tokens.length === 0) return 0
  const fields = entryFields(entry, includeDescription)
  let total = 0
  for (let tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
    let best = Number.POSITIVE_INFINITY
    for (let fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
      const score = directTokenScore(
        tokens[tokenIndex], fields[fieldIndex].value)
      best = Math.min(best, score + fields[fieldIndex].weight)
    }
    if (!Number.isFinite(best)) return Number.POSITIVE_INFINITY
    total += best
  }
  const query = normalize(queryValue)
  const name = normalize(entry.name)
  if (name === query) total -= 30
  else if (name.startsWith(query)) total -= 12
  return total
}

function fuzzyEntryScore(entry, queryValue, includeDescription) {
  const tokens = words(queryValue)
  if (tokens.length === 0) return 0
  const fields = entryFields(entry, includeDescription)
  let total = 0
  for (let tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
    if (tokens[tokenIndex].length < 2) return Number.POSITIVE_INFINITY
    let best = Number.POSITIVE_INFINITY
    for (let fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
      const score = fuzzyScore(tokens[tokenIndex], fields[fieldIndex].value)
      best = Math.min(best, score + fields[fieldIndex].weight)
    }
    if (!Number.isFinite(best)) return Number.POSITIVE_INFINITY
    total += best
  }
  return total
}

function ranked(matches) {
  return matches.sort(function(left, right) {
    return left.score - right.score
      || String(left.entry.name || left.entry.id || "").localeCompare(
        String(right.entry.name || right.entry.id || ""))
  })
}

function collectMatches(source, query, scorer, includeDescription) {
  const matches = []
  for (let index = 0; index < source.length; index++) {
    const score = scorer(source[index], query, includeDescription)
    if (Number.isFinite(score))
      matches.push({ entry: source[index], score: score })
  }
  return matches
}

function filterAndRank(entries, queryValue) {
  const source = Array.isArray(entries) ? entries : []
  const query = normalize(queryValue)
  if (query === "") return source.slice()
  // Prefer intentional catalog metadata. Free-form descriptions remain a
  // fallback so relational wording such as "Bluetooth audio owner" does not
  // pollute a direct search for the Audio widget.
  const primaryDirect = collectMatches(
    source, query, directEntryScore, false)
  if (primaryDirect.length > 0)
    return ranked(primaryDirect).map(function(match) {
      return match.entry
    })
  const expandedDirect = collectMatches(
    source, query, directEntryScore, true)
  if (expandedDirect.length > 0)
    return ranked(expandedDirect).map(function(match) {
      return match.entry
    })
  const primaryFuzzy = collectMatches(
    source, query, fuzzyEntryScore, false)
  if (primaryFuzzy.length > 0)
    return ranked(primaryFuzzy).map(function(match) {
      return match.entry
    })
  const expandedFuzzy = collectMatches(
    source, query, fuzzyEntryScore, true)
  return ranked(expandedFuzzy).map(function(match) {
    return match.entry
  })
}

function completionCandidates(entries) {
  const result = []
  const source = Array.isArray(entries) ? entries : []
  for (let index = 0; index < source.length; index++) {
    const entry = source[index]
    result.push({
      type: "plugin",
      value: String(entry.name || entry.id || ""),
      label: String(entry.name || entry.id || "")
    })
    if (String(entry.provider || "") !== "") result.push({
      type: "provider",
      value: String(entry.provider),
      label: String(entry.provider)
    })
    if (String(entry.author || "") !== "") result.push({
      type: "author",
      value: String(entry.author),
      label: String(entry.author)
    })
    const tags = entryTags(entry)
    for (let tagIndex = 0; tagIndex < tags.length; tagIndex++) result.push({
      type: "tag",
      value: tags[tagIndex],
      label: tags[tagIndex]
    })
  }
  return result
}

function completions(entries, queryValue, limitValue) {
  const query = normalize(queryValue).replace(/^@/, "")
  if (query.length < 2) return []
  const candidates = completionCandidates(entries)
  const matches = {}
  for (let index = 0; index < candidates.length; index++) {
    const candidate = candidates[index]
    const label = normalize(candidate.label)
    if (label === query) continue
    const score = fuzzyScore(query, label.replace(/^@/, ""))
    if (!Number.isFinite(score)) continue
    const key = candidate.type + ":" + label
    if (matches[key]) {
      matches[key].count++
    } else {
      matches[key] = {
        type: candidate.type,
        value: candidate.value,
        label: candidate.label,
        count: 1,
        score: score
      }
    }
  }
  const typeOrder = { plugin: 0, provider: 1, author: 2, tag: 3 }
  const result = Object.keys(matches).map(function(key) {
    return matches[key]
  }).sort(function(left, right) {
    return typeOrder[left.type] - typeOrder[right.type]
      || left.score - right.score
      || right.count - left.count
      || left.label.localeCompare(right.label)
  })
  const limit = Math.max(1, Number(limitValue || 3))
  return result.slice(0, limit)
}

function completionTarget(completion) {
  return completion ? String(completion.value || completion.label || "") : ""
}

function ghostText(queryValue, completion) {
  const query = String(queryValue || "")
  const target = completionTarget(completion)
  if (query === "" || target === "") return ""
  const queryLower = query.toLocaleLowerCase()
  const targetLower = target.toLocaleLowerCase()
  return targetLower.startsWith(queryLower)
    ? target : query + "  → " + target
}
