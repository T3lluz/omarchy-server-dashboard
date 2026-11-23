import QtQuick
import QtQuick.Window
import qs.Commons
import "Pixels.js" as Pixels
import "Motion.js" as Motion

// A pixel icon from Pixels.js, drawn as rectangles on whole device pixels so
// it stays sharp at any scale. The icon comes out as close to `size` as the
// grid allows: the 24-unit grid where a unit gets whole device pixels, the
// same grid halved (12 cells) where it would not. On a 1.25 scale a 14 px
// request draws 12 device pixels; a 20 px one draws 24.
// Never scaled: a fractional scale only ever picks the nearest sharp size.
//
// It also acts itself out (Motion.js): `play` going up plays its motion
// once, `delay` ms later (and so does showing, with `playOnShow`), and
// `live` loops it while it holds, starting and stopping at the top of a
// round of the shared clock so it never jumps.
// Nothing moves with reduced motion, nor while its window is hidden.
Item {
  id: icon

  property string name: ""
  // Art drawn elsewhere ({ g12, g24 }, as Pixels.js keeps it), in place of a
  // named icon: the server mark, whose lights move.
  property var custom: null
  property real size: 16
  property color color: "white"
  // Device pixels per cell of the halved grid, to match other pixel art
  // (PixelText) stroke for stroke; 0 picks it from `size`.
  property int unit: 0
  property int play: 0
  property int delay: 0
  property bool live: false
  property bool playOnShow: false

  readonly property var art: custom || Pixels.icons[name] || null
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  // Device pixels across, in twelfths: odd counts take the halved grid. Its
  // strokes are this many device pixels thick either way.
  readonly property int twelfths: unit > 0 ? unit : Math.max(1, Math.round(size * dpr / 12))
  readonly property bool fine: twelfths % 2 === 0
  readonly property real cell: (fine ? twelfths / 2 : twelfths) / dpr

  readonly property bool moves: !custom && !Style.reduceMotion && Motion.motionOf(name) !== null
  readonly property bool shown: visible && Window.window !== null && Window.window.visible
  // What it is doing: "rest", "play" or "loop", and how far in, in ms.
  property string kind: "rest"
  property real at: 0
  // When the next play starts (ms since the epoch), 0 for none.
  property real playAt: 0
  property bool looping: false
  property real lastPhase: 0
  // The frame as drawn. Set only when it changes: poses hold for 60 ms or
  // more, and the ticks in between leave the rectangles alone.
  property var rects: []
  property string drawn: ""
  function redraw() {
    var next = Motion.frame(name, art, fine, kind, at)
    var key = JSON.stringify(next)
    if (key === drawn) return
    drawn = key
    rects = next
  }
  onArtChanged: redraw()
  onFineChanged: redraw()
  onKindChanged: redraw()
  onAtChanged: redraw()

  implicitWidth: twelfths * 12 / dpr
  implicitHeight: implicitWidth

  onPlayChanged: start()
  onLiveChanged: if (live) wake()
  onShownChanged: {
    if (shown && playOnShow) start()
    if (shown && live) wake()
  }
  Component.onCompleted: {
    redraw()
    if (shown && playOnShow) start()
  }

  function start() {
    if (!moves || Motion.playMs(name) <= 0) return
    playAt = Date.now() + Style.duration(delay)
    wake()
  }
  onNameChanged: { kind = "rest"; at = 0; looping = false }

  function wake() {
    if (moves && shown) ticker.start()
  }

  // One step of the motion: a play first, then the loop, else rest.
  function step() {
    var now = Date.now()
    if (!moves || !shown) { kind = "rest"; at = 0; playAt = 0; looping = false; ticker.stop(); return }
    if (playAt > 0 && now >= playAt) {
      var into = now - playAt
      if (into < Motion.playMs(name)) {
        kind = "play"
        at = into
        return
      }
      playAt = 0
    }
    var period = Motion.loopMs(name)
    if (period > 0 && (live || looping)) {
      var ph = Motion.phase(now, period)
      var wrapped = ph < lastPhase
      lastPhase = ph
      // A loop joins and leaves at the top of a round, where it is at rest.
      if (wrapped) looping = live
      if (looping) { kind = "loop"; at = ph; return }
      kind = "rest"
      at = 0
      return
    }
    kind = "rest"
    at = 0
    if (playAt === 0) ticker.stop()
  }

  Timer {
    id: ticker
    interval: Motion.TICK_MS
    repeat: true
    onTriggered: icon.step()
  }

  // Over a count, so a new frame updates the rectangles in place.
  Repeater {
    model: icon.rects.length

    Rectangle {
      required property int index
      readonly property var r: icon.rects[index] || [0, 0, 0, 0, 1]
      x: r[0] * icon.cell
      y: r[1] * icon.cell
      width: r[2] * icon.cell
      height: r[3] * icon.cell
      opacity: r[4]
      color: icon.color
      antialiasing: false
    }
  }
}
