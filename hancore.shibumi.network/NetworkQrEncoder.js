.pragma library

// Shibumi-owned, dependency-free QR encoder for the bounded Wi-Fi sharing
// surface. It implements byte mode, error correction level M, versions 1-11,
// all eight masks, and a four-module quiet zone. It deliberately does not
// provide a general file, URL, image, or process boundary.

var MaxInputBytes = 240
var QuietZone = 4
var DataCodewords = [0, 16, 28, 44, 64, 86, 108, 124, 154, 182, 216, 254]
var BlockGroups = [
  null,
  [[1, 26, 16]],
  [[1, 44, 28]],
  [[1, 70, 44]],
  [[2, 50, 32]],
  [[2, 67, 43]],
  [[4, 43, 27]],
  [[4, 49, 31]],
  [[2, 60, 38], [2, 61, 39]],
  [[3, 58, 36], [2, 59, 37]],
  [[4, 69, 43], [1, 70, 44]],
  [[1, 80, 50], [4, 81, 51]]
]

function failure(code) {
  return { ok: false, code: code, size: 0, rows: [] }
}

function utf8Bytes(value) {
  if (typeof value !== "string" || value.length > MaxInputBytes)
    return null
  try {
    var encoded = unescape(encodeURIComponent(value))
    if (encoded.length < 1 || encoded.length > MaxInputBytes) return null
    var result = []
    for (var index = 0; index < encoded.length; index++)
      result.push(encoded.charCodeAt(index))
    return result
  } catch (error) {
    return null
  }
}

function appendBits(target, value, count) {
  if (!Array.isArray(target) || typeof value !== "number"
      || typeof count !== "number" || count < 0 || count > 31)
    throw new Error("invalid bit append")
  for (var bit = count - 1; bit >= 0; bit--)
    target.push((value >>> bit) & 1)
}

function selectVersion(byteCount) {
  for (var version = 1; version < DataCodewords.length; version++) {
    var countBits = version < 10 ? 8 : 16
    if (12 + 4 + countBits + byteCount * 8
        <= DataCodewords[version] * 8)
      return version
  }
  return 0
}

function dataCodewords(bytes, version) {
  var capacity = DataCodewords[version] * 8
  var bits = []
  // ECI assignment 26 declares UTF-8 explicitly. Without it, scanners may
  // reinterpret non-ASCII SSIDs as legacy QR byte-mode encodings.
  appendBits(bits, 7, 4)
  appendBits(bits, 26, 8)
  appendBits(bits, 4, 4)
  appendBits(bits, bytes.length, version < 10 ? 8 : 16)
  for (var index = 0; index < bytes.length; index++)
    appendBits(bits, bytes[index], 8)
  appendBits(bits, 0, Math.min(4, capacity - bits.length))
  while (bits.length % 8 !== 0) bits.push(0)
  var result = []
  for (var offset = 0; offset < bits.length; offset += 8) {
    var value = 0
    for (var bit = 0; bit < 8; bit++) value = value * 2 + bits[offset + bit]
    result.push(value)
  }
  var pad = 0
  while (result.length < DataCodewords[version]) {
    result.push(pad % 2 === 0 ? 0xEC : 0x11)
    pad++
  }
  if (result.length !== DataCodewords[version])
    throw new Error("data capacity mismatch")
  return result
}

function reedSolomonMultiply(left, right) {
  var x = left
  var y = right
  var result = 0
  for (var bit = 0; bit < 8; bit++) {
    if ((y & 1) !== 0) result ^= x
    var carry = (x & 0x80) !== 0
    x = (x << 1) & 0xFF
    if (carry) x ^= 0x1D
    y >>>= 1
  }
  return result
}

function reedSolomonDivisor(degree) {
  if (degree < 1 || degree > 255) throw new Error("invalid ECC degree")
  var result = new Array(degree).fill(0)
  result[degree - 1] = 1
  var root = 1
  for (var index = 0; index < degree; index++) {
    for (var coefficient = 0; coefficient < degree; coefficient++) {
      result[coefficient] = reedSolomonMultiply(result[coefficient], root)
      if (coefficient + 1 < degree)
        result[coefficient] ^= result[coefficient + 1]
    }
    root = reedSolomonMultiply(root, 2)
  }
  return result
}

function reedSolomonRemainder(data, divisor) {
  var result = new Array(divisor.length).fill(0)
  for (var index = 0; index < data.length; index++) {
    var factor = data[index] ^ result[0]
    for (var shift = 0; shift + 1 < result.length; shift++)
      result[shift] = result[shift + 1]
    result[result.length - 1] = 0
    for (var coefficient = 0; coefficient < result.length; coefficient++)
      result[coefficient] ^= reedSolomonMultiply(divisor[coefficient], factor)
  }
  return result
}

