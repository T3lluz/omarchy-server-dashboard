import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The server as rooms, each tinted in a tone of its own from the theme: failed
// services in the alert tone when there are any, the System (processor,
// memory and temperature as cells), a row of small rooms (the Disk and the
// Network as square tiles, the Containers beside them), and the Processes. A click opens a room to the rest of its
// readings, its rows and its bar switches, one room at a time. Reads
// everything from `host` (Panel.qml, or the offscreen harness's stand-in).
Column {
  id: dash

  required property var host
  readonly property var snap: host.snap

  readonly property var cells: Model.systemCells(snap)
  readonly property var diskList: Model.disks(snap)
  readonly property var rootDisk: diskList.length > 0 ? diskList[0] : null
  readonly property var counts: Model.containerCounts(host.containers)

  // The rooms in the order they show, for when each comes in.
  readonly property var order: {
    var keys = []
    if (host.failedUnits.length > 0) keys.push("failed")
    keys.push("system")
    if (rootDisk) keys.push("disks")
    keys.push("network")
    if (host.containers.length > 0) keys.push("containers")
    if (host.processes.length > 0) keys.push("processes")
    return keys
  }

  function delayOf(key) { return Math.max(0, order.indexOf(key)) * 70 }
  function toneFor(key) { return host.toneOf(Model.roomTone(key)) }
  function keyed(key) { return host.keyboardCursor && host.cursorActive && host.cursorKey === "r:" + key }
  function track(room, key) {
    if (room.hovered) host.hover("r:" + key)
    else host.unhover("r:" + key)
  }

  width: parent ? parent.width : 0
  spacing: host.roomGap

  // ------------------------------------------------------------ pieces

  // A label on the left, its value on the right. A long value wraps; it is
  // never cut.
  component InfoPair: Item {
    id: pair
    property string label: ""
    property string value: ""
    property int delay: 0

    implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)

    Text {
      id: pairLabel
      textFormat: Text.PlainText
      text: pair.label
      color: dash.host.fg
      opacity: 0.6
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Decode {
      id: pairValue
      host: dash.host
      anchors.right: parent.right
      width: Math.min(implicitWidth, pair.width - pairLabel.implicitWidth - Style.space(8))
      horizontalAlignment: Text.AlignRight
      wrapMode: Text.Wrap
      value: pair.value
      delay: pair.delay
      color: pair.value === "--" ? dash.host.dim : dash.host.fg
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Readings two to a line, or one where the values run long.
  component Facts: Grid {
    id: factGrid
    property var facts: []
    property int delay: 0

    visible: facts.length > 0
    width: parent ? parent.width : 0
    columns: 2
    columnSpacing: Style.space(20)
    rowSpacing: Style.spacing.labelGap

    readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

    // Over the count, so a poll updates the readings in place instead of
    // building them again.
    Repeater {
      model: factGrid.facts.length

      InfoPair {
        required property int index
        readonly property var fact: factGrid.facts[index] || ({ label: "", value: "" })
        width: factGrid.cellWidth
        label: fact.label
        value: fact.value
        delay: factGrid.delay + index * 40
      }
    }
  }

  // An open room's switches for what of it the bar shows: the same picks as
  // the settings page, here where the reading is. A row of its own rather
  // than the kit's SwitchRow, whose label is cut short in a half-width room:
  // this one wraps.
  component RoomPicks: Column {
    id: picks
    property string room: ""
    readonly property var list: dash.host.barOptions.filter(function(o) { return o.room === picks.room })

    visible: list.length > 0
    width: parent ? parent.width : 0
    spacing: Style.space(6)

    Repeater {
      model: picks.list

      Item {
        id: pick
        required property var modelData
        readonly property bool on: dash.host.setting(modelData.key, modelData.fallback) === true
        width: picks.width
        implicitHeight: Math.max(pickLabel.implicitHeight, pickSwitch.implicitHeight)

        Text {
          id: pickLabel
          anchors.left: parent.left
          anchors.right: pickSwitch.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: pick.modelData.inRoom
          color: dash.host.fg
          font.family: dash.host.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // The label switches too, as the kit's rows do.
        MouseArea {
          anchors.fill: pickLabel
          cursorShape: Qt.PointingHandCursor
          onClicked: dash.host.setOption(pick.modelData.key, !pick.on)
        }

        ToggleSwitch {
          id: pickSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: pick.on
          foreground: dash.host.fg
          accent: dash.host.accent
          onToggled: dash.host.setOption(pick.modelData.key, !pick.on)
        }
      }
    }
  }

  // One of the System room's cells: what it is, its figure in the block face
  // over a small meter, and a line of state. Hot, it takes the alert tone and
  // the alert mark beside its figure.
  component PartCell: Column {
    id: cell
    property var part: null
    property color tone: dash.host.fg
    property int delay: 0
    readonly property alias meter: cellMeter
    readonly property color shade: part && part.hot ? dash.host.lowTone : tone
    readonly property bool known: !!part && Model.hasLevel(part.level)

    spacing: Style.space(6)

    Row {
      spacing: Style.space(5)

      PixelIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: cell.part ? cell.part.icon : ""
        size: Style.font.bodySmall
        color: cell.shade
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: cell.part ? cell.part.label : ""
        color: dash.host.fg
        font.family: dash.host.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    // Counts up with its meter: the figure is the value scaled by how far
    // the meter has come, which for a share is the meter itself.
    BigFigure {
      value: cell.known ? cell.part.value * (cellMeter.level > 0 ? Math.min(1, cellMeter.shown / cellMeter.level) : 1) : null
      tone: cell.shade
      foreground: dash.host.fg
      mark: cell.part && cell.part.hot ? "warning-diamond" : ""
      suffix: cell.part ? cell.part.suffix : "%"
      fontSize: Style.font.caption
      maxWidth: cell.width
    }

    Meter {
      id: cellMeter
      host: dash.host
      width: parent.width
      small: true
      segments: 5
      level: cell.known ? cell.part.level : 0
      known: cell.known
      tone: cell.shade
      foreground: dash.host.fg
      delay: cell.delay
    }

    Decode {
      host: dash.host
      width: parent.width
      wrapMode: Text.Wrap
      value: cell.part ? cell.part.state : ""
      delay: cell.delay + 80
      color: cell.part && cell.part.hot ? dash.host.lowTone : dash.host.dim
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A disk in the open Disk tile's drawer: its name, a meter with the alert
  // line in it, and how full it is in the pixel type. The alert mark has a
  // column of its own either way, so nothing moves when it appears.
  component DiskRow: Item {
    id: diskRow
    property var disk: null
    property color tone: dash.host.fg
    property int delay: 0
    readonly property alias meter: rowMeter
    readonly property color shade: disk && disk.hot ? dash.host.lowTone : tone

    implicitHeight: Math.max(diskName.implicitHeight, rowMeter.implicitHeight)

    Text {
      id: diskName
      width: Math.round(diskRow.width * 0.34)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: diskRow.disk ? diskRow.disk.name : ""
      color: dash.host.fg
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Meter {
      id: rowMeter
      host: dash.host
      anchors.left: diskName.right
      anchors.leftMargin: Style.space(8)
      anchors.right: markSlot.left
      anchors.rightMargin: Style.space(5)
      anchors.verticalCenter: parent.verticalCenter
      small: true
      level: diskRow.disk ? diskRow.disk.level : 0
      marker: Model.DISK_ALERT
      tone: diskRow.shade
      foreground: dash.host.fg
      delay: diskRow.delay
    }

    Item {
      id: markSlot
      anchors.right: figureSlot.left
      anchors.rightMargin: Style.space(5)
      anchors.verticalCenter: parent.verticalCenter
      width: markIcon.implicitWidth
      height: markIcon.implicitHeight

      PixelIcon {
        id: markIcon
        visible: !!diskRow.disk && diskRow.disk.hot
        name: "warning-diamond"
        size: Style.font.bodySmall
        color: dash.host.lowTone
      }
    }

    Item {
      id: figureSlot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Model.pixelText("100%").width * figure.cell
      height: figure.implicitHeight

      PixelText {
        id: figure
        anchors.right: parent.right
        text: Model.percentText(rowMeter.shown)
        size: Style.font.caption * 0.8
        color: dash.host.fg
      }
    }
  }

  // A tile's first line: its pixel icon and name. Smaller than a room's
  // header, since a tile is a quarter of the panel wide, and without the
  // chevron: beside it "Network" broke in two. An open tile stays tinted,
  // as its drawer under the row is. The icon acts itself out all the same.
  component TileHeader: Item {
    id: tileHead
    property string icon: ""
    property string title: ""
    property color tone: dash.host.fg
    property string story: "pop"
    property int tick: 0
    property real k: 1
    readonly property var pose: Model.storyPose(story, k)

    width: parent ? parent.width : 0
    implicitHeight: Math.max(tileIcon.height, tileTitle.implicitHeight)

    onTickChanged: if (!Style.reduceMotion) tileStory.restart()

    NumberAnimation {
      id: tileStory
      target: tileHead
      property: "k"
      from: 0
      to: 1
      duration: Style.duration(tileHead.story === "buzz" ? 520 : 660)
    }

    PixelIcon {
      id: tileIcon
      y: Math.round((tileHead.height - height) / 2)
      name: tileHead.icon
      size: Style.font.bodySmall
      color: tileHead.tone
      transform: Translate { x: tileHead.pose.x * tileIcon.cell; y: tileHead.pose.y * tileIcon.cell }
    }

    Text {
      id: tileTitle
      anchors.left: tileIcon.right
      anchors.leftMargin: Style.space(4)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: tileHead.title
      color: dash.host.fg
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  // A container on one line: whether it runs, its name and how long it has
  // been up. With the cursor on it the status gives way to stop or start
  // and restart. Stopped ones dim; unhealthy ones take the alert tone.
  component ContainerRow: Rectangle {
    id: row
    property var container: null
    property string rowKey: ""
    readonly property bool running: Model.containerRunning(container)
    readonly property bool sick: Model.containerTrouble(container)
    readonly property bool lit: dash.host.cursorActive && dash.host.cursorKey === rowKey
    readonly property bool busy: !!container && dash.host.busyAction.indexOf("docker-") === 0
      && dash.host.busyAction.indexOf(":" + container.name) !== -1
    readonly property color ink: sick ? dash.host.lowTone : running ? dash.host.fg : dash.host.dim

    implicitHeight: Math.max(rowName.implicitHeight, statusBox.height, buttons.implicitHeight) + Style.space(6)
    radius: Style.cornerRadius
    color: lit ? Qt.rgba(dash.host.fg.r, dash.host.fg.g, dash.host.fg.b, 0.06) : "transparent"
    onLitChanged: if (lit && dash.host.keyboardCursor) dash.host.scrollIntoView(row)

    // Takes the row's clicks, so a click between the buttons leaves the room
    // open, and says what the pointer is on.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: containsMouse ? dash.host.hover(row.rowKey) : dash.host.unhover(row.rowKey)
    }

    PixelIcon {
      id: rowIcon
      x: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      name: Model.containerPixel(row.container)
      size: Style.font.bodySmall
      color: row.sick ? dash.host.lowTone : row.running ? dash.toneFor("containers") : dash.host.dim
    }

    Text {
      id: rowName
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4) + dash.host.iconColumn * 0.75
      anchors.right: statusBox.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: row.container ? row.container.name : ""
      color: row.ink
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      id: statusBox
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      // At least the buttons' room, so swapping to them never moves the name.
      width: Math.max(buttons.implicitWidth, Math.min(rowStatus.implicitWidth, Style.space(140)))
      height: rowStatus.implicitHeight

      Text {
        id: rowStatus
        width: parent.width
        visible: !buttons.visible
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: row.busy ? "Working…" : Model.containerStatus(row.container)
        color: row.sick ? dash.host.lowTone : dash.host.dim
        font.family: dash.host.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      visible: row.lit && !row.busy

      PixelButton {
        icon: row.running ? "stop" : "play"
        tooltipText: row.running ? "Stop (s)" : "Start (s)"
        foreground: dash.host.fg
        hoverColor: row.running ? dash.host.lowTone : dash.host.fg
        fontFamily: dash.host.fontFamily
        enabled: dash.host.busyAction === ""
        onClicked: dash.host.toggleContainer(row.container)
      }

      PixelButton {
        visible: row.running
        icon: "reload"
        tooltipText: "Restart (enter)"
        foreground: dash.host.fg
        fontFamily: dash.host.fontFamily
        enabled: dash.host.busyAction === ""
        onClicked: dash.host.restartContainer(row.container)
      }
    }
  }

  // A failed systemd unit: its name over its description, restart on the
  // right.
  component UnitRow: Rectangle {
    id: unitRow
    property var unit: null
    property string rowKey: ""
    readonly property bool lit: dash.host.cursorActive && dash.host.cursorKey === rowKey
    readonly property bool busy: !!unit && dash.host.busyAction === "unit-restart:" + unit.name

    implicitHeight: Math.max(unitText.implicitHeight, restart.implicitHeight) + Style.space(6)
    radius: Style.cornerRadius
    color: lit ? Qt.rgba(dash.host.fg.r, dash.host.fg.g, dash.host.fg.b, 0.06) : "transparent"
    onLitChanged: if (lit && dash.host.keyboardCursor) dash.host.scrollIntoView(unitRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: containsMouse ? dash.host.hover(unitRow.rowKey) : dash.host.unhover(unitRow.rowKey)
    }

    Column {
      id: unitText
      anchors.left: parent.left
      anchors.leftMargin: dash.host.textInset
      anchors.right: restart.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: unitRow.unit ? unitRow.unit.name : ""
        color: dash.host.fg
        font.family: dash.host.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        visible: text !== ""
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: unitRow.busy ? "Restarting…" : (unitRow.unit ? unitRow.unit.description : "")
        color: dash.host.dim
        font.family: dash.host.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    PixelButton {
      id: restart
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter
      icon: "reload"
      tooltipText: "Restart (uses sudo)"
      foreground: dash.host.fg
      fontFamily: dash.host.fontFamily
      enabled: !unitRow.busy && dash.host.busyAction === ""
      onClicked: dash.host.restartUnit(unitRow.unit)
    }
  }

  // A process: its name, its share of the processor and its memory.
  component ProcessRow: Item {
    id: proc
    property var process: null

    implicitHeight: Math.max(procName.implicitHeight, procCpu.implicitHeight)

    Text {
      id: procName
      width: procCpu.x - Style.space(10)
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: proc.process ? proc.process.name : ""
      color: dash.host.fg
      opacity: 0.6
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: procCpu
      anchors.right: procMem.left
      width: Style.space(56)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: proc.process ? proc.process.cpu.toFixed(1) + "%" : ""
      color: proc.process && proc.process.cpu >= 80 ? dash.host.lowTone : dash.host.fg
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: procMem
      anchors.right: parent.right
      width: Style.space(72)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: proc.process ? Model.size(proc.process.rssBytes) : ""
      color: dash.host.fg
      font.family: dash.host.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // ------------------------------------------------------- failed services

  // Holds still: no chevron, nothing to open. Each service restarts from its
  // own row.
  Room {
    id: failedRoom
    visible: dash.host.failedUnits.length > 0
    host: dash.host
    tone: dash.host.lowTone
    clickable: false
    delay: dash.delayOf("failed")
    spacing: Style.space(4)

    RoomHeader {
      host: dash.host
      icon: Model.roomPixel("failed")
      tone: failedRoom.tone
      title: "Failed services"
      status: dash.host.failedUnits.length + " failed, restarting asks sudo"
      value: dash.host.failedUnits.length
      suffix: ""
      showChevron: false
      story: Model.storyOf("failed")
      tick: failedRoom.story
      delay: failedRoom.delay + 120
    }

    Repeater {
      model: dash.host.failedUnits.length

      UnitRow {
        required property int index
        width: parent ? parent.width : 0
        unit: dash.host.failedUnits[index] || null
        rowKey: "u:" + index
      }
    }
  }

  // ---------------------------------------------------------------- system

  Room {
    id: systemRoom
    host: dash.host
    tone: dash.toneFor("system")
    expanded: dash.host.openRoom === "system"
    keyed: dash.keyed("system")
    delay: dash.delayOf("system")
    cells: [cpuCell.meter, memoryCell.meter, tempCell.meter]
    onClicked: dash.host.toggleRoom("system")
    onHoveredChanged: dash.track(systemRoom, "system")
    onKeyedChanged: if (keyed) dash.host.scrollIntoView(systemRoom)

    RoomHeader {
      host: dash.host
      icon: Model.roomPixel("system")
      tone: systemRoom.tone
      title: "System"
      status: Model.systemStatus(dash.snap)
      showFigure: false
      expanded: systemRoom.expanded
      story: Model.storyOf("system")
      tick: systemRoom.story
      delay: systemRoom.delay + 120
    }

    Row {
      id: cellRow
      width: parent.width
      spacing: Style.space(12)
      readonly property real cellWidth: (width - spacing * (Math.max(1, dash.cells.length) - 1)) / Math.max(1, dash.cells.length)

      PartCell { id: cpuCell; width: cellRow.cellWidth; part: dash.cells[0] || null; tone: systemRoom.tone; delay: systemRoom.delay + 80 }
      PartCell { id: memoryCell; visible: dash.cells.length > 1; width: cellRow.cellWidth; part: dash.cells[1] || null; tone: systemRoom.tone; delay: systemRoom.delay + 130 }
      PartCell { id: tempCell; visible: dash.cells.length > 2; width: cellRow.cellWidth; part: dash.cells[2] || null; tone: systemRoom.tone; delay: systemRoom.delay + 180 }
    }

    Drawer {
      open: systemRoom.expanded

      Facts { facts: Model.machineFacts(dash.snap) }
      Facts { facts: Model.systemFacts(dash.snap); columns: 1 }
      RoomPicks { room: "system" }
    }
  }

  // ------------------------------------------------ disk, network, containers

  // One row of small rooms: the Disk and the Network as square tiles a
  // quarter of the panel wide, the same size as the actions at the bottom,
  // and the Containers in the half that is left. All three have the same
  // shape: a name, a figure, and a meter or a second line under it. A tile
  // has no room for its details, so opening one slides them open full width
  // under the row, in its tone.
  Row {
    id: tiles
    readonly property real quarter: (width - spacing * 3) / 4
    readonly property real tileHeight: Math.max(disksRoom.visible ? disksRoom.implicitHeight : 0,
      networkRoom.implicitHeight, containersRoom.visible ? containersRoom.implicitHeight : 0)
    width: parent.width
    spacing: dash.host.roomGap

    Room {
      id: disksRoom
      visible: !!dash.rootDisk
      width: tiles.quarter
      height: tiles.tileHeight
      host: dash.host
      pad: Style.space(8)
      spacing: Style.space(5)
      tone: dash.diskList.some(function(d) { return d.hot }) ? dash.host.lowTone : dash.toneFor("disks")
      expanded: dash.host.openRoom === "disks"
      keyed: dash.keyed("disks")
      delay: dash.delayOf("disks")
      cells: [rootMeter]
      onClicked: dash.host.toggleRoom("disks")
      onHoveredChanged: dash.track(disksRoom, "disks")
      onKeyedChanged: if (keyed) dash.host.scrollIntoView(disksRoom)

      TileHeader {
        icon: Model.roomPixel("disks")
        title: dash.diskList.length > 1 ? "Disks" : "Disk"
        tone: disksRoom.tone
        story: Model.storyOf("disks")
        tick: disksRoom.story
      }

      // The root disk; the others are in the drawer, and a full one marks
      // the tile.
      BigFigure {
        value: dash.rootDisk ? rootMeter.shown : null
        tone: disksRoom.tone
        foreground: dash.host.fg
        mark: dash.diskList.some(function(d) { return d.hot }) ? "warning-diamond" : ""
        fontSize: Style.font.caption
        maxWidth: parent.width
      }

      Meter {
        id: rootMeter
        host: dash.host
        width: parent.width
        small: true
        segments: 5
        level: dash.rootDisk ? dash.rootDisk.level : 0
        marker: Model.DISK_ALERT
        tone: disksRoom.tone
        foreground: dash.host.fg
        delay: disksRoom.delay + 80
      }
    }

    Room {
      id: networkRoom
      width: tiles.quarter
      height: tiles.tileHeight
      host: dash.host
      pad: Style.space(8)
      spacing: Style.space(5)
      tone: dash.toneFor("network")
      expanded: dash.host.openRoom === "network"
      keyed: dash.keyed("network")
      delay: dash.delayOf("network")
      onClicked: dash.host.toggleRoom("network")
      onHoveredChanged: dash.track(networkRoom, "network")
      onKeyedChanged: if (keyed) dash.host.scrollIntoView(networkRoom)

      readonly property var rates: Model.networkRates(dash.snap)

      // The rates count up with the rooms, in the unit they end in.
      property real k: 1
      Connections {
        target: dash.host
        function onEntryChanged() {
          rateIn.stop()
          if (Style.reduceMotion) { networkRoom.k = 1; return }
          networkRoom.k = 0
          rateIn.start()
        }
      }
      SequentialAnimation {
        id: rateIn
        PauseAnimation { duration: Style.duration(networkRoom.delay + 80) }
        NumberAnimation { target: networkRoom; property: "k"; to: 1; duration: Style.duration(680); easing.type: Easing.OutCubic }
      }

      TileHeader {
        icon: Model.roomPixel("network")
        title: "Network"
        tone: networkRoom.tone
        story: Model.storyOf("network")
        tick: networkRoom.story
      }

      // Download over upload: which way, then how much a second, in the
      // pixel type, small, as Sonus writes an app's volume.
      Column {
        width: parent.width
        spacing: Style.space(5)
        topPadding: Style.space(2)

        Repeater {
          model: networkRoom.rates.length

          Row {
            required property int index
            readonly property var modelData: networkRoom.rates[index]
            spacing: Style.space(4)

            PixelIcon {
              anchors.verticalCenter: parent.verticalCenter
              name: modelData.icon
              size: Style.font.bodySmall
              color: networkRoom.tone
            }

            PixelText {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.parts ? Model.rateText(modelData.parts, networkRoom.k) + modelData.parts.unit : "--"
              size: Style.font.caption
              color: modelData.parts ? dash.host.fg : dash.host.dim
            }
          }
        }
      }
    }

    Room {
      id: containersRoom
      visible: dash.host.containers.length > 0
      width: tiles.width - (tiles.quarter + tiles.spacing) * ((disksRoom.visible ? 1 : 0) + 1)
      height: tiles.tileHeight
      host: dash.host
      pad: Style.space(8)
      spacing: Style.space(5)
      tone: dash.toneFor("containers")
      expanded: dash.host.openRoom === "containers"
      keyed: dash.keyed("containers")
      delay: dash.delayOf("containers")
      cells: [runMeter]
      onClicked: dash.host.toggleRoom("containers")
      onHoveredChanged: dash.track(containersRoom, "containers")
      onKeyedChanged: if (keyed) dash.host.scrollIntoView(containersRoom)

      readonly property color shade: dash.counts.trouble > 0 ? dash.host.lowTone : tone

      TileHeader {
        icon: Model.roomPixel("containers")
        title: "Containers"
        tone: containersRoom.shade
        story: Model.storyOf("containers")
        tick: containersRoom.story
      }

      // How many run, counting up with the meter of running ones, and what
      // most needs saying beside it.
      Row {
        width: parent.width
        spacing: Style.space(8)

        BigFigure {
          id: countFigure
          value: dash.counts.total > 0 ? Math.round(runMeter.shown / 100 * dash.counts.total) : null
          suffix: ""
          tone: containersRoom.shade
          foreground: dash.host.fg
          mark: dash.counts.trouble > 0 ? "warning-diamond" : ""
          fontSize: Style.font.caption
          maxWidth: parent.width / 2
        }

        Column {
          anchors.verticalCenter: countFigure.verticalCenter
          width: parent.width - countFigure.width - parent.spacing
          spacing: Style.space(1)

          Repeater {
            id: noteLines
            readonly property var lines: Model.containerNote(dash.host.containers)
            model: lines.length

            Decode {
              required property int index
              host: dash.host
              width: parent.width
              wrapMode: Text.Wrap
              value: noteLines.lines[index] || ""
              delay: containersRoom.delay + 120 + index * 40
              color: index > 0 && dash.counts.trouble > 0 ? dash.host.lowTone : dash.host.dim
              font.family: dash.host.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Meter {
        id: runMeter
        host: dash.host
        width: parent.width
        small: true
        level: dash.counts.total > 0 ? dash.counts.running / dash.counts.total * 100 : 0
        tone: containersRoom.shade
        foreground: dash.host.fg
        delay: containersRoom.delay + 80
      }
    }
  }

  // What the open tile holds, full width under the row. It keeps showing the
  // tile it opened for while it closes, so it slides shut rather than
  // emptying first; its gap above is part of its height for the same reason.
  Item {
    id: tileDrawer
    readonly property string open: ["disks", "network", "containers"].indexOf(dash.host.openRoom) !== -1 ? dash.host.openRoom : ""
    property string shown: ""
    onOpenChanged: if (open !== "") shown = open

    width: parent.width
    height: open !== "" ? drawerRoom.implicitHeight + dash.host.roomGap : 0
    visible: height > 0.5
    clip: true
    opacity: open !== "" ? 1 : 0

    Behavior on height { NumberAnimation { duration: Style.duration(tileDrawer.open !== "" ? 280 : 200); easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Style.duration(tileDrawer.open !== "" ? 220 : 160); easing.type: Easing.OutCubic } }

    Room {
      id: drawerRoom
      y: dash.host.roomGap
      width: parent.width
      host: dash.host
      clickable: false
      expanded: true
      tone: tileDrawer.shown === "disks" ? disksRoom.tone
        : tileDrawer.shown === "containers" ? containersRoom.shade : dash.toneFor("network")

      // ---- disks: every one with its meter, where each lives, the switch
      Column {
        visible: tileDrawer.shown === "disks"
        width: parent.width
        spacing: Style.space(8)

        Repeater {
          model: dash.diskList.length

          DiskRow {
            required property int index
            width: parent ? parent.width : 0
            disk: dash.diskList[index] || null
            tone: dash.toneFor("disks")
          }
        }

        Facts {
          columns: 2
          facts: dash.rootDisk ? [{ label: "Used", value: dash.rootDisk.used }, { label: "Free", value: dash.rootDisk.free }] : []
        }

        Facts { facts: Model.diskFacts(dash.snap); columns: 1 }
        RoomPicks { room: "disks" }
      }

      // ---- network: what went each way since boot, the switch
      Column {
        visible: tileDrawer.shown === "network"
        width: parent.width
        spacing: Style.space(8)

        Facts { facts: Model.networkFacts(dash.snap).slice(0, 2) }
        Facts { facts: Model.networkFacts(dash.snap).slice(2); columns: 1 }
        RoomPicks { room: "network" }
      }

      // ---- containers: every one, with stop, start and restart
      Column {
        visible: tileDrawer.shown === "containers"
        width: parent.width
        spacing: Style.space(1)

        Facts { facts: Model.containerFacts(dash.host.containers) }

        Item { width: 1; height: Style.space(4) }

        // Over the count: the list comes new from every poll, and building
        // 33 rows again every few seconds reset the pointer's row.
        Repeater {
          model: dash.host.containers.length

          ContainerRow {
            required property int index
            width: parent ? parent.width : 0
            container: dash.host.containers[index] || null
            rowKey: "c:" + index
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- processes

  Room {
    id: processesRoom
    visible: dash.host.processes.length > 0
    host: dash.host
    tone: dash.toneFor("processes")
    expanded: dash.host.openRoom === "processes"
    keyed: dash.keyed("processes")
    delay: dash.delayOf("processes")
    onClicked: dash.host.toggleRoom("processes")
    onHoveredChanged: dash.track(processesRoom, "processes")
    onKeyedChanged: if (keyed) dash.host.scrollIntoView(processesRoom)

    RoomHeader {
      host: dash.host
      icon: Model.roomPixel("processes")
      tone: processesRoom.tone
      title: "Processes"
      status: Model.processesStatus(dash.snap)
      showFigure: false
      expanded: processesRoom.expanded
      story: Model.storyOf("processes")
      tick: processesRoom.story
      delay: processesRoom.delay + 120
    }

    Column {
      width: parent.width
      spacing: Style.spacing.labelGap

      Repeater {
        model: Math.min(3, dash.host.processes.length)

        ProcessRow {
          required property int index
          width: parent ? parent.width : 0
          process: dash.host.processes[index] || null
        }
      }
    }

    Drawer {
      open: processesRoom.expanded
      spacing: Style.spacing.labelGap

      Repeater {
        model: Math.max(0, dash.host.processes.length - 3)

        ProcessRow {
          required property int index
          width: parent ? parent.width : 0
          process: dash.host.processes[index + 3] || null
        }
      }
    }
  }
}
