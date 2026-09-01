// NotyModel.js - Core pure model, geometry, styling, database SQL, task parser,
// and export/import engine for Noty (faithful port of aimen08/noty).
//
// Testable with `node NotyModel.js` (runs complete self-check test suite).

// 8 authentic Noty colors (Sources/Core.swift NoteColor.all)
var COLORS = [
  { key: "lemon", name: "Lemon", paper: "#FCE795", dash: "#E0AD08", ink: "#3A3008" },
  { key: "peach", name: "Peach", paper: "#FBCFA6", dash: "#E2762A", ink: "#422413" },
  { key: "rose",  name: "Rose",  paper: "#FAC4D1", dash: "#DC4570", ink: "#40161F" },
  { key: "lilac", name: "Lilac", paper: "#D9C7FA", dash: "#7C4DEE", ink: "#2A1B44" },
  { key: "sky",   name: "Sky",   paper: "#BEDDFA", dash: "#2280D6", ink: "#13293A" },
  { key: "mint",  name: "Mint",  paper: "#B4E8D0", dash: "#0E9B6E", ink: "#0F2E23" },
  { key: "sand",  name: "Sand",  paper: "#E3D3B4", dash: "#A37B3C", ink: "#372C18" },
  { key: "slate", name: "Slate", paper: "#CBD6E2", dash: "#4E6579", ink: "#1A242E" }
];

function colorByKey(key) {
  if (typeof key === "number" || (!isNaN(parseInt(key, 10)) && String(parseInt(key, 10)) === String(key).trim())) {
    return colorByIndex(key);
  }
  var k = String(key || "").toLowerCase();
  for (var i = 0; i < COLORS.length; i++) {
    if (COLORS[i].key === k) return COLORS[i];
  }
  return COLORS[0];
}

function colorByIndex(i) {
  var n = parseInt(i, 10);
  if (isNaN(n)) n = 0;
  return COLORS[((n % COLORS.length) + COLORS.length) % COLORS.length];
}

function colorIndex(keyOrIndex) {
  var n = parseInt(keyOrIndex, 10);
  if (!isNaN(n)) return ((n % COLORS.length) + COLORS.length) % COLORS.length;
  var k = String(keyOrIndex || "").toLowerCase();
  for (var i = 0; i < COLORS.length; i++) {
    if (COLORS[i].key === k) return i;
  }
  return 0;
}

// Available fonts matching Noty's Ink.allFaces
var FONTS = [
  { name: "Omarchy (iA Quattro)", family: "iA Writer Quattro S, sans-serif", sizeBump: 0 },
  { name: "System", family: "", sizeBump: 0 },
  { name: "JetBrains Mono", family: "JetBrainsMono Nerd Font, monospace", sizeBump: -0.5 },
  { name: "Caskaydia Mono", family: "CaskaydiaMono Nerd Font, monospace", sizeBump: -0.5 },
  { name: "Adwaita Sans", family: "Adwaita Sans, sans-serif", sizeBump: 0 },
  { name: "Liberation Sans", family: "Liberation Sans, sans-serif", sizeBump: 0 }
];

var FONT_SIZES = [
  { name: "Small", size: 11.5 },
  { name: "Regular", size: 13.5 },
  { name: "Large", size: 15.5 },
  { name: "Huge", size: 18.0 }
];

// Geometry metrics matching Noty Sources/DeckPanel.swift DeckGeom
var GEOM = {
  // Rest — a 10 pt pill of colour dashes
  pillWidth: 10,
  pillTouchWidth: 14,
  dashHeight: 10,
  dashWidth: 3.5,
  dashGap: 3.5,
  pillPad: 6,
  maxDashes: 14,

  // Fan
  tabWidth: 30,
  tabHeightMax: 118,
  tabHeightMin: 58,
  tabGap: 7,
  tabLap: 40,
  pitchMin: 56,
  pitchMax: 106,
  labelPad: 20,
  labelInset: 12,
  bleed: 14,
  leanDegrees: 3.0,
  chipWidth: 30,
  chipHeight: 24,
  chipGap: 6,
  fanWidth: 56,
  plusSize: 28,
  plusInset: 14,
  plusGap: 12,
  moreTabHeight: 34,
  heightBudget: 0.68,

  // Expanded note editor
  gutterWidth: 30,
  editorWidth: 460,
  editorHeight: 380,
  get expandedWidth() { return Math.max(this.fanWidth, this.editorWidth) + 22; },

  // Timeouts (seconds)
  fanLimit: 5,
  fanIdleTimeout: 4.0,
  noteIdleTimeout: 60.0
};

