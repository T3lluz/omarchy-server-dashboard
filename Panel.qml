import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The server as rooms, in the Rooms look Batteries and Sonus share. A title
// room heads the panel: the server mark, its name and a prompt line that
// types itself out. Under it the server's rooms (Dashboard.qml), each in a
// tone from the theme with its figures in the block face over meters of
// cells, and at the bottom, fixed, four small rooms for the shell, btop,
// reboot and shutdown. A click opens a room to the rest of what it knows.
// The gear swaps the rooms for the settings and the connect form, which keep
// the family's panel kit.
Panel {
  id: root
  moduleName: "io.github.t3lluz.server-dashboard"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var client: null
  // The host widget's WidgetSettings: shell.json as every monitor sees it.
  property var prefs: null
  property bool setupOpen: false
  property string confirmKind: ""

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(fg, 1.5)
  // The theme's alert colour, where it reads; a monochrome theme's is a quiet
  // grey, and a problem must not look calmer than the readings around it, so
  // there it is the text colour. Every alert also carries a mark.
  readonly property color lowTone: Model.contrast(Commons.Color.urgent, Commons.Color.background) >= 3.5 ? Commons.Color.urgent : fg
  readonly property string fontFamily: hostWidget ? hostWidget.textFont : Style.font.family

  readonly property real roomPad: Style.space(10)
  readonly property real roomGap: Style.space(3)
  // Room icons: pixel art at about 20 px (24 device pixels on a 1.25 scale).
  readonly property real iconColumn: Math.round(Style.font.heading * 1.25)
  readonly property real textInset: iconColumn + Style.space(10)

  readonly property var snap: client && client.snapshot ? client.snapshot : null
  readonly property bool configured: !!client && client.configured
  readonly property bool online: !!client && client.online && snap !== null
  readonly property string status: client ? client.status : "unconfigured"
  readonly property string errorKind: client ? client.errorKind : ""
  readonly property string busyAction: client ? client.busyAction : ""
  readonly property string displayName: hostWidget ? hostWidget.displayName : "Server"
  readonly property bool showSetup: !!client && (!client.configured || setupOpen
    || (status === "error" && ["auth", "nopassword", "config", "keyring"].indexOf(errorKind) !== -1))
  readonly property bool showDashboard: !showSetup
  readonly property bool showRooms: online && showDashboard
  readonly property var containers: online && snap.containers ? snap.containers : []
  readonly property var failedUnits: online && snap.failedUnits ? snap.failedUnits : []
  readonly property var processes: online && snap.processes ? snap.processes : []

  // Connecting, rebooting or powering off: the mark's lights take turns.
  readonly property bool serverWorking: configured && ((!online && status !== "error")
    || /^(reboot|poweroff):/.test(busyAction))
  // Offline, or a changed host key: a possible attack is no quiet matter, though
  // like a wrong password it needs the user rather than a retry.
  readonly property bool serverAlarm: status === "error" && !!client && (!client.needsUser || errorKind === "hostkey")

  // ------------------------------------------------------------- tones

  // The theme's terminal colours, read from its colors.toml whenever the
  // panel opens, so a theme switch shows on the next open.
  property var palette: ({})

  FileView {
    id: paletteFile
    path: Commons.Color.currentThemePath + "/colors.toml"
    blockLoading: false
    printErrors: false
    onLoaded: root.palette = Model.parsePalette(text())
  }

  // A room's colour (Model.roomToneHex): the theme's colour of that name, or
  // the tone's own hue where the theme's is a grey, softened toward the text
  // colour. The text colour where it would still read too faint. Only the
  // panel and the hover card take these; the bar keeps the bar's colours.
  function toneOf(name) {
    var c = Qt.color(Model.roomToneHex(name, palette, String(fg)))
    return Model.contrast(c, Commons.Color.background) >= 2.6 ? c : fg
  }

  // The open room, by key: "system", "disks", "network", "containers",
  // "processes".
  // One at a time.
  property string openRoom: ""
  function toggleRoom(key) {
    openRoom = openRoom === key ? "" : key
    if (!cursorActive || cursorKey.indexOf("c:") !== 0) return
    if (openRoom !== "containers") cursorKey = "r:containers"
  }

  // ------------------------------------------------------------- motion

  // Goes up each time the panel opens, or the server answers while it is
  // open: rooms rise in, meters fill, lines decode and icons act themselves
  // out, once.
  property int entry: 0

  // One clock for everything that moves on its own, ticking only while a
  // ripple still runs.
  readonly property real clockBase: Date.now()
  property real clock: 0
  property real awakeUntil: 0

  function wake(ms) {
    clock = Date.now() - clockBase
    awakeUntil = Math.max(awakeUntil, clock + ms)
  }

  Timer {
    interval: 70
    repeat: true
    running: root.opened && !Style.reduceMotion && root.clock < root.awakeUntil
    onTriggered: root.clock = Date.now() - root.clockBase
  }

  // Refreshing by hand turns the refresh icon once, in quarters.
  property real spin: 0
  NumberAnimation { id: spinRun; target: root; property: "spin"; from: 0; to: 360; duration: Style.duration(620); easing.type: Easing.OutCubic }

  function refreshNow() {
    if (client) client.retry()
    if (!Style.reduceMotion) spinRun.restart()
  }

  // Switching between the rooms and the settings slides the new page in from
  // the side it lives on, and the gear turns (or the arrow nudges) as it does.
  property real pageShift: 0
  property real pageFade: 1
  property real gearTurn: 0
  ParallelAnimation {
    id: pageIn
    NumberAnimation { target: root; property: "pageShift"; to: 0; duration: Style.duration(320); easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "pageFade"; to: 1; duration: Style.duration(220); easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "gearTurn"; to: 0; duration: Style.duration(420); easing.type: Easing.OutCubic }
  }

  // --------------------------------------------------------- the prompt

  // The line under the title (Model.heroLines), typed out by the title room.
  // A problem is the only line, so it holds still; otherwise the facts take
  // turns every 2.8 s. While the cursor is on something it says what that
  // does, at once.
  property int lineIndex: 0
  readonly property var heroLines: setupOpen && configured
    ? ["Saved as you change them"]
    : Model.heroLines({
        configured: configured,
        online: online,
        snapshot: snap,
        status: status,
        errorKind: errorKind,
        busyAction: busyAction
      })
  readonly property string heroHint: cursorActive && showDashboard ? hintFor(cursorKey) : ""
  readonly property string heroLine: heroHint !== "" ? heroHint : heroLines[lineIndex % heroLines.length]
  readonly property bool heroUrgent: heroHint === "" && !setupOpen
    && (serverAlarm || (online && Model.needsAttention(snap)))

  Timer {
    interval: 2800
    repeat: true
    running: root.opened && root.heroLines.length > 1 && root.heroHint === ""
    onTriggered: root.lineIndex = (root.lineIndex + 1) % Math.max(1, root.heroLines.length)
  }

  // ------------------------------------------------------------- actions

  readonly property var actions: [
    { key: "ssh", text: "SSH", hint: "Open a shell (t)" },
    { key: "btop", text: "Monitor", hint: "Open btop on the server (b)" },
    { key: "reboot", text: "Reboot", hint: "Reboot, asks first" },
    { key: "poweroff", text: "Shutdown", hint: "Shut down, asks first" }
  ]

  // What the bar can show beside the mark. `room` is where the same switch
  // sits in the panel.
  readonly property var barOptions: [
    { key: "barCpu", label: "CPU usage", inRoom: "CPU in the bar", icon: Model.GLYPHS.cpu, fallback: true, room: "system" },
    { key: "barRam", label: "Memory usage", inRoom: "Memory in the bar", icon: Model.GLYPHS.memory, fallback: true, room: "system" },
    { key: "barDisk", label: "Root disk", inRoom: "Root disk in the bar", icon: Model.GLYPHS.disk, hint: "How full the root disk is", fallback: false, room: "disks" },
    { key: "barTemp", label: "CPU temp", inRoom: "Temperature in the bar", icon: Model.GLYPHS.temp, fallback: false, room: "system" },
    { key: "barNetwork", label: "Network", inRoom: "Rates in the bar", icon: Model.GLYPHS.network, hint: "Download and upload rates", fallback: false, room: "network" }
  ]
  readonly property int barPickedCount: barOptions.filter(function(o) { return setting(o.key, o.fallback) === true }).length

  readonly property var updater: client ? client.updater : null

  // The banners over the rooms: the server not answering, a changed host
  // key, the action running or just finished, the server's alerts, an update.
  readonly property var notices: {
    var list = []
    if (!client) return list
    if (status === "error" && errorKind === "hostkey" && !showSetup)
      list.push({ key: "hostkey", tone: "urgent", icon: Model.GLYPHS.key, text: client.errorText, action: "trustKey", actionLabel: "Trust it" })
    else if (status === "error" && !showSetup)
      list.push({ key: "offline", tone: "urgent", icon: Model.GLYPHS.alert, text: client.errorText, action: "retry", actionLabel: "Retry" })
    if (client.actionStatus !== "")
      list.push({ key: "action", tone: client.actionFailed ? "urgent" : "accent", busy: busyAction !== "",
                  icon: busyAction !== "" ? Model.GLYPHS.busy : (client.actionFailed ? Model.GLYPHS.alert : Model.GLYPHS.done), text: client.actionStatus })
    var alerts = online && !showSetup ? Model.alertLines(snap) : []
    if (alerts.length > 0) list.push({ key: "alerts", tone: "urgent", icon: Model.GLYPHS.alert, text: alerts.join("\n") })
    if (updater && updater.notice) list.push(updater.notice)
    return list
  }

  function noticeAction(notice) {
    if (notice.action === "trustKey") client.trustNewKey()
    else if (notice.action === "retry") client.retry()
    else if (notice.action === "update" && updater) updater.apply()
  }

  function dismissNotice(notice) {
    if (notice.key === "update" && updater) updater.dismiss()
  }

  // ------------------------------------------------------------- cursor

  // One cursor for keyboard and mouse: "u:<i>" a failed unit, "r:<room>" a
  // room, "c:<i>" a container (while their room is open), "a:<i>" an action.
  property string cursorKey: ""
  property bool cursorActive: false
  // Only keyboard moves scroll; scrolling on hover would slide the next row
  // under a resting pointer and walk the list away on its own.
  property bool keyboardCursor: false

  readonly property var cursorTargets: {
    var keys = []
    if (!showRooms) return keys
    for (var u = 0; u < failedUnits.length; u++) keys.push("u:" + u)
    keys.push("r:system")
    if (snap.disks && snap.disks.length > 0) keys.push("r:disks")
    keys.push("r:network")
    if (containers.length > 0) {
      keys.push("r:containers")
      if (openRoom === "containers") for (var c = 0; c < containers.length; c++) keys.push("c:" + c)
    }
    if (processes.length > 0) keys.push("r:processes")
    for (var a = 0; a < actions.length; a++) keys.push("a:" + a)
    return keys
  }

  // What the thing under the cursor does, for the prompt. Short and without
  // names, so the line stays one line and nothing shifts under the pointer.
  function hintFor(key) {
    if (key === "") return ""
    var kind = key.split(":")[0]
    var rest = key.split(":")[1]
    var i = Number(rest)
    if (kind === "r") return openRoom === rest ? "Close it (enter)" : "Open it (enter)"
    if (kind === "a" && actions[i]) return actions[i].hint
    if (kind === "u") return "Restart the service (enter)"
    if (kind === "c" && containers[i])
      return Model.containerRunning(containers[i]) ? "Restart (enter), stop (s)" : "Start (enter)"
    return ""
  }

  function moveCursor(delta) {
    var keys = cursorTargets
    if (keys.length === 0) return
    var idx = keys.indexOf(cursorKey)
    if (idx === -1) idx = delta > 0 ? -1 : keys.length
    keyboardCursor = true
    cursorKey = keys[Math.max(0, Math.min(keys.length - 1, idx + delta))]
  }

  function hover(key) {
    keyboardCursor = false
    cursorActive = true
    cursorKey = key
  }

  // The pointer left what it lit. The key stays, so j and k pick up from
  // there; a keyboard move since keeps its own highlight.
  function unhover(key) {
    if (!keyboardCursor && cursorKey === key) cursorActive = false
  }

  function activateCursor() {
    var picked = cursorKey.split(":")
    var i = Number(picked[1])
    if (picked[0] === "r") toggleRoom(picked[1])
    else if (picked[0] === "c") restartContainer(containers[i])
    else if (picked[0] === "u") restartUnit(failedUnits[i])
    else if (picked[0] === "a") runAction(actions[i].key)
  }

  function scrollIntoView(item) {
    if (!item || !panelFlick || !keyboardCursor) return
    var p = item.mapToItem(body, 0, 0)
    if (p.y < panelFlick.contentY) panelFlick.contentY = Math.max(0, p.y - Style.space(8))
    else if (p.y + item.height > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height, p.y + item.height - panelFlick.height + Style.space(8))
  }

  // ------------------------------------------------------------- doing

  function toggleContainer(container) {
    if (!container || !client) return
    var running = Model.containerRunning(container)
    client.runAction(running ? "docker-stop" : "docker-start", container.name, (running ? "Stopping " : "Starting ") + container.name)
  }

  function restartContainer(container) {
    if (!container || !client) return
    if (!Model.containerRunning(container)) return toggleContainer(container)
    client.runAction("docker-restart", container.name, "Restarting " + container.name)
  }

  function restartUnit(unit) {
    if (!unit || !client) return
    client.runAction("unit-restart", unit.name, "Restarting " + unit.name)
  }

  function runAction(key) {
    if (!client) return
    if (key === "ssh") client.openTerminal("")
    else if (key === "btop") client.openTerminal("btop 2>/dev/null || htop 2>/dev/null || top")
    else if (key === "reboot" || key === "poweroff") askConfirm(key)
  }

  function askConfirm(kind) {
    confirmKind = kind
    confirm.selectedIndex = 0
    Qt.callLater(function() { confirmKeys.forceActiveFocus() })
  }

  function confirmMessage() {
    if (confirmKind === "reboot") return "Reboot " + displayName + "? Everything on it is down until it comes back."
    if (confirmKind === "poweroff") return "Shut down " + displayName + "? Turning it back on takes physical access."
    return ""
  }

  function resolveConfirm(accepted) {
    var kind = confirmKind
    confirmKind = ""
    keyCatcher.forceActiveFocus()
    if (!accepted || !client) return
    client.runAction(kind, "", kind === "reboot" ? "Rebooting " + displayName : "Shutting down " + displayName)
  }

  function submitSetup() {
    var target = targetField.text.trim()
    var port = Number(portField.text) || 22
    if (!Model.validTarget(target)) {
      formError.text = "Use the form user@host, for example casaos@100.64.0.10"
      return
    }
    if (port < 1 || port > 65535) {
      formError.text = "Port must be between 1 and 65535"
      return
    }
    formError.text = ""
    var password = passwordField.text
    passwordField.text = ""
    setupOpen = false
    if (hostWidget && typeof hostWidget.connectServer === "function") hostWidget.connectServer(target, port, password)
    keyCatcher.forceActiveFocus()
  }

  function fillPeer(peer) {
    var user = Model.targetUser(targetField.text) || Model.targetUser(client ? client.target : "")
    targetField.text = (user ? user + "@" : "") + peer.ip
    if (user) passwordField.forceActiveFocus()
    else {
      targetField.forceActiveFocus()
      targetField.cursorPosition = 0
    }
  }

  function resetForm() {
    targetField.text = client ? client.target : ""
    portField.text = String(client ? client.port : 22)
    passwordField.text = ""
    formError.text = ""
  }

  function setting(name, fallback) { return prefs ? prefs.get(name, fallback) : fallback }

  // Omarchy has no settings screen for plugin widgets, so the panel is it.
  function setOption(key, value) {
    if (hostWidget && typeof hostWidget.persistSettings === "function")
      hostWidget.persistSettings(({ [key]: value }))
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // ------------------------------------------------------------- lifecycle

  onOpenedChanged: {
    if (!opened) {
      confirmKind = ""
      setupOpen = false
      openRoom = ""
      return
    }
    cursorActive = false
    cursorKey = ""
    lineIndex = 0
    openRoom = ""
    pageIn.stop()
    pageShift = 0
    pageFade = 1
    gearTurn = 0
    if (panelFlick) panelFlick.contentY = 0
    paletteFile.reload()
    resetForm()
    if (client) {
      client.retry()
      if (showSetup) client.refreshPeers()
    }
    entry++
    Qt.callLater(function() {
      if (root.showSetup && !root.configured) targetField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  // The rooms come in when the server first answers, too.
  onShowRoomsChanged: if (showRooms && opened) entry++

  onSetupOpenChanged: {
    lineIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    if (!opened || Style.reduceMotion) return
    pageShift = Style.space(setupOpen ? 18 : -18)
    pageFade = 0
    gearTurn = setupOpen ? 1 : -1
    pageIn.restart()
  }

  onShowSetupChanged: {
    if (showSetup && client) {
      client.refreshPeers()
      resetForm()
    }
  }

  onCursorTargetsChanged: {
    if (cursorKey !== "" && cursorTargets.indexOf(cursorKey) === -1)
      cursorKey = cursorTargets.length > 0 ? cursorTargets[0] : ""
  }

  // ------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(wanted, Style.space(860))

    readonly property real bodyGap: root.showRooms ? root.roomGap : Style.space(14)
    // What everything needs, before the panel's limit.
    readonly property real wanted: heroRoom.implicitHeight
      + (body.implicitHeight > 0 ? bodyGap + body.implicitHeight : 0)
      + (footer.visible ? footer.implicitHeight : 0)
    // Whether the rooms are taller than the panel may be, decided from that
    // limit rather than from the scroll area's height. While a room opens the
    // window grows a frame behind its content, and the height is rounded, so
    // comparing with the height had the scrollbar flash in and out at every
    // step.
    readonly property bool overflowing: contentHeight < wanted + verticalContentInset - 1

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.confirmKind !== "" || targetField.activeFocus || passwordField.activeFocus || portField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          root.keyboardCursor = true
          if (root.cursorKey === "") root.moveCursor(1)
          return
        }
        root.moveCursor(dy !== 0 ? dy : dx)
      }
      onActivateRequested: if (root.cursorActive && root.cursorKey !== "") root.activateCursor()
      onCloseRequested: {
        if (root.openRoom !== "") root.toggleRoom(root.openRoom)
        else if (root.setupOpen && root.configured) root.setupOpen = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = t.toLowerCase()
        if (key === "r") root.refreshNow()
        else if (key === "t") root.runAction("ssh")
        else if (key === "b") root.runAction("btop")
        else if (key === "c" || key === ",") root.setupOpen = !root.setupOpen
        else if (key === "s" && root.cursorActive && root.cursorKey.indexOf("c:") === 0) root.toggleContainer(root.containers[Number(root.cursorKey.split(":")[1])])
      }

      // =========================================================== title
      Room {
        id: heroRoom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        host: root
        tone: root.toneOf("")
        clickable: false

        HeroBlock {
          id: hero
          width: parent.width
          host: root
          markSize: Math.round(Style.font.display * 1.5)
          title: root.setupOpen && root.configured ? "Settings" : root.displayName
          line: root.heroLine
          instant: root.heroHint !== ""
          working: root.serverWorking
          lightColor: root.heroUrgent ? root.lowTone : root.fg
          lineColor: root.heroUrgent ? root.lowTone : Qt.darker(root.fg, 1.3)

          PixelButton {
            visible: root.configured && !root.setupOpen
            icon: "reload"
            angle: Math.round(root.spin / 90) * 90
            acts: false
            tooltipText: "Refresh (r)"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.refreshNow()
          }

          PixelButton {
            visible: root.configured
            icon: root.setupOpen ? "arrow-left" : "settings-cog"
            // The gear turns in eighths, the arrow nudges in, in whole steps.
            angle: root.setupOpen ? 0 : Math.round(root.gearTurn * -2) * 45
            nudge: root.setupOpen ? Math.round(root.gearTurn * 2) : 0
            tooltipText: root.setupOpen ? "Back (c)" : "Bar, alerts and connection (c)"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.setupOpen = !root.setupOpen
          }
        }
      }

      // ========================================================= scrolls
      Flickable {
        id: panelFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heroRoom.bottom
        anchors.topMargin: panel.bodyGap
        anchors.bottom: footer.visible ? footer.top : parent.bottom
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: panel.overflowing
        // A room closing can leave the view past the end; bring it back.
        onContentHeightChanged: {
          var end = Math.max(0, contentHeight - height)
          if (contentY > end) contentY = end
        }
        // Always showing when there is more, since the clip can land between
        // two rooms and make the panel look finished. A thin bar laid over the
        // rooms' right padding, so it never narrows them: making room for it
        // reflowed every room each time it came and went.
        ScrollBar.vertical: ScrollBar {
          id: panelScroll
          policy: panel.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          padding: 0
          rightPadding: Style.space(2)
          topPadding: Style.space(2)
          bottomPadding: Style.space(2)
          background: Item {}
          contentItem: Rectangle {
            implicitWidth: Math.max(2, Style.space(3))
            radius: Style.cornerRadius > 0 ? width / 2 : 0
            color: root.fg
            opacity: panelScroll.pressed ? 0.6 : panelScroll.hovered ? 0.45 : 0.3
          }
        }

        Column {
          id: body
          width: panelFlick.width
          spacing: root.roomGap

          // ===================================================== dashboard
          Column {
            visible: root.showDashboard && root.notices.length > 0
            width: parent.width
            spacing: Style.space(6)
            bottomPadding: root.showRooms ? Style.space(6) : 0
            opacity: root.pageFade
            transform: Translate { x: root.setupOpen ? 0 : root.pageShift }

            // Over the count, so a banner that stays (a pending reboot) is not
            // built again on every poll.
            Repeater {
              model: root.showDashboard ? root.notices.length : 0

              Notice {
                required property int index
                readonly property var modelData: root.notices[index] || ({})
                width: parent ? parent.width : 0
                icon: modelData.icon
                text: modelData.text
                tone: modelData.tone
                actionLabel: modelData.actionLabel || ""
                busy: !!modelData.busy
                dismissable: !!modelData.dismissable
                foreground: root.fg
                accent: root.accent
                urgent: root.lowTone
                fontFamily: root.fontFamily
                onActioned: root.noticeAction(modelData)
                onDismissed: root.dismissNotice(modelData)
              }
            }
          }

          Dashboard {
            visible: root.showRooms
            host: root
            opacity: root.pageFade
            transform: Translate { x: root.setupOpen ? 0 : root.pageShift }
          }

          // ====================================================== settings
          Column {
            visible: root.showSetup
            width: parent.width
            spacing: Style.space(12)
            opacity: root.pageFade
            transform: Translate { x: root.setupOpen ? root.pageShift : 0 }

            SectionHeader {
              visible: root.configured
              icon: Model.GLYPHS.bar
              title: "SHOW IN THE BAR"
              detail: root.barPickedCount > 0 ? root.barPickedCount + " SHOWN" : "MARK ONLY"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Grid {
              id: barGrid
              visible: root.configured
              width: parent.width
              columns: 2
              columnSpacing: Style.space(6)
              rowSpacing: Style.space(6)

              readonly property real tileWidth: (width - columnSpacing) / 2

              Repeater {
                model: root.barOptions

                ToggleTile {
                  required property var modelData
                  readonly property bool on: root.setting(modelData.key, modelData.fallback) === true
                  width: barGrid.tileWidth
                  icon: modelData.icon
                  label: modelData.label
                  hint: modelData.hint || ""
                  checked: on
                  foreground: root.fg
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onToggled: root.setOption(modelData.key, !on)
                }
              }
            }

            PanelSeparator { visible: root.configured; foreground: root.fg }

            SectionHeader {
              visible: root.configured
              icon: Model.GLYPHS.bell
              title: "ALERTS"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            SwitchRow {
              visible: root.configured
              icon: Model.GLYPHS.bell
              label: "Notify me"
              hint: "Outages, unhealthy containers, full disks, failed services"
              checked: root.setting("notify", true) === true
              foreground: root.fg
              accent: root.accent
              fontFamily: root.fontFamily
              onToggled: root.setOption("notify", !checked)
            }

            PanelSeparator { visible: root.configured; foreground: root.fg }

            // ------------------------------------------------- connect form
            Column {
              id: setupForm
              width: parent.width
              spacing: Style.space(8)

              SectionHeader {
                icon: Model.GLYPHS.link
                title: root.configured ? "CONNECTION" : "CONNECT A SERVER"
                detail: root.configured ? Model.targetHost(root.client.target).toUpperCase() : ""
                foreground: root.fg
                fontFamily: root.fontFamily
              }

              Notice {
                visible: root.status === "error" && ["auth", "nopassword", "keyring"].indexOf(root.errorKind) !== -1
                tone: root.errorKind === "nopassword" ? "accent" : "urgent"
                icon: root.errorKind === "nopassword" ? Model.GLYPHS.key : Model.GLYPHS.alert
                text: root.client ? root.client.errorText : ""
                foreground: root.fg
                accent: root.accent
                urgent: root.lowTone
                fontFamily: root.fontFamily
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: targetField
                  width: parent.width - portField.width - parent.spacing
                  foreground: root.fg
                  font.family: root.fontFamily
                  placeholderText: "user@host"
                  onAccepted: passwordField.forceActiveFocus()
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                }

                TextField {
                  id: portField
                  width: Style.space(70)
                  foreground: root.fg
                  font.family: root.fontFamily
                  placeholderText: "22"
                  inputMethodHints: Qt.ImhDigitsOnly
                  validator: IntValidator { bottom: 1; top: 65535 }
                  onAccepted: root.submitSetup()
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                }
              }

              TextField {
                id: passwordField
                width: parent.width
                password: true
                foreground: root.fg
                font.family: root.fontFamily
                placeholderText: root.configured && root.errorKind !== "nopassword"
                  ? "Password (empty keeps the saved one)"
                  : "Password, stored in your keyring"
                onAccepted: root.submitSetup()
                Keys.onEscapePressed: keyCatcher.forceActiveFocus()
              }

              Notice {
                id: formError
                visible: text !== ""
                tone: "urgent"
                icon: Model.GLYPHS.alert
                foreground: root.fg
                accent: root.accent
                urgent: root.lowTone
                fontFamily: root.fontFamily
              }

              Caption {
                visible: !!root.client && root.client.peers.length > 0
                width: parent.width
                text: "Tailscale machines"
                foreground: root.fg
                fontFamily: root.fontFamily
              }

              Flow {
                visible: !!root.client && root.client.peers.length > 0
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.client ? root.client.peers : []

                  // Names only: the shell's buttons take Nerd Font glyphs,
                  // which would sit beside pixel icons.
                  Button {
                    required property var modelData
                    text: modelData.name
                    tooltipText: modelData.ip + (modelData.online ? "" : ", offline")
                    bordered: true
                    opacity: modelData.online ? 1 : 0.5
                    fontSize: Style.font.bodySmall
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onClicked: root.fillPeer(modelData)
                  }
                }
              }

              Row {
                spacing: Style.space(6)

                Button {
                  text: "Connect"
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.submitSetup()
                }

                Button {
                  visible: root.configured
                  text: "Forget password"
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: {
                    root.client.forget()
                    passwordField.forceActiveFocus()
                  }
                }
              }
            }

            // ------------------------------------------- about and updates
            PanelSeparator { foreground: root.fg }

            UpdateSection {
              icon: Model.GLYPHS.update
              autoCheckIcon: Model.GLYPHS.clock
              name: "Server Dashboard"
              version: root.updater ? root.updater.version : ""
              line: root.updater ? root.updater.line : ""
              available: !!root.updater && root.updater.available
              checking: !!root.updater && root.updater.checking
              busy: !!root.updater && root.updater.busy
              managed: !root.updater || root.updater.managed
              notes: root.updater ? root.updater.notes : []
              showAutoCheck: true
              autoCheck: root.setting("autoUpdateCheck", true) === true
              foreground: root.fg
              accent: root.accent
              fontFamily: root.fontFamily
              onVisibleChanged: if (visible && root.updater && !root.updater.check && !root.updater.checking) root.updater.checkNow()
              onCheckRequested: root.updater.checkNow()
              onApplyRequested: root.updater.apply()
              onAutoCheckToggled: root.setOption("autoUpdateCheck", !autoCheck)
            }
          }
        }
      }

      // ============================================================= footer
      // Fixed, so the actions stay in reach however long the rooms get.
      Row {
        id: footer
        visible: root.showRooms
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        topPadding: root.roomGap
        spacing: root.roomGap

        readonly property real tileWidth: (width - spacing * (root.actions.length - 1)) / root.actions.length
        readonly property real tileHeight: {
          var h = 0
          for (var i = 0; i < tiles.count; i++) if (tiles.itemAt(i)) h = Math.max(h, tiles.itemAt(i).implicitHeight)
          return h
        }

        Repeater {
          id: tiles
          model: root.actions

          ActionTile {
            required property var modelData
            required property int index
            host: root
            width: footer.tileWidth
            height: footer.tileHeight > 0 ? footer.tileHeight : implicitHeight
            action: modelData
            cursor: "a:" + index
            delay: 280 + index * 50
          }
        }
      }

      Item {
        id: confirmKeys
        anchors.fill: parent
        visible: root.confirmKind !== ""
        z: 10
        Keys.onPressed: function(event) {
          if (confirm.handleKey(event)) event.accepted = true
        }

        ConfirmDialog {
          id: confirm
          anchors.fill: parent
          opened: root.confirmKind !== ""
          message: root.confirmMessage()
          confirmText: root.confirmKind === "poweroff" ? "Shut down" : "Reboot"
          foreground: root.fg
          selectedText: root.lowTone
          fontFamily: root.fontFamily
          onCanceled: root.resolveConfirm(false)
          onConfirmed: root.resolveConfirm(true)
        }
      }
    }
  }
}
