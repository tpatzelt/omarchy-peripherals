# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-08

Initial release.

- Battery levels for wireless mice, keyboards, headsets, controllers, styluses
  and phones as a native Omarchy bar widget, with a keyboard-navigable panel
- The machine's own battery and AC adapter excluded by default, so the widget
  says only what Omarchy's battery indicator doesn't
- Emptiest device first everywhere: bar chip, panel hero, and list
- Edge-triggered low-battery notifications — one per device on the crossing,
  and silence for devices already low when the shell starts
- Paired-but-disconnected devices filtered out rather than shown at a stale 0%
- `chipBelowPercent` to keep full peripherals off the bar, with charging
  devices always visible
- Swappable `dumpCommand` so the parser can be exercised against a captured
  `upower --dump`; a sample fixture ships in `docs/sample-upower.txt`
- `PeripheralsCore.qml` usable standalone in any Quickshell config, with a
  runnable example under `examples/standalone`

[1.0.0]: https://github.com/tpatzelt/omarchy-peripherals/releases/tag/v1.0.0
