import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "NotyModel.js" as Model

// NotyEditor — Expanded note editor with paper styling, gutter, find bar,
// live task checkbox handling, autosave, and palette switcher.
// Faithful port of aimen08/noty Sources/NoteEditor.swift.
Item {
  id: editorRoot

  property var note: ({ id: -1, title: "", body: "", color: 0, pinned: 0, archived: 0, updated_at: 0 })
  property bool onRight: true
  property string fontFamily: "iA Writer Quattro S"
  property real fontSize: 13.5
  property bool findActive: false
  property string findQuery: ""
  property int findMatchCount: 0
  property int findCurrentIndex: -1

  signal saveRequested(int id, string title, string body)
  signal colorChanged(int id, int colorIndex)
  signal pinToggled(int id)
  signal moveUpRequested(int id)
  signal moveDownRequested(int id)
  signal archiveRequested(int id)
  signal deleteRequested(int id)
  signal closeRequested()
  signal noteInteracted()

  readonly property var pal: note ? Model.colorByIndex(note.color) : Model.COLORS[0]

  width: Model.GEOM.editorWidth + Model.GEOM.bleed
  height: Model.GEOM.editorHeight

  // Paper Shape: rounded on outward side (14px), square against screen edge
  Rectangle {
    id: notePaper
    anchors.fill: parent
    radius: 14

    // Square screen-facing edge
    Rectangle {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: onRight ? parent.right : undefined
      anchors.left: onRight ? undefined : parent.left
      width: parent.radius + 2
      color: parent.color
    }

    // Authentic paper gradient (slight shade at bottom)
    gradient: Gradient {
      GradientStop { position: 0.0; color: editorRoot.pal.paper }
      GradientStop {
        position: 1.0
        color: Qt.rgba(
          parseInt(editorRoot.pal.paper.substring(1,3), 16)/255 * 0.90,
          parseInt(editorRoot.pal.paper.substring(3,5), 16)/255 * 0.90,
          parseInt(editorRoot.pal.paper.substring(5,7), 16)/255 * 0.90, 1.0)
      }
    }

    border.color: Qt.rgba(0, 0, 0, 0.08)
    border.width: 0.5

    // Catch clicks inside note paper so they don't propagate to dismiss overlay
    MouseArea {
      anchors.fill: parent
      onClicked: function(mouse) {
        editorRoot.noteInteracted()
        bodyText.forceActiveFocus()
      }
    }

    // Soft drop shadow
    Rectangle {
      anchors.fill: parent
      anchors.margins: -1
      z: -1
      radius: parent.radius + 1
      color: "transparent"
      border.color: Qt.rgba(0, 0, 0, 0.28)
      border.width: 2
    }
  }

  // Row containing Gutter and Sheet
  Row {
    anchors.fill: parent
    spacing: 0
    layoutDirection: onRight ? Qt.LeftToRight : Qt.RightToLeft

    // --- SHEET: Header + FindBar + Editor + Footer ---
    Column {
      width: parent.width - (Model.GEOM.gutterWidth + Model.GEOM.bleed)
      height: parent.height
      spacing: 0

      // Header: Title + Saved + Pin + Task + Find
      Row {
        id: headerRow
        width: parent.width
        height: 32
        spacing: 8
        leftPadding: 14
        rightPadding: 14

        Text {
          id: titleLabel
          anchors.verticalCenter: parent.verticalCenter
          text: Model.displayTitle(editorRoot.note)
          color: editorRoot.pal.ink
          font.family: editorRoot.fontFamily !== "" ? editorRoot.fontFamily : Style.font.family
          font.pixelSize: 13
          font.weight: Font.DemiBold
          elide: Text.ElideRight
          width: parent.width - savedLabel.width - btnRow.width - parent.spacing * 2 - parent.leftPadding - parent.rightPadding
        }

        Text {
          id: savedLabel
          anchors.verticalCenter: parent.verticalCenter
          text: "Saved · " + Model.ago(editorRoot.note ? editorRoot.note.updated_at : 0)
          color: Qt.rgba(
            parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
            parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
            parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.42)
          font.family: editorRoot.fontFamily !== "" ? editorRoot.fontFamily : Style.font.family
          font.pixelSize: 10
        }

        Row {
          id: btnRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4

          // Pin Button
          NotyVectorButton {
            iconType: "pin"
            inkColor: editorRoot.pal.ink
            active: editorRoot.note && editorRoot.note.pinned === 1
            toolTipText: editorRoot.note && editorRoot.note.pinned === 1 ? "Unpin (Ctrl+P)" : "Pin so it stays open (Ctrl+P)"
            onClicked: editorRoot.pinToggled(editorRoot.note.id)
          }

          // Task Button
          NotyVectorButton {
            iconType: "task"
            inkColor: editorRoot.pal.ink
            toolTipText: "Toggle task checkbox (Ctrl+T)"
            onClicked: editorRoot.toggleCurrentLineTask()
          }

          // Find Button
          NotyVectorButton {
            iconType: "search"
            inkColor: editorRoot.pal.ink
            active: editorRoot.findActive
            toolTipText: "Find in note (Ctrl+F)"
            onClicked: {
              editorRoot.findActive = !editorRoot.findActive
              if (editorRoot.findActive) {
                Qt.callLater(function() { findInput.forceActiveFocus() })
              } else {
                noteTextArea.forceActiveFocus()
              }
            }
          }
        }
      }

      // Inline Find Bar
      Rectangle {
        id: findBar
        visible: editorRoot.findActive
        width: parent.width
        height: visible ? 28 : 0
        color: Qt.rgba(
          parseInt(editorRoot.pal.dash.substring(1,3), 16)/255,
          parseInt(editorRoot.pal.dash.substring(3,5), 16)/255,
          parseInt(editorRoot.pal.dash.substring(5,7), 16)/255, 0.14)

        Row {
          anchors.fill: parent
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          spacing: 6

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "⌕"
            font.pixelSize: 13
            font.bold: true
            color: Qt.rgba(
              parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
              parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
              parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.55)
          }

          TextField {
            id: findInput
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 150
            placeholderText: "Find in note…"
            color: editorRoot.pal.ink
            font.family: editorRoot.fontFamily !== "" ? editorRoot.fontFamily : Style.font.family
            font.pixelSize: 12
            background: Rectangle { color: "transparent" }
            onTextChanged: editorRoot.searchNote(text)
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                editorRoot.findActive = false
                noteTextArea.forceActiveFocus()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (event.modifiers & Qt.ShiftModifier) editorRoot.findPrev()
                else editorRoot.findNext()
                event.accepted = true
              }
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: editorRoot.findMatchCount === 0 ? "—" : (editorRoot.findMatchCount + " matches")
            font.family: editorRoot.fontFamily !== "" ? editorRoot.fontFamily : Style.font.family
            font.pixelSize: 10
            color: Qt.rgba(
              parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
              parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
              parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.50)
          }

          // Previous Match Button
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "▲"
            font.pixelSize: 9
            color: prevMouse.containsMouse ? editorRoot.pal.ink : Qt.rgba(
              parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
              parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
              parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.55)
            MouseArea {
              id: prevMouse
              anchors.fill: parent
              anchors.margins: -4
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: editorRoot.findPrev()
            }
          }

          // Next Match Button
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "▼"
            font.pixelSize: 9
            color: nextMouse.containsMouse ? editorRoot.pal.ink : Qt.rgba(
              parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
              parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
              parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.55)
            MouseArea {
              id: nextMouse
              anchors.fill: parent
              anchors.margins: -4
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: editorRoot.findNext()
            }
          }

          // Close find bar button
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "✕"
            font.pixelSize: 9
            color: Qt.rgba(
              parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
              parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
              parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.50)
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                editorRoot.findActive = false
                noteTextArea.forceActiveFocus()
              }
            }
          }
        }
      }

      // Note Text Area with Task Support
      ScrollView {
        id: scroll
        width: parent.width
        height: parent.height - 32 - (findBar.visible ? 28 : 0) - 34
        clip: true

        TextArea {
          id: noteTextArea
          color: editorRoot.pal.ink
          font.family: editorRoot.fontFamily !== "" ? editorRoot.fontFamily : Style.font.family
          font.pixelSize: Math.round(editorRoot.fontSize)
          wrapMode: TextArea.Wrap
          textFormat: TextArea.PlainText
          selectByMouse: true
          placeholderText: "Type a note… (Ctrl+T for task)"
          leftPadding: 15
          rightPadding: 15
          topPadding: 6
          bottomPadding: 6
          background: Rectangle { color: "transparent" }

          text: editorRoot.note ? (editorRoot.note.body || "") : ""

          onTextChanged: {
            if (editorRoot.note && editorRoot.note.id >= 0 && text !== (editorRoot.note.body || "")) {
              autosaveTimer.restart()
              editorRoot.noteInteracted()
            }
          }

          onPressed: function(event) {
            editorRoot.noteInteracted()
            var pos = noteTextArea.positionAt(event.x, event.y)
            var full = noteTextArea.text
            var lineStart = full.lastIndexOf("\n", Math.max(0, pos - 1)) + 1
            var lineEnd = full.indexOf("\n", pos)
            if (lineEnd === -1) lineEnd = full.length
            var line = full.substring(lineStart, lineEnd)

            if (Model.isTaskLine(line) && pos <= lineStart + 3) {
              var toggled = Model.toggleTaskLine(line)
              var next = full.substring(0, lineStart) + toggled + full.substring(lineEnd)
              noteTextArea.text = next
              noteTextArea.cursorPosition = pos
              autosaveTimer.restart()
              event.accepted = true
              return
            }
          }

          // Keyboard handling
          Keys.onPressed: function(event) {
            editorRoot.noteInteracted()

            // Escape closes note
            if (event.key === Qt.Key_Escape) {
              if (editorRoot.findActive) {
                editorRoot.findActive = false
              } else {
                editorRoot.closeRequested()
              }
              event.accepted = true
              return
            }

            // Return / Enter task continuation logic
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))) {
                var full = noteTextArea.text
                var cur = noteTextArea.cursorPosition
                var lineStart = full.lastIndexOf("\n", Math.max(0, cur - 1)) + 1
                var lineEnd = full.indexOf("\n", cur)
                if (lineEnd === -1) lineEnd = full.length
                var line = full.substring(lineStart, lineEnd)

                if (Model.isTaskLine(line)) {
                  // If task line is empty (just checkbox), remove checkbox and end list
                  if (Model.stripTask(line).trim() === "") {
                    var cleared = full.substring(0, lineStart) + full.substring(lineEnd)
                    noteTextArea.text = cleared
                    noteTextArea.cursorPosition = lineStart
                    autosaveTimer.restart()
                    event.accepted = true
                    return
                  }
                  // Otherwise, insert new task line with ☐
                  var insert = "\n" + Model.TASK_OPEN_PREFIX
                  var next = full.substring(0, cur) + insert + full.substring(cur)
                  noteTextArea.text = next
                  noteTextArea.cursorPosition = cur + insert.length
                  autosaveTimer.restart()
                  event.accepted = true
                  return
                }
              }
            }

            // Ctrl+T: Toggle task checkbox on current line
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_T) {
              editorRoot.toggleCurrentLineTask()
              event.accepted = true
              return
            }

            // Ctrl+F: Toggle find
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
              editorRoot.findActive = true
              Qt.callLater(function() { findInput.forceActiveFocus() })
              event.accepted = true
              return
            }

            // Ctrl+P: Toggle pin
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
              editorRoot.pinToggled(editorRoot.note.id)
              event.accepted = true
              return
            }

            // Ctrl+.: Cycle colour
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Period) {
              editorRoot.cycleColor()
              event.accepted = true
              return
            }

            // Ctrl+Backspace: Delete note
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Backspace) {
              editorRoot.deleteRequested(editorRoot.note.id)
              event.accepted = true
              return
            }

            // Ctrl++ / Ctrl+= : Increase font size
            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) {
              editorRoot.fontSize = Math.min(24.0, editorRoot.fontSize + 1.5)
              event.accepted = true
              return
            }

            // Ctrl+- : Decrease font size
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Minus) {
              editorRoot.fontSize = Math.max(9.0, editorRoot.fontSize - 1.5)
              event.accepted = true
              return
            }
          }
        }
      }

      // Footer: 8 color swatches + Archive / Delete / Close
      Row {
        id: footerRow
        width: parent.width
        height: 34
        spacing: 7
        leftPadding: 14
        rightPadding: 14

        // 8 color swatches
        Repeater {
          model: Model.COLORS
          delegate: Item {
            width: 16
            height: 34
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              id: swatchCircle
              anchors.centerIn: parent
              width: 11
              height: 11
              radius: 5.5
              color: modelData.dash
              scale: swatchMouse.containsMouse ? 1.25 : 1.0
              Behavior on scale { NumberAnimation { duration: 100 } }

              // Active ring
              Rectangle {
                anchors.fill: parent
                anchors.margins: -2.5
                radius: width / 2
                color: "transparent"
                border.color: editorRoot.note && editorRoot.note.color === index
                  ? Qt.rgba(
                      parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
                      parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
                      parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.65)
                  : "transparent"
                border.width: 1.5
              }
            }

            MouseArea {
              id: swatchMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: editorRoot.colorChanged(editorRoot.note.id, index)

              PanelToolTip {
                visible: swatchMouse.containsMouse
                text: modelData.name + " note"
              }
            }
          }
        }

        // Flexible spacer
        Item {
          width: Math.max(10, parent.width - parent.leftPadding - parent.rightPadding - (16 * 8 + 7 * 7) - (24 * 3 + 6 * 2))
          height: 1
        }

        // Footer Action Buttons (Archive, Delete, Close)
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          NotyVectorButton {
            iconType: "archive"
            inkColor: editorRoot.pal.ink
            toolTipText: "Archive Note (Ctrl+A)"
            onClicked: editorRoot.archiveRequested(editorRoot.note.id)
          }

          NotyVectorButton {
            iconType: "trash"
            inkColor: editorRoot.pal.ink
            toolTipText: "Delete Note (Ctrl+D)"
            onClicked: editorRoot.deleteRequested(editorRoot.note.id)
          }

          NotyVectorButton {
            iconType: "close"
            inkColor: editorRoot.pal.ink
            toolTipText: "Close Note (Esc)"
            onClicked: editorRoot.closeRequested()
          }
        }
      }
    }

    // --- GUTTER: The note's own tab carried down the screen edge ---
    Rectangle {
      id: gutter
      width: Model.GEOM.gutterWidth + Model.GEOM.bleed
      height: parent.height
      color: Qt.rgba(
        parseInt(editorRoot.pal.dash.substring(1,3), 16)/255,
        parseInt(editorRoot.pal.dash.substring(3,5), 16)/255,
        parseInt(editorRoot.pal.dash.substring(5,7), 16)/255, 0.20)
      clip: true

      // Rotated Title
      Text {
        anchors.centerIn: parent
        text: Model.displayTitle(editorRoot.note).toUpperCase()
        color: Qt.rgba(
          parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
          parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
          parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.70)
        font.family: editorRoot.fontFamily !== "" ? editorRoot.fontFamily : Style.font.family
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 0.8
        elide: Text.ElideRight
        width: parent.height - 44
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        transform: Rotation {
          origin.x: (parent.height - 44) / 2
          origin.y: 10 / 2
          angle: onRight ? 90 : -90
        }
      }

      // 1px Dashed dividing rule between gutter and sheet
      Canvas {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: onRight ? undefined : parent.right
        anchors.left: onRight ? parent.left : undefined
        width: 1
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = Qt.rgba(
            parseInt(editorRoot.pal.ink.substring(1,3), 16)/255,
            parseInt(editorRoot.pal.ink.substring(3,5), 16)/255,
            parseInt(editorRoot.pal.ink.substring(5,7), 16)/255, 0.22)
          ctx.lineWidth = 1
          ctx.setLineDash([3, 4])
          ctx.beginPath()
          ctx.moveTo(0.5, 0)
          ctx.lineTo(0.5, height)
          ctx.stroke()
        }
      }
    }
  }

  function normalizeBody(b) {
    if (!b) return ""
    var str = String(b)
    if (str.indexOf("\\n") !== -1 && str.indexOf("\n") === -1) {
      return str.replace(/\\n/g, "\n")
    }
    return str
  }

  onNoteChanged: {
    if (note && noteTextArea) {
      var nb = normalizeBody(note.body)
      if (noteTextArea.text !== nb) {
        noteTextArea.text = nb
      }
    }
  }

  Component.onCompleted: {
    if (note && noteTextArea) {
      noteTextArea.text = normalizeBody(note.body)
    }
  }

  function loadNote(n) {
    if (!n) return
    note = n
    var nb = normalizeBody(n.body)
    if (noteTextArea.text !== nb) {
      noteTextArea.text = nb
    }
    findActive = false
    findQuery = ""
    findMatchCount = 0
    Qt.callLater(function() { noteTextArea.forceActiveFocus() })
  }

  function focusEditor() {
    noteTextArea.forceActiveFocus()
  }

  function flushAutosave() {
    autosaveTimer.stop()
    if (editorRoot.note && editorRoot.note.id >= 0) {
      var tit = Model.derivedTitle(noteTextArea.text)
      editorRoot.saveRequested(editorRoot.note.id, tit, noteTextArea.text)
    }
  }

  Timer {
    id: autosaveTimer
    interval: 250 // 250ms debounced autosave
    onTriggered: {
      if (editorRoot.note && editorRoot.note.id >= 0) {
        var tit = Model.derivedTitle(noteTextArea.text)
        editorRoot.saveRequested(editorRoot.note.id, tit, noteTextArea.text)
      }
    }
  }

  function cycleColor() {
    if (!note || note.id < 0) return
    var nextCol = (note.color + 1) % Model.COLORS.length
    editorRoot.colorChanged(note.id, nextCol)
  }

  function toggleCurrentLineTask() {
    var full = noteTextArea.text
    var cur = noteTextArea.cursorPosition
    var lineStart = full.lastIndexOf("\n", Math.max(0, cur - 1)) + 1
    var lineEnd = full.indexOf("\n", cur)
    if (lineEnd === -1) lineEnd = full.length
    var line = full.substring(lineStart, lineEnd)

    var toggled = Model.toggleTaskLine(line)
    var next = full.substring(0, lineStart) + toggled + full.substring(lineEnd)
    noteTextArea.text = next
    noteTextArea.cursorPosition = Math.min(next.length, cur + (toggled.length - line.length))
    autosaveTimer.restart()
  }

  function searchNote(q) {
    findQuery = q
    if (!q || q.trim() === "") {
      findMatchCount = 0
      findCurrentIndex = -1
      return
    }
    var full = noteTextArea.text.toLowerCase()
    var target = q.toLowerCase()
    var count = 0
    var pos = 0
    while (pos < full.length) {
      var idx = full.indexOf(target, pos)
      if (idx === -1) break
      count++
      pos = idx + Math.max(1, target.length)
    }
    findMatchCount = count
    if (count > 0) findNext()
  }

  function findNext() {
    if (!findQuery || findQuery.trim() === "") return
    var full = noteTextArea.text.toLowerCase()
    var target = findQuery.toLowerCase()
    var cur = noteTextArea.cursorPosition
    var idx = full.indexOf(target, cur)
    if (idx === -1) idx = full.indexOf(target, 0) // wrap around
    if (idx !== -1) {
      noteTextArea.select(idx, idx + target.length)
    }
  }

  function findPrev() {
    if (!findQuery || findQuery.trim() === "") return
    var full = noteTextArea.text.toLowerCase()
    var target = findQuery.toLowerCase()
    var cur = Math.max(0, noteTextArea.selectionStart - 1)
    var idx = full.lastIndexOf(target, cur)
    if (idx === -1) idx = full.lastIndexOf(target) // wrap around
    if (idx !== -1) {
      noteTextArea.select(idx, idx + target.length)
    }
  }

  // --- Helper Components ---

  component NotyVectorButton: Rectangle {
    id: vecBtn
    property string iconType: "" // "pin", "task", "search", "archive", "trash", "close"
    property color inkColor: editorRoot.pal.ink
    property bool active: false
    property string toolTipText: ""

    signal clicked()

    width: 24
    height: 24
    radius: 6
    color: {
      if (iconType === "trash" && vecMouse.containsMouse) return Qt.rgba(0.95, 0.25, 0.25, 0.18)
      if (vecMouse.containsMouse) return Qt.rgba(
        parseInt(inkColor.toString().substring(1,3), 16)/255,
        parseInt(inkColor.toString().substring(3,5), 16)/255,
        parseInt(inkColor.toString().substring(5,7), 16)/255, 0.14)
      if (active) return Qt.rgba(
        parseInt(inkColor.toString().substring(1,3), 16)/255,
        parseInt(inkColor.toString().substring(3,5), 16)/255,
        parseInt(inkColor.toString().substring(5,7), 16)/255, 0.10)
      return "transparent"
    }

    Canvas {
      id: iconCanvas
      anchors.centerIn: parent
      width: 14
      height: 14
      renderTarget: Canvas.FramebufferObject

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width
        var h = height
        var ink = vecBtn.inkColor
        var isHover = vecMouse.containsMouse
        var alpha = vecBtn.active ? 0.95 : (isHover ? 0.90 : 0.55)

        if (vecBtn.iconType === "trash" && isHover) {
          ctx.strokeStyle = "#E53E3E"
          ctx.fillStyle = "#E53E3E"
        } else {
          ctx.strokeStyle = Qt.rgba(
            parseInt(ink.toString().substring(1,3), 16)/255,
            parseInt(ink.toString().substring(3,5), 16)/255,
            parseInt(ink.toString().substring(5,7), 16)/255, alpha)
          ctx.fillStyle = ctx.strokeStyle
        }

        ctx.lineWidth = 1.3
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        if (vecBtn.iconType === "moveUp") {
          ctx.beginPath()
          ctx.moveTo(7, 3)
          ctx.lineTo(2.8, 8.5)
          ctx.lineTo(5.2, 8.5)
          ctx.lineTo(5.2, 12)
          ctx.lineTo(8.8, 12)
          ctx.lineTo(8.8, 8.5)
          ctx.lineTo(11.2, 8.5)
          ctx.closePath()
          ctx.fill()
        } else if (vecBtn.iconType === "moveDown") {
          ctx.beginPath()
          ctx.moveTo(7, 12)
          ctx.lineTo(2.8, 6.5)
          ctx.lineTo(5.2, 6.5)
          ctx.lineTo(5.2, 3)
          ctx.lineTo(8.8, 3)
          ctx.lineTo(8.8, 6.5)
          ctx.lineTo(11.2, 6.5)
          ctx.closePath()
          ctx.fill()
        } else if (vecBtn.iconType === "pin") {
          if (vecBtn.active) {
            ctx.beginPath()
            ctx.arc(7, 4.5, 3, 0, Math.PI * 2)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(7, 7.5)
            ctx.lineTo(7, 13)
            ctx.stroke()
          } else {
            ctx.beginPath()
            ctx.arc(7, 4.5, 2.8, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(7, 7.5)
            ctx.lineTo(7, 13)
            ctx.stroke()
          }
        } else if (vecBtn.iconType === "task") {
          ctx.strokeRect(1.5, 1.5, 11, 11)
          ctx.beginPath()
          ctx.moveTo(3.5, 7)
          ctx.lineTo(6, 9.5)
          ctx.lineTo(10.5, 4.5)
          ctx.stroke()
        } else if (vecBtn.iconType === "search") {
          ctx.beginPath()
          ctx.arc(5.5, 5.5, 4, 0, Math.PI * 2)
          ctx.stroke()
          ctx.beginPath()
          ctx.moveTo(8.5, 8.5)
          ctx.lineTo(12.5, 12.5)
          ctx.stroke()
        } else if (vecBtn.iconType === "archive") {
          // Box top lid
          ctx.strokeRect(1.5, 2, 11, 2.5)
          // Box body
          ctx.beginPath()
          ctx.moveTo(2.5, 4.5)
          ctx.lineTo(2.5, 12)
          ctx.lineTo(11.5, 12)
          ctx.lineTo(11.5, 4.5)
          ctx.stroke()
          // Handle slot
          ctx.beginPath()
          ctx.moveTo(5, 7.5)
          ctx.lineTo(9, 7.5)
          ctx.stroke()
        } else if (vecBtn.iconType === "trash") {
          // Lid
          ctx.beginPath()
          ctx.moveTo(2, 3.5)
          ctx.lineTo(12, 3.5)
          ctx.moveTo(5, 3.5)
          ctx.lineTo(5, 1.5)
          ctx.lineTo(9, 1.5)
          ctx.lineTo(9, 3.5)
          ctx.stroke()
          // Can body
          ctx.beginPath()
          ctx.moveTo(3.5, 3.5)
          ctx.lineTo(4, 12.5)
          ctx.lineTo(10, 12.5)
          ctx.lineTo(10.5, 3.5)
          ctx.stroke()
          // Vertical ribs
          ctx.beginPath()
          ctx.moveTo(5.8, 6)
          ctx.lineTo(5.8, 10)
          ctx.moveTo(8.2, 6)
          ctx.lineTo(8.2, 10)
          ctx.stroke()
        } else if (vecBtn.iconType === "close") {
          ctx.beginPath()
          ctx.moveTo(3.5, 3.5)
          ctx.lineTo(10.5, 10.5)
          ctx.moveTo(10.5, 3.5)
          ctx.lineTo(3.5, 10.5)
          ctx.stroke()
        }
      }
    }

    Connections {
      target: vecBtn
      function onInkColorChanged() { iconCanvas.requestPaint() }
      function onActiveChanged() { iconCanvas.requestPaint() }
    }

    MouseArea {
      id: vecMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: iconCanvas.requestPaint()
      onExited: iconCanvas.requestPaint()
      onClicked: vecBtn.clicked()
    }

    PanelToolTip {
      visible: vecBtn.toolTipText !== "" && vecMouse.containsMouse
      text: vecBtn.toolTipText
    }
  }
}
