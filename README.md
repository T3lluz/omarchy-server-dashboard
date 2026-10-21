# Server Dashboard

An Omarchy bar widget that watches one Linux server over SSH, built for
servers reached over Tailscale. The bar shows a server mark with the stats
you pick (CPU and RAM by default, or none). Click it for a compact panel:

- CPU, RAM, root disk and CPU temperature dials
- Network rates, load and running containers on one line
- Alerts: unhealthy containers, a full root disk, reboot required
- Failed systemd services with restart
- Actions: SSH shell, btop/htop on the server, reboot, power off

Press **More** (or `e`) to expand it with:

- CPU, memory, download and upload history graphs
- System facts: OS, kernel, CPU, load, swap, tasks, uptime, reboot-required
- Every real filesystem with its usage bar
- Docker containers with start, stop and restart
- Top processes by CPU

The panel reopens the way you left it.

The colors, fonts, corner rounding and spacing come from the active Omarchy
theme, so the panel changes when you switch themes.

Nothing is installed on the server. Every poll is one shell command that reads
`/proc`, `/sys`, `df`, `ps`, `docker` and `systemctl`, sent over a single
multiplexed SSH session, so the server sees one login rather than one every
few seconds.

## Install

```sh
omarchy plugin add https://github.com/T3lluz/omarchy-server-dashboard.git --enable
```

Or by hand: copy this folder to
`~/.config/omarchy/plugins/io.github.t3lluz.server-dashboard/`, then run
`omarchy-shell shell rescanPlugins` and
`omarchy plugin enable io.github.t3lluz.server-dashboard`.

## Connect

Click the bar icon. The panel opens on a connect form:

1. Type `user@host`, for example `casaos@100.64.0.10`. Online machines on
   your tailnet are listed under the form; click one to fill in its address.
2. Type the password and press Enter.

The password is stored in your keyring (GNOME Keyring, via `secret-tool`)
and handed to `ssh` through `SSH_ASKPASS`. It never appears in `shell.json`,
in a command line, or on disk. The target and port are saved in the widget's
entry in `~/.config/omarchy/shell.json`.

Key-based logins also work: leave the password empty and the widget tries
your SSH keys.

## Use

| Input | Action |
|-------|--------|
| Left click | Open or close the dashboard |
| Middle click | Refresh now |
| Right click | Open an SSH shell on the server |
| `j` / `k`, arrows | Move between containers, services and actions |
| `enter` | Restart the selected container or service, or run the action |
| `s` | Start or stop the selected container |
| `e` | Expand or collapse the panel |
| `t` | SSH shell |
| `b` | btop (falls back to htop, then top) |
| `r` | Refresh |
| `c` | Settings: bar stats, panel and connection |
| `esc` | Close |

Reboot, power off and service restarts use `sudo` on the server, fed with the
saved password. Container actions try `docker` first and fall back to `sudo`.

## Settings

Click the ⚙ button in the panel (or press `c`) for the settings view. It has
the connection form, a **Show in the bar** switch for each stat, and
**Open expanded**. Changes apply immediately and are saved to
`~/.config/omarchy/shell.json`. Open it straight from a keybind with:

```sh
omarchy-shell io.github.t3lluz.server-dashboard settings
```

The same keys can also be set from a terminal, for example
`omarchy bar set io.github.t3lluz.server-dashboard barTemp true --json`:

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
| `panelExpanded` | `false` | Open the panel expanded |

Turn every `bar*` stat off to show only the server icon. The widget then
polls every 30 seconds while the panel is closed, only to color the icon
when the server goes away.

The bar draws the widget once per monitor. The first one owns the SSH
connection and the others mirror it, so the server sees one poller.

## Security notes

- Host keys are trusted on first use and pinned in
  `~/.local/state/omarchy-server-dashboard/known_hosts`. A changed key stops the
  connection before the password is sent. The panel then offers to trust the
  new key, which you should accept only if you reinstalled the server.
- A wrong password stops polling instead of retrying, so the widget will not
  trigger fail2ban.
- The multiplexed session socket lives in `$XDG_RUNTIME_DIR`, readable only by
  you, and closes after 10 minutes without use.

## Requirements

- `openssh`, `secret-tool` (libsecret) with a running keyring, `jq`
- `tailscale` for the machine list and the "Tailscale is off" hint
- A Linux server with `sshd`. Docker and systemd sections appear when present.

## Development

```sh
node tests/model.test.js
omarchy plugin validate ~/.config/omarchy/plugins/io.github.t3lluz.server-dashboard
omarchy-shell io.github.t3lluz.server-dashboard status
```

## License

MIT
