import QtQuick
import QtQuick.Window
import qs.Commons
import "Model.js" as Model

// A level drawn as Batteries draws a battery: an outlined body split into
// cells (Model.meterCells), each filled to the full height of the body, a
// tenth of the level each. It fills in from empty when the panel opens and
// slides to a new level after that. The pointer presses the cells under it
// down a little, and `press` sends a ripple out from a point, as Weave's pad
// does. Sonus's meter, without the fader.
Item {
  id: meter

  required property var host
  // 0..100.
  property real level: 0
  property bool known: true
  property int segments: 10
  property color tone: "white"
  property color foreground: "white"
  // A limit (where the disk alerts start), drawn as a tick through the body.
  property real marker: 0
  // How long after the panel opens this one starts filling, in ms, so the
  // panel fills from the top down.
  property int delay: 0
  // Small meters (a cell's, a disk row's) draw a thinner body.
  property bool small: false

  // What is drawn: the level while it fills in, else the level.
  property real shown: 0
  property var dent: null
  property var ripples: []

  // Laid out in whole device pixels, as Sonus's spectrum is: at 1.25 a
  // fractional cell width rounded its one-pixel gaps away, and the ten cells
  // of the Containers meter read as three bars. The outline, the inset and
  // the gaps are whole device pixels; the cells share what is left, the odd
  // pixels spread across them.
  // The window's ratio, not Screen's: on a 1.25 monitor Screen.devicePixelRatio says 2.
  readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
  readonly property int linePx: Math.max(1, Math.round(Style.space(1) * dpr))
  readonly property int insetPx: small ? Math.max(1, Math.round(Style.space(1) * dpr)) : Math.max(2, Math.round(Style.space(2) * dpr))
  readonly property int gapPx: small ? Math.max(1, Math.round(Style.space(1) * dpr)) : Math.max(2, Math.round(Style.space(2) * dpr))
  readonly property int bodyPx: Math.max(0, Math.floor(width * dpr))
  readonly property int innerPx: Math.max(0, bodyPx - 2 * (linePx + insetPx))
  readonly property int cellPx: Math.max(1, Math.floor((innerPx - gapPx * (segments - 1)) / Math.max(1, segments)))
  readonly property int spare: Math.max(0, innerPx - gapPx * (segments - 1) - cellPx * segments)
  readonly property real line: linePx / dpr
  function cellX(i) { return (i * (cellPx + gapPx) + Math.floor(i * spare / segments)) / dpr }
  function cellW(i) { return (cellPx + Math.floor((i + 1) * spare / segments) - Math.floor(i * spare / segments)) / dpr }

  implicitHeight: small ? Style.space(11) : Style.space(18)

  readonly property var cells: Model.meterCells({
    segments: segments,
    level: known ? shown : 0,
    dent: dent,
    ripples: ripples.map(function(r) { return { x: r.x, age: meter.host.clock - r.at } })
  })

  // Old ripples go once they have run out.
  Connections {
    target: meter.host
    enabled: meter.ripples.length > 0
    function onClockChanged() {
      var left = meter.ripples.filter(function(r) { return meter.host.clock - r.at < Model.METER.RIPPLE_MS })
      if (left.length !== meter.ripples.length) meter.ripples = left
    }
  }

  Connections {
    target: meter.host
    function onEntryChanged() { meter.enter() }
  }

  function enter() {
    fillIn.stop()
    settle.stop()
    if (Style.reduceMotion || !known) { shown = known ? level : 0; return }
    shown = 0
    fillIn.start()
  }

  // A point in the meter's own coordinates. Only near the body presses.
  function hover(x, y) {
    if (x < 0 || x > body.width || y < -height * 0.6 || y > height * 1.6) { dent = null; return }
    dent = x / body.width
  }

  function press(x, y) {
    if (Style.reduceMotion) return
    var next = ripples.slice(-3)
    next.push({ x: Math.max(0, Math.min(1, x / body.width)), at: host.clock })
    ripples = next
  }

  Component.onCompleted: {
    shown = known ? level : 0
    // Once laid out too, for a window that has not drawn a frame yet.
    Qt.callLater(meter.snap)
  }

  // Slides to the level as it is now. `to` is set here rather than bound:
  // this runs from onLevelChanged, which can come before a binding on `to`
  // has updated, so every meter drew the poll before. Sonus's slide.
  function slide() {
    settle.stop()
    settle.to = level
    settle.start()
  }

  onLevelChanged: {
    if (fillIn.running) return
    if (Style.reduceMotion || !host.opened) { shown = level; return }
    slide()
  }
  onKnownChanged: if (!fillIn.running) shown = known ? level : 0

  SequentialAnimation {
    id: fillIn
    PauseAnimation { duration: Style.duration(meter.delay) }
    NumberAnimation { target: meter; property: "shown"; to: meter.level; duration: Style.duration(680); easing.type: Easing.OutCubic }
    // The level may have moved on while it filled in.
    ScriptAction { script: if (meter.shown !== meter.level) meter.slide() }
  }

  NumberAnimation {
    id: settle
    target: meter
    property: "shown"
    duration: Style.duration(420)
    easing.type: Easing.OutCubic
  }

  // Whole device pixels in the window, as the icons do.
  property real snapX: 0
  property real snapY: 0

  function snap() {
    if (!visible) return
    var p = meter.mapToItem(null, 0, 0)
    var dx = Math.round(p.x * dpr) / dpr - p.x
    var dy = Math.round(p.y * dpr) / dpr - p.y
    if (Math.abs(dx - snapX) > 0.001) snapX = dx
    if (Math.abs(dy - snapY) > 0.001) snapY = dy
  }

  Connections {
    target: meter.Window.window
    ignoreUnknownSignals: true
    function onAfterAnimating() { meter.snap() }
  }


  Rectangle {
    id: body
    x: meter.snapX
    y: meter.snapY
    width: meter.bodyPx / meter.dpr
    height: Math.round(parent.height * meter.dpr) / meter.dpr
    color: "transparent"
    radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, 3) : 0
    border.width: meter.line
    border.color: Qt.rgba(meter.tone.r, meter.tone.g, meter.tone.b, meter.known ? 0.6 : 0.3)

    Item {
      id: cellRow
      x: (meter.linePx + meter.insetPx) / meter.dpr
      y: x
      width: meter.innerPx / meter.dpr
      height: body.height - y * 2

      Repeater {
        model: meter.segments

        Item {
          id: cell
          required property int index
          readonly property var c: meter.cells[index] || ({ fill: 0, glow: 0, press: 0 })

          x: meter.cellX(index)
          width: meter.cellW(index)
          height: cellRow.height
          // A cell gives under the pointer, as Weave's tiles do.
          scale: 1 - cell.c.press * 0.14

          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(meter.tone.r, meter.tone.g, meter.tone.b, 0.12)
            antialiasing: false
          }

          Rectangle {
            width: Math.round(parent.width * cell.c.fill * meter.dpr) / meter.dpr
            height: parent.height
            color: meter.tone
            antialiasing: false
          }

          Rectangle {
            visible: cell.c.glow > 0.01
            anchors.fill: parent
            color: Qt.rgba(meter.foreground.r, meter.foreground.g, meter.foreground.b, cell.c.glow * 0.55)
            antialiasing: false
          }
        }
      }
    }
  }

  // The limit: a tick through the body, poking out above and below, as
  // Batteries marks a charge limit.
  Rectangle {
    visible: meter.marker > 0 && meter.marker < 100
    x: body.x + Math.round((cellRow.x + cellRow.width * meter.marker / 100 - width / 2) * meter.dpr) / meter.dpr
    readonly property real poke: Math.max(2, Math.round(Style.space(3) * meter.dpr)) / meter.dpr
    y: body.y - poke
    width: meter.line
    height: body.height + poke * 2
    color: meter.foreground
    opacity: 0.55
    antialiasing: false
  }
}
