// Lock-screen music card: glass card, album-color glow, art, title/artist, cava bars, seekable progress,
// prev / play-pause / next, and the audio-output switcher underneath. Talks to players over MPRIS directly.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris

Item {
    id: card
    required property var theme
    width: 720
    height: 170 + 40          // card + output line

    // Prefer the player that is playing, else the first one
    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: {
        const ps = card.players;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        return ps.length ? ps[0] : null;
    }
    readonly property bool playing: player ? player.isPlaying : false

    visible: opacity > 0
    opacity: player ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    function fmt(s) { s = Math.max(0, Math.floor(s || 0)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }

    // Position: MPRIS doesn't push position updates, so poll while playing; the bar animates in between
    Timer {
        interval: 250; running: card.playing; repeat: true
        onTriggered: if (card.player) card.player.positionChanged()
    }

    // Album colour for the glow
    // ColorQuantizer can't fetch https art, so use the local copy LockAlbumArt.sh caches per track
    property string localArt: ""
    Process {
        id: artProc
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/LockAlbumArt.sh"]
        stdout: StdioCollector { onStreamFinished: { const p = text.trim(); card.localArt = p && !p.endsWith("blank.png") ? "file://" + p : ""; } }
    }
    readonly property string artKey: card.player ? card.player.trackArtUrl : ""
    onArtKeyChanged: artProc.running = true
    Component.onCompleted: artProc.running = true
    ColorQuantizer {
        id: quant
        source: card.localArt
        depth: 0
        rescaleSize: 32
    }
    readonly property color glow: quant.colors.length ? quant.colors[0] : theme.c13

    // ── Card ──────────────────────────────────────────
    Rectangle {
        id: glass
        width: 720; height: 170; radius: 28
        color: Qt.rgba(1, 1, 1, 0.07)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
        clip: true

        // soft album-colour glow fading from behind the artwork
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(card.glow.r, card.glow.g, card.glow.b, 0.30) }
                GradientStop { position: 0.55; color: Qt.rgba(card.glow.r, card.glow.g, card.glow.b, 0.0) }
            }
        }

        ClippingRectangle {
            id: art
            x: 20; y: 20; width: 130; height: 130; radius: 18
            color: Qt.rgba(1, 1, 1, 0.06)
            Image {
                anchors.fill: parent
                source: card.player ? card.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(260, 260)
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }

        // Title / artist
        Text {
            id: title
            x: 170; y: 22; width: 330
            text: card.player && card.player.trackTitle ? card.player.trackTitle : "Nothing playing"
            color: "white"
            elide: Text.ElideRight
            font { family: card.theme.mono; pointSize: 16; weight: Font.ExtraBold }
        }
        Text {
            x: 170; y: 52; width: 330
            text: card.player ? (card.player.trackArtist || "") : ""
            color: card.theme.c13
            elide: Text.ElideRight
            font { family: card.theme.mono; pointSize: 12 }
        }

        // Cava bars
        Row {
            id: bars
            x: 170; y: 82
            height: 30
            spacing: 4
            Repeater {
                model: 24
                Rectangle {
                    required property int index
                    readonly property real v: card.playing ? (cava.levels[index] || 0) / 100 : 0
                    anchors.bottom: parent.bottom
                    width: 9.5; radius: 2.5
                    height: 4 + v * 26
                    color: Qt.rgba(card.theme.c13.r, card.theme.c13.g, card.theme.c13.b, 0.45 + v * 0.55)
                    Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                }
            }
        }

        // Progress bar (drag to seek)
        Item {
            id: prog
            x: 175; y: 122; width: 320; height: 18
            readonly property real len: card.player ? card.player.length : 0
            property bool dragging: false
            property real dragFrac: 0
            readonly property real frac: dragging ? dragFrac : (len > 0 && card.player ? Math.min(1, card.player.position / len) : 0)
            readonly property bool active: dragging || seekArea.containsMouse

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: prog.active ? 6 : 4; radius: 3
                color: Qt.rgba(1, 1, 1, 0.18)
                Behavior on height { NumberAnimation { duration: 150 } }
                Rectangle {
                    height: parent.height; radius: 3
                    width: parent.width * prog.frac
                    color: card.theme.c13
                    Behavior on width { enabled: !prog.dragging; NumberAnimation { duration: 260; easing.type: Easing.Linear } }
                }
            }
            Rectangle {
                width: 14; height: 14; radius: 7
                color: "white"
                anchors.verticalCenter: parent.verticalCenter
                x: prog.width * prog.frac - width / 2
                scale: prog.active ? 1 : 0
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            }
            MouseArea {
                id: seekArea
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                enabled: card.player && card.player.canSeek
                cursorShape: Qt.PointingHandCursor
                function f(mx) { return Math.max(0, Math.min(1, (mx - 6) / prog.width)); }
                onPressed: m => { prog.dragging = true; prog.dragFrac = f(m.x); }
                onPositionChanged: m => { if (prog.dragging) prog.dragFrac = f(m.x); }
                onReleased: {
                    if (card.player && prog.len > 0) card.player.position = prog.dragFrac * prog.len;
                    prog.dragging = false;
                }
            }
        }
        Text {
            x: 175; y: 142
            text: card.fmt(prog.dragging ? prog.dragFrac * prog.len : (card.player ? card.player.position : 0))
            color: Qt.rgba(1, 1, 1, 0.75)
            font { family: card.theme.mono; pointSize: 9 }
        }
        Text {
            anchors.right: prog.right; y: 142
            text: card.fmt(prog.len)
            color: Qt.rgba(1, 1, 1, 0.75)
            font { family: card.theme.mono; pointSize: 9 }
        }

        // Controls
        GrowButton {
            x: 545 - width / 2; y: 85 - height / 2
            size: 40; glyphSize: 18; restGlow: 0.0
            glyph: card.theme.ic(0xf04ae)
            hot: card.theme.c13; restColor: Qt.rgba(1, 1, 1, 0.75)
            onClicked: if (card.player && card.player.canGoPrevious) card.player.previous()
        }
        GrowButton {
            x: 615 - width / 2; y: 85 - height / 2
            size: 58; glyphSize: 24; filled: true
            glyph: card.theme.ic(card.playing ? 0xf03e4 : 0xf040a)
            onClicked: if (card.player) card.player.togglePlaying()
        }
        GrowButton {
            x: 685 - width / 2; y: 85 - height / 2
            size: 40; glyphSize: 18; restGlow: 0.0
            glyph: card.theme.ic(0xf04ad)
            hot: card.theme.c13; restColor: Qt.rgba(1, 1, 1, 0.75)
            onClicked: if (card.player && card.player.canGoNext) card.player.next()
        }
    }

    // ── Cava (same visualizer as the Waybar one) ──────
    QtObject { id: cava; property var levels: [] }
    Process {
        running: card.playing
        command: ["sh", "-c",
            "f=${XDG_RUNTIME_DIR:-/tmp}/qslock-cava.conf; " +
            "printf '[general]\\nframerate = 60\\nbars = 24\\n[input]\\nmethod = pulse\\nsource = auto\\n" +
            "[output]\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 100\\n" +
            "[smoothing]\\nnoise_reduction = 55\\n' > \"$f\"; exec cava -p \"$f\""]
        stdout: SplitParser {
            onRead: data => { cava.levels = data.split(";").filter(s => s.length).map(Number); }
        }
    }

    // ── Audio output (click = next output) ───────────
    property var outputs: []
    readonly property var currentOut: outputs.find(o => o.default) || null
    Process {
        id: outList
        command: ["python3", "-I", Quickshell.env("HOME") + "/.config/hypr/scripts/AudioOutput.py", "list"]
        stdout: StdioCollector { onStreamFinished: { try { card.outputs = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: outNext
        command: ["python3", "-I", Quickshell.env("HOME") + "/.config/hypr/scripts/AudioOutput.py", "next"]
        onExited: outList.running = true
    }
    Timer { interval: 2000; running: card.visible; repeat: true; triggeredOnStart: true; onTriggered: outList.running = true }

    Text {
        id: outLabel
        anchors.horizontalCenter: parent.horizontalCenter
        y: 170 + 12
        visible: card.currentOut !== null
        text: card.currentOut ? card.currentOut.icon + "  " + card.currentOut.label + (card.outputs.length > 1 ? "   " + card.theme.ic(0xf0140) : "") : ""
        color: outMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.7)
        Behavior on color { ColorAnimation { duration: 150 } }
        font { family: card.theme.monoProp; pointSize: 11 }
        MouseArea {
            id: outMouse
            anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: card.outputs.length > 1
            onClicked: outNext.running = true
        }
    }
}
