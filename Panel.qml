import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The dashboard: gauges, history, system facts, storage, containers, failed
// services and processes for the connected server, plus the connect form.
Panel {
  id: root
  moduleName: "io.github.t3lluz.server-dashboard"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var client: null

  // Cursor shared by keyboard and mouse: "c:<i>" container, "u:<i>" failed
  // unit, "a:<i>" action button.
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
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var snap: client && client.snapshot ? client.snapshot : null
  readonly property bool online: !!client && client.online && snap !== null
  readonly property string status: client ? client.status : "unconfigured"
  readonly property string errorKind: client ? client.errorKind : ""
  readonly property string displayName: hostWidget ? hostWidget.displayName : "Server"
  readonly property bool showSetup: !!client && (!client.configured || setupOpen
    || (status === "error" && ["auth", "nopassword", "config", "keyring"].indexOf(errorKind) !== -1))
  readonly property bool showDetails: online && !showSetup && expanded
  readonly property var containers: online && snap.containers ? snap.containers : []
  readonly property var failedUnits: online && snap.failedUnits ? snap.failedUnits : []
  readonly property var processes: online && snap.processes ? snap.processes : []
  readonly property var disks: online && snap.disks ? snap.disks : []
  readonly property var rootDisk: disks.length > 0 ? disks[0] : null
  readonly property int runningContainers: containers.filter(Model.containerRunning).length

  readonly property var actions: [
    { key: "ssh", icon: "󰆍", text: "SSH", hint: "Open a shell on the server" },
    { key: "btop", icon: "󰓅", text: "Monitor", hint: "Open btop (or htop/top) on the server" },
    { key: "reboot", icon: "󰜉", text: "Reboot", hint: "Reboot the server" },
    { key: "poweroff", icon: "󰐥", text: "Power off", hint: "Shut the server down" }
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

  // The banners under the hero, as in the other plugins: a changed host key,
  // the action running or just finished, the server's alerts, an update.
  readonly property var notices: {
    var list = []
    if (!client) return list
    if (status === "error" && errorKind === "hostkey" && !showSetup)
      list.push({ key: "hostkey", tone: "urgent", icon: "󰌋", text: client.errorText, action: "trustKey", actionLabel: "Trust it" })
    if (client.actionStatus !== "")
      list.push({ key: "action", tone: client.actionFailed ? "urgent" : "accent", busy: client.busyAction !== "",
                  icon: client.busyAction !== "" ? "󰑐" : (client.actionFailed ? "󰀦" : "󰄬"), text: client.actionStatus })
    var alerts = alertText()
    if (alerts !== "" && !showSetup) list.push({ key: "alerts", tone: "urgent", icon: "󰀦", text: alerts.charAt(0).toUpperCase() + alerts.slice(1) })
    if (updater && updater.notice) list.push(updater.notice)
    return list
  }

  function noticeAction(notice) {
    if (notice.action === "trustKey") client.trustNewKey()
    else if (notice.action === "update" && updater) updater.apply()
  }

  function dismissNotice(notice) {
    if (notice.key === "update" && updater) updater.dismiss()
  }

  readonly property var cursorTargets: {
    var keys = []
    if (!online || showSetup) return keys
    if (expanded) for (var c = 0; c < containers.length; c++) keys.push("c:" + c)
    for (var u = 0; u < failedUnits.length; u++) keys.push("u:" + u)
    for (var a = 0; a < actions.length; a++) keys.push("a:" + a)
    return keys
  }

  readonly property var infoRows: {
    if (!online) return []
    var rows = []
    if (snap.osName) rows.push({ label: "OS", value: snap.osName })
    if (snap.kernel) rows.push({ label: "Kernel", value: snap.kernel + (snap.arch ? " · " + snap.arch : "") })
    if (snap.cpuModel || snap.cores) rows.push({ label: "CPU", value: (snap.cpuModel || "CPU") + (snap.cores ? " · " + snap.cores + " threads" : "") })
    if (snap.load) rows.push({ label: "Load", value: snap.load.one.toFixed(2) + "  " + snap.load.five.toFixed(2) + "  " + snap.load.fifteen.toFixed(2) })
    if (snap.memory && snap.memory.swapTotalBytes > 0) rows.push({ label: "Swap", value: Model.bytes(snap.memory.swapUsedBytes) + " / " + Model.bytes(snap.memory.swapTotalBytes) })
    if (snap.load && snap.load.total) rows.push({ label: "Tasks", value: snap.load.total + " (" + snap.load.running + " running)" })
    rows.push({ label: "Uptime", value: Model.uptime(snap.uptimeSeconds) })
    rows.push({ label: "Login", value: (snap.user || Model.targetUser(client.target)) + "@" + Model.targetHost(client.target) })
    if (snap.rebootRequired) rows.push({ label: "Updates", value: "Reboot required", urgent: true })
    return rows
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function heat(value, warm, hot) { return Model.level(value, warm, hot) }

  function heroMeta() {
    if (!client || !client.configured) return "Connect a server over SSH"
    if (online) return (snap.osName || "Linux") + " · up " + Model.uptime(snap.uptimeSeconds)
    if (status === "error") return client.errorText
    return "Connecting to " + client.target + "…"
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

  function activateCursor() {
    var parts = cursorKey.split(":")
    var i = Number(parts[1])
    if (parts[0] === "c") restartContainer(containers[i])
    else if (parts[0] === "u") restartUnit(failedUnits[i])
    else if (parts[0] === "a") runAction(actions[i].key)
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

  function summaryText() {
    if (!online) return ""
    var parts = ["󰇚 " + Model.rate(snap.rxRate), "󰕒 " + Model.rate(snap.txRate)]
    if (containers.length > 0) parts.push("󰡨 " + runningContainers + "/" + containers.length)
    return parts.join("   ")
  }

  function alertText() {
    if (!online) return ""
    var alerts = []
    var unhealthy = containers.filter(function(c) { return /unhealthy|restarting/i.test(c.status + " " + c.state) })
    if (unhealthy.length > 0) alerts.push(unhealthy.length === 1 ? unhealthy[0].name + " is unhealthy" : unhealthy.length + " containers unhealthy")
    if (rootDisk && rootDisk.percent >= 90) alerts.push("root disk " + Model.percent(rootDisk.percent) + " full")
    if (snap.rebootRequired) alerts.push("reboot required")
    return alerts.join(" · ")
  }

  function askConfirm(kind) {
    confirmKind = kind
    confirm.selectedIndex = 0
    Qt.callLater(function() { confirmKeys.forceActiveFocus() })
  }

  function confirmMessage() {
    if (confirmKind === "reboot") return "Reboot " + displayName + "? Everything on it is unavailable until it comes back."
    if (confirmKind === "poweroff") return "Power off " + displayName + "? You will need physical or out-of-band access to turn it back on."
    return ""
  }

  function resolveConfirm(accepted) {
    var kind = confirmKind
    confirmKind = ""
    keyCatcher.forceActiveFocus()
    if (!accepted || !client) return
    client.runAction(kind, "", kind === "reboot" ? "Rebooting " + displayName : "Powering off " + displayName)
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
    var p = item.mapToItem(column, 0, 0)
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
    if (panelFlick) panelFlick.contentY = 0
    resetForm()
    if (client) {
      client.retry()
      if (showSetup) client.refreshPeers()
    }
    Qt.callLater(function() {
      if (root.showSetup && !(root.client && root.client.configured)) targetField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.showDetails ? 460 : 380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

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
        else if (key === "s" && root.cursorKey.indexOf("c:") === 0) root.toggleContainer(root.containers[Number(root.cursorKey.split(":")[1])])
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------------------------------------------------------- hero
          PanelHero {
            id: hero
            width: parent.width
            title: root.setupOpen && root.client && root.client.configured ? "Settings" : root.displayName
            meta: root.setupOpen && root.client && root.client.configured ? "Changes save as you make them" : root.heroMeta()
            foreground: root.foreground
            fontFamily: root.fontFamily
            // Online or not shows as a dot on the server, as on the bar
            // icon; the line under the title says what is going on.
            iconComponent: Component {
              Item {
                implicitWidth: serverGlyph.implicitWidth
                implicitHeight: serverGlyph.implicitHeight

                Text {
                  id: serverGlyph
                  textFormat: Text.PlainText
                  text: "󰒋"
                  color: root.status === "error" && root.client && !root.client.needsUser ? root.urgent : root.foreground
                  opacity: root.online ? 1 : 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }

                Rectangle {
                  id: statusDot
                  readonly property bool connecting: !!root.client && root.client.configured && !root.online && root.status !== "error"
                  visible: !!root.client && root.client.configured
                  width: Math.max(8, Style.space(10))
                  height: width
                  radius: width / 2
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(4)
                  color: root.online ? root.accent : (root.status === "error" ? root.urgent : root.dim)
                  border.width: Math.max(2, Style.space(2))
                  border.color: Commons.Color.popups.background

                  SequentialAnimation on opacity {
                    running: statusDot.connecting
                    loops: Animation.Infinite
                    onStopped: statusDot.opacity = 1
                    NumberAnimation { from: 1; to: 0.25; duration: 600 }
                    NumberAnimation { from: 0.25; to: 1; duration: 600 }
                  }

                  PanelToolTip {
                    visible: dotMouse.containsMouse
                    text: root.online ? "Online" : (root.status === "error" ? "Offline" : "Connecting")
                    fontFamily: root.fontFamily
                  }

                  MouseArea {
                    id: dotMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                  }
                }
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(2)

                PanelActionButton {
                  visible: root.online && !root.setupOpen
                  iconText: root.expanded ? "󰅃" : "󰅀"
                  tooltipText: root.expanded ? "Less (e)" : "More: graphs, storage, containers and processes (e)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.toggleExpanded()
                }

                PanelActionButton {
                  visible: !!root.client && root.client.configured && !root.setupOpen
                  iconText: "󰑐"
                  tooltipText: "Refresh (r)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.client.retry()
                }

                PanelActionButton {
                  iconText: root.setupOpen ? "󰁍" : "󰒓"
                  tooltipText: root.setupOpen ? "Back to the dashboard (c)" : "Settings: bar, alerts, connection and updates (c)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.setupOpen = !root.setupOpen
                }
              }
            }
          }

          // --------------------------------------------------------- banners
          Repeater {
            model: root.notices

            Notice {
              required property var modelData
              width: column.width
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

          // ------------------------------------------------------ bar options
          Column {
            visible: root.showSetup && !!root.client && root.client.configured
            width: parent.width
            spacing: Style.space(12)

            PanelSeparator { foreground: root.foreground }

            SectionHeader {
              icon: "󰍜"
              title: "SHOW IN THE BAR"
              detail: root.barPickedCount > 0 ? root.barPickedCount + " SHOWN" : "ICON ONLY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Grid {
              id: barGrid
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

            PanelSeparator { foreground: root.foreground }

            SectionHeader {
              icon: "󰂚"
              title: "ALERTS AND PANEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SwitchRow {
              icon: "󰂚"
              label: "Notify me"
              hint: "When the server drops or comes back, a container turns unhealthy, a disk passes 90% or a service fails"
              checked: root.setting("notify", true) === true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onToggled: root.setOption("notify", !checked)
            }

            SwitchRow {
              icon: "󰁌"
              label: "Open expanded"
              hint: "Graphs, storage, containers and processes without pressing More"
              checked: root.expanded
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onToggled: root.setOption("panelExpanded", !root.expanded)
            }
          }

          // ---------------------------------------------------- connect form
          Column {
            id: setupForm
            visible: root.showSetup
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.foreground }

            SectionHeader {
              icon: "󰌘"
              title: root.client && root.client.configured ? "CONNECTION" : "CONNECT A SERVER"
              detail: root.client && root.client.configured ? Model.targetHost(root.client.target).toUpperCase() : ""
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
              placeholderText: root.client && root.client.configured && root.errorKind !== "nopassword"
                ? "Password (leave empty to keep the saved one)"
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
              visible: root.client && root.client.peers.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.client ? root.client.peers : []

                Button {
                  required property var modelData
                  text: modelData.name
                  iconText: modelData.os === "linux" ? "󰌽" : (modelData.os === "windows" ? "󰖳" : "󰄜")
                  tooltipText: modelData.ip + (modelData.online ? "" : " · offline")
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
              spacing: Style.space(8)

              Button {
                text: "Connect"
                iconText: "󰌘"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.submitSetup()
              }

              Button {
                visible: !!root.client && root.client.configured
                text: "Forget password"
                iconText: "󰅖"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  root.client.forget()
                  passwordField.forceActiveFocus()
                }
              }
            }
          }

          // ------------------------------------------------- about and updates
          PanelSeparator { visible: root.showSetup; foreground: root.foreground }

          UpdateSection {
            visible: root.showSetup
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

          // ------------------------------------------------------- unreachable
          Caption {
            visible: !root.showSetup && !!root.client && root.client.configured && !root.online
              && root.errorKind !== "hostkey"
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(6)
            text: root.status === "error"
              ? "Retrying every 30 seconds. Press r to try now."
              : "Opening an SSH session…"
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalAlignment: Text.AlignHCenter
          }

          // ------------------------------------------------------------ gauges
          Row {
            id: gauges
            visible: root.online && !root.showSetup
            width: parent.width
            spacing: Style.space(8)
            readonly property int count: root.snap && root.snap.cpuTemp !== null ? 4 : 3
            readonly property real cell: (width - spacing * (count - 1)) / count

            Gauge {
              width: gauges.cell
              height: Math.min(gauges.cell, Style.space(104))
              label: "CPU"
              percent: root.snap && root.snap.cpuPercent !== null ? root.snap.cpuPercent : -1
              heat: root.heat(percent, 70, 90)
              subText: root.snap && root.snap.load ? "load " + root.snap.load.one.toFixed(2) : ""
              foreground: root.foreground
              urgent: root.urgent
              fontFamily: root.fontFamily
            }

            Gauge {
              width: gauges.cell
              height: Math.min(gauges.cell, Style.space(104))
              label: "RAM"
              percent: root.snap && root.snap.memory ? root.snap.memory.percent : -1
              heat: root.heat(percent, 80, 92)
              subText: root.snap && root.snap.memory ? Model.bytes(root.snap.memory.usedBytes) + "/" + Model.bytes(root.snap.memory.totalBytes) : ""
              foreground: root.foreground
              urgent: root.urgent
              fontFamily: root.fontFamily
            }

            Gauge {
              width: gauges.cell
              height: Math.min(gauges.cell, Style.space(104))
              label: "DISK"
              percent: root.rootDisk ? root.rootDisk.percent : -1
              heat: root.heat(percent, 80, 92)
              subText: root.rootDisk ? Model.bytes(root.rootDisk.usedBytes) + "/" + Model.bytes(root.rootDisk.totalBytes) : ""
              foreground: root.foreground
              urgent: root.urgent
              fontFamily: root.fontFamily
            }

            Gauge {
              visible: gauges.count === 4
              width: gauges.cell
              height: Math.min(gauges.cell, Style.space(104))
              label: "TEMP"
              // A 100 °C scale reads naturally as a dial.
              percent: root.snap && root.snap.cpuTemp !== null ? Math.min(100, root.snap.cpuTemp) : -1
              valueText: root.snap ? Model.temperature(root.snap.cpuTemp) : "—"
              heat: root.heat(root.snap ? root.snap.cpuTemp : null, 70, 85)
              subText: "cpu"
              foreground: root.foreground
              urgent: root.urgent
              fontFamily: root.fontFamily
            }
          }

          // ----------------------------------------------------------- summary
          Column {
            visible: root.online && !root.showSetup
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.summaryText()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }

          // ---------------------------------------------------------- activity
          Grid {
            id: activity
            visible: root.showDetails
            width: parent.width
            columns: 2
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(10)
            readonly property real cell: (width - columnSpacing) / 2

            Sparkline {
              width: activity.cell
              label: "CPU"
              glyph: "󰓅"
              valueText: root.snap ? Model.percent(root.snap.cpuPercent) : "—"
              values: root.client ? root.client.cpuHistory : []
              capacity: root.client ? root.client.historyLength : 60
              foreground: root.foreground
              lineColor: root.accent
              fontFamily: root.fontFamily
            }

            Sparkline {
              width: activity.cell
              label: "Memory"
              glyph: "󰍛"
              valueText: root.snap && root.snap.memory ? Model.percent(root.snap.memory.percent) : "—"
              values: root.client ? root.client.memHistory : []
              capacity: root.client ? root.client.historyLength : 60
              foreground: root.foreground
              lineColor: root.accent
              fontFamily: root.fontFamily
            }

            Sparkline {
              width: activity.cell
              label: "Download"
              glyph: "󰇚"
              maxValue: 0
              valueText: root.snap ? Model.rate(root.snap.rxRate) : "—"
              values: root.client ? root.client.rxHistory : []
              capacity: root.client ? root.client.historyLength : 60
              foreground: root.foreground
              lineColor: root.foreground
              fontFamily: root.fontFamily
            }

            Sparkline {
              width: activity.cell
              label: "Upload"
              glyph: "󰕒"
              maxValue: 0
              valueText: root.snap ? Model.rate(root.snap.txRate) : "—"
              values: root.client ? root.client.txHistory : []
              capacity: root.client ? root.client.historyLength : 60
              foreground: root.foreground
              lineColor: root.foreground
              fontFamily: root.fontFamily
            }
          }

          // ------------------------------------------------------------ system
          PanelSeparator { visible: root.showDetails; foreground: root.foreground }

          Column {
            visible: root.showDetails
            width: parent.width
            spacing: Style.space(12)

            SectionHeader {
              icon: "󰒋"
              title: "SYSTEM"
              detail: root.snap && root.snap.hostname ? String(root.snap.hostname).toUpperCase() : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.infoRows

                Row {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    width: Style.space(64)
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    width: parent.width - Style.space(72)
                    textFormat: Text.PlainText
                    text: modelData.value
                    color: modelData.urgent ? root.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          // ----------------------------------------------------------- storage
          PanelSeparator { visible: root.disks.length > 0 && root.showDetails; foreground: root.foreground }

          Column {
            visible: root.disks.length > 0 && root.showDetails
            width: parent.width
            spacing: Style.space(12)

            SectionHeader {
              icon: "󰋊"
              title: "STORAGE"
              detail: root.disks.length + (root.disks.length === 1 ? " DISK" : " DISKS")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.disks

                Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(3)

                  Item {
                    width: parent.width
                    implicitHeight: mountLabel.implicitHeight

                    Text {
                      id: mountLabel
                      anchors.left: parent.left
                      width: parent.width - usage.implicitWidth - Style.space(8)
                      textFormat: Text.PlainText
                      text: "󰋊 " + modelData.mount
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideMiddle
                    }

                    Text {
                      id: usage
                      anchors.right: parent.right
                      textFormat: Text.PlainText
                      text: Model.bytes(modelData.usedBytes) + " / " + Model.bytes(modelData.totalBytes) + "  " + Model.percent(modelData.percent)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  LevelBar {
                    width: parent.width
                    level: modelData.percent
                    fill: modelData.percent >= 90 ? root.urgent : root.accent
                    track: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                  }
                }
              }
            }
          }

          // -------------------------------------------------------- containers
          PanelSeparator { visible: root.containers.length > 0 && root.showDetails; foreground: root.foreground }

          Column {
            visible: root.containers.length > 0 && root.showDetails
            width: parent.width
            spacing: Style.space(12)

            SectionHeader {
              icon: "󰡨"
              title: "CONTAINERS"
              detail: root.runningContainers + "/" + root.containers.length + " RUNNING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.containers

                ContainerRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  container: modelData
                  rowKey: "c:" + index
                }
              }
            }
          }

          // ----------------------------------------------------- failed units
          PanelSeparator { visible: root.failedUnits.length > 0 && !root.showSetup; foreground: root.foreground }

          Column {
            visible: root.failedUnits.length > 0 && !root.showSetup
            width: parent.width
            spacing: Style.space(12)

            SectionHeader {
              icon: "󰀦"
              title: "FAILED SERVICES"
              detail: root.failedUnits.length + " FAILED"
              detailColor: root.urgent
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.failedUnits

                UnitRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  unit: modelData
                  rowKey: "u:" + index
                }
              }
            }
          }

          // --------------------------------------------------------- processes
          PanelSeparator { visible: root.processes.length > 0 && root.showDetails; foreground: root.foreground }

          Column {
            visible: root.processes.length > 0 && root.showDetails
            width: parent.width
            spacing: Style.space(12)

            SectionHeader {
              icon: "󰘚"
              title: "TOP PROCESSES"
              detail: "CPU · MEMORY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.processes

                Row {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    width: parent.width - cpuCol.width - memCol.width - parent.spacing * 2
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    id: cpuCol
                    width: Style.space(58)
                    textFormat: Text.PlainText
                    text: modelData.cpu.toFixed(1) + "%"
                    color: modelData.cpu >= 80 ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignRight
                  }

                  Text {
                    id: memCol
                    width: Style.space(58)
                    textFormat: Text.PlainText
                    text: Model.bytes(modelData.rssBytes)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }
            }
          }

          // ----------------------------------------------------------- actions
          PanelSeparator { visible: root.online && !root.showSetup; foreground: root.foreground }

          // One row, four equal buttons.
          Row {
            id: actionRow
            visible: root.online && !root.showSetup
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
                fontSize: Style.font.caption
                tooltipText: modelData.hint
                bordered: true
                hasCursor: root.cursorActive && root.cursorKey === key
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !(root.client && root.client.busyAction !== "" && (modelData.key === "reboot" || modelData.key === "poweroff"))
                onHovered: function(on) { if (on) root.hover(actionButton.key) }
                onClicked: root.runAction(modelData.key)
              }
            }
          }

          Caption {
            visible: root.online && !root.showSetup
            width: parent.width
            text: root.expanded ? "j/k · enter run · s start/stop · t ssh · b monitor · e less · c settings"
              : "j/k · enter run · t ssh · b monitor · r refresh · e more"
            foreground: root.foreground
            opacity: 0.4
            fontFamily: root.fontFamily
            horizontalAlignment: Text.AlignHCenter
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
          confirmText: root.confirmKind === "poweroff" ? "Power off" : "Reboot"
          foreground: root.foreground
          selectedText: root.urgent
          fontFamily: root.fontFamily
          onCanceled: root.resolveConfirm(false)
          onConfirmed: root.resolveConfirm(true)
        }
      }
    }
  }

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
    implicitHeight: Math.max(Style.space(38), rowText.implicitHeight + Style.space(10))
    onHasCursorChanged: if (hasCursor && root.keyboardCursor) root.scrollIntoView(row)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.hover(row.rowKey)
    }

    // In the kit's icon column: 8 in, 22 wide, 10 to the text.
    Rectangle {
      id: dot
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8) + (Style.space(22) - width) / 2
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(6, Style.space(7))
      height: width
      radius: width / 2
      color: row.unhealthy ? root.urgent : (row.running ? root.accent : Util.alpha(root.foreground, 0.25))
    }

    Column {
      id: rowText
      anchors.left: dot.right
      anchors.leftMargin: Style.space(10) + (Style.space(22) - dot.width) / 2
      anchors.right: buttons.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.container ? row.container.name : ""
        color: row.running ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.hasCursor
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.busy ? "working…" : (row.container ? Model.shortStatus(row.container.status) + " · " + row.container.image : "")
        color: row.unhealthy ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        iconText: row.running ? "󰓛" : "󰐊"
        tooltipText: row.running ? "Stop (s)" : "Start (s)"
        foreground: root.foreground
        hoverColor: row.running ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        enabled: !row.busy && !!root.client && root.client.busyAction === ""
        onClicked: root.toggleContainer(row.container)
      }

      PanelActionButton {
        visible: row.running
        iconText: "󰜉"
        tooltipText: "Restart (enter)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !row.busy && !!root.client && root.client.busyAction === ""
        onClicked: root.restartContainer(row.container)
      }
    }
  }

  component UnitRow: CursorSurface {
    id: unitRow

    property var unit: null
    property string rowKey: ""
    readonly property bool busy: !!root.client && root.client.busyAction === "unit-restart:" + (unit ? unit.name : "")

    hasCursor: root.cursorActive && root.cursorKey === rowKey
    foreground: root.foreground
    implicitHeight: Math.max(Style.space(34), unitText.implicitHeight + Style.space(10))
    onHasCursorChanged: if (hasCursor && root.keyboardCursor) root.scrollIntoView(unitRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.hover(unitRow.rowKey)
    }

    Glyph {
      id: unitIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      icon: "󰅚"
      size: Style.font.title
      color: root.urgent
      fontFamily: root.fontFamily
    }

    Column {
      id: unitText
      anchors.left: unitIcon.right
      anchors.leftMargin: Style.space(10)
      anchors.right: restart.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: unitRow.unit ? unitRow.unit.name : ""
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        visible: text !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: unitRow.busy ? "restarting…" : (unitRow.unit ? unitRow.unit.description : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    PanelActionButton {
      id: restart
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
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
