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
  // Privileged helper: sealed root-owned copies + pins (see bin/lib/run.sh).
  // "unknown" until helper-check.sh reports; "missing"/"stale" route the
  // next privileged action through the provision dialog, "ok" runs it.
  property string helperState: "unknown"
  property string helperSource: ""
  property string pendingScript: ""
  property string pendingArgs: ""
  property bool pendingTerminal: false
  readonly property string helperRunPath: "/usr/local/share/omanomad/run.sh"
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
      // ui_location is a bare port ("8090"), an https port ("https:8480"),
      // or a path ("/chat"); "-"/empty means no UI of its own.
      var link = "";
      if (loc && loc !== "-" && loc !== "null") {
        if (loc.indexOf("https:") === 0) link = "https://localhost:" + loc.slice(6);
        else if (loc.charAt(0) === "/") link = "http://localhost:8080" + loc;
        else link = "http://localhost:" + loc;
      }
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
    if (!root.ensureHelper(script, "", false)) return;
    root.runPrivilegedNow(script);
  }

  function runPrivilegedNow(script) {
    if (actionProc.running) return;
    root.actionRunning = true;
    root.lastError = "";
    actionProc.command = ["pkexec", root.helperRunPath, script];
    actionProc.running = true;
  }

  function runInTerminal(script, args) {
    if (!root.ensureHelper(script, args, true)) return;
    root.runInTerminalNow(script, args);
  }

  function runInTerminalNow(script, args) {
    if (!root.bar) return;
    root.lastError = "";
    // Fixed root-owned bootstrap path plus panel-constant script names and
    // the single --purge-data flag; run.sh rejects anything else.
    var cmd = "omarchy-launch-floating-terminal-with-presentation pkexec "
      + root.helperRunPath + " " + script + (args ? " " + args : "");
    // Close first so the floating terminal that opens gets keyboard focus.
    root.close();
    root.bar.run(cmd);
  }

  // Gates a privileged action on the sealed helper: ready -> run now,
  // otherwise stash the request, refresh the helper state, and continue in
  // drainPending() once the check lands.
  function ensureHelper(script, args, terminal) {
    if (root.helperState === "ok") return true;
    root.pendingScript = script;
    root.pendingArgs = args;
    root.pendingTerminal = terminal;
    root.checkHelper();
    return false;
  }

  function drainPending() {
    if (root.pendingScript === "") return;
    if (root.helperState !== "ok") {
      provisionConfirmDialog.opened = true;
      return;
    }
    var script = root.pendingScript, args = root.pendingArgs, terminal = root.pendingTerminal;
    root.pendingScript = ""; root.pendingArgs = ""; root.pendingTerminal = false;
    if (terminal) root.runInTerminalNow(script, args);
    else root.runPrivilegedNow(script);
  }

  function checkHelper() {
    if (!helperCheckProc.running) {
      helperCheckProc.command = [scriptPath("helper-check.sh")];
      helperCheckProc.running = true;
    }
  }

  function parseHelperCheck(text) {
    var state = "unknown", source = "";
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("state=") === 0) state = lines[i].slice(6);
      else if (lines[i].indexOf("source=") === 0) source = lines[i].slice(7);
    }
    if (state !== "missing" && state !== "stale" && state !== "ok") state = "unknown";
    root.helperState = state;
    root.helperSource = source;
  }

  function provisionHelper() {
    var prov = scriptPath("lib/provision.sh");
    var binDir = prov.substring(0, prov.length - "/lib/provision.sh".length);
    provisionProc.command = ["pkexec", "bash", prov, binDir, root.helperSource];
    provisionProc.running = true;
  }

  function errorTail(text) {
    var lines = String(text || "").trim().split("\n");
    return lines.slice(Math.max(0, lines.length - 5)).join("\n");
  }

  // Remaining button actions (Install / Retry / Open). Start/Stop, Stack
  // update, and Uninstall live in the hero's icon rail instead. Dialogs
  // stay outside: single instances with no repetition to absorb.
  property var actionDefs: [
    { id: "install", text: "Install Project NOMAD", states: ["not-installed"] },
    { id: "retry", text: "Retry status check", states: ["unknown"] },
    { id: "open", text: "Open Command Center", states: ["running"] }
  ]

  function actionVisible(def) {
    return def.states.indexOf(root.nomadState) !== -1;
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
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    refresh();
    root.checkHelper();
    Qt.callLater(function() { keyCatcher.forceActiveFocus(); });
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

  Process {
    id: helperCheckProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseHelperCheck(text) }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.helperState = "unknown";
        root.lastError = "Privileged-helper check failed.";
        root.pendingScript = "";
      } else root.drainPending();
    }
  }

  Process {
    id: provisionProc
    stderr: StdioCollector { id: provisionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.errorTail(provisionStderr.text) || "Privileged-helper setup failed.";
        root.pendingScript = "";
      } else {
        root.helperState = "ok";
        root.drainPending();
      }
      root.refresh();
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
        if (provisionConfirmDialog.opened) provisionConfirmDialog.canceled();
        else if (purgeConfirmDialog.opened) purgeConfirmDialog.canceled();
        else if (uninstallConfirmDialog.opened) uninstallConfirmDialog.canceled();
        else if (chooserDialog.opened) chooserDialog.canceled();
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
            title: "OmaNomad (Project NOMAD)"
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
            trailingControl: Component {
              Row {
                spacing: Style.space(6)

                PanelActionButton {
                  iconText: "\uF011"
                  tooltipText: root.nomadState === "running" ? "Stop" : "Start"
                  foreground: root.foreground
                  hoverColor: root.foreground
                  fontFamily: root.fontFamily
                  enabled: (root.nomadState === "running" || root.nomadState === "stopped") && !root.actionRunning
                  onClicked: root.nomadState === "running"
                    ? root.runPrivileged("stop.sh")
                    : root.runPrivileged("start.sh")
                }

                PanelActionButton {
                  iconText: "\uF021"
                  tooltipText: "Stack update"
                  foreground: root.foreground
                  hoverColor: root.foreground
                  fontFamily: root.fontFamily
                  enabled: (root.nomadState === "running" || root.nomadState === "stopped") && !root.actionRunning
                  onClicked: root.runInTerminal("update.sh", "");
                }

                PanelActionButton {
                  iconText: "\uF1F8"
                  tooltipText: "Uninstall"
                  foreground: root.foreground
                  hoverColor: root.urgent
                  fontFamily: root.fontFamily
                  enabled: root.nomadState === "running" || root.nomadState === "stopped"
                  onClicked: chooserDialog.opened = true;
                }
              }
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
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.actionDefs.filter(function(def) { return root.actionVisible(def); })
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
          }
      }

      ChoiceDialog {
        id: chooserDialog
        anchors.fill: parent
        message: "Uninstall Project NOMAD?"
        choiceText: "Just uninstall"
        destructiveText: "Delete data too"
        selectedIndex: 1
        onCanceled: chooserDialog.opened = false
        onChosen: function(scope) {
          chooserDialog.opened = false;
          if (scope === "purge") purgeConfirmDialog.opened = true;
          else uninstallConfirmDialog.opened = true;
        }
      }

      ConfirmDialog {
        id: uninstallConfirmDialog
        anchors.fill: parent
        message: "Uninstall Project NOMAD? Containers and helpers are removed; storage, databases, and volumes are kept."
        confirmText: "Uninstall"
        onCanceled: uninstallConfirmDialog.opened = false
        onConfirmed: {
          uninstallConfirmDialog.opened = false;
          root.runInTerminal("uninstall.sh", "");
        }
      }

      ConfirmDialog {
        id: purgeConfirmDialog
        anchors.fill: parent
        message: "Delete everything, including all NOMAD data in /opt/project-nomad? This cannot be undone."
        confirmText: "Delete all data"
        onCanceled: purgeConfirmDialog.opened = false
        onConfirmed: {
          purgeConfirmDialog.opened = false;
          root.runInTerminal("uninstall.sh", "--purge-data");
        }
      }

      ConfirmDialog {
        id: provisionConfirmDialog
        anchors.fill: parent
        message: root.helperState === "stale"
          ? "Refresh the privileged helper? The plugin checkout changed since the helper was sealed; this recopies the scripts into /usr/local/share/omanomad and re-pins them. Only proceed if you trust this copy of the plugin."
          : "Install the privileged helper? Install, update, and uninstall run as root through scripts sealed in /usr/local/share/omanomad and verified on every run. This one-time setup copies them there from this checkout — only proceed if you trust this copy of the plugin."
        confirmText: root.helperState === "stale" ? "Refresh helper" : "Install helper"
        onCanceled: {
          provisionConfirmDialog.opened = false;
          root.pendingScript = ""; root.pendingArgs = ""; root.pendingTerminal = false;
        }
        onConfirmed: {
          provisionConfirmDialog.opened = false;
          root.provisionHelper();
        }
      }
    }
  }
}
