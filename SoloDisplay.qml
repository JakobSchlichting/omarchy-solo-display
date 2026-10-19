import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar indicator for scripts/solo-display, which does all the work: this file
// only shows whether solo mode is on and starts the script. The script keeps
// its snapshot in ~/.local/state/solo-display/state.json, so that file's
// presence is the on/off state, shared by the bar on every display (and by
// anything that runs the script directly, e.g. a keybinding).
//
// Left-click toggles. Right-click picks the display to keep, by connector
// name, the same way air.workspaces assigns its groups.
BarWidget {
  id: root
  moduleName: "js.solo-display"

  readonly property string pluginId: "js.solo-display"
  readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("scripts/solo-display"))
    .replace(/^file:\/\//, "").replace(/[?#].*$/, ""))
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/solo-display/state.json"

  readonly property string configuredMonitor: String(setting("monitor", ""))
  readonly property bool alwaysShow: setting("alwaysShow", false) === true

  property bool active: false
  property string activeMonitor: ""
  property bool busy: false
  property bool hovered: false
  property bool pickerOpen: false

  readonly property string targetLabel: root.configuredMonitor !== "" ? root.configuredMonitor : "the focused display"
  readonly property bool revealed: root.active || root.busy || root.pickerOpen || revealHost.revealInactiveIndicators

  function toggle() {
    if (root.busy) return
    root.busy = true
    busyTimeout.restart()
    // Detached: turning displays off destroys the bars (and this widget) on
    // them, which must not take the running script down too.
    Quickshell.execDetached([root.scriptPath, "toggle"])
  }

  function applyState(raw) {
    var next = false
    var monitor = ""
    try {
      var state = JSON.parse(String(raw || ""))
      next = !!state && typeof state === "object"
      monitor = next ? String(state.target || "") : ""
    } catch (error) {
      next = false
    }
    if (next !== root.active) root.busy = false
    root.active = next
    root.activeMonitor = monitor
  }

  function pickMonitor(name) {
    var next = {}
    for (var key in root.settings) next[key] = root.settings[key]
    next.monitor = name
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.pluginId, next)
  }

  function close() {
    root.pickerOpen = false
  }

  // Same reveal rules as omarchy.indicators: inactive indicators only show
  // while the center section is hovered, unless "Always Show" is set.
  QtObject {
    id: revealHost
    readonly property bool revealInactiveIndicators: root.alwaysShow || root.hovered
      || (root.bar && root.bar.centerSectionRevealHeld === true && root.bar.centerHoverRevealSuppressed !== true)
    function setIndicatorItemHovered(hovered) { root.hovered = hovered }
  }

  // `omarchy-shell js.solo-display toggle` — same path as a click. With a bar
  // per display only one instance receives it, which is all a toggle needs.
  IpcHandler {
    target: "js.solo-display"

    function toggle(): void {
      root.toggle()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
  }

  // Deleting a watched file doesn't always produce a change event, and the
  // watch is lost once it's gone; a slow re-read covers both.
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: stateFile.reload()
  }

  Timer {
    id: busyTimeout
    interval: 20000
    onTriggered: root.busy = false
  }

  implicitWidth: root.vertical ? indicator.implicitWidth : (root.revealed ? indicator.implicitWidth : 0)
  implicitHeight: root.vertical ? (root.revealed ? indicator.implicitHeight : 0) : indicator.implicitHeight
  clip: true

  Behavior on implicitWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
  Behavior on implicitHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  HoverHandler {
    onHoveredChanged: root.hovered = hovered
  }

  BarIndicator {
    id: indicator
    anchors.centerIn: parent
    bar: root.bar
    indicatorHost: revealHost
    active: root.active
    opacity: root.busy ? 0.6 : 1
    activeText: "󰍹"
    inactiveText: "󰍹"
    activeTooltipText: root.busy ? "Restoring displays…" : "Solo display on " + root.activeMonitor + " — click to restore all displays"
    inactiveTooltipText: root.busy ? "Switching to " + root.targetLabel + "…" : "Solo display: keep only " + root.targetLabel + " (right-click to change)"

    onPressed: function(button) {
      if (button === Qt.RightButton) root.pickerOpen = !root.pickerOpen
      else if (button === Qt.LeftButton) root.toggle()
    }
  }

  PopupCard {
    id: picker
    anchorItem: indicator
    owner: root
    bar: root.bar
    open: root.pickerOpen
    contentWidth: picker.fittedContentWidth(Style.space(260))
    contentHeight: picker.fittedContentHeight(pickerColumn.implicitHeight)

    Column {
      id: pickerColumn
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: "Solo display"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        text: "Display to keep"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      // An inline list rather than a Dropdown: the Dropdown's option list is a
      // nested popup that got clipped by this small popup window.
      Column {
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: {
            var names = []
            var screens = Quickshell.screens
            for (var i = 0; i < screens.length; i++) names.push(screens[i].name)
            if (root.configuredMonitor !== "" && names.indexOf(root.configuredMonitor) === -1) names.push(root.configuredMonitor)
            return names
          }

          delegate: Button {
            required property string modelData
            readonly property bool current: modelData === root.configuredMonitor
            width: parent.width
            leftAlign: true
            selected: current
            iconText: current ? "" : "󰍹"
            text: modelData
            foreground: Color.popups.text
            horizontalPadding: 8
            verticalPadding: 4
            onClicked: root.pickMonitor(modelData)
          }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Qt.darker(Color.popups.text, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        text: root.active
          ? "Solo mode is on for " + root.activeMonitor + ". A new choice applies the next time it's turned on."
          : "Every other display is turned off and workspaces " + String(root.setting("workspaces", "1-5")) + " move to this one."
      }
    }
  }
}
