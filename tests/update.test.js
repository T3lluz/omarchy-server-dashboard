// Update.js, the panel kit's update wording and banner. Run: node tests/update.test.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")

const dir = [path.join(__dirname, ".."), path.join(__dirname, "..", "components"), path.join(__dirname, "..", "ui")]
  .find(d => fs.existsSync(path.join(d, "Update.js")))
const source = fs.readFileSync(path.join(dir, "Update.js"), "utf8").replace(".pragma library", "")
const Update = new Function(source + "\nreturn { parse, ago, applying, line, notice }")()

const now = 1800000000
assert.strictEqual(Update.ago(30), "just now")
assert.strictEqual(Update.ago(300), "5 min ago")
assert.strictEqual(Update.ago(7300), "2 h ago")
assert.strictEqual(Update.ago(200000), "2 d ago")
assert.strictEqual(Update.parse("{\"a\":1}").a, 1)
assert.strictEqual(Update.parse("not json"), null)

const upToDate = { available: false, checked: now - 120, latest: "1.0.0" }
const newer = { available: true, checked: now - 60, current: "1.0.0", latest: "1.1.0", notes: ["Second"] }
const sameVersion = { available: true, checked: now - 60, current: "1.0.0", latest: "1.0.0", notes: [] }
assert.strictEqual(Update.line(null, null, now), "Not checked yet")
assert.strictEqual(Update.line(upToDate, null, now), "Up to date · checked 2 min ago")
assert.strictEqual(Update.line(newer, null, now), "Version 1.1.0 is available")
assert.strictEqual(Update.line(sameVersion, null, now), "An update is available", "no version bump, no number")
assert.strictEqual(Update.notice("Test", sameVersion, null, "1.0.0", now).text, "An update to Test is available")
assert.strictEqual(Update.line({ error: "Couldn't reach GitHub" }, null, now), "Couldn't reach GitHub")
assert.strictEqual(Update.line(newer, { state: "updating", at: now - 10 }, now), "Updating…")

assert.strictEqual(Update.notice("Test", upToDate, null, "1.0.0", now), null)
assert.strictEqual(Update.notice("Test", newer, null, "1.0.0", now).actionLabel, "Update")
assert.strictEqual(Update.notice("Test", newer, null, "1.0.0", now).text, "Test 1.1.0 is available")
assert.strictEqual(Update.notice("Test", newer, { state: "updating", at: now - 10 }, "1.0.0", now).busy, true)
assert.strictEqual(Update.notice("Test", null, { state: "updating", at: now - 900 }, "1.0.0", now), null, "an interrupted update is forgotten")
const failed = Update.notice("Test", newer, { state: "failed", message: "Couldn't reach GitHub", at: now - 60 }, "1.0.0", now)
assert.strictEqual(failed.actionLabel, "Retry")
assert.strictEqual(failed.tone, "urgent")
assert.strictEqual(Update.notice("Test", null, { state: "done", message: "Updated to 1.1.0.", version: "1.1.0", at: now - 60 }, "1.1.0", now).text,
  "Test: Updated to 1.1.0.")
assert.strictEqual(Update.notice("Test", null, { state: "done", message: "", version: "1.1.0", at: now - 60 }, "1.0.0", now), null,
  "a done state for another version is stale")
assert.strictEqual(Update.notice("Test", newer, null, "1.0.0", now, { update: "refresh", done: "check" }).icon, "refresh",
  "a plugin can name its own glyphs")

console.log("update tests passed")
