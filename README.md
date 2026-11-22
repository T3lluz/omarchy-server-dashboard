<div align="center">
  <img src="assets/icon.svg" width="72" height="72" alt="Server Dashboard" />
  <h1>Server Dashboard</h1>
  <p>A server in the Omarchy bar, over <b>SSH</b>, built for machines on <b>Tailscale</b>:<br/>
  live CPU, memory, disks, temperature and network, <b>Docker</b> containers and failed services, with restart, reboot and terminal actions.</p>
  <p>
    <img alt="Version" src="https://img.shields.io/badge/v1.5.0-111111?label=version" />
    <img alt="Omarchy 4" src="https://img.shields.io/badge/Omarchy-4-3ecbe6" />
    <img alt="Nothing installed on the server" src="https://img.shields.io/badge/server-agentless-3ecbe6" />
    <a href="https://github.com/T3lluz/omarchy-server-dashboard/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/T3lluz/omarchy-server-dashboard/actions/workflows/ci.yml/badge.svg" /></a>
    <img alt="License" src="https://img.shields.io/badge/license-MIT-34413e" />
  </p>
  <p><a href="#install"><b>Install</b></a> · <a href="#features">Features</a> · <a href="#connect">Connect</a> · <a href="#settings">Settings</a> · <a href="#security">Security</a></p>
  <img src="assets/preview.png" width="640" alt="The Server Dashboard panel twice: at rest, the title room with the server mark over rooms for the system (CPU, memory and temperature in big block digits over meters of cells), a row of small rooms for the disk, the network and the containers, and the processes, with SSH, Monitor, Reboot and Shutdown at the bottom; and with the System room open to its load, swap, processor and bar switches" />
</div>

## Features

- **A panel of rooms**, in the look Batteries and Sonus share. The system (CPU, memory and temperature, each in big block digits over a meter of cells), a row of small rooms for the disk (how full the root disk is), the network (download and upload) and the containers (how many run), and the processes each get a room tinted in a colour from your theme. Failed systemd services get one of their own, with restart, when there are any. SSH, btop, reboot and shutdown sit in four small rooms at the bottom, in reach however far the rest scrolls.
- **Click a room to open it:** the system's load, swap, processor and kernel; every disk with its meter and where it lives; what the network has moved since boot; every Docker container with start, stop and restart; the rest of the processes. Each room also holds the switches for what of it the bar shows.
- **It comes alive when it opens:** the rooms rise in, the meters fill while their numbers count up, the readings decode, and the server mark's lights come on. While the server connects or reboots the lights take turns. The line under the name types itself out: all clear, the uptime, the system, or what is wrong. Nothing moves with reduced motion on.
- **The bar shows what you pick:** the server mark alone, or with CPU, memory, root disk, temperature and network rates, as sharp pixel icons and digits in the bar's own colours. Something wrong turns the mark into an alert. Resting the pointer on it opens a card with every reading.
- **Notifications:** one when the server stops answering and one when it is back, and one for each new problem: a container turning unhealthy or restart-looping, a filesystem passing 90%, a systemd unit failing. Starting the shell never notifies about what was already wrong.
- **Nothing on the server:** every poll is one shell command reading `/proc`, `/sys`, `df`, `ps`, `docker` and `systemctl`, over a single multiplexed SSH session, so the server sees one login rather than one every few seconds.
- **Updates from the panel:** Settings says when a new version is on GitHub and installs it with one click. Edits you made in the plugin folder are kept in `git stash`, not lost.
- **Every monitor agrees:** the bar draws the widget once per screen; the first owns the connection, the others mirror it, and all of them read their settings straight from `shell.json`.

## Install

```bash
omarchy plugin add https://github.com/T3lluz/omarchy-server-dashboard.git --enable
```

Needs `openssh`, `secret-tool` (libsecret) with a running keyring, and `jq`; `tailscale` for the machine list and the "Tailscale is off" hint. The server needs `sshd`; the Docker and systemd sections appear when it has them.

## Connect

Click the bar icon. The panel opens on a connect form:

1. Type `user@host`, for example `casaos@100.64.0.10`. Online machines on your tailnet are listed under the form; click one to fill in its address.
2. Type the password and press Enter, or leave it empty to use your SSH keys.

The password is stored in your keyring (GNOME Keyring, via `secret-tool`) and handed to `ssh` through `SSH_ASKPASS`. It never appears in `shell.json`, in a command line, or on disk.

## Use

| Input | Action |
|-------|--------|
| Left click | Open or close the dashboard |
| Middle click | Refresh now |
| Right click | SSH shell on the server |
| `j` / `k`, arrows | Move between failed services, rooms, containers (while their room is open) and actions |
| `enter` | Open or close the room, restart the container or service, or run the action |
| `s` | Start or stop the selected container |
| `t` / `b` | SSH shell / btop (falls back to htop, then top) |
| `r` | Refresh |
| `c` | Settings: bar stats, alerts and connection |
| `esc` | Close the open room, then the panel |

Reboot, shutdown and service restarts use `sudo` on the server, fed the saved password. Container actions try `docker` first and fall back to `sudo`.

## Settings

The ⚙ button in the panel (or `c`) opens them. They are saved in the widget's entry in `~/.config/omarchy/shell.json`, and can be set from a terminal too, for example `omarchy bar set io.github.t3lluz.server-dashboard barTemp true --json`:

| Key | Default | Meaning |
|-----|---------|---------|
| `target` | | `user@host` |
| `port` | `22` | SSH port |
| `displayName` | | Shown instead of the server's hostname |
| `refreshIntervalSec` | `5` | Seconds between polls (2 to 120) |
| `barCpu` | `true` | CPU usage in the bar |
| `barRam` | `true` | Memory usage in the bar |
| `barDisk` | `false` | Root disk usage in the bar |
| `barTemp` | `false` | CPU temperature in the bar |
| `barNetwork` | `false` | Download and upload rates in the bar |
| `notify` | `true` | Desktop notifications for outages and new alerts |

With every `bar*` stat off the widget polls every 30 seconds while the panel is closed, enough to show an alert and notify.

## Commands

```bash
omarchy-shell io.github.t3lluz.server-dashboard toggle     # open on the focused monitor; open | close
omarchy-shell io.github.t3lluz.server-dashboard settings
omarchy-shell io.github.t3lluz.server-dashboard refresh
omarchy-shell io.github.t3lluz.server-dashboard status     # JSON: connection, CPU, memory, uptime
```

## Security

- Host keys are trusted on first use and pinned in `~/.local/state/omarchy-server-dashboard/known_hosts`. A changed key stops the connection before the password is sent; the panel then offers to trust the new key, which you should accept only if you reinstalled the server.
- A wrong password stops polling instead of retrying, so the widget will not trigger fail2ban.
- The multiplexed session socket lives in `$XDG_RUNTIME_DIR`, readable only by you, and closes after 10 minutes without use.

## Development

```bash
node tests/model.test.js
bash -n bin/server-dash
omarchy plugin validate .
omarchy restart shell    # pick up QML changes
```

`Model.js` parses the probe and holds the alert rules and the panel's pure logic, tested under node; `bin/server-dash` is the SSH side. Icons are [Pixelarticons](https://pixelarticons.com) (MIT), rasterised by `scripts/fetch-pixel-icons.py`. See [AGENTS.md](AGENTS.md) for how the pieces fit.

## License

MIT

One of a set of Omarchy plugins: [Batteries](https://github.com/T3lluz/omarchy-batteries) · [ROG Deck](https://github.com/T3lluz/omarchy-rog-deck) · [Sonus](https://github.com/T3lluz/omarchy-sonus) · **Server Dashboard**
