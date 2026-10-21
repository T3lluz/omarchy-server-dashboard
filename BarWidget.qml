import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry: a server mark with the stats picked in settings, and the host
// for the dashboard panel. The bar draws this widget once per monitor; the
// first instance owns the SSH client and the others read from it, so the
// server sees one poller and one login.
BarWidget {
  id: root
  moduleName: "io.github.t3lluz.server-dashboard"

  readonly property string target: String(setting("target", "")).trim()
  readonly property int port: Number(setting("port", 22)) || 22
  readonly property int intervalSec: Number(setting("refreshIntervalSec", 5)) || 5
  readonly property var barStats: {
    var stats = []
    if (setting("barCpu", true)) stats.push("cpu")
    if (setting("barRam", true)) stats.push("ram")
    if (setting("barDisk", false)) stats.push("disk")
    if (setting("barTemp", false)) stats.push("temp")
    if (setting("barNetwork", false)) stats.push("net")
    return stats
  }
  readonly property bool showsMetrics: barStats.length > 0 && !vertical

  property var leader: root
  readonly property bool isLeader: leader === root
  readonly property var ownClient: ownClientLoader.item ? ownClientLoader.item : null
  readonly property var client: isLeader ? ownClient : (leader ? leader.ownClient : null)

  readonly property string displayName: String(setting("displayName", "")).trim()
    || (client ? client.hostLabel : "") || "Server"
  readonly property bool online: !!client && client.online && !!client.snapshot
  readonly property color barFg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color iconColor: {
    if (!client) return Qt.darker(barFg, 1.55)
    if (client.status === "error" && !client.needsUser) return urgent
    if (client.online) return barFg
    return Qt.darker(barFg, 1.55)
  }
  readonly property var metricParts: {
    if (!showsMetrics || !online) return []
    var s = client.snapshot
    var parts = []
    for (var i = 0; i < barStats.length; i++) {
      var stat = barStats[i]
      if (stat === "cpu") parts.push("󰓅 " + Model.percent(s.cpuPercent))
      else if (stat === "ram") parts.push("󰍛 " + Model.percent(s.memory ? s.memory.percent : null))
      else if (stat === "disk" && s.disks && s.disks.length) parts.push("󰋊 " + Model.percent(s.disks[0].percent))
      else if (stat === "temp" && s.cpuTemp !== null) parts.push("󰔏 " + Model.temperature(s.cpuTemp))
      else if (stat === "net") {
        parts.push("󰇚 " + Model.rate(s.rxRate))
        parts.push("󰕒 " + Model.rate(s.txRate))
      }
    }
    return parts
  }
  readonly property string tooltip: {
    if (!client || !client.configured) return "Server Dashboard: click to connect a server"
    if (client.status === "error") return displayName + ": " + client.errorText
    if (!online) return displayName + ": connecting…"
    var s = client.snapshot
    return displayName + "  CPU " + Model.percent(s.cpuPercent)
      + "  RAM " + Model.percent(s.memory ? s.memory.percent : null)
      + "  up " + Model.uptime(s.uptimeSeconds)
  }

  function electLeader() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && "ownClient" in items[i]) {
        if (leader !== items[i]) leader = items[i]
        return
      }
    }
    if (leader !== root) leader = root
  }

  // Persists inline settings to this widget's shell.json entry, applied
  // locally first so the panel reacts on the click itself.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function connectServer(newTarget, newPort, password) {
    if (client) client.connectWith(newTarget, newPort, password)
    persistSettings({ target: newTarget, port: newPort })
  }

  // ---- Panel lifecycle, forwarded so shell summon/hide/toggle route here.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  property bool countedOpen: false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function refresh() { if (client) client.retry() }
  function prepareSettings() { if (panelLoader.item) panelLoader.item.setupOpen = true }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.client = root.client
  }

  function syncOpenCount() {
    var want = opened && !!client
    if (want === countedOpen) return
    countedOpen = want
    if (client) client.openPanels = Math.max(0, client.openPanels + (want ? 1 : -1))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: { electLeader(); injectPanel() }
  onSettingsChanged: injectPanel()
  onClientChanged: injectPanel()
  onOpenedChanged: syncOpenCount()
  Component.onCompleted: electLeader()
  Component.onDestruction: if (countedOpen && client) client.openPanels = Math.max(0, client.openPanels - 1)

  // moduleWidgets is not reactive, and monitors come and go.
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.electLeader()
  }

  Loader {
    id: ownClientLoader
    active: root.isLeader
    sourceComponent: Component { ServerClient { } }
  }

  // Every widget writes the same values, so the shared client sees one config.
  Binding { restoreMode: Binding.RestoreNone; target: root.client; when: !!root.client; property: "target"; value: root.target }
  Binding { restoreMode: Binding.RestoreNone; target: root.client; when: !!root.client; property: "port"; value: root.port }
  Binding { restoreMode: Binding.RestoreNone; target: root.client; when: !!root.client; property: "intervalSec"; value: root.intervalSec }
  Binding { restoreMode: Binding.RestoreNone; target: root.client; when: !!root.client; property: "barMetrics"; value: root.showsMetrics }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.t3lluz.server-dashboard"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // The focused monitor's widget opens; every panel is primed since the
    // shell, not this handler, decides which one that is.
    function settings(): void {
      root.broadcast("prepareSettings")
      var shell = root.bar ? root.bar.shell : null
      if (shell && typeof shell.summon === "function") shell.summon(root.moduleName, "{}")
      else root.open()
    }
    function refresh(): string { root.refresh(); return "ok" }
    function status(): string {
      var c = root.client
      if (!c) return JSON.stringify({ status: "loading" })
      return JSON.stringify({
        target: c.target,
        status: c.status,
        error: c.errorText,
        widgets: root.bar && root.bar.moduleWidgets ? root.bar.moduleWidgets(root.moduleName).length : 1,
        expanded: panelLoader.item ? panelLoader.item.expanded : null,
        cpu: c.snapshot ? c.snapshot.cpuPercent : null,
        memory: c.snapshot && c.snapshot.memory ? c.snapshot.memory.percent : null,
        uptime: c.snapshot ? c.snapshot.uptimeSeconds : null
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: true
    tooltipText: root.tooltip
    fixedWidth: root.vertical ? -1 : (root.metricParts.length > 0 ? content.implicitWidth + scaledHorizontalMargin * 2 : Style.bar.iconSlot)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else if (buttonCode === Qt.RightButton) { if (root.client && root.client.configured) root.client.openTerminal("") }
      else root.toggle()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)

      Item {
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        anchors.verticalCenter: parent.verticalCenter

        OpticalGlyph {
          anchors.fill: parent
          text: "󰒋"
          fontFamily: button.fontFamily
          fontSize: Style.bar.iconFont
          color: root.iconColor
        }

        // Pulses while the first connection is in flight.
        Rectangle {
          readonly property bool connecting: !!root.client && root.client.configured && root.client.status === "connecting"
          visible: connecting
          width: Math.max(4, Style.space(4))
          height: width
          radius: width / 2
          color: root.barFg
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          SequentialAnimation on opacity {
            running: parent.connecting
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.2; duration: 600 }
            NumberAnimation { from: 0.2; to: 1; duration: 600 }
          }
        }
      }

      // One item per stat so the row spacing, not padding characters,
      // separates them: the same gap as between the icon and the first stat.
      Repeater {
        id: metrics
        model: root.metricParts

        Text {
          required property string modelData
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData
          color: root.barFg
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
