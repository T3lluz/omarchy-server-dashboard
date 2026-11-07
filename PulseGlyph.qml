import QtQuick
import QtQuick.Effects

// The server's icon in the panel. While it connects or reboots it dims and
// soft bands rise through it: Batteries' charging pulse, the family's one
// motion, here for "working on it".
Item {
  id: root

  // Draws the device; sized to fill this item.
  property Component glyph: null
  property bool active: false
  // 0 to 1: how far the band has risen through the drawing.
  property real flow: 0

  Loader {
    id: art
    width: root.width
    height: root.height
    sourceComponent: root.glyph
  }

  // While active, the drawing is shown only through the effect below.
  // Hidden by its texture rather than `visible: false`, which would stop the
  // AirPods outline's own layer from rendering.
  ShaderEffectSource {
    id: artTexture
    visible: false
    sourceItem: art
    hideSource: root.active
    live: root.active
    smooth: true
  }

  // Dim everywhere, bright where the band is. The mask goes through a
  // texture too, or moving the band would not repaint the panel.
  Item {
    id: mask
    width: root.width
    height: root.height
    clip: true

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(1, 1, 1, 0.5)
    }

    // Rises from below the drawing to above it, one band per cycle.
    Rectangle {
      readonly property real travel: root.height + height
      y: root.height - travel * root.flow
      width: parent.width
      height: Math.max(root.height * 0.5, 8)
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.5; color: "white" }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
  }

  ShaderEffectSource {
    id: maskTexture
    visible: false
    sourceItem: mask
    hideSource: true
    live: root.active
    smooth: true
  }

  MultiEffect {
    visible: root.active
    anchors.fill: parent
    source: artTexture
    maskEnabled: true
    maskSource: maskTexture
    // A threshold of 0.5 spread by 1 passes the mask's alpha through as is.
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
  }

  // Stepped 20 times a second, not every frame. Each step repaints the whole
  // window, and at 100 to 165 Hz on every screen that kept the shell and the
  // compositor busy. 20 steps a second still reads as a glide.
  Timer {
    interval: 50
    repeat: true
    running: root.active && root.visible
    onTriggered: root.flow = (root.flow + interval / 2400) % 1
  }
}