function interleavedCodewords(data, version) {
  var groups = BlockGroups[version]
  var blocks = []
  var offset = 0
  for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
    var group = groups[groupIndex]
    for (var count = 0; count < group[0]; count++) {
      var totalLength = group[1]
      var dataLength = group[2]
      var blockData = data.slice(offset, offset + dataLength)
      offset += dataLength
      var divisor = reedSolomonDivisor(totalLength - dataLength)
      blocks.push({ data: blockData,
        ecc: reedSolomonRemainder(blockData, divisor) })
    }
  }
  if (offset !== data.length) throw new Error("block capacity mismatch")
  var result = []
  var maxDataLength = 0
  for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++)
    maxDataLength = Math.max(maxDataLength, blocks[blockIndex].data.length)
  for (var dataIndex = 0; dataIndex < maxDataLength; dataIndex++) {
    for (var dataBlock = 0; dataBlock < blocks.length; dataBlock++) {
      if (dataIndex < blocks[dataBlock].data.length)
        result.push(blocks[dataBlock].data[dataIndex])
    }
  }
  var eccLength = blocks[0].ecc.length
  for (var eccIndex = 0; eccIndex < eccLength; eccIndex++) {
    for (var eccBlock = 0; eccBlock < blocks.length; eccBlock++) {
      if (blocks[eccBlock].ecc.length !== eccLength)
        throw new Error("mixed ECC block length")
      result.push(blocks[eccBlock].ecc[eccIndex])
    }
  }
  return result
}

function emptyMatrix(size, value) {
  var result = []
  for (var row = 0; row < size; row++)
    result.push(new Array(size).fill(value))
  return result
}

function setFunction(modules, functions, x, y, dark) {
  if (x < 0 || y < 0 || y >= modules.length || x >= modules.length) return
  modules[y][x] = dark === true
  functions[y][x] = true
}

function drawFinder(modules, functions, centerX, centerY) {
  for (var dy = -4; dy <= 4; dy++) {
    for (var dx = -4; dx <= 4; dx++) {
      var distance = Math.max(Math.abs(dx), Math.abs(dy))
      setFunction(modules, functions, centerX + dx, centerY + dy,
        distance !== 2 && distance !== 4)
    }
  }
}

function drawAlignment(modules, functions, centerX, centerY) {
  for (var dy = -2; dy <= 2; dy++) {
    for (var dx = -2; dx <= 2; dx++)
      setFunction(modules, functions, centerX + dx, centerY + dy,
        Math.max(Math.abs(dx), Math.abs(dy)) !== 1)
  }
}

function alignmentPositions(version, size) {
  if (version === 1) return []
  var count = Math.floor(version / 7) + 2
  var step = version === 32 ? 26
    : Math.floor((version * 4 + count * 2 + 1) / (count * 2 - 2)) * 2
  var result = [6]
  for (var position = size - 7; result.length < count; position -= step)
    result.splice(1, 0, position)
  return result
}

function drawVersion(modules, functions, version) {
  if (version < 7) return
  var remainder = version
  for (var bit = 0; bit < 12; bit++)
    remainder = (remainder << 1) ^ ((remainder >>> 11) * 0x1F25)
  var bits = (version << 12) | remainder
  var size = modules.length
  for (var index = 0; index < 18; index++) {
    var dark = ((bits >>> index) & 1) !== 0
    var a = size - 11 + index % 3
    var b = Math.floor(index / 3)
    setFunction(modules, functions, a, b, dark)
    setFunction(modules, functions, b, a, dark)
  }
}

function drawFormat(modules, functions, mask) {
  var data = mask
  var remainder = data
  for (var bit = 0; bit < 10; bit++)
    remainder = (remainder << 1) ^ ((remainder >>> 9) * 0x537)
  var bits = ((data << 10) | remainder) ^ 0x5412
  var size = modules.length
  function formatBit(index) { return ((bits >>> index) & 1) !== 0 }
  for (var first = 0; first <= 5; first++)
    setFunction(modules, functions, 8, first, formatBit(first))
  setFunction(modules, functions, 8, 7, formatBit(6))
  setFunction(modules, functions, 8, 8, formatBit(7))
  setFunction(modules, functions, 7, 8, formatBit(8))
  for (var upper = 9; upper < 15; upper++)
    setFunction(modules, functions, 14 - upper, 8, formatBit(upper))
  for (var lower = 0; lower < 8; lower++)
    setFunction(modules, functions, size - 1 - lower, 8, formatBit(lower))
  for (var right = 8; right < 15; right++)
    setFunction(modules, functions, 8, size - 15 + right,
      formatBit(right))
  setFunction(modules, functions, 8, size - 8, true)
}

function drawFunctionPatterns(modules, functions, version) {
  var size = modules.length
  for (var index = 0; index < size; index++) {
    setFunction(modules, functions, 6, index, index % 2 === 0)
    setFunction(modules, functions, index, 6, index % 2 === 0)
  }
  drawFinder(modules, functions, 3, 3)
  drawFinder(modules, functions, size - 4, 3)
  drawFinder(modules, functions, 3, size - 4)
  var positions = alignmentPositions(version, size)
  for (var yIndex = 0; yIndex < positions.length; yIndex++) {
    for (var xIndex = 0; xIndex < positions.length; xIndex++) {
      if (yIndex === 0 && xIndex === 0
          || yIndex === 0 && xIndex === positions.length - 1
          || yIndex === positions.length - 1 && xIndex === 0) continue
      drawAlignment(modules, functions,
        positions[xIndex], positions[yIndex])
    }
  }
  drawFormat(modules, functions, 0)
  drawVersion(modules, functions, version)
}

