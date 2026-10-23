import QtQuick
import Quickshell
import Quickshell.Io

// This widget's entry in ~/.config/omarchy/shell.json, read from the file.
//
// The bar draws a widget once per monitor and hands each copy its settings,
// and that copy goes wrong in two ways: a list arrives as a Qt sequence that
// fails Array.isArray, so a pick reads as "none made" after every restart;
// and after a plugin reload a copy can be handed an entry older than the
// file. Every copy reading the file itself sees the same, real JSON, and a
// save merges into what is on disk, so a stale copy on one monitor cannot
// undo a choice made on another.
Item {
  id: store
  visible: false

  property string moduleName: ""
  // The bar's copy, used until the file has been read.
  property var injected: ({})
  // The plugin's shell facade; its updateEntryInline does the writing.
  property var shell: null

  readonly property string path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  property var fileEntry: null
  // Saved here but not yet seen back in the file, so the click shows at once.
  property var pending: ({})

  readonly property var values: {
    var base = fileEntry ? fileEntry : plain(injected)
    var out = {}
    for (var k in base) if (k !== "id") out[k] = base[k]
    for (var p in pending) out[p] = pending[p]
    return out
  }

  function plain(value) {
    try { return JSON.parse(JSON.stringify(value || {})) } catch (e) { return {} }
  }

  function get(name, fallback) {
    var value = values[name]
    return value === undefined || value === null ? fallback : value
  }

  function save(patch) {
    var entry = { id: moduleName }
    var current = values
    for (var k in current) entry[k] = current[k]
    var next = {}
    for (var p in pending) next[p] = pending[p]
    for (var key in patch) {
      var value = plain({ v: patch[key] }).v
      entry[key] = value
      next[key] = value
    }
    pending = next
    pendingExpiry.restart()
    if (shell && typeof shell.updateEntryInline === "function") shell.updateEntryInline(moduleName, entry)
  }

  // The layout entry with this id, else a top-level plugins entry, else null.
  function findEntry(config) {
    var layout = config && config.bar ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var list = layout && Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
      for (var i = 0; i < list.length; i++) {
        if (list[i] === moduleName) return {}
        if (list[i] && typeof list[i] === "object" && String(list[i].id) === moduleName) return list[i]
      }
    }
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var j = 0; j < plugins.length; j++)
      if (plugins[j] && String(plugins[j].id) === moduleName) return plugins[j]
    return null
  }

  function read(text) {
    var config
    // Caught mid-write: the change event after the rename reads it again.
    try { config = JSON.parse(String(text || "")) } catch (e) { return }
    var entry = findEntry(config)
    if (JSON.stringify(entry) !== JSON.stringify(fileEntry)) fileEntry = entry
    var left = {}
    for (var key in pending)
      if (!entry || JSON.stringify(entry[key]) !== JSON.stringify(pending[key])) left[key] = pending[key]
    if (JSON.stringify(left) !== JSON.stringify(pending)) pending = left
  }

  FileView {
    path: store.path
    watchChanges: true
    printErrors: false
    onLoaded: store.read(text())
    onFileChanged: reload()
  }

  // A save the shell turned down never shows up in the file; let the file
  // win again rather than holding the click's value forever.
  Timer {
    id: pendingExpiry
    interval: 4000
    onTriggered: store.pending = ({})
  }
}
