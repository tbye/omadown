// Countdown math for the bar label and the popup list.
//
// Two clocks, on purpose. With hours hidden, a date is a calendar day:
// tomorrow evening is still "1d", and the event day itself is "Today"
// until it is over. With hours shown, the label is the exact wait until
// one instant, split into 24-hour days and a remainder, so "1d 4h" is
// 28 hours and not a calendar day plus a leftover. A date with no time
// arrives at local midnight at the start of that day, then keeps counting
// through the day until the next midnight. A date with a time uses that
// local minute.
//
// Qt-free so node can run test/model.test.js. QML only formats nothing
// here; month names stay English, matching the rest of the shell.

var MAX_EVENTS = 50
var MAX_NAME = 60
var MS_PER_DAY = 86400000
var MS_PER_HOUR = 3600000
var MS_PER_MINUTE = 60000

var MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
]

function cleanName(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/^\s+|\s+$/g, "")
    .replace(/\s+/g, " ")
}

function asBool(value) {
  if (value === true || value === 1) return true
  if (typeof value !== "string") return false
  var text = value.replace(/^\s+|\s+$/g, "").toLowerCase()
  return text === "true" || text === "1" || text === "yes" || text === "on"
}

function asArray(value) {
  if (!value) return []
  if (Array.isArray(value)) return value
  if (typeof value.length === "number") {
    var out = []
    for (var i = 0; i < value.length; i++) out.push(value[i])
    return out
  }
  return []
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function parseDate(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text)
  if (!match) return null
  var year = parseInt(match[1], 10)
  var month = parseInt(match[2], 10)
  var day = parseInt(match[3], 10)
  if (year < 1 || month < 1 || month > 12) return null
  var probe = new Date(Date.UTC(year, month - 1, day))
  if (probe.getUTCFullYear() !== year || probe.getUTCMonth() !== month - 1 || probe.getUTCDate() !== day)
    return null
  return { year: year, month: month, day: day, date: match[1] + "-" + match[2] + "-" + match[3] }
}

// Empty is "no time", which means the whole calendar day. null is a bad value.
function parseTime(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (text === "") return ""
  var match = /^(\d{1,2}):(\d{2})$/.exec(text)
  if (!match) return null
  var hour = parseInt(match[1], 10)
  var minute = parseInt(match[2], 10)
  if (hour > 23 || minute > 59) return null
  return pad2(hour) + ":" + pad2(minute)
}

function normalizeEvent(raw, index) {
  if (!raw || typeof raw !== "object") return null
  var name = cleanName(raw.name)
  var parsed = parseDate(raw.date)
  if (!name || !parsed) return null
  var time = parseTime(raw.time)
  if (time === null) time = ""
  var id = String(raw.id === undefined || raw.id === null ? "" : raw.id).replace(/^\s+|\s+$/g, "")
  if (!id) id = "e" + index + "-" + parsed.date
  return {
    id: id,
    name: name,
    date: parsed.date,
    time: time,
    year: parsed.year,
    month: parsed.month,
    day: parsed.day
  }
}

function normalizeEvents(value) {
  var raw = asArray(value)
  var out = []
  var seen = {}
  for (var i = 0; i < raw.length; i++) {
    var event = normalizeEvent(raw[i], out.length)
    if (!event) continue
    if (seen[event.id]) {
      event = {
        id: event.id + "-" + i,
        name: event.name,
        date: event.date,
        time: event.time,
        year: event.year,
        month: event.month,
        day: event.day
      }
    }
    seen[event.id] = true
    out.push(event)
  }
  return out
}

function storedEvent(event) {
  return { id: event.id, name: event.name, date: event.date, time: event.time }
}

function storedList(events) {
  var out = []
  for (var i = 0; i < events.length; i++) out.push(storedEvent(events[i]))
  return out
}

function ymdOf(date) {
  return { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate() }
}

function calendarDayDiff(from, to) {
  var start = Date.UTC(from.year, from.month - 1, from.day)
  var end = Date.UTC(to.year, to.month - 1, to.day)
  return Math.round((end - start) / MS_PER_DAY)
}

// The instant the countdown is measuring. Date-only events use midnight at
// the start of a future day, and midnight at the end once that day has begun,
// so the day of the event still reads as in progress.
function targetMs(event, now) {
  if (event.time) {
    var bits = event.time.split(":")
    return new Date(event.year, event.month - 1, event.day, Number(bits[0]), Number(bits[1]), 0, 0).getTime()
  }
  var cal = calendarDayDiff(ymdOf(now), event)
  if (cal > 0) return new Date(event.year, event.month - 1, event.day, 0, 0, 0, 0).getTime()
  return new Date(event.year, event.month - 1, event.day + 1, 0, 0, 0, 0).getTime()
}

