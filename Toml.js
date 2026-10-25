.pragma library

// Minimal TOML reader for notify-center's flat config. Supports sections,
// quoted strings, numbers, booleans, and single-line arrays. This is not a
// general TOML implementation; it deliberately covers only the keys the
// plugin documents.

function stripComment(line) {
  var quote = ""
  for (var i = 0; i < line.length; i++) {
    var c = line.charAt(i)
    if (quote) {
      if (c === quote && line.charAt(i - 1) !== "\\") quote = ""
    } else if (c === '"' || c === "'") {
      quote = c
    } else if (c === "#") {
      return line.slice(0, i)
    }
  }
  return line
}

function unquote(value) {
  var s = String(value)
  return s.replace(/\\n/g, "\n")
    .replace(/\\t/g, "\t")
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, "\\")
}

function splitList(inner) {
  var parts = []
  var current = ""
  var quote = ""
  for (var i = 0; i < inner.length; i++) {
    var c = inner.charAt(i)
    if (quote) {
      current += c
      if (c === quote && inner.charAt(i - 1) !== "\\") quote = ""
      continue
    }
    if (c === '"' || c === "'") {
      quote = c
      current += c
      continue
    }
    if (c === ",") {
      parts.push(current)
      current = ""
      continue
    }
    current += c
  }
  if (current.trim().length > 0) parts.push(current)
  return parts
}

function parseValue(raw) {
  var value = String(raw || "").trim()
  if (value === "true") return true
  if (value === "false") return false

  var doubleQuoted = value.match(/^"((?:[^"\\]|\\.)*)"$/)
  if (doubleQuoted) return unquote(doubleQuoted[1])
  var singleQuoted = value.match(/^'([^']*)'$/)
  if (singleQuoted) return singleQuoted[1]

  if (value.charAt(0) === "[" && value.charAt(value.length - 1) === "]") {
    var inner = value.slice(1, -1).trim()
    if (!inner) return []
    var rawItems = splitList(inner)
    var items = []
    for (var i = 0; i < rawItems.length; i++) {
      var item = rawItems[i].trim()
      if (item.length > 0) items.push(parseValue(item))
    }
    return items
  }

  var number = Number(value)
  if (isFinite(number) && value !== "") return number
  return value
}

function parse(text) {
  var out = {}
  var section = ""
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = stripComment(lines[i]).trim()
    if (!line) continue

    var sectionMatch = line.match(/^\[([A-Za-z0-9_.-]+)\]$/)
    if (sectionMatch) {
      section = sectionMatch[1]
      continue
    }

    var equals = line.indexOf("=")
    if (equals < 0) continue
    var key = line.slice(0, equals).trim()
    if (!/^[A-Za-z0-9_-]+$/.test(key)) continue
    var raw = line.slice(equals + 1).trim()
    var fullKey = section ? section + "." + key : key
    out[fullKey] = parseValue(raw)
  }
  return out
}
