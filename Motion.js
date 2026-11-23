.pragma library

// How each pixel icon acts itself out. An icon's art is cut into parts
// (Pixels.js, from PARTS in scripts/fetch-pixel-icons.py) and only the part
// that moves does: the gauge's needle sweeps, the box's lid lifts, the
// bell's clapper swings a beat behind the bell.
//
// Two kinds of motion. A play runs once, `play` ms long, when something
// happens: the panel opens, a room is clicked, a state the icon stands for
// changes. A loop runs while a state holds (an action running, a problem
// standing), `loop` ms a round, and is still for most of it. Loops read the
// one clock every icon shares (LOOP_MS) and every loop's round divides it,
// so loops side by side keep time and a loop stops where it began.
//
// Poses move in whole cells of the 12 grid (one stroke) and come from step
// tables, never eased values, so pixel art never smears; on the 24 grid a
// cell is two units. Every play and every loop ends exactly at rest. Pure
// logic, tested by tests/motion.test.js; PixelIcon.qml drives it.

var LOOP_MS = 12000
// How often a moving icon redraws. Poses hold for 60 ms or more.
var TICK_MS = 33

// The value of a step table at e (0..1): [[from, value], ...] by `from`.
function at(e, table) {
  var v = table[0][1]
  for (var i = 1; i < table.length; i++) if (e >= table[i][0]) v = table[i][1]
  return v
}

// 0.3 alpha while e is in [from, to), else lit: a part going dark a moment.
function dim(e, from, to) {
  return e >= from && e < to ? 0.3 : 1
}

// A one-way travel through `n` steps over [from, to): which step it is on,
// or -1 outside.
function stepOf(e, from, to, n) {
  if (e < from || e >= to) return -1
  return Math.min(n - 1, Math.floor((e - from) / (to - from) * n))
}

// The gauge's needle, by name, as its parts.
function needle(state) {
  return {
    "needle": { a: state === "rest" ? 1 : 0 },
    "needle-right": { a: state === "right" ? 1 : 0 },
    "needle-up": { a: state === "up" ? 1 : 0 },
    "needle-zero": { a: state === "zero" ? 1 : 0 }
  }
}

// The pins light round the chip, a side at a time, starting at the top.
function pins(e) {
  return {
    "pins-top": { a: dim(e, 0.05, 0.25) },
    "pins-right": { a: dim(e, 0.25, 0.45) },
    "pins-bottom": { a: dim(e, 0.45, 0.65) },
    "pins-left": { a: dim(e, 0.65, 0.85) },
    "die": { a: dim(e, 0.85, 0.95) }
  }
}

// The chips go dark in turn, left to right, as a write passes over them.
function chips(e) {
  return {
    chip1: { a: dim(e, 0.1, 0.3) },
    chip2: { a: dim(e, 0.3, 0.5) },
    chip3: { a: dim(e, 0.5, 0.7) }
  }
}

// The mercury up to `level` cells over the bead.
function mercury(level) {
  var out = {}
  for (var i = 1; i <= 5; i++) out["mercury" + i] = { a: i <= level ? 1 : 0 }
  return out
}

// A gap runs round each platter's band, the lower one half a turn behind.
function platters(e) {
  var out = {}
  var step = stepOf(e, 0.05, 0.95, 8)
  for (var i = 0; i < 4; i++) {
    out["band-a" + i] = { a: step >= 0 && step % 4 === i ? 0 : 1 }
    out["band-b" + i] = { a: step >= 0 && (step + 2) % 4 === i ? 0 : 1 }
  }
  return out
}

