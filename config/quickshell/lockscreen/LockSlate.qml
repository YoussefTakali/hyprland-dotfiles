// Lock style "Slate" (default, 2026-10-28).
// The wallpaper stays whole and drifts slowly (Ken Burns). Everything else lives on one pane of dark glass on the
// left: stacked clock (hours white, minutes accent) with a seconds hairline, date, weather + status, a music card
// only while something plays, and the password pill. Unlock slides the glass away to the left.
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

    // ── Theme ─────────────────────────────────────────
    property color accent: "#AF5CE5"
    readonly property color danger: "#f38ba8"
    readonly property color ink: "#ffffff"
    readonly property color muted: Qt.rgba(1, 1, 1, 0.62)
    readonly property color faint: Qt.rgba(1, 1, 1, 0.38)
    readonly property string face: "Montserrat"
    readonly property string glyphs: "JetBrainsMono Nerd Font Propo"
    function ic(cp) { return String.fromCodePoint(cp); }
    Process {
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/wallust/wallust-hyprland.conf"]
        stdout: StdioCollector {
            onStreamFinished: { const m = text.match(/^\$color13 = rgb\((\w{6})\)/m); if (m) view.accent = "#" + m[1]; }
        }
    }

    // ── State ─────────────────────────────────────────
    readonly property bool unlocking: shell.unlocking
    readonly property bool busy: shell.busy
    readonly property bool failed: shell.failText !== "" && !busy
    property bool ready: false
    Timer { interval: 250; running: true; onTriggered: view.ready = true }
    readonly property bool away: unlocking || !ready        // glass off screen

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: view.now = new Date() }
    Component.onCompleted: if (view.shell.preview) input.text = Quickshell.env("QS_LOCK_PREVIEW_TEXT") || ""

    // ── Wallpaper, drifting ───────────────────────────
    Item {
        id: scene
        anchors.fill: parent
        clip: true
        Image {
            id: wall
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.config/hypr/wallpaper_effects/.wallpaper_current"
            fillMode: Image.PreserveAspectCrop
            transformOrigin: Item.Right
            property real drift: 1.0
            scale: view.unlocking ? 1.0 : drift
            Behavior on scale { enabled: view.unlocking; NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
            SequentialAnimation on drift {
                running: !view.unlocking
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.07; duration: 38000; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.07; to: 1.0; duration: 38000; easing.type: Easing.InOutSine }
            }
        }
    }
    // shade toward the glass so the edge never looks pasted on
    Rectangle {
        anchors.fill: parent
        opacity: view.away ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 650 } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.45) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.0) }
        }
    }

    // ── The glass ─────────────────────────────────────
    ShaderEffectSource { id: sceneTex; sourceItem: scene; live: true; hideSource: false; visible: false }

    Item {
        id: glass
        readonly property real m: 28
        y: m
        width: 580; height: view.height - 2 * m
        x: view.away ? -width - 60 : m
        Behavior on x { NumberAnimation { duration: view.unlocking ? 620 : 750; easing.type: view.unlocking ? Easing.InCubic : Easing.OutCubic } }
        transform: Translate { x: view.shakeX }

        // shadow
        Rectangle { id: shadowSrc; anchors.fill: parent; radius: 30; color: "black"; visible: false }
        MultiEffect {
            source: shadowSrc; anchors.fill: shadowSrc
            autoPaddingEnabled: true
            shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.45; shadowBlur: 1.0; shadowHorizontalOffset: 6
            blurMax: 48
        }
        ClippingRectangle {
            anchors.fill: parent
            radius: 30
            color: "transparent"
            // frosted copy of the wallpaper behind the pane
            MultiEffect {
                x: -glass.x - view.shakeX; y: -glass.y
                width: view.width; height: view.height
                source: sceneTex
                blurEnabled: true; blurMax: 64; blur: 1.0
                saturation: -0.1
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(0.06, 0.06, 0.1, 0.42) }
            // accent light falling from the top edge
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.20) }
                    GradientStop { position: 0.45; color: "transparent" }
                }
            }
            Image { anchors.fill: parent; source: "grain.png"; fillMode: Image.Tile; opacity: 0.045 }
        }
        Rectangle {
            anchors.fill: parent; radius: 30
            color: "transparent"
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
        }

        // ── Content ───────────────────────────────────
        Item {
            id: content
            anchors.fill: parent
            anchors.margins: 44

            // who is locked
            Row {
                id: who
                spacing: 12
                Rectangle {
                    width: 34; height: 34; radius: 17
                    color: view.accent
                    Text {
                        anchors.centerIn: parent
                        text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                        color: "#11111b"
                        font { family: view.face; pixelSize: 15; weight: Font.Bold }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Quickshell.env("USER")
                    color: view.ink
                    font { family: view.face; pixelSize: 16; weight: Font.DemiBold }
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: who.verticalCenter
                text: view.ic(0xf033e)
                color: view.faint
                font { family: view.glyphs; pixelSize: 18 }
            }

            // clock: numerals placed by their cap height (Montserrat digits ≈ 0.7 em), not by line boxes
            Item {
                id: clockBox
                anchors.top: who.bottom; anchors.topMargin: 40
                width: parent.width
                readonly property real px: 196
                readonly property real cap: px * 0.70
                readonly property real gap: 26
                height: cap * 2 + gap
                FontMetrics { id: fm; font.family: view.face; font.pixelSize: clockBox.px; font.weight: Font.Light }
                Text {
                    id: hours
                    x: -8
                    y: -(fm.ascent - clockBox.cap)
                    text: Qt.formatTime(view.now, "hh AP").split(" ")[0]
                    color: view.ink
                    font { family: view.face; pixelSize: clockBox.px; weight: Font.Light; letterSpacing: -3 }
                }
                Text {
                    anchors.left: hours.right; anchors.leftMargin: 12
                    y: 2
                    text: Qt.formatTime(view.now, "AP")
                    color: view.muted
                    font { family: view.face; pixelSize: 20; weight: Font.DemiBold; letterSpacing: 1 }
                }
                Text {
                    id: minutes
                    x: -8
                    y: hours.y + clockBox.cap + clockBox.gap
                    text: Qt.formatTime(view.now, "mm")
                    color: view.accent
                    font { family: view.face; pixelSize: clockBox.px; weight: Font.Light; letterSpacing: -3 }
                }
            }
            // seconds hairline
            Item {
                id: secs
                anchors.top: clockBox.bottom; anchors.topMargin: 34
                width: parent.width; height: 2
                Rectangle { anchors.fill: parent; radius: 1; color: Qt.rgba(1, 1, 1, 0.12) }
                Rectangle {
                    height: 2; radius: 1
                    color: view.accent
                    width: parent.width * view.now.getSeconds() / 59
                    Behavior on width { enabled: view.now.getSeconds() !== 0; NumberAnimation { duration: 950; easing.type: Easing.Linear } }
                }
            }
            Text {
                id: dateLine
                anchors.top: secs.bottom; anchors.topMargin: 22
                text: Qt.formatDate(view.now, "dddd, d MMMM")
                color: view.ink
                font { family: view.face; pixelSize: 24; weight: Font.Medium }
            }

            // weather + status
            Column {
                id: facts
                anchors.top: dateLine.bottom; anchors.topMargin: 26
                width: parent.width
                spacing: 12
                Repeater {
                    model: view.facts
                    delegate: Row {
                        required property var modelData
                        spacing: 14
                        Text {
                            width: 22; horizontalAlignment: Text.AlignHCenter
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: view.accent
                            font { family: view.glyphs; pixelSize: 17 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text
                            color: view.ink
                            font { family: view.face; pixelSize: 15; weight: Font.Medium }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.sub || ""
                            color: view.faint
                            font { family: view.face; pixelSize: 14 }
                        }
                    }
                }
            }

            // ── bottom stack: music, password, power ──
            Column {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 18

                // music card, only while there is a player
                Item {
                    width: parent.width
                    height: view.player ? 92 : 0
                    visible: height > 0
                    clip: true
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.fill: parent; radius: 20
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.07)
                    }
                    ClippingRectangle {
                        id: art
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 64; height: 64; radius: 14
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Image {
                            anchors.fill: parent
                            source: view.player ? (view.localArt || view.player.trackArtUrl) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(128, 128)
                        }
                    }
                    Column {
                        anchors.left: art.right; anchors.leftMargin: 14
                        anchors.right: controls.left; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            width: parent.width
                            text: view.player && view.player.trackTitle ? view.player.trackTitle : ""
                            color: view.ink
                            elide: Text.ElideRight
                            font { family: view.face; pixelSize: 15; weight: Font.DemiBold }
                        }
                        Text {
                            width: parent.width
                            text: view.player ? (view.player.trackArtist || "") : ""
                            color: view.muted
                            elide: Text.ElideRight
                            font { family: view.face; pixelSize: 13 }
                        }
                    }
                    Row {
                        id: controls
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        GrowButton {
                            size: 34; glyphSize: 13; restGlow: 0.0
                            glyph: view.ic(0xf04ae); hot: view.accent; restColor: view.muted
                            onClicked: if (view.player && view.player.canGoPrevious) view.player.previous()
                        }
                        GrowButton {
                            size: 40; glyphSize: 15; filled: true
                            glyph: view.ic(view.playing ? 0xf03e4 : 0xf040a)
                            onClicked: if (view.player) view.player.togglePlaying()
                        }
                        GrowButton {
                            size: 34; glyphSize: 13; restGlow: 0.0
                            glyph: view.ic(0xf04ad); hot: view.accent; restColor: view.muted
                            onClicked: if (view.player && view.player.canGoNext) view.player.next()
                        }
                    }
                    // progress along the bottom edge
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 1
                        x: 20; height: 2; radius: 1
                        readonly property real len: view.player ? view.player.length : 0
                        width: len > 0 ? (parent.width - 40) * Math.min(1, view.player.position / len) : 0
                        color: view.accent
                        opacity: 0.8
                    }
                }

                // password pill
                Rectangle {
                    id: pill
                    width: parent.width; height: 62; radius: 31
                    color: Qt.rgba(1, 1, 1, input.text.length ? 0.1 : 0.07)
                    border.width: 1
                    border.color: view.failed ? view.danger : (input.text.length ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.8) : Qt.rgba(1, 1, 1, 0.1))
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        x: 24; anchors.verticalCenter: parent.verticalCenter
                        text: view.ic(view.failed ? 0xf0341 : 0xf033e)
                        color: view.failed ? view.danger : view.faint
                        font { family: view.glyphs; pixelSize: 18 }
                    }
                    Text {
                        x: 58; anchors.verticalCenter: parent.verticalCenter
                        visible: input.text.length === 0
                        text: view.busy ? "Checking…" : "Password"
                        color: view.faint
                        font { family: view.face; pixelSize: 16; weight: Font.Medium }
                    }
                    Row {
                        x: 60; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Repeater {
                            model: Math.min(input.text.length, 24)
                            delegate: Rectangle {
                                required property int index
                                width: 9; height: 9; radius: 4.5
                                color: view.ink
                                opacity: view.busy ? 0.4 + 0.6 * Math.abs(Math.sin(wave.t - index * 0.25)) : 1
                                NumberAnimation on scale { from: 0; to: 1; duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                            }
                        }
                    }
                    QtObject { id: wave; property real t: 0 }
                    NumberAnimation { target: wave; property: "t"; running: view.busy; from: 0; to: Math.PI * 4; duration: 1500; loops: Animation.Infinite }

                    // submit
                    Rectangle {
                        id: go
                        anchors.right: parent.right; anchors.rightMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 44; radius: 22
                        color: input.text.length ? view.accent : Qt.rgba(1, 1, 1, 0.08)
                        scale: goMouse.pressed ? 0.92 : 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: view.ic(view.busy ? 0xf0450 : 0xf0054)
                            color: input.text.length ? "#11111b" : view.faint
                            font { family: view.glyphs; pixelSize: 20 }
                            RotationAnimation on rotation { running: view.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            onTextChanged: rotation = 0
                        }
                        MouseArea {
                            id: goMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: input.accepted()
                        }
                    }
                }
                // message line: error, or keyboard layout
                Item {
                    width: parent.width; height: 18
                    Text {
                        x: 24
                        text: view.failed ? view.shell.failText : ""
                        color: view.danger
                        font { family: view.face; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 24
                        text: layoutName.text ? "Keyboard: " + layoutName.text : ""
                        color: view.faint
                        font { family: view.face; pixelSize: 13 }
                    }
                }

                // power
                Item {
                    width: parent.width; height: 42
                    Row {
                        spacing: 10
                        Repeater {
                            model: [
                                { act: "suspend",  icon: 0xf04b2 },
                                { act: "reboot",   icon: 0xf0709 },
                                { act: "poweroff", icon: 0xf0425 }
                            ]
                            delegate: GrowButton {
                                required property var modelData
                                size: 40; glyphSize: 15
                                glyph: view.ic(modelData.icon)
                                hot: view.armed === modelData.act ? view.danger : view.accent
                                armed: view.armed === modelData.act
                                restColor: view.muted
                                restGlow: 0.0
                                onClicked: view.power(modelData.act)
                            }
                        }
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: ({ suspend: "Click again to sleep", reboot: "Click again to restart", poweroff: "Click again to shut down" })[view.armed] || ""
                        color: view.danger
                        font { family: view.face; pixelSize: 13; weight: Font.DemiBold }
                    }
                }
            }
        }
    }

    // ── Password input ────────────────────────────────
    property real shakeX: 0
    SequentialAnimation {
        id: shake
        NumberAnimation { target: view; property: "shakeX"; to: -14; duration: 55 }
        NumberAnimation { target: view; property: "shakeX"; to: 11; duration: 75 }
        NumberAnimation { target: view; property: "shakeX"; to: -6; duration: 75 }
        NumberAnimation { target: view; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutCubic }
    }
    Connections { target: view.shell; function onFailed() { shake.restart(); input.text = ""; } }
    TextInput {
        id: input
        width: 1; height: 1; opacity: 0
        echoMode: TextInput.Password
        focus: true
        enabled: !view.busy && !view.unlocking
        onAccepted: view.shell.tryUnlock(text)
        Keys.onEscapePressed: text = ""
        onTextChanged: if (text.length) view.shell.failText = ""
    }
    Timer { interval: 300; running: true; repeat: true; onTriggered: if (!input.activeFocus) input.forceActiveFocus() }
    Text {
        id: layoutName
        visible: false
        Process {
            running: true
            command: ["sh", "-c", "hyprctl devices -j | python3 -I -c 'import json,sys; k=[x for x in json.load(sys.stdin)[\"keyboards\"] if x.get(\"main\")]; print(k[0][\"active_keymap\"] if k else \"\")'"]
            stdout: StdioCollector { onStreamFinished: layoutName.text = text.trim() }
        }
    }

    // ── Music ─────────────────────────────────────────
    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: {
        const ps = view.players;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        return ps.length ? ps[0] : null;
    }
    readonly property bool playing: player ? player.isPlaying : false
    Timer { interval: 1000; running: view.playing; repeat: true; onTriggered: if (view.player) view.player.positionChanged() }
    property string localArt: ""
    Process {
        id: artProc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/LockAlbumArt.sh"]
        stdout: StdioCollector { onStreamFinished: { const p = text.trim(); view.localArt = p && !p.endsWith("blank.png") ? "file://" + p : ""; } }
    }
    readonly property string artKey: player ? player.trackArtUrl : ""
    onArtKeyChanged: artProc.running = true

    // ── Facts: weather, battery, notifications, mic ───
    property var weather: ({ temp: "", icon: "", cond: "", place: "" })
    Process {
        running: true
        command: ["sh", "-c", "cat $HOME/.cache/.weather_cache 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").map(s => s.trim()).filter(s => s.length);
                const t = (l[2] || "").match(/-?\d+°C/);
                const c = (l[1] || "").match(/^(\S+)\s+(.*)$/);
                const iconish = c && c[1].codePointAt(0) >= 0xe000;
                view.weather = { temp: t ? t[0] : "", icon: iconish ? c[1] : "", cond: iconish ? c[2] : (l[1] || ""),
                                 place: (l[0] || "").split(",").slice(-2).join(",").trim() };
            }
        }
    }
    property int notifCount: 0
    property bool micMuted: false
    Process {
        id: infoProc
        command: ["sh", "-c", "swaync-client -c 2>/dev/null || echo 0; wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -c MUTED"]
        stdout: StdioCollector {
            onStreamFinished: { const l = text.trim().split("\n"); view.notifCount = parseInt(l[0]) || 0; view.micMuted = (parseInt(l[1]) || 0) > 0; }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: infoProc.running = true }
    readonly property var facts: {
        const out = [];
        if (view.weather.temp) out.push({ icon: view.weather.icon || view.ic(0xf0599), text: view.weather.temp + "  " + view.weather.cond, sub: view.weather.place });
        const b = UPower.displayDevice;
        if (b && b.isPresent) {
            const pct = Math.round(b.percentage * 100);
            out.push({ icon: view.ic(UPower.onBattery ? (pct < 20 ? 0xf0083 : 0xf0079) : 0xf0084), text: pct + "%", sub: UPower.onBattery ? "on battery" : "charging" });
        }
        out.push({ icon: view.ic(view.notifCount ? 0xf009e : 0xf009a),
                   text: view.notifCount === 0 ? "No notifications" : view.notifCount === 1 ? "1 notification" : view.notifCount + " notifications" });
        if (view.micMuted) out.push({ icon: view.ic(0xf036d), text: "Microphone muted" });
        return out;
    }

    // ── Power (two clicks within 3 s) ─────────────────
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: view.armed = "" }
    Process { id: powerProc }
    function power(action) {
        if (view.shell.preview) { armed = action; disarm.restart(); return; }
        if (armed === action) { powerProc.command = ["systemctl", action]; powerProc.running = true; armed = ""; }
        else { armed = action; disarm.restart(); }
    }
}
