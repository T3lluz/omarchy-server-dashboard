.pragma library

// Pure parsing and formatting for the probe output of bin/server-dash.
// Nothing here touches QML, so tests/model.test.js can run it under node.

var IGNORED_IFACES = /^(lo|veth|docker|br-|virbr|tailscale|zt|wg|tun|tap|cni|flannel|cali|kube)/
var IGNORED_FS = /^(tmpfs|devtmpfs|dev|run|none|udev|overlay|shm|efivarfs|squashfs|cgroup|proc|sysfs)$/
var IGNORED_MOUNTS = /^(\/boot|\/snap|\/run\/credentials|\/var\/lib\/docker|\/var\/lib\/containers|\/dev|\/sys|\/proc)/
var CPU_SENSORS = ["k10temp", "coretemp", "zenpower", "cpu_thermal", "soc_thermal", "cpu-thermal", "x86_pkg_temp"]

function sections(raw) {
  var result = {}
  var current = null
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\s+$/, "")
    if (line.indexOf("@@") === 0) {
      current = line.substring(2).trim()
      result[current] = []
    } else if (current !== null) {
      result[current].push(line)
    }
  }
  return result
}

function firstLine(list) {
  if (!list) return ""
  for (var i = 0; i < list.length; i++) {
    var line = String(list[i] || "").trim()
    if (line !== "") return line
  }
  return ""
}

// "@@ERROR" replies carry a kind on the first line and a message on the second.
function parseError(raw) {
  var s = sections(raw)
  if (!s.ERROR) return null
  var lines = s.ERROR.filter(function(l) { return String(l).trim() !== "" })
  return { kind: lines[0] || "ssh", message: lines[1] || "Could not reach the server" }
}

function parseOs(lines) {
  var values = {}
  for (var i = 0; i < (lines || []).length; i++) {
    var idx = lines[i].indexOf("=")
    if (idx <= 0) continue
    values[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).replace(/^["']|["']$/g, "")
  }
  return { name: values.PRETTY_NAME || values.NAME || "", id: values.ID || "" }
}

function parseCpuInfo(lines) {
  var model = ""
  var cores = 0
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i]
    if (line.indexOf(":") !== -1 && model === "") model = line.substring(line.indexOf(":") + 1).trim()
    else if (/^\d+$/.test(line.trim())) cores = parseInt(line.trim(), 10)
  }
  model = model.replace(/\(R\)|\(TM\)|\(tm\)/g, "").replace(/\s+with Radeon.*$/i, "").replace(/\s+CPU\s+@.*$/i, "").replace(/\s+/g, " ").trim()
  return { model: model, cores: cores }
}

function parseCpuJiffies(lines) {
  var line = firstLine(lines)
  if (line.indexOf("cpu") !== 0) return null
  var parts = line.split(/\s+/).slice(1).map(function(v) { return Number(v) || 0 })
  if (parts.length < 4) return null
  var total = 0
  for (var i = 0; i < Math.min(parts.length, 8); i++) total += parts[i]
  return { total: total, idle: parts[3] + (parts[4] || 0) }
}

function parseMeminfo(lines) {
  var kb = {}
  for (var i = 0; i < (lines || []).length; i++) {
    var m = lines[i].match(/^(\w+):\s+(\d+)/)
    if (m) kb[m[1]] = Number(m[2])
  }
  if (!kb.MemTotal) return null
  var available = kb.MemAvailable !== undefined ? kb.MemAvailable : (kb.MemFree || 0) + (kb.Buffers || 0) + (kb.Cached || 0)
  var used = Math.max(0, kb.MemTotal - available)
  var swapTotal = kb.SwapTotal || 0
  var swapUsed = Math.max(0, swapTotal - (kb.SwapFree || 0))
  return {
    totalBytes: kb.MemTotal * 1024,
    usedBytes: used * 1024,
    percent: used / kb.MemTotal * 100,
    swapTotalBytes: swapTotal * 1024,
    swapUsedBytes: swapUsed * 1024,
    swapPercent: swapTotal > 0 ? swapUsed / swapTotal * 100 : 0
  }
}

