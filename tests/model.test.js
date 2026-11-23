// Run with: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { sections, parseError, parseProbe, withRates, parsePeers, percent, bytes, rate, uptime, temperature, level, targetHost, targetUser, validTarget, containerStatus, sizeOf, size, speed, uptimeLong, heroLines, problemCount, needsAttention, temperatureLevel, systemCells, systemStatus, networkFacts, networkRates, networkStatus, rateParts, rateText, machineFacts, systemFacts, disks, diskFacts, containerCounts, containerNote, containerFacts, containerTrouble, containerPixel, processesStatus, runningHot, parseDf, parseNetDev, parseCpuTemp, alerts, alertLines, newAlerts, ROOM_TONES, ROOM_PIXELS, roomTone, roomPixel, GLYPHS, PIXEL_GLYPHS, pixelFor, UI_PIXELS, serverMark, markGrid, markLights, workingLights, parsePalette, contrast, roomToneHex, bigDigits, PIXEL_FONT, pixelText, drawable, meterCells, revealLine, scramble, breakable, keepUnits, barItems, barMark, hoverRows, hoverNote }")()
const pixelSource = fs.readFileSync(path.join(__dirname, "..", "Pixels.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Pixels = new Function(pixelSource + "\nreturn { icons }")()

const sample = (ts, idle, rx) => `@@TS
${ts}
@@HOST
homeserver
@@USER
casaos
@@OS
NAME="Ubuntu"
PRETTY_NAME="Ubuntu 24.04.1 LTS"
ID=ubuntu
@@UNAME
Linux 6.8.0-45-generic x86_64
@@CPU
model name	: Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz
6
@@STAT
cpu  1000 0 500 ${idle} 100 0 0 0 0 0
@@MEM
MemTotal:       16000000 kB
MemAvailable:    4000000 kB
SwapTotal:       2000000 kB
SwapFree:        1500000 kB
@@LOAD
0.52 0.40 0.31 2/412 9999
@@UP
273600.12 100.00
@@NET
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 999999   22748    0    0    0     0          0         0  999999   22748    0    0    0     0       0          0
  eno1: ${rx}       0    0    0    0     0          0         0    5000       0    0    0    0     0       0          0
docker0: 777777   0    0    0    0     0          0         0   777777       0    0    0    0     0       0          0
tailscale0: 555   0    0    0    0     0          0         0   555       0    0    0    0     0       0          0
@@DF
Filesystem     1024-blocks      Used Available Capacity Mounted on
udev               8000000         0   8000000       0% /dev
tmpfs              1600000      2000   1598000       1% /run
/dev/sda2        500000000 200000000 275000000      43% /
/dev/sda2        500000000 200000000 275000000      43% /var/lib/docker/overlay2
/dev/sda1           524288      6000    518288       2% /boot/efi
/dev/sdb1       3900000000 1000000000 2900000000    26% /DATA
overlay          500000000 200000000 275000000      43% /var/lib/docker/overlay2/abc/merged
@@HWMON
/sys/class/hwmon/hwmon1/name:acpitz
/sys/class/hwmon/hwmon2/name:coretemp
/sys/class/hwmon/hwmon1/temp1_input:27800
/sys/class/hwmon/hwmon2/temp1_input:48000
@@THERMAL
@@PROC
    PID %CPU %MEM   RSS COMMAND
   1553 12.4  1.4 466428 dockerd
   2001  3.0  0.6 200076 jellyfin
@@HASDOCKER
/usr/bin/docker
@@DOCKER
jellyfin|running|Up 3 days (healthy)|linuxserver/jellyfin:latest
adguard|exited|Exited (0) 2 hours ago|adguard/adguardhome
immich|running|Up About an hour|ghcr.io/immich-app/immich-server:release
@@UNITS
smartd.service loaded failed failed Self Monitoring and Reporting Technology (SMART) Daemon
@@REBOOT
yes
@@END
`

const a = Model.parseProbe(sample(100, 10000, 1000000))
assert.strictEqual(a.hostname, "homeserver")
assert.strictEqual(a.osName, "Ubuntu 24.04.1 LTS")
assert.strictEqual(a.kernel, "6.8.0-45-generic")
assert.strictEqual(a.cpuModel, "Intel Core i5-8500T")
assert.strictEqual(a.cores, 6)
assert.strictEqual(Math.round(a.memory.percent), 75)
assert.strictEqual(Math.round(a.memory.swapPercent), 25)
assert.strictEqual(a.load.one, 0.52)
assert.strictEqual(a.uptimeSeconds, 273600)
assert.deepStrictEqual(a.net.ifaces, ["eno1"])
assert.deepStrictEqual(a.disks.map(d => d.mount), ["/", "/DATA"])
assert.strictEqual(a.cpuTemp, 48)
assert.strictEqual(a.processes.length, 2)
assert.strictEqual(a.processes[0].name, "dockerd")
assert.deepStrictEqual(a.containers.map(c => c.name), ["immich", "jellyfin", "adguard"])
assert.strictEqual(a.failedUnits[0].name, "smartd.service")
assert.strictEqual(a.rebootRequired, true)
assert.strictEqual(Model.withRates(a, null, 0).cpuPercent, null)

// 5 s later: 1500 busy jiffies of 2000 total, 5 MB received.
const b = Model.withRates(Model.parseProbe(sample(105, 10500, 6000000)), a, 5)
assert.strictEqual(b.cpuPercent, 0)
const c = Model.withRates(Model.parseProbe(sample(110, 10600, 6000000).replace("cpu  1000 0 500", "cpu  2400 0 500")), b, 5)
assert.strictEqual(Math.round(c.cpuPercent), 93)
assert.strictEqual(b.rxRate, 1000000)
assert.strictEqual(b.txRate, 0)

assert.deepStrictEqual(Model.parseError("@@ERROR\nauth\nWrong password\n"), { kind: "auth", message: "Wrong password" })
assert.strictEqual(Model.parseError(sample(1, 1, 1)), null)
assert.strictEqual(Model.parseProbe("@@TS\n1\n"), null, "a truncated probe is not a snapshot")

const peers = Model.parsePeers("pixel\t100.1.1.1\tandroid\tonline\nbox\t100.2.2.2\tlinux\toffline\nhomeserver\t100.64.0.10\tlinux\tonline\n")
assert.deepStrictEqual(peers.map(p => p.name), ["homeserver", "pixel", "box"])

assert.strictEqual(Model.percent(42.6), "43%")
assert.strictEqual(Model.percent(null), "—")
assert.strictEqual(Model.bytes(1536), "1.5K")
assert.strictEqual(Model.bytes(500 * 1024 * 1024 * 1024), "500G")
assert.strictEqual(Model.rate(2 * 1024 * 1024), "2M/s")
assert.strictEqual(Model.uptime(273600), "3d 4h")
assert.strictEqual(Model.uptime(3900), "1h 5m")
assert.strictEqual(Model.temperature(47.6), "48°")
assert.strictEqual(Model.level(95, 75, 90), 2)
assert.strictEqual(Model.targetHost("casaos@100.64.0.10"), "100.64.0.10")
assert.strictEqual(Model.targetUser("casaos@100.64.0.10"), "casaos")
assert.strictEqual(Model.validTarget("casaos@100.64.0.10"), true)
assert.strictEqual(Model.validTarget("-oProxyCommand=x"), false)
assert.strictEqual(Model.validTarget("a b@host"), false)
assert.strictEqual(Model.containerStatus({ status: "Up 3 days (healthy)" }), "Up 3 days, healthy")
assert.strictEqual(Model.containerStatus({ status: "Up About an hour (health: starting)" }), "Up about an hour, starting")
assert.strictEqual(Model.containerStatus({ status: "Exited (0) 2 hours ago" }), "Stopped 2 hours ago")
assert.strictEqual(Model.containerStatus({ status: "Exited (137) 5 minutes ago" }), "Exited with code 137, 5 minutes ago")
assert.strictEqual(Model.containerStatus({ state: "created", status: "" }), "created")

// The panel's copy: sizes in one unit, rates with a space, uptime in words.
assert.strictEqual(Model.sizeOf(5.7 * 1024 ** 3, 14.5 * 1024 ** 3), "5.7 of 14.5 GB")
assert.strictEqual(Model.sizeOf(174 * 1024 ** 3, 467 * 1024 ** 3), "174 of 467 GB")
assert.strictEqual(Model.sizeOf(0, 0), "--")
assert.strictEqual(Model.speed(5.4 * 1024), "5.4 KB/s")
assert.strictEqual(Model.speed(300), "300 B/s")
assert.strictEqual(Model.speed(null), "--")
assert.strictEqual(Model.size(466428 * 1024), "455 MB")
assert.strictEqual(Model.uptimeLong(23 * 86400 + 3 * 3600 + 60), "23 days 3 hours")
assert.strictEqual(Model.uptimeLong(86400), "1 day")
assert.strictEqual(Model.uptimeLong(3900), "1 hour 5 minutes")
assert.strictEqual(Model.uptimeLong(30), "under a minute")

// The probe's own ps never counts as a process.
assert.deepStrictEqual(Model.parseProbe(sample(1, 1000, 0).replace("@@PROC\n", "@@PROC\n   99 100 0.0 4400 ps\n")).processes.filter(p => p.name === "ps"), [])

// The Network room: two rates as figures, what has gone each way since boot.
{
  const rates = Model.networkRates(b)
  assert.deepStrictEqual(rates.map(r => r.key), ["rx", "tx"])
  assert.deepStrictEqual(rates[0].parts, { number: 1000000 / 1024, decimals: 0, unit: "K/s" })
  assert.strictEqual(Model.rateText(rates[0].parts), "977")
  assert.strictEqual(Model.networkRates(a)[0].parts, null, "no rate before the second poll")
  assert.strictEqual(Model.rateText(null), "--")
  assert.strictEqual(Model.rateText(Model.rateParts(5.5 * 1024)), "5.5")
  assert.strictEqual(Model.rateText(Model.rateParts(5.5 * 1024), 0.5), "2.8", "counts up in the unit it ends in")
  assert.strictEqual(Model.rateText(Model.rateParts(9.97 * 1024)), "10", "never 10.0")
  assert.strictEqual(Model.rateParts(300).unit, "B/s")
  assert.strictEqual(Model.rateParts(2.5 * 1024 ** 3).unit, "G/s")
  assert.deepStrictEqual(Model.networkFacts(b), [{ label: "Received", value: "5.7 MB" }, { label: "Sent", value: "4.9 KB" }, { label: "Interfaces", value: "eno1" }])
  assert.deepStrictEqual(Model.networkFacts(null), [])
  assert.strictEqual(Model.networkStatus(b), "eno1")
  for (const v of [0, 300, 5.5 * 1024, 123.4 * 1024 ** 2, 2.5 * 1024 ** 3]) {
    const parts = Model.rateParts(v)
    assert.ok(Model.drawable(parts.unit), parts.unit + " can be drawn")
    assert.ok(/^[0-9.]+$/.test(Model.rateText(parts)), "the block face draws " + Model.rateText(parts))
  }
}

// The System room's readings when open.
{
  assert.deepStrictEqual(Model.machineFacts(b).map(f => f.label), ["Uptime", "Load", "Tasks", "Swap", "Cores", "Arch"])
  assert.strictEqual(Model.machineFacts(b)[1].value, "0.52 0.40 0.31")
  assert.strictEqual(Model.machineFacts(b)[3].value, "0.5 of 1.9 GB")
  assert.deepStrictEqual(Model.systemFacts(b).map(f => f.label), ["Processor", "System", "Kernel"])
  assert.deepStrictEqual(Model.systemFacts(null), [])
  assert.strictEqual(Model.systemStatus(b), "Up 3d 4h \u00B7 412 tasks")
}

// The System room's cells: the processor, memory and its temperature, each a
// figure over a meter over a state line, turning to the alert tone when hot.
{
  const cells = Model.systemCells(c)
  assert.deepStrictEqual(cells.map(r => r.key), ["cpu", "memory", "temp"])
  assert.strictEqual(Math.round(cells[0].value), 93)
  assert.strictEqual(cells[0].state, "Load 0.52")
  assert.strictEqual(cells[0].hot, true, "93% CPU is hot")
  assert.strictEqual(cells[1].state, "11.4 of 15.3 GB")
  assert.strictEqual(cells[1].suffix, "%")
  assert.strictEqual(cells[2].suffix, "\u00B0C")
  assert.strictEqual(cells[2].state, "Normal")
  assert.strictEqual(Model.systemCells(Object.assign({}, c, { cpuTemp: 90 }))[2].state, "Hot")
  assert.strictEqual(Model.systemCells(Object.assign({}, c, { cpuTemp: 90 }))[2].hot, true)
  assert.strictEqual(Model.systemCells(Object.assign({}, c, { cpuTemp: null })).length, 2)
  assert.strictEqual(Model.systemCells(a)[0].value, null, "no CPU share before the second poll")
  assert.deepStrictEqual(Model.systemCells(null), [])
  for (const cell of cells) assert.ok(cell.suffix === "" || Model.drawable(cell.suffix), cell.suffix + " can be drawn")

  // Disks: the root one first, a name each, hot at 90%.
  const list = Model.disks(c)
  assert.deepStrictEqual(list.map(d => d.name), ["Root", "DATA"])
  assert.strictEqual(list[0].detail, "191 of 477 GB")
  assert.strictEqual(list[0].hot, false)
  assert.deepStrictEqual(Model.diskFacts(c).map(f => f.label), ["/", "/DATA"])
  assert.deepStrictEqual(Model.disks(null), [])
  assert.strictEqual(Model.disks({ disks: [{ mount: "/mnt/media/", device: "x", percent: 95, usedBytes: 1, availableBytes: 1, totalBytes: 2 }] })[0].name, "media")
  assert.strictEqual(Model.runningHot(Object.assign({}, c, { cpuPercent: 10, disks: [{ mount: "/", percent: 95, usedBytes: 1, availableBytes: 1, totalBytes: 2 }] })), true)

  // Containers: counts, the state line and the two readings.
  const n = Model.containerCounts(c.containers)
  assert.deepStrictEqual(n, { total: 3, running: 2, stopped: 1, trouble: 0, checked: 1, healthy: 1 })
  assert.deepStrictEqual(Model.containerNote(c.containers), ["running", "1 stopped"])
  assert.deepStrictEqual(Model.containerFacts(c.containers), [{ label: "Running", value: "2 of 3" }, { label: "Healthy", value: "1 of 1" }])
  const sick = [{ name: "web", state: "running", status: "Up 2 hours (unhealthy)" }]
  assert.deepStrictEqual(Model.containerNote(sick), ["running", "1 unhealthy"])
  assert.deepStrictEqual(Model.containerNote([{ name: "a", state: "running", status: "Up 1 day (healthy)" }]), ["running", "1 healthy"])
  assert.strictEqual(Model.containerPixel(sick[0]), "warning-diamond")
  assert.strictEqual(Model.containerPixel(c.containers[2]), "stop", "the stopped one sorts last")
  assert.deepStrictEqual(Model.containerNote([]), [])
  assert.strictEqual(Model.processesStatus(c), "dockerd at 12.4%")
  assert.strictEqual(Model.processesStatus(null), "")
}

// The prompt line: what is going on, then facts to rotate through.
{
  const calm = Object.assign({}, c, { rebootRequired: false, failedUnits: [], containers: [], disks: [], cpuPercent: 10, memory: Object.assign({}, c.memory, { percent: 10 }) })
  const state = extra => Object.assign({ configured: true, online: true, snapshot: calm, status: "online", errorKind: "", busyAction: "" }, extra)
  assert.deepStrictEqual(Model.heroLines(state({ configured: false })), ["Connect a server over SSH"])
  assert.strictEqual(Model.heroLines(state())[0], "All clear")
  assert.ok(Model.heroLines(state()).length > 1, "a healthy server rotates through facts")
  assert.strictEqual(Model.needsAttention(calm), false)
  const withSnap = extra => state({ snapshot: Object.assign({}, calm, extra) })
  assert.deepStrictEqual(Model.heroLines(withSnap({ rebootRequired: true })), ["Reboot required"], "named when it is the only thing")
  assert.deepStrictEqual(Model.heroLines(withSnap({ failedUnits: [{ name: "a" }] })), ["1 alert"])
  // The count is everything listed: the banner's lines plus failed units.
  const listed = Object.assign({}, calm, { rebootRequired: true, failedUnits: [{ name: "a" }, { name: "b" }] })
  assert.strictEqual(Model.problemCount(listed), 3)
  assert.deepStrictEqual(Model.heroLines(state({ snapshot: listed })), ["3 alerts"])
  // Hot gauges are never "all clear", though they are not listed as alerts.
  assert.deepStrictEqual(Model.heroLines(withSnap({ cpuPercent: 97 })), ["Running hot"])
  assert.strictEqual(Model.needsAttention(Object.assign({}, calm, { cpuTemp: 93 })), true)
  // A temperature's meter stays low while calm and fills where it turns hot.
  assert.ok(Model.temperatureLevel(46) < 30)
  assert.strictEqual(Model.temperatureLevel(70), 40)
  assert.strictEqual(Model.temperatureLevel(85), 100)
  assert.strictEqual(Model.temperatureLevel(120), 100)
  assert.deepStrictEqual(Model.heroLines(state({ busyAction: "reboot:" })), ["Rebooting"])
  assert.deepStrictEqual(Model.heroLines(state({ online: false, status: "connecting" })), ["Connecting over SSH"])
  assert.deepStrictEqual(Model.heroLines(state({ online: false, status: "error", errorKind: "unreachable" })), ["Offline", "Retrying every 30 seconds"])
  assert.deepStrictEqual(Model.heroLines(state({ online: false, status: "error", errorKind: "auth" })), ["Password needed"])
  assert.deepStrictEqual(Model.heroLines(state({ online: false, status: "error", errorKind: "hostkey" })), ["Host key changed"])
}

// The probe of this very machine must parse too.
for (const f of process.argv.slice(2)) {
  const snap = Model.parseProbe(fs.readFileSync(f, "utf8"))
  assert.ok(snap && snap.memory && snap.disks.length > 0, "parses " + f)
  console.log(f, "→", snap.hostname, snap.osName, snap.disks.map(d => d.mount).join(","), "temp", snap.cpuTemp, "ifaces", snap.net.ifaces.join(","))
}

// Alerts: unhealthy and restart-looping containers, full disks, failed units.
{
  const snap = {
    containers: [
      { name: "web", state: "running", status: "Up 2 hours (unhealthy)" },
      { name: "db", state: "restarting", status: "Restarting (1) 3 seconds ago" },
      { name: "old", state: "exited", status: "Exited (0) 2 days ago" },
      { name: "ok", state: "running", status: "Up 3 days (healthy)" }
    ],
    disks: [{ mount: "/", percent: 93.4 }, { mount: "/srv", percent: 40 }],
    failedUnits: [{ name: "backup.service", description: "" }]
  }
  const now = Model.alerts(snap)
  assert.deepStrictEqual(Object.keys(now).sort(), ["container:db", "container:web", "disk:/", "unit:backup.service"])
  assert.strictEqual(now["disk:/"], "/ is 93% full")
  assert.strictEqual(now["container:db"], "db keeps restarting")
  assert.deepStrictEqual(Model.alerts(null), {})
  // The banner leaves failed units to their section and adds a pending reboot.
  assert.deepStrictEqual(Model.alertLines(Object.assign({}, snap, { rebootRequired: true })).slice(-1), ["Reboot required"])
  assert.ok(!Model.alertLines(snap).some(l => /backup/.test(l)), "failed units have their own section")
  assert.deepStrictEqual(Model.alertLines(null), [])
  // Only what is new since the last poll is announced.
  assert.deepStrictEqual(Model.newAlerts(now, now), [])
  assert.deepStrictEqual(Model.newAlerts({ "disk:/": "/ is 93% full" }, { "disk:/": "/ is 94% full", "unit:x": "x failed" }), ["x failed"])
}

// ------------------------------------------------------------------ rooms

// Every pixel icon the QML and the model name exists in Pixels.js.
{
  const used = new Set(Model.UI_PIXELS)
  for (const k in Model.ROOM_PIXELS) used.add(Model.ROOM_PIXELS[k])
  for (const k in Model.PIXEL_GLYPHS) used.add(Model.PIXEL_GLYPHS[k])
  const c = Model.withRates(Model.parseProbe(sample(105, 10050, 2000000)), Model.parseProbe(sample(100, 10000, 1000000)), 1)
  for (const cell of Model.systemCells(c)) used.add(cell.icon)
  for (const item of Model.barItems(c, ["cpu", "ram", "disk", "temp", "net"])) used.add(item.icon)
  for (const row of Model.hoverRows(c)) { used.add(row.icon); if (row.mark) used.add(row.mark) }
  for (const ct of c.containers) used.add(Model.containerPixel(ct))
  used.add(Model.barMark({ configured: true, status: "error", needsUser: false }).icon)
  used.add("server")
  // The QML names these directly; read them out of the files too.
  for (const f of fs.readdirSync(path.join(__dirname, "..")).filter(f => f.endsWith(".qml"))) {
    const text = fs.readFileSync(path.join(__dirname, "..", f), "utf8")
    for (const m of text.matchAll(/(?:name|icon):\s*"([a-z0-9-]+)"/g)) if (Pixels.icons[m[1]] || /-/.test(m[1])) used.add(m[1])
  }
  for (const name of used) assert.ok(Pixels.icons[name], name + " is in Pixels.js")
  for (const name in Pixels.icons) {
    const icon = Pixels.icons[name]
    assert.ok(icon.g24.length > 0 && icon.g12.length > 0, name + " has both grids")
    for (const r of icon.g12) assert.ok(r[0] >= 0 && r[1] >= 0 && r[0] + r[2] <= 12 && r[1] + r[3] <= 12, name + " stays on the 12 grid")
  }
}

// Every glyph the panel hands the kit has a pixel icon.
{
  for (const k in Model.GLYPHS) assert.ok(Model.pixelFor(Model.GLYPHS[k]) !== "", k + " maps to a pixel icon")
  assert.strictEqual(Model.pixelFor("\u{F06B0}"), "download", "the updater's banner glyph")
  assert.strictEqual(Model.pixelFor("\u{F012C}"), "check")
  assert.strictEqual(Model.pixelFor("x"), "")
}

// The mark: its parts together are the "server" icon in Pixels.js, each
// light one cell high and two wide; lights that are off move to "off".
{
  const cells = part => {
    const out = new Set()
    for (const [x, y, w, h] of Model.serverMark(part, [true, true]).g12)
      for (let i = 0; i < w; i++) for (let j = 0; j < h; j++) out.add((x + i) + "," + (y + j))
    return out
  }
  const all = new Set([...cells("frame"), ...cells("lines"), ...cells("on")])
  const icon = new Set()
  for (const [x, y, w, h] of Pixels.icons.server.g12) for (let i = 0; i < w; i++) for (let j = 0; j < h; j++) icon.add((x + i) + "," + (y + j))
  assert.deepStrictEqual([...all].sort(), [...icon].sort(), "the mark's parts make up the server icon")
  assert.strictEqual(cells("on").size, 4)
  assert.strictEqual(Model.serverMark("on", [true, false]).g12.length, 1)
  assert.strictEqual(Model.serverMark("off", [true, false]).g12.length, 1)
  assert.deepStrictEqual(Model.serverMark("frame").g24[0], Model.serverMark("frame").g12[0].map(v => v * 2))
  assert.deepStrictEqual(Model.markLights(0), [false, false])
  assert.deepStrictEqual(Model.markLights(0.45), [true, false])
  assert.deepStrictEqual(Model.markLights(1), [true, true])
  assert.deepStrictEqual(Model.workingLights(0), [true, false])
  assert.deepStrictEqual(Model.workingLights(1), [false, true])
}

// Tones are valid colours; a grey theme gets the tones' own hues.
{
  const greys = { blue: "#7a7a7a", cyan: "#808080", green: "#777777" }
  const theme = Model.parsePalette('color4 = "#123456"\nblue = "#3b82f6"\ncyan="#06b6d4"\n')
  assert.strictEqual(theme.blue, "#3b82f6")
  for (const k in Model.ROOM_TONES) {
    for (const pal of [theme, greys, {}]) assert.ok(/^#[0-9a-f]{6}$/.test(Model.roomToneHex(Model.roomTone(k), pal, "#cdd6f4")), k + " is a colour")
  }
  assert.strictEqual(Model.roomToneHex("", theme, "#cdd6f4"), "#cdd6f4", "no tone is the text colour")
  assert.notStrictEqual(Model.roomToneHex("blue", greys, "#cdd6f4"), Model.roomToneHex("green", greys, "#cdd6f4"))
  const white = { r: 1, g: 1, b: 1 }, black = { r: 0, g: 0, b: 0 }
  assert.ok(Math.abs(Model.contrast(white, black) - 21) < 0.01)
}

// Names break at their own separators, never mid-word, and decoding keeps
// the breaks where they are.
{
  const Z = "\u200B"
  assert.strictEqual(Model.breakable("immich_machine_learning"), "immich_" + Z + "machine_" + Z + "learning")
  assert.strictEqual(Model.breakable("/srv/backups"), "/" + Z + "srv/" + Z + "backups")
  assert.strictEqual(Model.breakable("kworker/R-amdgpu"), "kworker/" + Z + "R-amdgpu")
  assert.strictEqual(Model.breakable("smartd.service"), "smartd." + Z + "service")
  assert.strictEqual(Model.breakable("a b. c"), "a b. c", "nothing before a space")
  assert.strictEqual(Model.breakable("kworker at 100.0%, 14.5 GB, 12:30"), "kworker at 100.0%, 14.5 GB, 12:30", "numbers stay whole")
  assert.strictEqual(Model.breakable(Model.breakable("a_b")), "a_" + Z + "b", "twice is once")
  assert.strictEqual(Model.breakable(""), "")
  assert.strictEqual(Model.breakable(null), "")
  const name = Model.breakable("immich_machine-learning/x.y")
  for (let p = 0; p < 1; p += 0.1) {
    const s = Model.scramble(name, p, 3)
    assert.strictEqual(s.length, name.length)
    for (let i = 0; i < name.length; i++) if (" ·-_/.:@\u200B".includes(name[i])) assert.strictEqual(s[i], name[i], "separators hold while decoding")
  }
}

// A number keeps its word on a status line.
{
  const N = "\u00A0"
  assert.strictEqual(Model.keepUnits("Exited with code 137, 5 minutes ago"), "Exited with code" + N + "137, 5" + N + "minutes ago")
  assert.strictEqual(Model.keepUnits("Up 11 days, healthy"), "Up 11" + N + "days, healthy")
  assert.strictEqual(Model.keepUnits("Restarting (1) 3 seconds ago"), "Restarting (1) 3" + N + "seconds ago")
  assert.strictEqual(Model.keepUnits("Up 2 hours"), "Up 2" + N + "hours")
  assert.strictEqual(Model.keepUnits("Created"), "Created")
}

// The block face, the pixel type and every string the bar writes.
{
  assert.deepStrictEqual(Model.bigDigits("1"), ["\u2580\u2588 ", " \u2588 ", "\u2580\u2580\u2580"])
  assert.deepStrictEqual(Model.bigDigits("5.5").map(r => r.length), [9, 9, 9], "a point is one column")
  assert.strictEqual(Model.bigDigits("5.5")[2].charAt(4), "\u2580", "on the baseline")
  assert.strictEqual(Model.bigDigits("42")[0].length, 7)
  const snaps = [
    Model.withRates(Model.parseProbe(sample(105, 10050, 2000000)), Model.parseProbe(sample(100, 10000, 1000000)), 1),
    Model.parseProbe(sample(100, 10000, 1000000)),
    Object.assign(Model.parseProbe(sample(100, 10000, 1000000)), { cpuPercent: 100, rxRate: 3.2 * 1024 ** 3, txRate: 512, cpuTemp: 104.6 })
  ]
  for (const snap of snaps) {
    for (const item of Model.barItems(snap, ["cpu", "ram", "disk", "temp", "net"])) assert.ok(Model.drawable(item.text), JSON.stringify(item.text) + " can be drawn")
    for (const row of Model.hoverRows(snap)) assert.ok(Model.drawable(row.text), JSON.stringify(row.text) + " can be drawn")
  }
  assert.ok(Model.drawable("100%") && Model.drawable("--") && Model.drawable("41\u00B0C"))
  for (const unit of ["B", "K", "M", "G", "T"]) assert.ok(Model.drawable("1.5" + unit))
  assert.strictEqual(Model.pixelText("1").width, 4)
  assert.strictEqual(Model.pixelText("").width, 0)
  for (const ch in Model.PIXEL_FONT) {
    const g = Model.PIXEL_FONT[ch]
    assert.strictEqual(g.length, 5, ch + " is five rows")
    assert.ok(g.every(r => r.length === g[0].length), ch + " rows are one width")
  }
}

// The bar: what each stat says, the mark's state.
{
  const c = Model.withRates(Model.parseProbe(sample(105, 10050, 2000000)), Model.parseProbe(sample(100, 10000, 1000000)), 1)
  const items = Model.barItems(c, ["cpu", "ram", "temp", "net"])
  assert.deepStrictEqual(items.map(i => i.key), ["cpu", "ram", "temp", "rx", "tx"])
  assert.strictEqual(items[0].text, "0%")
  assert.strictEqual(items[2].text, "48\u00B0")
  assert.strictEqual(items[3].text, "977K")
  assert.deepStrictEqual(Model.barItems(null, ["cpu"]), [])
  assert.strictEqual(Model.barItems(Model.parseProbe(sample(100, 10000, 1000000)), ["cpu"])[0].text, "--")
  assert.strictEqual(Model.barItems(Object.assign({}, c, { cpuPercent: 95 }), ["cpu"])[0].hot, true)
  const mark = extra => Model.barMark(Object.assign({ configured: true, online: true, status: "online", needsUser: false, alertCount: 0, working: false }, extra))
  assert.deepStrictEqual(mark({}), { icon: "server", tone: "", working: false })
  assert.strictEqual(mark({ alertCount: 2 }).icon, "warning-diamond", "an alert is a mark, not colour alone")
  assert.strictEqual(mark({ online: false, status: "error" }).tone, "low")
  assert.strictEqual(mark({ online: false, status: "error", needsUser: true }).tone, "dim")
  assert.strictEqual(mark({ working: true }).working, true)
  assert.strictEqual(mark({ configured: false }).tone, "dim")
}

// The hover card: a line per reading, the alert tone and a mark when hot.
{
  const c = Model.withRates(Model.parseProbe(sample(105, 10050, 2000000)), Model.parseProbe(sample(100, 10000, 1000000)), 1)
  const rows = Model.hoverRows(c)
  assert.deepStrictEqual(rows.map(r => r.key), ["cpu", "memory", "temp", "disk:/", "disk:/DATA", "containers"])
  assert.strictEqual(rows[3].name, "Root disk")
  assert.strictEqual(rows[5].text, "2")
  const hot = Model.hoverRows(Object.assign({}, c, { cpuPercent: 99 }))[0]
  assert.strictEqual(hot.tone, "low")
  assert.strictEqual(hot.mark, "warning-diamond")
  assert.deepStrictEqual(Model.hoverRows(null), [])
  assert.strictEqual(Model.hoverNote(c), "2 alerts, open the panel to see")
  assert.strictEqual(Model.hoverNote(Object.assign({}, c, { failedUnits: [], rebootRequired: false })), "Up 3 days 4 hours")
  assert.strictEqual(Model.hoverNote(Object.assign({}, c, { failedUnits: [] })), "Reboot required", "one problem is named")
  assert.strictEqual(Model.hoverNote(Object.assign({}, c, { rebootRequired: false })), "smartd.service failed")
}

// The prompt lays out the whole line from the first character.
{
  assert.strictEqual(Model.revealLine("All clear", 9, true), "All clear\u258C")
  assert.ok(Model.revealLine("All clear", 3, true).startsWith("All "))
  assert.ok(Model.revealLine("All clear", 3, true).includes('<font color="#00000000">'))
  assert.ok(Model.revealLine("a<b", 0, true).includes("&lt;"), "markup in a line is escaped")
  assert.strictEqual(Model.scramble("Up 3 days", 1, 0), "Up 3 days")
  assert.strictEqual(Model.scramble("Up 3 days", 0, 0).length, 9)
  assert.strictEqual(Model.scramble("a b", 0, 0).charAt(1), " ", "spaces hold still")
  const cells = Model.meterCells({ segments: 10, level: 45, dent: null, ripples: [] })
  assert.strictEqual(cells.length, 10)
  assert.strictEqual(cells[3].fill, 1)
  assert.strictEqual(cells[4].fill, 0.5)
  assert.strictEqual(cells[5].fill, 0)
}

console.log("model tests passed")
