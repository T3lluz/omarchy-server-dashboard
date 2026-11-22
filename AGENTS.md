# AGENTS.md

How Server Dashboard is put together, for anyone (or any agent) changing it. The user-facing story is in [README.md](README.md).

## Layout

- `BarWidget.qml`: the bar entry, once per monitor. The first instance (the leader) loads `ServerClient.qml`; the others read the leader's. Hosts `Panel.qml`, the hover card and the IPC target. The mark and the stats picked in settings are pixel icons with figures in the pixel type, in the bar's own colours (`Model.barItems`, `Model.barMark`).
- `ServerClient.qml`: polling, history, actions and notifications for the one server.
- `Panel.qml`: the panel (see "Panel look" below). A title room fixed at the top (`HeroBlock.qml`: the mark, the server's name, the prompt line), the banners, the rooms (`Dashboard.qml`), and four action rooms fixed at the bottom (`ActionTile.qml`). The gear swaps the rooms for the settings and the connect form, which keep the panel kit. State, the keyboard cursor and the one clock live here.
- `Dashboard.qml`: the rooms, read from a `host` (the panel, or the offscreen harness's stand-in): failed services, System (CPU, memory and temperature as cells), a row of small rooms (Disk and Network as quarter-width tiles, Containers in the half beside them, their details in one drawer under the row), Processes. A click opens a room (`host.openRoom`, one at a time) to a `Drawer` with the rest of its readings, its rows and its bar switches.
- `Room.qml`, `RoomHeader.qml`, `Drawer.qml`, `Decode.qml`, `BigFigure.qml`, `HeroBlock.qml`, `PixelButton.qml`, `HoverCard.qml`, `HoverRow.qml`: Sonus's room components, the same files less what is Sonus's own (a drop target, the fader mark). `Meter.qml` is Sonus's meter without the fader, plus a limit tick.
- `ServerMark.qml`: the mark, drawn by `Model.serverMark` after the app icon: two server units, each with a light and a label line. The lights come on one unit after the other as the panel opens, and take turns while the server connects or reboots, in the panel and in the bar.
- `PixelIcon.qml`, `PixelText.qml`, `Pixels.js`: every icon is pixel art from one set, Pixelarticons (MIT), rasterised by `scripts/fetch-pixel-icons.py` onto exact grids (24, and 12 for small sizes) and drawn on whole device pixels. Add an icon to the script's list and rerun it. The pixel type (`Model.PIXEL_FONT`) has the digits, `%`, `°`, `C` and the size letters the bar's rates need.
- `Glyph.qml`: the kit's icon. The kit is handed Nerd Font glyphs (`Model.GLYPHS`, escapes because the characters are invisible in most editors); `Glyph.qml` draws the pixel icon `Model.PIXEL_GLYPHS` gives each, so the kit's icons match the rooms'. Map a new glyph there. The one typed glyph left is the "Check now" button in the shared `UpdateSection`.
- `Updater.qml`, `Update.js`, `bin/plugin-update`: the shared updater, hosted by `ServerClient.qml`.
- `WidgetSettings.qml`: this widget's `shell.json` entry, read from the file (see below).
- `Model.js`: parses the probe, rates, formatting, the alert rules, and the Rooms look's pure logic (tones, the block face, the pixel type, meter cells, the prompt, icon stories, the mark). Tested by `tests/model.test.js`.
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

The panel is in the Rooms look Batteries 2.8 set and Sonus 1.8 carried on (the brief is `files get key:roomstheme`): each part of the server a room tinted in its own tone, numbers in a block face, pixel icons, and motion that answers what happens. The settings page keeps the panel kit, so it matches the other plugins. Scaled through `Style`.

- Panel `Style.space(380)`. Rooms: padding 10, joined by 3, `Style.cornerRadius`, the tone at 0.065 alpha, 0.11 under the pointer or while open. The keyboard's cursor adds a 1 px outline in the tone, so it reads apart from the pointer.
- Tones (`Model.roomTone`, `Model.roomToneHex`): System is the machine (blue), Disk storage and Network connections (cyan, side by side as Sonus's output and input share blue), Containers running things (green); the title room, Processes and the action rooms take none (the text colour). The theme's colour of that name from its `colors.toml` (read on each open) when it is a colour, else DailyDash's hue, softened 30% toward the text colour. Failures and anything running hot use `lowTone`. Only the panel and the hover card use tones; the bar keeps the bar's colours.
- A room's header: pixel icon at `font.heading` × 1.25 (20) in the tone, `font.body` bold name with a `font.caption` chevron that flips when the room is open, `font.caption` state dimmed, the figure as `BigFigure` on the `font.bodySmall` grid on the right (`font.caption` in a System cell). Units are in the pixel type: `%`, `°C`, none for a count.
- The tile row: Disk and Network are square tiles a quarter of the panel wide, the same size as the action rooms, padding 8; Containers fills the half beside them in the same shape. Each has a small header (`TileHeader`: icon at `font.bodySmall` and a bold name, no chevron, since beside one "Network" broke in two; the open tile stays tinted like its drawer), then its figure at the `font.caption` grid (`BigFigure.maxWidth` shrinks the blocks of a "100%" that would run out of the tile), then a five or ten cell meter or a second line. Network writes its rates in the pixel type (`5.5K/s`, `Model.rateParts`), small, as Sonus writes an app's volume. A tile has no room for its details, so the open one's drawer slides open full width under the row, in its tone, as Sonus opens its device list under its top row: every disk with its meter and where it lives; what went each way since boot; every container with stop, start and restart.
- Meters: ten cells across a room, five in a System cell, a tenth (or a fifth) each, track at 0.12, outline at 0.6, no nub. The disks' meters have a 1 px tick at 90%, where their alerts start. A disk after the root one shows its share in the small pixel type, so the room's own figure stays the big one.
- Clicks open things: System its load, swap, cores and what the machine is, plus its bar switches; the tiles their drawer under the row (above); Processes the rest of the list. One open at a time. Failed services hold still: no chevron, each restarts from its row. The four action rooms run their action (reboot and shutdown ask first).
- Prompt: `❯` and the line from `Model.heroLines`, typed at 22 ms a character behind a block cursor blinking at 530 ms, laid out whole from the first character so no word hops lines. A new fact every 2800 ms; a problem is the only line, so it holds still. While the cursor is on something it says what that does, at once. Keep those hints short and free of names.

Motion, all on one clock (`entry` goes up on each open and when the server first answers; `clock` ticks only while a ripple runs) and all off with reduced motion:

- Opening: rooms rise 12 and fade in, 70 ms apart; each meter fills from empty over 680 ms while its figure counts up (the container count with its meter of running ones; the rates on their own, in the unit they end in); state lines and readings decode out of scrambled glyphs; each icon plays its story (`Model.storyOf`); the mark's lights come on, top then bottom; the prompt types itself out.
- Pointer: cells under it give; a click ripples out through the room's meters (Weave's 760 ms), plays the icon again and opens the room, its drawer sliding over 280 ms.
- Changes while open: a level slides to its new value in 420 ms; text just changes. The refresh icon turns in quarters; the settings slide in from their side and the gear turns in 45° steps.
- Working (connecting, rebooting): the mark's lights take turns every 530 ms, in the panel and the bar.

Alerts never depend on colour alone. A monochrome theme's urgent colour can be a quiet grey, so `lowTone` falls back to the text colour when it has too little contrast, a hot reading gets the alert mark beside its figure, and the bar swaps the server mark for the alert.

## Panel kit

`SectionHeader`, `StatTile`, `ToggleTile`, `SwitchRow`, `Seg`, `Notice`, `LevelBar`, `OptionRow`, `Caption` and `UpdateSection` in the plugin folder are the panel kit: the same files, byte for byte, in ROG Deck, Batteries, Sonus and Server Dashboard, so the four look like one family. Change a kit file in all four or not at all. `Glyph.qml` is the one part each plugin owns: here it draws the pixel icon for each glyph (see Layout).

`Updater.qml`, `Update.js` and `bin/plugin-update` are the shared updater (ROG Deck, Batteries and Server Dashboard; Sonus's engine updates itself the same way). It stashes local edits, untracked files too, before fast-forwarding, and drops the stash when the edits already are the update. `tests/update.test.js` and `tests/test_plugin_update.py` cover it.

Panels never cut text: a `Notice` shows all of its message, a `Caption` breaks long words and paths, and a `ToggleTile` label that does not fit shows in full in its tooltip. The kit's `SwitchRow` cuts a long label, so the rooms' bar switches are a row of their own (`RoomPicks` in `Dashboard.qml`) whose label wraps. Every text that can hold a name (a container, a mount, a unit, a process) wraps with `Text.Wrap`, which breaks inside a word only when the word alone is wider than its column.

The scrollbar is a thin bar laid over the rooms' right padding, never a strip the rooms make room for: narrowing them reflowed every room each time it came and went. Whether it shows is `panel.overflowing`, worked out from what the panel wants against its height limit. Comparing the content with the scroll area's height had it flash in and out while a room opened, because the window grows a frame behind its content and the height is rounded.

To check a layout without opening the panel on someone's screen, run `Dashboard.qml` offscreen in a second quickshell with the shell's own `Commons` and `Ui` and a stand-in host as wide as the panel's content area (`Style.space(380)` less `Style.spacing.popupPadding` each side), as the Rooms brief describes, fed the worst data: long names with no spaces, three-digit figures, failed units, a full disk, every state at once.

## Rules that are easy to break

- **Settings** are read with `setting(key, fallback)` and saved with `persistSettings({...})`. Both go through `WidgetSettings.qml`, which reads `~/.config/omarchy/shell.json` itself. Never read `settings.foo` directly: the bar's copy turns a list into a Qt sequence that fails `Array.isArray`, and after a plugin reload it can be older than the file. Either one makes a pick look unset, which is how choices "reset after a reboot" or differ between monitors.
- **One widget per monitor.** The bar draws the widget on every screen. Long-running work (a poller, a client, a process) lives in one place, a leader instance or the service, and the others read from it. Never start it per instance.
- **IPC** is answered by whichever monitor's widget registered first, so `open`, `close` and `toggle` go through the shell's `summon`, `hide` and `toggle`, which pick the focused monitor.
- **Nothing may write inside the plugin folder at runtime.** The shell watches it and reloads every plugin when a file appears there. Python sets `sys.dont_write_bytecode`; state goes to `~/.local/state` or `~/.config`.
- **QML changes need `omarchy restart shell`.** Hot reload can keep the old component cached.
- **Pure logic goes in `Model.js`** (a `.pragma library` with no QML) so `node tests/*.test.js` can run it. Change it with a test. The tests check that every pixel icon the QML or the model names exists in `Pixels.js`, every kit glyph has a pixel icon, every string the bar writes can be drawn in the pixel type, and every icon story ends where it began.
- **Pixel art stays sharp.** `Rectangle`s with `antialiasing: false`, positions in whole cells of the icon's own grid (`PixelIcon.cell`), never `scale` or a turn other than a quarter (the gear's eighths are the one exception, and only while it turns).
- Comments say why, in plain sentences. Match the surrounding code.

## Release

Bump `version` in `manifest.json` and the version badge in `README.md` together, run the tests, and describe the change for the person using it in the commit message.
