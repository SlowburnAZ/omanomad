import QtQuick
import QtQuick.Controls
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
  property string notice: ""
  property bool actionRunning: false
  // Fast re-poll burst after a privileged action exits: the stack needs a
  // few seconds to move stopped <-> running.
  property int burstLeft: 0
  property bool statusFailed: false
  // Child components (Information Library, AI Assistant, ...) reported by
  // the Command Center API; best-effort, only rendered while running.
  property var components: []
  // Not-installed catalog entries stay collapsed behind a disclosure row
  // so the panel shows state, not a 13-row wall of dim text.
  property bool showAvailable: false
  readonly property var installedComponents: components.filter(function(c) { return c.installed; })
  readonly property var availableComponents: components.filter(function(c) { return !c.installed; })
  readonly property int pollIntervalMs: Math.max(5, root.setting("refreshIntervalSec", 30) || 30) * 1000

  readonly property color accent: Color.accent
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string stateText: nomadState === "running"
    ? "running · " + installedComponents.length + " component" + (installedComponents.length === 1 ? "" : "s")
    : nomadState === "stopped" ? "stopped"
    : nomadState === "not-installed" ? "not installed"
    : root.statusFailed ? "unreachable" : "checking…"

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
    if (!componentsProc.running) {
      componentsProc.command = [scriptPath("components.sh")];
      componentsProc.running = true;
    }
  }

  function parseComponents(text) {
    var installed = [], available = [];
    var lines = String(text || "").trim().split("\n");
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split("|");
      if (f.length < 3 || f[0] === "") continue;
      var loc = f.length > 3 ? f[3] : "-";
      // ui_location is a bare port ("8090") or a path ("/chat"); "-"/empty
      // means the component exposes no UI of its own.
      var link = loc && loc !== "-" && loc !== "null"
        ? (loc.charAt(0) === "/" ? "http://localhost:8080" + loc
                                 : "http://localhost:" + loc)
        : "";
      var row = { name: f[0], installed: f[1] === "1", status: f[2], link: link };
      (row.installed ? installed : available).push(row);
    }
    root.components = installed.concat(available);
  }

  function parseState(text) {
    var s = String(text || "").trim().split(/\s+/)[0] || "";
    if (s === "running" || s === "stopped" || s === "not-installed") root.nomadState = s;
    else root.nomadState = "unknown";
  }

  // Two launch paths, deliberately not unified: Start/Stop are
  // non-interactive (direct pkexec, exit-code capture below), while
  // Install/Update/Uninstall need a terminal for their prompts and are
  // fire-and-forget (bar.run offers no completion signal to unify on).
  // One adapter per path = hypothetical seam; don't merge them.

  function runPrivileged(script) {
    if (actionProc.running) return;
    root.actionRunning = true;
    root.lastError = "";
    root.notice = "";
    actionProc.command = ["pkexec", "bash", scriptPath(script)];
    actionProc.running = true;
  }

  function runInTerminal(script, args) {
    if (!root.bar) return;
    root.lastError = "";
    var cmd = "omarchy-launch-floating-terminal-with-presentation pkexec bash "
      + shellQuote(scriptPath(script)) + (args ? " " + args : "");
    root.bar.run(cmd);
    root.notice = "Continue in the floating terminal…";
    // bar.run is fire-and-forget: re-poll on the next tick and on reopen.
    Qt.callLater(root.refresh);
  }

  function errorTail(text) {
    var lines = String(text || "").trim().split("\n");
    return lines.slice(Math.max(0, lines.length - 5)).join("\n");
  }

  // Single source of truth for state -> visible actions. `group` picks the
  // render slot: primary full-width, controls pair, destructive pair.
  // Dialogs stay outside: single instances with no repetition to absorb.
  property var actionDefs: [
    { id: "install", text: "Install Project NOMAD", states: ["not-installed"], group: "primary" },
    { id: "retry", text: "Retry status check", states: ["unknown"], group: "primary" },
    { id: "open", text: "Open Command Center", states: ["running"], group: "primary" },
    { id: "start", text: "Start", states: ["stopped"], group: "controls", needsIdle: true },
    { id: "stop", text: "Stop", states: ["running"], group: "controls", needsIdle: true },
    { id: "update", text: "Stack update", states: ["stopped", "running"], group: "controls" },
    { id: "uninstall", text: "Uninstall", states: ["stopped", "running"], group: "danger" },
    { id: "uninstallPurge", text: "Uninstall + delete data", states: ["stopped", "running"], group: "danger" }
  ]

  function actionVisible(def) {
    return def.states.indexOf(root.nomadState) !== -1;
  }

  function actionsIn(group) {
    return root.actionDefs.filter(function(def) {
      return def.group === group && root.actionVisible(def);
    });
  }

  function statusWord(status) {
    return status === "running" ? "up"
      : status === "stopped" ? "down"
      : status === "unknown" ? "?" : status;
  }

  function performAction(id) {
    if (id === "install") root.runInTerminal("install.sh", "");
    else if (id === "retry") root.refresh();
    else if (id === "open") Qt.openUrlExternally("http://localhost:8080");
    else if (id === "start") root.runPrivileged("start.sh");
    else if (id === "stop") root.runPrivileged("stop.sh");
    else if (id === "update") root.runInTerminal("update.sh", "");
    else if (id === "uninstall") uninstallDialog.opened = true;
    else if (id === "uninstallPurge") purgeDialog.opened = true;
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    refresh();
    Qt.callLater(function() { keyCatcher.forceActiveFocus(); });
  } else {
    root.notice = "";
  }

  Process {
    id: statusProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseState(text) }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        if (root.statusFailed) { root.statusFailed = false; root.lastError = ""; }
      } else {
        root.statusFailed = true;
        root.nomadState = "unknown";
        root.lastError = root.errorTail(statusStderr.text) || ("Status check failed (exit " + exitCode + ").");
      }
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.actionRunning = false;
      if (exitCode !== 0) root.lastError = root.errorTail(actionStderr.text);
      else root.burstLeft = 3;

      root.refresh();
    }
  }

  Process {
    id: componentsProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseComponents(text) }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.components = [];
    }
  }

  // Slow background poll keeps the bar icon honest while closed; the open
  // panel polls at refreshIntervalSec, plus burstTimer after Start/Stop.
  Timer {
    interval: root.opened ? root.pollIntervalMs : 120000
    running: true
    repeat: true
    // First tick at startup, not 2 min in: the bar icon is state-colored
    // and would otherwise sit dim (unknown) after every shell restart.
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: burstTimer
    interval: 5000
    repeat: true
    running: root.opened && root.burstLeft > 0
    onTriggered: {
      root.burstLeft--;
      root.refresh();
    }
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
      Image {
        anchors.centerIn: parent
        source: Qt.resolvedUrl("./assets/nomad-logo.webp")
        height: Style.space(14)
        width: height * 0.87
        fillMode: Image.PreserveAspectFit
        mipmap: true
        opacity: root.nomadState === "running" ? 1.0 : 0.5
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
              Image {
                source: Qt.resolvedUrl("./assets/nomad-logo.webp")
                height: Style.font.display
                width: height * 0.87
                fillMode: Image.PreserveAspectFit
                mipmap: true
            }
          }

          Item {
            visible: root.nomadState === "running"
            width: parent.width
            height: Style.space(16)

            Rectangle {
              id: ccDot
              width: Style.space(8)
              height: Style.space(8)
              radius: Style.space(4)
              color: root.accent
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: ccName
              textFormat: Text.PlainText
              text: "Command Center"
              color: root.dim
              font.underline: true
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
              anchors.left: ccDot.right
              anchors.leftMargin: Style.space(8)
              anchors.right: ccStatus.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                width: parent.implicitWidth
                height: parent.implicitHeight
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally("http://localhost:8080");
              }
            }

            Text {
              id: ccStatus
              textFormat: Text.PlainText
              text: "up"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Repeater {
            model: root.nomadState === "running" ? root.installedComponents : []
            delegate: Item {
              required property var modelData
              width: parent.width
              height: Style.space(16)

              Rectangle {
                id: compDot
                width: Style.space(8)
                height: Style.space(8)
                radius: Style.space(4)
                color: modelData.status === "running" ? root.accent : root.urgent
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: compName
                textFormat: Text.PlainText
                text: modelData.name
                color: modelData.status === "running" ? root.dim : root.urgent
                font.underline: modelData.link !== ""
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                anchors.left: compDot.right
                anchors.leftMargin: Style.space(8)
                anchors.right: compStatus.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  visible: modelData.link !== ""
                  width: parent.implicitWidth
                  height: parent.implicitHeight
                  cursorShape: Qt.PointingHandCursor
                  onClicked: Qt.openUrlExternally(modelData.link);
                }
              }

              Text {
                id: compStatus
                textFormat: Text.PlainText
                text: root.statusWord(modelData.status)
                color: modelData.status === "running" ? root.dim : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          Row {
            visible: root.nomadState === "running" && root.availableComponents.length > 0
            width: parent.width

            Text {
              textFormat: Text.PlainText
              text: (root.showAvailable ? "▾" : "▸") + " Available (" + root.availableComponents.length + ")"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.NoWrap

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showAvailable = !root.showAvailable;
              }
            }
          }

          Repeater {
            model: root.nomadState === "running" && root.showAvailable ? root.availableComponents : []
            delegate: Text {
              required property var modelData
              textFormat: Text.PlainText
              width: parent.width - Style.space(16)
              leftPadding: Style.space(16)
              text: modelData.name
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.actionRunning || (root.nomadState === "unknown" && root.lastError === "")
            width: parent.width
            text: root.actionRunning ? "Working…" : "Checking…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.notice !== ""
            width: parent.width
            text: root.notice
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.14)
          }

          Repeater {
            model: root.actionsIn("primary")
            delegate: Button {
              required property var modelData
              width: parent.width
              text: modelData.text
              selected: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.performAction(modelData.id)
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.actionsIn("controls")
              delegate: Button {
                required property var modelData
                width: (parent.width - Style.space(8)) / 2
                text: modelData.text
                foreground: root.foreground
                enabled: !modelData.needsIdle || !root.actionRunning
                fontFamily: root.fontFamily
                onClicked: root.performAction(modelData.id)
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.actionsIn("danger")
              delegate: Button {
                required property var modelData
                width: (parent.width - Style.space(8)) / 2
                text: modelData.text
                foreground: root.urgent
                fontFamily: root.fontFamily
                onClicked: root.performAction(modelData.id)
              }
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