function inspect(event, now) {
  var cal = calendarDayDiff(ymdOf(now), event)
  var delta = targetMs(event, now) - now.getTime()
  var past = event.time ? delta < 0 : cal < 0
  return { cal: cal, delta: delta, past: past, today: cal === 0 }
}

function splitDuration(delta) {
  var abs = Math.abs(delta)
  if (abs < 1000) abs = 0
  return {
    past: delta < 0 && abs > 0,
    days: Math.floor(abs / MS_PER_DAY),
    hours: Math.floor((abs % MS_PER_DAY) / MS_PER_HOUR),
    minutes: Math.floor((abs % MS_PER_HOUR) / MS_PER_MINUTE)
  }
}

function plural(n, word) {
  return n + " " + word + (n === 1 ? "" : "s")
}

function barLabel(info, showHours) {
  if (!showHours) {
    if (info.past && info.cal === 0) return "Passed"
    if (!info.past && info.cal === 0) return "Today"
    if (info.past) return Math.abs(info.cal) + "d ago"
    return info.cal + "d"
  }
  var span = splitDuration(info.delta)
  var text = ""
  if (span.days > 0) text = span.days + "d" + (span.hours > 0 ? " " + span.hours + "h" : "")
  else if (span.hours > 0) text = span.hours + "h"
  else if (span.minutes > 0) text = span.minutes + "m"
  else return span.past ? "Passed" : "Now"
  return span.past ? text + " ago" : text
}

function longRemaining(info, showHours) {
  if (!showHours) {
    if (info.past && info.cal === 0) return "passed"
    if (!info.past && info.cal === 0) return "today"
    var days = Math.abs(info.cal)
    return plural(days, "day") + (info.past ? " ago" : "")
  }
  var span = splitDuration(info.delta)
  var bits = []
  if (span.days > 0) bits.push(plural(span.days, "day"))
  if (span.hours > 0) bits.push(plural(span.hours, "hour"))
  if (span.days === 0 && span.hours === 0)
    bits.push(span.minutes > 0 ? plural(span.minutes, "minute") : "now")
  var text = bits.join(", ")
  if (span.past && text !== "now") text += " ago"
  return text
}

// Vertical bars are one icon wide, so the wordy labels become a short stack.
function verticalLines(bar) {
  if (bar === "Today" || bar === "Passed") return ["0d"]
  if (bar === "Now") return ["0m"]
  return String(bar).split(" ")
}

function whenLine(event) {
  var line = MONTHS[event.month - 1] + " " + event.day + ", " + event.year
  if (event.time) line += " at " + event.time
  return line
}

function parts(event, now, showHours) {
  var ready = event && event.year ? event : normalizeEvent(event, 0)
  if (!ready) return { bar: "", vertical: [], long: "", past: false, today: false, when: "" }
  var info = inspect(ready, now)
  var bar = barLabel(info, !!showHours)
  return {
    bar: bar,
    vertical: verticalLines(bar),
    long: longRemaining(info, !!showHours),
    past: info.past,
    today: info.today && !info.past,
    when: whenLine(ready)
  }
}

function tooltip(event, now, showHours) {
  if (!event) return "Countdowns"
  var view = parts(event, now, showHours)
  return event.name + " · " + view.when + " · " + view.long
}

function nearnessMs(event, now) {
  if (event.time) return Math.abs(targetMs(event, now) - now.getTime())
  return Math.abs(calendarDayDiff(ymdOf(now), event)) * MS_PER_DAY
}

function sortByNearness(events, now) {
  var list = normalizeEvents(events)
  var ranked = []
  for (var i = 0; i < list.length; i++) {
    var event = list[i]
    ranked.push({
      event: event,
      near: nearnessMs(event, now),
      past: inspect(event, now).past,
      name: event.name
    })
  }
  ranked.sort(function(a, b) {
    if (a.near !== b.near) return a.near - b.near
    if (a.past !== b.past) return a.past ? 1 : -1
    if (a.name !== b.name) return a.name < b.name ? -1 : 1
    if (a.event.id === b.event.id) return 0
    return a.event.id < b.event.id ? -1 : 1
  })
  var out = []
  for (var j = 0; j < ranked.length; j++) out.push(ranked[j].event)
  return out
}

function orderKey(events) {
  var ids = []
  for (var i = 0; i < events.length; i++) ids.push(events[i].id)
  return ids.join("\n")
}

