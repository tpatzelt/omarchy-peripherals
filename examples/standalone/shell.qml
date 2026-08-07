// Minimal standalone Quickshell example — no Omarchy involved.
//
//   quickshell -p examples/standalone
//
// PeripheralsCore has no compositor or Omarchy dependencies, so any Quickshell
// config can instantiate it and bind to its outputs. This one draws a small
// always-on-top readout in the top-right corner of every screen, and stays
// invisible while nothing wireless is paired.
// Run this with ../../scripts/run-example.sh, which assembles a temporary
// config directory containing this file plus a copy of PeripheralsCore.qml.
//
// Quickshell only scans QML inside the config directory it is pointed at, so
// PeripheralsCore.qml has to sit next to the shell.qml that uses it. In your
// own config, copy it next to yours.
//
// No wireless peripherals to hand? Point the parser at a captured dump:
//
//   ./scripts/run-example.sh docs/sample-upower.txt
//
import QtQuick
import Quickshell

ShellRoot {
  PeripheralsCore {
    id: gear
    intervalMs: 15000
    // A fixture path passed to run-example.sh arrives as PERIPHERALS_DUMP.
    dumpCommand: Quickshell.env("PERIPHERALS_DUMP")
      ? ["cat", Quickshell.env("PERIPHERALS_DUMP")]
      : ["upower", "--dump"]
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: gear.ready && gear.count > 0

      anchors.top: true
      anchors.right: true
      margins.top: 8
      margins.right: 8
      implicitWidth: readout.implicitWidth + 24
      implicitHeight: readout.implicitHeight + 16
      color: "#cc1a1b26"

      Text {
        id: readout
        anchors.centerIn: parent
        font.family: "monospace"
        font.pixelSize: 13
        color: "#c0caf5"
        text: {
          var lines = []
          for (var i = 0; i < gear.devices.length; i++) {
            var d = gear.devices[i]
            // A dozen-character ASCII meter, so the example needs no theme.
            var filled = Math.round(d.percent / 100 * 12)
            var meter = ""
            for (var c = 0; c < 12; c++) meter += c < filled ? "█" : "░"
            var pct = Math.round(d.percent) + "%"
            while (pct.length < 4) pct = " " + pct
            var state = gear.stateLabel(d)
            lines.push(pct + " " + meter + "  " + d.name + "  [" + d.kind + "]"
                       + (state !== "" ? "  " + state : ""))
          }
          return lines.join("\n")
        }
      }
    }
  }
}
