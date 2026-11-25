// Run with: node tests/motion.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const load = (file, names) => new Function(
  fs.readFileSync(path.join(__dirname, "..", file), "utf8").replace(/^\.pragma library\s*/, "") + "\nreturn { " + names + " }")()
const Motion = load("Motion.js", "LOOP_MS, TICK_MS, MOTIONS, motionOf, playMs, loopMs, phase, frame, moves, untilMove")
const Pixels = load("Pixels.js", "icons")

// Drawn cells as "x,y@alpha", so two frames compare whatever their rects.
// A rect at alpha 0 or no width is there only to keep the count.
const cells = rects => {
  const out = []
  for (const [x, y, w, h, a] of rects) if (a > 0) for (let i = 0; i < w; i++) for (let j = 0; j < h; j++) out.push((x + i) + "," + (y + j) + "@" + a)
  return out.sort()
}
const lit = rects => rects.filter(r => r[4] > 0 && r[2] > 0).length

// Icons that move by other means: the chevron flips as its room opens, the
// gear turns in the panel's own steps, the server mark lights up unit by unit.
const ELSEWHERE = ["chevron-down", "settings-cog", "server"]

for (const name in Pixels.icons) {
  if (ELSEWHERE.includes(name)) assert.strictEqual(Motion.motionOf(name), null, name + " moves elsewhere")
  else assert.ok(Motion.motionOf(name), name + " acts itself out")
}

for (const name in Motion.MOTIONS) {
  const m = Motion.MOTIONS[name]
  const art = Pixels.icons[name]
  assert.ok(art, name + " is in Pixels.js")
  const parts = art.parts ? Object.keys(art.parts) : ["base"]
  for (const id of m.hidden || []) assert.ok(parts.includes(id), name + ": hidden part " + id + " exists")
  assert.ok(m.play > 0, name + " has a play")
  assert.ok(m.loop === 0 || Motion.LOOP_MS % m.loop === 0, name + "'s loop divides the shared clock")

  for (const fine of [false, true]) {
    const grid = fine ? "g24" : "g12"
    const n = fine ? 24 : 12
    const rest = cells(Motion.frame(name, art, fine, "rest", 0))
    assert.deepStrictEqual(rest, cells(art[grid].map(r => r.concat(1))), name + " rests as its art")
    // Its parts at rest are the art: what is cut out is all there, and
    // what was added hides.
    if (art.parts) {
      const shown = []
      for (const id of parts) if (!(m.hidden || []).includes(id)) shown.push(...art.parts[id][grid].map(r => r.concat(1)))
      assert.deepStrictEqual(cells(shown), rest, name + "'s parts make up its art on " + grid)
    }

    for (const kind of ["play", "loop"]) {
      const length = kind === "play" ? m.play : m.loop
      if (!length) continue
      if (!(kind === "play" && m.draws)) assert.deepStrictEqual(cells(Motion.frame(name, art, fine, kind, 0)), rest, name + " " + kind + " starts at rest")
      if (kind === "play") assert.deepStrictEqual(cells(Motion.frame(name, art, fine, kind, length)), rest, name + " play ends at rest")
      for (let ms = 0; ms <= length; ms += 10) {
        const poses = m.pose(kind, Math.min(1, ms / length))
        for (const id in poses) {
          if (id === "rot") { assert.ok(Number.isInteger(poses.rot), name + " turns in quarters"); continue }
          assert.ok(parts.includes(id), name + ": pose names a part it has, " + id)
          const p = poses[id]
          for (const k of ["x", "y", "clip"]) if (p[k] !== undefined) assert.ok(Number.isInteger(p[k]), name + " moves in whole cells")
          if (p.a !== undefined) assert.ok(p.a >= 0 && p.a <= 1, name + " alpha in range")
        }
        for (const [x, y, w, h] of Motion.frame(name, art, fine, kind, ms)) {
          assert.ok([x, y, w, h].every(Number.isInteger), name + " draws on whole cells")
          assert.ok(x >= -2 && y >= -2 && x + w <= n + 2 && y + h <= n + 2, name + " stays by its grid")
        }
      }
      // The last step lands at rest, so stopping there moves nothing. A turn
      // lands on its last quarter, which is the rest again.
      const last = m.pose(kind, (length - 1) / length)
      const end = cells(Motion.frame(name, art, fine, kind, length - 1))
      if (!last.rot) assert.deepStrictEqual(end, rest, name + " " + kind + " ends at rest")
    }
  }
}

