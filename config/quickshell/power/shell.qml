// Power menu (replaces wlogout). Run: qs -p ~/.config/quickshell/power/shell.qml  (PowerMenu.sh toggles it)
// Lock and Sleep act at once; Log out / Restart / Shut down count down 3 s first (click again = now, Esc = cancel).
// Keys: ←/→ or Tab to move, Enter to choose, L U E R S shortcuts, Esc or a click on the background to close.
//@ pragma UseQApplication
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root
    settings.watchFiles: false

    // ── Theme (wallust) ───────────────────────────────
    property color accent: "#AF5CE5"
    property color danger: "#f38ba8"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string monoProp: "JetBrainsMono Nerd Font Propo"
    function ic(cp) { return String.fromCodePoint(cp); }

    Process {
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/wallust/wallust-hyprland.conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/^\$color13 = rgb\((\w{6})\)/m);
                if (m) root.accent = "#" + m[1];
            }
        }
    }

    readonly property var actions: [
        { id: "lock",     label: "Lock",      key: "L", icon: 0xf033e, confirm: false, doing: "" },
        { id: "suspend",  label: "Sleep",     key: "U", icon: 0xf04b2, confirm: false, doing: "" },
        { id: "logout",   label: "Log out",   key: "E", icon: 0xf0343, confirm: true,  doing: "Logging out" },
        { id: "reboot",   label: "Restart",   key: "R", icon: 0xf0709, confirm: true,  doing: "Restarting" },
        { id: "poweroff", label: "Shut down", key: "S", icon: 0xf0425, confirm: true,  doing: "Shutting down" }
    ]
    property int current: 0
    property string armed: ""          // action counting down
    property real countdown: 0         // 1 → 0 over 3 s
    property bool closing: false

    function run(id) {
        const home = Quickshell.env("HOME");
        const cmd = {
            lock:     ["bash", "-c", "sleep 0.25; " + home + "/.config/hypr/scripts/LockScreen.sh"],
            suspend:  ["bash", "-c", "sleep 0.3; systemctl suspend"],    // hypridle locks before sleep
            logout:   ["hyprctl", "dispatch", "exit"],
            reboot:   ["systemctl", "reboot"],
            poweroff: ["systemctl", "poweroff"]
        }[id];
        Quickshell.execDetached(cmd);
        close();
    }
    function choose(i) {
        const a = actions[i];
        current = i;
        if (!a.confirm || armed === a.id) { armed = ""; run(a.id); return; }
        armed = a.id; countdown = 1; countAnim.restart();
    }
    function cancel() { armed = ""; countAnim.stop(); }
    function close() { if (closing) return; closing = true; quitTimer.start(); }

    NumberAnimation {
        id: countAnim
        target: root; property: "countdown"; from: 1; to: 0; duration: 3000
        onFinished: if (root.armed) { const id = root.armed; root.armed = ""; root.run(id); }
    }
    Timer { id: quitTimer; interval: 260; onTriggered: Qt.quit() }

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
    property string uptime: ""
    Process {
        running: true
        command: ["uptime", "-p"]
        stdout: StdioCollector { onStreamFinished: root.uptime = text.trim().replace(/^up /, "up ") }
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "qs-power"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: page
            anchors.fill: parent
            focus: true
            opacity: root.closing ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            Keys.onPressed: event => {
                const k = event.key;
                if (k === Qt.Key_Escape) { root.armed ? root.cancel() : root.close(); }
                else if (k === Qt.Key_Left || k === Qt.Key_Backtab || k === Qt.Key_H) { root.cancel(); root.current = (root.current + root.actions.length - 1) % root.actions.length; }
                else if (k === Qt.Key_Right || k === Qt.Key_Tab) { root.cancel(); root.current = (root.current + 1) % root.actions.length; }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { root.choose(root.current); }
                else {
                    const i = root.actions.findIndex(a => a.key === event.text.toUpperCase());
                    if (i >= 0) root.choose(i); else return;
                }
                event.accepted = true;
            }

            // Dark tint over the live desktop (Hyprland blurs behind this layer)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.067, 0.067, 0.106, 0.55)
                MouseArea { anchors.fill: parent; onClicked: root.armed ? root.cancel() : root.close() }
            }
            // Soft accent glow behind the cards
            RadialGradient {
                anchors.centerIn: cards
                width: 1500; height: 760
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30) }
                    GradientStop { position: 0.5; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // ── Header: clock, date, greeting ────────────
            Column {
                id: header
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: cards.top; anchors.bottomMargin: 56
                spacing: 6
                property real shift: root.closing ? -20 : 0
                transform: Translate { y: header.shift }
                Component.onCompleted: { entry.start(); }
                NumberAnimation on opacity { id: entry; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic; running: false }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(root.now, "HH:mm")
                    color: "#ffffff"
                    font { family: root.mono; pixelSize: 96; weight: Font.Bold }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(root.now, "dddd, d MMMM") + (root.uptime ? "  ·  " + root.uptime : "")
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font { family: root.mono; pixelSize: 17 }
                }
                Item { width: 1; height: 10 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.armed
                        ? root.actions.find(a => a.id === root.armed).doing + " in " + Math.ceil(root.countdown * 3) + "…"
                        : "See you soon, " + Quickshell.env("USER")
                    color: root.armed ? root.danger : root.accent
                    font { family: root.mono; pixelSize: 20; weight: Font.DemiBold }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }

            // ── Action cards ─────────────────────────────
            Row {
                id: cards
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 60
                spacing: 22

                Repeater {
                    model: root.actions
                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool sel: root.current === index
                        readonly property bool isArmed: root.armed === modelData.id
                        readonly property color hot: modelData.confirm ? root.danger : root.accent
                        width: 150; height: 176

                        // staggered rise-in
                        opacity: 0
                        property real rise: 40
                        transform: Translate { y: card.rise + (root.closing ? 24 : 0) }
                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: 60 + card.index * 55 }
                            ParallelAnimation {
                                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                                NumberAnimation { target: card; property: "rise"; to: 0; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                            }
                        }

                        Rectangle {
                            id: face
                            anchors.fill: parent
                            radius: 26
                            color: card.isArmed ? Qt.rgba(card.hot.r, card.hot.g, card.hot.b, 0.22)
                                 : card.sel ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.06)
                            border.width: card.sel || card.isArmed ? 2 : 1
                            border.color: card.isArmed || card.sel ? card.hot : Qt.rgba(1, 1, 1, 0.08)
                            scale: mouse.pressed ? 0.95 : (card.sel ? 1.07 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            // icon disc with countdown ring
                            Item {
                                id: disc
                                width: 76; height: 76
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top; anchors.topMargin: 26
                                Rectangle {
                                    anchors.fill: parent; radius: width / 2
                                    color: card.sel || card.isArmed ? card.hot : Qt.rgba(1, 1, 1, 0.08)
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Canvas {
                                    id: ring
                                    anchors.fill: parent; anchors.margins: -7
                                    visible: card.isArmed
                                    property real p: card.isArmed ? root.countdown : 0
                                    onPChanged: requestPaint()
                                    onPaint: {
                                        const c = getContext("2d"); c.reset();
                                        c.lineWidth = 3.5; c.lineCap = "round"; c.strokeStyle = card.hot;
                                        c.beginPath();
                                        c.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * p);
                                        c.stroke();
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: card.isArmed ? Math.ceil(root.countdown * 3) : root.ic(card.modelData.icon)
                                    color: card.sel || card.isArmed ? "#11111b" : "#e6e9f5"
                                    font { family: root.monoProp; pixelSize: card.isArmed ? 32 : 34; weight: Font.Bold }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: disc.bottom; anchors.topMargin: 18
                                text: card.isArmed ? "Click to confirm" : card.modelData.label
                                color: card.sel || card.isArmed ? "#ffffff" : Qt.rgba(1, 1, 1, 0.75)
                                font { family: root.mono; pixelSize: card.isArmed ? 13 : 16; weight: Font.DemiBold }
                            }
                            // key hint
                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 10
                                width: 22; height: 22; radius: 7
                                color: Qt.rgba(1, 1, 1, card.sel ? 0.16 : 0.07)
                                Text {
                                    anchors.centerIn: parent; text: card.modelData.key
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font { family: root.mono; pixelSize: 11; weight: Font.Bold }
                                }
                            }
                        }
                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: if (!root.armed) root.current = card.index
                            onClicked: root.choose(card.index)
                        }
                    }
                }
            }

            // ── Footer hint ──────────────────────────────
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: cards.bottom; anchors.topMargin: 48
                text: root.armed ? "Esc or click outside to cancel"
                                 : "←  →  move   ·   Enter  select   ·   Esc  close"
                color: Qt.rgba(1, 1, 1, 0.45)
                font { family: root.mono; pixelSize: 13 }
            }
        }
    }
}
