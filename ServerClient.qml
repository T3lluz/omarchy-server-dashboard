import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "Model.js" as Model

// Owns the connection to one server: polling, history, and the actions the
// panel can run. All SSH work happens in bin/server-dash; this side only
// schedules it and keeps state.
Item {
  id: root
  visible: false

  property string target: ""
  property int port: 22
  property int intervalSec: 5
  // The full rate is only worth it while numbers are on screen.
  property bool barMetrics: true
  property int openPanels: 0
  readonly property bool fastPolling: barMetrics || openPanels > 0

  // "unconfigured" | "connecting" | "online" | "error"
  property string status: target === "" ? "unconfigured" : "connecting"
  property string errorKind: ""
  property string errorText: ""
  property var snapshot: null
  property var previousSnapshot: null
  property real lastPollMs: 0
  property var peers: []

  // Desktop notifications when the server drops, or a new alert
  // (Model.alerts) appears; each follows its alert until it is over.
  property bool notify: true
  property string displayName: ""
  // The alerts last seen, and whether the server was last seen up; null
  // until the first answer, so starting the shell never notifies.
  property var lastAlerts: null
  property bool announcedDown: false
  property int failedPolls: 0
  readonly property int alertCount: Object.keys(snapshot ? Model.alerts(snapshot) : {}).length

  property string busyAction: ""
  property string actionStatus: ""
  property bool actionFailed: false

  // Updates go through bin/plugin-update, as in ROG Deck and Batteries; the
  // settings' About section and the update banner read it.
  property bool autoUpdateCheck: true
  readonly property alias updater: updaterItem

  Updater {
    id: updaterItem
    pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
    autoCheck: root.autoUpdateCheck
  }

  readonly property bool online: status === "online"
  readonly property bool configured: target !== ""
  // These need the user, so retrying would only collect failed logins.
  readonly property bool needsUser: status === "error" && ["auth", "nopassword", "hostkey", "config"].indexOf(errorKind) !== -1
  readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("bin/server-dash").toString().replace(/^file:\/\//, ""))
  readonly property string hostLabel: snapshot && snapshot.hostname ? snapshot.hostname : Model.targetHost(target)

  property bool _holdPolling: false
  property string _pendingTarget: ""

  signal actionFinished(string kind, bool ok)

  function pollNow() {
    if (!configured || _holdPolling) return
    if (probeProc.running) return
    probeProc.command = ["bash", scriptPath, "probe", target, String(port)]
    probeProc.running = true
    probeWatchdog.restart()
  }

  function serverName() {
    return displayName || hostLabel || "Server"
  }

  // Two failed polls in a row before calling the server down, so one dropped
  // packet on the tailnet stays quiet. Ones that need the user (a password,
  // a changed host key) are shown in the panel, not announced.
  function noteFailure() {
    failedPolls += 1
    if (failedPolls < 2 || announcedDown || lastAlerts === null || needsUser) return
    announcedDown = true
    sendAlert(Model.alertNote("server", null, serverName(), errorText), false)
  }

  function noteSnapshot(next) {
    failedPolls = 0
    var current = Model.alerts(next)
    if (announcedDown) {
      announcedDown = false
      var back = Model.calmNote("server", next, serverName())
      // Its own card turns to the good news; after a reboot asked for, or
      // once the card was dismissed, the news comes on a card of its own.
      if (notices["server"]) notices["server"].calm(back)
      else if (notify) sendCalm(back)
    }
    followAlerts(next)
    if (lastAlerts !== null) {
      for (var key in current) if (!lastAlerts.hasOwnProperty(key)) sendAlert(Model.alertNote(key, next, serverName(), ""), false)
    }
    lastAlerts = current
  }

  // ------------------------------------------------------------- alerts

  // An alert is a real notification, so it takes its place in the shell's
  // stack and history and keeps to Do Not Disturb, dressed in the panel's
  // look: its picture is a pixel badge (bin/badge) drawn for the focused
  // screen's scale, and a click opens the panel. The notification follows
  // its alert: once the server answers again, or the disk, container or
  // service is fine, the same card turns to the good news in the room's
  // colour and goes; when the thing it was about is gone, it is withdrawn.

  // The bar widget that knows the room colours (its alertTone).
  property var toneHost: null
  // Alert key -> its notice, while its notification is up.
  property var notices: ({})
  readonly property string badgeScript: decodeURIComponent(Qt.resolvedUrl("bin/badge").toString().replace(/^file:\/\//, ""))
  readonly property string alertDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-server-dashboard/alerts"
  readonly property string openArgv: JSON.stringify(["omarchy-shell", "io.github.t3lluz.server-dashboard", "open"])
  // Draws the badge, then hands the rest of the arguments to notify-send.
  readonly property string sendScript: 'python3 -B "$1" "$2" "$3" "$4" "$5" "$6"; img="$2"; [ -s "$img" ] || img=network-server; '
    + 'shift 6; exec notify-send -a "Server Dashboard" -i "$img" -h "string:omarchy-exec-argv:$OPEN_ARGV" "$@"'

  function sendAlert(note, preview) {
    if ((!notify && !preview) || notices[note.key]) return
    var notice = noticeComponent.createObject(root, { note: note, preview: !!preview })
    var next = Object.assign({}, notices)
    next[note.key] = notice
    notices = next
  }

  // Good news with no card of its own to land on: shown a few seconds.
  function sendCalm(note) {
    Quickshell.execDetached(alertCommand(note, "-calm", false, ["-u", "normal", "-t", "5000", "-h", "boolean:transient:true"]))
  }

  function alertCommand(note, suffix, low, flags) {
    var file = alertDir + "/" + String(note.key).replace(/[^A-Za-z0-9_-]/g, "_") + suffix + ".png"
    return ["env", "OPEN_ARGV=" + openArgv, "sh", "-c", sendScript, "server-dash-alert", badgeScript, file,
            String(badgeSize()), note.icon, toneHex(note.tone, low), note.mark]
      .concat(flags).concat(["--", note.title, note.body])
  }

  function followAlerts(snap) {
    for (var key in notices) {
      var n = notices[key]
      if (!n || n.preview || n.answered || key === "server") continue
      var now = Model.alertState(key, snap)
      if (now === "clear") n.calm(Model.calmNote(key, snap, serverName()))
      else if (now === "gone") n.withdraw()
    }
  }

  function withdrawAll() {
    for (var key in notices) if (notices[key]) notices[key].withdraw()
  }

  function dropNotice(key, notice) {
    if (notices[key] !== notice) return
    var next = Object.assign({}, notices)
    delete next[key]
    notices = next
  }

  // The shell draws a sender's picture in a slot 40 wide; at the focused
  // screen's scale, a whole number of device pixels, so it stays sharp.
  function badgeSize() {
    var m = Hyprland.focusedMonitor
    var scale = m && m.scale > 0 ? m.scale : 1
    return Math.round(Style.space(40) * scale)
  }

  function toneHex(name, low) {
    var c = toneHost && typeof toneHost.alertTone === "function" ? toneHost.alertTone(name, low) : null
    return c ? String(c) : "#ffffff"
  }

  // The server going quiet, as the panel would tell it, on a made-up error:
  // a few seconds later it is back on the same card.
  function previewAlert() {
    var old = notices["preview"]
    if (old) old.withdraw()
    dropNotice("preview", old)
    var note = Model.alertNote("server", null, serverName(), "Timed out reaching " + Model.targetHost(target || "server"))
    note.key = "preview"
    sendAlert(note, true)
  }

  Component {
    id: noticeComponent

    Item {
      id: notice
      visible: false

      property var note: ({})
      property bool preview: false
      // The notification's id, once the shell has it.
      property string nid: ""
      property bool answered: false

      function calm(next) {
        if (answered || !nid) return
        answered = true
        next.key = note.key
        replacer.command = root.alertCommand(next, "-calm", false,
          ["-r", nid, "-u", "normal", "-t", "5000", "-h", "boolean:transient:true"])
        replacer.running = true
      }

      function withdraw() {
        if (answered) return
        answered = true
        if (!nid) return
        closer.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                          "--object-path", "/org/freedesktop/Notifications",
                          "--method", "org.freedesktop.Notifications.CloseNotification", nid]
        closer.running = true
      }

      // --wait keeps this running until the notification closes, which is
      // how the notice knows it is gone.
      Process {
        id: sender
        stdout: SplitParser {
          onRead: function(line) {
            var id = String(line).trim()
            if (!notice.nid && /^[0-9]+$/.test(id)) notice.nid = id
          }
        }
        onExited: {
          root.dropNotice(notice.note.key, notice)
          notice.destroy(1000)
        }
      }

      Process { id: replacer }
      Process { id: closer }

      Timer {
        interval: 6000
        running: notice.preview && notice.nid !== ""
        onTriggered: notice.calm(Model.calmNote("server", root.snapshot, root.serverName()))
      }

      Component.onCompleted: {
        sender.command = root.alertCommand(note, "-alert", true, ["-p", "--wait", "-u", "critical"])
        sender.running = true
      }
    }
  }

  function reset() {
    withdrawAll()
    lastAlerts = null
    announcedDown = false
    failedPolls = 0
    snapshot = null
    previousSnapshot = null
    errorKind = ""
    errorText = ""
    actionStatus = ""
    status = configured ? "connecting" : "unconfigured"
  }

  function retry() {
    if (!configured) return
    if (status === "error") {
      errorKind = ""
      errorText = ""
      status = "connecting"
    }
    pollNow()
  }

  // Saves the password (when given) before the first probe, so that probe
  // already authenticates with it.
  function connectWith(newTarget, newPort, password) {
    _holdPolling = true
    if (probeProc.running) probeProc.running = false
    _pendingTarget = newTarget
    if (password !== "") {
      saveProc.environment = { SERVER_DASH_PASSWORD: password }
      saveProc.command = ["bash", scriptPath, "save", newTarget]
      saveProc.running = true
    } else {
      finishConnect()
    }
  }

  function finishConnect() {
    // The old master may hold a session authenticated with an old password.
    Quickshell.execDetached(["bash", scriptPath, "disconnect", _pendingTarget, String(port)])
    _holdPolling = false
    reset()
    Qt.callLater(pollNow)
  }

  function forget() {
    Quickshell.execDetached(["bash", scriptPath, "forget", target, String(port)])
  }

  function trustNewKey() {
    if (controlProc.running) return
    controlProc.command = ["bash", scriptPath, "trust", target, String(port)]
    controlProc.running = true
  }

  function refreshPeers() {
    if (peersProc.running) return
    peersProc.command = ["bash", scriptPath, "peers"]
    peersProc.running = true
  }

  function runAction(kind, arg, label) {
    if (actionProc.running || !online) return
    busyAction = kind + ":" + (arg || "")
    actionStatus = label + "…"
    actionFailed = false
    actionProc.kind = kind
    actionProc.label = label
    actionProc.command = ["bash", scriptPath, "action", target, String(port), kind, arg || ""]
    actionProc.running = true
  }

  function openTerminal(remoteCommand) {
    var argv = ["omarchy-launch-tui", "--app-id=org.omarchy.server-dashboard", "bash", scriptPath, "shell", target, String(port)]
    if (remoteCommand) argv.push(remoteCommand)
    Quickshell.execDetached(argv)
  }

  function handleProbe(exitCode, out, err) {
    probeWatchdog.stop()
    if (_holdPolling) return

    var failure = Model.parseError(out)
    var parsed = failure ? null : Model.parseProbe(out)
    if (!parsed) {
      if (!failure) failure = { kind: "ssh", message: String(err || "").trim().split("\n")[0] || "No answer from the server" }
      errorKind = failure.kind
      errorText = failure.message
      status = "error"
      noteFailure()
      return
    }

    var now = Date.now()
    var elapsed = previousSnapshot ? (now - lastPollMs) / 1000 : 0
    var next = Model.withRates(parsed, previousSnapshot, elapsed)
    lastPollMs = now
    previousSnapshot = parsed
    snapshot = next
    errorKind = ""
    errorText = ""
    status = "online"
    noteSnapshot(next)
  }

  onTargetChanged: if (!_holdPolling) { reset(); Qt.callLater(pollNow) }
  onPortChanged: if (!_holdPolling) { reset(); Qt.callLater(pollNow) }
  Component.onCompleted: Qt.callLater(pollNow)

  Timer {
    id: pollTimer
    running: root.configured && !root._holdPolling && !root.needsUser
    repeat: true
    interval: {
      if (root.status === "error") return 30000
      return (root.fastPolling ? Math.max(2, root.intervalSec) : 30) * 1000
    }
    onTriggered: root.pollNow()
  }

  Timer {
    id: probeWatchdog
    interval: 25000
    onTriggered: if (probeProc.running) probeProc.running = false
  }

  Process {
    id: probeProc
    running: false
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    stderr: StdioCollector { id: probeErr; waitForEnd: true }
    onExited: function(exitCode) { root.handleProbe(exitCode, String(probeOut.text || ""), String(probeErr.text || "")) }
  }

  Process {
    id: saveProc
    running: false
    stdout: StdioCollector { id: saveOut; waitForEnd: true }
    onExited: function(exitCode) {
      saveProc.environment = ({})
      if (exitCode !== 0) {
        var failure = Model.parseError(String(saveOut.text || "")) || { kind: "keyring", message: "Could not save the password" }
        root._holdPolling = false
        root.errorKind = failure.kind
        root.errorText = failure.message
        root.status = "error"
        return
      }
      root.finishConnect()
    }
  }

  Process {
    id: controlProc
    running: false
    onExited: root.retry()
  }

  Process {
    id: peersProc
    running: false
    stdout: StdioCollector { id: peersOut; waitForEnd: true }
    onExited: root.peers = Model.parsePeers(String(peersOut.text || ""))
  }

  Process {
    id: actionProc
    property string kind: ""
    property string label: ""
    running: false
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var ok = exitCode === 0
      var failure = Model.parseError(String(actionOut.text || ""))
      root.busyAction = ""
      root.actionFailed = !ok
      if (ok) {
        root.actionStatus = actionProc.label + " done"
      } else {
        var detail = failure ? failure.message : String(actionErr.text || "").trim().split("\n").pop()
        if (/incorrect password|a password is required|no tty present/i.test(detail)) detail = "sudo refused the saved password"
        root.actionStatus = actionProc.label + " failed" + (detail ? ": " + detail : "")
      }
      statusClear.restart()
      root.actionFinished(actionProc.kind, ok)
      if (actionProc.kind === "reboot" || actionProc.kind === "poweroff") {
        // Asked for, so not worth announcing as an outage.
        root.announcedDown = true
        root.status = "error"
        root.errorKind = "unreachable"
        root.errorText = actionProc.kind === "reboot" ? "Rebooting…" : "Powered off"
        root.snapshot = null
      } else {
        Qt.callLater(root.pollNow)
      }
    }
  }

  Timer {
    id: statusClear
    interval: 6000
    onTriggered: root.actionStatus = ""
  }
}
