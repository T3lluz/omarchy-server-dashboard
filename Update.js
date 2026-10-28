.pragma library

// Panel kit: the words and the banner for a plugin's updates. `check` is
// what `bin/plugin-update check` printed, `state` what `bin/plugin-update
// apply` last left in ~/.local/state/<plugin>/update.json, `now` seconds
// since the epoch. Pure, so tests/update.test.js can run it under node.

function parse(raw) {
  try {
    var data = JSON.parse(String(raw || "").trim())
    return data && typeof data === "object" ? data : null
  } catch (e) {
    return null
  }
}

function ago(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  if (s < 60) return "just now"
  if (s < 3600) return Math.floor(s / 60) + " min ago"
  if (s < 86400) return Math.floor(s / 3600) + " h ago"
  return Math.floor(s / 86400) + " d ago"
}

// An apply that has not reported back in five minutes is gone.
function applying(state, now) {
  return !!state && state.state === "updating" && now - state.at < 300
}

// Whether the update brings a version number of its own.
function newer(check) {
  return !!check.latest && check.latest !== check.current
}

// The line beside the Check now / Update button.
function line(check, state, now) {
  if (applying(state, now)) return "Updating…"
  if (!check) return "Not checked yet"
  if (check.error) return check.error
  // Commits without a version bump still count; say so without a number.
  if (check.available) return newer(check) ? "Version " + check.latest + " is available" : "An update is available"
  return "Up to date · checked " + ago(now - check.checked)
}

// The banner over the panel, or null. A finished update shows for ten
// minutes, a failed one for an hour. `icons` names the glyphs for
// "update" and "done" in the plugin's Glyph.
function notice(name, check, state, version, now, icons) {
  var glyphs = icons || { update: "󰚰", done: "󰄬" }
  if (applying(state, now))
    return { key: "update", tone: "accent", icon: glyphs.update, text: "Updating " + name + "…", busy: true }
  if (state && state.state === "failed" && now - state.at < 3600)
    // Older runs left the raw tool name in front of the news.
    return { key: "update", tone: "urgent", icon: glyphs.update, text: "Update failed: " + String(state.message || "").replace(/^omarchy-plugin-update: /, ""),
             action: "update", actionLabel: "Retry", dismissable: true }
  if (state && state.state === "done" && state.version === version && now - state.at < 600)
    return { key: "update", tone: "accent", icon: glyphs.done, text: name + ": " + state.message, dismissable: true }
  if (check && check.available)
    return { key: "update", tone: "accent", icon: glyphs.update,
             text: newer(check) ? name + " " + check.latest + " is available" : "An update to " + name + " is available",
             action: "update", actionLabel: "Update", dismissable: true }
  return null
}
