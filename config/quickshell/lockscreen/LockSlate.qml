// Lock style "Slate" (default, 2026-10-28).
// The wallpaper stays whole and drifts slowly (Ken Burns). Everything else lives on one pane of dark glass on the
// left: stacked clock (hours white, minutes accent) with a seconds hairline, date, weather + status, a music card
// only while something plays, and the password pill. Unlock slides the glass away to the left.
// Extras: ambient mode (after 20 s idle the pane slides away and a quiet clock stays; any key/mouse brings it back),
// Caps Lock warning + layout hint after 3 wrong tries, a second page (scroll or ↓) with the month and the week's
// weather, and a living wallpaper (mouse parallax; the pane's top light pulses with the music's bass).
// Test hooks (preview only): QS_LOCK_IDLE=<s> idle delay, QS_LOCK_PAGE=1 start on the second page.
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

    // ambient mode
    property bool idle: false
    readonly property int idleMs: parseInt(Quickshell.env("QS_LOCK_IDLE") || "20") * 1000
    Timer {
        id: idleTimer
        interval: view.idleMs
        running: !view.idle && input.text.length === 0 && !view.busy && !view.unlocking
        onTriggered: { view.idle = true; view.page = 0; }
    }
    function poke() { if (view.idle) view.idle = false; idleTimer.restart(); }

    // page 0 = clock, 1 = calendar + forecast
    property int page: view.shell.preview ? (parseInt(Quickshell.env("QS_LOCK_PAGE") || "0") ? 1 : 0) : 0

    // mouse parallax
    property real parX: 0
    property real parY: 0
    // Qt resends hover events every frame while anything animates under a resting cursor, so only a real
    // move (> 4 px since the last one) counts as activity — otherwise ambient mode would never start.
    HoverHandler {
        property point last: Qt.point(-100, -100)
        onPointChanged: {
            const p = point.position;
            if (Math.abs(p.x - last.x) + Math.abs(p.y - last.y) < 4) return;
            last = p;
            view.parX = (p.x / view.width - 0.5) * -30;
            view.parY = (p.y / view.height - 0.5) * -18;
            view.poke();
        }
    }

    // Caps Lock (main keyboard)
    property bool caps: false
    Process {
        id: capsProc
        command: ["sh", "-c", "hyprctl devices -j | python3 -I -c 'import json,sys; k=[x for x in json.load(sys.stdin)[\"keyboards\"] if x.get(\"main\")]; print(1 if k and k[0].get(\"capsLock\") else 0)'"]
        stdout: StdioCollector { onStreamFinished: view.caps = text.trim() === "1" }
    }
    Timer { interval: 700; running: !view.idle && !view.away; repeat: true; triggeredOnStart: true; onTriggered: capsProc.running = true }

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
            width: parent.width; height: parent.height
            x: view.unlocking ? 0 : view.parX
            y: view.unlocking ? 0 : view.parY
            Behavior on x { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
            source: "file://" + Quickshell.env("HOME") + "/.config/hypr/wallpaper_effects/.wallpaper_current"
            fillMode: Image.PreserveAspectCrop
            transformOrigin: Item.Right
            property real drift: 1.04          // ≥ 1.04 so the parallax shift never shows an edge
            scale: view.unlocking ? 1.0 : drift
            Behavior on scale { enabled: view.unlocking; NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
            SequentialAnimation on drift {
                running: !view.unlocking
                loops: Animation.Infinite
                NumberAnimation { from: 1.04; to: 1.10; duration: 38000; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.10; to: 1.04; duration: 38000; easing.type: Easing.InOutSine }
            }
        }
    }
    // shade toward the glass so the edge never looks pasted on
    Rectangle {
        anchors.fill: parent
        opacity: view.away || view.idle ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 900 } }
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
        x: view.away || view.idle ? -width - 60 : m
        Behavior on x { NumberAnimation { duration: view.unlocking ? 620 : (view.idle ? 1100 : 650); easing.type: view.unlocking || view.idle ? Easing.InOutCubic : Easing.OutCubic } }
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
                    GradientStop { position: 0.0; color: Qt.rgba(view.accent.r, view.accent.g, view.accent.b, Math.min(0.62, 0.20 + view.bass * 0.42)) }
                    GradientStop { position: 0.30 + view.bass * 0.22; color: "transparent" }
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

            // ── pages (scroll or ↑/↓) ──────────────────
            Item {
                id: pager
                anchors.top: who.bottom; anchors.topMargin: 6
                anchors.bottom: bottomStack.top; anchors.bottomMargin: 18
                width: parent.width
                clip: true
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: e => { if (e.angleDelta.y !== 0) view.page = e.angleDelta.y < 0 ? 1 : 0; view.poke(); }
                }
                Item {
                    id: pages
                    width: parent.width; height: parent.height * 2
                    y: -view.page * pager.height
                    Behavior on y { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

            Item {
                id: page1
                width: pager.width; height: pager.height
                opacity: view.page === 0 ? 1 : 0.0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            // clock: numerals placed by their cap height (Montserrat digits ≈ 0.7 em), not by line boxes
            Item {
                id: clockBox
                anchors.top: parent.top; anchors.topMargin: 34
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
            }   // page1

            // ── page 2: the month and the week's weather ──
            Item {
                id: page2
                y: pager.height
                width: pager.width; height: pager.height
                opacity: view.page === 1 ? 1 : 0.0
                Behavior on opacity { NumberAnimation { duration: 400 } }

                Text {
                    id: monthTitle
                    y: 30
                    text: Qt.formatDate(view.now, "MMMM yyyy")
                    color: view.ink
                    font { family: view.face; pixelSize: 26; weight: Font.DemiBold }
                }
                Grid {
                    id: cal
                    anchors.top: monthTitle.bottom; anchors.topMargin: 18
                    columns: 7
                    rowSpacing: 4
                    readonly property real cw: page2.width / 7
                    Repeater {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        delegate: Text {
                            required property string modelData
                            width: cal.cw; height: 26
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: view.faint
                            font { family: view.face; pixelSize: 12; weight: Font.DemiBold }
                        }
                    }
                    Repeater {
                        model: view.calCells
                        delegate: Item {
                            required property var modelData
                            width: cal.cw; height: 38
                            Rectangle {
                                anchors.centerIn: parent
                                width: 34; height: 34; radius: 17
                                color: view.accent
                                visible: modelData.today === true
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.d || ""
                                color: modelData.today ? "#11111b" : (modelData.past ? view.faint : (modelData.weekend ? view.muted : view.ink))
                                font { family: view.face; pixelSize: 15; weight: modelData.today ? Font.Bold : Font.Medium }
                            }
                        }
                    }
                }

                // the week's weather: day, sky, rain chance, low ── range ── high
                Column {
                    anchors.top: cal.bottom; anchors.topMargin: 30
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: view.forecast
                        delegate: Item {
                            id: fday
                            required property var modelData
                            width: parent.width; height: 26
                            Text {
                                width: 70
                                anchors.verticalCenter: parent.verticalCenter
                                text: fday.modelData.name
                                color: view.ink
                                font { family: view.face; pixelSize: 15; weight: Font.DemiBold }
                            }
                            Text {
                                x: 74; width: 24
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: view.ic(fday.modelData.icon)
                                color: view.accent
                                font { family: view.glyphs; pixelSize: 17 }
                            }
                            Text {
                                x: 108; width: 50
                                anchors.verticalCenter: parent.verticalCenter
                                text: fday.modelData.rain >= 20 ? fday.modelData.rain + "%" : ""
                                color: "#89dceb"
                                font { family: view.face; pixelSize: 13; weight: Font.DemiBold }
                            }
                            Text {
                                id: lo
                                x: 168; width: 40
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(fday.modelData.lo) + "°"
                                color: view.muted
                                font { family: view.face; pixelSize: 15; weight: Font.Medium }
                            }
                            Item {
                                id: range
                                anchors.left: lo.right; anchors.leftMargin: 14
                                anchors.right: hi.left; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6
                                Rectangle { anchors.fill: parent; radius: 3; color: Qt.rgba(1, 1, 1, 0.1) }
                                Rectangle {
                                    readonly property real span: Math.max(1, view.fcMax - view.fcMin)
                                    x: range.width * (fday.modelData.lo - view.fcMin) / span
                                    width: Math.max(8, range.width * (fday.modelData.hi - fday.modelData.lo) / span)
                                    height: parent.height; radius: 3
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#89b4fa" }
                                        GradientStop { position: 1.0; color: view.accent }
                                    }
                                }
                            }
                            Text {
                                id: hi
                                anchors.right: parent.right
                                width: 40
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(fday.modelData.hi) + "°"
                                color: view.ink
                                font { family: view.face; pixelSize: 15; weight: Font.DemiBold }
                            }
                        }
                    }
                }
            }
                }   // pages
            }   // pager

            // page dots
            Column {
                anchors.right: parent.right; anchors.rightMargin: -26
                anchors.verticalCenter: pager.verticalCenter
                spacing: 8
                Repeater {
                    model: 2
                    delegate: Rectangle {
                        required property int index
                        width: 6; radius: 3
                        height: view.page === index ? 20 : 6
                        color: view.page === index ? view.accent : Qt.rgba(1, 1, 1, 0.3)
                        Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: view.page = index }
                    }
                }
            }

            // ── bottom stack: music, password, power ──
            Column {
                id: bottomStack
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

                    // Caps Lock warning
                    Rectangle {
                        anchors.right: go.left; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: capsRow.width + 20; height: 28; radius: 14
                        color: Qt.rgba(0.976, 0.886, 0.686, 0.16)
                        opacity: view.caps ? 1 : 0
                        scale: view.caps ? 1 : 0.8
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        Row {
                            id: capsRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { anchors.verticalCenter: parent.verticalCenter; text: view.ic(0xf0632); color: "#f9e2af"; font { family: view.glyphs; pixelSize: 14 } }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Caps Lock is on"; color: "#f9e2af"; font { family: view.face; pixelSize: 12; weight: Font.Bold } }
                        }
                    }
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
                        text: !view.failed ? ""
                            : view.shell.attempts >= 3 ? "Still wrong. Check Caps Lock and the " + (layoutName.text || "keyboard") + " layout."
                            : view.shell.failText
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
        Keys.onEscapePressed: { text = ""; view.page = 0; }
        Keys.onDownPressed: view.page = 1
        Keys.onUpPressed: view.page = 0
        Keys.onPressed: event => { view.poke(); event.accepted = false; }
        onTextChanged: { view.poke(); if (text.length) { view.shell.failText = ""; view.page = 0; } }
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

    // ── Bass level for the pulsing light (cava, 6 mono bars) ─
    property real bass: 0
    Behavior on bass { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
    Process {
        running: view.playing && !view.idle && !view.away
        command: ["sh", "-c",
            "f=${XDG_RUNTIME_DIR:-/tmp}/qslock-bass.conf; " +
            "printf '[general]\\nframerate = 40\\nbars = 6\\n[input]\\nmethod = pulse\\nsource = auto\\n" +
            "[output]\\nmethod = raw\\nchannels = mono\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 100\\n' > \"$f\"; exec cava -p \"$f\""]
        stdout: SplitParser {
            onRead: data => { const v = data.split(";").filter(x => x.length).map(Number); view.bass = v.length ? Math.min(1, (v[0] + v[1]) / 200) : 0; }
        }
        onRunningChanged: if (!running) view.bass = 0
    }

    // ── Calendar ──────────────────────────────────────
    readonly property var calCells: {
        const n = view.now, y = n.getFullYear(), m = n.getMonth(), today = n.getDate();
        const first = (new Date(y, m, 1).getDay() + 6) % 7;        // Monday first
        const days = new Date(y, m + 1, 0).getDate();
        const out = [];
        for (let i = 0; i < first; i++) out.push({ d: 0 });
        for (let d = 1; d <= days; d++) {
            const wd = (first + d - 1) % 7;
            out.push({ d: d, today: d === today, past: d < today, weekend: wd >= 5 });
        }
        return out;
    }

    // ── Forecast (Open-Meteo cache written by the Waybar weather module) ─
    property var forecast: []
    property real fcMin: 0
    property real fcMax: 1
    Process {
        id: fcProc
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.cache/open_meteo_cache.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const f = JSON.parse(text).forecast, d = f.daily, h = f.hourly;
                    const todayKey = Qt.formatDate(new Date(), "yyyy-MM-dd");
                    const out = [];
                    for (let i = 0; i < d.time.length && out.length < 6; i++) {
                        if (d.time[i] < todayKey) continue;
                        let rain = 0;
                        for (let j = 0; j < h.time.length; j++)
                            if (h.time[j].startsWith(d.time[i])) rain = Math.max(rain, h.precipitation_probability[j] || 0);
                        const date = new Date(d.time[i] + "T12:00:00");
                        out.push({ name: d.time[i] === todayKey ? "Today" : Qt.formatDate(date, "ddd"),
                                   lo: d.temperature_2m_min[i], hi: d.temperature_2m_max[i], rain: rain,
                                   icon: rain >= 70 ? 0xf0596 : rain >= 45 ? 0xf0597 : rain >= 20 ? 0xf0595 : 0xf0599 });
                    }
                    view.fcMin = Math.min(...out.map(o => o.lo));
                    view.fcMax = Math.max(...out.map(o => o.hi));
                    view.forecast = out;
                } catch (e) { view.forecast = []; }
            }
        }
    }

    // ── Ambient clock (shown while idle) ──────────────
    Rectangle {       // soft shade under the corner clock, so it reads on bright wallpapers too
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: parent.height * 0.5
        opacity: ambient.opacity
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }
    Item {
        id: ambient
        anchors.left: parent.left; anchors.leftMargin: 80
        anchors.bottom: parent.bottom; anchors.bottomMargin: 76
        width: 700; height: ambCol.height
        opacity: view.idle && !view.away ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: view.idle ? 1400 : 300; easing.type: Easing.InOutQuad } }
        transform: Translate { y: view.idle ? 0 : 24; Behavior on y { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } } }
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.6; shadowBlur: 0.8 }
        Column {
            id: ambCol
            spacing: 6
            Row {
                spacing: 14
                Text {
                    text: Qt.formatTime(view.now, "hh:mm AP").split(" ")[0]
                    color: "white"
                    font { family: view.face; pixelSize: 150; weight: Font.ExtraLight; letterSpacing: -2 }
                }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: Qt.formatTime(view.now, "AP")
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font { family: view.face; pixelSize: 24; weight: Font.DemiBold }
                }
            }
            Row {
                spacing: 18
                Text {
                    text: Qt.formatDate(view.now, "dddd, d MMMM")
                    color: "white"
                    font { family: view.face; pixelSize: 22; weight: Font.Medium }
                }
                Text {
                    text: view.weather.temp
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font { family: view.face; pixelSize: 22; weight: Font.Medium }
                }
                Text {
                    visible: view.notifCount > 0
                    text: view.ic(0xf009e) + " " + view.notifCount
                    color: view.accent
                    font { family: view.glyphs; pixelSize: 20 }
                }
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 30
        text: "Press any key to unlock"
        color: Qt.rgba(1, 1, 1, 0.55)
        opacity: ambient.opacity
        font { family: view.face; pixelSize: 13; weight: Font.Medium }
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
