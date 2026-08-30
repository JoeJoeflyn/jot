import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// BarWidget for Jot — adds a crisp sticky-note icon button to the Omarchy bar
BarWidget {
  id: root
  moduleName: "jot"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: toggleProc
    command: ["quickshell", "ipc", "-p", "/usr/share/omarchy/shell", "call", "jot", "toggle"]
  }

  Process {
    id: managerProc
    command: ["quickshell", "ipc", "-p", "/usr/share/omarchy/shell", "call", "jot", "open", "{\"action\":\"all\"}"]
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.iconSlot
    tooltipText: "Jot Sticky Notes\nLeft-click: Hide / Show Dock\nRight-click: All Notes & Archive"

    iconComponent: Component {
      Item {
        anchors.centerIn: parent
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas

        Canvas {
          anchors.fill: parent
          anchors.margins: 2
          renderTarget: Canvas.FramebufferObject

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width
            var h = height
            var fold = 5
            var rad = 2

            // Note Sheet outline with folded top-right corner
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.85)
            ctx.beginPath()
            ctx.moveTo(rad, 0)
            ctx.lineTo(w - fold, 0)
            ctx.lineTo(w, fold)
            ctx.lineTo(w, h - rad)
            ctx.arcTo(w, h, w - rad, h, rad)
            ctx.lineTo(rad, h)
            ctx.arcTo(0, h, 0, h - rad, rad)
            ctx.lineTo(0, rad)
            ctx.arcTo(0, 0, rad, 0, rad)
            ctx.closePath()
            ctx.fill()

            // Fold flap
            ctx.fillStyle = Qt.rgba(0, 0, 0, 0.28)
            ctx.beginPath()
            ctx.moveTo(w - fold, 0)
            ctx.lineTo(w, fold)
            ctx.lineTo(w - fold, fold)
            ctx.closePath()
            ctx.fill()

            // 2 Note rule lines
            ctx.fillStyle = Qt.rgba(0, 0, 0, 0.35)
            ctx.fillRect(3, 7, w - 6, 1.5)
            ctx.fillRect(3, 10, w - 8, 1.5)
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (!managerProc.running) managerProc.running = true
      } else {
        if (!toggleProc.running) toggleProc.running = true
      }
    }
  }
}