function parseLoad(lines) {
  var parts = firstLine(lines).split(/\s+/)
  if (parts.length < 3) return null
  var procs = parts[3] ? parts[3].split("/") : []
  return {
    one: Number(parts[0]) || 0,
    five: Number(parts[1]) || 0,
    fifteen: Number(parts[2]) || 0,
    running: Number(procs[0]) || 0,
    total: Number(procs[1]) || 0
  }
}

function parseUptime(lines) {
  var value = Number(firstLine(lines).split(/\s+/)[0])
  return isFinite(value) && value > 0 ? Math.floor(value) : 0
}

function parseNetDev(lines) {
  var rx = 0
  var tx = 0
  var ifaces = []
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i]
    var colon = line.indexOf(":")
    if (colon <= 0) continue
    var name = line.substring(0, colon).trim()
    if (name === "" || name.indexOf("|") !== -1 || IGNORED_IFACES.test(name)) continue
    var fields = line.substring(colon + 1).trim().split(/\s+/)
    if (fields.length < 9) continue
    rx += Number(fields[0]) || 0
    tx += Number(fields[8]) || 0
    ifaces.push(name)
  }
  return { rx: rx, tx: tx, ifaces: ifaces }
}

function parseDf(lines) {
  var seen = {}
  var disks = []
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i]
    if (line.indexOf("Filesystem") === 0) continue
    var f = line.trim().split(/\s+/)
    if (f.length < 6) continue
    var fs = f[0]
    var mount = f.slice(5).join(" ")
    if (IGNORED_FS.test(fs) || (mount !== "/" && IGNORED_MOUNTS.test(mount))) continue
    var size = Number(f[1]) * 1024
    if (!(size > 0)) continue
    if (seen[fs]) {
      // Bind mounts and btrfs subvolumes repeat their device; keep the shortest mount.
      if (mount.length < seen[fs].mount.length) seen[fs].mount = mount
      continue
    }
    var disk = {
      device: fs,
      mount: mount,
      totalBytes: size,
      usedBytes: Number(f[2]) * 1024,
      availableBytes: Number(f[3]) * 1024
    }
    disk.percent = disk.totalBytes > 0 ? disk.usedBytes / (disk.usedBytes + disk.availableBytes) * 100 : 0
    seen[fs] = disk
    disks.push(disk)
  }
  disks.sort(function(a, b) {
    if (a.mount === "/") return -1
    if (b.mount === "/") return 1
    return b.totalBytes - a.totalBytes
  })
  return disks
}

// `grep -H .` pairs a sensor's name and reading by their shared directory.
function pairByDir(lines, nameFile, valueFile) {
  var byDir = {}
  for (var i = 0; i < (lines || []).length; i++) {
    var line = lines[i]
    var colon = line.indexOf(":")
    if (colon <= 0) continue
    var path = line.substring(0, colon)
    var value = line.substring(colon + 1).trim()
    var dir = path.substring(0, path.lastIndexOf("/"))
    var file = path.substring(path.lastIndexOf("/") + 1)
    if (!byDir[dir]) byDir[dir] = {}
    if (file === nameFile) byDir[dir].name = value
    else if (file === valueFile) byDir[dir].milli = Number(value)
  }
  var out = []
  for (var d in byDir) {
    if (byDir[d].name !== undefined && isFinite(byDir[d].milli)) out.push({ name: byDir[d].name, celsius: byDir[d].milli / 1000 })
  }
  return out
}

function parseCpuTemp(hwmonLines, thermalLines) {
  var sensors = pairByDir(hwmonLines, "name", "temp1_input").concat(pairByDir(thermalLines, "type", "temp"))
  for (var i = 0; i < CPU_SENSORS.length; i++) {
    for (var j = 0; j < sensors.length; j++) {
      if (sensors[j].name === CPU_SENSORS[i] && sensors[j].celsius > 0) return sensors[j].celsius
    }
  }
  var best = null
  for (var k = 0; k < sensors.length; k++) {
    if (/acpitz|thermal|cpu|soc/i.test(sensors[k].name) && sensors[k].celsius > 0 && (best === null || sensors[k].celsius > best))
      best = sensors[k].celsius
  }
  return best
}

