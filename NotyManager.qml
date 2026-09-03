import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "NotyModel.js" as Model

// NotyManager — All Notes & Archive Library Window.
// Faithful port of aimen08/noty Sources/LibraryWindow.swift:
//   - Segmented mode: All Notes vs Archive
//   - Live search across titles and note bodies
//   - Left sidebar with colored dashes, timestamps, task counts, preview
//   - Right detail pane with paper styling, live editing, and task checkbox support
Item {
  id: mgrRoot

  property bool open: false
  property string mode: "all" // "all" | "archive"
  property string searchQuery: ""
  property int selectedNoteId: -1
  property int loadedDetailNoteId: -1
  property var notesList: []
  property string fontFamily: ""
  property real fontSize: 13.5
  property var historyList: []
  property bool historyOpen: false

  signal closeRequested()
  signal newNoteRequested()
  signal saveRequested(int id, string title, string body)
  signal colorChanged(int id, int colorIndex)
  signal pinToggled(int id)
  signal archiveToggled(int id, bool toArchived)
  signal deleteRequested(int id)
  signal historyRequested(int id)
  signal snapshotRequested(int id)
  signal historyRestoreRequested(int id, string title, string body)

  visible: open
  opacity: open ? 1.0 : 0.0
  scale: open ? 1.0 : 0.96
  transformOrigin: Item.Center
  Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  // Filtered notes list based on mode and searchQuery
  readonly property var filteredNotes: {
    var list = Array.isArray(notesList) ? notesList : []
    var isArch = (mode === "archive")
    var q = searchQuery.trim().toLowerCase()
    var out = []
    for (var i = 0; i < list.length; i++) {
      var n = list[i]
      if (isArch ? (n.archived === 1) : (n.archived === 0)) {
        if (q === "") {
          out.push(n)
        } else {
          var t = String(n.title || "").toLowerCase()
          var b = String(n.body || "").toLowerCase()
          if (t.indexOf(q) !== -1 || b.indexOf(q) !== -1) {
            out.push(n)
          }
        }
      }
    }
    return out
  }

  readonly property var selectedNote: {
    if (selectedNoteId < 0) return null
    for (var i = 0; i < filteredNotes.length; i++) {
      if (filteredNotes[i].id === selectedNoteId) return filteredNotes[i]
    }
    return filteredNotes.length > 0 ? filteredNotes[0] : null
  }

  onFilteredNotesChanged: {
    if (filteredNotes.length > 0) {
      var found = false
      for (var i = 0; i < filteredNotes.length; i++) {
        if (filteredNotes[i].id === selectedNoteId) { found = true; break }
      }
      if (!found) selectedNoteId = filteredNotes[0].id
    } else {
      selectedNoteId = -1
    }
  }

  // Load text only when switching to a different note, not when the same
  // note is refreshed from DB after a save (which would clobber in-progress typing)
  onSelectedNoteIdChanged: {
    if (selectedNoteId < 0 || selectedNoteId === loadedDetailNoteId) {
      if (selectedNoteId < 0) { loadedDetailNoteId = -1; detailTextArea.text = "" }
      return
    }
    loadedDetailNoteId = selectedNoteId
    // Look up directly from notesList — the selectedNote binding may not have
    // recomputed yet during signal cascades (onFilteredNotesChanged → selectedNoteId).
    var n = null
    for (var i = 0; i < notesList.length; i++) {
      if (notesList[i].id === selectedNoteId) { n = notesList[i]; break }
    }
    detailTextArea.text = n ? (n.body || "") : ""
    historyList = []
    historyOpen = false
  }

  function show(initialMode) {
    mode = initialMode || "all"
    searchQuery = ""
    open = true
    historyList = []
    historyOpen = false
    if (filteredNotes.length > 0) {
      loadedDetailNoteId = -1
      selectedNoteId = filteredNotes[0].id
    }
    refreshDetail()
    if (selectedNoteId >= 0) snapshotRequested(selectedNoteId)
  }

  function refreshDetail() {
    if (selectedNoteId >= 0 && detailTextArea) {
      var n = null
      for (var i = 0; i < notesList.length; i++) {
        if (notesList[i].id === selectedNoteId) { n = notesList[i]; break }
      }
      if (n) {
        loadedDetailNoteId = n.id
        detailTextArea.text = n.body || ""
      }
    }
    historyList = []
    historyOpen = false
  }

  function close() {
    open = false
    detailEditor.flush()
    closeRequested()
  }

  // Flush current edit before switching mode — selectedNote is still valid here,
  // before filteredNotes recomputes and clears selectedNoteId.
  function switchMode(newMode) {
    if (mode === newMode) return
    detailEditor.flush()
    mode = newMode
  }

  // Dismiss on click outside modal card
  MouseArea {
    anchors.fill: parent
    onClicked: mgrRoot.close()
    Keys.onEscapePressed: mgrRoot.close()
  }

  // Centered Modal Window Card
  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - 40, 760)
    height: Math.min(parent.height - 40, 520)
    radius: 14
    color: Color.menu.background || Qt.rgba(0.12, 0.12, 0.14, 0.98)
    border.color: Color.menu.border || Qt.rgba(1, 1, 1, 0.10)
    border.width: 1

    // Apple-style soft, layered shadow (outer diffuse + inner tight)
    Rectangle {
      anchors.fill: parent
      anchors.margins: -2
      z: -2
      radius: parent.radius + 2
      color: "transparent"
      border.color: Qt.rgba(0, 0, 0, 0.30)
      border.width: 6
    }
    Rectangle {
      anchors.fill: parent
      anchors.margins: -1
      z: -1
      radius: parent.radius + 1
      color: "transparent"
      border.color: Qt.rgba(0, 0, 0, 0.50)
      border.width: 2
    }

    // Swallow clicks inside the card
    MouseArea {
      anchors.fill: parent
    }

    Column {
      anchors.fill: parent
      spacing: 0

      // TOP BAR: Segmented Mode + Search + New Note + Close
      Rectangle {
        width: parent.width
        height: 48
        color: Qt.rgba(1, 1, 1, 0.03)
        radius: 14

        // Square bottom corners
        Rectangle {
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: 14
          color: parent.color
        }

        Row {
          anchors.fill: parent
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          spacing: 12

          // Segmented Switcher: All Notes | Archive
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 180
            height: 28
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.30)
            border.color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 0.5

            Row {
              anchors.fill: parent
              anchors.margins: 2
              spacing: 2

              // "All Notes" segment
              Rectangle {
                width: (parent.width - 2) / 2
                height: parent.height
                radius: 6
                color: mgrRoot.mode === "all"
                  ? (allSegMouse.containsPress ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.16))
                  : (allSegMouse.containsPress ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                  anchors.centerIn: parent
                  text: "All Notes"
                  color: mgrRoot.mode === "all" ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.55)
                  font.family: Style.font.family
                  font.pixelSize: 11
                  font.bold: mgrRoot.mode === "all"
                  // ponytail: tracking bump for small caps-style labels
                  font.letterSpacing: 0.3
                }

                MouseArea {
                  id: allSegMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: mgrRoot.switchMode("all")
                }
              }

              // "Archive" segment
              Rectangle {
                width: (parent.width - 2) / 2
                height: parent.height
                radius: 6
                color: mgrRoot.mode === "archive"
                  ? (archSegMouse.containsPress ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.16))
                  : (archSegMouse.containsPress ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                  anchors.centerIn: parent
                  text: "Archive"
                  color: mgrRoot.mode === "archive" ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.55)
                  font.family: Style.font.family
                  font.pixelSize: 11
                  font.bold: mgrRoot.mode === "archive"
                  font.letterSpacing: 0.3
                }

                MouseArea {
                  id: archSegMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: mgrRoot.switchMode("archive")
                }
              }
            }
          }

          // Search Field
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 220
            height: 28
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.05)
            border.color: searchInput.activeFocus ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.06)
            border.width: 0.5
            Behavior on border.color { ColorAnimation { duration: 160 } }

            Row {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 6

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "⌕"
                font.pixelSize: 13
                font.bold: true
                color: Qt.rgba(1, 1, 1, 0.55)
              }

              TextField {
                id: searchInput
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40
                placeholderText: "Search notes…"
                color: "#FFFFFF"
                font.family: Style.font.family
                font.pixelSize: 12
                background: Rectangle { color: "transparent" }
                onTextChanged: mgrRoot.searchQuery = text
              }

              Text {
                visible: searchInput.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                font.pixelSize: 10
                color: searchClearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.70) : Qt.rgba(1, 1, 1, 0.45)
                Behavior on color { ColorAnimation { duration: 100 } }
                MouseArea {
                  id: searchClearMouse
                  anchors.fill: parent
                  anchors.margins: -4
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: searchInput.text = ""
                }
              }
            }
          }

          // Flexible space
          Item {
            width: Math.max(10, parent.width - 180 - 220 - newNoteBtn.width - closeBtn.width - parent.spacing * 4 - parent.leftPadding - parent.rightPadding)
            height: 1
          }

          // New Note Button
          Rectangle {
            id: newNoteBtn
            anchors.verticalCenter: parent.verticalCenter
            width: newNoteLabel.implicitWidth + 18
            height: 28
            radius: 7
            color: newNoteMouse.containsPress
              ? Qt.rgba(1, 1, 1, 0.20)
              : (newNoteMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08))
            Behavior on color { ColorAnimation { duration: 100 } }
            scale: newNoteMouse.containsPress ? 0.96 : 1.0
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

            Row {
              anchors.centerIn: parent
              spacing: 4

              Text {
                text: "+"
                color: "#FFFFFF"
                font.family: Style.font.family
                font.pixelSize: 13
                font.bold: true
              }

              Text {
                id: newNoteLabel
                text: "New Note"
                color: "#FFFFFF"
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: true
              }
            }

            MouseArea {
              id: newNoteMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: mgrRoot.newNoteRequested()
            }
          }

          // Close Button
          Rectangle {
            id: closeBtn
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: 7
            color: closeMouse.containsPress
              ? Qt.rgba(1, 1, 1, 0.20)
              : (closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent")
            Behavior on color { ColorAnimation { duration: 100 } }
            scale: closeMouse.containsPress ? 0.92 : 1.0
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

            Text {
              anchors.centerIn: parent
              text: "✕"
              color: Qt.rgba(1, 1, 1, 0.70)
              font.pixelSize: 12
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: mgrRoot.close()
            }
          }
        }
      }

      // Horizontal Divider — soft edge, not hard line
      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(1, 1, 1, 0.06)
      }

      // TWO-PANE BODY: Left Sidebar + Right Detail
      Row {
        width: parent.width
        height: parent.height - 49
        spacing: 0

        // LEFT SIDEBAR (Notes List)
        Column {
          width: 260
          height: parent.height
          spacing: 0

          ListView {
            id: listView
            width: parent.width
            height: parent.height - 28
            clip: true
            model: mgrRoot.filteredNotes

            delegate: Rectangle {
              id: noteRow
              width: listView.width
              height: 52
              color: mgrRoot.selectedNoteId === modelData.id
                ? Qt.rgba(1, 1, 1, 0.10)
                : (rowHover.containsPress ? Qt.rgba(1, 1, 1, 0.08)
                  : (rowHover.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"))
              Behavior on color { ColorAnimation { duration: 120 } }

              readonly property var pal: Model.colorByIndex(modelData.color)
              readonly property var counts: Model.taskCounts(modelData.body)

              Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                // Colored Dash (width 3.5, height 32)
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 3.5
                  height: 32
                  radius: 2
                  color: noteRow.pal.dash
                }

                // Text info
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 24
                  spacing: 2

                  // Title
                  Text {
                    text: Model.displayTitle(modelData)
                    color: mgrRoot.selectedNoteId === modelData.id ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.85)
                    font.family: Style.font.family
                    font.pixelSize: 13
                    font.weight: mgrRoot.selectedNoteId === modelData.id ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  // Subtitle: Time + Task count + Snippet
                  Row {
                    width: parent.width
                    spacing: 6

                    Text {
                      text: Model.ago(modelData.updated_at)
                      color: Qt.rgba(1, 1, 1, 0.45)
                      font.family: Style.font.family
                      font.pixelSize: 10
                    }

                    // Task badge
                    Rectangle {
                      visible: noteRow.counts.total > 0
                      width: taskCountLabel.implicitWidth + 8
                      height: 14
                      radius: 4
                      color: noteRow.counts.done === noteRow.counts.total
                        ? Qt.rgba(0.2, 0.8, 0.4, 0.25)
                        : Qt.rgba(1, 1, 1, 0.10)

                      Text {
                        id: taskCountLabel
                        anchors.centerIn: parent
                        text: (noteRow.counts.done === noteRow.counts.total ? "✓ " : "") +
                              noteRow.counts.done + "/" + noteRow.counts.total
                        color: noteRow.counts.done === noteRow.counts.total ? "#68D391" : Qt.rgba(1, 1, 1, 0.65)
                        font.family: Style.font.family
                        font.pixelSize: 9
                        font.bold: true
                      }
                    }

                    // Preview Snippet
                    Text {
                      visible: text !== ""
                      text: Model.notePreview(modelData.body)
                      color: Qt.rgba(1, 1, 1, 0.35)
                      font.family: Style.font.family
                      font.pixelSize: 10
                      elide: Text.ElideRight
                      width: parent.width - 100
                    }
                  }
                }
              }

              MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (mgrRoot.selectedNoteId !== modelData.id) {
                    detailEditor.flush()
                    mgrRoot.selectedNoteId = modelData.id
                    mgrRoot.snapshotRequested(modelData.id)
                  }
                }
              }
            }
          }

          // Sidebar Footer: Count Badge
          Rectangle {
            width: parent.width
            height: 28
            color: Qt.rgba(1, 1, 1, 0.015)

            Text {
              anchors.centerIn: parent
              text: mgrRoot.filteredNotes.length + " " + (mgrRoot.filteredNotes.length === 1 ? "note" : "notes")
              color: Qt.rgba(1, 1, 1, 0.35)
              font.family: Style.font.family
              font.pixelSize: 10
              font.weight: Font.Medium
              font.letterSpacing: 0.3
            }
          }
        }

        // Vertical Divider
        Rectangle {
          width: 1
          height: parent.height
          color: Qt.rgba(1, 1, 1, 0.06)
        }

        // RIGHT DETAIL PANE
        Item {
          id: detailPane
          width: parent.width - 261
          height: parent.height

          // Empty state when no note selected
          Item {
            visible: mgrRoot.selectedNote === null
            anchors.fill: parent

            Column {
              anchors.centerIn: parent
              spacing: 10

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "≡"
                font.pixelSize: 28
                font.weight: Font.Light
                color: Qt.rgba(1, 1, 1, 0.20)
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: mgrRoot.filteredNotes.length === 0 ? "No notes found" : "Select a note"
                color: Qt.rgba(1, 1, 1, 0.40)
                font.family: Style.font.family
                font.pixelSize: 13
                font.weight: Font.Medium
              }
            }
          }

          // Note Detail Editor
          Item {
            id: detailContainer
            visible: mgrRoot.selectedNote !== null
            anchors.fill: parent

            readonly property var curPal: mgrRoot.selectedNote ? Model.colorByIndex(mgrRoot.selectedNote.color) : Model.COLORS[0]

            // Paper Background matching note's color
            Rectangle {
              anchors.fill: parent
              color: detailContainer.curPal.paper
              radius: 12
              // Cover top corners so only bottom-right follows card radius
              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.radius
                color: parent.color
              }
            }

            Column {
              anchors.fill: parent
              spacing: 0

              // Detail Header Bar
              Rectangle {
                width: parent.width
                height: 38
                color: Qt.rgba(
                  parseInt(detailContainer.curPal.dash.substring(1,3), 16)/255,
                  parseInt(detailContainer.curPal.dash.substring(3,5), 16)/255,
                  parseInt(detailContainer.curPal.dash.substring(5,7), 16)/255, 0.15)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: 14
                  anchors.rightMargin: 14
                  spacing: 6

                  // 8 Color Swatches (tight cluster)
                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Repeater {
                      model: Model.COLORS
                      delegate: Item {
                        width: 12
                        height: 38
                        Rectangle {
                          anchors.centerIn: parent
                          width: 10
                          height: 10
                          radius: 5
                          color: modelData.dash
                          Rectangle {
                            anchors.fill: parent
                            anchors.margins: -2
                            radius: width / 2
                            color: "transparent"
                            border.color: mgrRoot.selectedNote && mgrRoot.selectedNote.color === index
                              ? detailContainer.curPal.ink
                              : "transparent"
                            border.width: 1.5
                          }
                        }
                        MouseArea {
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            if (mgrRoot.selectedNote) {
                              mgrRoot.colorChanged(mgrRoot.selectedNote.id, index)
                            }
                          }
                        }
                      }
                    }
                  }

                  // Flexible spacer
                  Item {
                    width: Math.max(8, parent.width - 12 * 8 - 3 * 7 - 6 * 5 - 24 - (histLabel.implicitWidth + 14) - (archLabel.implicitWidth + 14) - 24)
                    height: 1
                  }

                  // Pin/Unpin button
                  Rectangle {
                    id: pinBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 22
                    radius: 6
                    color: Qt.rgba(
                      parseInt(detailContainer.curPal.ink.substring(1,3), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(3,5), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(5,7), 16)/255,
                      pinMouse.containsPress ? 0.16 : 0.08)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    scale: pinMouse.containsPress ? 0.92 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    Canvas {
                      anchors.centerIn: parent
                      width: 14
                      height: 14
                      renderTarget: Canvas.FramebufferObject
                      onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var ink = detailContainer.curPal.ink
                        var isPinned = mgrRoot.selectedNote && mgrRoot.selectedNote.pinned === 1
                        ctx.strokeStyle = Qt.rgba(
                          parseInt(ink.substring(1,3), 16)/255,
                          parseInt(ink.substring(3,5), 16)/255,
                          parseInt(ink.substring(5,7), 16)/255, isPinned ? 0.95 : 0.60)
                        ctx.fillStyle = ctx.strokeStyle
                        ctx.lineWidth = 1.3
                        ctx.lineCap = "round"
                        if (isPinned) {
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
                      }
                    }

                    MouseArea {
                      id: pinMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (mgrRoot.selectedNote) mgrRoot.pinToggled(mgrRoot.selectedNote.id)
                      }
                    }
                  }

                  // History / rollback button
                  Rectangle {
                    id: histBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: histLabel.implicitWidth + 14
                    height: 22
                    radius: 6
                    color: mgrRoot.historyOpen ? Qt.rgba(
                      parseInt(detailContainer.curPal.ink.substring(1,3), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(3,5), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(5,7), 16)/255, 0.20) : Qt.rgba(
                      parseInt(detailContainer.curPal.ink.substring(1,3), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(3,5), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(5,7), 16)/255,
                      histMouse.containsPress ? 0.16 : 0.08)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    scale: histMouse.containsPress ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    Text {
                      id: histLabel
                      anchors.centerIn: parent
                      text: "↺ History"
                      color: detailContainer.curPal.ink
                      font.family: Style.font.family
                      font.pixelSize: 11
                    }

                    MouseArea {
                      id: histMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (mgrRoot.historyOpen) {
                          mgrRoot.historyOpen = false
                        } else if (mgrRoot.selectedNote) {
                          mgrRoot.historyRequested(mgrRoot.selectedNote.id)
                          mgrRoot.historyOpen = true
                        }
                      }
                    }
                  }

                  // Archive / Restore button
                  Rectangle {
                    id: archBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: archLabel.implicitWidth + 14
                    height: 22
                    radius: 6
                    color: Qt.rgba(
                      parseInt(detailContainer.curPal.ink.substring(1,3), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(3,5), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(5,7), 16)/255,
                      archMouse.containsPress ? 0.16 : 0.08)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    scale: archMouse.containsPress ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    Text {
                      id: archLabel
                      anchors.centerIn: parent
                      text: mgrRoot.selectedNote && mgrRoot.selectedNote.archived === 1 ? "Restore" : "Archive"
                      color: detailContainer.curPal.ink
                      font.family: Style.font.family
                      font.pixelSize: 11
                    }

                    MouseArea {
                      id: archMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (mgrRoot.selectedNote) {
                          mgrRoot.archiveToggled(mgrRoot.selectedNote.id, mgrRoot.selectedNote.archived === 0)
                        }
                      }
                    }
                  }

                  // Delete button
                  Rectangle {
                    id: delBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 22
                    radius: 6
                    color: Qt.rgba(
                      parseInt(detailContainer.curPal.ink.substring(1,3), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(3,5), 16)/255,
                      parseInt(detailContainer.curPal.ink.substring(5,7), 16)/255,
                      delMouse.containsPress ? 0.16 : 0.08)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    scale: delMouse.containsPress ? 0.92 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    Text {
                      anchors.centerIn: parent
                      text: "✕"
                      font.pixelSize: 11
                      font.bold: true
                      color: detailContainer.curPal ? detailContainer.curPal.ink : "#222222"
                    }

                    MouseArea {
                      id: delMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (mgrRoot.selectedNote) mgrRoot.deleteRequested(mgrRoot.selectedNote.id)
                      }
                    }
                  }
                }
              }

              // Note Text Area
              ScrollView {
                id: detailScroll
                width: parent.width
                height: parent.height - 38
                clip: true

                TextArea {
                  id: detailTextArea
                  color: detailContainer.curPal.ink
                  font.family: mgrRoot.fontFamily !== "" ? mgrRoot.fontFamily : Style.font.family
                  font.pixelSize: mgrRoot.fontSize
                  wrapMode: TextArea.Wrap
                  textFormat: TextArea.PlainText
                  selectByMouse: true
                  leftPadding: 16
                  rightPadding: 16
                  topPadding: 12
                  bottomPadding: 12
                  background: Rectangle { color: "transparent" }

                  onTextChanged: {
                    if (loadedDetailNoteId >= 0) {
                      mgrAutosaveTimer.restart()
                    }
                  }

                  // Task Checkbox Clicking
                  MouseArea {
                    anchors.fill: parent
                    propagateComposedEvents: true
                    acceptedButtons: Qt.LeftButton
                    onClicked: function(mouse) {
                      var pos = detailTextArea.positionAt(mouse.x, mouse.y)
                      var text = detailTextArea.text
                      var lineStart = text.lastIndexOf("\n", Math.max(0, pos - 1)) + 1
                      var lineEnd = text.indexOf("\n", pos)
                      if (lineEnd === -1) lineEnd = text.length
                      var line = text.substring(lineStart, lineEnd)

                      var pLen = Model.taskPrefixLength(line)
                      if (pLen > 0 && pos >= lineStart && pos <= lineStart + pLen) {
                        var savedY = detailScroll.contentItem ? detailScroll.contentItem.contentY : 0
                        var toggled = Model.toggleTaskLine(line)
                        detailTextArea.remove(lineStart, lineEnd)
                        detailTextArea.insert(lineStart, toggled)
                        detailTextArea.cursorPosition = Math.min(detailTextArea.text.length, pos + (toggled.length - line.length))
                        if (detailScroll.contentItem) detailScroll.contentItem.contentY = savedY
                        mgrAutosaveTimer.restart()
                        mouse.accepted = true
                        return
                      }
                      mouse.accepted = false
                    }
                  }

                  // Enter task continuation and shortcuts
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))) {
                        var full = detailTextArea.text
                        var cur = detailTextArea.cursorPosition
                        var lineStart = full.lastIndexOf("\n", Math.max(0, cur - 1)) + 1
                        var lineEnd = full.indexOf("\n", cur)
                        if (lineEnd === -1) lineEnd = full.length
                        var line = full.substring(lineStart, lineEnd)

                        var cont = Model.listContinuation(line)
                        if (cont) {
                          var savedY = detailScroll.contentItem ? detailScroll.contentItem.contentY : 0
                          if (cont.isEmpty) {
                            if (cont.indent.length >= 2) {
                              detailTextArea.remove(lineStart, lineStart + 2)
                              detailTextArea.cursorPosition = Math.max(lineStart, cur - 2)
                            } else {
                              detailTextArea.remove(lineStart, lineEnd)
                              detailTextArea.cursorPosition = lineStart
                            }
                            if (detailScroll.contentItem) detailScroll.contentItem.contentY = savedY
                            mgrAutosaveTimer.restart()
                            event.accepted = true
                            return
                          }
                          detailTextArea.insert(cur, cont.nextPrefix)
                          detailTextArea.cursorPosition = cur + cont.nextPrefix.length
                          if (detailScroll.contentItem) detailScroll.contentItem.contentY = savedY
                          mgrAutosaveTimer.restart()
                          event.accepted = true
                          return
                        }
                      }
                    }

                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_T) {
                      detailEditor.toggleTask()
                      event.accepted = true
                      return
                    }

                    // Ctrl+V: Convert markdown task syntax from pasted content
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                      Qt.callLater(function() {
                        var after = detailTextArea.text
                        var converted = Model.tasksFromMarkdown(after)
                        if (converted !== after) {
                          var curPos = detailTextArea.cursorPosition
                          var newCursor = Model.tasksFromMarkdown(after.substring(0, curPos)).length
                          var savedY = detailScroll.contentItem ? detailScroll.contentItem.contentY : 0
                          detailTextArea.text = converted
                          detailTextArea.cursorPosition = newCursor
                          if (detailScroll.contentItem) detailScroll.contentItem.contentY = savedY
                          mgrAutosaveTimer.restart()
                        }
                      })
                    }
                  }
                }
              }
            }
          }
        }

        // History / rollback popup
        Rectangle {
          id: historyPopup
          visible: mgrRoot.historyOpen && mgrRoot.selectedNote !== null
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: 44
          anchors.rightMargin: 12
          width: 340
          height: mgrRoot.historyList.length === 0 ? 120 : Math.min(360, 116 + histListCol.implicitHeight)
          radius: 12
          color: Color.menu.background || Qt.rgba(0.12, 0.12, 0.14, 0.98)
          border.color: Color.menu.border || Qt.rgba(1, 1, 1, 0.10)
          border.width: 1
          z: 50

          // Origin-aware scale-in from the history button (top-right)
          transformOrigin: Item.TopRight
          scale: mgrRoot.historyOpen ? 1.0 : 0.95
          opacity: mgrRoot.historyOpen ? 1.0 : 0.0
          Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

          // Drop shadow
          Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            z: -1
            radius: parent.radius + 1
            color: "transparent"
            border.color: Qt.rgba(0, 0, 0, 0.45)
            border.width: 3
          }

          // Click-outside-to-close (only swallows inside popup)
          MouseArea {
            anchors.fill: parent
            onClicked: mgrRoot.historyOpen = false
          }

          Column {
            id: histCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header: title + close
            Row {
              width: parent.width
              spacing: 6

              Text {
                id: histTitleLabel
                anchors.verticalCenter: parent.verticalCenter
                text: "↺ Note history"
                color: "#FFFFFF"
                font.family: Style.font.family
                font.pixelSize: 13
                font.bold: true
              }

              Item {
                width: Math.max(4, parent.width - histTitleLabel.implicitWidth - histCloseBtn.width - 6 - histCountLabel.implicitWidth - 12)
                height: 1
              }

              Text {
                id: histCountLabel
                anchors.verticalCenter: parent.verticalCenter
                visible: mgrRoot.historyList.length > 0
                text: mgrRoot.historyList.length + (mgrRoot.historyList.length === 1 ? " version" : " versions")
                color: Qt.rgba(1, 1, 1, 0.40)
                font.family: Style.font.family
                font.pixelSize: 10
              }

              Rectangle {
                id: histCloseBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: 5
                color: histCloseMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06)
                Text {
                  anchors.centerIn: parent
                  text: "✕"
                  color: Qt.rgba(1, 1, 1, 0.60)
                  font.pixelSize: 10
                }
                MouseArea {
                  id: histCloseMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: mgrRoot.historyOpen = false
                }
              }
            }

            Text {
              visible: mgrRoot.historyList.length > 0
              text: "Click a version to restore it"
              color: Qt.rgba(1, 1, 1, 0.45)
              font.family: Style.font.family
              font.pixelSize: 11
            }

            Text {
              visible: mgrRoot.historyList.length === 0
              text: "No older versions yet — one is saved each time you open this note."
              color: Qt.rgba(1, 1, 1, 0.45)
              font.family: Style.font.family
              font.pixelSize: 11
              wrapMode: Text.WordWrap
              width: parent.width
            }

            ScrollView {
              visible: mgrRoot.historyList.length > 0
              width: parent.width
              height: Math.min(254, histListCol.implicitHeight)
              clip: true

              Column {
                id: histListCol
                width: histCol.width - 4
                spacing: 4

                Repeater {
                  model: mgrRoot.historyList
                  delegate: Rectangle {
                    width: histListCol.width
                    height: 52
                    radius: 7
                    color: histRowMouse.containsPress
                      ? Qt.rgba(1, 1, 1, 0.16)
                      : (histRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04))
                    border.color: histRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    scale: histRowMouse.containsPress ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: 10
                      anchors.rightMargin: 8
                      spacing: 8

                      // Version index badge
                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        radius: 11
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Text {
                          anchors.centerIn: parent
                          text: (index + 1)
                          color: Qt.rgba(1, 1, 1, 0.60)
                          font.family: Style.font.family
                          font.pixelSize: 10
                          font.bold: true
                        }
                      }

                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 30 - (histRowMouse.containsMouse ? 56 : 0)
                        spacing: 2

                        Text {
                          text: Model.displayTitle(modelData)
                          color: "#FFFFFF"
                          font.family: Style.font.family
                          font.pixelSize: 12
                          elide: Text.ElideRight
                          width: parent.width
                        }

                        Row {
                          width: parent.width
                          spacing: 6
                          Text {
                            text: Model.ago(modelData.updated_at)
                            color: Qt.rgba(1, 1, 1, 0.40)
                            font.family: Style.font.family
                            font.pixelSize: 10
                          }
                          Text {
                            visible: text !== ""
                            text: Model.notePreview(modelData.body)
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font.family: Style.font.family
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            width: parent.width - 60
                          }
                        }
                      }

                      // Restore hint (hover)
                      Text {
                        visible: histRowMouse.containsMouse
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↺ Restore"
                        color: "#FFFFFF"
                        font.family: Style.font.family
                        font.pixelSize: 10
                        font.bold: true
                      }
                    }

                    MouseArea {
                      id: histRowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        var n = mgrRoot.selectedNote
                        if (n) {
                          var t = String(modelData.title || "").trim() !== "" ? modelData.title : Model.derivedTitle(modelData.body)
                          mgrRoot.historyRestoreRequested(n.id, t, modelData.body || "")
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  QtObject {
    id: detailEditor
    function flush() {
      mgrAutosaveTimer.stop()
      // Use loadedDetailNoteId, not selectedNote — selectedNote is a binding
      // that can be null by the time flush runs (e.g. after filteredNotes
      // recomputes). loadedDetailNoteId always tracks what's in the text area.
      if (loadedDetailNoteId >= 0 && detailTextArea) {
        var tit = Model.derivedTitle(detailTextArea.text)
        mgrRoot.saveRequested(loadedDetailNoteId, tit, detailTextArea.text)
      }
    }
    function toggleTask() {
      var full = detailTextArea.text
      var selStart = detailTextArea.selectionStart
      var selEnd = detailTextArea.selectionEnd
      var savedY = detailScroll.contentItem ? detailScroll.contentItem.contentY : 0

      if (selEnd > selStart) {
        var lineStart = full.lastIndexOf("\n", Math.max(0, selStart - 1)) + 1
        var lineEnd = full.indexOf("\n", selEnd)
        if (lineEnd === -1) lineEnd = full.length
        var block = full.substring(lineStart, lineEnd)
        var newBlock = Model.toggleTaskBlock(block)
        detailTextArea.remove(lineStart, lineEnd)
        detailTextArea.insert(lineStart, newBlock)
        detailTextArea.select(lineStart, lineStart + newBlock.length)
        if (detailScroll.contentItem) detailScroll.contentItem.contentY = savedY
        mgrAutosaveTimer.restart()
        return
      }

      var cur = detailTextArea.cursorPosition
      var ls = full.lastIndexOf("\n", Math.max(0, cur - 1)) + 1
      var le = full.indexOf("\n", cur)
      if (le === -1) le = full.length
      var line = full.substring(ls, le)
      var toggled = Model.toggleTaskLine(line)
      detailTextArea.remove(ls, le)
      detailTextArea.insert(ls, toggled)
      detailTextArea.cursorPosition = Math.min(detailTextArea.text.length, cur + (toggled.length - line.length))
      if (detailScroll.contentItem) detailScroll.contentItem.contentY = savedY
      mgrAutosaveTimer.restart()
    }
  }

  Timer {
    id: mgrAutosaveTimer
    interval: 250
    onTriggered: {
      if (loadedDetailNoteId >= 0 && detailTextArea) {
        var tit = Model.derivedTitle(detailTextArea.text)
        mgrRoot.saveRequested(loadedDetailNoteId, tit, detailTextArea.text)
      }
    }
  }
}
