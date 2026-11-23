import QtQuick
import qs.Commons
import "Model.js" as Model

// The title room's content: the server mark, a bold title, and the prompt
// line under it, typed out a character at a time behind a cursor. The prompt
// keeps room for two lines, so one wrapping as it changes moves nothing.
// Sonus's, with the server mark in place of the faders.
Item {
  id: hero

  required property var host
  // The mark's lights take turns while the server connects or reboots.
  property bool working: false
  // Its lights in the alert tone while the server is down or in trouble.
  property color lightColor: host.fg
  property real markSize: Style.font.display
  property string title: ""
  property string line: ""
  property color lineColor: Qt.darker(host.fg, 1.3)
  // A line that answers the pointer (a drag, a fader) shows at once.
  property bool instant: false
  default property alias actions: actionRow.children

  property int typed: 0
  property bool cursorOn: true
  readonly property string revealed: Model.revealLine(line, typed, cursorOn)

  implicitHeight: Math.max(serverMark.height, labels.implicitHeight)

  function arrive() {
    typed = Style.reduceMotion ? line.length : 0
    serverMark.play()
  }

  onLineChanged: typed = instant || Style.reduceMotion ? line.length : 0
  onInstantChanged: if (instant) typed = line.length
  // A page coming into view types its line out and plays its mark again.
  onVisibleChanged: if (visible && host.opened) arrive()

  Connections {
    target: hero.host
    function onEntryChanged() { hero.arrive() }
  }

  Timer {
    interval: 22
    repeat: true
    running: hero.visible && hero.host.opened && hero.typed < hero.line.length
    onTriggered: hero.typed = Math.min(hero.line.length, hero.typed + 1)
  }

  Timer {
    interval: 530
    repeat: true
    running: hero.visible && hero.host.opened && !Style.reduceMotion
    onTriggered: hero.cursorOn = !hero.cursorOn
  }

  // Measures two real lines of the prompt, for the room it always keeps.
  Text {
    id: twoLines
    visible: false
    textFormat: Text.PlainText
    text: "X\nX"
    font.family: hero.host.fontFamily
    font.pixelSize: Style.font.caption
  }

  ServerMark {
    id: serverMark
    anchors.left: parent.left
    y: Math.round((hero.height - height) / 2)
    size: hero.markSize
    animated: true
    working: hero.working
    color: hero.host.fg
    dimColor: hero.host.dim
    lightColor: hero.lightColor
  }

  Column {
    id: labels
    anchors.left: serverMark.right
    anchors.leftMargin: Style.space(10)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Item {
      width: parent.width
      height: Math.max(titleText.implicitHeight, actionRow.implicitHeight)

      Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: actionRow.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: Model.breakable(hero.title)
        color: hero.host.fg
        font.family: hero.host.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Row {
        id: actionRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
      }
    }

    // The prompt sign, then the line, hanging under its first word when it
    // wraps. The whole line is laid out from the first character and only
    // revealed as it types, the rest drawn clear, so a word never jumps to the
    // next line as it grows. The cursor takes the place of the next character
    // (the font is monospaced, so that moves nothing), and at the end sits in
    // a cell the layout always keeps for it.
    Item {
      width: parent.width
      height: Math.max(lineText.implicitHeight, twoLines.implicitHeight)

      Text {
        id: promptSign
        textFormat: Text.PlainText
        text: "\u276F"
        color: hero.lineColor
        font.family: hero.host.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: lineText
        anchors.left: promptSign.right
        anchors.leftMargin: Style.space(6)
        anchors.right: parent.right
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: hero.revealed
        color: hero.lineColor
        font.family: hero.host.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
