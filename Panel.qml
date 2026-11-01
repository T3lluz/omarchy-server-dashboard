import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Glyphs.js" as Glyphs

// The dashboard, drawn the way Batteries draws its devices: the server big
// with its readings beside it, then each part with its number, then failed
// services, and with More the containers and processes. The gear swaps them
// for the settings and the connect form, which keep the family's panel kit.
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
  readonly property bool configured: !!client && client.configured
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

  // The server's readings: the facts beside its drawing and a row per part.
  readonly property var facts: Model.serverFacts(online ? snap : null)
  readonly property var parts: online ? Model.parts(snap, expanded) : []
  // Connecting, rebooting or powering off: the server pulses until it is
  // done, the way a device pulses in Batteries while it charges.
  readonly property bool serverWorking: configured && ((!online && status !== "error")
    || /^(reboot|poweroff):/.test(client.busyAction))

  // The family's rhythm, as in Batteries: settings keep the kit's gaps, the
  // dashboard gets more air around its drawings.
  readonly property real sectionGap: Style.space(12)
  readonly property real tileGap: Style.space(8)
  readonly property real groupGap: Style.space(20)
  // The gap between a name and its status line.
  readonly property real lineGap: Style.space(3)
  // A part's drawing runs from its reading's cap height to the baseline of
  // the share under it.
  readonly property real partIconSize: readingType.height + lineGap + smallType.height - capInset(readingType) - smallType.descent

  readonly property var actions: [
    { key: "ssh", icon: "󰆍", text: "SSH", hint: "Open a shell on the server (t)" },
    { key: "btop", icon: "󰓅", text: "Monitor", hint: "Open btop, or htop or top, on the server (b)" },
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

  // The banners at the top of the dashboard, as in the other plugins: a
  // changed host key, the action running or just finished, the server's
  // alerts, an update.
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

  // How far below a line's top its capitals start.
  function capInset(metrics) { return metrics.ascent - metrics.tightBoundingRect("H").height }

  // Width over height of what a drawing draws (Glyphs.js).
  function inkAspect(name) {
    var ink = Glyphs.glyphs[name].ink
    return (ink[2] - ink[0]) / (ink[3] - ink[1])
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function heroMeta() {
    if (setupOpen && configured) return "Changes save as you make them"
    if (!configured) return "Connect a server over SSH"
    if (online) {
      var count = client.alertCount
      return (snap.osName || "Linux") + " · " + (count === 0 ? "all clear" : count + (count === 1 ? " alert" : " alerts"))
    }
    if (status === "error") return "Offline"
    return "Connecting to " + Model.targetHost(client.target)
  }

  // What the server is doing, a part per line beside its drawing.
  function serverStatus() {
    if (!configured) return ""
    if (client.busyAction.indexOf("reboot:") === 0) return "Rebooting"
    if (client.busyAction.indexOf("poweroff:") === 0) return "Powering off"
    if (online) return "Online" + (snap.uptimeSeconds > 0 ? "\nUp " + Model.uptimeLong(snap.uptimeSeconds) : "")
    if (status === "error") return "Offline\n" + client.errorText
    return "Connecting\nOpening an SSH session"
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

  // One part of the server: its drawing and name on the left, and on the
  // right its reading over the share in use. The drawing runs from the
  // reading's cap height to the share's baseline, in a column as wide as
  // the memory stick needs, so every name starts at the same place.
  component PartRow: Item {
    id: partRow
    property var part: null
    readonly property color tone: part && part.hot ? root.urgent : root.foreground

    width: parent ? parent.width : 0
    height: Math.max(partValues.implicitHeight, partName.implicitHeight)

    DeviceGlyph {
      id: partGlyph
      x: Style.space(2)
      y: root.capInset(readingType)
      width: Math.round(root.partIconSize * 1.5)
      height: root.partIconSize
      name: partRow.part ? partRow.part.glyph : "cpu"
      color: root.foreground
    }

    Text {
      id: partName
      anchors.left: partGlyph.right
      anchors.leftMargin: Style.space(16)
      anchors.right: partValues.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: partGlyph.verticalCenter
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: partRow.part ? partRow.part.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
    }

    Column {
      id: partValues
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      spacing: root.lineGap

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: partRow.part ? partRow.part.detail : ""
        color: partRow.part && partRow.part.detail === "--" ? root.dim : partRow.tone
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: partRow.part ? partRow.part.share : ""
        color: partRow.part && partRow.part.hot ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // A group's name in bold with what it holds on the right, the way
  // Batteries heads its AirPods.
  component GroupHeader: Item {
    id: groupHeader
    property string title: ""
    property string detail: ""
    property color titleColor: root.foreground

    width: parent ? parent.width : 0
    height: Math.max(groupTitle.implicitHeight, groupDetail.implicitHeight)

    Text {
      id: groupTitle
      x: Style.space(2)
      textFormat: Text.PlainText
      text: groupHeader.title
      color: groupHeader.titleColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      id: groupDetail
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.baseline: groupTitle.baseline
      width: parent.width - groupTitle.implicitWidth - Style.space(20)
      horizontalAlignment: Text.AlignRight
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: groupHeader.detail
      color: root.dim
      font.family: root.fontFamily
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
          spacing: Style.space(14)

          PanelHero {
            id: hero
            width: parent.width
            title: root.setupOpen && root.configured ? "Settings" : root.displayName
            meta: root.heroMeta()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰒋"
                color: root.status === "error" && root.client && !root.client.needsUser ? root.urgent : root.foreground
                opacity: root.online || !root.configured ? 1 : 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(2)

                PanelActionButton {
                  visible: root.online && !root.setupOpen
                  iconText: root.expanded ? "󰅃" : "󰅀"
                  tooltipText: root.expanded ? "Less (e)" : "More: every disk, containers and processes (e)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.toggleExpanded()
                }

                PanelActionButton {
                  visible: root.configured && !root.setupOpen
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

          PanelSeparator { foreground: root.foreground }

          // ======================================================= dashboard
          // Roomier than the settings: the drawings need air around them.
          Column {
            visible: !root.showSetup
            width: parent.width
            spacing: root.groupGap

            Repeater {
              model: root.notices

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

            // Type measured once, so drawings can line up with text: from the
            // cap height of a first line to the baseline of a last.
            FontMetrics { id: statusType; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle }
            FontMetrics { id: readingType; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            FontMetrics { id: smallType; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }

            // ------------------------------------------------------- server
            // The server drawn as tall as what it is doing and its readings
            // beside it, as Batteries draws the laptop.
            Item {
              visible: root.configured
              width: parent.width
              height: serverInfo.implicitHeight

              // From the status's cap height to the last row's baseline, in
              // the drawing's own proportions. The readings have a fixed
              // width, so the drawing can size from their height without a
              // loop; past the room left it shrinks and centres.
              Item {
                id: serverArt
                readonly property real aspect: root.inkAspect("server")
                readonly property real span: serverInfo.implicitHeight - root.capInset(statusType) - smallType.descent
                readonly property real room: parent.width - serverInfo.width - Style.space(20) - x
                x: Style.space(2)
                width: Math.min(room, Math.round(span * aspect))
                height: Math.round(width / aspect)
                y: root.capInset(statusType) + (span - height) / 2

                PulseGlyph {
                  anchors.fill: parent
                  active: root.serverWorking
                  opacity: root.online || root.serverWorking ? 1 : 0.6
                  glyph: Component { DeviceGlyph { name: "server"; color: root.foreground } }
                }
              }

              Column {
                id: serverInfo
                anchors.right: parent.right
                anchors.rightMargin: Style.space(2)
                width: Style.space(156)
                spacing: Style.space(4)

                Text {
                  width: parent.width
                  bottomPadding: Style.space(4)
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: root.serverStatus()
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                }

                // Label on the left, reading on the right: the network, the
                // containers and the system.
                Repeater {
                  model: root.facts

                  Item {
                    required property var modelData
                    width: serverInfo.width
                    height: Math.max(factLabel.implicitHeight, factValue.implicitHeight)

                    Text {
                      id: factLabel
                      textFormat: Text.PlainText
                      text: modelData.label
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      id: factValue
                      anchors.right: parent.right
                      width: Math.min(implicitWidth, parent.width - factLabel.implicitWidth - Style.space(10))
                      horizontalAlignment: Text.AlignRight
                      wrapMode: Text.Wrap
                      textFormat: Text.PlainText
                      text: modelData.value
                      color: modelData.value === "--" ? root.dim : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                  }
                }
              }
            }

            Caption {
              visible: root.configured && root.status === "error" && root.errorKind !== "hostkey"
              width: parent.width
              leftPadding: Style.space(2)
              wrapMode: Text.WordWrap
              text: "Retrying every 30 seconds. Press r to try now."
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // -------------------------------------------------------- parts
            PanelSeparator { visible: root.parts.length > 0; foreground: root.foreground }

            Column {
              visible: root.parts.length > 0
              width: parent.width
              spacing: root.groupGap

              Repeater {
                model: root.parts

                PartRow {
                  required property var modelData
                  part: modelData
                }
              }
            }

            // ----------------------------------------------- failed services
            PanelSeparator { visible: root.failedUnits.length > 0; foreground: root.foreground }

            Column {
              visible: root.failedUnits.length > 0
              width: parent.width
              spacing: Style.space(12)

              GroupHeader {
                title: "Failed services"
                titleColor: root.urgent
                detail: root.failedUnits.length + " failed"
              }

              Column {
                width: parent.width
                spacing: Style.space(2)

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
            }

            // --------------------------------------------------- containers
            PanelSeparator { visible: root.showDetails && root.containers.length > 0; foreground: root.foreground }

            Column {
              visible: root.showDetails && root.containers.length > 0
              width: parent.width
              spacing: Style.space(12)

              GroupHeader {
                title: "Containers"
                detail: root.runningContainers + " of " + root.containers.length + " running"
              }

              Column {
                width: parent.width
                spacing: Style.space(2)

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

            // ---------------------------------------------------- processes
            PanelSeparator { visible: root.showDetails && root.processes.length > 0; foreground: root.foreground }

            Column {
              visible: root.showDetails && root.processes.length > 0
              width: parent.width
              spacing: Style.space(18)

              GroupHeader {
                title: "Processes"
                detail: "CPU and memory"
              }

              // Label on the left, readings on the right, as beside the
              // server.
              Column {
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: root.processes

                  Item {
                    required property var modelData
                    width: parent ? parent.width : 0
                    height: Math.max(procName.implicitHeight, procCpu.implicitHeight)

                    Text {
                      id: procName
                      x: Style.space(2)
                      width: procCpu.x - x - Style.space(10)
                      textFormat: Text.PlainText
                      wrapMode: Text.Wrap
                      text: modelData.name
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      id: procCpu
                      anchors.right: procMem.left
                      width: Style.space(56)
                      horizontalAlignment: Text.AlignRight
                      textFormat: Text.PlainText
                      text: modelData.cpu.toFixed(1) + "%"
                      color: modelData.cpu >= 80 ? root.urgent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      id: procMem
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(2)
                      width: Style.space(72)
                      horizontalAlignment: Text.AlignRight
                      textFormat: Text.PlainText
                      text: Model.size(modelData.rssBytes)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                  }
                }
              }
            }

            // ------------------------------------------------------ actions
            PanelSeparator { visible: root.online; foreground: root.foreground }

            // One row, four equal buttons, unboxed like the rest of the view.
            Row {
              id: actionRow
              visible: root.online
              width: parent.width
              spacing: Style.space(4)

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
                  fontSize: Style.font.bodySmall
                  iconSize: Style.font.body
                  tooltipText: modelData.hint
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

          // ======================================================== settings
          Column {
            visible: root.showSetup
            width: parent.width
            spacing: root.sectionGap

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
              columnSpacing: root.tileGap
              rowSpacing: root.tileGap

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
              icon: "󰂚"
              title: "ALERTS AND PANEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SwitchRow {
              visible: root.configured
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
              visible: root.configured
              icon: "󰁌"
              label: "Open expanded"
              hint: "Every disk, containers and processes without pressing More"
              checked: root.expanded
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onToggled: root.setOption("panelExpanded", !root.expanded)
            }

            PanelSeparator { visible: root.configured; foreground: root.foreground }

            // ---------------------------------------------------- connect form
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
                visible: !!root.client && root.client.peers.length > 0
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
                  visible: root.configured
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

            // -------------------------------------------- about and updates
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

  // A container: its name over what it is doing and its image, with stop or
  // start and restart on the right. Stopped ones dim, unhealthy ones urgent.
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
    implicitHeight: rowText.implicitHeight + Style.space(12)
    onHasCursorChanged: if (hasCursor && root.keyboardCursor) root.scrollIntoView(row)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.hover(row.rowKey)
      onExited: root.unhover(row.rowKey)
    }

    Column {
      id: rowText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: buttons.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.lineGap

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: row.container ? row.container.name : ""
        color: row.unhealthy ? root.urgent : (row.running ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: row.busy ? "Working…" : (row.container ? Model.containerStatus(row.container) + " · " + row.container.image : "")
        color: row.unhealthy ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
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

  // A failed systemd unit: its name over its description, with restart on
  // the right.
  component UnitRow: CursorSurface {
    id: unitRow

    property var unit: null
    property string rowKey: ""
    readonly property bool busy: !!root.client && root.client.busyAction === "unit-restart:" + (unit ? unit.name : "")

    hasCursor: root.cursorActive && root.cursorKey === rowKey
    foreground: root.foreground
    implicitHeight: unitText.implicitHeight + Style.space(12)
    onHasCursorChanged: if (hasCursor && root.keyboardCursor) root.scrollIntoView(unitRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.hover(unitRow.rowKey)
      onExited: root.unhover(unitRow.rowKey)
    }

    Column {
      id: unitText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: restart.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.lineGap

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: unitRow.unit ? unitRow.unit.name : ""
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
      }

      Text {
        visible: text !== ""
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: unitRow.busy ? "Restarting…" : (unitRow.unit ? unitRow.unit.description : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
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
