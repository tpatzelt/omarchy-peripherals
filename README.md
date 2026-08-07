<p align="center">
  <h1 align="center">omarchy-peripherals</h1>
  <p align="center">
    The battery levels your bar doesn't show — mouse, keyboard, headset, controller.
    <br />
    Read from UPower, warned about once, and never confused with your laptop's own battery.
  </p>
</p>

<p align="center">
  <a href="#install"><strong>Install</strong></a> ·
  <a href="#using-it"><strong>Using it</strong></a> ·
  <a href="#configuration"><strong>Configuration</strong></a> ·
  <a href="#standalone-quickshell"><strong>Standalone</strong></a> ·
  <a href="#how-it-works"><strong>How it works</strong></a>
</p>

---

Omarchy's battery indicator tells you about the machine. Nothing tells you
about the keyboard that dies mid-sentence, or that the headset you were about
to take a call on has 6% left. Every one of those devices already reports its
charge to UPower — it just never reaches your screen.

This widget puts them there: one small chip per peripheral, a panel with a
gauge for each, and one notification when something crosses your threshold.

## Features

- **Every wireless peripheral** — mice, keyboards, headsets and headphones,
  game controllers, styluses, tablets, phones; whatever UPower can see
- **Not your laptop battery** — the internal battery and the AC adapter are
  excluded by default, because Omarchy already shows those and duplicating them
  only buries the information you came for
- **Emptiest first** — the bar, the panel hero and the list all lead with the
  device about to die, not with whatever the daemon happened to enumerate first
- **One notification per device** — fired on the crossing below your threshold,
  not once per refresh for the rest of the week
- **Two-step colouring** — "getting low" and "act now" look different, so a
  threshold isn't the first warning you get
- **Charging is never hidden** — a peripheral on the charger stays on the bar
  even when `chipBelowPercent` would otherwise hide it, so you can watch it climb
- **Knows what's actually there** — paired-but-disconnected devices keep stale
  entries in UPower with a bogus percentage; those are filtered out
- **Sensible names** — "Logitech" + "Logitech MX Keys Mini" becomes
  *Logitech MX Keys Mini*, not the doubled version
- **Invisible when it has nothing to say** — a desktop with a wired keyboard
  never sees this widget at all
- **Testable without hardware** — the parser can be pointed at a captured
  `upower --dump`, and a sample fixture ships in `docs/`
- **Theme-native** — built from Omarchy's own bar and panel components
- **Reusable core** — `PeripheralsCore.qml` has no Omarchy dependency and works
  in any Quickshell config

## Install

```bash
omarchy plugin add https://github.com/tpatzelt/omarchy-peripherals.git --enable --yes
```

That clones into `~/.config/omarchy/plugins/tpatzelt.peripherals/` and adds the
widget to the right-hand bar section. Move it wherever you like:

```bash
omarchy bar move tpatzelt.peripherals --section right
```

> Plugins run as unsandboxed code inside `omarchy-shell`. Omarchy deliberately
> installs them **disabled** unless you pass `--enable`, so you can read the
> source first. It's two short QML files.

**Nothing on the bar means nothing was found.** Check what UPower can actually
see:

```bash
upower --dump | grep -A2 -E '^\s+(mouse|keyboard|headset|headphones|gaming-input|pen)$'
```

If your device isn't there, UPower isn't getting a battery level for it — pair
it, connect it, and check again. Bluetooth devices only report while connected.

### Manual install

```bash
git clone https://github.com/tpatzelt/omarchy-peripherals.git \
  ~/.config/omarchy/plugins/tpatzelt.peripherals
omarchy-shell shell rescanPlugins
omarchy plugin enable tpatzelt.peripherals
```

### Updating

```bash
omarchy plugin update tpatzelt.peripherals
```

### Uninstall

```bash
omarchy plugin remove tpatzelt.peripherals
```

## Using it

| Action | What it does |
| --- | --- |
| **Left-click** | Open the panel |
| **Right-click** | Refresh now (or run your own command — see `onRightClick`) |
| **Middle-click** | Refresh now |
| **Hover** | Every device, its level, and its state |
| `j` / `k`, `↓` / `↑` | Move between devices |
| `r` | Refresh now |
| `Tab` | Move to the next bar panel |
| `Esc` | Close |

The panel can also be opened from anywhere:

```bash
omarchy-shell tpatzelt.peripherals toggle
```

## Configuration

Settings live inline in the widget's entry in `~/.config/omarchy/shell.json`.
Changes there hot-reload; you do not need to restart the shell.

```json
{
  "id": "tpatzelt.peripherals",
  "lowPercent": 25,
  "chipBelowPercent": 60,
  "exclude": ["phone"]
}
```

