import QtQuick
import qs.Commons
import "Model.js" as Model

// A room's figure in the block face (Model.bigDigits), with a small unit
// (%, °C, or none for a count) and the mark beside it, a pixel icon: the
// alert when it runs hot. The mark's column is there either way, so nothing
// moves when one appears. The blocks are laid out on the font's character
// grid but drawn as rectangles, since typed block characters leave hairline
// seams. `value` follows the room's meter while it fills in, so the number
// counts up with it.
Item {
  id: figure

  property var value: null
  // The figure as text instead, for one with a decimal point ("5.5"); "--"
  // reads as unknown.
  property string text: ""
  property color tone: "white"
  property color foreground: "white"
  property string mark: ""
  // What follows the figure, in the pixel type: "%", "\u00B0C", or "".
  property string suffix: "%"
  // A level that says nothing now reads quieter, as an unknown one does.
  property bool dimmed: false
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall
  // The widest it may be; 0 for no limit. A figure that would run past it
  // (a full disk's "100%" in a quarter-width tile) draws its blocks smaller
  // instead. The blocks are rectangles, so they stay sharp at any size.
  property real maxWidth: 0
  readonly property real markSize: Math.round(fontSize * 1.1)

  readonly property bool known: text !== "" ? text !== "--" : Model.hasLevel(value)
  readonly property var rows: Model.bigDigits(text !== "" ? text : known ? String(Math.round(value)) : "--")
  readonly property int cols: rows[0].length
  readonly property real baseCellW: grid.implicitWidth / 10
  readonly property real fit: maxWidth > 0 && cols > 0
    ? Math.min(1, (maxWidth - Style.space(3) - side.implicitWidth) / (cols * baseCellW)) : 1
  readonly property real cellW: baseCellW * fit
  readonly property real cellH: Math.round(metrics.height * 0.9 * fit)
  readonly property real digitsWidth: Math.round(cols * cellW)
  readonly property color faceColor: known && !dimmed ? tone : Qt.darker(foreground, 1.5)
  // Every block of every row, as [col, row, "full" | "top" | "bottom"].
  readonly property var blocks: {
    var out = []
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        var ch = rows[r].charAt(c)
        if (ch === "█") out.push([c, r, "full"])
        else if (ch === "▀") out.push([c, r, "top"])
        else if (ch === "▄") out.push([c, r, "bottom"])
      }
    }
    return out
  }

  implicitWidth: digitsWidth + Style.space(3) + side.implicitWidth
  // The face sits two and a half rows tall: nothing hangs below the bottom bar.
  implicitHeight: Math.round(cellH * 2.5)

  FontMetrics {
    id: metrics
    font.family: figure.fontFamily
    font.pixelSize: figure.fontSize
  }

  // The width of the font's own characters, measured as drawn.
  Text {
    id: grid
    visible: false
    text: "0000000000"
    font.family: figure.fontFamily
    font.pixelSize: figure.fontSize
  }

  Repeater {
    model: figure.blocks

    Rectangle {
      required property var modelData
      readonly property real from: modelData[1] * figure.cellH + (modelData[2] === "bottom" ? figure.cellH / 2 : 0)
      x: Math.round(modelData[0] * figure.cellW)
      y: Math.round(from)
      width: Math.round((modelData[0] + 1) * figure.cellW) - x
      height: Math.round(from + (modelData[2] === "full" ? figure.cellH : figure.cellH / 2)) - y
      color: figure.faceColor
      antialiasing: false
    }
  }

  // The mark over the %, in one column as wide as the wider of the two.
  Item {
    id: side
    x: figure.digitsWidth + Style.space(3)
    implicitWidth: Math.max(pct.implicitWidth, markIcon.implicitWidth)
    height: figure.implicitHeight

    PixelIcon {
      id: markIcon
      visible: figure.mark !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      name: figure.mark
      size: figure.markSize
      color: figure.dimmed ? Qt.darker(figure.foreground, 1.5) : figure.tone
    }

    PixelText {
      id: pct
      visible: figure.known && figure.suffix !== ""
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      text: figure.suffix
      size: Style.font.caption * 0.75
      color: Qt.darker(figure.foreground, 1.5)
    }
  }
}
