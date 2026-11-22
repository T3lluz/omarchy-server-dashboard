// Run with: node tests/alerts.test.js
// What the notifications say and how each one's life goes (Model.alertNote,
// calmNote, alertState).
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { alerts, alertNote, calmNote, alertState, roomTone }")()
const pixelSource = fs.readFileSync(path.join(__dirname, "..", "Pixels.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Pixels = new Function(pixelSource + "\nreturn { icons }")()

const snap = (over) => Object.assign({
  disks: [{ mount: "/", percent: 93 }, { mount: "/srv/media", percent: 40 }],
  containers: [
    { name: "immich", state: "running", status: "Up 2 hours (unhealthy)" },
    { name: "jellyfin", state: "restarting", status: "Restarting (1) 5 seconds ago" },
    { name: "web", state: "running", status: "Up 3 days" }
  ],
  failedUnits: [{ name: "backup.service" }]
}, over || {})

let passed = 0
function test(name, fn) { fn(); passed++ }

test("every alert key gets a note with an icon that exists and one plain sentence", () => {
  const s = snap()
  const keys = Object.keys(Model.alerts(s)).concat(["server"])
  assert.deepStrictEqual(keys.sort(), ["container:immich", "container:jellyfin", "disk:/", "server", "unit:backup.service"])
  for (const key of keys) {
    for (const note of [Model.alertNote(key, s, "twolluz", ""), Model.calmNote(key, s, "twolluz")]) {
      assert.ok(Pixels.icons[note.icon], key + " icon " + note.icon)
      assert.ok(/^(cross|check|meter:\d+)$/.test(note.mark), key + " mark " + note.mark)
      assert.ok(note.title && note.title.length <= 40, key + " title " + note.title)
      assert.ok(/^[^\n]+\.$/.test(note.body), key + " body " + note.body)
      assert.ok(!/[—–]/.test(note.title + note.body), key + " has a dash")
      assert.strictEqual(note.key, key)
    }
  }
})

test("the server going quiet, and coming back", () => {
  const down = Model.alertNote("server", null, "twolluz", "Timed out reaching twolluz")
  assert.strictEqual(down.title, "twolluz is down")
  assert.strictEqual(down.body, "Timed out reaching twolluz.")
  assert.strictEqual(down.icon, "server")
  assert.strictEqual(down.mark, "cross")
  assert.strictEqual(down.tone, Model.roomTone("system"))
  assert.strictEqual(Model.alertNote("server", null, "twolluz", "").body, "It stopped answering over SSH.")
  assert.strictEqual(Model.alertNote("server", null, "twolluz", "Rebooting…").body, "Rebooting.")
  const back = Model.calmNote("server", snap(), "twolluz")
  assert.strictEqual(back.title, "twolluz is back")
  assert.strictEqual(back.body, "It answers over SSH again.")
  assert.strictEqual(back.mark, "check")
})

test("a disk filling carries its level on the meter, and its new one once it has room", () => {
  const note = Model.alertNote("disk:/", snap(), "twolluz", "")
  assert.strictEqual(note.title, "Disk almost full")
  assert.strictEqual(note.body, "/ on twolluz is 93% full.")
  assert.strictEqual(note.mark, "meter:93")
  assert.strictEqual(note.tone, "cyan")
  const freed = snap({ disks: [{ mount: "/", percent: 81.6 }] })
  const calm = Model.calmNote("disk:/", freed, "twolluz")
  assert.strictEqual(calm.title, "Disk has room again")
  assert.strictEqual(calm.body, "/ on twolluz is 82% full.")
  assert.strictEqual(calm.mark, "meter:82")
})

test("containers and services say what happened to them", () => {
  const s = snap()
  assert.strictEqual(Model.alertNote("container:immich", s, "twolluz").title, "Container unhealthy")
  assert.strictEqual(Model.alertNote("container:immich", s, "twolluz").body, "immich is unhealthy on twolluz.")
  assert.strictEqual(Model.alertNote("container:jellyfin", s, "twolluz").title, "Container restarting")
  assert.strictEqual(Model.alertNote("container:jellyfin", s, "twolluz").body, "jellyfin keeps restarting on twolluz.")
  assert.strictEqual(Model.alertNote("container:immich", s, "twolluz").tone, "green")
  assert.strictEqual(Model.calmNote("container:immich", s, "twolluz").title, "Container healthy again")
  const unit = Model.alertNote("unit:backup.service", s, "twolluz")
  assert.strictEqual(unit.title, "Service failed")
  assert.strictEqual(unit.body, "backup.service failed on twolluz.")
  assert.strictEqual(unit.icon, "warning-diamond")
  assert.strictEqual(Model.calmNote("unit:backup.service", s, "twolluz").title, "Service recovered")
})

test("an alert stands, clears, or goes with what it was about", () => {
  const s = snap()
  for (const key of Object.keys(Model.alerts(s))) assert.strictEqual(Model.alertState(key, s), "on", key)
  // No answer yet says nothing new.
  assert.strictEqual(Model.alertState("disk:/", null), "on")
  const fine = snap({
    disks: [{ mount: "/", percent: 70 }],
    containers: [{ name: "immich", state: "running", status: "Up 3 hours (healthy)" }],
    failedUnits: []
  })
  assert.strictEqual(Model.alertState("disk:/", fine), "clear")
  assert.strictEqual(Model.alertState("container:immich", fine), "clear")
  assert.strictEqual(Model.alertState("unit:backup.service", fine), "clear")
  // Unmounted, removed: nothing to say about them any more.
  assert.strictEqual(Model.alertState("disk:/srv/backup", fine), "gone")
  assert.strictEqual(Model.alertState("container:jellyfin", fine), "gone")
  const stopped = snap({ disks: [{ mount: "/", percent: 50 }], failedUnits: [],
    containers: [{ name: "immich", state: "exited", status: "Exited (0) 1 second ago" }] })
  assert.strictEqual(Model.alertState("container:immich", stopped), "gone", "a stopped container is not well again")
})

test("the client's QML names each method once, so it still loads", () => {
  // A second `function forget` once kept the whole widget off the bar.
  for (const file of ["ServerClient.qml", "BarWidget.qml"]) {
    const qml = fs.readFileSync(path.join(__dirname, "..", file), "utf8")
    const seen = {}
    for (const m of qml.matchAll(/^  function (\w+)\(/gm)) {
      assert.ok(!seen[m[1]], file + " has two " + m[1] + "()")
      seen[m[1]] = true
    }
  }
})

console.log(passed + " alert tests passed")
