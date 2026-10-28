// Volume / brightness / microphone OSD (2026-10-28). Always running (exec-once in Startup_Apps.conf).
// Volume.sh and Brightness.sh call:  ~/.config/hypr/scripts/Osd.sh <volume|brightness|mic> <0-150> [muted]
// A glass pill at the bottom centre with the accent bar; fades out after 1.5 s; never takes clicks or focus.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    settings.watchFiles: false

    property color accent: "#AF5CE5"
    function loadAccent() { accentProc.running = true; }
    Process {
        id: accentProc
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/wallust/wallust-hyprland.conf"]
        stdout: StdioCollector { onStreamFinished: { const m = text.match(/^\$color13 = rgb\((\w{6})\)/m); if (m) root.accent = "#" + m[1]; } }
    }

    property string kind: "volume"
    property int value: 0
    property bool muted: false
    property bool shown: false

    IpcHandler {
        target: "osd"
        function popup(kind: string, value: int, muted: bool): void {
            if (!root.shown) root.loadAccent();          // pick up a new wallpaper accent
            root.kind = kind; root.value = value; root.muted = muted;
            root.shown = true;
            hide.restart();
        }
    }
    Timer { id: hide; interval: 1500; onTriggered: root.shown = false }

    function ic(cp) { return String.fromCodePoint(cp); }
    readonly property int icon: kind === "brightness" ? (value < 34 ? 0xf00de : value < 67 ? 0xf00df : 0xf00e0)
                              : kind === "mic" ? (muted ? 0xf036d : 0xf036c)
                              : muted || value === 0 ? 0xf075f : value < 34 ? 0xf057f : value < 67 ? 0xf0580 : 0xf057e
    readonly property string label: kind === "brightness" ? "Brightness" : kind === "mic" ? "Microphone" : "Volume"

    PanelWindow {
        anchors.bottom: true
        margins.bottom: 84
        implicitWidth: 360; implicitHeight: 72
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "qs-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}                                     // clicks go through

        Rectangle {
            id: pill
            anchors.centerIn: parent
            width: 340; height: 60; radius: 30
            color: Qt.rgba(0.07, 0.07, 0.11, 0.82)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.92
            Behavior on opacity { NumberAnimation { duration: root.shown ? 120 : 380; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

            Rectangle {
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40; radius: 20
                color: root.muted ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                Text {
                    anchors.centerIn: parent
                    text: root.ic(root.icon)
                    color: root.muted ? Qt.rgba(1, 1, 1, 0.5) : root.accent
                    font { family: "JetBrainsMono Nerd Font Propo"; pixelSize: 20 }
                }
            }
            Text {
                x: 64; y: 12
                text: root.muted ? root.label + " muted" : root.label
                color: Qt.rgba(1, 1, 1, 0.75)
                font { family: "Montserrat"; pixelSize: 12; weight: Font.DemiBold }
            }
            Item {
                id: track
                x: 64; y: 35
                width: 210; height: 8
                Rectangle { anchors.fill: parent; radius: 4; color: Qt.rgba(1, 1, 1, 0.12) }
                Rectangle {
                    height: parent.height; radius: 4
                    width: parent.width * Math.min(100, root.value) / 100
                    color: root.muted ? Qt.rgba(1, 1, 1, 0.35) : root.accent
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: root.value + "%"
                color: "white"
                font { family: "Montserrat"; pixelSize: 15; weight: Font.Bold; features: { "tnum": 1 } }
            }
        }
    }
}