function indexOfId(events, id) {
  var wanted = String(id || "")
  for (var i = 0; i < events.length; i++) if (events[i].id === wanted) return i
  return -1
}

function findById(events, id) {
  var index = indexOfId(events, id)
  return index < 0 ? null : events[index]
}

function pickBarEvent(events, defaultId, now) {
  var list = normalizeEvents(events)
  if (list.length === 0) return null
  var pinned = findById(list, defaultId)
  if (pinned) return pinned
  return sortByNearness(list, now)[0]
}

function validateDraft(draft) {
  var name = cleanName(draft && draft.name)
  if (!name) return { ok: false, error: "Enter a name" }
  if (name.length > MAX_NAME) return { ok: false, error: "Name is too long" }
  var parsed = parseDate(draft && draft.date)
  if (!parsed) return { ok: false, error: "Use a date like 2026-12-25" }
  var time = parseTime(draft && draft.time)
  if (time === null) return { ok: false, error: "Use a time like 09:30, or leave it blank" }
  return {
    ok: true,
    name: name,
    date: parsed.date,
    time: time,
    year: parsed.year,
    month: parsed.month,
    day: parsed.day
  }
}

function newId(nowMs, rand) {
  var ms = Number(nowMs)
  if (!isFinite(ms)) ms = Date.now()
  var roll = Number(rand)
  if (!isFinite(roll)) roll = Math.random()
  var n = Math.floor(Math.abs(roll) * 1000000)
  return "c" + Math.floor(ms).toString(36) + n.toString(36)
}

function uniqueId(list, id) {
  var taken = {}
  for (var i = 0; i < list.length; i++) taken[list[i].id] = true
  var next = id
  while (!next || taken[next]) next = (next || "c") + "x"
  return next
}

function nextDefault(current, id, pin) {
  if (pin) return id
  if (String(current || "") === id) return ""
  return String(current || "")
}

function addCountdown(events, defaultId, draft, id) {
  var list = normalizeEvents(events)
  if (list.length >= MAX_EVENTS) return { ok: false, error: "You already have 50 countdowns" }
  var valid = validateDraft(draft)
  if (!valid.ok) return valid
  var eventId = uniqueId(list, String(id || "") || newId(Date.now(), Math.random()))
  list.push({
    id: eventId,
    name: valid.name,
    date: valid.date,
    time: valid.time,
    year: valid.year,
    month: valid.month,
    day: valid.day
  })
  return {
    ok: true,
    events: storedList(list),
    defaultId: nextDefault(defaultId, eventId, !!(draft && draft.pin))
  }
}

function updateCountdown(events, defaultId, id, draft) {
  var list = normalizeEvents(events)
  var index = indexOfId(list, id)
  if (index < 0) return { ok: false, error: "That countdown is gone" }
  var valid = validateDraft(draft)
  if (!valid.ok) return valid
  list[index] = {
    id: list[index].id,
    name: valid.name,
    date: valid.date,
    time: valid.time,
    year: valid.year,
    month: valid.month,
    day: valid.day
  }
  return {
    ok: true,
    events: storedList(list),
    defaultId: nextDefault(defaultId, list[index].id, !!(draft && draft.pin))
  }
}

function removeCountdown(events, defaultId, id) {
  var list = normalizeEvents(events)
  var next = []
  for (var i = 0; i < list.length; i++) if (list[i].id !== id) next.push(list[i])
  var def = String(defaultId || "")
  if (def === id) def = ""
  return { events: storedList(next), defaultId: def }
}

function cycleDefault(events, defaultId, now) {
  var list = sortByNearness(events, now)
  if (list.length === 0) return ""
  if (list.length === 1) return list[0].id
  var current = pickBarEvent(events, defaultId, now)
  var index = 0
  for (var i = 0; i < list.length; i++) if (current && list[i].id === current.id) index = i
  return list[(index + 1) % list.length].id
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_EVENTS: MAX_EVENTS,
    MAX_NAME: MAX_NAME,
    asBool: asBool,
    parseDate: parseDate,
    parseTime: parseTime,
    normalizeEvents: normalizeEvents,
    parts: parts,
    tooltip: tooltip,
    sortByNearness: sortByNearness,
    orderKey: orderKey,
    indexOfId: indexOfId,
    findById: findById,
    pickBarEvent: pickBarEvent,
    addCountdown: addCountdown,
    updateCountdown: updateCountdown,
    removeCountdown: removeCountdown,
    cycleDefault: cycleDefault,
    newId: newId
  }
}
