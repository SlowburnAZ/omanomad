import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omanomad"
  ipcTarget: "omanomad"
  manageIpc: false

  // Poll state: unknown until the first status.sh run completes.
  property string nomadState: "unknown"
  property string lastError: ""
  property bool purgeData: false
  property bool actionRunning: false

  readonly property string glyph: ""
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: nomadState === "running" ? foreground : dim
  readonly property color barIconColor: nomadState === "running" ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string stateText: nomadState === "running" ? "Command Center running"
    : nomadState === "stopped" ? "Installed — stopped"
    : nomadState === "not-installed" ? "Not installed" : "Checking…"
  readonly property int pollIntervalMs: Math.max(5, root.setting("refreshIntervalSec", 30)) * 1000

  // Scripts live beside this file; resolve relative to it, never via a
  // hardcoded ~/.config path.
  function scriptPath(name) {
    return Qt.resolvedUrl("./bin/" + name).toString().replace(/^file:\/\//, "");
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }

  function refresh() {
    if (!statusProc.running) {
      statusProc.command = [scriptPath("status.sh")];
      statusProc.running = true;
    }
  }

  function parseState(text) {
    var s = String(text || "").trim().split(/\s+/)[0] || "";
    if (s === "running" || s === "stopped" || s === "not-installed") root.nomadState = s;
    else root.nomadState = "unknown";
  }

  function runPrivileged(script) {
    if (actionProc.running) return;
    root.actionRunning = true;
    root.lastError = "";
    actionProc.command = ["pkexec", "bash", scriptPath(script)];
    actionProc.running = true;
  }

  function runInTerminal(script, args) {
    if (!root.bar) return;
    var cmd = "omarchy-launch-floating-terminal-with-presentation pkexec bash "
      + shellQuote(scriptPath(script)) + (args ? " " + args : "");
    root.bar.run(cmd);
    // bar.run is fire-and-forget: re-poll on the next tick and on reopen.
    Qt.callLater(root.refresh);
  }

  function errorTail(text) {
    var lines = String(text || "").trim().split("\n");
    return lines.slice(Math.max(0, lines.length - 5)).join("\n");
  }

  // Single source of truth for state -> visible actions. Array order is
  // render order; `states` filters per nomadState. Purge row and dialogs
  // stay outside: single instances with no repetition to absorb.
  property var actionDefs: [
    { id: "install", text: "Install Project NOMAD", states: ["not-installed"], primary: true },
    { id: "open", text: "Open Command Center", states: ["running"], primary: true },
    { id: "start", text: "Start", states: ["stopped"], primary: true, needsIdle: true },
    { id: "stop", text: "Stop", states: ["running"], needsIdle: true },
    { id: "openDisabled", text: "Open Command Center", states: ["stopped"], enabled: false },
    { id: "update", text: "Update", states: ["stopped", "running"] },
    { id: "uninstall", text: "Uninstall…", states: ["stopped", "running"], danger: true }
  ]

  function actionVisible(def) {
    return def.states.indexOf(root.nomadState) !== -1;
  }

  function performAction(id) {
    if (id === "install") root.runInTerminal("install.sh", "");
    else if (id === "open") Qt.openUrlExternally("http://localhost:8080");
    else if (id === "start") root.runPrivileged("start.sh");
    else if (id === "stop") root.runPrivileged("stop.sh");
    else if (id === "update") root.runInTerminal("update.sh", "");
    else if (id === "uninstall") {
      if (root.purgeData) purgeDialog.opened = true;
      else uninstallDialog.opened = true;
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    refresh();
    Qt.callLater(function() { keyCatcher.forceActiveFocus(); });
  }

  Process {
    id: statusProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseState(text) }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.actionRunning = false;
      if (exitCode !== 0) root.lastError = root.errorTail(actionStderr.text);
      root.refresh();
    }
  }

  Timer {
    interval: root.pollIntervalMs
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open(); }
    function close(): void { root.close(); }
    function show(): void { root.open(); }
    function hide(): void { root.close(); }
    function toggle(): void { root.toggle(); }
    function refresh(): string { root.refresh(); return "ok"; }
    function status(): string { return root.nomadState; }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.glyph
        color: root.barIconColor
        opacity: root.nomadState === "running" ? 1.0 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.space(12)
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh();
      else root.toggle();
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (purgeDialog.opened) purgeDialog.canceled();
        else if (uninstallDialog.opened) uninstallDialog.canceled();
        else root.close();
      }
      onTabRequested: function(direction) { root.switchPanel(direction); }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh();
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Project NOMAD"
            meta: root.stateText
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.nomadState === "running" ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.glyph
                color: root.iconColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.lastError !== "" || root.actionRunning
            width: parent.width
            text: root.actionRunning ? "Working…" : root.lastError
            color: root.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.actionDefs
            delegate: Button {
              required property var modelData
              visible: root.actionVisible(modelData)
              width: parent.width
              text: modelData.text
              selected: !!modelData.primary
              foreground: modelData.danger ? root.urgent : undefined
              enabled: modelData.enabled !== false && (!modelData.needsIdle || !root.actionRunning)
              fontFamily: root.fontFamily
              onClicked: root.performAction(modelData.id)
            }
          }
          RowLayout {
            visible: root.nomadState === "stopped" || root.nomadState === "running"
            width: parent.width
            spacing: Style.space(8)

            ToggleSwitch {
              id: purgeToggle
              checked: root.purgeData
              foreground: root.foreground
              Layout.alignment: Qt.AlignVCenter
              onToggled: root.purgeData = !root.purgeData
            }

            Text {
              textFormat: Text.PlainText
              text: "Also delete all data (purge)"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              wrapMode: Text.WordWrap
            }
          }

        }
      }

      ConfirmDialog {
        id: uninstallDialog
        anchors.fill: parent
        message: "Uninstall Project NOMAD? Containers and helpers are removed; storage, databases, and volumes are kept."
        confirmText: "Uninstall"
        onCanceled: uninstallDialog.opened = false
        onConfirmed: {
          uninstallDialog.opened = false;
          root.runInTerminal("uninstall.sh", "");
        }
      }

      ConfirmDialog {
        id: purgeDialog
        anchors.fill: parent
        message: "Delete everything, including all NOMAD data in /opt/project-nomad? This cannot be undone."
        confirmText: "Delete all data"
        onCanceled: purgeDialog.opened = false
        onConfirmed: {
          purgeDialog.opened = false;
          root.runInTerminal("uninstall.sh", "--purge-data");
        }
      }
    }
  }
}
