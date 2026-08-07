import QtQuick
import Quickshell.Io

// Tracks the battery level of wireless peripherals — mice, keyboards,
// headsets, controllers, styluses, phones — via UPower.
//
// Deliberately free of any Omarchy or compositor dependency: plain QtQuick
// plus Quickshell.Io, so any Quickshell config can instantiate it and bind to
// the outputs. Peripherals.qml is the Omarchy bar widget and panel built on top.
//
// The laptop's own battery and the AC adapter are excluded on purpose: those
// are what a normal battery widget already shows. What nothing shows is the
// keyboard that is about to die mid-sentence.
QtObject {
  id: root

  // ── Configuration ───────────────────────────────────────────────────────

  // Peripheral batteries report in whole percent and drain over weeks. UPower
  // itself only refreshes most of them every couple of minutes.
  property int intervalMs: 120000

  // Below this a device counts as low. Exposed here rather than only in the
  // widget so a standalone user gets the same classification.
  property real lowPercent: 20

  // Include the machine's own battery and the AC adapter. Off by default —
  // Omarchy already has a battery indicator, and duplicating it in a widget
  // about peripherals only makes the real information harder to find.
  property bool includeInternal: false

  // Device kinds to hide. UPower's own vocabulary: mouse, keyboard, headset,
  // headphones, gaming-input, pen, touchpad, phone, tablet, media-player,
  // computer, ups, battery, line-power.
  property var excludeKinds: []

  // The command whose output gets parsed. Swappable so the parser can be
  // pointed at a captured `upower --dump` for testing, or at a wrapper on a
  // system where UPower lives somewhere unusual.
  property var dumpCommand: ["upower", "--dump"]

  property bool running: true

  // ── State ───────────────────────────────────────────────────────────────

  // False until the first dump has been parsed. Bind widget visibility to
  // this rather than rendering an empty frame while UPower is still starting.
  readonly property bool ready: _ready

  // Matching devices, emptiest first:
  //   { path, kind, vendor, model, name, serial, percent, state,
  //     warningLevel, rechargeable, timeToEmpty, internal }
  property var devices: []

  readonly property int count: devices.length
  // Emptiest first, so this is the one worth acting on.
  readonly property var lowest: devices.length > 0 ? devices[0] : null
  readonly property bool anyLow: !!lowest && lowest.percent <= lowPercent

  property string lastError: ""

  signal polled()
  // Emitted the first time a device crosses below lowPercent. Lets a widget
  // warn once rather than on every poll for the rest of the week.
  signal wentLow(string name, real percent)

  onExcludeKindsChanged: refresh()
  onIncludeInternalChanged: refresh()

  // ── Actions ─────────────────────────────────────────────────────────────

  function refresh() {
    if (!_pollProc.running) _pollProc.running = true
  }

  // ── Formatting ──────────────────────────────────────────────────────────

  // UPower prints "10.2 days", "3.4 hours", "45.0 minutes"; round it to
  // something that fits a panel row and doesn't imply false precision.
  function formatRuntime(text) {
    var m = String(text || "").match(/^([\d.]+)\s+(\w+)/)
    if (!m) return ""
    var value = parseFloat(m[1])
    var unit = m[2].replace(/s$/, "")
    if (!isFinite(value) || value <= 0) return ""
    return Math.round(value) + " " + unit + (Math.round(value) === 1 ? "" : "s")
  }

  function stateLabel(entry) {
    if (!entry) return ""
    if (entry.state === "charging") return "Charging"
    if (entry.state === "fully-charged") return "Charged"
    if (entry.state === "pending-charge") return "Waiting to charge"
    if (entry.timeToEmpty !== "") return formatRuntime(entry.timeToEmpty) + " left"
    return ""
  }

  // ── Internals ───────────────────────────────────────────────────────────

  property bool _ready: false
  // Devices already reported low, so wentLow() fires on the crossing rather
  // than once per poll for as long as the battery stays down.
  property var _lowSeen: ({})

  function _asList(value) {
    if (Array.isArray(value)) return value
    return typeof value === "string" && value !== "" ? [value] : []
  }

  // "Logitech MX Vertical" from a vendor and a model that often repeat each
  // other ("Logitech" + "Logitech MX Vertical"), falling back to the object
  // path's tail for a device that reports neither.
  function _name(vendor, model, path) {
    var v = String(vendor || "").trim()
    var m = String(model || "").trim()
    if (m !== "" && v !== "" && m.toLowerCase().indexOf(v.toLowerCase()) !== 0) return v + " " + m
    if (m !== "") return m
    if (v !== "") return v
    var tail = String(path || "").split("/").pop()
    return tail.replace(/_/g, " ") || "Device"
  }

  // upower --dump is a flat, indented block per device:
  //
  //   Device: /org/freedesktop/UPower/devices/mouse_dev_DC_CD_6A_5F_E1_D4
  //     native-path:  ...
  //     model:        MX Vertical
  //     power supply: no
  //     mouse                       <- the kind, alone on its own line
  //       percentage:   75%
  //       state:        discharging
  //   History (rate):               <- and then pages of samples
  //     1786139432  0.130  discharging
  //
  // The kind is a bare word at the device's own indent level, not a key, so
  // it needs recognising as "an indented line with no colon in it".
  function _apply(text) {
    var lines = String(text || "").split("\n")
    var out = []
    var cur = null
    var inHistory = false

    function flush() {
      if (!cur) return
      var deny = _asList(excludeKinds)

      var isInternal = cur.powerSupply || cur.path.indexOf("/DisplayDevice") >= 0
      var usable = cur.kind !== "" && cur.kind !== "line-power" && cur.percent >= 0
      // UPower keeps entries for peripherals that have been paired but are not
      // currently connected; those report present: no and a stale percentage.
      if (usable && cur.present && deny.indexOf(cur.kind) === -1
          && (includeInternal || !isInternal)) {
        cur.internal = isInternal
        cur.name = _name(cur.vendor, cur.model, cur.path)
        out.push(cur)
      }
      cur = null
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var trimmed = line.trim()

      if (trimmed.indexOf("Device:") === 0) {
        flush()
        inHistory = false
        cur = {
          path: trimmed.slice(7).trim(),
          kind: "", vendor: "", model: "", name: "", serial: "",
          percent: -1, state: "", warningLevel: "", timeToEmpty: "",
          rechargeable: false, present: true, powerSupply: false, internal: false
        }
        continue
      }
      if (!cur) continue

      // Anything else flush against the left margin ends the device block —
      // `upower --dump` finishes with an unindented "Daemon:" section whose
      // keys would otherwise be read as the last device's.
      if (trimmed !== "" && line.charAt(0) !== " " && line.charAt(0) !== "\t") {
        flush()
        inHistory = false
        continue
      }

      // History and Statistics blocks are tab-separated sample rows that can
      // run to hundreds of lines and contain none of the fields we want.
      if (trimmed.indexOf("History") === 0 || trimmed.indexOf("Statistics") === 0) {
        inHistory = true
        continue
      }
      if (trimmed === "") { inHistory = false; continue }
      if (inHistory) continue

      var colon = trimmed.indexOf(":")
      if (colon < 0) {
        // A bare indented word: the device kind. Only the first one counts —
        // "present", "rechargeable" and friends all carry colons.
        if (cur.kind === "" && /^[a-z][a-z-]*$/.test(trimmed)) cur.kind = trimmed
        continue
      }

      var key = trimmed.slice(0, colon).trim()
      var value = trimmed.slice(colon + 1).trim()

      if (key === "vendor") cur.vendor = value
      else if (key === "model") cur.model = value
      else if (key === "serial") cur.serial = value
      else if (key === "power supply") cur.powerSupply = value === "yes"
      else if (key === "present") cur.present = value !== "no"
      else if (key === "rechargeable") cur.rechargeable = value === "yes"
      else if (key === "state") cur.state = value
      else if (key === "warning-level") cur.warningLevel = value
      else if (key === "time to empty") cur.timeToEmpty = value
      else if (key === "percentage") {
        var pct = parseFloat(value.replace("%", ""))
        if (isFinite(pct)) cur.percent = Math.max(0, Math.min(100, pct))
      }
    }
    flush()

    // Emptiest first: the row that matters is the one about to die.
    out.sort(function (a, b) { return a.percent - b.percent })

    var seen = ({})
    for (var d = 0; d < out.length; d++) {
      var entry = out[d]
      var key2 = entry.path
      var isLow = entry.percent <= lowPercent && entry.state !== "charging"
      if (isLow) {
        seen[key2] = true
        if (!_lowSeen[key2] && _ready) wentLow(entry.name, entry.percent)
      }
    }
    _lowSeen = seen

    devices = out
    lastError = ""
    _ready = true
    polled()
  }

  property Process _pollProc: Process {
    command: root.dumpCommand
    stdout: StdioCollector {
      onStreamFinished: root._apply(text)
    }
    onExited: function (exitCode) {
      if (exitCode !== 0 && !root._ready) root.lastError = "could not read UPower"
    }
  }

  property Timer _timer: Timer {
    interval: Math.max(5000, root.intervalMs)
    running: root.running
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