// Each icon: `play` and `loop` in ms (0 when it has none), the parts hidden
// at rest, and `pose(kind, e)` with e 0..1 through the play or the loop
// round: { part: { x, y, a, clip } } in 12 grid cells (clip: columns from
// the left that show), and `rot` in quarter turns for the whole icon.
// Parts a pose leaves out stay at rest. A play that `draws` the icon in
// starts from nothing; every other starts at rest.
var MOTIONS = {
  // System: the needle revs, drops to zero, climbs back and touches the red.
  // Running hot, it flicks into the red now and then.
  "speed-fast": {
    play: 1100, loop: 2400, hidden: ["needle-right", "needle-up", "needle-zero"],
    pose: function(kind, e) {
      if (kind === "play") return needle(at(e, [[0, "rest"], [0.08, "up"], [0.2, "zero"], [0.36, "up"], [0.5, "rest"], [0.64, "right"], [0.84, "rest"]]))
      return needle(at(e, [[0, "rest"], [0.7, "right"], [0.78, "rest"], [0.86, "right"], [0.94, "rest"]]))
    }
  },
  // Disks: the platters spin, a gap running round each band.
  "database": { play: 1000, loop: 0, pose: function(kind, e) { return platters(e) } },
  // Network: the download arrow drops a step, then the upload one rises.
  "sort-vertical": {
    play: 1000, loop: 0,
    pose: function(kind, e) {
      return {
        down: { y: at(e, [[0, 0], [0.08, 1], [0.4, 0]]) },
        up: { y: at(e, [[0, 0], [0.48, -1], [0.8, 0]]) }
      }
    }
  },
  // Containers: the lid lifts and drops back; while a container starts,
  // stops or restarts, it keeps lifting.
  "package": {
    play: 900, loop: 1500,
    pose: function(kind, e) {
      return { lid: { y: kind === "play" ? at(e, [[0, 0], [0.1, -1], [0.6, 0]]) : at(e, [[0, 0], [0.1, -1], [0.5, 0]]) } }
    }
  },
  // Processes: each line steps out of the list in turn, top to bottom.
  "list-box": {
    play: 900, loop: 0,
    pose: function(kind, e) {
      return {
        line1: { x: at(e, [[0, 0], [0.05, 1], [0.3, 0]]) },
        line2: { x: at(e, [[0, 0], [0.3, 1], [0.55, 0]]) },
        line3: { x: at(e, [[0, 0], [0.55, 1], [0.8, 0]]) }
      }
    }
  },
  // An alert: the mark blinks twice. Standing, it blinks once a round.
  "warning-diamond": {
    play: 900, loop: 3000,
    pose: function(kind, e) {
      if (kind === "play") return { bang: { a: at(e, [[0, 1], [0.1, 0], [0.3, 1], [0.5, 0], [0.7, 1]]) } }
      return { bang: { a: at(e, [[0, 1], [0.04, 0], [0.12, 1], [0.2, 0], [0.28, 1]]) } }
    }
  },
  // The processor: current runs round its pins and the die answers.
  // Running hot, the same in the first half of each round.
  "cpu": {
    play: 1000, loop: 2400,
    pose: function(kind, e) { return pins(kind === "play" ? e : e * 2) }
  },
  // Memory: a write passes over the chips.
  "memory-stick": {
    play: 900, loop: 2400,
    pose: function(kind, e) { return chips(kind === "play" ? e : e * 2) }
  },
  // Temperature: the mercury climbs the tube and sinks back. Running hot,
  // it climbs and stays near the top a while.
  "thermometer": {
    play: 1400, loop: 2400, hidden: ["mercury1", "mercury2", "mercury3", "mercury4", "mercury5"],
    pose: function(kind, e) {
      if (kind === "play") return mercury(at(e, [[0, 0], [0.08, 1], [0.16, 2], [0.24, 3], [0.32, 4], [0.4, 5], [0.62, 4], [0.7, 3], [0.78, 2], [0.86, 1], [0.94, 0]]))
      return mercury(at(e, [[0, 0], [0.05, 1], [0.1, 2], [0.15, 3], [0.2, 4], [0.25, 5], [0.55, 4], [0.6, 5], [0.75, 4], [0.8, 3], [0.85, 2], [0.9, 1], [0.95, 0]]))
    }
  },
  // The rates: down drops a step, up rises one.
  "arrow-down": { play: 700, loop: 0, pose: function(kind, e) { return { base: { y: at(e, [[0, 0], [0.1, 1], [0.5, 0]]) } } } },
  "arrow-up": { play: 700, loop: 0, pose: function(kind, e) { return { base: { y: at(e, [[0, 0], [0.1, -1], [0.5, 0]]) } } } },
  // Start: the triangle pushes forward.
  "play": { play: 600, loop: 0, pose: function(kind, e) { return { base: { x: at(e, [[0, 0], [0.1, 1], [0.5, 0]]) } } } },
  // Stop: the light in the square goes out a moment.
  "stop": { play: 600, loop: 0, pose: function(kind, e) { return { dot: { a: at(e, [[0, 1], [0.1, 0], [0.55, 1]]) } } } },
  // An update: the arrow drops into the tray, goes in, and a new one comes
  // down from the top.
  "download": {
    play: 1100, loop: 0,
    pose: function(kind, e) {
      return { arrow: {
        y: at(e, [[0, 0], [0.12, 1], [0.35, 0], [0.55, -1], [0.75, 0]]),
        a: at(e, [[0, 1], [0.35, 0], [0.55, 1]])
      } }
    }
  },
  // Waiting: the glass turns over, a quarter at a time.
  "hourglass": { play: 900, loop: 0, pose: function(kind, e) { return { rot: at(e, [[0, 0], [0.2, 1], [0.45, 2], [0.9, 0]]) } } },
  // The bar: the divider slides across the panes and back.
  "layout": { play: 900, loop: 0, pose: function(kind, e) { return { divider: { x: at(e, [[0, 0], [0.1, 1], [0.3, 2], [0.55, 1], [0.75, 0]]) } } } },
  // Notifications: the bell rocks and the clapper swings a beat behind.
  "bell": {
    play: 1100, loop: 0,
    pose: function(kind, e) {
      return {
        body: { x: at(e, [[0, 0], [0.06, -1], [0.18, 1], [0.3, -1], [0.42, 1], [0.54, 0]]) },
        clapper: { x: at(e, [[0, 0], [0.12, 1], [0.24, -1], [0.36, 1], [0.48, -1], [0.6, 0]]) }
      }
    }
  },
  // A link: the two ends pull apart over the bar and close again.
  "link": {
    play: 900, loop: 0,
    pose: function(kind, e) {
      return {
        left: { x: at(e, [[0, 0], [0.1, -1], [0.55, 0]]) },
        right: { x: at(e, [[0, 0], [0.1, 1], [0.55, 0]]) }
      }
    }
  },
  // The keyring: the key jiggles into the lock twice.
  "key": { play: 900, loop: 0, pose: function(kind, e) { return { base: { x: at(e, [[0, 0], [0.1, 1], [0.3, 0], [0.45, 1], [0.65, 0]]) } } } },
  // Done: the check draws itself, the short stroke, then the long one.
  "check": {
    play: 700, loop: 0, draws: true,
    pose: function(kind, e) {
      return {
        short: { a: at(e, [[0, 0], [0.12, 1]]) },
        long: { a: at(e, [[0, 0], [0.3, 1]]), clip: at(e, [[0, 6], [0.4, 7], [0.5, 8], [0.6, 9], [0.7, 12]]) }
      }
    }
  },
  // Close: the cross snaps shut and open.
  "close": { play: 600, loop: 0, pose: function(kind, e) { return { tips: { a: at(e, [[0, 1], [0.1, 0], [0.55, 1]]) } } } },
  // Back: the arrow steps the way it points.
  "arrow-left": { play: 600, loop: 0, pose: function(kind, e) { return { base: { x: at(e, [[0, 0], [0.1, -1], [0.5, 0]]) } } } },
  // SSH: a cursor blinks after the prompt.
  "terminal": {
    play: 1600, loop: 0, hidden: ["cursor"],
    pose: function(kind, e) { return { cursor: { a: at(e, [[0, 0], [0.04, 1], [0.2, 0], [0.36, 1], [0.52, 0], [0.68, 1], [0.84, 0]]) } } }
  },
  // Monitor: the line is drawn again, left to right.
  "chart-line": {
    play: 1000, loop: 0, draws: true,
    pose: function(kind, e) { return { line: { clip: at(e, [[0, 3], [0.1, 4], [0.2, 5], [0.3, 6], [0.4, 7], [0.5, 8], [0.6, 9], [0.7, 10], [0.8, 12]]) } } }
  },
  // Reboot, restart, busy: the arrows go round a quarter at a time; while it
  // runs they keep going.
  "reload": {
    play: 800, loop: 1200,
    pose: function(kind, e) { return { rot: Math.floor(e * 4) % 4 } }
  },
  // Shutdown: the switch goes in, the ring goes dark, and both come back.
  // While it shuts down, the same each round.
  "power": {
    play: 1200, loop: 2400,
    pose: function(kind, e) {
      var k = kind === "play" ? e : e * 2
      return {
        stem: { y: at(k, [[0, 0], [0.1, 1], [0.6, 0]]) },
        base: { a: at(k, [[0, 1], [0.2, 0.3], [0.6, 1]]) }
      }
    }
  }
}

