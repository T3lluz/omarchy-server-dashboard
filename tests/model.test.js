// Run with: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { sections, parseError, parseProbe, withRates, pushHistory, parsePeers, percent, bytes, rate, uptime, temperature, level, targetHost, targetUser, validTarget, shortStatus, parseDf, parseNetDev, parseCpuTemp, alerts, newAlerts }")()

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

assert.deepStrictEqual(Model.pushHistory([1, 2, 3], 4, 3), [2, 3, 4])
assert.deepStrictEqual(Model.pushHistory([], null, 3), [0])

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
assert.strictEqual(Model.shortStatus("Up 3 days (healthy)"), "up 3d · healthy")
assert.strictEqual(Model.shortStatus("Exited (0) 2 hours ago"), "exited 0 · 2h ago")

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
  // Only what is new since the last poll is announced.
  assert.deepStrictEqual(Model.newAlerts(now, now), [])
  assert.deepStrictEqual(Model.newAlerts({ "disk:/": "/ is 93% full" }, { "disk:/": "/ is 94% full", "unit:x": "x failed" }), ["x failed"])
}

console.log("model tests passed")
