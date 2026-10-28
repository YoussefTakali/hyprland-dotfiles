// Lock page — "Fogged window" (2026-10-28).
// The screen is a pane of misted glass over the wallpaper. Nothing is printed on it: the time and date are
// wiped clean into the fog, so the letters are the sharp wallpaper showing through.
//   • every few seconds a droplet runs down the glass, leaving a clear trail that slowly fogs back over
//   • moving the mouse wipes the fog where it passes
//   • typing drags a wiped streak under the date; a wrong password fogs it back up in red
//   • unlocking evaporates the fog outward from the clock; locking lets it creep back in from the edges
// Music is only a quiet line at the bottom, and is gone when nothing plays.
// Previous designs: ~/.config/hypr/backup-utilities-2026-10-12/lockscreen-v1/ (cards), lockscreen-v2-iris/
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects as GE
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

Item {
    id: view
    required property var shell

    // ── Theme (wallust) ───────────────────────────────
    property color accent: "#AF5CE5"
    readonly property color danger: "#f38ba8"
    readonly property string face: "Montserrat"
    readonly property string glyphs: "JetBrainsMono Nerd Font Propo"
    function ic(cp) { return String.fromCodePoint(cp); }

    Process {
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/wallust/wallust-hyprland.conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/^\$color13 = rgb\((\w{6})\)/m);
                if (m) view.accent = "#" + m[1];
            }
        }
    }

    // ── State ─────────────────────────────────────────
    readonly property bool unlocking: shell.unlocking
    readonly property bool busy: shell.busy
    readonly property bool failed: shell.failText !== "" && !busy
    property bool ready: false
    Timer { interval: 350; running: true; onTriggered: view.ready = true }   // after the surface is on screen
    readonly property bool open: unlocking || !ready      // fog fully cleared (start of lock, and unlock)

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: view.now = new Date() }

    // ── Layout ────────────────────────────────────────
    readonly property real cx: width / 2
    readonly property real clockTop: height / 2 - 330
    readonly property real dateTop: clockTop + 318
    readonly property real streakY: dateTop + 118        // centre line of the password streak

    // fog-free circle used for the lock/unlock transitions
    readonly property real fullR: Math.hypot(width, height) * 0.75
    property real clearR: fullR
    Behavior on clearR { NumberAnimation { duration: view.unlocking ? 750 : 1100; easing.type: view.unlocking ? Easing.InCubic : Easing.OutCubic } }
    onOpenChanged: clearR = open ? fullR : 0
    Component.onCompleted: {
        if (view.shell.preview) input.text = Quickshell.env("QS_LOCK_PREVIEW_TEXT") || "";
    }

    // ── The glass ─────────────────────────────────────
    Image {
        id: wall
        anchors.fill: parent
        source: "file://" + Quickshell.env("HOME") + "/.config/hypr/wallpaper_effects/.wallpaper_current"
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    // fog: blurred, paled, desaturated wallpaper with a little grain
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true; blurMax: 64; blur: 1.0
        brightness: 0.06
        saturation: -0.45
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.85, 0.88, 0.95, 0.13) }
    Image {
        anchors.fill: parent
        source: "grain.png"
        fillMode: Image.Tile
        opacity: 0.07
    }

    // soft dark halo under everything wiped clear, so the edges of the letters read on any wallpaper
    Item {
        anchors.fill: parent
        opacity: view.open ? 0 : 0.5
        Behavior on opacity { NumberAnimation { duration: 400 } }
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 0.5; blurMax: 32 }
        ClockFace { v: view; ink: Qt.rgba(0, 0, 0, 0.85) }
    }

    // what is wiped clear: the sharp wallpaper, cut out by clearMask (alpha multiply)
    GE.OpacityMask {
        anchors.fill: parent
        source: wall
        maskSource: clearMask
    }
    Item {
        id: clearMask
        anchors.fill: parent
        visible: false

        // droplet trails + mouse wipes, drawn at 1/4 resolution (scaling softens the edges like real streaks)
        Canvas {
            id: trails
            width: Math.ceil(view.width / 4); height: Math.ceil(view.height / 4)
            scale: 4; transformOrigin: Item.TopLeft
            smooth: true
            property var drops: []
            property var wipes: []
            onPaint: {
                const c = getContext("2d");
                // fog creeps back: fade everything a little each frame
                c.globalCompositeOperation = "destination-out";
                c.fillStyle = "rgba(0,0,0,0.035)";
                c.fillRect(0, 0, width, height);
                c.globalCompositeOperation = "source-over";
                c.strokeStyle = "white"; c.fillStyle = "white"; c.lineCap = "round";

                // mouse wipes
                for (const w of wipes) {
                    c.lineWidth = 11;
                    c.beginPath(); c.moveTo(w[0], w[1]); c.lineTo(w[2], w[3]); c.stroke();
                }
                wipes = [];

                // droplets: stick, then slide in little stutters, leaving a trail
                if (drops.length < 7 && Math.random() < 0.035)
                    drops.push({ x: Math.random() * width, y: Math.random() * height * 0.7, v: 0, r: 0.9 + Math.random() * 1.3, life: 0 });
                const keep = [];
                for (const d of drops) {
                    d.life++;
                    if (d.life > 20) d.v = Math.max(0, Math.min(2.4, d.v + (Math.random() - 0.42) * 0.35));
                    const ny = d.y + d.v, nx = d.x + (Math.random() - 0.5) * 0.25;
                    c.lineWidth = d.r * 1.7;
                    c.beginPath(); c.moveTo(d.x, d.y); c.lineTo(nx, ny); c.stroke();
                    c.beginPath(); c.arc(nx, ny, d.r * 1.15, 0, 2 * Math.PI); c.fill();
                    d.x = nx; d.y = ny;
                    if (d.y < height + 4 && d.life < 900 && !(d.life > 60 && Math.random() < 0.002)) keep.push(d);
                }
                drops = keep;
                beads.requestPaint();
            }
        }
        Timer {
            interval: 33; repeat: true
            running: !view.open
            onTriggered: trails.requestPaint()
        }

        // lock / unlock: the fog-free circle around the clock
        GE.RadialGradient {
            x: view.cx - view.clearR; y: view.clockTop + 170 - view.clearR
            width: view.clearR * 2; height: width
            gradient: Gradient {
                GradientStop { position: 0.0; color: "white" }
                GradientStop { position: 0.35; color: "white" }
                GradientStop { position: 0.5; color: "transparent" }
            }
        }

        ClockFace { v: view; ink: "white" }

        // password streak
        Rectangle {
            id: streak
            x: view.cx - width / 2 + view.shakeX
            y: view.streakY - height / 2
            height: 56; radius: 28
            width: input.text.length === 0 ? 0 : Math.min(560, 76 + input.text.length * 22)
            color: "white"
            Behavior on width { NumberAnimation { duration: view.failed ? 600 : 240; easing.type: Easing.OutCubic } }
        }
    }

    // droplet beads: a little highlight on each drop (drawn at 1/2 resolution)
    Canvas {
        id: beads
        width: Math.ceil(view.width / 2); height: Math.ceil(view.height / 2)
        scale: 2; transformOrigin: Item.TopLeft
        opacity: view.open ? 0 : 1
        onPaint: {
            const c = getContext("2d");
            c.clearRect(0, 0, width, height);
            for (const d of trails.drops) {
                const x = d.x * 2, y = d.y * 2, r = d.r * 2.3;
                c.fillStyle = "rgba(0,0,0,0.22)";
                c.beginPath(); c.arc(x + 0.6, y + 1.2, r, 0, 2 * Math.PI); c.fill();
                c.fillStyle = "rgba(255,255,255,0.55)";
                c.beginPath(); c.arc(x - r * 0.3, y - r * 0.35, r * 0.38, 0, 2 * Math.PI); c.fill();
            }
        }
    }

    // wipe the glass with the mouse
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: !view.open
        acceptedButtons: Qt.NoButton
        property real lx: -1
        property real ly: -1
        onPositionChanged: m => {
            const x = m.x / 4, y = m.y / 4;
            if (lx >= 0) trails.wipes.push([lx, ly, x, y]);
            lx = x; ly = y;
        }
        onExited: lx = -1
    }

    // ── Time and date, wiped into the fog ─────────────
    component ClockFace: Item {
        id: cf
        required property var v
        property color ink: "white"
        anchors.fill: parent
        Row {
            id: timeRow
            anchors.horizontalCenter: parent.horizontalCenter
            y: cf.v.clockTop
            Text {
                text: Qt.formatTime(cf.v.now, "h")
                color: cf.ink
                font { family: cf.v.face; pixelSize: 290; weight: Font.ExtraBold; letterSpacing: -6 }
            }
            Text {
                text: ":"
                leftPadding: 18; rightPadding: 8
                color: cf.ink
                opacity: cf.v.now.getSeconds() % 2 ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutSine } }
                font { family: cf.v.face; pixelSize: 290; weight: Font.ExtraBold }
            }
            Text {
                text: Qt.formatTime(cf.v.now, "mm")
                color: cf.ink
                font { family: cf.v.face; pixelSize: 290; weight: Font.ExtraBold; letterSpacing: -6 }
            }
        }
        Text {
            x: timeRow.x + timeRow.width + 14
            y: cf.v.clockTop + 78
            text: Qt.formatTime(cf.v.now, "AP")
            color: cf.ink
            font { family: cf.v.face; pixelSize: 46; weight: Font.ExtraBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: cf.v.dateTop
            text: Qt.formatDate(cf.v.now, "dddd d MMMM")
            color: cf.ink
            font { family: cf.v.face; pixelSize: 44; weight: Font.Bold }
        }
    }

    // ── Password ──────────────────────────────────────
    property real shakeX: 0
    property int typedBeforeSubmit: 0
    SequentialAnimation {
        id: failAnim
        NumberAnimation { target: view; property: "shakeX"; to: -16; duration: 55 }
        NumberAnimation { target: view; property: "shakeX"; to: 13; duration: 75 }
        NumberAnimation { target: view; property: "shakeX"; to: -7; duration: 75 }
        NumberAnimation { target: view; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutCubic }
    }
    // the red streak that fogs back up after a wrong password
    Rectangle {
        id: redStreak
        x: view.cx - width / 2 + view.shakeX
        y: view.streakY - height / 2
        height: 56; radius: 28
        color: view.danger
        opacity: 0
        width: 0
        ParallelAnimation {
            id: redAnim
            NumberAnimation { target: redStreak; property: "opacity"; from: 0.55; to: 0; duration: 900; easing.type: Easing.InQuad }
            NumberAnimation { target: redStreak; property: "width"; to: 56; duration: 900; easing.type: Easing.OutCubic }
        }
    }
    Connections {
        target: view.shell
        function onFailed() {
            redStreak.width = Math.min(560, 76 + Math.max(view.typedBeforeSubmit, input.text.length) * 22);
            redAnim.restart();
            failAnim.restart();
            input.text = "";
        }
    }

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

    // ── Everything printed on the glass (fades on unlock) ─
    Item {
        id: ui
        anchors.fill: parent
        opacity: view.open ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: view.unlocking ? 300 : 900; easing.type: Easing.OutCubic } }
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.55; shadowBlur: 0.45; shadowVerticalOffset: 1 }

        // dots inside the streak
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: view.shakeX
            y: view.streakY - 5
            spacing: 10
            Repeater {
                model: Math.min(input.text.length, 22)
                delegate: Rectangle {
                    required property int index
                    width: 10; height: 10; radius: 5
                    color: "white"
                    opacity: view.busy ? 0.35 + 0.65 * Math.abs(Math.sin((pulse.t - index * 0.18))) : 1
                    NumberAnimation on scale { from: 0; to: 1; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 3 }
                }
            }
        }
        QtObject { id: pulse; property real t: 0 }
        NumberAnimation { target: pulse; property: "t"; running: view.busy; from: 0; to: Math.PI * 4; duration: 1600; loops: Animation.Infinite }

        // hint (where the streak will appear)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: view.streakY - height / 2
            spacing: 12
            opacity: input.text.length === 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: hint.width + (view.failed ? 28 : 0); height: 34; radius: 17
                color: view.failed ? view.danger : "transparent"
                Behavior on color { ColorAnimation { duration: 200 } }
                Text {
                    id: hint
                    anchors.centerIn: parent
                    text: view.busy ? "Checking…" : view.failed ? view.shell.failText : "Type your password"
                    color: view.failed ? "#1e1e2e" : Qt.rgba(1, 1, 1, 0.9)
                    font { family: view.face; pixelSize: 16; weight: Font.Bold }
                }
            }
            Rectangle {       // keyboard layout, since the password depends on it
                anchors.verticalCenter: parent.verticalCenter
                visible: layoutLabel.text !== ""
                width: layoutLabel.width + 16; height: 24; radius: 7
                color: Qt.rgba(1, 1, 1, 0.16)
                Text {
                    id: layoutLabel
                    anchors.centerIn: parent
                    color: "white"
                    font { family: view.face; pixelSize: 12; weight: Font.Bold }
                    Process {
                        running: true
                        command: ["sh", "-c", "hyprctl devices -j | python3 -I -c 'import json,sys; k=[x for x in json.load(sys.stdin)[\"keyboards\"] if x.get(\"main\")]; print(k[0][\"active_keymap\"] if k else \"\")'"]
                        stdout: StdioCollector { onStreamFinished: layoutLabel.text = text.trim() }
                    }
                }
            }
        }

        // ── Now playing: one quiet line, only when something plays ─
        Row {
            id: music
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 46
            spacing: 14
            opacity: view.player ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300 } }

            GrowButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 36; glyphSize: 14; restGlow: 0.0
                glyph: view.ic(0xf04ae)
                hot: view.accent; restColor: Qt.rgba(1, 1, 1, 0.8)
                onClicked: if (view.player && view.player.canGoPrevious) view.player.previous()
            }
            GrowButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 40; glyphSize: 15; filled: true
                glyph: view.ic(view.playing ? 0xf03e4 : 0xf040a)
                onClicked: if (view.player) view.player.togglePlaying()
            }
            GrowButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 36; glyphSize: 14; restGlow: 0.0
                glyph: view.ic(0xf04ad)
                hot: view.accent; restColor: Qt.rgba(1, 1, 1, 0.8)
                onClicked: if (view.player && view.player.canGoNext) view.player.next()
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: Math.min(implicitWidth, 420)
                    text: view.player && view.player.trackTitle ? view.player.trackTitle : ""
                    color: "white"
                    elide: Text.ElideRight
                    font { family: view.face; pixelSize: 15; weight: Font.Bold }
                }
                Row {
                    spacing: 10
                    Text {
                        width: Math.min(implicitWidth, 260)
                        text: view.player ? (view.player.trackArtist || "") : ""
                        color: Qt.rgba(1, 1, 1, 0.75)
                        elide: Text.ElideRight
                        font { family: view.face; pixelSize: 13; weight: Font.Medium }
                    }
                    // audio output (click = next output)
                    Text {
                        id: outIcon
                        visible: view.currentOut !== null
                        text: view.currentOut ? view.currentOut.icon + " " : ""
                        color: outMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.6)
                        font { family: view.glyphs; pixelSize: 13 }
                        Text {
                            anchors.left: parent.right
                            anchors.baseline: parent.baseline
                            text: view.currentOut ? view.currentOut.label : ""
                            color: parent.color
                            font { family: view.face; pixelSize: 13; weight: Font.Medium }
                        }
                        MouseArea {
                            id: outMouse
                            width: 200; height: parent.height + 8; y: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: view.outputs.length > 1
                            onClicked: outNext.running = true
                        }
                    }
                }
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
                font { family: view.face; pixelSize: 44; weight: Font.Light }
            }
            Row {
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.weather.icon
                    color: "white"
                    font { family: view.glyphs; pixelSize: 17 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.weather.cond
                    color: "white"
                    font { family: view.face; pixelSize: 15; weight: Font.DemiBold }
                }
            }
            Text {
                text: view.weather.place
                color: Qt.rgba(1, 1, 1, 0.7)
                font { family: view.face; pixelSize: 13; weight: Font.Medium }
            }
        }

        // ── Status + power (bottom right) ─────────────
        Column {
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
                        color: "white"
                        font { family: view.face; pixelSize: 14; weight: Font.DemiBold }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; horizontalAlignment: Text.AlignHCenter
                        text: view.ic(modelData.icon)
                        color: "white"
                        font { family: view.glyphs; pixelSize: 16 }
                    }
                }
            }
            Item { width: 1; height: 10 }
            Text {
                anchors.right: parent.right
                text: ({ suspend: "Click again to sleep", reboot: "Click again to restart", poweroff: "Click again to shut down" })[view.armed] || " "
                color: view.danger
                font { family: view.face; pixelSize: 13; weight: Font.Bold }
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
                        restColor: "white"
                        restGlow: 0.12
                        onClicked: view.power(modelData.act)
                    }
                }
            }
        }
    }

    // ── Music (MPRIS) ─────────────────────────────────
    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: {
        const ps = view.players;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        return ps.length ? ps[0] : null;
    }
    readonly property bool playing: player ? player.isPlaying : false

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
            out.push({ text: UPower.onBattery ? pct + "%" : pct + "%, charging", icon: UPower.onBattery ? (pct < 20 ? 0xf0083 : 0xf0079) : 0xf0084 });
        }
        out.push({ text: view.notifCount === 0 ? "No notifications" : view.notifCount === 1 ? "1 notification" : view.notifCount + " notifications",
                   icon: view.notifCount ? 0xf009e : 0xf009a });
        out.push({ text: view.micMuted ? "Mic muted" : "Mic on", icon: view.micMuted ? 0xf036d : 0xf036c });
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
