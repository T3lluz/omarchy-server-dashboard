import QtQuick
import QtQuick.Window
import "Model.js" as Model

// A line in the pixel type (Model.pixelText): the panel's block digits, the
// % and the bar's units, drawn as rectangles on whole device pixels. `unit`
// is device pixels per cell, the same unit a PixelIcon beside it takes so
// their strokes match; 0 picks it from `size`, the height of a capital in
// logical pixels.
Item {
  id: line

  property string text: ""
  property color color: "white"
  property real size: 9
  property int unit: 0
  // The widest it may be, 0 for no limit: wider, it takes the largest whole
  // cell that fits, so it stays sharp and never runs out of its room. Lines
  // that should keep one size fit the same `fitText`, the widest of them.
  property real maxWidth: 0
  property string fitText: text
  readonly property int fitWidth: Model.pixelText(fitText).width

  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  readonly property int wanted: unit > 0 ? unit : Math.max(1, Math.round(size * dpr / 5))
  readonly property int px: maxWidth > 0 && fitWidth > 0
    ? Math.max(1, Math.min(wanted, Math.floor(maxWidth * dpr / fitWidth))) : wanted
  readonly property real cell: px / dpr
  readonly property var shape: Model.pixelText(text)

  implicitWidth: shape.width * cell
  implicitHeight: shape.height * cell

  Repeater {
    model: line.shape.rects

    Rectangle {
      required property var modelData
      x: modelData[0] * line.cell
      y: modelData[1] * line.cell
      width: modelData[2] * line.cell
      height: modelData[3] * line.cell
      color: line.color
      antialiasing: false
    }
  }
}