// A turn: four quarters make a whole one, and the glass looks the same upside down.
{
  const art = Pixels.icons.hourglass
  const half = Motion.frame("hourglass", art, false, "play", 0.5 * Motion.MOTIONS.hourglass.play)
  assert.deepStrictEqual(cells(half), cells(Motion.frame("hourglass", art, false, "rest", 0)), "the hourglass upside down is the hourglass")
}

// Loops share one clock: icons side by side are on the same beat.
{
  assert.strictEqual(Motion.phase(Motion.LOOP_MS * 3 + 250, 1200), 250)
  assert.strictEqual(Motion.phase(Motion.LOOP_MS - 1, 2400), 2399)
  assert.strictEqual(Motion.phase(Motion.LOOP_MS, 2400), 0)
}

// A part only some of the time: the cursor shows in a play and not at rest.
{
  const art = Pixels.icons.terminal
  const rest = lit(Motion.frame("terminal", art, false, "rest", 0))
  assert.ok(lit(Motion.frame("terminal", art, false, "play", 100)) > rest, "the cursor shows")
  assert.strictEqual(lit(Motion.frame("terminal", art, false, "play", Motion.playMs("terminal") - 1)), rest, "and goes")
}

// A moving icon draws the same number of rects in every frame, so the
// rectangles update in place instead of being made again.
for (const name in Motion.MOTIONS) {
  const m = Motion.MOTIONS[name]
  const art = Pixels.icons[name]
  const count = Motion.frame(name, art, false, "rest", 0).length
  for (const kind of ["play", "loop"]) {
    const length = kind === "play" ? m.play : m.loop
    for (let ms = 0; length && ms <= length; ms += 50) assert.strictEqual(Motion.frame(name, art, false, kind, ms).length, count, name + " keeps its count")
  }
}

// A resting loop says how long it stays still, so an icon can sleep: the
// alert blinks in the first 28% of its 3 s round and rests the rest.
{
  assert.deepStrictEqual(Motion.moves("warning-diamond"), [[120, 360], [600, 840]])
  assert.strictEqual(Motion.untilMove("warning-diamond", 200), 0, "moving")
  assert.strictEqual(Motion.untilMove("warning-diamond", 400), 200, "between blinks")
  assert.strictEqual(Motion.untilMove("warning-diamond", 1000), 3000 - 1000 + 120, "round the top")
  assert.strictEqual(Motion.untilMove("warning-diamond", 0), 120)
  for (const name in Motion.MOTIONS) {
    const m = Motion.MOTIONS[name]
    if (!m.loop) continue
    assert.ok(Motion.moves(name).length > 0, name + "'s loop moves")
    for (let ph = 0; ph < m.loop; ph += 37) {
      const wait = Motion.untilMove(name, ph)
      assert.ok(wait >= 0 && wait <= m.loop, name + " waits a round at most")
      // Nothing moves during the wait, to the sampling's 10 ms.
      for (let t = ph; t < ph + wait - 10; t += 10) {
        const tt = t % m.loop
        assert.deepStrictEqual(cells(Motion.frame(name, Pixels.icons[name], false, "loop", tt)),
          cells(Motion.frame(name, Pixels.icons[name], false, "rest", 0)), name + " is still while it waits")
      }
    }
  }
}

console.log("motion tests passed")
