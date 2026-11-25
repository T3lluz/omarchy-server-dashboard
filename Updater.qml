import QtQuick
import Quickshell
import Quickshell.Io
import "Update.js" as Update

// Panel kit: one plugin's updates, behind its About section and its update
// banner. Checks with bin/plugin-update, starts the update detached (it
// rewrites the plugin folder, and the shell's reload ends every process the
// plugin started) and follows what the script leaves in
// ~/.local/state/<plugin>/update.json. What a closed banner was about (its
// `seen`: the remote's commit, or an update's outcome) is kept in
// dismissed.json beside it, so it stays closed after the shell restarts.
// Load it once, in the service or the leader widget, never once per monitor.
Item {
  id: updater

  // The plugin folder: bin/plugin-update and manifest.json live there.
  property string pluginDir: ""
  property bool autoCheck: true
  // The banner's glyphs, for a plugin whose Glyph draws something else.
  property var icons: ({ update: "󰚰", done: "󰄬" })

  property var manifest: ({})
  property var check: null
  // What bin/plugin-update apply last left in update.json.
  property var outcome: null
  property bool checking: false
  // Seconds since the epoch, ticking once a minute for "checked 5 min ago".
  property real now: Math.floor(Date.now() / 1000)
  // What the banner the user closed was about; something new shows again.
  property string dismissedSeen: ""

  readonly property string name: manifest.name || ""
  readonly property string version: manifest.version || ""
  readonly property string script: pluginDir + "/bin/plugin-update"
  readonly property string stateDir: manifest.id
    ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/" + String(manifest.id).split(".").pop()
    : ""
  readonly property string statePath: stateDir !== "" ? stateDir + "/update.json" : ""
  readonly property string dismissedPath: stateDir !== "" ? stateDir + "/dismissed.json" : ""
  readonly property bool available: !!check && check.available === true
  readonly property bool applying: Update.applying(outcome, now)
  readonly property bool busy: checking || applying
  // Installed without git: nothing to check against.
  readonly property bool managed: !check || check.managed !== false
  readonly property string line: checking ? "Checking…" : Update.line(check, outcome, now)
  readonly property var notes: available && check.notes ? check.notes : []
  readonly property var notice: {
    var n = Update.notice(name, check, outcome, version, now, icons)
    return n && (!n.seen || n.seen !== dismissedSeen) ? n : null
  }

  function checkNow() {
    if (checkProc.running || pluginDir === "") return
    checking = true
    checkProc.running = true
  }

  function apply() {
    if (applying || pluginDir === "") return
    outcome = { state: "updating", message: "", version: null, at: Math.floor(Date.now() / 1000) }
    Quickshell.execDetached([script, "apply"])
    stateWatch.start()
  }

  function dismiss() {
    if (!notice || !notice.seen) return
    dismissedSeen = notice.seen
    if (stateDir === "") return
    // Written whole and moved into place, outside the plugin folder.
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s" "$2" > "$1/dismissed.json.tmp" && mv "$1/dismissed.json.tmp" "$1/dismissed.json"',
                             "sh", stateDir, JSON.stringify({ seen: dismissedSeen })])
  }

  FileView {
    path: updater.pluginDir !== "" ? updater.pluginDir + "/manifest.json" : ""
    printErrors: false
    onLoaded: updater.manifest = Update.parse(text()) || ({})
  }

  FileView {
    path: updater.dismissedPath
    printErrors: false
    onLoaded: {
      var data = Update.parse(text())
      // A banner closed since the shell started wins over the file.
      if (data && typeof data.seen === "string" && updater.dismissedSeen === "") updater.dismissedSeen = data.seen
    }
  }

  Process {
    id: checkProc
    command: [updater.script, "check"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = Update.parse(text)
        if (data) updater.check = data
      }
    }
    onExited: updater.checking = false
  }

  FileView {
    id: stateFile
    path: updater.statePath
    printErrors: false
    onLoaded: {
      var data = Update.parse(text())
      if (!data) return
      // A click made since the file was written wins over the file.
      if (updater.outcome && updater.outcome.at > data.at) return
      updater.outcome = data
      if (data.state !== "updating") stateWatch.stop()
    }
  }

  // The file may not exist until the update writes it, and a failed update
  // doesn't reload the plugin, so read it again while one is running.
  Timer {
    id: stateWatch
    interval: 2000
    repeat: true
    onTriggered: {
      stateFile.reload()
      if (!updater.outcome || Date.now() / 1000 - updater.outcome.at > 300) stop()
    }
  }

  // First check a minute after login, then every six hours.
  Timer {
    interval: updater.check ? 6 * 3600 * 1000 : 60 * 1000
    running: updater.autoCheck && updater.pluginDir !== ""
    repeat: true
    onTriggered: updater.checkNow()
  }

  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: updater.now = Math.floor(Date.now() / 1000)
  }
}
