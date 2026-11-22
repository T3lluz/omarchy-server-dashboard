import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry: the server mark with the stats picked in settings, each a pixel
// icon and its figure in the pixel type, in the bar's own colours, and the
// host for the dashboard panel. Resting the pointer on it opens a card with
// the readings. The bar draws this widget once per monitor; the first
// instance owns the SSH client and the others read from it, so the server
// sees one poller and one login.
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
  readonly property color barFg: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(barFg, 1.55)
  // Everything on whole device pixels, never scaled. Figures in the pixel
  // type stand as tall as the bar's own digits. Icons take the largest sharp
  // size that is not bigger than the shell's own (its icon size, with pixel
  // art's two units clear around the 24): twelve device pixels on a 1.25
  // scale, twenty-four on a 2.
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  readonly property int pixelUnit: Math.max(1, Math.round(button.fontSize * 0.72 * dpr / 5))
  readonly property int iconUnit: Math.max(1, Math.floor(Style.bar.iconSize * 24 / 20 * dpr / 12))

  // The mark: the server, the alert while something is wrong (a mark, not
  // only a colour), its lights taking turns while it connects or reboots.
  readonly property var mark: Model.barMark({
    configured: !!client && client.configured,
    online: online,
    status: client ? client.status : "unconfigured",
    needsUser: !!client && client.needsUser,
    alertCount: client ? client.alertCount : 0,
    working: !!client && client.configured && ((client.status === "connecting" && !client.snapshot)
      || /^(reboot|poweroff):/.test(client.busyAction))
  })
  readonly property var items: showsMetrics && online ? Model.barItems(client.snapshot, barStats) : []

  function toneColor(tone) {
    if (tone === "low") return urgent
    if (tone === "dim") return dim
    return barFg
  }

  // The shell's plain tooltip, only while there is no card to show.
  readonly property string tooltip: {
    if (!client || !client.configured) return "Server Dashboard: click to connect a server"
    if (client.status === "error") return displayName + ": " + client.errorText
    if (!online) return displayName + ": connecting…"
    return ""
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

  // Settings come from shell.json itself rather than the bar's copy, so
  // every monitor agrees after a reload (WidgetSettings.qml).
  function setting(name, fallback) { return prefs.get(name, fallback) }
  function persistSettings(values) { prefs.save(values) }

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

  // summon, hide or toggle through the shell; this widget's own panel when
  // there is no shell to ask.
  function summon(how) {
    var shell = root.bar ? root.bar.shell : null
    var done = false
    if (shell && how === "summon" && typeof shell.summon === "function") done = shell.summon(root.moduleName, "{}")
    else if (shell && how === "hide" && typeof shell.hide === "function") done = shell.hide(root.moduleName)
    else if (shell && how === "toggle" && typeof shell.toggle === "function") done = shell.toggle(root.moduleName, "{}")
    if (done) return
    if (how === "summon") root.open()
    else if (how === "hide") root.close()
    else root.toggle()
  }
  function refresh() { if (client) client.retry() }
  function prepareSettings() { if (panelLoader.item) panelLoader.item.setupOpen = true }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.prefs = prefs
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

  WidgetSettings {
    id: prefs
    moduleName: root.moduleName
    injected: root.settings
    shell: root.bar ? root.bar.shell : null
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
  Binding { restoreMode: Binding.RestoreNone; target: root.client; when: !!root.client; property: "notify"; value: root.setting("notify", true) === true }
  Binding { restoreMode: Binding.RestoreNone; target: root.client; when: !!root.client; property: "autoUpdateCheck"; value: root.setting("autoUpdateCheck", true) === true }
  Binding { restoreMode: Binding.RestoreNone; target: root.client; when: !!root.client; property: "displayName"; value: String(root.setting("displayName", "")).trim() }

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

    // Through the shell, which opens the panel on the focused monitor; this
    // handler belongs to whichever monitor's widget registered first.
    function open(): void { root.summon("summon") }
    function close(): void { root.summon("hide") }
    function show(): void { root.summon("summon") }
    function hide(): void { root.summon("hide") }
    function toggle(): void { root.summon("toggle") }
    // The focused monitor's widget opens; every panel is primed since the
    // shell, not this handler, decides which one that is.
    function settings(): void {
      root.broadcast("prepareSettings")
      root.summon("summon")
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
        room: panelLoader.item ? panelLoader.item.openRoom : null,
        cpu: c.snapshot ? c.snapshot.cpuPercent : null,
        memory: c.snapshot && c.snapshot.memory ? c.snapshot.memory.percent : null,
        uptime: c.snapshot ? c.snapshot.uptimeSeconds : null
      })
    }
  }

  // The hover card: after the shell's tooltip delay, gone the moment the
  // pointer leaves or the panel opens.
  readonly property var hoverRows: online ? Model.hoverRows(client.snapshot) : []
  readonly property bool cardWanted: button.tooltipHovered && !opened && hoverRows.length > 0
  property bool cardShown: false
  onCardWantedChanged: if (!cardWanted) cardShown = false

  Timer {
    interval: 400
    running: root.cardWanted && !root.cardShown
    onTriggered: root.cardShown = true
  }

  HoverCard {
    target: button
    bar: root.bar
    shown: root.cardShown
    rows: root.hoverRows
    note: root.online ? Model.hoverNote(root.client.snapshot) : ""
    palette: panelLoader.item ? panelLoader.item.palette : ({})
    unit: root.pixelUnit
    fontFamily: button.fontFamily
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: true
    // The hover card above takes the place of the plain tooltip once the
    // server answers.
    tooltipText: root.tooltip
    fixedWidth: root.vertical ? -1 : (root.items.length > 0 ? content.implicitWidth + scaledHorizontalMargin * 2 : Style.bar.iconSlot)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else if (buttonCode === Qt.RightButton) { if (root.client && root.client.configured) root.client.openTerminal("") }
      else root.toggle()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      // One slot, as big as the mark, so swapping it for the alert moves
      // nothing beside it.
      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: serverMark.implicitWidth
        height: serverMark.implicitHeight

        ServerMark {
          id: serverMark
          visible: root.mark.icon === "server"
          unit: root.iconUnit
          working: root.mark.working
          color: root.toneColor(root.mark.tone)
          dimColor: root.mark.tone === "dim" ? Qt.darker(root.barFg, 2.2) : root.dim
        }

        PixelIcon {
          visible: root.mark.icon !== "server"
          name: root.mark.icon
          unit: root.iconUnit
          color: root.toneColor(root.mark.tone)
        }
      }

      Repeater {
        model: root.vertical ? [] : root.items

        Row {
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          PixelIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: modelData.icon
            unit: root.iconUnit
            color: modelData.hot ? root.urgent : root.barFg
          }

          PixelText {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.text
            unit: root.pixelUnit
            color: modelData.hot ? root.urgent : root.barFg
          }
        }
      }
    }
  }
}
