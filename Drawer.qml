import QtQuick
import qs.Commons

// What an open room adds: it slides open under the rest of the room.
Item {
  id: drawer

  property bool open: false
  property real spacing: Style.space(8)
  default property alias content: drawerColumn.data

  width: parent ? parent.width : 0
  height: open ? drawerColumn.implicitHeight : 0
  visible: height > 0.5
  clip: true
  opacity: open ? 1 : 0

  Behavior on height { NumberAnimation { duration: Style.duration(280); easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }

  // Takes the clicks that land between the drawer's own rows and switches,
  // which would reach the room under it and close it. Under the content, so
  // those still take theirs; no hover, so the room stays lit.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    cursorShape: Qt.ArrowCursor
    onClicked: function(mouse) { mouse.accepted = true }
  }

  Column {
    id: drawerColumn
    width: parent.width
    spacing: drawer.spacing
    topPadding: Style.space(2)
  }
}
