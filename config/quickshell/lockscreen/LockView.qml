// The lock page. Layout mirrors the old hyprlock.conf (positions in px on a 1920x1080 screen).
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

Item {
    id: view
    required property var shell

    // ── Theme (wallust, same file hyprlock used) ───────
    property color c8: "#7E8395"
    property color c9: "#B4BCD6"
    property color c12: "#BC5C69"
    property color c13: "#AF5CE5"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string monoProp: "JetBrainsMono Nerd Font Propo"
    function ic(cp) { return String.fromCodePoint(cp); }

    Process {
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/wallust/wallust-hyprland.conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const get = n => { const m = text.match(new RegExp("^\\$color" + n + " = rgb\\((\\w{6})\\)", "m")); return m ? "#" + m[1] : null; };
                view.c8 = get(8) || view.c8; view.c9 = get(9) || view.c9;
                view.c12 = get(12) || view.c12; view.c13 = get(13) || view.c13;
            }
        }
    }

    // ── Background: blurred, dimmed wallpaper ─────────
    Image {
        id: wall
        anchors.fill: parent
        source: "file://" + Quickshell.env("HOME") + "/.config/hypr/wallpaper_effects/.wallpaper_current"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
    }
    // ── Power buttons logic (on the page root so the buttons can call view.power / view.armed) ─
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: view.armed = "" }
    Process { id: powerProc }
    function power(action) {
        if (view.shell.preview) { armed = action; disarm.restart(); return; }
        if (armed === action) { powerProc.command = ["systemctl", action]; powerProc.running = true; armed = ""; }
        else { armed = action; disarm.restart(); }
    }

    // Fade the whole page in
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

    // ── Clock state ───────────────────────────────────
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: view.now = new Date() }

    // Frosted: blurred wallpaper, lifted toward white (unlock: blur and veil clear while the UI zooms away)
    readonly property bool unlocking: view.shell.unlocking
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blur: view.unlocking ? 0.0 : 1.0
        blurMax: 48
        brightness: view.unlocking ? 0.0 : -0.12
        saturation: view.unlocking ? 0.0 : -0.1
        Behavior on blur { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
        Behavior on brightness { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
    }
    Rectangle {               // milky white veil
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, view.unlocking ? 0 : 0.04)
        Behavior on color { ColorAnimation { duration: 650; easing.type: Easing.InOutCubic } }
    }

    Item {
        id: ui
        anchors.fill: parent
        opacity: view.unlocking ? 0 : 1
        scale: view.unlocking ? 1.06 : 1
        Behavior on opacity { NumberAnimation { duration: 480; easing.type: Easing.InCubic } }
        Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.InOutCubic } }


    Text {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -60
        text: Qt.formatTime(view.now, "hh:mm AP").split(" ")[0]
        color: view.c8
        font { family: view.mono; pointSize: 160; weight: Font.Thin }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 55
        text: Qt.formatTime(view.now, "AP") + "  :" + Qt.formatTime(view.now, "ss")
        color: Qt.rgba(1, 1, 1, 0.6)
        font { family: view.mono; pointSize: 22; weight: Font.Light }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 100
        text: Qt.formatDate(view.now, "dddd, d MMMM")
        color: view.c13
        font { family: view.mono; pointSize: 24; weight: Font.Light }
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 140
        width: 150; height: 1
        color: Qt.rgba(1, 1, 1, 0.12)
    }

    // ── User + password ───────────────────────────────
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 340
        text: Quickshell.env("USER")
        color: Qt.rgba(1, 1, 1, 0.78)
        font { family: view.mono; pointSize: 18; weight: Font.Light }
    }

    Rectangle {
        id: field
        width: 280; height: 60; radius: 12
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 260
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: view.unlocking ? view.c13 : (view.shell.failText !== "" ? view.c12 : (input.activeFocus && input.text.length ? view.c13 : view.c8))
        Behavior on border.color { ColorAnimation { duration: 200 } }
        // fade in when typing, like hyprlock's fade_on_empty
        opacity: input.text.length > 0 || view.shell.failText !== "" || view.shell.busy || view.unlocking ? 1 : 0.7
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        transform: Translate { id: shake; x: 0 }
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: shake; property: "x"; to: -12; duration: 50 }
            NumberAnimation { target: shake; property: "x"; to: 10; duration: 70 }
            NumberAnimation { target: shake; property: "x"; to: -6; duration: 70 }
            NumberAnimation { target: shake; property: "x"; to: 0; duration: 80; easing.type: Easing.OutCubic }
        }
        Connections { target: view.shell; function onFailed() { shakeAnim.restart(); input.text = ""; } }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: 14
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            passwordCharacter: "●"
            color: view.c13
            font { family: view.mono; pointSize: 14; letterSpacing: 4 }
            focus: true
            enabled: !view.shell.busy
            onAccepted: view.shell.tryUnlock(text)
            Keys.onEscapePressed: text = ""
            onTextChanged: if (text.length) view.shell.failText = ""
        }
        Text {               // success check
            anchors.centerIn: parent
            text: view.ic(0xf012c)
            color: view.c13
            font { family: view.monoProp; pointSize: 22 }
            scale: view.unlocking ? 1 : 0.2
            opacity: view.unlocking ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        Text {
            anchors.centerIn: parent
            visible: input.text.length === 0 && !view.unlocking
            text: view.shell.busy ? "checking…" : (view.shell.failText !== "" ? view.shell.failText : "password")
            color: view.shell.failText !== "" ? view.c12 : Qt.rgba(1, 1, 1, 0.55)
            font { family: view.mono; pointSize: 11; italic: true }
        }
    }
    // keep keyboard focus in the field whatever is clicked
    Timer { interval: 300; running: true; repeat: true; onTriggered: if (!input.activeFocus) input.forceActiveFocus() }

    Text {
        id: layoutLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 230
        color: Qt.rgba(1, 1, 1, 0.65)
        font { family: view.mono; pointSize: 12 }
        Process {
            running: true
            command: ["sh", "-c", "hyprctl devices -j | python3 -I -c 'import json,sys; k=[x for x in json.load(sys.stdin)[\"keyboards\"] if x.get(\"main\")]; print(k[0][\"active_keymap\"] if k else \"\")'"]
            stdout: StdioCollector { onStreamFinished: layoutLabel.text = text.trim() }
        }
    }

    // ── Music card ────────────────────────────────────
    MusicCard {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 120
        theme: view
    }

    // ── Power buttons (two clicks within 3 s) ─────────

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 150 - 23
        spacing: 80 - 46
        Repeater {
            model: [
                { act: "suspend",  icon: 0xf0904 },
                { act: "reboot",   icon: 0xf0709 },
                { act: "poweroff", icon: 0xf0425 }
            ]
            delegate: GrowButton {
                required property var modelData
                size: 46
                glyph: view.ic(modelData.icon)
                hot: modelData.act === "poweroff" || view.armed === modelData.act ? view.c12 : view.c13
                armed: view.armed === modelData.act
                restColor: Qt.rgba(1, 1, 1, 0.8)
                onClicked: view.power(modelData.act)
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 84
        text: ({ suspend: "Click again to sleep", reboot: "Click again to restart", poweroff: "Click again to shut down" })[view.armed] || ""
        color: view.c12
        opacity: view.armed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        font { family: view.mono; pointSize: 11; weight: Font.Light }
    }

    // ── Bottom-right info ─────────────────────────────
    Column {
        anchors.right: parent.right; anchors.rightMargin: 30
        anchors.bottom: parent.bottom; anchors.bottomMargin: 28
        spacing: 6
        Text { id: infoLine; anchors.right: parent.right; color: Qt.rgba(1, 1, 1, 0.75); font { family: view.mono; pointSize: 13 } }
        Text { id: uptimeLine; anchors.right: parent.right; color: Qt.rgba(1, 1, 1, 0.75); font { family: view.mono; pointSize: 13 } }
        Text {
            anchors.right: parent.right
            color: Qt.rgba(1, 1, 1, 0.75)
            font { family: view.mono; pointSize: 13 }
            readonly property var dev: UPower.displayDevice
            text: dev && dev.isPresent ? "Battery: " + Math.round(dev.percentage * 100) + "%" + (UPower.onBattery ? "" : " (Charging)") : ""
        }
    }
    Process {
        id: infoProc
        command: ["sh", "-c", "$HOME/.config/hypr/scripts/LockInfo.sh; uptime -p"]
        stdout: StdioCollector {
            onStreamFinished: { const l = text.trim().split("\n"); infoLine.text = l[0] || ""; uptimeLine.text = l[1] || ""; }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: infoProc.running = true }

    // ── Bottom-left weather ───────────────────────────
    Text {
        id: weather
        anchors.left: parent.left; anchors.leftMargin: 30
        anchors.bottom: parent.bottom; anchors.bottomMargin: 30
        color: Qt.rgba(1, 1, 1, 0.75)
        lineHeight: 1.15
        horizontalAlignment: Text.AlignLeft   // keep left even when a line is Arabic (RTL)
        font { family: view.mono; pointSize: 13; weight: Font.Light }
        Process {
            running: true
            command: ["sh", "-c", "cat $HOME/.cache/.weather_cache 2>/dev/null"]
            stdout: StdioCollector { onStreamFinished: weather.text = text.trim() }
        }
    }
    }
}