function leanDegrees(onRight) {
  return onRight ? -GEOM.leanDegrees : GEOM.leanDegrees;
}

function pillHeight(noteCount) {
  var count = parseInt(noteCount, 10);
  if (isNaN(count) || count < 0) count = 0;
  var shown = Math.min(count, GEOM.maxDashes);
  var n = Math.max(1, shown + (count > GEOM.maxDashes ? 1 : 0));
  return GEOM.pillPad * 2 + n * GEOM.dashHeight + (n - 1) * GEOM.dashGap;
}

// Checkbox task engine (Unicode ☐ \u2610 and ☑ \u2611 with \uFE0E text presentation selector)
var TASK_OPEN = "[ ]";
var TASK_DONE = "[✓]";
var TASK_OPEN_PREFIX = "[ ] ";
var TASK_DONE_PREFIX = "[✓] ";

function taskMarker(line) {
  var s = String(line || "").replace(/^\s+/, "");
  if (s.indexOf("[✓]") === 0 || s.indexOf("[x]") === 0 || s.indexOf("[X]") === 0 || s.indexOf("[v]") === 0 || s.indexOf("[V]") === 0 || s.indexOf("\u2611") === 0 || s.indexOf("- [x]") === 0 || s.indexOf("- [X]") === 0) return "done";
  if (s.indexOf("[ ]") === 0 || s.indexOf("\u2610") === 0 || s.indexOf("- [ ]") === 0) return "open";
  return null;
}

function isTaskLine(line) {
  return taskMarker(line) !== null;
}

function toggleTaskLine(line) {
  var s = String(line || "");
  var m = taskMarker(s);
  if (m === "open") {
    return s.replace(/^(\s*)(\[\s*\]|\u2610\uFE0E?|[-*]\s+\[\s*\])\s*/, "$1[✓] ");
  }
  if (m === "done") {
    return s.replace(/^(\s*)(\[[✓xXvV]\]|\u2611\uFE0E?|[-*]\s+\[[xX]\])\s*/, "$1[ ] ");
  }
  return "[ ] " + s;
}

function stripTask(line) {
  if (!isTaskLine(line)) return String(line || "");
  return String(line).replace(/^(\s*)(\[[✓xXvV ]\]|\u2610\uFE0E?|\u2611\uFE0E?|[-*]\s+\[[ xX]\])\s*/, "");
}

// Toggle tasks across a multi-line block (for selection-based Ctrl+T).
// If any non-empty line is not yet a task, convert all non-task lines to open tasks.
// If all non-empty lines are already tasks, toggle each (open↔done).
function toggleTaskBlock(text) {
  var lines = String(text || "").split("\n");
  var anyNonTask = false;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== "" && !isTaskLine(lines[i])) { anyNonTask = true; break; }
  }
  var out = [];
  for (var j = 0; j < lines.length; j++) {
    var l = lines[j];
    if (l.trim() === "") { out.push(l); continue; }
    if (anyNonTask) {
      out.push(isTaskLine(l) ? l : (TASK_OPEN_PREFIX + l));
    } else {
      out.push(toggleTaskLine(l));
    }
  }
  return out.join("\n");
}

function taskCounts(body) {
  var lines = String(body || "").split("\n");
  var done = 0, total = 0;
  for (var i = 0; i < lines.length; i++) {
    var m = taskMarker(lines[i]);
    if (m === "open") total++;
    else if (m === "done") { total++; done++; }
  }
  return { done: done, total: total };
}