function parseProcesses(lines) {
  var out = []
  for (var i = 0; i < (lines || []).length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 5 || f[0] === "PID" || !/^\d+$/.test(f[0])) continue
    // The probe's own ps, alive for an instant and so always near 100%.
    if (f.slice(4).join(" ") === "ps") continue
    out.push({
      pid: Number(f[0]),
      cpu: Number(f[1]) || 0,
      mem: Number(f[2]) || 0,
      rssBytes: (Number(f[3]) || 0) * 1024,
      name: f.slice(4).join(" ")
    })
  }
  return out.slice(0, 6)
}

function parseContainers(lines) {
  var out = []
  for (var i = 0; i < (lines || []).length; i++) {
    var parts = lines[i].split("|")
    if (parts.length < 4 || parts[0] === "") continue
    out.push({ name: parts[0], state: parts[1], status: parts[2], image: parts.slice(3).join("|") })
  }
  out.sort(function(a, b) {
    var ra = a.state === "running" ? 0 : 1
    var rb = b.state === "running" ? 0 : 1
    return ra !== rb ? ra - rb : a.name.localeCompare(b.name)
  })
  return out
}

function parseFailedUnits(lines) {
  var out = []
  for (var i = 0; i < (lines || []).length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 4 || f[0] === "") continue
    out.push({ name: f[0], description: f.slice(4).join(" ") })
  }
  return out
}

function parseProbe(raw) {
  var s = sections(raw)
  if (s.END === undefined) return null
  var os = parseOs(s.OS)
  var cpuInfo = parseCpuInfo(s.CPU)
  var uname = firstLine(s.UNAME).split(/\s+/)
  return {
    timestamp: Number(firstLine(s.TS)) || 0,
    hostname: firstLine(s.HOST),
    user: firstLine(s.USER),
    osName: os.name,
    osId: os.id,
    kernel: uname[1] || "",
    arch: uname[2] || "",
    cpuModel: cpuInfo.model,
    cores: cpuInfo.cores,
    jiffies: parseCpuJiffies(s.STAT),
    memory: parseMeminfo(s.MEM),
    load: parseLoad(s.LOAD),
    uptimeSeconds: parseUptime(s.UP),
    net: parseNetDev(s.NET),
    disks: parseDf(s.DF),
    cpuTemp: parseCpuTemp(s.HWMON, s.THERMAL),
    processes: parseProcesses(s.PROC),
    hasDocker: firstLine(s.HASDOCKER) !== "",
    containers: parseContainers(s.DOCKER),
    failedUnits: parseFailedUnits(s.UNITS),
    rebootRequired: firstLine(s.REBOOT) === "yes"
  }
}

// CPU and network are counters since boot, so a rate needs the previous sample.
// The first poll after connecting reports null rather than inventing a zero.
function withRates(current, previous, elapsedSec) {
  current.cpuPercent = null
  current.rxRate = null
  current.txRate = null
  if (!previous || !(elapsedSec > 0.2)) return current
  if (current.jiffies && previous.jiffies) {
    var dTotal = current.jiffies.total - previous.jiffies.total
    var dIdle = current.jiffies.idle - previous.jiffies.idle
    if (dTotal > 0) current.cpuPercent = clamp((dTotal - dIdle) / dTotal * 100, 0, 100)
  }
  if (current.net && previous.net) {
    current.rxRate = Math.max(0, current.net.rx - previous.net.rx) / elapsedSec
    current.txRate = Math.max(0, current.net.tx - previous.net.tx) / elapsedSec
  }
  return current
}

function parsePeers(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f.length < 4) continue
    out.push({ name: f[0], ip: f[1], os: f[2], online: f[3] === "online" })
  }
  out.sort(function(a, b) {
    if (a.online !== b.online) return a.online ? -1 : 1
    var la = a.os === "linux" ? 0 : 1
    var lb = b.os === "linux" ? 0 : 1
    return la !== lb ? la - lb : a.name.localeCompare(b.name)
  })
  return out
}

// ---------------------------------------------------------------- format

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

function percent(value) {
  if (value === null || value === undefined || !isFinite(value)) return "—"
  return Math.round(value) + "%"
}