function drawCodewords(modules, functions, codewords) {
  var size = modules.length
  var bitLength = codewords.length * 8
  var bitIndex = 0
  for (var right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5
    for (var vertical = 0; vertical < size; vertical++) {
      var upward = ((right + 1) & 2) === 0
      var y = upward ? size - 1 - vertical : vertical
      for (var column = 0; column < 2; column++) {
        var x = right - column
        if (functions[y][x]) continue
        if (bitIndex < bitLength) {
          var value = codewords[bitIndex >>> 3]
          modules[y][x] = ((value >>> (7 - (bitIndex & 7))) & 1) !== 0
        }
        bitIndex++
      }
    }
  }
  if (bitIndex < bitLength) throw new Error("matrix capacity mismatch")
}

function maskBit(mask, x, y) {
  switch (mask) {
  case 0: return (x + y) % 2 === 0
  case 1: return y % 2 === 0
  case 2: return x % 3 === 0
  case 3: return (x + y) % 3 === 0
  case 4: return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0
  case 5: return x * y % 2 + x * y % 3 === 0
  case 6: return (x * y % 2 + x * y % 3) % 2 === 0
  case 7: return ((x + y) % 2 + x * y % 3) % 2 === 0
  default: throw new Error("invalid mask")
  }
}

function applyMask(modules, functions, mask) {
  for (var y = 0; y < modules.length; y++) {
    for (var x = 0; x < modules.length; x++) {
      if (!functions[y][x] && maskBit(mask, x, y))
        modules[y][x] = !modules[y][x]
    }
  }
}

function runPenalty(values) {
  var result = 0
  var runColor = values[0]
  var runLength = 1
  for (var index = 1; index < values.length; index++) {
    if (values[index] === runColor) runLength++
    else {
      if (runLength >= 5) result += 3 + runLength - 5
      runColor = values[index]
      runLength = 1
    }
  }
  if (runLength >= 5) result += 3 + runLength - 5
  return result
}

function patternPenalty(values) {
  var result = 0
  for (var index = 0; index + 10 < values.length; index++) {
    var first = ""
    for (var offset = 0; offset < 11; offset++)
      first += values[index + offset] ? "1" : "0"
    if (first === "00001011101" || first === "10111010000") result += 40
  }
  return result
}

function penaltyScore(modules) {
  var size = modules.length
  var result = 0
  var dark = 0
  for (var y = 0; y < size; y++) {
    result += runPenalty(modules[y]) + patternPenalty(modules[y])
    for (var x = 0; x < size; x++) if (modules[y][x]) dark++
  }
  for (var xColumn = 0; xColumn < size; xColumn++) {
    var column = []
    for (var yRow = 0; yRow < size; yRow++) column.push(modules[yRow][xColumn])
    result += runPenalty(column) + patternPenalty(column)
  }
  for (var row = 0; row + 1 < size; row++) {
    for (var columnIndex = 0; columnIndex + 1 < size; columnIndex++) {
      var color = modules[row][columnIndex]
      if (modules[row][columnIndex + 1] === color
          && modules[row + 1][columnIndex] === color
          && modules[row + 1][columnIndex + 1] === color) result += 3
    }
  }
  result += Math.floor(Math.abs(dark * 100 / (size * size) - 50) / 5) * 10
  return result
}

function addQuietZone(modules) {
  var size = modules.length + QuietZone * 2
  var rows = []
  var white = "0".repeat(size)
  for (var top = 0; top < QuietZone; top++) rows.push(white)
  for (var y = 0; y < modules.length; y++) {
    var row = "0".repeat(QuietZone)
    for (var x = 0; x < modules.length; x++) row += modules[y][x] ? "1" : "0"
    rows.push(row + "0".repeat(QuietZone))
  }
  for (var bottom = 0; bottom < QuietZone; bottom++) rows.push(white)
  return rows
}

function encode(value) {
  var bytes = utf8Bytes(value)
  if (!bytes) return failure("invalid")
  var version = selectVersion(bytes.length)
  if (version === 0) return failure("too-long")
  try {
    var data = dataCodewords(bytes, version)
    var codewords = interleavedCodewords(data, version)
    var size = version * 4 + 17
    var modules = emptyMatrix(size, false)
    var functions = emptyMatrix(size, false)
    drawFunctionPatterns(modules, functions, version)
    drawCodewords(modules, functions, codewords)
    var bestMask = 0
    var bestPenalty = Infinity
    for (var mask = 0; mask < 8; mask++) {
      applyMask(modules, functions, mask)
      drawFormat(modules, functions, mask)
      var penalty = penaltyScore(modules)
      if (penalty < bestPenalty) {
        bestPenalty = penalty
        bestMask = mask
      }
      applyMask(modules, functions, mask)
    }
    applyMask(modules, functions, bestMask)
    drawFormat(modules, functions, bestMask)
    var rows = addQuietZone(modules)
    return { ok: true, code: "ready", size: rows.length, rows: rows }
  } catch (error) {
    return failure("internal")
  }
}
