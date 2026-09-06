var maxShelves = 9
var maxItemsPerShelf = 100
var maxShelfNameLength = 64
var maxShelfFileBytes = 4 * 1024 * 1024

function defaultShelf() {
  return { name: "Default", items: [] }
}

function normalizedShelfName(raw) {
  var name = String(raw === undefined || raw === null ? "" : raw).trim()
  name = name.replace(/[\u0000\r\n]/g, "").slice(0, maxShelfNameLength)
  return name
}

function validateShelves(value, validateItems) {
  if (typeof value === "string" || value instanceof String) {
    var source = String(value || "[]")
    try {
      value = JSON.parse(source)
    } catch (e) {
      return { status: "invalid", shelves: [], truncated: false, containsOversized: false }
    }
  }
  if (!Array.isArray(value)) return { status: "invalid", shelves: [], truncated: false, containsOversized: false }

  var shelves = []
  var truncated = false
  var containsOversized = false
  var count = Math.min(value.length, maxShelves)

  for (var i = 0; i < count; i++) {
    var raw = value[i]
    if (!raw || typeof raw !== "object") return { status: "invalid", shelves: [], truncated: false, containsOversized: false }

    var name = normalizedShelfName(raw.name)
    if (!name) return { status: "invalid", shelves: [], truncated: false, containsOversized: false }

    var items = Array.isArray(raw.items) ? raw.items : []
    var itemResult = typeof validateItems === "function"
      ? validateItems(items)
      : { status: "ok", entries: items, truncated: false, containsOversized: false }
    if (itemResult.status !== "ok" || !Array.isArray(itemResult.entries))
      return { status: itemResult.status === "oversized" ? "oversized" : "invalid", shelves: [], truncated: false, containsOversized: true }
    if (itemResult.containsOversized)
      return { status: "oversized", shelves: [], truncated: false, containsOversized: true }

    shelves.push({ name: name, items: itemResult.entries })
    truncated = truncated || !!itemResult.truncated
    containsOversized = containsOversized || !!itemResult.containsOversized
  }

  if (value.length > maxShelves) truncated = true
  if (shelves.length === 0 && value.length > 0)
    return { status: "invalid", shelves: [], truncated: false, containsOversized: false }
  return { status: "ok", shelves: shelves, truncated: truncated, containsOversized: containsOversized }
}

function ensureShelf(shelves) {
  var values = Array.isArray(shelves) ? shelves : []
  if (values.length > 0) return values
  return [{ name: "Default", items: [] }]
}

function stripStoredItem(entry) {
  if (!entry || entry.type !== "image") {
    return { type: "text", text: String(entry && entry.text || "") }
  }
  var image = { type: "image", path: String(entry.path || ""), mime: String(entry.mime || "image/png") }
  if (entry.capturedAt !== undefined) image.capturedAt = entry.capturedAt
  return image
}

function serializeShelves(shelves, validateItems, byteLength, trailingNewlines) {
  if (typeof validateItems !== "function" || typeof byteLength !== "function")
    return { status: "invalid", text: "", containsOversized: false }

  var validated = validateShelves(shelves, validateItems)
  if (validated.status !== "ok" || validated.containsOversized) {
    return {
      status: validated.status === "ok" ? "oversized" : validated.status,
      text: "",
      containsOversized: !!validated.containsOversized
    }
  }

  var stored = []
  for (var i = 0; i < validated.shelves.length; i++) {
    var shelf = validated.shelves[i]
    var items = []
    for (var j = 0; j < shelf.items.length; j++) items.push(stripStoredItem(shelf.items[j]))
    stored.push({ name: shelf.name, items: items })
  }

  var suffix = Number(trailingNewlines) === 2 ? "\n\n" : "\n"
  var text = JSON.stringify(stored, null, 2) + suffix
  if (byteLength(text) > maxShelfFileBytes)
    return { status: "oversized", text: "", containsOversized: false }

  return { status: "ok", text: text, containsOversized: false }
}

function canonicalItem(entry) {
  if (!entry || typeof entry !== "object") return null
  if (entry.type === "image")
    return "i:" + String(entry.path || "") + ":" + String(entry.mime || "") + ":" + String(entry.capturedAt || "")
  if (entry.type === "text" && entry.oversized === true)
    return "o:" + String(entry.originalLength || 0)
  if (entry.type === "text") return "t:" + String(entry.text || "")
  return null
}

function shelvesEqual(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) return false

  for (var i = 0; i < left.length; i++) {
    var leftShelf = left[i] || {}
    var rightShelf = right[i] || {}
    if (normalizedShelfName(leftShelf.name) !== normalizedShelfName(rightShelf.name)) return false

    var leftItems = Array.isArray(leftShelf.items) ? leftShelf.items : []
    var rightItems = Array.isArray(rightShelf.items) ? rightShelf.items : []
    if (leftItems.length !== rightItems.length) return false

    for (var j = 0; j < leftItems.length; j++) {
      if (canonicalItem(leftItems[j]) !== canonicalItem(rightItems[j])) return false
    }
  }

  return true
}

function shelfWriteDisposition(result, expected, reportedSaved, failed) {
  if (!reportedSaved && !failed) return "pending"
  if (reportedSaved && !failed && result && result.status === "ok" && shelvesEqual(result.shelves, expected))
    return "confirmed"
  return "failed"
}

function replaceShelfItems(shelves, index, items) {
  var values = Array.isArray(shelves) ? shelves.map(function(s) { return s }) : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values
  var shelf = { name: values[target].name, items: Array.isArray(items) ? items : [] }
  var next = values.slice()
  next.splice(target, 1, shelf)
  return next
}

function renameShelf(shelves, index, name) {
  var values = Array.isArray(shelves) ? shelves.map(function(s) { return s }) : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values
  var nextName = normalizedShelfName(name)
  if (!nextName) return values
  var shelf = { name: nextName, items: Array.isArray(values[target].items) ? values[target].items : [] }
  var next = values.slice()
  next.splice(target, 1, shelf)
  return next
}

function removeShelf(shelves, index) {
  var values = Array.isArray(shelves) ? shelves.map(function(s) { return s }) : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values
  var next = values.slice()
  next.splice(target, 1)
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    maxShelves: maxShelves,
    maxItemsPerShelf: maxItemsPerShelf,
    maxShelfNameLength: maxShelfNameLength,
    maxShelfFileBytes: maxShelfFileBytes,
    defaultShelf: defaultShelf,
    normalizedShelfName: normalizedShelfName,
    validateShelves: validateShelves,
    ensureShelf: ensureShelf,
    serializeShelves: serializeShelves,
    shelvesEqual: shelvesEqual,
    shelfWriteDisposition: shelfWriteDisposition,
    replaceShelfItems: replaceShelfItems,
    renameShelf: renameShelf,
    removeShelf: removeShelf
  }
}