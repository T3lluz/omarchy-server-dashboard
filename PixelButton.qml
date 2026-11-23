import QtQuick
import qs.Commons
import qs.Ui

// The shell's small action button with a pixel icon laid over it, so the
// icon can turn (a gear in eighths, its teeth landing where they were, the
// refresh arrows in quarters) or be nudged in whole steps. Under the pointer
// the icon acts itself out (Motion.js), unless the button turns it already.
PanelActionButton {
  id: button

  property string icon: ""
  property color iconColor: foreground
  // Degrees, and a sideways nudge in steps of two pixels.
  property real angle: 0
  property int nudge: 0
  property bool acts: true
  property int hovers: 0

  iconText: ""
  onHovered: function(isHovered) { if (isHovered && enabled && acts) hovers++ }

  PixelIcon {
    anchors.centerIn: parent
    name: button.icon
    size: button.fontSize
    color: button.iconColor
    opacity: button.enabled ? 1 : 0.45
    rotation: button.angle
    transform: Translate { x: button.nudge * Style.space(2) }
    play: button.hovers
  }
}
