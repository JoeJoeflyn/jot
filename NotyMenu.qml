import QtQuick
import qs.Commons
import qs.Ui
import "NotyModel.js" as Model

// NotyMenu — Contextual popup menu for Noty deck, tabs, and actions.
Item {
  id: menuRoot

  property bool open: false
  property real menuX: 0
  property real menuY: 0
  property var targetNote: null
  property string menuType: "deck" // "deck" | "tab" | "export" | "font" | "size" | "style"

  property string activeSubmenu: ""
  property string currentFont: ""
  property real currentFontSize: 13.5
  property string currentDeckStyle: "tabs" // "tabs" | "compact"
  property bool onRight: true

  signal actionTriggered(string action, var data)

  visible: open
  opacity: open ? 1.0 : 0.0
  Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

  function showAt(x, y, type, note) {
    targetNote = note || null
    menuType = type || "deck"
    activeSubmenu = ""
    menuX = Math.max(10, Math.min(x, parent.width - menuCard.width - 10))
    menuY = Math.max(10, Math.min(y, parent.height - menuCard.height - 10))
    open = true
  }

  function close() {
    open = false
    activeSubmenu = ""
    targetNote = null
  }

  // Dismiss on click outside
  MouseArea {
    anchors.fill: parent
    onClicked: menuRoot.close()
    Keys.onEscapePressed: menuRoot.close()
  }

  // Main Menu Card
  Rectangle {
    id: menuCard
    x: menuRoot.menuX
    y: menuRoot.menuY
    width: 220
    height: menuCol.implicitHeight + 12
    radius: 10
    color: Color.menu.background || Qt.rgba(0.14, 0.14, 0.16, 0.98)
    border.color: Color.menu.border || Qt.rgba(1, 1, 1, 0.12)
    border.width: 1

    // Drop shadow
    Rectangle {
      anchors.fill: parent
      anchors.margins: -1
      z: -1
      radius: parent.radius + 1
      color: "transparent"
      border.color: Qt.rgba(0, 0, 0, 0.35)
      border.width: 2
    }

    Column {
      id: menuCol
      anchors.top: parent.top
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: 1

      // TAB SPECIFIC MENU
      Loader {
        width: parent.width
        active: menuRoot.menuType === "tab" && menuRoot.targetNote !== null
        sourceComponent: Component {
          Column {
            width: parent.width
            spacing: 1

            MenuItemRow {
              iconText: "↑"
              title: "Move Up in Deck"
              onTriggered: {
                menuRoot.actionTriggered("moveNoteUp", menuRoot.targetNote)
                menuRoot.close()
              }
            }

            MenuItemRow {
              iconText: "↓"
              title: "Move Down in Deck"
              onTriggered: {
                menuRoot.actionTriggered("moveNoteDown", menuRoot.targetNote)
                menuRoot.close()
              }
            }

            MenuSeparator {}

            MenuItemRow {
              iconText: menuRoot.targetNote && menuRoot.targetNote.pinned === 1 ? "★" : "☆"
              title: menuRoot.targetNote && menuRoot.targetNote.pinned === 1 ? "Unpin" : "Pin"
              shortcut: "Ctrl+P"
              onTriggered: {
                menuRoot.actionTriggered("togglePin", menuRoot.targetNote)
                menuRoot.close()
              }
            }

            MenuItemRow {
              iconText: "⌹"
              title: "Archive"
              onTriggered: {
                menuRoot.actionTriggered("archiveNote", menuRoot.targetNote)
                menuRoot.close()
              }
            }

            MenuItemRow {
              iconText: "◉"
              title: "Cycle colour"
              shortcut: "Ctrl+."
              onTriggered: {
                menuRoot.actionTriggered("cycleColor", menuRoot.targetNote)
                menuRoot.close()
              }
            }

            MenuItemRow {
              iconText: "≡"
              title: "All Notes..."
              shortcut: "Ctrl+O"
              onTriggered: {
                menuRoot.actionTriggered("openManager", "all")
                menuRoot.close()
              }
            }

            MenuSeparator {}

            MenuItemRow {
              iconText: "✕"
              title: "Delete"
              shortcut: "Ctrl+⌫"
              isDestructive: true
              onTriggered: {
                menuRoot.actionTriggered("deleteNote", menuRoot.targetNote)
                menuRoot.close()
              }
            }
          }
        }
      }

      // DECK GENERAL MENU
      Loader {
        width: parent.width
        active: menuRoot.menuType === "deck"
        sourceComponent: Component {
          Column {
            width: parent.width
            spacing: 1

            MenuItemRow {
              iconText: "+"
              title: "New Note"
              shortcut: "Ctrl+Alt+N"
              onTriggered: {
                menuRoot.actionTriggered("newNote", null)
                menuRoot.close()
              }
            }

            MenuItemRow {
              iconText: "≡"
              title: "All Notes"
              shortcut: "Ctrl+Alt+A"
              onTriggered: {
                menuRoot.actionTriggered("openManager", "all")
                menuRoot.close()
              }
            }

            MenuItemRow {
              iconText: "⌹"
              title: "Archive"
              shortcut: "Ctrl+Alt+L"
              onTriggered: {
                menuRoot.actionTriggered("openManager", "archive")
                menuRoot.close()
              }
            }

            MenuSeparator {}

            MenuItemRow {
              iconText: "◫"
              title: "Deck style"
              hasSubmenu: true
              submenuActive: menuRoot.activeSubmenu === "style"
              onTriggered: {
                menuRoot.activeSubmenu = menuRoot.activeSubmenu === "style" ? "" : "style"
              }
            }

            MenuItemRow {
              iconText: "A"
              title: "Note font"
              hasSubmenu: true
              submenuActive: menuRoot.activeSubmenu === "font"
              onTriggered: {
                menuRoot.activeSubmenu = menuRoot.activeSubmenu === "font" ? "" : "font"
              }
            }

            MenuItemRow {
              iconText: "Tt"
              title: "Text size"
              hasSubmenu: true
              submenuActive: menuRoot.activeSubmenu === "size"
              onTriggered: {
                menuRoot.activeSubmenu = menuRoot.activeSubmenu === "size" ? "" : "size"
              }
            }

            MenuItemRow {
              iconText: menuRoot.onRight ? "◀" : "▶"
              title: menuRoot.onRight ? "Dock to left edge" : "Dock to right edge"
              onTriggered: {
                menuRoot.actionTriggered("toggleEdge", null)
                menuRoot.close()
              }
            }

            MenuSeparator {}

            MenuItemRow {
              iconText: "↗"
              title: "Export"
              hasSubmenu: true
              submenuActive: menuRoot.activeSubmenu === "export"
              onTriggered: {
                menuRoot.activeSubmenu = menuRoot.activeSubmenu === "export" ? "" : "export"
              }
            }

            MenuItemRow {
              iconText: "↙"
              title: "Import notes…"
              onTriggered: {
                menuRoot.actionTriggered("importNotes", null)
                menuRoot.close()
              }
            }

            MenuSeparator {}

            MenuItemRow {
              iconText: "—"
              title: "Collapse deck"
              onTriggered: {
                menuRoot.actionTriggered("collapseDeck", null)
                menuRoot.close()
              }
            }

            MenuItemRow {
              iconText: "✕"
              title: "Quit Noty"
              onTriggered: {
                menuRoot.actionTriggered("quit", null)
                menuRoot.close()
              }
            }
          }
        }
      }
    }
  }

  // SUBMENU CARD (Style / Font / Size / Export)
  Rectangle {
    id: submenuCard
    visible: menuRoot.activeSubmenu !== ""
    x: menuRoot.onRight ? (menuCard.x - width - 6) : (menuCard.x + menuCard.width + 6)
    y: Math.min(menuCard.y + 70, parent.height - height - 10)
    width: 210
    height: subCol.implicitHeight + 12
    radius: 10
    color: Color.menu.background || Qt.rgba(0.14, 0.14, 0.16, 0.98)
    border.color: Color.menu.border || Qt.rgba(1, 1, 1, 0.12)
    border.width: 1

    Column {
      id: subCol
      anchors.top: parent.top
      anchors.topMargin: 6
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: 1

      // Deck Style Submenu
      Repeater {
        model: menuRoot.activeSubmenu === "style" ? [
          { title: "Labelled tabs", key: "tabs" },
          { title: "Colour chips", key: "compact" }
        ] : []
        delegate: MenuItemRow {
          title: modelData.title
          checked: menuRoot.currentDeckStyle === modelData.key
          onTriggered: {
            menuRoot.actionTriggered("setDeckStyle", modelData.key)
            menuRoot.close()
          }
        }
      }

      // Font Submenu
      Repeater {
        model: menuRoot.activeSubmenu === "font" ? Model.FONTS : []
        delegate: MenuItemRow {
          title: modelData.name
          checked: menuRoot.currentFont === modelData.family
          onTriggered: {
            menuRoot.actionTriggered("setFontFamily", modelData.family)
            menuRoot.close()
          }
        }
      }

      // Text Size Submenu
      Repeater {
        model: menuRoot.activeSubmenu === "size" ? Model.FONT_SIZES : []
        delegate: MenuItemRow {
          title: modelData.name + " (" + modelData.size + "pt)"
          checked: Math.abs(menuRoot.currentFontSize - modelData.size) < 0.2
          onTriggered: {
            menuRoot.actionTriggered("setFontSize", modelData.size)
            menuRoot.close()
          }
        }
      }

      // Export Submenu
      Repeater {
        model: menuRoot.activeSubmenu === "export" ? [
          { title: "Markdown (.md files)", key: "markdown_zip" },
          { title: "Plain text (.txt files)", key: "text_zip" },
          { title: "Single document (.md)", key: "single_md" },
          { title: "Sticky archive (.stickies)", key: "stickies_json" }
        ] : []
        delegate: MenuItemRow {
          title: modelData.title
          onTriggered: {
            menuRoot.actionTriggered("exportNotes", modelData.key)
            menuRoot.close()
          }
        }
      }
    }
  }

  // Helper Inline Component: MenuItemRow
  component MenuItemRow: Rectangle {
    id: rowItem
    property string iconText: ""
    property string title: ""
    property string shortcut: ""
    property bool checked: false
    property bool hasSubmenu: false
    property bool submenuActive: false
    property bool isDestructive: false

    signal triggered()

    width: parent ? parent.width : 200
    height: 28
    radius: 6
    color: mouse.containsMouse || submenuActive ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

    Row {
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      spacing: 8

      Text {
        visible: rowItem.iconText !== "" || rowItem.checked
        anchors.verticalCenter: parent.verticalCenter
        text: rowItem.checked ? "✓" : rowItem.iconText
        color: rowItem.checked ? "#68D391" : (rowItem.isDestructive ? "#FC8181" : Qt.rgba(1, 1, 1, 0.7))
        font.family: Style.font.family
        font.pixelSize: 11
        width: 14
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: rowItem.title
        color: rowItem.isDestructive ? "#FEB2B2" : (Color.menu.text || "#FFFFFF")
        font.family: Style.font.family
        font.pixelSize: 12
        elide: Text.ElideRight
        width: parent.width - 24 - (rowItem.shortcut !== "" ? shortcutLabel.implicitWidth + 8 : (rowItem.hasSubmenu ? 16 : 0))
      }

      Text {
        id: shortcutLabel
        visible: rowItem.shortcut !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: rowItem.shortcut
        color: Qt.rgba(1, 1, 1, 0.40)
        font.family: Style.font.family
        font.pixelSize: 11
      }

      Text {
        visible: rowItem.hasSubmenu
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: Qt.rgba(1, 1, 1, 0.50)
        font.family: Style.font.family
        font.pixelSize: 14
        font.bold: true
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: rowItem.triggered()
    }
  }

  // Helper Inline Component: MenuSeparator
  component MenuSeparator: Rectangle {
    width: parent ? parent.width - 16 : 180
    height: 1
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    color: Qt.rgba(1, 1, 1, 0.08)
  }
}
