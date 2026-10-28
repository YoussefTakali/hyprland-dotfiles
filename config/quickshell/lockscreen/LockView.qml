// Lock page — "Iris" (2026-10-28).
// The screen is frosted wallpaper; one clear lens in the middle shows the real wallpaper (or the album art
// while music plays) and stands in for the clock's colon:  09 ◯ 47.
//   • the 60 ticks around the lens sweep the seconds, and dance as a radial cava visualizer with music
//   • each typed character lights a dot inside the lens rim; a wrong password drains them in red
//   • on success the lens opens like a camera iris until it fills the screen, then the session unlocks
//     (and when the lock starts, it closes the same way)
// Previous design: ~/.config/hypr/backup-utilities-2026-10-12/lockscreen-v1/
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

Item {
    id: view
    required property var shell

    // ── Theme (wallust) ───────────────────────────────
    property color accent: "#AF5CE5"
    property color c12: "#BC5C69"
    readonly property color danger: "#f38ba8"
    readonly property string face: "Montserrat"
    readonly property string glyphs: "JetBrainsMono Nerd Font Propo"
    function ic(cp) { return String.fromCodePoint(cp); }
    // compatibility with GrowButton callers that expect these names
    readonly property color c13: accent
    readonly property string mono: face

    Process {
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/wallust/wallust-hyprland.conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const get = n => { const m = text.match(new RegExp("^\\$color" + n + " = rgb\\((\\w{6})\\)", "m")); return m ? "#" + m[1] : null; };
                view.accent = get(13) || view.accent; view.c12 = get(12) || view.c12;
            }
        }
    }

    // ── State ─────────────────────────────────────────
    readonly property bool unlocking: shell.unlocking
    readonly property bool busy: shell.busy
    property bool ready: false                     // false for the first frames: the iris starts open, then closes
    Timer { interval: 60; running: true; onTriggered: view.ready = true }
    readonly property bool open: unlocking || !ready

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: view.now = new Date() }

    // ── Geometry ──────────────────────────────────────
    readonly property real cx: width / 2
    readonly property real cy: height / 2 - 50
    readonly property real baseR: 172
    readonly property real openR: Math.hypot(Math.max(cx, width - cx), Math.max(cy, height - cy)) + 20
    readonly property real r: open ? openR : baseR + Math.min(input.text.length, 12) * 1.1
    property real rAnim: openR
    onRChanged: rAnim = r
    Behavior on rAnim {
        NumberAnimation { duration: view.open ? 680 : (view.ready ? 200 : 760); easing.type: view.open ? Easing.InOutCubic : Easing.OutCubic }
    }
    property real shakeX: 0
    property real flash: 0           // red wash inside the lens after a wrong password

    // ── Music (MPRIS) ─────────────────────────────────
    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: {
        const ps = view.players;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        return ps.length ? ps[0] : null;
    }
    readonly property bool playing: player ? player.isPlaying : false
    Timer { interval: 500; running: view.playing; repeat: true; onTriggered: if (view.player) view.player.positionChanged() }
    function fmt(s) { s = Math.max(0, Math.floor(s || 0)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }

    property string localArt: ""
    Process {
        id: artProc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/LockAlbumArt.sh"]
        stdout: StdioCollector { onStreamFinished: { const p = text.trim(); view.localArt = p && !p.endsWith("blank.png") ? "file://" + p : ""; } }
    }
    readonly property string artKey: player ? player.trackArtUrl : ""
    onArtKeyChanged: artProc.running = true

    // cava: 31 mono bars, mirrored onto the 60 ticks (bass at the bottom, treble at the top)
    property var levels: []
    Process {
        running: view.playing && !view.unlocking
        command: ["sh", "-c",
            "f=${XDG_RUNTIME_DIR:-/tmp}/qslock-cava.conf; " +
            "printf '[general]\\nframerate = 60\\nbars = 31\\n[input]\\nmethod = pulse\\nsource = auto\\n" +
            "[output]\\nmethod = raw\\nchannels = mono\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 100\\n" +
            "[smoothing]\\nnoise_reduction = 60\\n' > \"$f\"; exec cava -p \"$f\""]
        stdout: SplitParser { onRead: data => { view.levels = data.split(";").filter(s => s.length).map(Number); } }
    }
    onPlayingChanged: if (!playing) levels = []
    function level(i) { const k = 30 - (i <= 30 ? i : 60 - i); return (view.levels[k] || 0) / 100; }

    // ── Background: frosted wallpaper ─────────────────
    Image {
        id: wall
        anchors.fill: parent
        source: "file://" + Quickshell.env("HOME") + "/.config/hypr/wallpaper_effects/.wallpaper_current"
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blurMax: 64
        blur: view.open ? 0.0 : 1.0
        brightness: view.open ? 0.0 : -0.3
        saturation: view.open ? 0.0 : -0.2
        Behavior on blur { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }
        Behavior on brightness { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }
        Behavior on saturation { NumberAnimation { duration: 700 } }
    }

    // ── The lens (with ring and password dots) ────────
    Item {
        id: lensGroup
        anchors.fill: parent
        transform: Translate { x: view.shakeX }

        // soft drop shadow under the lens
        Rectangle {
            id: shadowSrc
            x: view.cx - view.rAnim; y: view.cy - view.rAnim
            width: view.rAnim * 2; height: width; radius: width / 2
            color: "black"; visible: false
        }
        MultiEffect {
            source: shadowSrc
            anchors.fill: shadowSrc
            autoPaddingEnabled: true
            shadowEnabled: true; shadowColor: "black"; shadowBlur: 1.0; shadowOpacity: 0.55; shadowVerticalOffset: 10
            blurMax: 48
            opacity: view.open ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }

        // seconds ring / visualizer
        Repeater {
            model: 60
            delegate: Item {
                id: tick
                required property int index
                readonly property bool major: index % 5 === 0
                readonly property bool passed: index <= view.now.getSeconds()
                readonly property real lvl: view.playing ? view.level(index) : 0
                x: view.cx; y: view.cy
                rotation: index * 6
                opacity: view.open ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 300 } }
                Rectangle {
                    x: -width / 2
                    y: -(view.rAnim + 32 + height)
                    width: tick.major ? 3.5 : 2.5
                    height: (tick.major ? 14 : 8) + tick.lvl * 44
                    radius: width / 2
                    color: tick.passed ? view.accent : Qt.rgba(1, 1, 1, 0.26)
                    Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                    Behavior on color { ColorAnimation { duration: 350 } }
                }
            }
        }

        ClippingRectangle {
            id: lens
            x: view.cx - view.rAnim; y: view.cy - view.rAnim
            width: view.rAnim * 2; height: width; radius: width / 2
            color: "black"

            // the real wallpaper, aligned with the screen: a clear window in the frost
            Image {
                x: -lens.x; y: -lens.y
                width: view.width; height: view.height
                source: wall.source
                fillMode: Image.PreserveAspectCrop
            }
            // album art while music plays (its own round clip: it stays cover-sized while the iris opens around it)
            ClippingRectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, 2 * (view.baseR + 14)); height: width; radius: width / 2
                color: "transparent"
                opacity: art.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: view.open ? 260 : 600; easing.type: Easing.InOutQuad } }
                Image {
                    id: art
                    readonly property bool shown: view.player !== null && status === Image.Ready && !view.open
                    anchors.fill: parent
                    source: view.player ? (view.localArt || view.player.trackArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(640, 640)
                }
            }
            // glass depth: darker toward the rim
            GE.RadialGradient {
                anchors.fill: parent
                opacity: view.open ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 400 } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.38; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.42) }
                }
            }
            Rectangle { anchors.fill: parent; color: view.danger; opacity: view.flash }
            // play / pause hint on hover
            Rectangle {
                anchors.centerIn: parent
                width: 76; height: 76; radius: 38
                color: Qt.rgba(0, 0, 0, 0.45)
                opacity: lensMouse.containsMouse && view.player && !view.open ? 1 : 0
                scale: opacity ? 1 : 0.8
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                Text {
                    anchors.centerIn: parent
                    text: view.ic(view.playing ? 0xf03e4 : 0xf040a)
                    color: "white"
                    font { family: view.glyphs; pixelSize: 34 }
                }
            }
        }
        // rim
        Rectangle {
            x: lens.x; y: lens.y; width: lens.width; height: lens.height; radius: lens.radius
            color: "transparent"
            border.width: 1.5
            border.color: view.flash > 0.01 ? view.danger : Qt.rgba(1, 1, 1, 0.3)
            opacity: view.open ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
        MouseArea {
            id: lensMouse
            x: lens.x; y: lens.y; width: lens.width; height: lens.height
            hoverEnabled: true
            enabled: !view.open
            cursorShape: view.player ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (view.player) view.player.togglePlaying()
        }

        // password dots: one per character, clockwise from the top, in the band between the rim and the ticks
        Item {
            id: dots
            x: view.cx; y: view.cy
            opacity: view.open ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
            NumberAnimation on rotation {
                running: view.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite
                onRunningChanged: if (!running) dots.rotation = 0
            }
            Repeater {
                model: Math.min(input.text.length, 40)
                delegate: Item {
                    required property int index
                    rotation: index * 9
                    Rectangle {
                        x: -5; y: -(view.rAnim + 16) - 5
                        width: 10; height: 10; radius: 5
                        color: view.busy ? view.accent : "white"
                        NumberAnimation on scale { from: 0; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3 }
                    }
                }
            }
        }
        // drained dots after a wrong password: they turn red and fall away
        Item {
            x: view.cx; y: view.cy
            Repeater {
                id: drain
                model: 0
                delegate: Item {
                    id: dd
                    required property int index
                    rotation: index * 9
                    Rectangle {
                        id: ddot
                        x: -5; y: -(view.rAnim + 16) - 5
                        width: 10; height: 10; radius: 5
                        color: view.danger
                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: dd.index * 25 }
                            ParallelAnimation {
                                NumberAnimation { target: ddot; property: "y"; to: ddot.y + 60; duration: 420; easing.type: Easing.InCubic }
                                NumberAnimation { target: ddot; property: "opacity"; to: 0; duration: 420 }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Wrong password: shake, flash, drain ───────────
    SequentialAnimation {
        id: failAnim
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: view; property: "shakeX"; to: -18; duration: 55 }
                NumberAnimation { target: view; property: "shakeX"; to: 15; duration: 75 }
                NumberAnimation { target: view; property: "shakeX"; to: -9; duration: 75 }
                NumberAnimation { target: view; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                NumberAnimation { target: view; property: "flash"; to: 0.35; duration: 90 }
                NumberAnimation { target: view; property: "flash"; to: 0; duration: 700; easing.type: Easing.OutCubic }
            }
        }
    }
    Timer { id: drainReset; interval: 1400; onTriggered: drain.model = 0 }
    Connections {
        target: view.shell
        function onFailed() {
            drain.model = Math.min(Math.max(view.typedBeforeSubmit, input.text.length), 40);
            drainReset.restart();
            input.text = "";
            failAnim.restart();
        }
    }
    property int typedBeforeSubmit: 0

    // ── Hidden password field ─────────────────────────
    TextInput {
        id: input
        width: 1; height: 1; opacity: 0
        echoMode: TextInput.Password
        focus: true
        enabled: !view.busy && !view.unlocking
        onAccepted: { view.typedBeforeSubmit = text.length; view.shell.tryUnlock(text); }
        Keys.onEscapePressed: text = ""
        onTextChanged: if (text.length) view.shell.failText = ""
    }
    Timer { interval: 300; running: true; repeat: true; onTriggered: if (!input.activeFocus) input.forceActiveFocus() }
    Component.onCompleted: {
        artProc.running = true;
        if (view.shell.preview) input.text = Quickshell.env("QS_LOCK_PREVIEW_TEXT") || "";
    }

    // ── Everything else fades away when unlocking ─────
    Item {
        id: ui
        anchors.fill: parent
        opacity: view.open ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: view.unlocking ? 350 : 600; easing.type: Easing.OutCubic } }

        // Clock: hours | lens | minutes
        Item {
            id: clock
            anchors.fill: parent
            readonly property real gap: 64
            property real push: view.open ? 320 : 0
            Behavior on push { NumberAnimation { duration: 680; easing.type: Easing.InOutCubic } }
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.45; shadowBlur: 0.6 }

            Text {
                id: hours
                text: Qt.formatTime(view.now, "hh AP").split(" ")[0]
                x: view.cx - view.baseR - clock.gap - width - clock.push
                y: view.cy - height / 2
                color: Qt.rgba(1, 1, 1, 0.95)
                font { family: view.face; pixelSize: 220; weight: Font.Thin }
            }
            Text {
                id: minutes
                text: Qt.formatTime(view.now, "mm")
                x: view.cx + view.baseR + clock.gap + clock.push
                y: view.cy - height / 2
                color: Qt.rgba(1, 1, 1, 0.95)
                font { family: view.face; pixelSize: 220; weight: Font.Thin }
            }
            Text {
                text: Qt.formatTime(view.now, "AP")
                anchors.left: minutes.left; anchors.leftMargin: 10
                y: minutes.y + minutes.height - 26
                color: view.accent
                font { family: view.face; pixelSize: 20; weight: Font.DemiBold; letterSpacing: 3 }
            }
        }

        // Date and status under the lens
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: view.cy + view.baseR + 118
            spacing: 14
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(view.now, "dddd d MMMM")
                color: Qt.rgba(1, 1, 1, 0.88)
                font { family: view.face; pixelSize: 24; weight: Font.Medium; letterSpacing: 0.5 }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                height: 26
                Text {
                    id: statusText
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.busy ? "Checking…"
                        : view.shell.failText !== "" ? view.shell.failText
                        : input.text.length ? "Press Enter to unlock"
                        : "Type your password"
                    color: view.shell.failText !== "" && !view.busy ? view.danger : Qt.rgba(1, 1, 1, 0.55)
                    font { family: view.face; pixelSize: 15; weight: Font.Medium }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Rectangle {       // keyboard layout, since the password depends on it
                    anchors.verticalCenter: parent.verticalCenter
                    visible: layoutLabel.text !== ""
                    width: layoutLabel.width + 16; height: 22; radius: 6
                    color: Qt.rgba(1, 1, 1, 0.1)
                    Text {
                        id: layoutLabel
                        anchors.centerIn: parent
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font { family: view.face; pixelSize: 12; weight: Font.DemiBold }
                        Process {
                            running: true
                            command: ["sh", "-c", "hyprctl devices -j | python3 -I -c 'import json,sys; k=[x for x in json.load(sys.stdin)[\"keyboards\"] if x.get(\"main\")]; print(k[0][\"active_keymap\"] if k else \"\")'"]
                            stdout: StdioCollector { onStreamFinished: layoutLabel.text = text.trim() }
                        }
                    }
                }
            }
        }

        // ── Now playing (bottom centre) ───────────────
        Item {
            id: music
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 54
            width: 640; height: 96
            opacity: view.player ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300 } }

            Column {
                id: meta
                anchors.horizontalCenter: parent.horizontalCenter
                width: 400
                spacing: 4
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: view.player && view.player.trackTitle ? view.player.trackTitle : "Nothing playing"
                    color: "white"
                    elide: Text.ElideRight
                    font { family: view.face; pixelSize: 18; weight: Font.DemiBold }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: view.player ? (view.player.trackArtist || "") : ""
                    color: view.accent
                    elide: Text.ElideRight
                    font { family: view.face; pixelSize: 15; weight: Font.Medium }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    readonly property real len: view.player ? view.player.length : 0
                    text: len > 0 ? view.fmt(view.player.position) + " / " + view.fmt(len) : ""
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font { family: view.face; pixelSize: 12; weight: Font.Medium; features: { "tnum": 1 } }
                }
            }
            GrowButton {
                anchors.right: meta.left; anchors.rightMargin: 14
                anchors.verticalCenter: meta.verticalCenter
                size: 44; glyphSize: 18; restGlow: 0.0
                glyph: view.ic(0xf04ae)
                hot: view.accent; restColor: Qt.rgba(1, 1, 1, 0.7)
                onClicked: if (view.player && view.player.canGoPrevious) view.player.previous()
            }
            GrowButton {
                anchors.left: meta.right; anchors.leftMargin: 14
                anchors.verticalCenter: meta.verticalCenter
                size: 44; glyphSize: 18; restGlow: 0.0
                glyph: view.ic(0xf04ad)
                hot: view.accent; restColor: Qt.rgba(1, 1, 1, 0.7)
                onClicked: if (view.player && view.player.canGoNext) view.player.next()
            }
            // audio output (click = next output)
            Row {
                id: outRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: meta.bottom; anchors.topMargin: 8
                spacing: 8
                visible: view.currentOut !== null
                property bool hot: false
                readonly property color tint: hot ? "white" : Qt.rgba(1, 1, 1, 0.55)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.currentOut ? view.currentOut.icon : ""
                    color: outRow.tint
                    font { family: view.glyphs; pixelSize: 15 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.currentOut ? view.currentOut.label : ""
                    color: outRow.tint
                    font { family: view.face; pixelSize: 13; weight: Font.Medium }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: view.outputs.length > 1
                    text: view.ic(0xf0140)
                    color: outRow.tint
                    font { family: view.glyphs; pixelSize: 13 }
                }
            }
            MouseArea {
                x: outRow.x - 8; y: outRow.y - 6; width: outRow.width + 16; height: outRow.height + 12
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: view.outputs.length > 1
                onContainsMouseChanged: outRow.hot = containsMouse
                onClicked: outNext.running = true
            }
        }

        // ── Weather (bottom left) ─────────────────────
        Column {
            anchors.left: parent.left; anchors.leftMargin: 44
            anchors.bottom: parent.bottom; anchors.bottomMargin: 40
            spacing: 2
            Text {
                text: view.weather.temp
                color: "white"
                font { family: view.face; pixelSize: 44; weight: Font.ExtraLight }
            }
            Row {
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.weather.icon
                    color: view.accent
                    font { family: view.glyphs; pixelSize: 17 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.weather.cond
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font { family: view.face; pixelSize: 15; weight: Font.Medium }
                }
            }
            Text {
                text: view.weather.place
                color: Qt.rgba(1, 1, 1, 0.45)
                font { family: view.face; pixelSize: 13 }
                horizontalAlignment: Text.AlignLeft
            }
        }

        // ── Status + power (bottom right) ─────────────
        Column {
            id: side
            anchors.right: parent.right; anchors.rightMargin: 44
            anchors.bottom: parent.bottom; anchors.bottomMargin: 40
            spacing: 8

            Repeater {
                model: view.statusLines
                delegate: Row {
                    required property var modelData
                    anchors.right: parent.right
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        color: Qt.rgba(1, 1, 1, 0.75)
                        font { family: view.face; pixelSize: 14; weight: Font.Medium }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; horizontalAlignment: Text.AlignHCenter
                        text: view.ic(modelData.icon)
                        color: modelData.hot ? view.accent : Qt.rgba(1, 1, 1, 0.6)
                        font { family: view.glyphs; pixelSize: 16 }
                    }
                }
            }
            Item { width: 1; height: 10 }
            Text {
                anchors.right: parent.right
                text: ({ suspend: "Click again to sleep", reboot: "Click again to restart", poweroff: "Click again to shut down" })[view.armed] || " "
                color: view.danger
                font { family: view.face; pixelSize: 13; weight: Font.DemiBold }
            }
            Row {
                anchors.right: parent.right
                spacing: 14
                Repeater {
                    model: [
                        { act: "suspend",  icon: 0xf04b2 },
                        { act: "reboot",   icon: 0xf0709 },
                        { act: "poweroff", icon: 0xf0425 }
                    ]
                    delegate: GrowButton {
                        required property var modelData
                        size: 42; glyphSize: 16
                        glyph: view.ic(modelData.icon)
                        hot: view.armed === modelData.act ? view.danger : view.accent
                        armed: view.armed === modelData.act
                        restColor: Qt.rgba(1, 1, 1, 0.75)
                        restGlow: 0.1
                        onClicked: view.power(modelData.act)
                    }
                }
            }
        }
    }

    // ── Data ──────────────────────────────────────────
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
                view.weather = { temp: t ? t[0].replace("C", "") : "", icon: iconish ? c[1] : "", cond: iconish ? c[2] : (l[1] || ""),
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

    readonly property var battery: UPower.displayDevice
    readonly property var statusLines: {
        const out = [];
        const b = view.battery;
        if (b && b.isPresent) {
            const pct = Math.round(b.percentage * 100);
            out.push({ text: UPower.onBattery ? pct + "%" : pct + "%, charging", icon: UPower.onBattery ? (pct < 20 ? 0xf0083 : 0xf0079) : 0xf0084, hot: !UPower.onBattery });
        }
        out.push({ text: view.notifCount === 0 ? "No notifications" : view.notifCount === 1 ? "1 notification" : view.notifCount + " notifications",
                   icon: view.notifCount ? 0xf009e : 0xf009a, hot: view.notifCount > 0 });
        out.push({ text: view.micMuted ? "Mic muted" : "Mic on", icon: view.micMuted ? 0xf036d : 0xf036c, hot: false });
        return out;
    }

    property var outputs: []
    readonly property var currentOut: outputs.find(o => o.default) || null
    Process {
        id: outList
        command: ["python3", "-I", Quickshell.env("HOME") + "/.config/hypr/scripts/AudioOutput.py", "list"]
        stdout: StdioCollector { onStreamFinished: { try { view.outputs = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: outNext
        command: ["python3", "-I", Quickshell.env("HOME") + "/.config/hypr/scripts/AudioOutput.py", "next"]
        onExited: outList.running = true
    }
    Timer { interval: 2000; running: view.player !== null; repeat: true; triggeredOnStart: true; onTriggered: outList.running = true }

    // ── Power buttons (two clicks within 3 s) ─────────
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: view.armed = "" }
    Process { id: powerProc }
    function power(action) {
        if (view.shell.preview) { armed = action; disarm.restart(); return; }
        if (armed === action) { powerProc.command = ["systemctl", action]; powerProc.running = true; armed = ""; }
        else { armed = action; disarm.restart(); }
    }
}
