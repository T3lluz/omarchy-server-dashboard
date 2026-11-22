import QtQuick
import qs.Commons
import "Model.js" as Model

// One of the panel's four actions (a shell, btop, reboot, shutdown): a small
// room with its pixel icon over its name. It acts its icon out when it comes
// in and when clicked; reboot and shutdown take the alert tone under the
// pointer, since they ask before they act.
Room {
  id: tile

  property var action: null
  // The cursor key it answers to, "a:<i>".
  property string cursor: ""
  readonly property bool drastic: !!action && (action.key === "reboot" || action.key === "poweroff")
  readonly property string storyName: Model.storyOf(action ? action.key : "")
  property real k: 1
  readonly property var pose: Model.storyPose(storyName, k)

  tone: host.toneOf("")
  pad: Style.space(8)
  spacing: Style.space(5)
  keyed: host.keyboardCursor && host.cursorActive && host.cursorKey === cursor
  enabled: !(drastic && host.busyAction !== "")
  opacity: fade * (enabled ? 1 : 0.5)
  onClicked: host.runAction(action.key)
  onHoveredChanged: hovered ? host.hover(cursor) : host.unhover(cursor)
  // The room counts up each time its icon should act itself out.
  onStoryChanged: if (!Style.reduceMotion) storyRun.restart()

  NumberAnimation {
    id: storyRun
    target: tile
    property: "k"
    from: 0
    to: 1
    duration: Style.duration(660)
  }

  PixelIcon {
    id: tileIcon
    anchors.horizontalCenter: parent.horizontalCenter
    name: Model.roomPixel(tile.action ? tile.action.key : "")
    size: Style.font.heading
    color: tile.drastic && (tile.hovered || tile.keyed) ? tile.host.lowTone : tile.host.fg
    transform: Translate { x: tile.pose.x * tileIcon.cell; y: tile.pose.y * tileIcon.cell }
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
