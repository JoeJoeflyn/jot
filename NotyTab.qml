import QtQuick
import qs.Commons
import qs.Ui
import "NotyModel.js" as Model

// NotyTab — Single vertical tab in the fan (or compact colour chip).
// Faithful port of aimen08/noty's VerticalTab & ChipTab:
//   - Rounded on the outward-facing side only (edgeTabShape)
//   - 3-degree lean toward the screen edge
//   - Coloured paper fill with rich shadow
//   - Label turned on its side, pinned to the top (the uncovered strip)
//   - Pin dot indicator if pinned
//   - Staged 45ms slide-in from off-screen with spring physics
//   - Click & Press spring scale feedback
Item {
  id: tab

  property var note: ({ id: -1, title: "", body: "", color: 0, pinned: 0, archived: 0 })
  property bool isOpen: false
  property bool onRight: true
  property real strip: 80
  property real tabHeight: Model.GEOM.tabHeightMin
  property int stagingIndex: 0
  property bool revealed: true
  property bool isCompact: false
  property bool isMoreTab: false
  property int moreCount: 0
  property string emptyLabel: ""
  property string fontFamily: ""

  signal clicked()
  signal contextMenuRequested(real globalX, real globalY)
  signal reorderRequested(int fromIndex, int toIndex)

  property bool isDragging: false
  property real dragOffsetY: 0

  readonly property var pal: isMoreTab ? null : Model.colorByIndex(note ? note.color : 0)
  readonly property string labelText: {
    if (emptyLabel !== "") return emptyLabel
    if (isMoreTab) return "+" + moreCount
    return Model.displayTitle(note).toUpperCase()
  }

  implicitWidth: isCompact ? Model.GEOM.chipWidth + Model.GEOM.bleed : Model.GEOM.tabWidth + Model.GEOM.bleed
  implicitHeight: isCompact ? Model.GEOM.chipHeight : Math.max(Model.GEOM.tabHeightMin, tabHeight)
  width: implicitWidth
  height: implicitHeight

  z: (hitArea.drag.active || hitArea.containsMouse) ? 300 : (20 - stagingIndex)

  // Staging + Hover Nudge: slide-in from screen edge, nudge outward on hover
  property bool stageRevealed: false
  opacity: (revealed && stageRevealed) ? 1.0 : 0.0
  x: (revealed && stageRevealed)
    ? (hitArea.containsMouse || hitArea.drag.active ? (onRight ? -8 : 8) : 0)
    : (onRight ? (width + 28) : -(width + 28))

  Behavior on opacity {
    NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
  }
  Behavior on x {
    SpringAnimation { spring: 3.5; damping: 0.78; duration: 220 }
  }

  Timer {
    id: stageTimer
    interval: Math.max(10, stagingIndex * 45)
    running: true
    onTriggered: tab.stageRevealed = true
  }

  function restage() {
    stageRevealed = false
    stageTimer.restart()
  }

  onRevealedChanged: {
    if (revealed) restage()
    else stageRevealed = false
  }

  // Visual container with 3-degree lean, hover lift, and press animation
  Item {
    id: container
    anchors.left: parent.left
    anchors.right: parent.right
    height: parent.height
    y: 0
    transformOrigin: onRight ? Item.Right : Item.Left
    rotation: isCompact ? (onRight ? -1.8 : 1.8) : (onRight ? -Model.GEOM.leanDegrees : Model.GEOM.leanDegrees)

    scale: hitArea.pressed ? 0.95 : (hitArea.containsMouse ? 1.04 : 1.0)
    Behavior on scale {
      NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
    }

    // Tab Body Shape
    Rectangle {
      id: tabBody
      anchors.fill: parent
      radius: isCompact ? 7 : (isMoreTab ? 9 : 11)
      color: isMoreTab ? Qt.rgba(1, 1, 1, 0.16) : (pal ? pal.paper : "#E0E0E0")

      // Square the screen-docked edge
      Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: onRight ? parent.right : undefined
        anchors.left: onRight ? undefined : parent.left
        width: parent.radius + 2
        color: parent.color
      }

      border.color: Qt.rgba(0, 0, 0, 0.08)
      border.width: 0.5

      // Subtle shadow
      Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        z: -1
        radius: parent.radius
        color: "transparent"
        border.color: Qt.rgba(0, 0, 0, hitArea.containsMouse || isOpen ? 0.28 : 0.15)
        border.width: 1
      }
    }

    // Label: Rotated and pinned to the top strip
    Item {
      id: labelContainer
      visible: !isCompact
      anchors.top: parent.top
      anchors.left: onRight ? parent.left : undefined
      anchors.right: onRight ? undefined : parent.right
      width: Model.GEOM.tabWidth
      height: Math.max(20, tab.strip)
      clip: true

      Text {
        id: titleText
        anchors.centerIn: parent
        text: tab.labelText
        color: isMoreTab
          ? Qt.rgba(1, 1, 1, 0.80)
          : (pal ? Qt.rgba(
              parseInt(pal.ink.substring(1,3), 16) / 255,
              parseInt(pal.ink.substring(3,5), 16) / 255,
              parseInt(pal.ink.substring(5,7), 16) / 255, 0.88) : "#222")
        font.family: tab.fontFamily !== "" ? tab.fontFamily : Style.font.family
        font.pixelSize: isMoreTab ? 10 : 9.5
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
        elide: Text.ElideRight
        width: Math.max(20, tab.strip - Model.GEOM.labelInset)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        transform: Rotation {
          origin.x: titleText.width / 2
          origin.y: titleText.height / 2
          angle: onRight ? 90 : -90
        }
      }
    }

    // Compact mode chip dash
    Rectangle {
      visible: isCompact && !isMoreTab
      anchors.fill: parent
      anchors.margins: 2
      radius: 5
      color: pal ? pal.dash : "#888"
    }

    // Compact mode "+N" text
    Text {
      visible: isCompact && isMoreTab
      anchors.centerIn: parent
      text: "+" + moreCount
      color: Qt.rgba(1, 1, 1, 0.80)
      font.family: Style.font.family
      font.pixelSize: 10
      font.bold: true
    }

    // Pin indicator dot
    Rectangle {
      visible: !isMoreTab && !isCompact && note && note.pinned === 1
      anchors.top: parent.top
      anchors.topMargin: 7
      anchors.right: onRight ? parent.right : undefined
      anchors.left: onRight ? undefined : parent.left
      anchors.rightMargin: onRight ? (Model.GEOM.bleed + 6) : 0
      anchors.leftMargin: onRight ? 0 : (Model.GEOM.bleed + 6)
      width: 5
      height: 5
      radius: 2.5
      color: pal ? pal.dash : "#DC4570"
    }
  }

  MouseArea {
    id: hitArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: hitArea.drag.active ? Qt.ClosedHandCursor : (hitArea.containsMouse && !tab.isMoreTab ? Qt.OpenHandCursor : Qt.PointingHandCursor)

    drag.target: !tab.isMoreTab ? container : null
    drag.axis: Drag.YAxis
    drag.threshold: 4

    onPressed: function(mouse) {
      if (typeof root !== "undefined" && root.fanActivity) {
        root.fanActivity()
      }
    }

    onReleased: function(mouse) {
      if (typeof root !== "undefined" && root.fanActivity) {
        root.fanActivity()
      }
      var offsetY = container.y
      container.y = 0

      if (hitArea.drag.active || Math.abs(offsetY) > 8) {
        var stripHeight = tab.strip > 0 ? tab.strip : 60
        var slotsMoved = Math.round(offsetY / stripHeight)
        var targetIdx = Math.max(0, tab.stagingIndex + slotsMoved)
        if (slotsMoved !== 0) {
          tab.reorderRequested(tab.stagingIndex, targetIdx)
        }
      } else if (mouse.button === Qt.LeftButton) {
        tab.clicked()
      }
    }

    onCanceled: {
      container.y = 0
    }

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var globalPos = mapToItem(null, mouse.x, mouse.y)
        tab.contextMenuRequested(globalPos.x, globalPos.y)
      }
    }

    PanelToolTip {
      visible: !tab.isMoreTab && tab.note && hitArea.containsMouse && !hitArea.drag.active
      text: (tab.note ? Model.displayTitle(tab.note) : "") + " (Drag up/down to reorder)"
    }
  }
}