// Derived title from first non-empty line
function derivedTitle(body) {
  var lines = String(body || "").split("\n");
  var line = "";
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== "") { line = lines[i].trim(); break; }
  }
  var clean = line.replace(/^#{1,6}\s*/, "");
  clean = stripTask(clean).trim();
  if (clean === "") return "";
  return clean.length > 60 ? clean.substring(0, 60) + "…" : clean;
}

function displayTitle(note) {
  if (!note) return "New note";
  var t = (note.title !== undefined && note.title !== null) ? String(note.title).trim() : "";
  if (t !== "") return t;
  var d = derivedTitle(note.body);
  return d !== "" ? d : "New note";
}

function notePreview(body) {
  var lines = String(body || "").split("\n");
  var rest = [];
  var firstFound = false;
  for (var i = 0; i < lines.length; i++) {
    var trimmed = lines[i].trim();
    if (!firstFound) {
      if (trimmed !== "") firstFound = true;
    } else {
      if (trimmed !== "") rest.push(stripTask(trimmed));
    }
  }
  var joined = rest.join(" ");
  return joined.length > 100 ? joined.substring(0, 100) + "…" : joined;
}

// Markdown conversion for task checkboxes
function tasksFromMarkdown(text) {
  return String(text || "")
    .replace(/^(\s*)[-*]\s+\[ \]\s+/gm, "$1" + TASK_OPEN_PREFIX)
    .replace(/^(\s*)[-*]\s+\[[xX]\]\s+/gm, "$1" + TASK_DONE_PREFIX);
}

function tasksToMarkdown(text) {
  return String(text || "")
    .replace(/^(\s*)\[\s*\]\s+/gm, "$1- [ ] ")
    .replace(/^(\s*)\[[✓xXvV]\]\s+/gm, "$1- [x] ");
}

