# AGENTS.md

How Server Dashboard is put together, for anyone (or any agent) changing it. The user-facing story is in [README.md](README.md).

## Layout

- `BarWidget.qml`: the bar entry, once per monitor. The first instance (the leader) loads `ServerClient.qml`; the others read the leader's. Hosts `Panel.qml` and the IPC target.
- `ServerClient.qml`: polling, history, actions and notifications for the one server.
- `Panel.qml`: the dashboard, built to the numbers below. A fixed header (the hero and its status line), a fixed row of actions at the bottom, and between them what scrolls: banners, failed services, a two-column gauge grid (kit `LevelBar`), a two-column grid of readings, and the details row that opens the other disks, processes, the system and containers. Settings and the connect form replace the middle and keep the panel kit.
- `PulseGlyph.qml`: Batteries' charging pulse, on the hero icon while the server connects or reboots. It steps at 20 Hz rather than every frame; keep any motion here that light.
- `Updater.qml`, `Update.js`, `bin/plugin-update`: the shared updater, hosted by `ServerClient.qml`.
- `WidgetSettings.qml`: this widget's `shell.json` entry, read from the file (see below).
- `Model.js`: parses the probe, rates, formatting and the alert rules. Tested by `tests/model.test.js`.
- `bin/server-dash`: the SSH side (bash): one multiplexed master per target, the password from the keyring through `SSH_ASKPASS`, pinned host keys.

## Test

```bash
node tests/model.test.js
node tests/update.test.js
python3 -B -m unittest discover tests
bash -n bin/server-dash
omarchy-shell io.github.t3lluz.server-dashboard status | jq
```

Never put a password or token on a command line or in `shell.json`; `bin/server-dash` reads it from the keyring.

## Panel look

The numbers come from Omarchy's own panels (network, power, audio, tailscale, agents), through `Style.space()` and `Style.font` so they scale. Copy these rather than inventing new ones, so Server Dashboard, Batteries and Sonus stay one family.

- Width `space(380)`, gaps `space(14)` between sections.
- Hero: Nerd Font glyph at `font.display`, `space(14)` to the labels, title at `font.title` bold, status line at `font.caption` bold with 1.2 letter spacing, in capitals, `Qt.darker(foreground, 1.4)`.
- Row icons: Nerd Font glyph at `font.icon`, in a `space(22)` slot with `space(8)` to the text. Rows at `font.body` with captions under them, padded by `spacing.xl` or `spacing.rowPaddingX`.
- Readings: `font.bodySmall`, labels at 0.6 opacity, `spacing.labelGap` between lines, `space(20)` between columns.
- Icon buttons: `PanelActionButton`, with a tooltip. Button rows: `Button`, bordered, `space(6)` apart.

No drawings, no text taller than `font.display`, no paragraphs. Explain with titles, icons, state labels and the status line: it rotates every 2.8 seconds with the same fade as Omarchy's power and network phrases, and while the cursor is on something it says what that does. Keep those hints short and free of names, because a line that wraps would shift rows under the pointer.

Alerts use `Commons.Color.urgent`, not `bar.urgent`, which follows `bar.active`. A monochrome theme makes urgent a quiet grey, so the panel falls back to the foreground there and hot gauges swap their icon for an alert glyph.

## Panel kit

`SectionHeader`, `StatTile`, `ToggleTile`, `SwitchRow`, `Seg`, `Notice`, `LevelBar`, `OptionRow`, `Caption` and `UpdateSection` in the plugin folder are the panel kit: the same files, byte for byte, in ROG Deck, Batteries, Sonus and Server Dashboard, so the four look like one family. Change a kit file in all four or not at all. `Glyph.qml` is the one part each plugin owns: Nerd Font glyphs here, drawn Tabler icons in Batteries.

`Updater.qml`, `Update.js` and `bin/plugin-update` are the shared updater (ROG Deck, Batteries and Server Dashboard; Sonus's engine updates itself the same way). It stashes local edits, untracked files too, before fast-forwarding, and drops the stash when the edits already are the update. `tests/update.test.js` and `tests/test_plugin_update.py` cover it.

Panels never cut text: a `Notice` shows all of its message, a `Caption` breaks long words and paths, and a `ToggleTile` label that does not fit shows in full in its tooltip.

## Rules that are easy to break

- **Settings** are read with `setting(key, fallback)` and saved with `persistSettings({...})`. Both go through `WidgetSettings.qml`, which reads `~/.config/omarchy/shell.json` itself. Never read `settings.foo` directly: the bar's copy turns a list into a Qt sequence that fails `Array.isArray`, and after a plugin reload it can be older than the file. Either one makes a pick look unset, which is how choices "reset after a reboot" or differ between monitors.
- **One widget per monitor.** The bar draws the widget on every screen. Long-running work (a poller, a client, a process) lives in one place, a leader instance or the service, and the others read from it. Never start it per instance.
- **IPC** is answered by whichever monitor's widget registered first, so `open`, `close` and `toggle` go through the shell's `summon`, `hide` and `toggle`, which pick the focused monitor.
- **Nothing may write inside the plugin folder at runtime.** The shell watches it and reloads every plugin when a file appears there. Python sets `sys.dont_write_bytecode`; state goes to `~/.local/state` or `~/.config`.
- **QML changes need `omarchy restart shell`.** Hot reload can keep the old component cached.
- **Pure logic goes in `Model.js`** (a `.pragma library` with no QML) so `node tests/*.test.js` can run it. Change it with a test.
- Comments say why, in plain sentences. Match the surrounding code.

## Release

Bump `version` in `manifest.json` and the version badge in `README.md` together, run the tests, and describe the change for the person using it in the commit message.
