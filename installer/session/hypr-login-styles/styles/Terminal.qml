import QtQuick
import "../components"

// A kitty window over the blurred desktop: fastfetch output drawn from this
// machine, then a `login:` prompt, and a tmux-style status line with power.
Item {
    id: s
    property var theme
    property var session
    property Item backdrop
    readonly property real u: theme.u
    readonly property real fs: 19 * u          // terminal font size
    readonly property real lh: fs * 1.55       // line height
    property real reveal: 0
    NumberAnimation on reveal { from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }

    function tint(c, text) { return "<font color='" + String(c) + "'>" + text + "</font>" }

    WallView { anchors.fill: parent; backdrop: s.backdrop; blur: 0.55; brightness: -0.08 }

    Surface {
        id: win
        theme: s.theme; backdrop: s.backdrop
        gradientBorder: true
        tint: 0.9; blur: 0.9
        width: 1240 * s.u; height: 720 * s.u
        x: s.theme.position === "left" ? 96 * s.u : s.theme.position === "right" ? s.width - width - 96 * s.u : (s.width - width) / 2
        y: (s.height - height) / 2 + (1 - s.reveal) * 30 * s.u
        opacity: s.reveal

        Item {
            id: screen
            anchors { fill: parent; margins: 34 * s.u; bottomMargin: bar.height + 20 * s.u }

            Text {   // the command that produced the readout
                id: cmd
                textFormat: Text.StyledText
                text: s.tint(s.theme.accent, "❯ ") + s.tint(s.theme.fg, "fastfetch")
                font { family: s.theme.font; pixelSize: s.fs }
            }

            // "logo" column: a big clock in place of the distro art
            Column {
                id: art
                anchors { top: cmd.bottom; topMargin: s.lh * 0.8 }
                width: 410 * s.u
                spacing: 2 * s.u
                Text {
                    text: Qt.formatTime(s.session.now, "HH:mm")
                    color: s.theme.accent
                    font { family: s.theme.font; pixelSize: 118 * s.u; weight: Font.Bold }
                }
                Text {
                    text: Qt.formatDate(s.session.now, "dddd d MMMM").toLowerCase()
                    color: s.theme.accent2
                    font { family: s.theme.font; pixelSize: s.fs }
                }
                Item { width: 1; height: s.lh }
                Grid {   // the palette, as fastfetch prints it
                    columns: 8; spacing: 0
                    Repeater {
                        model: 16
                        Rectangle { width: 40 * s.u; height: 24 * s.u; color: s.theme.c(index) }
                    }
                }
            }

            Column {
                id: fetch
                anchors { left: art.right; leftMargin: 40 * s.u; top: art.top; right: parent.right }
                spacing: 0
                Text {
                    textFormat: Text.StyledText
                    text: s.tint(s.theme.accent2, s.session.userName) + s.tint(s.theme.fg, "@") + s.tint(s.theme.accent, s.theme.host)
                    font { family: s.theme.font; pixelSize: s.fs; weight: Font.Bold }
                    height: s.lh
                }
                Text {
                    text: "─".repeat(Math.max(8, (s.session.userName + s.theme.host).length + 1))
                    color: s.theme.muted
                    font { family: s.theme.font; pixelSize: s.fs }
                    height: s.lh
                }
                Repeater {
                    model: [["OS", s.theme.os], ["Kernel", s.theme.kernel], ["WM", s.theme.wm],
                            ["Shell", s.theme.shell], ["Terminal", s.theme.terminal], ["Theme", s.theme.gtk],
                            ["Icons", s.theme.icons], ["Font", s.theme.font], ["Session", s.session.sessionName + "  (F1)"]]
                    Item {
                        visible: modelData[1] !== "" && modelData[1] !== undefined
                        width: fetch.width; height: visible ? s.lh : 0
                        Text {
                            width: 150 * s.u
                            text: modelData[0]
                            color: s.theme.accent
                            font { family: s.theme.font; pixelSize: s.fs; weight: Font.Bold }
                        }
                        Glyph {
                            x: 150 * s.u
                            width: parent.width - x
                            elide: Text.ElideRight
                            theme: s.theme; session: s.session
                            text: modelData[1]
                            font.pixelSize: s.fs
                            hover: modelData[0] === "Session" ? s.theme.accent2 : s.theme.fg
                            onClicked: if (modelData[0] === "Session") s.session.cycleSession(1)
                        }
                    }
                }
            }

            // the prompt, at the bottom of the screen like a fresh shell
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                Text {
                    visible: s.session.failed
                    height: visible ? s.lh : 0
                    text: "Login incorrect" + (s.session.failures > 1 ? "  (" + s.session.failures + ")" : "")
                    color: s.theme.accent2
                    font { family: s.theme.font; pixelSize: s.fs }
                }
                Text {
                    height: s.lh
                    textFormat: Text.StyledText
                    text: s.tint(s.theme.accent, "❯ ") + s.tint(s.theme.fg, "login ") + s.tint(s.theme.accent2, s.session.userName)
                          + (s.session.capsLock ? s.tint(s.theme.muted, "    [caps lock]") : "")
                    font { family: s.theme.font; pixelSize: s.fs }
                }
                Row {
                    height: s.lh
                    Text {
                        id: label
                        text: "Password: "
                        color: s.theme.fg
                        font { family: s.theme.font; pixelSize: s.fs }
                    }
                    Secret {
                        theme: s.theme; session: s.session
                        width: s.width; height: label.height
                        font.pixelSize: s.fs
                        hint: ""
                        showCursorBlock: true
                    }
                }
            }
        }

        // tmux-like status line
        Rectangle {
            id: bar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 2 * s.u }
            height: 38 * s.u
            color: s.theme.alpha(s.theme.c(0), 0.6)
            radius: s.theme.rounding - 2 * s.u
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                Rectangle {
                    height: bar.height; width: tab.width + 32 * s.u
                    color: s.theme.accent
                    radius: s.theme.rounding - 2 * s.u
                    Text { id: tab; anchors.centerIn: parent; text: "0:login*"; color: s.theme.bg; font { family: s.theme.font; pixelSize: 15 * s.u; weight: Font.Bold } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 16 * s.u
                    text: s.theme.terminal ? "1:" + s.theme.shell + "  2:" + s.theme.terminal : ""
                    color: s.theme.muted
                    font { family: s.theme.font; pixelSize: 15 * s.u }
                }
            }
            Row {
                anchors { right: parent.right; rightMargin: 18 * s.u; verticalCenter: parent.verticalCenter }
                spacing: 22 * s.u
                Repeater {
                    model: [["suspend", s.theme.iSleep + " sleep"], ["reboot", s.theme.iReboot + " reboot"], ["poweroff", s.theme.iPower + " off"]]
                    Glyph {
                        theme: s.theme; session: s.session
                        action: modelData[0]; text: modelData[1]
                        normal: s.theme.fg
                        font.pixelSize: 15 * s.u
                    }
                }
                Text {
                    text: "│  " + s.theme.host + "  " + Qt.formatTime(s.session.now, "HH:mm")
                    color: s.theme.accent2
                    font { family: s.theme.font; pixelSize: 15 * s.u }
                }
            }
        }
    }
}