// Safe SQL helpers
function sqlQuote(s) {
  return "'" + String(s === null || s === undefined ? "" : s).replace(/'/g, "''") + "'";
}

function initSql() {
  return [
    "CREATE TABLE IF NOT EXISTS notes (",
    "  id INTEGER PRIMARY KEY AUTOINCREMENT,",
    "  title TEXT NOT NULL DEFAULT '',",
    "  body TEXT NOT NULL DEFAULT '',",
    "  color INTEGER NOT NULL DEFAULT 0,",
    "  pinned INTEGER DEFAULT 0,",
    "  archived INTEGER DEFAULT 0,",
    "  sort_order INTEGER DEFAULT 0,",
    "  created_at INTEGER NOT NULL,",
    "  updated_at INTEGER NOT NULL",
    ");"
  ].join(" ");
}

function selectActiveSql() {
  return "SELECT id, title, body, color, pinned, archived, sort_order, created_at, updated_at FROM notes WHERE archived=0 ORDER BY pinned DESC, sort_order ASC, id ASC;";
}

function selectAllSql(archived) {
  if (archived === undefined || archived === null) {
    return "SELECT id, title, body, color, pinned, archived, sort_order, created_at, updated_at FROM notes ORDER BY pinned DESC, sort_order ASC, id ASC;";
  }
  var isArchived = archived ? 1 : 0;
  return "SELECT id, title, body, color, pinned, archived, sort_order, created_at, updated_at FROM notes WHERE archived=" + isArchived + " ORDER BY pinned DESC, sort_order ASC, id ASC;";
}

function reorderNotesSql(idList) {
  if (!Array.isArray(idList)) return "";
  var sql = "";
  for (var i = 0; i < idList.length; i++) {
    sql += "UPDATE notes SET sort_order=" + i + " WHERE id=" + Number(idList[i]) + ";";
  }
  return sql;
}

function insertSql(title, body, color) {
  var now = Math.floor(Date.now() / 1000);
  var colIdx = colorIndex(color);
  var tit = title || derivedTitle(body);
  return "INSERT INTO notes (title, body, color, pinned, archived, sort_order, created_at, updated_at) VALUES (" +
    sqlQuote(tit) + ", " + sqlQuote(body) + ", " + Number(colIdx) + ", 0, 0, 0, " + now + ", " + now + ");";
}

function updateSql(id, title, body) {
  var now = Math.floor(Date.now() / 1000);
  var tit = title !== undefined && title !== null ? title : derivedTitle(body);
  return "UPDATE notes SET title=" + sqlQuote(tit) + ", body=" + sqlQuote(body) + ", updated_at=" + now + " WHERE id=" + Number(id) + ";";
}

function setColorSql(id, color) {
  var colIdx = colorIndex(color);
  var now = Math.floor(Date.now() / 1000);
  return "UPDATE notes SET color=" + Number(colIdx) + ", updated_at=" + now + " WHERE id=" + Number(id) + ";";
}

function setPinnedSql(id, pinned) {
  var p = pinned ? 1 : 0;
  var now = Math.floor(Date.now() / 1000);
  return "UPDATE notes SET pinned=" + p + ", updated_at=" + now + " WHERE id=" + Number(id) + ";";
}

function archiveSql(id, archived) {
  var a = archived ? 1 : 0;
  var now = Math.floor(Date.now() / 1000);
  return "UPDATE notes SET archived=" + a + ", updated_at=" + now + " WHERE id=" + Number(id) + ";";
}

function deleteSql(id) {
  return "DELETE FROM notes WHERE id=" + Number(id) + ";";
}

function restoreNoteSql(note) {
  if (!note) return "";
  var now = Math.floor(Date.now() / 1000);
  var col = colorIndex(note.color);
  return "INSERT INTO notes (id, title, body, color, pinned, archived, created_at, updated_at) VALUES (" +
    Number(note.id) + ", " + sqlQuote(note.title || "") + ", " + sqlQuote(note.body || "") + ", " +
    col + ", " + (note.pinned ? 1 : 0) + ", " + (note.archived ? 1 : 0) + ", " +
    Number(note.created_at || now) + ", " + now + ");";
}

// Parse sqlite3 -json output safely
function parseRows(text) {
  var s = String(text || "").trim();
  if (!s) return [];
  try {
    var v = JSON.parse(s);
    if (!Array.isArray(v)) return [];
    // Normalize row fields
    for (var i = 0; i < v.length; i++) {
      var r = v[i];
      r.id = Number(r.id);
      r.color = colorIndex(r.color);
      r.pinned = Number(r.pinned) === 1 ? 1 : 0;
      r.archived = Number(r.archived) === 1 ? 1 : 0;
      r.sort_order = Number(r.sort_order || 0);
      r.created_at = Number(r.created_at || 0);
      r.updated_at = Number(r.updated_at || 0);
      r.title = String(r.title || "");
      r.body = String(r.body || "").replace(/\\n/g, "\n");
    }
    return v;
  } catch (e) {
    return [];
  }
}

// Relative time formatting matching Noty's Fmt.ago
function ago(timestamp) {
  var now = Math.floor(Date.now() / 1000);
  var ts = Number(timestamp || 0);
  if (ts <= 0) return "just now";
  var diff = Math.max(0, now - ts);
  if (diff < 60) return "just now";
  if (diff < 3600) return Math.floor(diff / 60) + "m ago";
  if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
  if (diff < 86400 * 7) return Math.floor(diff / 86400) + "d ago";
  return new Date(ts * 1000).toLocaleDateString();
}

// Export / Import formats
function exportStickiesJson(notes) {
  var list = Array.isArray(notes) ? notes : [];
  var out = list.map(function(n) {
    return {
      title: n.title || "",
      body: n.body || "",
      color: colorIndex(n.color),
      pinned: n.pinned === 1,
      archived: n.archived === 1,
      created_at: n.created_at,
      updated_at: n.updated_at
    };
  });
  return JSON.stringify({ version: 1, exported_at: new Date().toISOString(), notes: out }, null, 2);
}

function exportSingleMarkdown(notes) {
  var list = Array.isArray(notes) ? notes : [];
  var chunks = list.map(function(n) {
    var tit = displayTitle(n);
    var col = colorByIndex(n.color).name;
    var dt = n.updated_at ? new Date(n.updated_at * 1000).toLocaleString() : "";
    var body = tasksToMarkdown(n.body);
    return "## " + tit + "\n*Color: " + col + " | " + dt + "*\n\n" + body;
  });
  return chunks.join("\n\n---\n\n");
}

function parseStickiesJson(jsonStr) {
  try {
    var obj = JSON.parse(jsonStr);
    var rawNotes = obj.notes || (Array.isArray(obj) ? obj : []);
    if (!Array.isArray(rawNotes)) return [];
    return rawNotes.map(function(n) {
      return {
        title: String(n.title || derivedTitle(n.body)),
        body: String(n.body || ""),
        color: colorIndex(n.color),
        pinned: n.pinned ? 1 : 0,
        archived: n.archived ? 1 : 0
      };
    });
  } catch (e) {
    return [];
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    COLORS: COLORS,
    colorByKey: colorByKey,
    colorByIndex: colorByIndex,
    colorIndex: colorIndex,
    FONTS: FONTS,
    FONT_SIZES: FONT_SIZES,
    GEOM: GEOM,
    leanDegrees: leanDegrees,
    pillHeight: pillHeight,
    TASK_OPEN: TASK_OPEN,
    TASK_DONE: TASK_DONE,
    TASK_OPEN_PREFIX: TASK_OPEN_PREFIX,
    TASK_DONE_PREFIX: TASK_DONE_PREFIX,
    taskMarker: taskMarker,
    isTaskLine: isTaskLine,
    toggleTaskLine: toggleTaskLine,
    toggleTaskBlock: toggleTaskBlock,
    stripTask: stripTask,
    taskCounts: taskCounts,
    derivedTitle: derivedTitle,
    displayTitle: displayTitle,
    notePreview: notePreview,
    tasksFromMarkdown: tasksFromMarkdown,
    tasksToMarkdown: tasksToMarkdown,
    sqlQuote: sqlQuote,
    initSql: initSql,
    selectActiveSql: selectActiveSql,
    selectAllSql: selectAllSql,
    insertSql: insertSql,
    updateSql: updateSql,
    setColorSql: setColorSql,
    setPinnedSql: setPinnedSql,
    archiveSql: archiveSql,
    deleteSql: deleteSql,
    restoreNoteSql: restoreNoteSql,
    parseRows: parseRows,
    ago: ago,
    exportStickiesJson: exportStickiesJson,
    exportSingleMarkdown: exportSingleMarkdown,
    parseStickiesJson: parseStickiesJson
  };
}

// Self-check test runner: `node NotyModel.js`
if (typeof require === "function" && require.main === module) {
  var assert = require("assert");

  // Palette tests
  assert.strictEqual(COLORS.length, 8);
  assert.strictEqual(colorByIndex(0).key, "lemon");
  assert.strictEqual(colorByIndex(7).key, "slate");
  assert.strictEqual(colorByIndex(8).key, "lemon"); // wrap
  assert.strictEqual(colorByKey("mint").dash, "#0E9B6E");
  assert.strictEqual(colorByKey("peach").paper, "#FBCFA6");
  assert.strictEqual(colorIndex("Rose"), 2);
  assert.strictEqual(colorIndex("2"), 2);

  // Task tests
  assert.strictEqual(toggleTaskLine("buy milk"), "[ ] buy milk");
  assert.strictEqual(toggleTaskLine("[ ] buy milk"), "[✓] buy milk");
  assert.strictEqual(toggleTaskLine("[✓] buy milk"), "[ ] buy milk");
  assert.strictEqual(isTaskLine("[ ] hello"), true);
  assert.strictEqual(isTaskLine("[✓] hello"), true);
  assert.strictEqual(isTaskLine("hello"), false);
  assert.strictEqual(stripTask("[ ] hello"), "hello");
  assert.strictEqual(stripTask("[✓] hello"), "hello");

  // Multi-line block toggle
  var block1 = "Catsset idea\nCar on border\nHover preview";
  var conv1 = toggleTaskBlock(block1);
  assert.strictEqual(conv1, "[ ] Catsset idea\n[ ] Car on border\n[ ] Hover preview");
  // All open → toggle all to done
  var conv2 = toggleTaskBlock(conv1);
  assert.strictEqual(conv2, "[✓] Catsset idea\n[✓] Car on border\n[✓] Hover preview");
  // All done → toggle all back to open
  var conv3 = toggleTaskBlock(conv2);
  assert.strictEqual(conv3, "[ ] Catsset idea\n[ ] Car on border\n[ ] Hover preview");
  // Mixed: some tasks, some not → all non-tasks become open, tasks stay
  var mixed = toggleTaskBlock("[✓] done one\nplain line\n[ ] open one");
  assert.strictEqual(mixed, "[✓] done one\n[ ] plain line\n[ ] open one");
  // Empty lines preserved
  var withEmpty = toggleTaskBlock("item 1\n\nitem 2");
  assert.strictEqual(withEmpty, "[ ] item 1\n\n[ ] item 2");

  var counts = taskCounts("[ ] task 1\n[✓] task 2\nplain text\n[ ] task 3");
  assert.deepStrictEqual(counts, { done: 1, total: 3 });

  // Markdown roundtrip
  var mdIn = "- [ ] Task 1\n- [x] Task 2\nRegular line";
  var converted = tasksFromMarkdown(mdIn);
  assert.strictEqual(isTaskLine(converted.split("\n")[0]), true);
  assert.strictEqual(isTaskLine(converted.split("\n")[1]), true);

  // Title derivation
  assert.strictEqual(derivedTitle(""), "");
  assert.strictEqual(derivedTitle("   \n\n# Shopping List\n[ ] Bread\n[ ] Milk"), "Shopping List");
  assert.strictEqual(derivedTitle("[ ] Buy eggs\nNext item"), "Buy eggs");

  // SQL generation
  assert.strictEqual(sqlQuote("Don't worry"), "'Don''t worry'");
  var ins = insertSql("Title", "Body", "mint");
  assert.ok(ins.indexOf("'Title'") !== -1);
  assert.ok(ins.indexOf("'Body'") !== -1);
  assert.ok(ins.indexOf("5") !== -1); // mint is 5

  // Geometry
  assert.strictEqual(GEOM.expandedWidth, 482);
  assert.strictEqual(pillHeight(1), 6 * 2 + 1 * 10 + 0 * 3.5);
  assert.strictEqual(pillHeight(3), 6 * 2 + 3 * 10 + 2 * 3.5);
  assert.strictEqual(leanDegrees(true), -3.0);
  assert.strictEqual(leanDegrees(false), 3.0);

  // Time format
  assert.strictEqual(ago(Math.floor(Date.now() / 1000) - 10), "just now");
  assert.strictEqual(ago(Math.floor(Date.now() / 1000) - 120), "2m ago");
  assert.strictEqual(ago(Math.floor(Date.now() / 1000) - 7200), "2h ago");

  // Parse JSON rows
  var rows = parseRows('[{"id":"1","title":"Hi","body":"☐ test","color":"sky","pinned":"1","archived":"0","created_at":100,"updated_at":200}]');
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].id, 1);
  assert.strictEqual(rows[0].color, 4); // sky is 4
  assert.strictEqual(rows[0].pinned, 1);

  // Stickies export & import
  var exp = exportStickiesJson(rows);
  var imported = parseStickiesJson(exp);
  assert.strictEqual(imported.length, 1);
  assert.strictEqual(imported[0].title, "Hi");
  assert.strictEqual(imported[0].color, 4);
  assert.strictEqual(imported[0].pinned, 1);

  console.log("All NotyModel.js tests passed successfully!");
}
