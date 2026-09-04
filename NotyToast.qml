import QtQuick
import qs.Commons
import qs.Ui
import "NotyModel.js" as Model

// NotyToast — 10-second floating deletion undo toast.
// Matches aimen08/noty Sources/UndoToast.swift:
//   - Circular countdown progress ring in the deleted note's dash colour
//   - "Note deleted" header with note title preview
//   - Instant "Undo" button to restore note
Item {
  id: toast

  property var pendingNote: null
  property real durationMs: 10000
  property real startTime: 0
  property real remaining: 10.0

  signal undoRequested()
  signal commitRequested()

  width: 280
  height: 46
  opacity: pendingNote ? 1.0 : 0.0
  visible: opacity > 0

  Behavior on opacity {
    NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
  }

  function start(note) {
    pendingNote = note
    startTime = Date.now()
    remaining = 10.0
    countdownTimer.restart()
    ringCanvas.requestPaint()
  }

  function dismiss() {
    countdownTimer.stop()
    pendingNote = null
  }

  Timer {
    id: countdownTimer
    interval: 80
    repeat: true
    running: false
    onTriggered: {
      if (!pendingNote) { stop(); return }
      var elapsed = Date.now() - startTime
      toast.remaining = Math.max(0, (toast.durationMs - elapsed) / 1000)
      ringCanvas.requestPaint()
      if (elapsed >= toast.durationMs) {
        stop()
        toast.commitRequested()
        toast.dismiss()
      }
    }
  }

  readonly property var pal: pendingNote ? Model.colorByIndex(pendingNote.color) : Model.COLORS[0]

  Rectangle {
    id: card
    anchors.fill: parent
    radius: 12
    color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
    border.color: Qt.rgba(1, 1, 1, 0.12)
    border.width: 1

    // Shadow
    Rectangle {
      anchors.fill: parent
      anchors.margins: -1
      z: -1
      radius: 13
      color: "transparent"
      border.color: Qt.rgba(0, 0, 0, 0.35)
      border.width: 2
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      spacing: 10

      // Countdown Ring Canvas
      Canvas {
        id: ringCanvas
        width: 18
        height: 18
        anchors.verticalCenter: parent.verticalCenter

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2
          var cy = height / 2
          var r = width / 2 - 2

          // Background track
          ctx.beginPath()
          ctx.arc(cx, cy, r, 0, 2 * Math.PI)
          ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.20)
          ctx.lineWidth = 2
          ctx.stroke()

          // Active progress arc
          var frac = Math.max(0, Math.min(1.0, toast.remaining / 10.0))
          if (frac > 0) {
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + (2 * Math.PI * frac), false)
            ctx.strokeStyle = toast.pal.dash
            ctx.lineWidth = 2
            ctx.lineCap = "round"
            ctx.stroke()
          }
        }
      }

      // Text column
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - ringCanvas.width - undoBtn.width - parent.spacing * 2 - 24
        spacing: 1

        Text {
          textFormat: Text.PlainText
          text: "Note deleted"
          color: "#FFFFFF"
          font.family: Style.font.family
          font.pixelSize: 12
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: toast.pendingNote ? Model.displayTitle(toast.pendingNote) : ""
          color: Qt.rgba(1, 1, 1, 0.65)
          font.family: Style.font.family
          font.pixelSize: 11
          elide: Text.ElideRight
          width: parent.width
        }
      }

      // Undo button
      Rectangle {
        id: undoBtn
        anchors.verticalCenter: parent.verticalCenter
        width: undoLabel.implicitWidth + 14
        height: 24
        radius: 6
        color: undoMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10)

        Text {
          id: undoLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "Undo"
          color: "#FFFFFF"
          font.family: Style.font.family
          font.pixelSize: 12
          font.bold: true
        }

        MouseArea {
          id: undoMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            toast.undoRequested()
            toast.dismiss()
          }
        }
      }
    }
  }
}
