import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The dashboard, built to Omarchy's own panel numbers. A fixed header with the
// status line that changes, a fixed row of actions at the bottom, and between
// them what scrolls: alerts, failed services, gauges, readings, and the
// details row with disks, processes, the system and containers. The gear swaps
// the middle for the settings and the connect form.
Panel {
  id: root
  moduleName: "io.github.t3lluz.server-dashboard"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var client: null

  // Cursor shared by keyboard and mouse: "u:<i>" failed unit, "a:<i>" action
  // button, "m" the details row, "c:<i>" container.
  property string cursorKey: ""
  property bool cursorActive: false
  // Only keyboard moves scroll; scrolling on hover would slide the next row
  // under a resting pointer and walk the list away on its own.
  property bool keyboardCursor: false
  property bool setupOpen: false
  property string confirmKind: ""
  // The host widget's WidgetSettings: shell.json as every monitor sees it.
  property var prefs: null
  readonly property bool expanded: setting("panelExpanded", false) === true

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  // The theme's alert color. A monochrome theme makes it a quiet grey, which
  // would make a problem look calmer than the readings around it, so there it
  // is the bright foreground instead; the alert glyphs carry the rest.
  readonly property color urgent: Commons.Color.urgent.hslSaturation < 0.2 ? foreground : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var snap: client && client.snapshot ? client.snapshot : null
  readonly property bool configured: !!client && client.configured
  readonly property bool online: !!client && client.online && snap !== null
  readonly property string status: client ? client.status : "unconfigured"
  readonly property string errorKind: client ? client.errorKind : ""
  readonly property string displayName: hostWidget ? hostWidget.displayName : "Server"
  readonly property bool showSetup: !!client && (!client.configured || setupOpen
    || (status === "error" && ["auth", "nopassword", "config", "keyring"].indexOf(errorKind) !== -1))
  readonly property bool showDashboard: !showSetup
  readonly property bool showDetails: online && showDashboard && expanded
  readonly property var containers: online && snap.containers ? snap.containers : []
  readonly property var failedUnits: online && snap.failedUnits ? snap.failedUnits : []
  readonly property var processes: online && snap.processes ? snap.processes : []
  readonly property var parts: online ? Model.parts(snap) : []
  readonly property var facts: online ? Model.serverFacts(snap) : []
  readonly property var otherDisks: online ? Model.otherDisks(snap) : []
  readonly property var systemFacts: online ? Model.systemFacts(snap) : []
  readonly property string detailsLabel: online ? Model.detailsLabel(snap) : ""
  readonly property int runningContainers: containers.filter(Model.containerRunning).length

  // Connecting, rebooting or powering off: the icon pulses until it is done.
  readonly property bool serverWorking: configured && ((!online && status !== "error")
    || /^(reboot|poweroff):/.test(client.busyAction))

  // The status line. It says what the panel knows, rotates through the facts
  // the way Omarchy's panels rotate their phrases, and while the cursor is on
  // something it says what that does.
  property int lineIndex: 0
  readonly property var heroLines: setupOpen && configured
    ? ["Saved as you change them"]
    : Model.heroLines({
        configured: configured,
        online: online,
        snapshot: snap,
        status: status,
        errorKind: errorKind,
        busyAction: client ? client.busyAction : ""
      })
  readonly property string heroHint: cursorActive && showDashboard ? hintFor(cursorKey) : ""
  readonly property string heroLine: heroHint !== "" ? heroHint : heroLines[lineIndex % heroLines.length]
  // Offline, or a changed host key: a possible attack is no quiet matter, though
  // like a wrong password it needs the user rather than a retry.
  readonly property bool serverAlarm: status === "error" && !!client && (!client.needsUser || errorKind === "hostkey")
  readonly property bool heroUrgent: heroHint === "" && !setupOpen
    && (serverAlarm || (online && Model.needsAttention(snap)))

  readonly property var actions: [
    { key: "ssh", icon: "󰆍", text: "SSH", hint: "Open a shell (t)" },
    { key: "btop", icon: "󰨇", text: "Monitor", hint: "Open btop on the server (b)" },
    { key: "reboot", icon: "󰜉", text: "Reboot", hint: "Reboot, asks first" },
    { key: "poweroff", icon: "󰐥", text: "Shutdown", hint: "Shut down, asks first" }
  ]

  // What the bar can show beside the server mark, with the bar's own glyphs.
  readonly property var barOptions: [
    { key: "barCpu", label: "CPU usage", icon: "󰓅", fallback: true },
    { key: "barRam", label: "Memory usage", icon: "󰍛", fallback: true },
    { key: "barDisk", label: "Root disk", icon: "󰋊", hint: "How full the root disk is", fallback: false },
    { key: "barTemp", label: "CPU temp", icon: "󰔏", fallback: false },
    { key: "barNetwork", label: "Network", icon: "󰇚", hint: "Download and upload rates", fallback: false }
  ]
  readonly property int barPickedCount: barOptions.filter(function(o) { return setting(o.key, o.fallback) === true }).length

  readonly property var updater: client ? client.updater : null

  // The banners at the top of the dashboard: the server not answering, a
  // changed host key, the action running or just finished, the server's
  // alerts, an update.
  readonly property var notices: {
    var list = []
    if (!client) return list
    if (status === "error" && errorKind === "hostkey" && !showSetup)
      list.push({ key: "hostkey", tone: "urgent", icon: "󰌋", text: client.errorText, action: "trustKey", actionLabel: "Trust it" })
    else if (status === "error" && !showSetup)
      list.push({ key: "offline", tone: "urgent", icon: "󰀦", text: client.errorText, action: "retry", actionLabel: "Retry" })
    if (client.actionStatus !== "")
      list.push({ key: "action", tone: client.actionFailed ? "urgent" : "accent", busy: client.busyAction !== "",
                  icon: client.busyAction !== "" ? "󰑐" : (client.actionFailed ? "󰀦" : "󰄬"), text: client.actionStatus })
    var alerts = online && !showSetup ? Model.alertLines(snap) : []
    if (alerts.length > 0) list.push({ key: "alerts", tone: "urgent", icon: "󰀦", text: alerts.join("\n") })
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

  readonly property var cursorTargets: {
    var keys = []
    if (!online || showSetup) return keys
    for (var u = 0; u < failedUnits.length; u++) keys.push("u:" + u)
    keys.push("m")
    if (expanded) for (var c = 0; c < containers.length; c++) keys.push("c:" + c)
    for (var a = 0; a < actions.length; a++) keys.push("a:" + a)
    return keys
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // What the thing under the cursor does, for the status line. Short and
  // without names, so the line stays one line and nothing shifts under the
  // pointer.
  function hintFor(key) {
    if (key === "") return ""
    if (key === "m") return (expanded ? "Hide" : "Show") + " the details (e)"
    var kind = key.split(":")[0]
    var i = Number(key.split(":")[1])
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

  // The pointer left what it lit, inside the panel or out of it. The key
  // stays, so j and k pick up from there; a keyboard move since keeps its
  // own highlight.
  function unhover(key) {
    if (!keyboardCursor && cursorKey === key) cursorActive = false
  }

  function activateCursor() {
    if (cursorKey === "m") return toggleExpanded()
    var picked = cursorKey.split(":")
    var i = Number(picked[1])
    if (picked[0] === "c") restartContainer(containers[i])
    else if (picked[0] === "u") restartUnit(failedUnits[i])
    else if (picked[0] === "a") runAction(actions[i].key)
  }

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

  // Remembered in shell.json so the panel reopens the way it was left.
  function toggleExpanded() {
    setOption("panelExpanded", !expanded)
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

  function scrollIntoView(item) {
    if (!item || !panelFlick) return
    var p = item.mapToItem(body, 0, 0)
    if (p.y < panelFlick.contentY) panelFlick.contentY = Math.max(0, p.y - Style.space(8))
    else if (p.y + item.height > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height, p.y + item.height - panelFlick.height + Style.space(8))
  }

  onOpenedChanged: {
    if (!opened) {
      confirmKind = ""
      setupOpen = false
      return
    }
    cursorActive = false
    cursorKey = ""
    lineIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    resetForm()
    if (client) {
      client.retry()
      if (showSetup) client.refreshPeers()
    }
    Qt.callLater(function() {
      if (root.showSetup && !root.configured) targetField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  onSetupOpenChanged: if (panelFlick) panelFlick.contentY = 0

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

  // A hint or a single line has nothing to swap to: finish any fade now, so
  // the line never sticks half-faded.
  onHeroHintChanged: if (heroHint !== "") stopLineSwap()
  onHeroLinesChanged: if (heroLines.length < 2) stopLineSwap()

  function stopLineSwap() {
    lineSwap.stop()
    heroCaption.opacity = 1
  }

  // The same pace and fade as the phrases in Omarchy's power and network
  // panels. Only runs while the panel is open.
  Timer {
    interval: 2800
    repeat: true
    running: root.opened && root.heroLines.length > 1 && root.heroHint === ""
    onTriggered: lineSwap.restart()
  }

  SequentialAnimation {
    id: lineSwap
    PropertyAnimation {
      target: heroCaption; property: "opacity"
      to: 0; duration: Style.duration(150); easing.type: Easing.OutCubic
    }
    ScriptAction { script: root.lineIndex = (root.lineIndex + 1) % Math.max(1, root.heroLines.length) }
    PropertyAnimation {
      target: heroCaption; property: "opacity"
      to: 1; duration: Style.duration(200); easing.type: Easing.OutCubic
    }
  }

  // Text in the panel's font, plain so a name from the server can never turn
  // into markup.
  component PanelText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  // A glyph in the row icon slot.
  component RowIcon: PanelText {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(22)
    horizontalAlignment: Text.AlignHCenter
    font.pixelSize: Style.font.icon
  }

  // Gauges side by side, for the main ones and the other disks.
  component GaugeGrid: Grid {
    id: grid
    property var parts: []
    readonly property real cellWidth: (width - columnSpacing) / 2

    width: parent ? parent.width : 0
    columns: 2
    columnSpacing: Style.space(20)
    rowSpacing: Style.space(12)

    Repeater {
      model: grid.parts

      Gauge {
        required property var modelData
        width: grid.cellWidth
        part: modelData
      }
    }
  }

  // One gauge: icon, name and value, a meter, and a quieter detail under it.
  // The tooltip holds what does not fit, as on the meters in Omarchy's Agents.
  component Gauge: Column {
    id: gauge
    property var part: null
    readonly property color tone: part && part.hot ? root.urgent : root.foreground

    spacing: Style.spacing.labelGap

    HoverHandler { id: gaugeHover }

    PanelToolTip {
      visible: gaugeHover.hovered && text !== ""
      text: gauge.part ? gauge.part.tip : ""
      fontFamily: root.fontFamily
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(gaugeName.implicitHeight, gaugeValue.implicitHeight)

      PanelText {
        id: gaugeIcon
        anchors.left: parent.left
        anchors.top: parent.top
        width: Style.space(20)
        // The glyph changes too, so a hot reading stands out in every theme.
        text: gauge.part ? (gauge.part.hot ? "󰀦" : gauge.part.icon) : ""
        color: gauge.tone
        font.pixelSize: Style.font.icon
      }

      PanelText {
        id: gaugeName
        anchors.left: gaugeIcon.right
        anchors.right: gaugeValue.left
        anchors.rightMargin: Style.space(6)
        wrapMode: Text.Wrap
        text: gauge.part ? gauge.part.name : ""
      }

      PanelText {
        id: gaugeValue
        anchors.right: parent.right
        text: gauge.part ? gauge.part.value : ""
        color: gauge.part && gauge.part.value === "--" ? root.dim : gauge.tone
        font.bold: true
      }
    }

    LevelBar {
      width: parent.width
      level: gauge.part ? gauge.part.level : 0
      fill: gauge.tone
    }

    PanelText {
      width: parent.width
      wrapMode: Text.Wrap
      text: gauge.part ? gauge.part.detail : ""
      color: gauge.part && gauge.part.hot ? root.urgent : root.dim
      font.pixelSize: Style.font.bodySmall
    }
  }

  // A label on the left, its value on the right, as Omarchy's network and
  // power panels list their readings. A long value wraps; it is never cut.
  component InfoPair: Item {
    id: pair
    property string label: ""
    property string value: ""

    implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)

    PanelText {
      id: pairLabel
      text: pair.label
      opacity: 0.6
      font.pixelSize: Style.font.bodySmall
    }

    PanelText {
      id: pairValue
      anchors.right: parent.right
      width: Math.min(implicitWidth, parent.width - pairLabel.implicitWidth - Style.space(8))
      horizontalAlignment: Text.AlignRight
      wrapMode: Text.Wrap
      text: pair.value
      color: pair.value === "--" ? root.dim : root.foreground
      font.pixelSize: Style.font.bodySmall
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(header.implicitHeight
      + (body.implicitHeight > 0 ? Style.space(14) + body.implicitHeight : 0)
      + (footer.visible ? footer.implicitHeight : 0), Style.space(860))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.confirmKind !== "" || targetField.activeFocus || passwordField.activeFocus || portField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          if (root.cursorKey === "") root.moveCursor(1)
          return
        }
        root.moveCursor(dy !== 0 ? dy : dx)
      }
      onActivateRequested: if (root.cursorActive && root.cursorKey !== "") root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = t.toLowerCase()
        if (key === "r") { if (root.client) root.client.retry() }
        else if (key === "t") root.runAction("ssh")
        else if (key === "b") root.runAction("btop")
        else if (key === "c" || key === ",") root.setupOpen = !root.setupOpen
        else if (key === "e") root.toggleExpanded()
        else if (key === "s" && root.cursorActive && root.cursorKey.indexOf("c:") === 0) root.toggleContainer(root.containers[Number(root.cursorKey.split(":")[1])])
      }

      // ============================================================= header
      Column {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          id: hero
          width: parent.width
          implicitHeight: Math.max(heroIconMetrics.implicitHeight, heroLabels.implicitHeight, heroButtons.implicitHeight)

          PanelText {
            id: heroIconMetrics
            visible: false
            text: heroIcon.glyphText
            font.pixelSize: Style.font.display
          }

          PulseGlyph {
            id: heroIcon
            readonly property string glyphText: root.setupOpen && root.configured ? "󰒓" : "󰒋"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: heroIconMetrics.implicitWidth
            height: heroIconMetrics.implicitHeight
            active: root.serverWorking
            opacity: root.online || root.serverWorking || !root.configured || root.setupOpen ? 1 : 0.55
            glyph: Component {
              PanelText {
                text: heroIcon.glyphText
                color: root.serverAlarm && !root.setupOpen ? root.urgent : root.foreground
                font.pixelSize: Style.font.display
              }
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroButtons.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelText {
              width: parent.width
              wrapMode: Text.Wrap
              text: root.setupOpen && root.configured ? "Settings" : root.displayName
              font.pixelSize: Style.font.title
              font.bold: true
            }

            PanelText {
              id: heroCaption
              width: parent.width
              wrapMode: Text.Wrap
              text: root.heroLine.toUpperCase()
              color: root.heroUrgent ? root.urgent : root.dim
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }

          Row {
            id: heroButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              visible: root.configured && !root.setupOpen
              iconText: "󰑐"
              tooltipText: "Refresh (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.client.retry()
            }

            PanelActionButton {
              visible: root.configured
              iconText: root.setupOpen ? "󰁍" : "󰒓"
              tooltipText: root.setupOpen ? "Back (c)" : "Settings (c)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.setupOpen = !root.setupOpen
            }
          }
        }

        PanelSeparator {
          visible: body.implicitHeight > 0
          foreground: root.foreground
        }
      }

      // ========================================================= scrolls
      Flickable {
        id: panelFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Style.space(14)
        anchors.bottom: footer.visible ? footer.top : parent.bottom
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        // Always showing when there is more, since the clip can land between
        // two rows and make the panel look finished. The body leaves it room.
        ScrollBar.vertical: ScrollBar { id: panelScroll; policy: panelFlick.interactive ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }

        Column {
          id: body
          width: panelFlick.width - (panelFlick.interactive ? panelScroll.width + Style.space(4) : 0)
          spacing: Style.space(14)

          // ===================================================== dashboard
          Repeater {
            model: root.showDashboard ? root.notices : []

            Notice {
              required property var modelData
              width: parent ? parent.width : 0
              icon: modelData.icon
              text: modelData.text
              tone: modelData.tone
              actionLabel: modelData.actionLabel || ""
              busy: !!modelData.busy
              dismissable: !!modelData.dismissable
              foreground: root.foreground
              accent: root.accent
              urgent: root.urgent
              fontFamily: root.fontFamily
              onActioned: root.noticeAction(modelData)
              onDismissed: root.dismissNotice(modelData)
            }
          }

          // ------------------------------------------------ failed services
          Column {
            visible: root.showDashboard && root.failedUnits.length > 0
            width: parent.width
            spacing: Style.space(6)

            SectionHeader {
              icon: "󰀦"
              title: "FAILED SERVICES"
              detail: root.failedUnits.length + " FAILED"
              detailColor: root.urgent
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.failedUnits

              UnitRow {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                unit: modelData
                rowKey: "u:" + index
              }
            }
          }

          // --------------------------------------------------------- gauges
          GaugeGrid {
            visible: root.showDashboard && root.parts.length > 0
            parts: root.parts
          }

          // ------------------------------------------------------- readings
          Grid {
            id: factGrid
            visible: root.showDashboard && root.facts.length > 0
            width: parent.width
            columns: 2
            columnSpacing: Style.space(20)
            rowSpacing: Style.spacing.labelGap

            readonly property real cellWidth: (width - columnSpacing) / 2

            Repeater {
              model: root.facts

              InfoPair {
                required property var modelData
                width: factGrid.cellWidth
                label: modelData.label
                value: modelData.value
              }
            }
          }

          // ---------------------------------------------------- details row
          CursorSurface {
            id: detailsRow
            visible: root.showDashboard && root.detailsLabel !== ""
            width: parent.width
            hasCursor: root.cursorActive && root.cursorKey === "m"
            foreground: root.foreground
            implicitHeight: detailsText.implicitHeight + Style.spacing.xl
            onHasCursorChanged: if (hasCursor && root.keyboardCursor) root.scrollIntoView(detailsRow)

            HoverHandler {
              onHoveredChanged: if (hovered) root.hover("m"); else root.unhover("m")
            }

            TapHandler {
              onTapped: root.toggleExpanded()
            }

            PanelText {
              id: detailsText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.right: detailsIcon.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              wrapMode: Text.Wrap
              text: root.detailsLabel
            }

            PanelText {
              id: detailsIcon
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: root.expanded ? "󰅃" : "󰅀"
              font.pixelSize: Style.font.icon
            }
          }

          // ---------------------------------------------------------- disks
          Column {
            visible: root.showDetails && root.otherDisks.length > 0
            width: parent.width
            spacing: Style.space(10)

            SectionHeader {
              icon: "󰋊"
              title: "DISKS"
              detail: root.otherDisks.length + " MORE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            GaugeGrid { parts: root.otherDisks }
          }

          // ------------------------------------------------------ processes
          Column {
            visible: root.showDetails && root.processes.length > 0
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: processHeader.implicitHeight

              SectionHeader {
                id: processHeader
                icon: "󰐰"
                title: "PROCESSES"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelText {
                anchors.right: memoryColumn.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(56)
                horizontalAlignment: Text.AlignRight
                text: "CPU"
                color: root.dim
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              PanelText {
                id: memoryColumn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(72)
                horizontalAlignment: Text.AlignRight
                text: "MEMORY"
                color: root.dim
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              Repeater {
                model: root.processes

                Item {
                  required property var modelData
                  width: parent ? parent.width : 0
                  implicitHeight: Math.max(procName.implicitHeight, procCpu.implicitHeight)

                  PanelText {
                    id: procName
                    width: procCpu.x - Style.space(10)
                    wrapMode: Text.Wrap
                    text: modelData.name
                    opacity: 0.6
                    font.pixelSize: Style.font.bodySmall
                  }

                  PanelText {
                    id: procCpu
                    anchors.right: procMem.left
                    width: Style.space(56)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.cpu.toFixed(1) + "%"
                    color: modelData.cpu >= 80 ? root.urgent : root.foreground
                    font.pixelSize: Style.font.bodySmall
                  }

                  PanelText {
                    id: procMem
                    anchors.right: parent.right
                    width: Style.space(72)
                    horizontalAlignment: Text.AlignRight
                    text: Model.size(modelData.rssBytes)
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          // --------------------------------------------------------- system
          Column {
            visible: root.showDetails && root.systemFacts.length > 0
            width: parent.width
            spacing: Style.space(6)

            SectionHeader {
              icon: "󰌽"
              title: "SYSTEM"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              Repeater {
                model: root.systemFacts

                InfoPair {
                  required property var modelData
                  width: parent ? parent.width : 0
                  label: modelData.label
                  value: modelData.value
                }
              }
            }
          }

          // ----------------------------------------------------- containers
          Column {
            visible: root.showDetails && root.containers.length > 0
            width: parent.width
            spacing: Style.space(6)

            SectionHeader {
              icon: "󰡨"
              title: "CONTAINERS"
              detail: root.runningContainers + " OF " + root.containers.length + " RUNNING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width

              Repeater {
                model: root.containers

                ContainerRow {
                  required property var modelData
                  required property int index
                  width: parent ? parent.width : 0
                  container: modelData
                  rowKey: "c:" + index
                }
              }
            }
          }

          // ====================================================== settings
          Column {
            visible: root.showSetup
            width: parent.width
            spacing: Style.space(12)

            SectionHeader {
              visible: root.configured
              icon: "󰍜"
              title: "SHOW IN THE BAR"
              detail: root.barPickedCount > 0 ? root.barPickedCount + " SHOWN" : "ICON ONLY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Grid {
              id: barGrid
              visible: root.configured
              width: parent.width
              columns: 2
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(8)

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
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onToggled: root.setOption(modelData.key, !on)
                }
              }
            }

            PanelSeparator { visible: root.configured; foreground: root.foreground }

            SectionHeader {
              visible: root.configured
              icon: "󰕮"
              title: "ALERTS AND PANEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SwitchRow {
              visible: root.configured
              icon: "󰂚"
              label: "Notify me"
              hint: "Outages, unhealthy containers, full disks, failed services"
              checked: root.setting("notify", true) === true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onToggled: root.setOption("notify", !checked)
            }

            SwitchRow {
              visible: root.configured
              icon: "󰅀"
              label: "Open with details"
              checked: root.expanded
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onToggled: root.setOption("panelExpanded", !root.expanded)
            }

            PanelSeparator { visible: root.configured; foreground: root.foreground }

            // ------------------------------------------------- connect form
            Column {
              id: setupForm
              width: parent.width
              spacing: Style.space(8)

              SectionHeader {
                icon: "󰌘"
                title: root.configured ? "CONNECTION" : "CONNECT A SERVER"
                detail: root.configured ? Model.targetHost(root.client.target).toUpperCase() : ""
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Notice {
                visible: root.status === "error" && ["auth", "nopassword", "keyring"].indexOf(root.errorKind) !== -1
                tone: root.errorKind === "nopassword" ? "accent" : "urgent"
                icon: root.errorKind === "nopassword" ? "󰌋" : "󰀦"
                text: root.client ? root.client.errorText : ""
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                fontFamily: root.fontFamily
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: targetField
                  width: parent.width - portField.width - parent.spacing
                  foreground: root.foreground
                  font.family: root.fontFamily
                  placeholderText: "user@host"
                  onAccepted: passwordField.forceActiveFocus()
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                }

                TextField {
                  id: portField
                  width: Style.space(70)
                  foreground: root.foreground
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
                foreground: root.foreground
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
                icon: "󰀦"
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                fontFamily: root.fontFamily
              }

              Caption {
                visible: !!root.client && root.client.peers.length > 0
                width: parent.width
                text: "Tailscale machines"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Flow {
                visible: !!root.client && root.client.peers.length > 0
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.client ? root.client.peers : []

                  Button {
                    required property var modelData
                    text: modelData.name
                    iconText: modelData.os === "linux" ? "󰌽" : (modelData.os === "windows" ? "󰖳" : "󰄜")
                    tooltipText: modelData.ip + (modelData.online ? "" : ", offline")
                    bordered: true
                    opacity: modelData.online ? 1 : 0.5
                    fontSize: Style.font.bodySmall
                    iconSize: Style.font.bodySmall
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.fillPeer(modelData)
                  }
                }
              }

              Row {
                spacing: Style.space(6)

                Button {
                  text: "Connect"
                  iconText: "󰌘"
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.submitSetup()
                }

                Button {
                  visible: root.configured
                  text: "Forget password"
                  iconText: "󰅖"
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: {
                    root.client.forget()
                    passwordField.forceActiveFocus()
                  }
                }
              }
            }

            // ------------------------------------------- about and updates
            PanelSeparator { foreground: root.foreground }

            UpdateSection {
              icon: "󰚰"
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
              foreground: root.foreground
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
      // Fixed, so the actions stay in reach however long the list above gets.
      Column {
        id: footer
        visible: root.online && root.showDashboard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        topPadding: Style.space(14)
        spacing: Style.space(14)

        PanelSeparator { foreground: root.foreground }

        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.actions

            Button {
              id: actionButton
              required property var modelData
              required property int index
              readonly property string key: "a:" + index
              width: (actionRow.width - actionRow.spacing * (root.actions.length - 1)) / root.actions.length
              text: modelData.text
              iconText: modelData.icon
              bordered: true
              fontSize: Style.font.bodySmall
              iconSize: Style.font.icon
              horizontalPadding: Style.space(6)
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              hasCursor: root.cursorActive && root.cursorKey === key
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !(root.client && root.client.busyAction !== "" && (modelData.key === "reboot" || modelData.key === "poweroff"))
              onHovered: function(on) { if (on) root.hover(actionButton.key); else root.unhover(actionButton.key) }
              onClicked: root.runAction(modelData.key)
            }
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
          foreground: root.foreground
          selectedText: root.urgent
          fontFamily: root.fontFamily
          onCanceled: root.resolveConfirm(false)
          onConfirmed: root.resolveConfirm(true)
        }
      }
    }
  }

  // A container on one line: its state, name and how long it has been up. The
  // cursor swaps the status for stop or start and restart; the image is the
  // name's tooltip. Stopped ones dim, unhealthy ones urgent.
  component ContainerRow: CursorSurface {
    id: row

    property var container: null
    property string rowKey: ""
    readonly property bool running: Model.containerRunning(container)
    readonly property bool busy: !!root.client && root.client.busyAction.indexOf(":" + (container ? container.name : "")) !== -1
      && root.client.busyAction.indexOf("docker-") === 0
    readonly property bool unhealthy: !!container && /unhealthy|restarting/i.test(container.status + " " + container.state)

    hasCursor: root.cursorActive && root.cursorKey === rowKey
    foreground: root.foreground
    implicitHeight: Math.max(rowName.implicitHeight + Style.spacing.xl, rowStatus.implicitHeight + Style.spacing.xl, buttons.implicitHeight + Style.spacing.xxs)
    onHasCursorChanged: if (hasCursor && root.keyboardCursor) root.scrollIntoView(row)

    HoverHandler {
      onHoveredChanged: if (hovered) root.hover(row.rowKey); else root.unhover(row.rowKey)
    }

    RowIcon {
      id: rowIcon
      text: row.unhealthy ? "󰀦" : (row.running ? "󰗠" : "󰝦")
      color: row.unhealthy ? root.urgent : (row.running ? root.foreground : root.dim)
    }

    PanelText {
      id: rowName
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.space(8)
      anchors.right: statusBox.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.Wrap
      text: row.container ? row.container.name : ""
      color: row.unhealthy ? root.urgent : (row.running ? root.foreground : root.dim)

      HoverHandler { id: nameHover }

      PanelToolTip {
        visible: nameHover.hovered && text !== ""
        text: row.container ? row.container.image : ""
        fontFamily: root.fontFamily
      }
    }

    Item {
      id: statusBox
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      // At least the buttons' room, so swapping to them never moves the name.
      width: Math.max(Style.space(50), Math.min(rowStatus.implicitWidth, Style.space(132)))
      height: rowStatus.implicitHeight

      PanelText {
        id: rowStatus
        width: parent.width
        visible: !buttons.visible
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.Wrap
        text: row.busy ? "Working…" : (row.container ? Model.containerStatus(row.container) : "")
        color: row.unhealthy ? root.urgent : root.dim
        font.pixelSize: Style.font.bodySmall
      }
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      visible: row.hasCursor && !row.busy

      PanelActionButton {
        iconText: row.running ? "󰓛" : "󰐊"
        tooltipText: row.running ? "Stop (s)" : "Start (s)"
        foreground: root.foreground
        hoverColor: row.running ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        enabled: !!root.client && root.client.busyAction === ""
        onClicked: root.toggleContainer(row.container)
      }

      PanelActionButton {
        visible: row.running
        iconText: "󰜉"
        tooltipText: "Restart (enter)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !!root.client && root.client.busyAction === ""
        onClicked: root.restartContainer(row.container)
      }
    }
  }

  // A failed systemd unit: its name over its description, with restart on
  // the right.
  component UnitRow: CursorSurface {
    id: unitRow

    property var unit: null
    property string rowKey: ""
    readonly property bool busy: !!root.client && root.client.busyAction === "unit-restart:" + (unit ? unit.name : "")

    hasCursor: root.cursorActive && root.cursorKey === rowKey
    foreground: root.foreground
    implicitHeight: Math.max(unitText.implicitHeight, restart.implicitHeight) + Style.spacing.rowPaddingX
    onHasCursorChanged: if (hasCursor && root.keyboardCursor) root.scrollIntoView(unitRow)

    HoverHandler {
      onHoveredChanged: if (hovered) root.hover(unitRow.rowKey); else root.unhover(unitRow.rowKey)
    }

    RowIcon {
      id: unitIcon
      text: "󰅚"
      color: root.urgent
    }

    Column {
      id: unitText
      anchors.left: unitIcon.right
      anchors.leftMargin: Style.space(8)
      anchors.right: restart.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      PanelText {
        width: parent.width
        wrapMode: Text.Wrap
        text: unitRow.unit ? unitRow.unit.name : ""
        color: root.urgent
      }

      PanelText {
        visible: text !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: unitRow.busy ? "Restarting…" : (unitRow.unit ? unitRow.unit.description : "")
        color: root.dim
        font.pixelSize: Style.font.caption
      }
    }

    PanelActionButton {
      id: restart
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰜉"
      tooltipText: "Restart service (uses sudo)"
      foreground: root.foreground
      fontFamily: root.fontFamily
      enabled: !unitRow.busy && !!root.client && root.client.busyAction === ""
      onClicked: root.restartUnit(unitRow.unit)
    }
  }
}
