import QtQuick
import qs.Commons
import qs.Commons as Commons

// History tile: label and current value over a filled line of recent samples.
// `maxValue` <= 0 scales to the largest sample, which suits network rates.
Item {
  id: root

  property var values: []
  property real maxValue: 100
  property string label: ""
  property string valueText: ""
  property string glyph: ""
  property color foreground: Commons.Color.foreground
  property color lineColor: Commons.Color.accent
  property string fontFamily: Style.font.family
  property int capacity: 60

  readonly property color dim: Qt.darker(foreground, 1.55)

  implicitHeight: header.implicitHeight + Style.space(4) + Style.space(34)

  onValuesChanged: chart.requestPaint()
  onLineColorChanged: chart.requestPaint()
  onWidthChanged: chart.requestPaint()

  Row {
    id: header
    width: parent.width
    spacing: Style.space(6)

    Text {
      id: glyphText
      visible: root.glyph !== ""
      textFormat: Text.PlainText
      text: root.glyph
      color: root.lineColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      textFormat: Text.PlainText
      text: root.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      width: parent.width - valueLabel.implicitWidth - (glyphText.visible ? glyphText.implicitWidth + parent.spacing : 0) - parent.spacing
      elide: Text.ElideRight
    }

    Text {
      id: valueLabel
      textFormat: Text.PlainText
      text: root.valueText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  Canvas {
    id: chart
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.topMargin: Style.space(4)
    anchors.bottom: parent.bottom
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      ctx.fillStyle = Util.alpha(root.foreground, 0.035)
      ctx.fillRect(0, 0, w, h)

      var v = root.values || []
      if (v.length < 2) return
      var max = root.maxValue
      if (!(max > 0)) {
        max = 1
        for (var m = 0; m < v.length; m++) max = Math.max(max, v[m])
        max *= 1.15
      }
      // Right-aligned so a fresh connection fills in from the newest sample.
      var step = w / Math.max(1, root.capacity - 1)
      var x0 = w - (v.length - 1) * step
      function yFor(value) { return h - 1 - Math.max(0, Math.min(1, value / max)) * (h - 3) }

      ctx.beginPath()
      ctx.moveTo(x0, h)
      for (var i = 0; i < v.length; i++) ctx.lineTo(x0 + i * step, yFor(v[i]))
      ctx.lineTo(w, h)
      ctx.closePath()
      var grad = ctx.createLinearGradient(0, 0, 0, h)
      grad.addColorStop(0, Util.alpha(root.lineColor, 0.32))
      grad.addColorStop(1, Util.alpha(root.lineColor, 0.02))
      ctx.fillStyle = grad
      ctx.fill()

      ctx.beginPath()
      for (var j = 0; j < v.length; j++) {
        var x = x0 + j * step
        var y = yFor(v[j])
        if (j === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.lineWidth = Math.max(1, Style.space(1.5))
      ctx.strokeStyle = root.lineColor
      ctx.stroke()
    }
  }
}