| Key | Default | What it does |
| --- | --- | --- |
| `interval` | `120` | Seconds between refreshes |
| `lowPercent` | `20` | At or below this a device goes urgent and notifies once |
| `showAll` | `true` | Show every device on the bar. Off shows only the emptiest |
| `maxChips` | `3` | Cap on how many chips reach the bar |
| `chipBelowPercent` | `100` | Only show devices at or below this level. Charging devices are always shown |
| `notify` | `true` | One desktop notification per device as it crosses the threshold |
| `showIcons` | `true` | Turn off for a text-only readout if your font lacks Nerd Font glyphs |
| `includeInternal` | `false` | Include the machine's own battery and AC adapter |
| `exclude` | `[]` | UPower kinds to hide, e.g. `["phone", "media-player"]` |
| `onRightClick` | `""` | Empty means right-click refreshes |
| `mouseIcon` `keyboardIcon` `headsetIcon` `gamepadIcon` `phoneIcon` `penIcon` `genericIcon` | Nerd Font glyphs | Override any of them |

### A quieter bar

Keep the bar empty until something actually needs charging:

```json
{ "id": "tpatzelt.peripherals", "chipBelowPercent": 40 }
```

## Standalone Quickshell

`PeripheralsCore.qml` is plain QtQuick plus `Quickshell.Io` — no Omarchy
imports, no compositor assumptions. Copy it next to your own `shell.qml` and
bind to it:

```qml
PeripheralsCore {
  id: gear
  intervalMs: 120000
  lowPercent: 20
  onWentLow: function (name, percent) {
    console.log(name, "is at", Math.round(percent) + "%")
  }
}
```

A runnable example lives in `examples/standalone`:

```bash
./scripts/run-example.sh                         # this machine's UPower
./scripts/run-example.sh docs/sample-upower.txt  # a captured dump
```

Quickshell only scans QML **inside the config directory it is pointed at**, so
`PeripheralsCore.qml` has to sit next to the `shell.qml` that uses it — the
script assembles a temporary directory containing both.

### Core API

| Property | Type | Notes |
| --- | --- | --- |
| `ready` | `bool` | False until the first dump has been parsed |
| `devices` | `array` | `{ path, kind, vendor, model, name, serial, percent, state, warningLevel, rechargeable, timeToEmpty, internal }`, emptiest first |
| `count` | `int` | Number of matching devices |
| `lowest` | `object` | The emptiest device |
| `anyLow` | `bool` | The emptiest device is at or below `lowPercent` |
| `wentLow(name, percent)` | signal | Fires once per device as it crosses below |
| `stateLabel(entry)` | `string` | `Charging`, `Charged`, `3 days left`, … |
| `dumpCommand` | `array` | Defaults to `["upower", "--dump"]`; swap it to parse a fixture |
| `refresh()` | | Re-read now |

## How it works

**UPower, parsed as text.** `upower --dump` is a flat, indented block per
device, and the *kind* — `mouse`, `keyboard`, `headset` — is a bare word on its
own line rather than a `key: value` pair. The parser recognises it as "an
indented line with no colon in it", which is what distinguishes it from
`present:` and `rechargeable:` in the same block.

**History blocks are skipped explicitly.** A device with history contributes
hundreds of tab-separated sample rows that contain none of the fields wanted
here, and one of them would otherwise be mistaken for a device kind.

**The Daemon section ends the last device.** `upower --dump` finishes with an
unindented `Daemon:` block; without a rule that a left-margin line closes the
current device, its keys would be read as the last peripheral's.

**Disconnected devices are dropped.** UPower keeps entries for peripherals that
have been paired but are not connected, reporting `present: no` and a stale
percentage — usually `0%`, which would otherwise dominate an emptiest-first
list with a device that isn't even on your desk.

**Notifications are edge-triggered.** The set of devices already below the
threshold is kept between polls, and `wentLow` fires only for devices that
weren't in it. The first poll only seeds that set, so restarting the shell with
an already-flat mouse doesn't re-announce it.

**One highlight at a time.** The panel follows the first-party pattern: hover
and `j`/`k` write to the same cursor state on the root, so the mouse and the
keyboard can never paint two selected rows.

## Requirements

- Omarchy 4 (Quattro) or newer, with `omarchy-shell`
- `upower` — pulled in by essentially every desktop stack; `pacman -S upower`
  if it somehow isn't there
- `notify-send` for notifications (`libnotify`), or set `notify: false`
- A Nerd Font for the glyphs (Omarchy's default bar font has them). Set
  `showIcons: false` if yours doesn't

## Related

- [omarchy-sysmon](https://github.com/tpatzelt/omarchy-sysmon) — CPU, memory and
  network throughput
- [omarchy-diskspace](https://github.com/tpatzelt/omarchy-diskspace) —
  filesystem usage with a warning threshold
- [omarchy-systemd-widget](https://github.com/tpatzelt/omarchy-systemd-widget) —
  failed systemd units
- [omarchy-vpn-widget](https://github.com/tpatzelt/omarchy-vpn-widget) —
  NetworkManager VPN status and switching

## License

MIT — see [LICENSE](LICENSE).