function motionOf(name) {
  return MOTIONS[name] || null
}

function playMs(name) {
  var m = MOTIONS[name]
  return m ? m.play : 0
}

function loopMs(name) {
  var m = MOTIONS[name]
  return m ? m.loop : 0
}

// Where `now` (ms) is in a loop of `period` ms, on the shared clock.
function phase(now, period) {
  return period > 0 ? (now % LOOP_MS) % period : 0
}

function partPose(m, poses, id) {
  var p = poses[id]
  var hidden = !!m.hidden && m.hidden.indexOf(id) !== -1
  return {
    x: p && p.x ? p.x : 0,
    y: p && p.y ? p.y : 0,
    a: p && p.a !== undefined ? p.a : (hidden ? 0 : 1),
    clip: p && p.clip !== undefined ? p.clip : 12
  }
}

// A quarter turn clockwise of rect [x, y, w, h] on an n grid.
function turn(r, n) {
  return [n - r[1] - r[3], r[0], r[3], r[2]]
}

// The icon's rects as drawn: [x, y, w, h, alpha] on its grid (`fine` for
// the 24 one). `kind` is "rest", "play" or "loop"; `ms` how far into the
// play, or the loop's phase. An icon at rest, or with no motion or no
// parts, is its whole art. While it moves, every part's rects are there in
// every frame, a hidden or clipped one at alpha 0 or no width, so the
// count holds and the drawn rectangles update in place.
function frame(name, art, fine, kind, ms) {
  if (!art) return []
  var grid = fine ? "g24" : "g12"
  var m = MOTIONS[name]
  if (!m) return art[grid].map(function(r) { return [r[0], r[1], r[2], r[3], 1] })
  var length = kind === "play" ? m.play : kind === "loop" ? m.loop : 0
  var poses = length > 0 ? m.pose(kind, Math.max(0, Math.min(1, ms / length))) || {} : {}
  var step = fine ? 2 : 1
  var n = fine ? 24 : 12
  var shift = art.shift || [0, 0]
  var parts = art.parts || { base: { g12: art.g12, g24: art.g24 } }
  var out = []
  for (var id in parts) {
    var p = partPose(m, poses, id)
    // The last column that shows, on this grid.
    var edge = p.clip >= 12 ? n : fine ? p.clip * 2 + shift[0] : p.clip
    var rects = parts[id][grid]
    for (var i = 0; i < rects.length; i++) {
      var r = rects[i]
      var w = Math.max(0, Math.min(r[0] + r[2], edge) - r[0])
      out.push([r[0] + p.x * step, r[1] + p.y * step, w, r[3], w > 0 ? p.a : 0])
    }
  }
  var rot = ((poses.rot || 0) % 4 + 4) % 4
  for (var q = 0; q < rot; q++) out = out.map(function(r) { var t = turn(r, n); return [t[0], t[1], t[2], t[3], r[4]] })
  return out
}
