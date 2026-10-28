// Calendar + forecast popup under the Waybar clock (CalendarPopup.sh toggles it). Same look as the Slate lock
// screen's second page. ‹ › or scroll to change month, the month title returns to today, Esc / click outside closes.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root
    settings.watchFiles: false

    property color accent: "#AF5CE5"
    readonly property string face: "Montserrat"
    readonly property string glyphs: "JetBrainsMono Nerd Font Propo"
    readonly property color ink: "#ffffff"
    readonly property color muted: Qt.rgba(1, 1, 1, 0.62)
    readonly property color faint: Qt.rgba(1, 1, 1, 0.38)
    function ic(cp) { return String.fromCodePoint(cp); }
    Process {
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/wallust/wallust-hyprland.conf"]
        stdout: StdioCollector { onStreamFinished: { const m = text.match(/^\$color13 = rgb\((\w{6})\)/m); if (m) root.accent = "#" + m[1]; } }
    }

    property bool closing: false
    function close() { if (closing) return; closing = true; quitTimer.start(); }
    Timer { id: quitTimer; interval: 200; onTriggered: Qt.quit() }

    // shown month (offset from today)
    readonly property date today: new Date()
    property int offset: 0
    readonly property date shown: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property var cells: {
        const y = shown.getFullYear(), m = shown.getMonth();
        const isThis = offset === 0, td = today.getDate();
        const first = (new Date(y, m, 1).getDay() + 6) % 7;
        const days = new Date(y, m + 1, 0).getDate();
        const out = [];
        for (let i = 0; i < first; i++) out.push({ d: 0 });
        for (let d = 1; d <= days; d++) {
            const wd = (first + d - 1) % 7;
            out.push({ d: d, today: isThis && d === td, past: offset < 0 || (isThis && d < td), weekend: wd >= 5 });
        }
        return out;
    }

    property var forecast: []
    property real fcMin: 0
    property real fcMax: 1
    Process {
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
                        out.push({ name: d.time[i] === todayKey ? "Today" : Qt.formatDate(new Date(d.time[i] + "T12:00:00"), "ddd"),
                                   lo: d.temperature_2m_min[i], hi: d.temperature_2m_max[i], rain: rain,
                                   icon: rain >= 70 ? 0xf0596 : rain >= 45 ? 0xf0597 : rain >= 20 ? 0xf0595 : 0xf0599 });
                    }
                    root.fcMin = Math.min(...out.map(o => o.lo));
                    root.fcMax = Math.max(...out.map(o => o.hi));
                    root.forecast = out;
                } catch (e) { root.forecast = []; }
            }
        }
    }

    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "qs-calendar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        MouseArea { anchors.fill: parent; onClicked: root.close() }   // click outside closes

        Item {
            id: panel
            focus: true
            Keys.onEscapePressed: root.close()
            Keys.onLeftPressed: root.offset--
            Keys.onRightPressed: root.offset++
            width: 440; height: body.height + 56
            x: (parent.width - width) / 2
            y: 56
            opacity: root.closing ? 0 : 1
            scale: root.closing ? 0.97 : 1
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 180 } }
            Component.onCompleted: { opacity = 1; }
            NumberAnimation on y { from: 40; to: 56; duration: 260; easing.type: Easing.OutCubic }

            MouseArea { anchors.fill: parent }   // clicks inside don't close
            WheelHandler { onWheel: e => { root.offset += e.angleDelta.y < 0 ? 1 : -1; } }

            Rectangle {
                anchors.fill: parent; radius: 22
                color: Qt.rgba(0.07, 0.07, 0.11, 0.82)
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
                Rectangle {
                    anchors.fill: parent; radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) }
                        GradientStop { position: 0.4; color: "transparent" }
                    }
                }
            }

            Column {
                id: body
                x: 28; y: 28
                width: parent.width - 56
                spacing: 0

                // month header with arrows
                Item {
                    width: parent.width; height: 34
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDate(root.shown, "MMMM yyyy")
                        color: root.ink
                        font { family: root.face; pixelSize: 22; weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.offset = 0 }
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            model: [{ g: 0xf0141, d: -1 }, { g: 0xf0142, d: 1 }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 32; height: 32; radius: 16
                                color: arrowMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                                Text { anchors.centerIn: parent; text: root.ic(modelData.g); color: root.ink; font { family: root.glyphs; pixelSize: 18 } }
                                MouseArea { id: arrowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.offset += modelData.d }
                            }
                        }
                    }
                }
                Item { width: 1; height: 14 }
                Grid {
                    id: cal
                    columns: 7
                    rowSpacing: 2
                    readonly property real cw: body.width / 7
                    Repeater {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        delegate: Text {
                            required property string modelData
                            width: cal.cw; height: 24
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData; color: root.faint
                            font { family: root.face; pixelSize: 12; weight: Font.DemiBold }
                        }
                    }
                    Repeater {
                        model: root.cells
                        delegate: Item {
                            required property var modelData
                            width: cal.cw; height: 38
                            Rectangle {
                                anchors.centerIn: parent
                                width: 34; height: 34; radius: 17
                                color: root.accent
                                visible: modelData.today === true
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.d || ""
                                color: modelData.today ? "#11111b" : (modelData.past ? root.faint : (modelData.weekend ? root.muted : root.ink))
                                font { family: root.face; pixelSize: 15; weight: modelData.today ? Font.Bold : Font.Medium }
                            }
                        }
                    }
                }

                Item { width: 1; height: 20; visible: root.forecast.length > 0 }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08); visible: root.forecast.length > 0 }
                Item { width: 1; height: 16; visible: root.forecast.length > 0 }

                Column {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: root.forecast
                        delegate: Item {
                            id: fday
                            required property var modelData
                            width: parent.width; height: 24
                            Text { width: 64; anchors.verticalCenter: parent.verticalCenter; text: fday.modelData.name; color: root.ink; font { family: root.face; pixelSize: 14; weight: Font.DemiBold } }
                            Text { x: 66; width: 24; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter
                                   text: root.ic(fday.modelData.icon); color: root.accent; font { family: root.glyphs; pixelSize: 16 } }
                            Text { x: 98; width: 44; anchors.verticalCenter: parent.verticalCenter
                                   text: fday.modelData.rain >= 20 ? fday.modelData.rain + "%" : ""; color: "#89dceb"; font { family: root.face; pixelSize: 12; weight: Font.DemiBold } }
                            Text { id: lo; x: 146; width: 36; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight
                                   text: Math.round(fday.modelData.lo) + "°"; color: root.muted; font { family: root.face; pixelSize: 14; weight: Font.Medium } }
                            Item {
                                id: range
                                anchors.left: lo.right; anchors.leftMargin: 12
                                anchors.right: hi.left; anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6
                                Rectangle { anchors.fill: parent; radius: 3; color: Qt.rgba(1, 1, 1, 0.1) }
                                Rectangle {
                                    readonly property real span: Math.max(1, root.fcMax - root.fcMin)
                                    x: range.width * (fday.modelData.lo - root.fcMin) / span
                                    width: Math.max(8, range.width * (fday.modelData.hi - fday.modelData.lo) / span)
                                    height: parent.height; radius: 3
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#89b4fa" }
                                        GradientStop { position: 1.0; color: root.accent }
                                    }
                                }
                            }
                            Text { id: hi; anchors.right: parent.right; width: 36; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight
                                   text: Math.round(fday.modelData.hi) + "°"; color: root.ink; font { family: root.face; pixelSize: 14; weight: Font.DemiBold } }
                        }
                    }
                }
            }
        }
    }
}
