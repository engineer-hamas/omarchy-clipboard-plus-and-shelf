#!/usr/bin/env node

const assert = require("node:assert/strict");
const shelf = require("../ClipboardShelf.js");
const history = require("../ClipboardHistory.js");

function validateItems(items) {
  return history.validateHistory(items, shelf.maxItemsPerShelf, false);
}

function parsedShelves(values) {
  const result = shelf.validateShelves(JSON.parse(JSON.stringify(values)), validateItems);
  assert.equal(result.status, "ok");
  return result.shelves;
}

function serialize(values) {
  const result = shelf.serializeShelves(values, validateItems, history.utf8ByteLength, 1);
  assert.equal(result.status, "ok");
  return result.text;
}

assert.equal(shelf.maxShelves, 9);
assert.equal(shelf.maxItemsPerShelf, 100);
assert.equal(shelf.maxShelfNameLength, 64);

assert.deepEqual(shelf.defaultShelf(), { name: "Default", items: [] });
assert.equal(shelf.normalizedShelfName("  My\u0000Shelf\n"), "MyShelf");
assert.equal(shelf.normalizedShelfName("  "), "");
assert.equal(shelf.normalizedShelfName("x".repeat(80)).length, 64);

assert.deepEqual(shelf.ensureShelf([]), [{ name: "Default", items: [] }]);
assert.equal(shelf.ensureShelf([shelf.defaultShelf()]).length, 1);

assert.equal(shelf.nextShelfName([]), "Shelf 1");
assert.equal(shelf.nextShelfName([{ name: "Shelf 1", items: [] }]), "Shelf 2");
assert.equal(
  shelf.nextShelfName([
    { name: "Shelf 1", items: [] },
    { name: "Shelf 2", items: [] },
    { name: "Work", items: [] }
  ]),
  "Shelf 3"
);

let created = shelf.addShelf([]);
assert.equal(created.status, "ok");
assert.equal(created.index, 0);
assert.deepEqual(created.shelves, [{ name: "Shelf 1", items: [] }]);

created = shelf.addShelf(Array.from({ length: 9 }, (_, i) => ({ name: "S" + i, items: [] })));
assert.equal(created.status, "full");
assert.equal(created.index, -1);

const withItems = shelf.addShelf([{ name: "Default", items: [{ type: "text", text: "hi" }] }]);
assert.equal(withItems.status, "ok");
assert.equal(withItems.index, 1);
assert.deepEqual(withItems.shelves[1], { name: "Shelf 1", items: [] });

const basic = parsedShelves([
  { name: "Default", items: [{ type: "text", text: "hello" }] },
  { name: "Projects", items: [{ type: "image", path: "/tmp/a.png", mime: "image/png" }] }
]);
assert.equal(basic.length, 2);
assert.equal(basic[0].name, "Default");
assert.equal(basic[0].items[0].text, "hello");
assert.equal(basic[1].name, "Projects");
assert.equal(basic[1].items[0].type, "image");

assert.equal(shelf.validateShelves(null, validateItems).status, "invalid");
assert.equal(shelf.validateShelves("nope", validateItems).status, "invalid");
assert.equal(shelf.validateShelves([{ name: "  ", items: [] }], validateItems).status, "invalid");
assert.equal(shelf.validateShelves([{ items: [] }], validateItems).status, "invalid");

const truncated = shelf.validateShelves(
  Array.from({ length: 12 }, (_, i) => ({ name: "S" + i, items: [] })),
  validateItems
);
assert.equal(truncated.status, "ok");
assert.equal(truncated.shelves.length, 9);
assert.equal(truncated.truncated, true);

const oversized = shelf.validateShelves(
  [{ name: "Big", items: [{ type: "text", text: "x".repeat(1024 * 1024 + 1) }] }],
  validateItems
);
assert.equal(oversized.status, "oversized");

const serialized = serialize(basic);
assert.ok(serialized.endsWith("\n"));
const reparsed = parsedShelves(JSON.parse(serialized));
assert.equal(reparsed.length, 2);
assert.equal(reparsed[1].items[0].path, "/tmp/a.png");
assert.equal(reparsed[1].items[0].capturedAt, undefined);

const roundtrip = shelf.validateShelves(JSON.parse(serialize(basic)), validateItems);
assert.equal(roundtrip.status, "ok");
assert.equal(roundtrip.containsOversized, false);

const replaced = shelf.replaceShelfItems(basic, 0, [{ type: "text", text: "new" }]);
assert.equal(replaced[0].items[0].text, "new");
assert.equal(replaced[0].name, "Default");
assert.equal(basic[0].items[0].text, "hello");

const renamed = shelf.renameShelf(basic, 1, "  Work-shelf  ");
assert.equal(renamed[1].name, "Work-shelf");
assert.equal(shelf.renameShelf(basic, 1, "   ")[1].name, "Projects");

const removed = shelf.removeShelf(basic, 0);
assert.equal(removed.length, 1);
assert.equal(removed[0].name, "Projects");
assert.equal(basic.length, 2);

const a = parsedShelves([{ name: "X", items: [{ type: "text", text: "t" }] }]);
const b = parsedShelves([{ name: "X", items: [{ type: "text", text: "t" }] }]);
const c = parsedShelves([{ name: "X", items: [{ type: "text", text: "u" }] }]);
assert.equal(shelf.shelvesEqual(a, b), true);
assert.equal(shelf.shelvesEqual(a, c), false);
assert.equal(shelf.shelvesEqual(a, []), false);

assert.equal(shelf.shelfWriteDisposition({ status: "ok", shelves: a }, b, false, false), "pending");
assert.equal(shelf.shelfWriteDisposition({ status: "ok", shelves: b }, a, true, false), "confirmed");
assert.equal(shelf.shelfWriteDisposition({ status: "ok", shelves: b }, a, true, true), "failed");
assert.equal(shelf.shelfWriteDisposition({ status: "invalid", shelves: [] }, a, true, false), "failed");

console.log("clipboard-shelf: all assertions passed");