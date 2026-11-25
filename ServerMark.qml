import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// The Server Dashboard mark (Model.serverMark), after the app icon: two
// server units, each with a light and a label line. The outlines take
// `color`, the label lines `dimColor`, and each light is lit or dark. With
// `animated`, `play()` brings the lights up one unit after the other (the
// panel opening). While `working` (connecting, rebooting) they take turns,
// a beat each, the way a busy machine's lights do.
Item {
  id: mark

  property real size: 16
  // Device pixels per cell, as PixelIcon.unit; 0 picks it from `size`.
  property int unit: 0
  property color color: "white"
  property color dimColor: Qt.tint(color, Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.45))
  property color lightColor: color
  property bool animated: false
  property bool working: false

  property real k: 1
  property int beat: 0
  readonly property var lights: working && !Style.reduceMotion ? Model.workingLights(beat) : Model.markLights(k)

  implicitWidth: frame.implicitWidth
  implicitHeight: frame.implicitHeight

  function play() {
    if (!animated || Style.reduceMotion) return
    run.restart()
  }

  NumberAnimation {
    id: run
    target: mark
    property: "k"
    from: 0
    to: 1
    duration: Style.duration(620)
  }

  Timer {
    interval: 530
    repeat: true
    running: mark.working && mark.visible && !Style.reduceMotion
    onTriggered: mark.beat = (mark.beat + 1) % 2
  }

  PixelIcon {
    id: frame
    custom: Model.serverMark("frame")
    size: mark.size
    unit: mark.unit
    color: mark.color
  }

  PixelIcon {
    custom: Model.serverMark("lines")
    size: mark.size
    unit: mark.unit
    color: mark.dimColor
  }

  PixelIcon {
    custom: Model.serverMark("off", mark.lights)
    size: mark.size
    unit: mark.unit
    color: mark.dimColor
  }

  PixelIcon {
    custom: Model.serverMark("on", mark.lights)
    size: mark.size
    unit: mark.unit
    color: mark.lightColor
  }
}
