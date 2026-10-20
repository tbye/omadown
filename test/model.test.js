#!/usr/bin/env node
"use strict"

var assert = require("assert")
var Model = require("../Model.js")

function at(year, month, day, hour, minute) {
  return new Date(year, month - 1, day, hour || 0, minute || 0, 0, 0)
}

function event(id, name, date, time) {
  return { id: id, name: name, date: date, time: time || "" }
}

function label(ev, now, hours) {
  var list = Model.normalizeEvents([ev])
  return Model.parts(list[0], now, hours).bar
}

var dec24evening = at(2026, 12, 24, 20, 0)
var christmas = event("xmas", "Christmas", "2026-12-25")

assert.strictEqual(label(christmas, dec24evening, false), "1d")
assert.strictEqual(label(christmas, dec24evening, true), "4h")
assert.strictEqual(label(christmas, at(2026, 12, 23, 20, 0), false), "2d")
assert.strictEqual(label(christmas, at(2026, 12, 23, 20, 0), true), "1d 4h")
assert.strictEqual(label(christmas, at(2026, 12, 25, 10, 0), false), "Today")
assert.strictEqual(label(christmas, at(2026, 12, 25, 10, 0), true), "14h")
assert.strictEqual(label(christmas, at(2026, 12, 26, 10, 0), false), "1d ago")
assert.strictEqual(label(christmas, at(2026, 12, 26, 10, 0), true), "10h ago")

var timed = event("meet", "Meet", "2026-12-25", "15:00")
assert.strictEqual(label(timed, at(2026, 12, 25, 10, 0), false), "Today")
assert.strictEqual(label(timed, at(2026, 12, 25, 10, 0), true), "5h")
assert.strictEqual(label(timed, at(2026, 12, 25, 16, 0), false), "Passed")
assert.strictEqual(label(timed, at(2026, 12, 25, 16, 0), true), "1h ago")
assert.strictEqual(label(timed, at(2026, 12, 23, 12, 0), true), "2d 3h")
assert.strictEqual(label(event("exact", "Exact", "2026-12-27", "15:00"), at(2026, 12, 25, 15, 0), true), "2d")

var soon = Model.parts(Model.normalizeEvents([event("s", "Soon", "2026-12-25", "10:40")])[0], at(2026, 12, 25, 10, 0), true)
assert.strictEqual(soon.bar, "40m")
assert.deepStrictEqual(soon.vertical, ["40m"])
assert.deepStrictEqual(Model.parts(christmas, at(2026, 12, 25, 10, 0), false).vertical, ["0d"])
assert.strictEqual(Model.parts(christmas, at(2026, 12, 23, 20, 0), true).long, "1 day, 4 hours")

var now = at(2026, 10, 19, 12, 0)
var mixed = [
  event("far", "Far", "2026-12-25"),
  event("tomorrow", "Tomorrow", "2026-10-21"),
  event("yesterday", "Yesterday", "2026-10-18"),
  event("soon", "Soon", "2026-10-19", "15:00")
]
assert.deepStrictEqual(Model.sortByNearness(mixed, now).map(function(item) { return item.id }), [
  "soon", "yesterday", "tomorrow", "far"
])

var tie = Model.sortByNearness([
  event("past", "Past", "2026-10-18"),
  event("next", "Next", "2026-10-20")
], now)
assert.deepStrictEqual(tie.map(function(item) { return item.id }), ["next", "past"])

assert.strictEqual(Model.pickBarEvent(mixed, "far", now).id, "far")
assert.strictEqual(Model.pickBarEvent(mixed, "missing", now).id, "soon")
assert.strictEqual(Model.pickBarEvent(mixed, "", now).id, "soon")
assert.strictEqual(Model.pickBarEvent([], "", now), null)

assert.strictEqual(Model.parseDate("2024-02-29").date, "2024-02-29")
assert.strictEqual(Model.parseDate("2025-02-29"), null)
assert.strictEqual(Model.parseDate("2026-04-31"), null)
assert.strictEqual(Model.parseDate("12/25/2026"), null)
assert.strictEqual(Model.parseTime("9:05"), "09:05")
assert.strictEqual(Model.parseTime(""), "")
assert.strictEqual(Model.parseTime("24:00"), null)
assert.strictEqual(Model.asBool("yes"), true)
assert.strictEqual(Model.asBool(false), false)

var dirty = Model.normalizeEvents([
  null,
  { name: "  Launch day  ", date: "2026-12-25", time: "9:30" },
  { id: "ok", name: "Keep", date: "2026-01-02", time: "nope" },
  { name: "", date: "2026-01-02" }
])
assert.strictEqual(dirty.length, 2)
assert.strictEqual(dirty[0].name, "Launch day")
assert.strictEqual(dirty[0].time, "09:30")
assert.strictEqual(dirty[0].id, "e0-2026-12-25")
assert.strictEqual(dirty[1].time, "")

var added = Model.addCountdown([], "", { name: "Trip", date: "2026-11-01", time: "", pin: true }, "trip")
assert.strictEqual(added.ok, true)
assert.strictEqual(added.defaultId, "trip")
assert.deepStrictEqual(added.events, [{ id: "trip", name: "Trip", date: "2026-11-01", time: "" }])
assert.strictEqual(Model.addCountdown(added.events, "trip", { name: "Trip", date: "2026-11-01" }, "trip").events[1].id, "tripx")

var unpinned = Model.addCountdown(added.events, added.defaultId, {
  name: "Other", date: "2026-11-02", pin: false
}, "other")
assert.strictEqual(unpinned.defaultId, "trip")

var edited = Model.updateCountdown(unpinned.events, unpinned.defaultId, "trip", {
  name: "Trip west", date: "2026-11-03", time: "8:00", pin: false
})
assert.strictEqual(edited.ok, true)
assert.strictEqual(edited.defaultId, "")
assert.strictEqual(edited.events[0].name, "Trip west")
assert.strictEqual(edited.events[0].time, "08:00")

var removed = Model.removeCountdown(edited.events, "other", "other")
assert.strictEqual(removed.defaultId, "")
assert.strictEqual(removed.events.length, 1)

assert.strictEqual(Model.addCountdown([], "", { name: "", date: "2026-11-01" }).error, "Enter a name")
assert.strictEqual(Model.addCountdown([], "", { name: "X", date: "November 1" }).error, "Use a date like 2026-12-25")
assert.strictEqual(Model.addCountdown([], "", { name: "X", date: "2026-11-01", time: "noon" }).error, "Use a time like 09:30, or leave it blank")

var full = []
for (var i = 0; i < Model.MAX_EVENTS; i++) full.push(event("id" + i, "N" + i, "2026-10-19"))
assert.strictEqual(Model.addCountdown(full, "", { name: "More", date: "2026-10-20" }).ok, false)

var cycleEvents = [event("a", "A", "2026-10-21"), event("b", "B", "2026-12-25")]
assert.strictEqual(Model.cycleDefault(cycleEvents, "a", now), "b")
assert.strictEqual(Model.cycleDefault(cycleEvents, "", now), "b")
assert.strictEqual(Model.cycleDefault([event("only", "Only", "2026-10-21")], "", now), "only")

var source = [event("a", "A", "2026-10-21")]
Model.addCountdown(source, "", { name: "B", date: "2026-10-22", pin: true }, "b")
assert.strictEqual(source.length, 1)

console.log("model tests ok")