function bytes(value) {
  if (value === null || value === undefined || !isFinite(value)) return "—"
  var units = ["B", "K", "M", "G", "T", "P"]
  var v = Math.max(0, value)
  var i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  var digits = v >= 100 || i === 0 ? 0 : (v >= 10 ? 1 : 1)
  return v.toFixed(digits).replace(/\.0$/, "") + units[i]
}

function rate(value) {
  if (value === null || value === undefined || !isFinite(value)) return "—"
  return bytes(value) + "/s"
}

function uptime(seconds) {
  if (!(seconds > 0)) return "—"
  var d = Math.floor(seconds / 86400)
  var h = Math.floor((seconds % 86400) / 3600)
  var m = Math.floor((seconds % 3600) / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  return m + "m"
}

function temperature(celsius) {
  if (celsius === null || celsius === undefined || !isFinite(celsius)) return "—"
  return Math.round(celsius) + "°"
}

// 0 calm, 1 warm, 2 hot: drives accent versus urgent in the gauges.
function level(value, warm, hot) {
  if (value === null || value === undefined || !isFinite(value)) return 0
  if (value >= hot) return 2
  if (value >= warm) return 1
  return 0
}

function targetHost(target) {
  var t = String(target || "")
  return t.indexOf("@") >= 0 ? t.substring(t.indexOf("@") + 1) : t
}

function targetUser(target) {
  var t = String(target || "")
  return t.indexOf("@") >= 0 ? t.substring(0, t.indexOf("@")) : ""
}

function validTarget(target) {
  return /^([A-Za-z0-9._-]+@)?[A-Za-z0-9._:-]+$/.test(String(target || "")) && String(target).charAt(0) !== "-"
}

function containerRunning(container) {
  return !!container && (container.state === "running" || container.state === "restarting")
}

// A container's state as the panel's status line says it: "Up 7 days,
// healthy", "Stopped 2 hours ago", "Exited with code 137, 2 hours ago".
function containerStatus(container) {
  if (!container) return ""
  var status = String(container.status || container.state || "")
  var exited = status.match(/^Exited \((\d+)\) (.*)$/)
  if (exited) return exited[1] === "0" ? "Stopped " + exited[2] : "Exited with code " + exited[1] + ", " + exited[2]
  return status
    .replace(/ \(health: starting\)/, ", starting")
    .replace(/ \((healthy|unhealthy)\)/, ", $1")
    .replace(/^(\w+) (About|Less)/, function(m, verb, word) { return verb + " " + word.toLowerCase() })
}

// ---------------------------------------------------------------- panel

// A number as the panel prints it: one decimal under 100.
function shortNumber(value) {
  return String(value >= 100 ? Math.round(value) : Math.round(value * 10) / 10)
}

// "5.7 of 14.5 GB": both sizes in the larger one's unit.
function sizeOf(used, total) {
  if (!(total > 0)) return "--"
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var i = 0
  var t = total
  while (t >= 1024 && i < units.length - 1) { t /= 1024; i++ }
  var unit = Math.pow(1024, i)
  return shortNumber(Math.max(0, used || 0) / unit) + " of " + shortNumber(total / unit) + " " + units[i]
}

// "455 MB": one size, as the process list prints it.
function size(value) {
  if (value === null || value === undefined || !isFinite(value)) return "--"
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var v = Math.max(0, value)
  var i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  return (i === 0 ? Math.round(v) : shortNumber(v)) + " " + units[i]
}

// "5.4 KB/s", or two dashes before the second poll has a rate.
function speed(value) {
  var amount = size(value)
  return amount === "--" ? amount : amount + "/s"
}

// "23 days 3 hours": the uptime written out, for the panel's status line.
function uptimeLong(seconds) {
  if (!(seconds > 0)) return ""
  var d = Math.floor(seconds / 86400)
  var h = Math.floor((seconds % 86400) / 3600)
  var m = Math.floor((seconds % 3600) / 60)
  function count(v, word) { return v + " " + word + (v === 1 ? "" : "s") }
  if (d > 0) return count(d, "day") + (h > 0 ? " " + count(h, "hour") : "")
  if (h > 0) return count(h, "hour") + (m > 0 ? " " + count(m, "minute") : "")
  if (m > 0) return count(m, "minute")
  return "under a minute"
}

// The status line under the panel's title, one entry per state or fact. The
// panel rotates through them, the way Omarchy's own panels rotate theirs.
// `state` has configured, online, snapshot, status, errorKind and busyAction.
function heroLines(state) {
  if (!state.configured) return ["Connect a server over SSH"]
  if (/^reboot:/.test(state.busyAction)) return ["Rebooting"]
  if (/^poweroff:/.test(state.busyAction)) return ["Shutting down"]
  if (state.online && state.snapshot) {
    var snap = state.snapshot
    var count = problemCount(snap)
    if (count === 1 && snap.rebootRequired) return ["Reboot required"]
    if (count > 0) return [count + (count === 1 ? " alert" : " alerts")]
    if (parts(snap).some(function(part) { return part.hot })) return ["Running hot"]
    var lines = ["All clear"]
    if (snap.uptimeSeconds > 0) lines.push("Up " + uptimeLong(snap.uptimeSeconds))
    if (snap.osName) lines.push(snap.osName)
    return lines
  }
  if (state.status === "error") {
    if (state.errorKind === "hostkey") return ["Host key changed"]
    if (["auth", "nopassword", "keyring", "config"].indexOf(state.errorKind) !== -1) return ["Password needed"]
    return ["Offline", "Retrying every 30 seconds"]
  }
  return ["Connecting over SSH"]
}

function percentText(value) {
  if (value === null || value === undefined || !isFinite(value)) return "--"
  return Math.round(value) + "%"
}

// How far along a temperature's meter sits: the calm range stays in the low
// part of the track, and the warm range climbs to full where it turns hot.
function temperatureLevel(celsius) {
  if (celsius < 70) return clamp(celsius, 0, 70) / 70 * 40
  return 40 + (clamp(celsius, 70, 85) - 70) / 15 * 60
}

// One disk as a gauge, named by the end of its path to fit the half-width
// cell; the tooltip has all of it. Hot at 90%, where the notifications start.
function diskPart(disk) {
  return {
    key: "disk:" + disk.mount, icon: "\u{F02CA}", name: disk.mount === "/" ? "Root disk" : disk.mount.split("/").pop(),
    value: percentText(disk.percent), level: disk.percent, detail: sizeOf(disk.usedBytes, disk.totalBytes),
    tip: "Mounted at " + disk.mount, hot: disk.percent >= 90
  }
}

// The panel's gauges: processor, its temperature, memory and the root disk.
// Each has an icon and name, a value, a level from 0 to 100 for the meter, a
// detail under it, an optional tooltip, and `hot` turning it urgent.
function parts(snap) {
  if (!snap) return []
  var out = [{
    key: "cpu", icon: "\u{F0EE0}", name: "Processor",
    value: percentText(snap.cpuPercent), level: snap.cpuPercent,
    detail: snap.load ? "Load " + snap.load.one.toFixed(2) : "--",
    tip: (snap.cpuModel || "") + (snap.cores > 0 ? (snap.cpuModel ? ", " : "") + snap.cores + " cores" : ""),
    hot: level(snap.cpuPercent, 70, 90) === 2
  }]
  if (snap.cpuTemp !== null && snap.cpuTemp !== undefined) {
    var warmth = level(snap.cpuTemp, 70, 85)
    out.push({ key: "temp", icon: warmth === 0 ? "\u{F050F}" : "\u{F10C2}", name: "Temperature",
               value: Math.round(snap.cpuTemp) + " °C", level: temperatureLevel(snap.cpuTemp),
               detail: ["Normal", "Warm", "Hot"][warmth], tip: "", hot: warmth === 2 })
  }
  if (snap.memory) {
    out.push({ key: "memory", icon: "\u{F061A}", name: "Memory", value: percentText(snap.memory.percent), level: snap.memory.percent,
               detail: sizeOf(snap.memory.usedBytes, snap.memory.totalBytes), tip: "", hot: snap.memory.percent >= 92 })
  }
  if (snap.disks && snap.disks.length > 0) out.push(diskPart(snap.disks[0]))
  return out
}

// The filesystems after the root one, as gauges for the details.
function otherDisks(snap) {
  return snap && snap.disks ? snap.disks.slice(1).map(diskPart) : []
}

// The label and value pairs under the gauges: the network, then what the
// server is running. Two dashes stand in until there is a rate.
function serverFacts(snap) {
  if (!snap) return []
  var facts = [
    { label: "Download", value: speed(snap.rxRate) },
    { label: "Upload", value: speed(snap.txRate) }
  ]
  if (snap.uptimeSeconds > 0) facts.push({ label: "Uptime", value: uptime(snap.uptimeSeconds) })
  var containers = snap.containers || []
  if (containers.length > 0) facts.push({ label: "Containers", value: containers.filter(containerRunning).length + " of " + containers.length })
  if (snap.load && snap.load.total) facts.push({ label: "Tasks", value: String(snap.load.total) })
  if (snap.memory && snap.memory.swapTotalBytes > 0) facts.push({ label: "Swap", value: sizeOf(snap.memory.swapUsedBytes, snap.memory.swapTotalBytes) })
  return facts
}

// What the machine is, for the details.
function systemFacts(snap) {
  if (!snap) return []
  var facts = []
  if (snap.cpuModel) facts.push({ label: "Processor", value: snap.cpuModel })
  if (snap.cores > 0) facts.push({ label: "Cores", value: String(snap.cores) })
  if (snap.osName) facts.push({ label: "System", value: snap.osName })
  if (snap.kernel) facts.push({ label: "Kernel", value: snap.kernel })
  if (snap.arch) facts.push({ label: "Architecture", value: snap.arch })
  return facts
}

// What the details row opens, named in the order they appear under it.
function detailsLabel(snap) {
  if (!snap) return ""
  var names = []
  if (otherDisks(snap).length > 0) names.push("disks")
  if ((snap.processes || []).length > 0) names.push("processes")
  if (systemFacts(snap).length > 0) names.push("system")
  if ((snap.containers || []).length > 0) names.push("containers")
  var label = names.join(", ")
  return label.charAt(0).toUpperCase() + label.slice(1)
}

// ---------------------------------------------------------------- alerts

// What is wrong on the server right now, keyed so the same problem keeps the
// same key from poll to poll: { key: message }. Unhealthy or restart-looping
// containers, filesystems at 90% or more, and failed systemd units. A
// stopped container is left out: stopping one is usually on purpose.
function alerts(snapshot) {
  var out = {}
  if (!snapshot) return out
  var containers = snapshot.containers || []
  for (var i = 0; i < containers.length; i++) {
    var c = containers[i]
    if (/unhealthy/i.test(c.status + " " + c.state)) out["container:" + c.name] = c.name + " is unhealthy"
    else if (c.state === "restarting") out["container:" + c.name] = c.name + " keeps restarting"
  }
  var disks = snapshot.disks || []
  for (var d = 0; d < disks.length; d++)
    if (disks[d].percent >= 90) out["disk:" + disks[d].mount] = disks[d].mount + " is " + Math.round(disks[d].percent) + "% full"
  var units = snapshot.failedUnits || []
  for (var u = 0; u < units.length; u++) out["unit:" + units[u].name] = units[u].name + " failed"
  return out
}

// What the banner at the top of the panel says: every alert except failed
// units, which have their own section, and a pending reboot.
function alertLines(snapshot) {
  if (!snapshot) return []
  var all = alerts(snapshot)
  var lines = []
  for (var key in all) if (key.indexOf("unit:") !== 0) lines.push(all[key])
  if (snapshot.rebootRequired) lines.push("Reboot required")
  return lines
}

// Everything the panel lists as wrong: the banner's lines and failed units.
function problemCount(snapshot) {
  return snapshot ? alertLines(snapshot).length + (snapshot.failedUnits || []).length : 0
}

// Whether the status line should stand out: something is listed as wrong, or
// a gauge runs hot.
function needsAttention(snapshot) {
  return problemCount(snapshot) > 0 || parts(snapshot).some(function(part) { return part.hot })
}

// The alerts in `current` that were not in `previous`, as messages.
function newAlerts(previous, current) {
  var fresh = []
  for (var key in current) if (!previous || !previous.hasOwnProperty(key)) fresh.push(current[key])
  return fresh
}

