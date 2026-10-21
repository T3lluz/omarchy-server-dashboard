import QtQuick
import qs.Commons
import qs.Commons as Commons

// Dial gauge: a 270° track with tick marks, filled up to `percent`. Colors
// come from the theme, so the arc follows the accent and turns urgent when hot.
Item {
  id: root

  property real percent: -1
  property string label: ""
  property string valueText: percent >= 0 ? Math.round(percent) + "%" : "—"
  property string subText: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property int heat: 0
  property string fontFamily: Style.font.family
  property real stroke: Math.max(3, Style.space(5))

  readonly property color arcColor: heat >= 2 ? urgent : (heat === 1 ? Qt.tint(accent, Util.alpha(urgent, 0.45)) : accent)
  readonly property color dim: Qt.darker(foreground, 1.55)
  property real animated: Math.max(0, percent)

  implicitWidth: Style.space(78)
  implicitHeight: Style.space(78)

  Behavior on animated {
    NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
  }

  onAnimatedChanged: dial.requestPaint()
  onArcColorChanged: dial.requestPaint()
  onForegroundChanged: dial.requestPaint()
  onWidthChanged: dial.requestPaint()
  onHeightChanged: dial.requestPaint()

  Canvas {
    id: dial
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2
      var cy = height / 2
      var r = Math.min(width, height) / 2 - root.stroke - Style.space(4)
      var start = Math.PI * 0.75
      var sweep = Math.PI * 1.5
      var p = root.percent >= 0 ? Math.max(0, Math.min(1, root.animated / 100)) : 0

      var ticks = 30
      for (var t = 0; t <= ticks; t++) {
        var frac = t / ticks
        var a = start + sweep * frac
        var major = t % 5 === 0
        var outer = r + root.stroke / 2 + Style.space(4)
        var inner = outer - (major ? Style.space(3) : Style.space(1.5))
        ctx.beginPath()
        ctx.lineWidth = 1
        ctx.strokeStyle = (p > 0 && frac <= p + 0.0001)
          ? Util.alpha(root.arcColor, major ? 0.9 : 0.55)
          : Util.alpha(root.foreground, major ? 0.22 : 0.1)
        ctx.moveTo(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner)
        ctx.lineTo(cx + Math.cos(a) * outer, cy + Math.sin(a) * outer)
        ctx.stroke()
      }

      ctx.lineWidth = root.stroke
      ctx.lineCap = Style.cornerRadius > 0 ? "round" : "butt"
      ctx.strokeStyle = Util.alpha(root.foreground, 0.1)
      ctx.beginPath()
      ctx.arc(cx, cy, r, start, start + sweep)
      ctx.stroke()

      if (p > 0) {
        ctx.strokeStyle = root.arcColor
        ctx.beginPath()
        ctx.arc(cx, cy, r, start, start + sweep * p)
        ctx.stroke()
      }
    }
  }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: Style.space(2)
    width: parent.width - root.stroke * 2 - Style.space(14)
    spacing: 0

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.valueText
      color: root.heat >= 2 ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      fontSizeMode: Text.HorizontalFit
      minimumPixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: parent.width
    visible: root.subText !== ""
    textFormat: Text.PlainText
    text: root.subText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
  }
}
