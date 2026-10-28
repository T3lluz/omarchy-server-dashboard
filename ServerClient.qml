import QtQuick
import Quickshell
import Quickshell.Io
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
  property int historyLength: 60
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
  property var cpuHistory: []
  property var memHistory: []
  property var rxHistory: []
  property var txHistory: []
  property var peers: []

  // Desktop notifications when the server drops, comes back, or a new alert
  // (Model.alerts) appears.
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

  function notifyUser(urgency, title, body) {
    if (!notify) return
    Quickshell.execDetached(["notify-send", "-u", urgency, "-a", "Server Dashboard", "-i", "network-server", title, body])
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
    notifyUser("critical", serverName() + " is unreachable", errorText || "No answer over SSH")
  }

  function noteSnapshot(next) {
    failedPolls = 0
    var current = Model.alerts(next)
    if (announcedDown) {
      announcedDown = false
      notifyUser("normal", serverName() + " is back", "Answering again over SSH")
    }
    if (lastAlerts !== null) {
      var fresh = Model.newAlerts(lastAlerts, current)
      if (fresh.length > 0) notifyUser("critical", serverName() + ": " + fresh[0], fresh.slice(1).join("\n"))
    }
    lastAlerts = current
  }

  function reset() {
    lastAlerts = null
    announcedDown = false
    failedPolls = 0
    snapshot = null
    previousSnapshot = null
    cpuHistory = []
    memHistory = []
    rxHistory = []
    txHistory = []
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

    if (next.cpuPercent !== null) cpuHistory = Model.pushHistory(cpuHistory, next.cpuPercent, historyLength)
    memHistory = Model.pushHistory(memHistory, next.memory ? next.memory.percent : null, historyLength)
    if (next.rxRate !== null) {
      rxHistory = Model.pushHistory(rxHistory, next.rxRate, historyLength)
      txHistory = Model.pushHistory(txHistory, next.txRate, historyLength)
    }
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
