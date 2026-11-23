import QtQuick
import qs.Commons
import "Model.js" as Model

// One of the panel's four actions (a shell, btop, reboot, shutdown): a small
// room with its pixel icon over its name. It acts its icon out when it comes
// in, under the pointer and when clicked, and keeps at it while its reboot
// or shutdown runs; reboot and shutdown take the alert tone under the
// pointer, since they ask before they act.
Room {
  id: tile

  property var action: null
  // The cursor key it answers to, "a:<i>".
  property string cursor: ""
  readonly property bool drastic: !!action && (action.key === "reboot" || action.key === "poweroff")
  // Its own action is running: a reboot or shutdown on its way.
  readonly property bool running: drastic && host.busyAction.indexOf(action.key + ":") === 0
  property int hovers: 0

  tone: host.toneOf("")
  pad: Style.space(8)
  spacing: Style.space(5)
  keyed: host.keyboardCursor && host.cursorActive && host.cursorKey === cursor
  enabled: !(drastic && host.busyAction !== "")
  opacity: fade * (enabled ? 1 : 0.5)
  onClicked: host.runAction(action.key)
  onHoveredChanged: {
    if (hovered) { host.hover(cursor); hovers++ }
    else host.unhover(cursor)
  }

  PixelIcon {
    id: tileIcon
    anchors.horizontalCenter: parent.horizontalCenter
    name: Model.roomPixel(tile.action ? tile.action.key : "")
    size: Style.font.heading
    color: tile.drastic && (tile.hovered || tile.keyed) ? tile.host.lowTone : tile.host.fg
    // Acts out on coming in, on a click and under the pointer; loops while
    // its reboot or shutdown runs.
    play: tile.story + tile.hovers
    live: tile.running
  }

  Text {
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    text: tile.action ? tile.action.text : ""
    color: tile.host.fg
    font.family: tile.host.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
