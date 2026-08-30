import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "NotyModel.js" as Model

// Noty — Sticky notes that live at the edge of your screen.
// Faithful, pixel-perfect, high-performance port of aimen08/noty to Linux/Quickshell.
//
// Three states, one movement:
//   1. Rest     — A 12 pt pill of coloured dashes on the screen edge
//   2. Fan      — Notes shingle down the edge 45ms apart with a 3° lean
//   3. Expanded — Note slides clear of the deck, carrying its tab down the gutter
//
// Features:
//   - Local SQLite database (~/.local/share/jot/notes.db)
//   - Real interactive checkbox tasks (☐ / ☑) with Return auto-continuation
//   - 8 rich pastel paper colors with top-to-bottom light gradients
//   - 250ms debounced autosave
//   - 10-second deletion undo toast with circular countdown timer
//   - Multi-display support (one dormant pill per screen, activates on pointer enter)
//   - All Notes & Archive Library window with live search and markdown support
//   - Right-click context menus with submenus (deck style, note font, size, export, import)
//   - Export (Markdown / Plaintext / Single file / .stickies JSON) & Import
//   - Click-through input masking: NO intrusive fullscreen modal blocking
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string dbDir: home + "/.local/share/jot"
  readonly property string dbPath: dbDir + "/notes.db"
  readonly property string settingsPath: dbDir + "/settings.json"

  // User Preferences
  property bool onRight: true
  property string deckStyle: "tabs" // "tabs" | "compact"
  property string noteFont: "iA Writer Quattro S"
  property real noteFontSize: 13.5
  property bool showAllTabs: false
  property bool deckVisible: true

  // Deck State
  property string deckState: "rest" // "rest" | "fan" | "expanded"
  property int activeNoteId: -1
  property int activeNoteIndex: 0
  property var activeScreen: null
  property int revealTick: 0

  // Window modals
  property bool managerOpen: false
  property string managerInitialMode: "all"

  // Note store list
  property var notes: []
  property var activeNotes: []
  property var archivedNotes: []

  // Pending delete for 10s undo toast
  property var pendingDeletedNote: null

  // ----------------------------------------------------------------- Settings

  FileView {
    id: settingsFile
    path: root.settingsPath
    onLoaded: {
      try {
        var s = JSON.parse(text || "{}")
        if (s.onRight !== undefined) root.onRight = s.onRight
        if (s.deckStyle !== undefined) root.deckStyle = s.deckStyle
        if (s.noteFont !== undefined) root.noteFont = s.noteFont
        if (s.noteFontSize !== undefined) root.noteFontSize = s.noteFontSize
        if (s.deckVisible !== undefined) root.deckVisible = s.deckVisible
      } catch (e) {}
    }
  }

  function saveSettings() {
    var s = {
      onRight: root.onRight,
      deckStyle: root.deckStyle,
      noteFont: root.noteFont,
      noteFontSize: root.noteFontSize,
      deckVisible: root.deckVisible
    }
    settingsWriteProc.command = ["bash", "-c", "mkdir -p " + JSON.stringify(dbDir) + " && cat << 'EOF' > " + JSON.stringify(settingsPath) + "\n" + JSON.stringify(s, null, 2) + "\nEOF"]
    settingsWriteProc.running = true
  }

  Process { id: settingsWriteProc }

  // ----------------------------------------------------------------- Database

  property var pendingRowsCallback: null

  Process {
    id: dbRead
    stdout: StdioCollector {
      id: readOut
      waitForEnd: true
      onStreamFinished: {
        var rows = Model.parseRows(readOut.text)
        var cb = root.pendingRowsCallback
        root.pendingRowsCallback = null
        if (typeof cb === "function") cb(rows)
      }
    }
    onExited: function(code) {
      if (code !== 0) root.pendingRowsCallback = null
    }
  }

  function runSelect(sql, cb) {
    root.pendingRowsCallback = cb
    dbRead.command = ["sqlite3", "-json", dbPath, sql]
    dbRead.running = true
  }

  Process {
    id: dbWrite
    stdout: StdioCollector { id: writeOut; waitForEnd: true }
    onExited: function(code) {
      loadNotes()
    }
  }

  function runWrite(sql) {
    dbWrite.command = ["sqlite3", dbPath, sql]
    dbWrite.running = true
  }

  function loadNotes() {
    runSelect(Model.selectAllSql(), function(rows) {
      root.notes = rows
      var act = []
      var arch = []
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].archived === 1) arch.push(rows[i])
        else act.push(rows[i])
      }
      root.activeNotes = act
      root.archivedNotes = arch

      // If active note was deleted or vanished, collapse to fan
      if (root.activeNoteId >= 0) {
        var found = false
        for (var j = 0; j < act.length; j++) {
          if (act[j].id === root.activeNoteId) {
            found = true
            root.activeNoteIndex = j
            break
          }
        }
        if (!found) root.collapseToFan()
      }
    })
  }

  function initDatabase() {
    var initCommands = [
      "mkdir -p " + JSON.stringify(dbDir),
      "sqlite3 " + JSON.stringify(dbPath) + " " + JSON.stringify(Model.initSql()),
      // Migrate legacy string colors if present
      "sqlite3 " + JSON.stringify(dbPath) + " \"UPDATE notes SET color=0 WHERE color='yellow' OR color='lemon';\"",
      "sqlite3 " + JSON.stringify(dbPath) + " \"UPDATE notes SET color=1 WHERE color='peach';\"",
      "sqlite3 " + JSON.stringify(dbPath) + " \"UPDATE notes SET color=2 WHERE color='rose';\"",
      "sqlite3 " + JSON.stringify(dbPath) + " \"UPDATE notes SET color=3 WHERE color='lilac';\"",
      "sqlite3 " + JSON.stringify(dbPath) + " \"UPDATE notes SET color=4 WHERE color='sky';\"",
      "sqlite3 " + JSON.stringify(dbPath) + " \"UPDATE notes SET color=5 WHERE color='mint';\"",
      "sqlite3 " + JSON.stringify(dbPath) + " \"UPDATE notes SET color=6 WHERE color='sand';\"",
      "sqlite3 " + JSON.stringify(dbPath) + " \"UPDATE notes SET color=7 WHERE color='slate';\""
    ].join(" && ")

    dbWrite.command = ["bash", "-c", initCommands]
    dbWrite.running = true
  }

  Component.onCompleted: {
    initDatabase()
  }

  // ----------------------------------------------------------- State Machine

  function expandNote(noteId, index, screen) {
    if (screen) root.activeScreen = screen
    var nid = Number(noteId)
    root.activeNoteId = nid
    if (index !== undefined && index >= 0) root.activeNoteIndex = index
    else {
      for (var i = 0; i < root.activeNotes.length; i++) {
        if (Number(root.activeNotes[i].id) === nid) { root.activeNoteIndex = i; break }
      }
    }
    root.deckState = "expanded"
    fanIdleTimer.stop()
    noteIdleTimer.restart()
  }

  function collapseToFan() {
    root.activeNoteId = -1
    root.deckState = "fan"
    fanIdleTimer.restart()
    noteIdleTimer.stop()
    root.revealTick++
  }

  function collapseToRest() {
    root.deckState = "rest"
    root.activeNoteId = -1
    root.showAllTabs = false
    fanIdleTimer.stop()
    noteIdleTimer.stop()
  }

  function noteActivity() {
    if (root.deckState === "expanded") {
      noteIdleTimer.restart()
    } else if (root.deckState === "fan") {
      fanIdleTimer.restart()
    }
  }

  readonly property var currentActiveNote: {
    if (root.activeNoteId < 0) return null
    var nid = Number(root.activeNoteId)
    for (var i = 0; i < root.activeNotes.length; i++) {
      if (Number(root.activeNotes[i].id) === nid) return root.activeNotes[i]
    }
    return null
  }

  readonly property bool isOpenNotePinned: {
    return currentActiveNote ? (currentActiveNote.pinned === 1) : false
  }

  // Idle Timers matching Noty
  Timer {
    id: fanIdleTimer
    interval: Model.GEOM.fanIdleTimeout * 1000 // 4 seconds
    onTriggered: {
      if (root.deckState === "fan") root.collapseToRest()
    }
  }

  Timer {
    id: noteIdleTimer
    interval: Model.GEOM.noteIdleTimeout * 1000 // 60 seconds
    onTriggered: {
      if (root.deckState === "expanded" && !root.isOpenNotePinned) {
        root.collapseToRest()
      }
    }
  }

  // ------------------------------------------------------------- CRUD Actions

  function newNote() {
    var sql = Model.insertSql("", "", 0) + " SELECT last_insert_rowid();"
    runSelect(sql, function(rows) {
      loadNotes()
      if (rows && rows.length > 0) {
        var newId = rows[0]["last_insert_rowid()"] || rows[0].id
        if (newId) {
          Qt.callLater(function() { root.expandNote(newId, 0) })
        }
      }
    })
  }

  function saveNote(id, title, body) {
    runWrite(Model.updateSql(id, title, body))
  }

  function setNoteColor(id, colorIdx) {
    runWrite(Model.setColorSql(id, colorIdx))
  }

  function toggleNotePin(id) {
    for (var i = 0; i < root.notes.length; i++) {
      if (root.notes[i].id === id) {
        var nextPin = root.notes[i].pinned === 1 ? 0 : 1
        runWrite(Model.setPinnedSql(id, nextPin))
        return
      }
    }
  }

  function archiveNote(id, toArchived) {
    runWrite(Model.archiveSql(id, toArchived !== undefined ? toArchived : true))
    if (root.activeNoteId === id) root.collapseToFan()
  }

  function deleteNoteWithUndo(id) {
    var target = null
    for (var i = 0; i < root.notes.length; i++) {
      if (root.notes[i].id === id) { target = root.notes[i]; break }
    }
    if (!target) return

    // Immediately remove from display and show undo toast
    if (root.activeNoteId === id) root.collapseToFan()
    undoToast.start(target)
    runWrite(Model.deleteSql(id))
  }

  function restoreDeletedNote(note) {
    if (!note) return
    runWrite(Model.restoreNoteSql(note))
  }

  function moveNoteUp(id) {
    var arr = root.activeNotes.slice()
    var idx = -1
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === id) { idx = i; break }
    }
    if (idx > 0) {
      var tmp = arr[idx]
      arr[idx] = arr[idx - 1]
      arr[idx - 1] = tmp
      root.activeNotes = arr
      var ids = arr.map(function(n) { return n.id })
      runWrite(Model.reorderNotesSql(ids))
    }
  }

  function moveNoteDown(id) {
    var arr = root.activeNotes.slice()
    var idx = -1
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === id) { idx = i; break }
    }
    if (idx >= 0 && idx < arr.length - 1) {
      var tmp = arr[idx]
      arr[idx] = arr[idx + 1]
      arr[idx + 1] = tmp
      root.activeNotes = arr
      var ids = arr.map(function(n) { return n.id })
      runWrite(Model.reorderNotesSql(ids))
    }
  }

  function reorderNotesByIndex(fromIdx, toIdx) {
    var arr = root.activeNotes.slice()
    if (fromIdx < 0 || fromIdx >= arr.length) return
    var boundedTo = Math.max(0, Math.min(arr.length - 1, toIdx))
    if (fromIdx === boundedTo) return
    var item = arr.splice(fromIdx, 1)[0]
    arr.splice(boundedTo, 0, item)
    root.activeNotes = arr
    var ids = arr.map(function(n) { return n.id })
    runWrite(Model.reorderNotesSql(ids))
  }

  // --------------------------------------------------------- Export & Import

  Process {
    id: exportImportProc
    onExited: function(code) {
      loadNotes()
    }
  }

  function exportNotes(format) {
    var exportDir = root.home + "/Documents/Noty-Export"
    var dateStamp = new Date().toISOString().replace(/[:.]/g, "-")

    if (format === "stickies_json") {
      var jsonStr = Model.exportStickiesJson(root.notes)
      var filePath = exportDir + "/Noty-Archive-" + dateStamp + ".stickies"
      exportImportProc.command = ["bash", "-c", "mkdir -p " + JSON.stringify(exportDir) + " && cat << 'EOF' > " + JSON.stringify(filePath) + "\n" + jsonStr + "\nEOF"]
      exportImportProc.running = true
    } else if (format === "single_md") {
      var mdStr = Model.exportSingleMarkdown(root.notes)
      var filePath = exportDir + "/All-Notes-" + dateStamp + ".md"
      exportImportProc.command = ["bash", "-c", "mkdir -p " + JSON.stringify(exportDir) + " && cat << 'EOF' > " + JSON.stringify(filePath) + "\n" + mdStr + "\nEOF"]
      exportImportProc.running = true
    } else if (format === "markdown_zip" || format === "text_zip") {
      var folder = exportDir + "/Notes-" + dateStamp
      var script = "mkdir -p " + JSON.stringify(folder) + "\n"
      for (var i = 0; i < root.notes.length; i++) {
        var n = root.notes[i]
        var fname = (Model.displayTitle(n).replace(/[\/\\?%*:|"<>]/g, "_") || ("Note-" + n.id)) + (format === "markdown_zip" ? ".md" : ".txt")
        var content = format === "markdown_zip" ? Model.tasksToMarkdown(n.body) : n.body
        script += "cat << 'EOF' > " + JSON.stringify(folder + "/" + fname) + "\n" + content + "\nEOF\n"
      }
      exportImportProc.command = ["bash", "-c", script]
      exportImportProc.running = true
    }
  }

  function importNotes() {
    var script = [
      "if [ -d \"$HOME/Documents/Noty-Export\" ]; then",
      "  for f in \"$HOME/Documents/Noty-Export\"/*.stickies; do",
      "    [ -f \"$f\" ] && cat \"$f\" && break",
      "  done",
      "fi"
    ].join("\n")

    var proc = Qt.createQmlObject('import Quickshell.Io; Process { property string out: ""; stdout: StdioCollector { onStreamFinished: proc.out = text } }', root)
    proc.command = ["bash", "-c", script]
    proc.onExited = function(code) {
      if (code === 0 && proc.out) {
        var imported = Model.parseStickiesJson(proc.out)
        for (var i = 0; i < imported.length; i++) {
          runWrite(Model.insertSql(imported[i].title, imported[i].body, imported[i].color))
        }
      }
    }
    proc.running = true
  }

  // ------------------------------------------------------- MULTI-SCREEN DECKS

  // One deck panel per physical screen
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: deckPanel
        required property var modelData

        screen: modelData
        visible: root.deckVisible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "omarchy-noty-deck"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.deckState === "expanded" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Full-screen, fixed-size surface with Region input masking (like notifications/OSD).
        // The surface never resizes, so Hyprland compositor never clips or squishes the expanded card.
        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        // INPUT MASK: When expanded, fullScreenDismissItem covers the entire screen to catch click-outside.
        // When resting/fanning, Region only covers the edge pill/tabs so apps below receive clicks.
        mask: Region {
          item: (root.deckState === "expanded" || root.managerOpen)
            ? fullScreenDismissItem
            : ((root.deckState === "fan") ? activeFanContainer : activePillContainer)
        }

        Item {
          id: fullScreenDismissItem
          anchors.fill: parent
        }

        // Region wrapper for expanded state covering both note editor and fan tabs
        Item {
          id: deckInteractiveRegion
          anchors.right: root.onRight ? parent.right : undefined
          anchors.left: root.onRight ? undefined : parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Model.GEOM.editorWidth + Model.GEOM.bleed + 40
        }

        // Click-outside backdrop dismiss area (active when note is open)
        MouseArea {
          id: outsideDismissArea
          anchors.fill: parent
          visible: root.deckState === "expanded"
          z: 5
          onClicked: {
            root.collapseToFan()
          }
        }

        // --- Active Interactive Area Container ---
        Item {
          id: deckContent
          anchors.fill: parent
          z: 10

          // 1. REST STATE: The 10pt Pill on screen edge
          Item {
            id: activePillContainer
            visible: root.deckState === "rest"
            opacity: root.deckState === "rest" ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

            anchors.right: root.onRight ? parent.right : undefined
            anchors.left: root.onRight ? undefined : parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Model.GEOM.pillWidth + 4
            height: Model.pillHeight(root.activeNotes.length) + 6

            // Background Frosted Pill
            Rectangle {
              id: pillBg
              anchors.right: root.onRight ? parent.right : undefined
              anchors.left: root.onRight ? undefined : parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Model.GEOM.pillWidth
              height: Model.pillHeight(root.activeNotes.length)
              radius: 5
              color: Qt.rgba(0.08, 0.08, 0.10, 0.82)
              border.color: Qt.rgba(1, 1, 1, 0.16)
              border.width: 0.5

              // Square the screen docked edge
              Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: root.onRight ? parent.right : undefined
                anchors.left: root.onRight ? undefined : parent.left
                width: 3
                color: parent.color
              }

              // Subtle ambient shadow
              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: root.onRight ? -2 : 0
                anchors.rightMargin: root.onRight ? 0 : -2
                anchors.topMargin: 1
                anchors.bottomMargin: -1
                z: -1
                radius: parent.radius
                color: Qt.rgba(0, 0, 0, 0.35)
              }

              // Coloured Dashes Column
              Column {
                anchors.centerIn: parent
                spacing: Model.GEOM.dashGap

                // Normal note dashes (up to 14)
                Repeater {
                  model: Math.min(root.activeNotes.length, Model.GEOM.maxDashes)
                  Rectangle {
                    width: Model.GEOM.dashWidth
                    height: Model.GEOM.dashHeight
                    radius: 1.75
                    color: {
                      var n = root.activeNotes[index]
                      return n ? Model.colorByIndex(n.color).dash : "#888888"
                    }
                  }
                }

                // Overflow dash
                Rectangle {
                  visible: root.activeNotes.length > Model.GEOM.maxDashes
                  width: Model.GEOM.dashWidth
                  height: Model.GEOM.dashHeight
                  radius: 1.75
                  color: Qt.rgba(1, 1, 1, 0.45)
                }

                // Empty deck dash
                Rectangle {
                  visible: root.activeNotes.length === 0
                  width: Model.GEOM.dashWidth
                  height: Model.GEOM.dashHeight
                  radius: 1.75
                  color: Qt.rgba(1, 1, 1, 0.25)
                }
              }
            }

            // Hover & Click Hit Area
            MouseArea {
              id: pillMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor

              onEntered: {
                root.activeScreen = deckPanel.screen
                if (root.deckState === "rest") {
                  root.deckState = "fan"
                  fanIdleTimer.restart()
                  root.revealTick++
                }
              }

              onClicked: function(mouse) {
                root.activeScreen = deckPanel.screen
                if (mouse.button === Qt.RightButton) {
                  var globalP = mapToItem(null, mouse.x, mouse.y)
                  contextMenu.showAt(globalP.x, globalP.y, "deck", null)
                } else {
                  if (root.deckState === "expanded") {
                    root.collapseToFan()
                  } else if (root.deckState === "rest") {
                    root.deckState = "fan"
                    fanIdleTimer.restart()
                    root.revealTick++
                  }
                }
              }
            }
          }

          // 2. FAN STATE: 45ms Shingled Tabs Deck (Remains visible during fan AND expanded)
          Item {
            id: activeFanContainer
            visible: root.deckState !== "rest"
            opacity: root.deckState !== "rest" ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

            anchors.right: root.onRight ? parent.right : undefined
            anchors.left: root.onRight ? undefined : parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Model.GEOM.tabWidth + Model.GEOM.bleed + 40

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              onEntered: root.fanActivity()
              onPositionChanged: root.fanActivity()
            }

            // Dashed Spine line hanging at the screen edge
            Canvas {
              id: spineLine
              anchors.right: root.onRight ? parent.right : undefined
              anchors.left: root.onRight ? undefined : parent.left
              anchors.rightMargin: root.onRight ? 3 : 0
              anchors.leftMargin: root.onRight ? 0 : 3
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: Math.min(parent.height - 80, fanColumnWrapper.height + 20)

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.35)
                ctx.lineWidth = 1
                ctx.setLineDash([3, 4])
                ctx.beginPath()
                ctx.moveTo(0.5, 0)
                ctx.lineTo(0.5, height)
                ctx.stroke()
              }
            }

            // Wrapper for Tabs + More + Plus Button
            Item {
              id: fanColumnWrapper
              anchors.right: root.onRight ? parent.right : undefined
              anchors.left: root.onRight ? undefined : parent.left
              anchors.rightMargin: root.onRight ? -Model.GEOM.bleed : 0
              anchors.leftMargin: root.onRight ? 0 : -Model.GEOM.bleed
              anchors.verticalCenter: parent.verticalCenter
              width: Model.GEOM.tabWidth + Model.GEOM.bleed
              height: tabsStack.implicitHeight + (fanMoreTab.visible ? (Model.GEOM.moreTabHeight + Model.GEOM.tabGap) : 0) + Model.GEOM.plusGap + Model.GEOM.plusSize

              // Tabs Column with negative spacing for the shingle
              Column {
                id: tabsStack
                anchors.top: parent.top
                anchors.right: root.onRight ? parent.right : undefined
                anchors.left: root.onRight ? undefined : parent.left

                readonly property int visibleCount: root.showAllTabs
                  ? root.activeNotes.length
                  : Math.min(root.activeNotes.length, Model.GEOM.fanLimit)
                readonly property int hiddenCount: Math.max(0, root.activeNotes.length - Model.GEOM.fanLimit)
                readonly property bool hasMoreTab: !root.showAllTabs && hiddenCount > 0
                readonly property bool hasLessTab: root.showAllTabs && root.activeNotes.length > Model.GEOM.fanLimit

                readonly property real itemHeight: pitch + Model.GEOM.tabLap
                readonly property real pitch: {
                  var p = 80.0
                  var maxH = deckPanel.height * Model.GEOM.heightBudget
                  var count = Math.max(1, visibleCount)
                  if (count * p + Model.GEOM.tabLap > maxH) {
                    p = Math.max(36.0, (maxH - Model.GEOM.tabLap) / count)
                  }
                  return p
                }

                spacing: root.deckStyle === "compact" ? Model.GEOM.chipGap : (pitch - itemHeight)

                // Active note tabs
                Repeater {
                  model: tabsStack.visibleCount
                  delegate: NotyTab {
                    note: root.activeNotes[index]
                    isOpen: root.activeNoteId === (root.activeNotes[index] ? root.activeNotes[index].id : -1)
                    onRight: root.onRight
                    isCompact: root.deckStyle === "compact"
                    fontFamily: root.noteFont
                    tabHeight: tabsStack.itemHeight
                    strip: tabsStack.pitch
                    stagingIndex: index
                    revealed: root.deckState !== "rest"

                    onClicked: {
                      if (root.deckState === "expanded") {
                        root.collapseToFan()
                      } else {
                        if (isOpen) {
                          root.collapseToFan()
                        } else {
                          root.expandNote(note.id, index, deckPanel.screen)
                        }
                      }
                    }

                    onContextMenuRequested: function(gx, gy) {
                      contextMenu.showAt(gx, gy, "tab", note)
                    }

                    onReorderRequested: function(fromIdx, toIdx) {
                      root.reorderNotesByIndex(fromIdx, toIdx)
                    }
                  }
                }

                // Empty deck "NEW NOTE" tab
                NotyTab {
                  visible: root.activeNotes.length === 0
                  note: ({ id: -1, title: "", body: "", color: 0, pinned: 0 })
                  isOpen: false
                  onRight: root.onRight
                  isCompact: root.deckStyle === "compact"
                  fontFamily: root.noteFont
                  tabHeight: tabsStack.itemHeight
                  strip: tabsStack.pitch
                  stagingIndex: 0
                  revealed: root.deckState !== "rest"
                  emptyLabel: "NEW NOTE"
                  onClicked: {
                    if (root.deckState === "expanded") {
                      root.collapseToFan()
                    } else {
                      root.newNote()
                    }
                  }
                }
              }

              // "+N more" / "− Less" tab (anchored cleanly below tabsStack)
              NotyTab {
                id: fanMoreTab
                visible: tabsStack.hasMoreTab || tabsStack.hasLessTab
                anchors.top: tabsStack.bottom
                anchors.topMargin: Model.GEOM.tabGap
                anchors.right: root.onRight ? parent.right : undefined
                anchors.left: root.onRight ? undefined : parent.left
                note: ({
                  id: -2,
                  title: tabsStack.hasLessTab ? "− LESS" : ("+" + tabsStack.hiddenCount),
                  body: "",
                  color: 0,
                  pinned: 0
                })
                isOpen: false
                onRight: root.onRight
                isCompact: root.deckStyle === "compact"
                fontFamily: root.noteFont
                height: Model.GEOM.moreTabHeight
                strip: Model.GEOM.moreTabHeight
                stagingIndex: tabsStack.visibleCount
                revealed: root.deckState !== "rest"
                isMoreTab: true
                moreCount: tabsStack.hasLessTab ? 0 : tabsStack.hiddenCount
                emptyLabel: tabsStack.hasLessTab ? "− LESS" : ""
                onClicked: {
                  if (root.deckState === "expanded") {
                    root.collapseToFan()
                  } else {
                    root.showAllTabs = !root.showAllTabs
                  }
                }
              }

              // Floating Plus Button: ALWAYS BELOW all tabs, NEVER overlapping!
              Item {
                id: plusButtonItem
                anchors.top: fanMoreTab.visible ? fanMoreTab.bottom : tabsStack.bottom
                anchors.topMargin: Model.GEOM.plusGap
                anchors.right: root.onRight ? parent.right : undefined
                anchors.left: root.onRight ? undefined : parent.left
                anchors.rightMargin: root.onRight ? (4 + Model.GEOM.bleed) : 0
                anchors.leftMargin: root.onRight ? 0 : (4 + Model.GEOM.bleed)
                width: Model.GEOM.plusSize
                height: Model.GEOM.plusSize

                Rectangle {
                  id: plusCircle
                  anchors.fill: parent
                  radius: width / 2
                  color: Qt.rgba(0.18, 0.18, 0.20, 0.90)
                  border.color: Qt.rgba(1, 1, 1, 0.18)
                  border.width: 1

                  scale: plusMouse.pressed ? 0.92 : (plusMouse.containsMouse ? 1.12 : 1.0)
                  Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                  Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Qt.rgba(1, 1, 1, 0.90)
                    font.family: Style.font.family
                    font.pixelSize: 15
                    font.bold: true
                  }
                }

                MouseArea {
                  id: plusMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.deckState === "expanded") {
                      root.collapseToFan()
                    } else {
                      root.newNote()
                    }
                  }
                }
              }
            }

            // Mouse hover tracker
            MouseArea {
              anchors.fill: parent
              anchors.margins: -15
              hoverEnabled: true
              acceptedButtons: Qt.RightButton
              z: -1
              onEntered: fanIdleTimer.restart()
              onExited: fanIdleTimer.restart()
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  var gp = mapToItem(null, mouse.x, mouse.y)
                  contextMenu.showAt(gp.x, gp.y, "deck", null)
                }
              }
            }
          }

          // 3. EXPANDED STATE: The Note Editor (Emerges from the tab with NotePull spring animation)
          Item {
            id: activeEditorContainer
            z: 100
            visible: root.deckState === "expanded" && root.currentActiveNote !== null

            anchors.right: root.onRight ? parent.right : undefined
            anchors.left: root.onRight ? undefined : parent.left
            anchors.rightMargin: root.onRight ? -Model.GEOM.bleed : 0
            anchors.leftMargin: root.onRight ? 0 : -Model.GEOM.bleed
            width: Model.GEOM.editorWidth + Model.GEOM.bleed
            height: Model.GEOM.editorHeight

            // Smooth vertical alignment with the clicked tab
            property real targetY: {
              if (root.activeNoteId < 0) return (deckPanel.height - Model.GEOM.editorHeight) / 2
              var idx = root.activeNoteIndex
              var pitch = tabsStack.pitch
              var topY = (deckPanel.height - fanColumnWrapper.height) / 2
              var tabCenter = topY + idx * pitch + pitch / 2
              var idealY = tabCenter - Model.GEOM.editorHeight / 2
              var lowestY = Math.max(10, deckPanel.height - Model.GEOM.editorHeight - 10)
              return Math.max(10, Math.min(idealY, lowestY))
            }

            y: targetY
            Behavior on y {
              SpringAnimation { spring: 3.5; damping: 0.82; duration: 250 }
            }

            // NotePull GPU Transform Animation: Slide + Scale + Fade
            property bool isExpanded: root.deckState === "expanded" && root.currentActiveNote !== null

            opacity: isExpanded ? 1.0 : 0.0
            Behavior on opacity {
              NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
            }

            transform: [
              Translate {
                x: activeEditorContainer.isExpanded ? 0 : (root.onRight ? 55 : -55)
                Behavior on x {
                  SpringAnimation { spring: 3.6; damping: 0.80; duration: 250 }
                }
              },
              Scale {
                origin.x: root.onRight ? activeEditorContainer.width : 0
                origin.y: activeEditorContainer.height / 2
                xScale: activeEditorContainer.isExpanded ? 1.0 : 0.95
                yScale: activeEditorContainer.isExpanded ? 1.0 : 0.95
                Behavior on xScale {
                  SpringAnimation { spring: 3.6; damping: 0.80; duration: 250 }
                }
                Behavior on yScale {
                  SpringAnimation { spring: 3.6; damping: 0.80; duration: 250 }
                }
              }
            ]

            NotyEditor {
              id: noteEditorComponent
              anchors.fill: parent
              note: root.currentActiveNote
              onRight: root.onRight
              fontFamily: root.noteFont
              fontSize: root.noteFontSize

              onSaveRequested: function(id, tit, body) {
                root.saveNote(id, tit, body)
              }
              onColorChanged: function(id, colIdx) {
                root.setNoteColor(id, colIdx)
              }
              onPinToggled: function(id) {
                root.toggleNotePin(id)
              }
              onMoveUpRequested: function(id) {
                root.moveNoteUp(id)
              }
              onMoveDownRequested: function(id) {
                root.moveNoteDown(id)
              }
              onArchiveRequested: function(id) {
                root.archiveNote(id, true)
              }
              onDeleteRequested: function(id) {
                root.deleteNoteWithUndo(id)
              }
              onCloseRequested: {
                root.collapseToFan()
              }
              onNoteInteracted: {
                root.noteActivity()
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- OVERLAYS

  // 10-Second Undo Deletion Floating Toast
  PanelWindow {
    id: toastPanel
    visible: undoToast.visible
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-noty-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      bottom: true
      left: true
      right: true
    }
    margins {
      bottom: 34
    }
    implicitHeight: 54

    mask: Region { item: undoToast }

    NotyToast {
      id: undoToast
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom

      onUndoRequested: {
        if (undoToast.pendingNote) {
          root.restoreDeletedNote(undoToast.pendingNote)
        }
      }
    }
  }

  // Right-Click Context Menu Overlay
  PanelWindow {
    id: contextMenuPanel
    visible: contextMenu.open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-noty-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    NotyMenu {
      id: contextMenu
      anchors.fill: parent
      onRight: root.onRight
      currentFont: root.noteFont
      currentFontSize: root.noteFontSize
      currentDeckStyle: root.deckStyle

      onActionTriggered: function(action, data) {
        if (action === "newNote") root.newNote()
        else if (action === "openManager") {
          root.managerInitialMode = String(data || "all")
          root.managerOpen = true
        }
        else if (action === "moveNoteUp" && data) root.moveNoteUp(data.id)
        else if (action === "moveNoteDown" && data) root.moveNoteDown(data.id)
        else if (action === "togglePin" && data) root.toggleNotePin(data.id)
        else if (action === "archiveNote" && data) root.archiveNote(data.id, true)
        else if (action === "cycleColor" && data) root.setNoteColor(data.id, (data.color + 1) % Model.COLORS.length)
        else if (action === "deleteNote" && data) root.deleteNoteWithUndo(data.id)
        else if (action === "setDeckStyle") {
          root.deckStyle = String(data)
          root.saveSettings()
        }
        else if (action === "setFontFamily") {
          root.noteFont = String(data)
          root.saveSettings()
        }
        else if (action === "setFontSize") {
          root.noteFontSize = Number(data)
          root.saveSettings()
        }
        else if (action === "toggleEdge") {
          root.onRight = !root.onRight
          root.saveSettings()
        }
        else if (action === "exportNotes") root.exportNotes(String(data))
        else if (action === "importNotes") root.importNotes()
        else if (action === "collapseDeck") root.collapseToRest()
        else if (action === "quit") root.collapseToRest()
      }
    }
  }

  // All Notes & Archive Library Window
  PanelWindow {
    id: managerPanel
    visible: root.managerOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-noty-manager"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)
    }

    NotyManager {
      id: libraryManager
      anchors.fill: parent
      open: root.managerOpen
      notesList: root.notes
      fontFamily: root.noteFont
      fontSize: root.noteFontSize

      onCloseRequested: {
        root.managerOpen = false
      }
      onNewNoteRequested: {
        root.managerOpen = false
        root.newNote()
      }
      onSaveRequested: function(id, tit, body) {
        root.saveNote(id, tit, body)
      }
      onColorChanged: function(id, colIdx) {
        root.setNoteColor(id, colIdx)
      }
      onPinToggled: function(id) {
        root.toggleNotePin(id)
      }
      onArchiveToggled: function(id, toArchived) {
        root.archiveNote(id, toArchived)
      }
      onDeleteRequested: function(id) {
        root.deleteNoteWithUndo(id)
      }
    }
  }

  onManagerOpenChanged: {
    if (managerOpen) {
      loadNotes()
      libraryManager.show(root.managerInitialMode)
    }
  }

  // ------------------------------------------------------------- IPC

  IpcHandler {
    target: "jot"

    function ping(): string { return "ok" }
    function state(): string { return root.deckState }

    function open(payloadJson: string): string {
      console.log("NOTY OPEN IPC CALLED raw:", payloadJson)
      var p = ({})
      try { p = JSON.parse(payloadJson || "{}") } catch (e) { p = ({}) }
      console.log("NOTY OPEN IPC parsed:", JSON.stringify(p))
      if (p.action === "manager" || p.action === "all") {
        root.managerInitialMode = "all"
        root.managerOpen = true
      } else if (p.action === "archive") {
        root.managerInitialMode = "archive"
        root.managerOpen = true
      } else if (p.action === "new") {
        root.newNote()
      } else if (p.action === "expand" || p.id !== undefined) {
        var targetId = parseInt(p.id || "1")
        console.log("NOTY EXPANDING NOTE ID:", targetId)
        root.expandNote(targetId, -1)
      } else if (p.action === "export") {
        root.exportNotes(p.format || "markdown_zip")
      } else {
        root.deckState = "fan"
        fanIdleTimer.restart()
        root.revealTick++
      }
      return "ok"
    }

    function expand(noteIdStr: string): string {
      var nid = parseInt(noteIdStr || "1")
      root.expandNote(nid, -1)
      return "ok"
    }

    function toggle(): string {
      root.deckVisible = !root.deckVisible
      if (!root.deckVisible) {
        root.collapseToRest()
      } else {
        root.deckState = "fan"
        fanIdleTimer.restart()
        root.revealTick++
      }
      root.saveSettings()
      return root.deckVisible ? "shown" : "hidden"
    }

    function toggleVisibility(): string {
      return toggle()
    }

    function hide(): string {
      root.deckVisible = false
      root.collapseToRest()
      root.saveSettings()
      return "hidden"
    }

    function show(): string {
      root.deckVisible = true
      root.deckState = "fan"
      fanIdleTimer.restart()
      root.revealTick++
      root.saveSettings()
      return "shown"
    }

    function close(): string {
      root.collapseToRest()
      root.managerOpen = false
      return "ok"
    }
  }
}
