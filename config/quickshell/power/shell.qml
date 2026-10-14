// Power menu (replaces wlogout). Run: qs -p ~/.config/quickshell/power/shell.qml  (PowerMenu.sh toggles it)
// Lock and Sleep act at once; Log out / Restart / Shut down count down 3 s first (click again = now, Esc = cancel).
// Keys: ←/→ or Tab to move, Enter to choose, L U E R S shortcuts, Esc or a click on the background to close.
//@ pragma UseQApplication
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Shapes as Shapes
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
    property color c12: "#BC5C69"
    property color c14: "#89b4fa"
    property color danger: "#f38ba8"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string monoProp: "JetBrainsMono Nerd Font Propo"
    function ic(cp) { return String.fromCodePoint(cp); }

    Process {
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/wallust/wallust-hyprland.conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const get = n => { const m = text.match(new RegExp("^\\$color" + n + " = rgb\\((\\w{6})\\)", "m")); return m ? "#" + m[1] : null; };
                root.accent = get(13) || root.accent; root.c12 = get(12) || root.c12; root.c14 = get(14) || root.c14;
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
            // ── Header: clock, date, greeting ────────────
            Column {
                id: header
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: cards.top; anchors.bottomMargin: 40
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

            // ── Action orbs ──────────────────────────────
            Row {
                id: cards
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 80
                spacing: 44

                Repeater {
                    model: root.actions
                    delegate: Item {
                        id: orb
                        required property var modelData
                        required property int index
                        readonly property bool sel: root.current === index
                        readonly property bool isArmed: root.armed === modelData.id
                        readonly property bool lit: sel || isArmed
                        readonly property color hot: isArmed ? root.danger : root.accent
                        width: 160; height: 250

                        // fly out from the middle of the row, staggered
                        property real fly: 1
                        readonly property real toCenter: cards.width / 2 - (x + width / 2)
                        opacity: 1 - fly
                        transform: [
                            Translate { x: orb.toCenter * orb.fly; y: root.closing ? 40 : 0
                                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.InCubic } } },
                            Scale { origin.x: orb.width / 2; origin.y: 85; xScale: 1 - orb.fly * 0.6; yScale: 1 - orb.fly * 0.6 }
                        ]
                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: 40 + orb.index * 45 }
                            NumberAnimation { target: orb; property: "fly"; to: 0; duration: 700; easing.type: Easing.OutExpo }
                        }

                        Item {
                            id: disc
                            width: 136; height: 136
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 17
                            scale: mouse.pressed ? 0.92 : (orb.lit ? 1.16 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

                            // halo
                            Rectangle { id: haloSrc; anchors.fill: parent; radius: width / 2; color: orb.hot; visible: false }
                            MultiEffect {
                                source: haloSrc
                                anchors.fill: haloSrc
                                autoPaddingEnabled: true
                                shadowEnabled: true
                                shadowColor: orb.hot
                                shadowBlur: 1.0
                                shadowScale: 1.12
                                shadowOpacity: 1.0
                                blurMax: 64
                                opacity: orb.lit ? 0.9 : 0
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                            }

                            // rotating 3-colour ring (wallust 13 / 12 / 14, like the window borders)
                            Shape {
                                id: ring
                                anchors.centerIn: parent
                                width: 156; height: 156
                                preferredRendererType: Shape.CurveRenderer
                                opacity: orb.sel && !orb.isArmed ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                                property real angle: 0
                                NumberAnimation on angle { from: 0; to: 360; duration: 3200; loops: Animation.Infinite; running: ring.visible }
                                ShapePath {
                                    strokeWidth: 0; strokeColor: "transparent"
                                    fillRule: ShapePath.OddEvenFill
                                    fillGradient: Shapes.ConicalGradient {
                                        centerX: 78; centerY: 78; angle: ring.angle
                                        GradientStop { position: 0.0;  color: root.accent }
                                        GradientStop { position: 0.33; color: root.c12 }
                                        GradientStop { position: 0.66; color: root.c14 }
                                        GradientStop { position: 1.0;  color: root.accent }
                                    }
                                    PathAngleArc { centerX: 78; centerY: 78; radiusX: 78; radiusY: 78; startAngle: 0; sweepAngle: 360 }
                                    PathAngleArc { centerX: 78; centerY: 78; radiusX: 73; radiusY: 73; startAngle: 0; sweepAngle: 360; moveToStart: true }
                                }
                            }

                            // countdown arc
                            Canvas {
                                anchors.centerIn: parent
                                width: 158; height: 158
                                visible: orb.isArmed
                                property real p: orb.isArmed ? root.countdown : 0
                                onPChanged: requestPaint()
                                onPaint: {
                                    const c = getContext("2d"); c.reset();
                                    c.lineWidth = 5; c.lineCap = "round";
                                    c.strokeStyle = Qt.rgba(1, 1, 1, 0.12);
                                    c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 3, 0, 2 * Math.PI); c.stroke();
                                    c.strokeStyle = root.danger;
                                    c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 3, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * p); c.stroke();
                                }
                            }

                            // the orb
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: orb.lit ? Qt.rgba(0.16, 0.16, 0.24, 0.96) : Qt.rgba(1, 1, 1, 0.10) }
                                    GradientStop { position: 1.0; color: orb.lit ? Qt.rgba(0.07, 0.07, 0.11, 0.96) : Qt.rgba(1, 1, 1, 0.04) }
                                }
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, orb.lit ? 0.0 : 0.12)
                            }
                            Text {
                                anchors.centerIn: parent
                                text: orb.isArmed ? Math.ceil(root.countdown * 3) : root.ic(orb.modelData.icon)
                                color: orb.isArmed ? root.danger : (orb.sel ? "#ffffff" : Qt.rgba(1, 1, 1, 0.78))
                                font { family: root.monoProp; pixelSize: orb.isArmed ? 58 : 62; weight: Font.Bold }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                // little bounce when selected
                                scale: orb.sel ? 1.0 : 0.92
                                Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.5 } }
                            }
                        }

                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: disc.bottom; anchors.topMargin: 30
                            spacing: 8
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: orb.isArmed ? "Click to confirm" : orb.modelData.label
                                color: orb.isArmed ? root.danger : (orb.sel ? "#ffffff" : Qt.rgba(1, 1, 1, 0.6))
                                font { family: root.mono; pixelSize: orb.isArmed ? 15 : 19; weight: Font.Bold }
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 24; height: 24; radius: 7
                                color: orb.sel ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35) : Qt.rgba(1, 1, 1, 0.07)
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Text {
                                    anchors.centerIn: parent; text: orb.modelData.key
                                    color: Qt.rgba(1, 1, 1, orb.sel ? 0.95 : 0.5)
                                    font { family: root.mono; pixelSize: 12; weight: Font.Bold }
                                }
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: if (!root.armed) root.current = orb.index
                            onClicked: root.choose(orb.index)
                        }
                    }
                }
            }

            // ── Footer hint ──────────────────────────────
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: cards.bottom; anchors.topMargin: 36
                text: root.armed ? "Esc or click outside to cancel"
                                 : "←  →  move   ·   Enter  select   ·   Esc  close"
                color: Qt.rgba(1, 1, 1, 0.45)
                font { family: root.mono; pixelSize: 13 }
            }
        }
    }
}
