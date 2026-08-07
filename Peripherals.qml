import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui
import qs.Commons

// Omarchy bar widget + popup panel: battery levels for wireless peripherals.
//
// All the UPower work lives in PeripheralsCore.qml, which has no Omarchy
// dependency. This file is the bar chips, the panel, and the keyboard model.
Panel {
  id: root
  moduleName: "tpatzelt.peripherals"
  ipcTarget: "tpatzelt.peripherals"

  // ── Settings, from this widget's shell.json layout entry ────────────────
  // Defaults here mirror manifest.json's barWidget.defaults.
  readonly property real intervalSec: setting("interval", 120)
  readonly property real lowPercent: setting("lowPercent", 20)
  readonly property bool includeInternal: setting("includeInternal", false)
  readonly property var excludeKinds: setting("exclude", [])

  // Show every peripheral on the bar, or only the emptiest one. A desk with a
  // mouse, a keyboard and a headset is three chips; some people want three,
  // some want the one that is about to die.
  readonly property bool showAll: setting("showAll", true)
  readonly property int maxChips: setting("maxChips", 3)
  // Hide chips above this level, so a full mouse costs no bar space. 100 shows
  // everything, which is the default.
  readonly property real chipBelowPercent: setting("chipBelowPercent", 100)
  readonly property bool showIcons: setting("showIcons", true)

  // A desktop notification the first time a device drops below lowPercent.
  readonly property bool notify: setting("notify", true)

  readonly property string rightClickCommand: setting("onRightClick", "")

  // Advanced: the command whose output gets parsed. Point it at a captured
  // dump (["cat", "/path/to/upower.txt"]) to see how the widget will look with
  // devices you don't currently have, or at a wrapper on a system where
  // UPower lives somewhere unusual.
  readonly property var dumpCommand: setting("dumpCommand", ["upower", "--dump"])

  // Nerd Font glyphs per UPower device kind. Written as escapes rather than
  // literal astral-plane characters so the file survives any editor or
  // transport that mangles them. Override any of them from shell.json.
  readonly property string mouseIcon: setting("mouseIcon", "\udb80\udf7d")
  readonly property string keyboardIcon: setting("keyboardIcon", "\udb80\udf0c")
  readonly property string headsetIcon: setting("headsetIcon", "\udb80\udecb")
  readonly property string gamepadIcon: setting("gamepadIcon", "\uf11b")
  readonly property string phoneIcon: setting("phoneIcon", "\uf10b")
  readonly property string penIcon: setting("penIcon", "\uf040")
  readonly property string genericIcon: setting("genericIcon", "\uf240")

  // Panel (qs.Ui) is a plain Item \u2014 unlike BarWidget it does not lift the
  // host's geometry, so a widget built on it has to read `vertical` itself.
  readonly property bool vertical: bar ? bar.vertical : false

  PeripheralsCore {
    id: gear
    intervalMs: Math.max(5000, Math.round(root.intervalSec * 1000))
    lowPercent: root.lowPercent
    includeInternal: root.includeInternal
    excludeKinds: root.excludeKinds
    dumpCommand: root.dumpCommand

    onWentLow: function (name, percent) {
      if (!root.notify) return
      notifyProc.command = ["notify-send", "-u", "normal", "-a", "peripherals",
                            name + " battery low", Math.round(percent) + "% remaining"]
      notifyProc.running = true
    }
  }

  Process { id: notifyProc }

  // ── Derived state ───────────────────────────────────────────────────────

  function iconFor(entry) {
    if (!entry) return genericIcon
    switch (entry.kind) {
      case "mouse": return mouseIcon
      case "touchpad": return mouseIcon
      case "keyboard": return keyboardIcon
      case "headset": return headsetIcon
      case "headphones": return headsetIcon
      case "gaming-input": return gamepadIcon
      case "phone": return phoneIcon
      case "tablet": return phoneIcon
      case "media-player": return phoneIcon
      case "pen": return penIcon
      default: return genericIcon
    }
  }

  function isLow(entry) {
    return !!entry && entry.percent <= lowPercent && entry.state !== "charging"
  }

  // What the bar actually renders. Charging devices are never hidden by
  // chipBelowPercent — a peripheral on the charger is exactly the one you
  // want to see climb.
  readonly property var chips: {
    var out = []
    for (var i = 0; i < gear.devices.length; i++) {
      var d = gear.devices[i]
      if (d.percent > chipBelowPercent && d.state !== "charging") continue
      out.push(d)
      if (!showAll || out.length >= Math.max(1, maxChips)) break
    }
    return out
  }

  readonly property string barTooltip: {
    if (gear.lastError !== "") return gear.lastError
    if (gear.count === 0) return "No wireless peripherals"
    var parts = []
    for (var i = 0; i < gear.devices.length; i++) {
      var d = gear.devices[i]
      var state = gear.stateLabel(d)
      parts.push(d.name + "  " + Math.round(d.percent) + "%"
                 + (state !== "" ? "  ·  " + state : ""))
    }
    return parts.join("\n")
  }

  // ── Keyboard cursor ─────────────────────────────────────────────────────
  // Mirrors the first-party panels: one highlight on screen at a time, shared
  // by mouse hover and j/k, driven from here rather than from each row's own
  // containsMouse.
  property bool cursorActive: false
  property int selectedIndex: -1

  function selectByDelta(delta) {
    if (gear.devices.length === 0) return
    var next = selectedIndex + delta
    selectedIndex = Math.max(0, Math.min(gear.devices.length - 1, next))
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  function openPanel() {
    cursorActive = false
    selectedIndex = -1
    gear.refresh()
    root.open()
  }

  function handleBarPress(button) {
    if (button === Qt.RightButton) {
      if (rightClickCommand !== "" && root.bar) root.bar.run(rightClickCommand)
      else gear.refresh()
      return
    }
    if (button === Qt.MiddleButton) { gear.refresh(); return }
    if (root.opened) root.close()
    else root.openPanel()
  }

  // Two steps, so "getting low" and "act now" are distinguishable at a glance
  // rather than only at the threshold itself.
  function meterColor(entry) {
    if (!entry) return root.bar.foreground
    if (entry.state === "charging" || entry.state === "fully-charged") return root.bar.foreground
    if (entry.percent <= root.lowPercent) return root.bar.urgent
    if (entry.percent <= root.lowPercent * 2) return Qt.lighter(root.bar.urgent, 1.5)
    return root.bar.foreground
  }

  // ── Bar widget ──────────────────────────────────────────────────────────

  // A machine with no wireless peripherals — a desktop on a wired keyboard, a
  // laptop with nothing paired — has nothing to say, so the widget takes no
  // bar space there at all.
  visible: gear.ready && chips.length > 0
  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  Grid {
    id: layout
    anchors.centerIn: parent
    // One column stacks the chips on a vertical bar; a high column count keeps
    // them on a single row otherwise.
    columns: root.vertical ? 1 : 99

    Repeater {
      model: root.chips

      WidgetButton {
        required property var modelData
        bar: root.bar
        text: {
          var value = Math.round(modelData.percent) + "%"
          if (!root.showIcons || root.vertical) return value
          return root.iconFor(modelData) + " " + value
        }
        active: root.isLow(modelData)
        fontSize: Style.font.caption
        horizontalMargin: 4
        tooltipText: modelData.name + "  ·  " + Math.round(modelData.percent) + "%"
          + (gear.stateLabel(modelData) !== "" ? "  ·  " + gear.stateLabel(modelData) : "")
        onPressed: function (b) { root.handleBarPress(b) }
      }
    }
  }

  // ── Panel ───────────────────────────────────────────────────────────────

  KeyboardPanel {
    id: panel
    anchorItem: layout
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        // The first keypress only lights the cursor up where it already is,
        // so j doesn't skip the top row on the way in.
        if (!root.cursorActive) {
          root.cursorActive = true
          if (root.selectedIndex < 0) root.selectedIndex = 0
          return
        }
        if (dy !== 0) root.selectByDelta(dy)
      }

      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) { if (t === "r" || t === "R") gear.refresh() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: whichever peripheral is emptiest ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight,
                                     heroValue.implicitHeight)

            Text {
              id: heroIcon
              text: root.iconFor(gear.lowest)
              color: root.meterColor(gear.lowest)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: heroValue
              text: gear.lowest ? Math.round(gear.lowest.percent) + "%" : "—"
              color: root.meterColor(gear.lowest)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroValue.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: gear.lowest ? gear.lowest.name : "Peripherals"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: {
                  if (gear.lastError !== "") return gear.lastError
                  if (!gear.lowest) return "NOTHING PAIRED"
                  var state = gear.stateLabel(gear.lowest)
                  return state !== "" ? state.toUpperCase() : gear.lowest.kind.toUpperCase()
                }
                color: gear.lastError !== "" ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }
            }
          }

          UsageMeter {
            width: parent.width
            height: Style.space(6)
            percent: gear.lowest ? gear.lowest.percent : 0
            fillColor: root.meterColor(gear.lowest)
          }
        }

        PanelSeparator {
          visible: gear.count > 1
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          visible: gear.count > 1
          text: "DEVICES"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        // Cap the height so a very well-equipped desk can't push the panel
        // off-screen. ListView over Repeater buys positionViewAtIndex, which
        // keeps the keyboard-selected row scrolled into view.
        ListView {
          id: list
          width: parent.width
          visible: gear.count > 1
          height: Math.min(contentHeight, Style.space(240))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          model: gear.devices
          currentIndex: root.selectedIndex
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          // Wrapper takes the required props from ListView's delegate context,
          // which doesn't bind into nested `component` declarations, and passes
          // them down explicitly.
          delegate: Item {
            required property var modelData
            required property int index
            width: ListView.view.width
            height: deviceRow.implicitHeight

            DeviceRow {
              id: deviceRow
              width: parent.width
              entry: modelData
              index: parent.index
            }
          }
        }
      }
    }
  }

  // ── Components ──────────────────────────────────────────────────────────

  // A plain two-rectangle meter rather than a ProgressBar: the Controls style
  // in use is not guaranteed to follow the bar's own theme colours, and a
  // battery gauge that ignores the theme is worse than no gauge.
  component UsageMeter: Rectangle {
    id: meter
    property real percent: 0
    property color fillColor: root.bar.foreground

    radius: height / 2
    color: Style.selectedFillFor(root.bar.foreground, Color.accent)

    Rectangle {
      height: parent.height
      radius: parent.radius
      color: meter.fillColor
      width: parent.width * Math.max(0, Math.min(1, meter.percent / 100))

      Behavior on width {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }
    }
  }

  // One peripheral: icon, name and level on top, its own meter underneath.
  component DeviceRow: CursorSurface {
    id: row
    required property var entry
    required property int index

    hasCursor: root.cursorActive && root.selectedIndex === index
    foreground: root.bar.foreground
    implicitHeight: rowBody.implicitHeight

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true

      // Move the cursor here when the mouse enters; leaving doesn't clear it,
      // so subsequent j/k pick up from the row the mouse last sat on.
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.selectedIndex = row.index
      }
    }

    Column {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(6)
      spacing: Style.space(5)
      bottomPadding: Style.space(7)

      Item {
        width: parent.width
        implicitHeight: Math.max(rowIcon.implicitHeight, rowName.implicitHeight,
                                 rowValue.implicitHeight)

        Text {
          id: rowIcon
          text: root.iconFor(row.entry)
          color: root.meterColor(row.entry)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.iconLarge
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: rowValue
          text: row.entry ? Math.round(row.entry.percent) + "%" : "—"
          color: root.meterColor(row.entry)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: rowName
          anchors.left: rowIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.right: rowValue.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: row.entry ? row.entry.name : ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      UsageMeter {
        width: parent.width
        height: Style.space(4)
        percent: row.entry ? row.entry.percent : 0
        fillColor: root.meterColor(row.entry)
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: row.entry ? gear.stateLabel(row.entry) : ""
        color: Qt.darker(root.bar.foreground, 1.6)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
