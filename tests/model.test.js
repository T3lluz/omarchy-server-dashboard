// Run with: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { sections, parseError, parseProbe, withRates, parsePeers, percent, bytes, rate, uptime, temperature, level, targetHost, targetUser, validTarget, containerStatus, sizeOf, size, speed, uptimeLong, heroLines, problemCount, needsAttention, temperatureLevel, serverFacts, systemFacts, parts, otherDisks, detailsLabel, parseDf, parseNetDev, parseCpuTemp, alerts, alertLines, newAlerts }")()

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

// Under the gauges: nothing until connected, dashes until the first rate.
assert.deepStrictEqual(Model.serverFacts(null), [])
{
  const facts = Model.serverFacts(b)
  assert.deepStrictEqual(facts.map(f => f.label), ["Download", "Upload", "Uptime", "Containers", "Tasks", "Swap"])
  assert.strictEqual(facts[0].value, "977 KB/s")
  assert.strictEqual(facts[3].value, "2 of 3")
  assert.strictEqual(facts[5].value, "0.5 of 1.9 GB")
  assert.strictEqual(Model.serverFacts(a)[0].value, "--")
  assert.deepStrictEqual(Model.systemFacts(b).map(f => f.label), ["Processor", "Cores", "System", "Kernel", "Architecture"])
  assert.deepStrictEqual(Model.systemFacts(null), [])
}

// The gauges: processor and its temperature, memory and the root disk, each
// with a value, a level for its meter and a detail, urgent where it runs hot.
{
  const rows = Model.parts(c)
  assert.deepStrictEqual(rows.map(r => r.key), ["cpu", "temp", "memory", "disk:/"])
  assert.ok(rows.every(r => r.icon.length > 0), "every gauge has an icon")
  assert.strictEqual(rows[0].name, "Processor")
  assert.strictEqual(rows[0].value, "93%")
  assert.strictEqual(rows[0].detail, "Load 0.52")
  assert.ok(rows[0].tip.startsWith("Intel Core i5-8500T"), "the processor's model is its tooltip")
  assert.strictEqual(rows[0].hot, true, "93% CPU is hot")
  assert.strictEqual(rows[1].value, "48 °C")
  assert.strictEqual(rows[1].detail, "Normal")
  assert.strictEqual(rows[2].value, "75%")
  assert.strictEqual(rows[2].detail, "11.4 of 15.3 GB")
  assert.strictEqual(rows[3].name, "Root disk")
  assert.strictEqual(rows[3].value, "42%")
  assert.deepStrictEqual(Model.otherDisks(c).map(r => r.name), ["DATA"])
  assert.deepStrictEqual(Model.otherDisks(null), [])
  assert.strictEqual(Model.parts(Object.assign({}, c, { cpuTemp: 90 }))[1].detail, "Hot")
  assert.strictEqual(Model.parts(Object.assign({}, c, { cpuTemp: 90 }))[1].hot, true)
  assert.strictEqual(Model.parts(Object.assign({}, c, { cpuTemp: null })).length, 3)
  assert.strictEqual(Model.parts(a)[0].value, "--", "no CPU share before the second poll")
  assert.deepStrictEqual(Model.parts(null), [])
  assert.strictEqual(Model.detailsLabel(c), "Disks, processes, system, containers")
  assert.strictEqual(Model.detailsLabel(Object.assign({}, c, { containers: [] })), "Disks, processes, system")
}

// The status line: what is going on, then facts to rotate through.
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

console.log("model tests passed")
