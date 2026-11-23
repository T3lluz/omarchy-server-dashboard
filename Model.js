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

// A container's state as its row says it: "Up 7 days,
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

// "23 days 3 hours": the uptime written out, for the panel's prompt line.
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

// The prompt line under the panel's title, one entry per state or fact. The
// panel types them out in turn, the way the other plugins' prompts do; a
// problem is the only line, so it holds still. `state` has configured,
// online, snapshot, status, errorKind and busyAction.
function heroLines(state) {
  if (!state.configured) return ["Connect a server over SSH"]
  if (/^reboot:/.test(state.busyAction)) return ["Rebooting"]
  if (/^poweroff:/.test(state.busyAction)) return ["Shutting down"]
  if (state.online && state.snapshot) {
    var snap = state.snapshot
    var count = problemCount(snap)
    if (count === 1 && snap.rebootRequired) return ["Reboot required"]
    if (count > 0) return [count + (count === 1 ? " alert" : " alerts")]
    if (runningHot(snap)) return ["Running hot"]
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

// The System room's cells: the processor, memory and the processor's
// temperature, each a small figure over a meter over a line of state.
// `value` is the figure, `level` the meter (0..100), `suffix` what follows
// the figure, `hot` turns the cell to the alert tone and gives it a mark.
function systemCells(snap) {
  if (!snap) return []
  var cells = [{
    key: "cpu", label: "CPU", icon: "cpu",
    value: hasLevel(snap.cpuPercent) ? snap.cpuPercent : null,
    level: hasLevel(snap.cpuPercent) ? snap.cpuPercent : null, suffix: "%",
    state: snap.load ? "Load " + snap.load.one.toFixed(2) : "--",
    hot: level(snap.cpuPercent, 70, 90) === 2
  }]
  if (snap.memory) {
    cells.push({ key: "memory", label: "Memory", icon: "memory-stick", value: snap.memory.percent, level: snap.memory.percent,
                 suffix: "%", state: sizeOf(snap.memory.usedBytes, snap.memory.totalBytes), hot: snap.memory.percent >= 92 })
  }
  if (hasLevel(snap.cpuTemp)) {
    var warmth = level(snap.cpuTemp, 70, 85)
    cells.push({ key: "temp", label: "Temp", icon: "thermometer", value: snap.cpuTemp, level: temperatureLevel(snap.cpuTemp),
                 suffix: "°C", state: ["Normal", "Warm", "Hot"][warmth], hot: warmth === 2 })
  }
  return cells
}

// The System room's state line: how long it has been up, how busy.
function systemStatus(snap) {
  if (!snap) return ""
  var bits = []
  if (snap.uptimeSeconds > 0) bits.push("Up " + uptime(snap.uptimeSeconds))
  if (snap.load && snap.load.total) bits.push(snap.load.total + " tasks")
  return bits.join(" · ")
}

// A rate as the Network tile shows it, in the pixel type: a number with one
// decimal under 10 and its unit ("5.5K/s"). `number` and `decimals` stay
// apart so it can count up without changing unit. Null before the second
// poll has a rate.
function rateParts(bytesPerSecond) {
  if (!hasLevel(bytesPerSecond)) return null
  var units = ["B", "K", "M", "G", "T"]
  var v = Math.max(0, bytesPerSecond)
  var i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  var decimals = i > 0 && v < 10 ? 1 : 0
  // 9.96 K would round to "10.0"; show it as "10" in the same unit.
  if (decimals === 1 && Math.round(v * 10) / 10 >= 10) decimals = 0
  return { number: v, decimals: decimals, unit: units[i] + "/s" }
}

function rateText(parts, k) {
  if (!parts) return "--"
  var n = parts.number * (k === undefined ? 1 : Math.max(0, Math.min(1, k)))
  return n.toFixed(parts.decimals)
}

// The Network tile's two rates, download over upload.
function networkRates(snap) {
  if (!snap) return []
  return [
    { key: "rx", label: "Download", icon: "arrow-down", parts: rateParts(snap.rxRate) },
    { key: "tx", label: "Upload", icon: "arrow-up", parts: rateParts(snap.txRate) }
  ]
}

// The interfaces the rates count.
function networkStatus(snap) {
  if (!snap || !snap.net || !snap.net.ifaces) return ""
  return snap.net.ifaces.join(" · ")
}

// The open Network tile: what has gone each way since the server booted,
// and the interfaces it counts.
function networkFacts(snap) {
  if (!snap || !snap.net) return []
  var facts = [{ label: "Received", value: size(snap.net.rx) }, { label: "Sent", value: size(snap.net.tx) }]
  if (snap.net.ifaces && snap.net.ifaces.length) facts.push({ label: "Interfaces", value: networkStatus(snap) })
  return facts
}

// The short readings the open System room adds, two to a line.
function machineFacts(snap) {
  if (!snap) return []
  var facts = []
  if (snap.uptimeSeconds > 0) facts.push({ label: "Uptime", value: uptime(snap.uptimeSeconds) })
  if (snap.load) facts.push({ label: "Load", value: snap.load.one.toFixed(2) + " " + snap.load.five.toFixed(2) + " " + snap.load.fifteen.toFixed(2) })
  if (snap.load && snap.load.total) facts.push({ label: "Tasks", value: String(snap.load.total) })
  if (snap.memory && snap.memory.swapTotalBytes > 0) facts.push({ label: "Swap", value: sizeOf(snap.memory.swapUsedBytes, snap.memory.swapTotalBytes) })
  if (snap.cores > 0) facts.push({ label: "Cores", value: String(snap.cores) })
  if (snap.arch) facts.push({ label: "Arch", value: snap.arch })
  return facts
}

// What the machine is, one to a line, since names run long.
function systemFacts(snap) {
  if (!snap) return []
  var facts = []
  if (snap.cpuModel) facts.push({ label: "Processor", value: snap.cpuModel })
  if (snap.osName) facts.push({ label: "System", value: snap.osName })
  if (snap.kernel) facts.push({ label: "Kernel", value: snap.kernel })
  return facts
}

// Each filesystem as the Disk tile and its drawer show it, the root one first: a name by
// the end of its path, how full it is, and hot at 90%, where the
// notifications start.
var DISK_ALERT = 90

function disks(snap) {
  if (!snap || !snap.disks) return []
  return snap.disks.map(function(disk) {
    var name = disk.mount === "/" ? "Root" : (disk.mount.split("/").filter(function(p) { return p !== "" }).pop() || disk.mount)
    return {
      key: "disk:" + disk.mount, mount: disk.mount, device: disk.device, name: name,
      level: disk.percent, used: size(disk.usedBytes), free: size(disk.availableBytes), total: size(disk.totalBytes),
      detail: sizeOf(disk.usedBytes, disk.totalBytes), hot: disk.percent >= DISK_ALERT
    }
  })
}

// The open Disks room: where each one lives.
function diskFacts(snap) {
  return disks(snap).map(function(d) { return { label: d.mount, value: d.device } })
}

// Unhealthy or restarting over and over: the containers the room keeps in
// view and the alerts name. A stopped one is left alone; stopping one is
// usually on purpose.
function containerTrouble(container) {
  return !!container && (/unhealthy/i.test(container.status + " " + container.state) || container.state === "restarting")
}

function containerCounts(list) {
  var out = { total: 0, running: 0, stopped: 0, trouble: 0, checked: 0, healthy: 0 }
  ;(list || []).forEach(function(c) {
    out.total++
    if (containerRunning(c)) out.running++
    else out.stopped++
    if (containerTrouble(c)) out.trouble++
    if (/\((healthy|unhealthy|health: starting)\)/.test(c.status || "")) {
      out.checked++
      if (/\(healthy\)/.test(c.status)) out.healthy++
    }
  })
  return out
}

// What the Containers tile says beside its count, a line each: they run,
// and then what most needs saying (trouble, stopped ones, health checks).
function containerNote(list) {
  var n = containerCounts(list)
  if (n.total === 0) return []
  var lines = ["running"]
  if (n.trouble > 0) lines.push(n.trouble + " unhealthy")
  else if (n.stopped > 0) lines.push(n.stopped + " stopped")
  else if (n.checked > 0) lines.push(n.healthy + " healthy")
  return lines
}

function containerFacts(list) {
  var n = containerCounts(list)
  if (n.total === 0) return []
  var facts = [{ label: "Running", value: n.running + " of " + n.total }]
  if (n.checked > 0) facts.push({ label: "Healthy", value: n.healthy + " of " + n.checked })
  return facts
}

// A container row's icon: playing, stopped, or the alert.
function containerPixel(container) {
  if (containerTrouble(container)) return "warning-diamond"
  return containerRunning(container) ? "play" : "stop"
}

// The Processes room's state line: the busiest one.
function processesStatus(snap) {
  var list = snap && snap.processes ? snap.processes : []
  if (list.length === 0) return ""
  return list[0].name + " at " + list[0].cpu.toFixed(1) + "%"
}

// A gauge past its limit, for the prompt: the cells, or a full disk.
function runningHot(snap) {
  return systemCells(snap).some(function(c) { return c.hot }) || disks(snap).some(function(d) { return d.hot })
}

// ------------------------------------------------------------------ rooms

// Shared with Batteries and Sonus, the Rooms look: room tones, the block face
// and the pixel type, the cells of a meter, the prompt that types itself, the
// icon stories and the decode. Icons are names in Pixels.js (pixel art); the
// panel kit is handed Nerd Font glyphs, which Glyph.qml swaps for their pixel
// icons through PIXEL_GLYPHS.

function hasLevel(value) {
  return value !== null && value !== undefined && isFinite(value)
}

// Each room's tone, by what it holds, so the plugins agree: the machine is
// blue, storage and connections cyan (side by side, as Sonus's output and
// input share blue), running things green. Processes and the title room
// take none (the text colour); failures take the alert tone in the panel.
var ROOM_TONES = {
  system: "blue",
  disks: "cyan",
  network: "cyan",
  containers: "green",
  processes: "",
  failed: "",
  title: ""
}

function roomTone(key) {
  return ROOM_TONES[key] || ""
}

// Every room's icon. What each acts out is in Motion.js.
var ROOM_PIXELS = {
  system: "speed-fast",
  disks: "database",
  network: "sort-vertical",
  containers: "package",
  processes: "list-box",
  failed: "warning-diamond",
  ssh: "terminal",
  btop: "chart-line",
  reboot: "reload",
  poweroff: "power"
}

function roomPixel(key) {
  return ROOM_PIXELS[key] || "server"
}

// The Nerd Font glyphs the panel kit is handed, as escapes because a Nerd
// Font character is invisible in most editors. Material Design Icons.
var GLYPHS = {
  alert: "\u{F0026}",
  key: "\u{F030B}",
  busy: "\u{F0450}",
  done: "\u{F012C}",
  update: "\u{F06B0}",
  clock: "\u{F051F}",
  bar: "\u{F1513}",
  bell: "\u{F009A}",
  link: "\u{F0318}",
  cpu: "\u{F0EE0}",
  memory: "\u{F061A}",
  disk: "\u{F02CA}",
  temp: "\u{F050F}",
  network: "\u{F01DA}"
}

// Each glyph's pixel icon. Glyph.qml draws the pixel icon for any glyph
// listed here, so the kit's icons match the rooms'.
var PIXEL_GLYPHS = {}
;(function() {
  var byName = {
    alert: "warning-diamond", key: "key", busy: "reload", done: "check", update: "download",
    clock: "hourglass", bar: "layout", bell: "bell", link: "link", cpu: "cpu", memory: "memory-stick",
    disk: "database", temp: "thermometer", network: "arrow-down"
  }
  for (var k in byName) PIXEL_GLYPHS[GLYPHS[k]] = byName[k]
  // The updater's own: updating and done.
  PIXEL_GLYPHS["\u{F06B0}"] = "download"
  PIXEL_GLYPHS["\u{F012C}"] = "check"
})()

function pixelFor(glyph) {
  return PIXEL_GLYPHS[glyph] || ""
}

// Every pixel icon the QML and this file name, for the test that checks they
// all exist in Pixels.js.
var UI_PIXELS = ["chevron-down", "settings-cog", "arrow-left", "reload", "check", "play", "stop",
  "warning-diamond", "cpu", "memory-stick", "thermometer", "database", "arrow-down", "arrow-up",
  "speed-fast", "package", "list-box", "terminal", "chart-line", "power", "sort-vertical"]

// ------------------------------------------------------------ the mark

// The Server Dashboard mark, after its app icon: two server units, each with
// a light and a label line. Drawn on the icons' 12-cell grid in their weight
// (one-cell outlines, corners cut), the 24-unit grid being the same drawing
// doubled. `part` is "frame" (the outlines), "lines" (the labels), "on" (the
// lights that are lit) or "off" (the ones that are not), so each can take
// its own colour. `lights` is [top, bottom], true for lit.
var MARK_UNIT = [
  "..########..",
  ".#........#.",
  ".#.##.###.#.",
  ".#........#.",
  "..########.."
]

function markGrid(part, lights) {
  var g = []
  for (var r = 0; r < 12; r++) { g.push([]); for (var c = 0; c < 12; c++) g[r].push(false) }
  var tops = [0, 6]
  for (var u = 0; u < 2; u++) {
    var lit = !lights || lights[u] !== false
    for (var row = 0; row < MARK_UNIT.length; row++) {
      for (var col = 0; col < 12; col++) {
        if (MARK_UNIT[row].charAt(col) !== "#") continue
        var light = row === 2 && (col === 3 || col === 4)
        var line = row === 2 && col >= 6 && col <= 8
        var want = light ? (lit ? "on" : "off") : line ? "lines" : "frame"
        if (want === part) g[tops[u] + row][col] = true
      }
    }
  }
  return g
}

// Runs along each row, merged down where the next rows repeat them, as
// [x, y, w, h]: the shape Pixels.js keeps its icons in.
function gridRects(grid) {
  var runs = []
  for (var r = 0; r < grid.length; r++) {
    var c = 0
    while (c < grid[r].length) {
      if (!grid[r][c]) { c++; continue }
      var s = c
      while (c < grid[r].length && grid[r][c]) c++
      runs.push([s, r, c - s, 1])
    }
  }
  var merged = []
  runs.forEach(function(run) {
    for (var m = 0; m < merged.length; m++) {
      var x = merged[m]
      if (x[0] === run[0] && x[2] === run[2] && x[1] + x[3] === run[1]) { x[3]++; return }
    }
    merged.push(run.slice())
  })
  return merged
}

// The mark as a pixel icon's art: { g12, g24 }.
function serverMark(part, lights) {
  var g12 = gridRects(markGrid(part, lights))
  return { g12: g12, g24: g12.map(function(q) { return [q[0] * 2, q[1] * 2, q[2] * 2, q[3] * 2] }) }
}

// Which lights are lit `k` of the way (0..1) through the mark's story: dark,
// then the top unit, then the bottom one, as a machine coming up.
function markLights(k) {
  if (!(k < 1)) return [true, true]
  return [k >= 0.3, k >= 0.6]
}

// While the server connects or reboots, the lights take turns, a beat each.
function workingLights(beat) {
  return beat % 2 === 0 ? [true, false] : [false, true]
}

// ------------------------------------------------------------ room tones

// The named colours in a theme's colors.toml: { red: "#565d60", ... }.
function parsePalette(text) {
  var out = {}
  String(text || "").split("\n").forEach(function(line) {
    var m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) out[m[1]] = m[2]
  })
  return out
}

// Contrast between two colours ({r, g, b}, 0 to 1), by the WCAG formula.
function contrast(a, b) {
  function lum(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  var la = lum(a), lb = lum(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// Each tone's own hue, DailyDash's, for themes whose palette is all greys.
var TONE_HUES = {
  blue: "#5ab4f5",
  magenta: "#c38af0",
  cyan: "#4fc9d9",
  green: "#5cc98a",
  yellow: "#f1b467"
}

function hexRgb(hex) {
  var m = String(hex || "").match(/^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i)
  return m ? { r: parseInt(m[1], 16) / 255, g: parseInt(m[2], 16) / 255, b: parseInt(m[3], 16) / 255 } : null
}

function rgbHex(c) {
  function h(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
  return "#" + h(c.r) + h(c.g) + h(c.b)
}

// HSL saturation, 0 to 1.
function saturation(c) {
  var max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b)
  var l = (max + min) / 2
  if (max === min) return 0
  return (max - min) / (1 - Math.abs(2 * l - 1))
}

// A room's tone: the theme's colour of that name when it is a colour, else
// the tone's own hue, either way softened toward the theme's text colour so
// it sits quietly in the theme. No name is the text colour itself.
function roomToneHex(name, palette, foreground) {
  var fg = hexRgb(foreground) || { r: 0.8, g: 0.8, b: 0.8 }
  if (!name) return rgbHex(fg)
  var own = hexRgb(palette ? palette[name] : null)
  var base = own && saturation(own) >= 0.3 ? own : hexRgb(TONE_HUES[name] || TONE_HUES.green)
  var k = 0.3
  return rgbHex({ r: base.r + (fg.r - base.r) * k, g: base.g + (fg.g - base.g) * k, b: base.b + (fg.b - base.b) * k })
}

// ------------------------------------------------------------ block face

// Figures in a three-row block face, as seven segments: the top and the
// middle bar ride the upper half of their row, so the digit sits two and a
// half rows tall. Returns the three rows; anything unknown is a dash.
var SEGMENTS = {
  "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fbgc",
  "5": "afgcd", "6": "afgecd", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g"
}

// A one on the right-hand segments alone reads as a stray bar beside its
// neighbour, so it stands in the middle on a foot. A decimal point is one
// column, a half block on the baseline.
var BIG_ONE = ["▀█ ", " █ ", "▀▀▀"]
var BIG_POINT = [" ", " ", "▀"]

function bigDigits(text) {
  var rows = ["", "", ""]
  String(text).split("").forEach(function(ch, i) {
    var gap = i > 0 ? " " : ""
    if (ch === "1" || ch === ".") {
      var glyph = ch === "1" ? BIG_ONE : BIG_POINT
      for (var r = 0; r < 3; r++) rows[r] += gap + glyph[r]
      return
    }
    var s = SEGMENTS[ch] === undefined ? SEGMENTS["-"] : SEGMENTS[ch]
    function on(seg) { return s.indexOf(seg) !== -1 }
    rows[0] += gap + (on("f") ? "█" : on("a") ? "▀" : " ") + (on("a") ? "▀" : " ") + (on("b") ? "█" : on("a") ? "▀" : " ")
    rows[1] += gap + (on("e") ? "█" : on("g") ? "▀" : " ") + (on("g") ? "▀" : " ") + (on("c") ? "█" : on("g") ? "▀" : " ")
    // Without a bottom bar (4, 7) the sides still reach the baseline.
    rows[2] += gap + (on("d") ? "▀▀▀" : (on("e") ? "▀" : " ") + " " + (on("c") ? "▀" : " "))
  })
  return rows
}

// ------------------------------------------------------------- pixel type

// Small figures in the block face, as pixels: each digit is the face's
// columns by five half rows (bigDigits) with its middle column doubled, four
// wide, so the inside of a 0 or an 8 is two pixels and reads at bar size. The
// one keeps a single stem. The %, the degree, the size letters the bar's
// rates need ("5.4K") and the Network room's "/s" are drawn to match. Rows top to bottom, "#" on.
var PIXEL_FONT = {
  "1": [".##.", "..#.", "..#.", "..#.", ".###"],
  "%": ["##..#", "##.#.", "..#..", ".#.##", "#..##"],
  " ": ["..", "..", "..", "..", ".."],
  ".": [".", ".", ".", ".", "#"],
  "°": ["###", "#.#", "###", "...", "..."],
  "C": ["####", "#...", "#...", "#...", "####"],
  "B": ["###.", "#..#", "####", "#..#", "###."],
  "K": ["#..#", "#.#.", "##..", "#.#.", "#..#"],
  "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
  "G": ["####", "#...", "#.##", "#..#", "####"],
  "T": ["###", ".#.", ".#.", ".#.", ".#."],
  "/": ["..#", "..#", ".#.", "#..", "#.."],
  "s": ["...", ".##", "#..", ".##", "##."]
}
;(function() {
  "023456789-".split("").forEach(function(ch) {
    var rows = bigDigits(ch)
    var half = []
    rows.forEach(function(row) {
      var top = "", bottom = ""
      for (var i = 0; i < row.length; i++) {
        var c = row.charAt(i)
        var t = c === "█" || c === "▀" ? "#" : "."
        var u = c === "█" || c === "▄" ? "#" : "."
        // The middle column twice.
        top += i === 1 ? t + t : t
        bottom += i === 1 ? u + u : u
      }
      half.push(top, bottom)
    })
    PIXEL_FONT[ch] = half.slice(0, 5)
  })
})()

// A line in the pixel type: { width, height, rects }, in cells, rects as
// [x, y, w, h] merged along each row. A cell between letters; anything the
// type lacks is skipped.
function pixelText(text) {
  var rects = [], x = 0
  String(text || "").split("").forEach(function(ch) {
    var glyph = PIXEL_FONT[ch]
    if (!glyph) return
    if (x > 0) x += 1
    for (var r = 0; r < glyph.length; r++) {
      var row = glyph[r], c = 0
      while (c < row.length) {
        if (row.charAt(c) !== "#") { c++; continue }
        var start = c
        while (c < row.length && row.charAt(c) === "#") c++
        rects.push([x + start, r, c - start, 1])
      }
    }
    x += glyph[0].length
  })
  return { width: x, height: 5, rects: rects }
}

// Whether the pixel type can draw all of `text`.
function drawable(text) {
  return String(text).split("").every(function(ch) { return PIXEL_FONT[ch] !== undefined })
}

// --------------------------------------------------------------- meters

// A level drawn as a meter of cells, the way Batteries draws a battery: ten
// cells for a tenth each, so it can be counted at a glance. For each cell,
// how full it is (0..1), how lit (`glow`, 0..1: a ripple passing) and how
// far the pointer presses it (`press`, 0..1).
//
// opts: segments, level (0..100, fractional while it fills in), dent (0..1
// across the body, where the pointer is) and ripples ([{ x, age }], x 0..1
// across, age in ms).
var METER = {
  RIPPLE_MS: 760,      // Weave's ripple
  RIPPLE_CELLS: 14,    // how far it travels, in cells
  DENT_CELLS: 1.6      // how wide the pointer presses, in cells
}

function meterCells(opts) {
  var n = Math.max(1, Math.floor(opts.segments || 10))
  var lvl = hasLevel(opts.level) ? Math.max(0, Math.min(100, opts.level)) : 0
  var full = lvl / 100 * n
  var ripples = opts.ripples || []
  var out = []
  for (var i = 0; i < n; i++) {
    var fill = Math.max(0, Math.min(1, full - i))
    var glow = 0
    for (var j = 0; j < ripples.length; j++) {
      var k = ripples[j].age / METER.RIPPLE_MS
      if (k < 0 || k >= 1) continue
      var d = Math.abs(i + 0.5 - ripples[j].x * n)
      var ring = 1 - Math.abs(d - k * METER.RIPPLE_CELLS) / 1.1
      if (ring > 0) glow = Math.max(glow, ring * (1 - k))
    }
    var press = 0
    if (opts.dent !== null && opts.dent !== undefined)
      press = Math.max(0, 1 - Math.abs(i + 0.5 - opts.dent * n) / METER.DENT_CELLS)
    out.push({ fill: fill, glow: glow, press: press })
  }
  return out
}

// ---------------------------------------------------------------- prompt

function escapeHtml(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// The prompt line `typed` characters in, as styled text that always lays out
// the whole line plus a cursor cell, the part not typed yet drawn clear, so a
// word never wraps differently while it types. The cursor stands in for the
// next character, except a space, which it would glue to the next word; once
// typed, it blinks in the cell kept for it at the end.
var CURSOR = "▌"
var CLEAR = "<font color=\"#00000000\">"

function revealLine(line, typed, cursorOn) {
  line = String(line || "")
  var n = Math.max(0, Math.min(line.length, Math.floor(typed) || 0))
  var shown = escapeHtml(line.substring(0, n))
  var rest
  if (n < line.length) {
    var next = line.charAt(n)
    shown += next === " " ? " " : CURSOR
    rest = line.substring(n + 1) + CURSOR
  } else if (cursorOn) {
    shown += CURSOR
    rest = ""
  } else {
    rest = CURSOR
  }
  return rest === "" ? shown : shown + CLEAR + escapeHtml(rest) + "</font>"
}

// ---------------------------------------------------------------- motion

// Text arriving the way a terminal decodes it: the first `progress` of it
// is real, the rest cycles through glyphs. Spaces and separators stay put so
// the line keeps its shape. `seed` varies the noise between runs.
var GLITCH = "#%&*+=<>/\\|~:;?!$@"

function scramble(text, progress, seed) {
  text = String(text || "")
  var keep = Math.floor(Math.max(0, Math.min(1, progress)) * text.length)
  var tick = Math.floor(progress * 14)
  var out = ""
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i)
    if (i < keep || ch === " " || ch === "·") { out += ch; continue }
    var h = (((i + 1) * 73856093) ^ (((seed || 0) + 1) * 19349663) ^ ((tick + 1) * 83492791)) >>> 0
    out += GLITCH.charAt(h % GLITCH.length)
  }
  return out
}

// ------------------------------------------------------------------- bar

// What the bar shows beside the mark, in the order the settings list them:
// { key, icon, text, hot }, the text in the pixel type. CPU and memory as a
// share, the root disk too, the temperature in degrees, the network as two
// sizes a second ("5.4K"), the arrows saying which way.
function barItems(snap, stats) {
  if (!snap) return []
  var out = []
  ;(stats || []).forEach(function(stat) {
    if (stat === "cpu") out.push({ key: "cpu", icon: "cpu", text: percentText(snap.cpuPercent), hot: level(snap.cpuPercent, 70, 90) === 2 })
    else if (stat === "ram" && snap.memory) out.push({ key: "ram", icon: "memory-stick", text: percentText(snap.memory.percent), hot: snap.memory.percent >= 92 })
    else if (stat === "disk" && snap.disks && snap.disks.length) out.push({ key: "disk", icon: "database", text: percentText(snap.disks[0].percent), hot: snap.disks[0].percent >= DISK_ALERT })
    else if (stat === "temp" && hasLevel(snap.cpuTemp)) out.push({ key: "temp", icon: "thermometer", text: Math.round(snap.cpuTemp) + "°", hot: level(snap.cpuTemp, 70, 85) === 2 })
    else if (stat === "net") {
      out.push({ key: "rx", icon: "arrow-down", text: hasLevel(snap.rxRate) ? bytes(snap.rxRate) : "--", hot: false })
      out.push({ key: "tx", icon: "arrow-up", text: hasLevel(snap.txRate) ? bytes(snap.txRate) : "--", hot: false })
    }
  })
  return out
}

// The mark in the bar: the server, or the alert when something is wrong;
// dim while it waits for the user; its lights taking turns while it works.
// state: { configured, online, status, needsUser, alertCount, working }.
function barMark(state) {
  if (!state.configured) return { icon: "server", tone: "dim", working: false }
  if (state.working) return { icon: "server", tone: "", working: true }
  if (state.status === "error" && state.needsUser) return { icon: "server", tone: "dim", working: false }
  if (state.status === "error") return { icon: "warning-diamond", tone: "low", working: false }
  if (state.online && state.alertCount > 0) return { icon: "warning-diamond", tone: "low", working: false }
  return { icon: "server", tone: state.online ? "" : "dim", working: false }
}

// The card that opens when the pointer rests on the bar item: a line per
// reading, as the rooms have them. { key, name, icon, tone (a room tone
// name, or "low"), level (0..100 or null for no meter), text, mark }.
function hoverRows(snap) {
  if (!snap) return []
  var rows = systemCells(snap).map(function(c) {
    return { key: c.key, name: c.label, icon: c.icon, tone: c.hot ? "low" : roomTone("system"), level: c.level,
             text: c.key === "temp" ? Math.round(c.value) + "°" : percentText(c.value), mark: c.hot ? "warning-diamond" : "" }
  })
  disks(snap).slice(0, 3).forEach(function(d) {
    rows.push({ key: d.key, name: d.mount === "/" ? "Root disk" : d.name, icon: "database", tone: d.hot ? "low" : roomTone("disks"),
                level: d.level, text: percentText(d.level), mark: d.hot ? "warning-diamond" : "" })
  })
  var n = containerCounts(snap.containers)
  if (n.total > 0) {
    rows.push({ key: "containers", name: "Containers", icon: "package", tone: n.trouble > 0 ? "low" : roomTone("containers"),
                level: n.running / n.total * 100, text: String(n.running), mark: n.trouble > 0 ? "warning-diamond" : "" })
  }
  return rows
}

// The line under the card's rows: the problem when there is one, how many
// when there are more, else how long the server has been up.
function hoverNote(snap) {
  if (!snap) return ""
  var lines = alertLines(snap).concat((snap.failedUnits || []).map(function(u) { return u.name + " failed" }))
  if (lines.length === 1) return lines[0]
  if (lines.length > 1) return lines.length + " alerts, open the panel to see"
  return snap.uptimeSeconds > 0 ? "Up " + uptimeLong(snap.uptimeSeconds) : ""
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

// Whether the prompt should stand out: something is listed as wrong, or a
// gauge runs hot.
function needsAttention(snapshot) {
  return problemCount(snapshot) > 0 || runningHot(snapshot)
}

// The alerts in `current` that were not in `previous`, as messages.
function newAlerts(previous, current) {
  var fresh = []
  for (var key in current) if (!previous || !previous.hasOwnProperty(key)) fresh.push(current[key])
  return fresh
}


// ------------------------------------------------------------ notifications

// What a notification says and shows, in the panel's look. `key` is one of
// alerts()' keys, or "server" for the server going quiet. The summary reads
// like a room's name, the body is one plain sentence with the fact, and the
// badge (bin/badge) is the room's icon with a mark: a cross for something
// that stopped, a meter for a disk filling. `tone` names the room's colour;
// while the alert stands the badge takes the panel's low tone instead.
function alertNote(key, snapshot, server, errorText) {
  var kind = String(key).split(":")[0]
  var name = String(key).substring(kind.length + 1)
  var on = " on " + server + "."
  if (kind === "server") {
    var why = String(errorText || "").trim()
    return {
      key: key, icon: "server", tone: roomTone("system"), mark: "cross",
      title: server + " is down",
      body: why ? why.replace(/[.!?…]*$/, ".") : "It stopped answering over SSH."
    }
  }
  if (kind === "disk") {
    var level = diskLevel(snapshot, name)
    return {
      key: key, icon: roomPixel("disks"), tone: roomTone("disks"), mark: "meter:" + Math.round(level || 0),
      title: "Disk almost full",
      body: name + " on " + server + " is " + Math.round(level || 0) + "% full."
    }
  }
  if (kind === "container") {
    var c = findContainer(snapshot, name)
    var restarting = !!c && c.state === "restarting" && !/unhealthy/i.test(c.status + " " + c.state)
    return {
      key: key, icon: roomPixel("containers"), tone: roomTone("containers"), mark: "cross",
      title: restarting ? "Container restarting" : "Container unhealthy",
      body: name + (restarting ? " keeps restarting" : " is unhealthy") + on
    }
  }
  return {
    key: key, icon: roomPixel("failed"), tone: roomTone("failed"), mark: "cross",
    title: "Service failed",
    body: name + " failed" + on
  }
}

// What the same notification turns into once the problem is gone, in the
// room's own tone, before it leaves by itself.
function calmNote(key, snapshot, server) {
  var kind = String(key).split(":")[0]
  var name = String(key).substring(kind.length + 1)
  var note = alertNote(key, snapshot, server, "")
  if (kind === "server") {
    note.title = server + " is back"
    note.body = "It answers over SSH again."
  } else if (kind === "disk") {
    var level = Math.round(diskLevel(snapshot, name) || 0)
    note.title = "Disk has room again"
    note.body = name + " on " + server + " is " + level + "% full."
    note.mark = "meter:" + level
    return note
  } else if (kind === "container") {
    note.title = "Container healthy again"
    note.body = name + " is running again on " + server + "."
  } else {
    note.title = "Service recovered"
    note.body = name + " is no longer failed on " + server + "."
  }
  note.mark = "check"
  return note
}

// What became of an alert in a new snapshot: "on" while it stands, "clear"
// once its disk, container or service is fine again, "gone" when the thing
// it was about went away (a disk unmounted, a container removed), which
// takes the notification down without a word.
function alertState(key, snapshot) {
  if (!snapshot) return "on"
  if (alerts(snapshot).hasOwnProperty(key)) return "on"
  var kind = String(key).split(":")[0]
  var name = String(key).substring(kind.length + 1)
  if (kind === "disk") return diskLevel(snapshot, name) === null ? "gone" : "clear"
  // Stopped since, rather than well again: stopping one is usually on
  // purpose, so its card goes without a word instead of saying it runs.
  if (kind === "container") return containerRunning(findContainer(snapshot, name)) ? "clear" : "gone"
  return "clear"
}

function diskLevel(snapshot, mount) {
  var list = snapshot && snapshot.disks || []
  for (var i = 0; i < list.length; i++) if (list[i].mount === mount) return list[i].percent
  return null
}

function findContainer(snapshot, name) {
  var list = snapshot && snapshot.containers || []
  for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
  return null
}
