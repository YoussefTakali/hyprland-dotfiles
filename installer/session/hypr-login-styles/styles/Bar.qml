import QtQuick
import "../components"

// The desktop as you leave it: wallpaper untouched, the vertical waybar on the
// left, and the login arriving as a swaync-style notification next to it.
Item {
    id: s
    property var theme
    property var session
    property Item backdrop
    readonly property real u: theme.u
    readonly property real g: 8 * u
    readonly property string position: theme.position || "left"   // which edge holds the bar; center = card in the middle
    readonly property bool barRight: position === "right"
    property real slide: 0
    NumberAnimation on slide { from: 0; to: 1; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 0.8 }

    // ---- the bar ---------------------------------------------------------------
    Surface {
        id: bar
        theme: s.theme; backdrop: s.backdrop
        tint: 0.84; blur: 0.7
        x: s.barRight ? s.width - s.g - width : s.g; y: s.g
        width: 66 * s.u; height: s.height - 2 * s.g

        Column {   // top: logo + workspaces
            anchors { top: parent.top; topMargin: 22 * s.u; horizontalCenter: parent.horizontalCenter }
            spacing: 22 * s.u
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: s.theme.iLinux
                color: s.theme.accent
                font { family: s.theme.font; pixelSize: 28 * s.u }
            }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 9 * s.u
                Repeater {
                    model: 5
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 10 * s.u; height: index === 0 ? 32 * s.u : 10 * s.u; radius: width / 2
                        color: index === 0 ? s.theme.accent : s.theme.alpha(s.theme.fg, 0.3)
                    }
                }
            }
        }
        Column {   // middle: vertical clock
            anchors.centerIn: parent
            spacing: 2 * s.u
            Repeater {
                model: [[Qt.formatTime(s.session.now, "HH"), s.theme.fg, Font.Bold], [Qt.formatTime(s.session.now, "mm"), s.theme.accent2, Font.Bold]]
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData[0]; color: modelData[1]
                    font { family: s.theme.font; pixelSize: 28 * s.u; weight: modelData[2] }
                }
            }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 22 * s.u; height: 2 * s.u; color: s.theme.alpha(s.theme.fg, 0.2) }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(s.session.now, "ddd").toLowerCase() + "\n" + Qt.formatDate(s.session.now, "d")
                horizontalAlignment: Text.AlignHCenter
                color: s.theme.muted
                font { family: s.theme.font; pixelSize: 15 * s.u }
            }
        }
        Column {   // bottom: keyboard + power
            anchors { bottom: parent.bottom; bottomMargin: 22 * s.u; horizontalCenter: parent.horizontalCenter }
            spacing: 20 * s.u
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: s.session.layout !== "" || s.session.capsLock
                text: s.session.capsLock ? "CAP" : s.session.layout
                color: s.session.capsLock ? s.theme.accent2 : s.theme.muted
                font { family: s.theme.font; pixelSize: 13 * s.u; weight: Font.Bold }
            }
            Repeater {
                model: [["suspend", s.theme.iSleep], ["reboot", s.theme.iReboot], ["poweroff", s.theme.iPower]]
                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    theme: s.theme; session: s.session
                    action: modelData[0]; text: modelData[1]
                    normal: modelData[0] === "poweroff" ? s.theme.accent2 : s.theme.fg
                    font.pixelSize: 22 * s.u
                }
            }
        }
    }

    // ---- notifications ----------------------------------------------------------
    readonly property real cardX: position === "right" ? bar.x - 2 * g - cardW
                                  : position === "center" ? (width - cardW) / 2 : bar.x + bar.width + 2 * g
    readonly property real cardsH: card.height + 2 * g + look.height + 40 * u
    function offscreen(x, progress) {   // slide in from the bar's side, like swaync
        return barRight ? x + (1 - progress) * (width - x) : x - (1 - progress) * (x + cardW)
    }
    readonly property real cardW: 470 * u

    Surface {
        id: card
        theme: s.theme; backdrop: s.backdrop
        borderColor: s.theme.alpha(s.theme.accent, 0.55)
        tint: 0.86
        x: s.offscreen(s.cardX, s.slide)
        y: s.position === "center" ? (s.height - s.cardsH) / 2 : 3 * s.g
        width: s.cardW; height: body.height + 44 * s.u

        Column {
            id: body
            x: 22 * s.u; y: 22 * s.u
            width: parent.width - 44 * s.u
            spacing: 14 * s.u

            Item {   // app line
                width: parent.width; height: 20 * s.u
                Text {
                    text: s.theme.iLock + "   sddm"
                    color: s.theme.accent
                    font { family: s.theme.font; pixelSize: 14 * s.u; weight: Font.Bold }
                }
                Text {
                    anchors.right: parent.right
                    text: "now"
                    color: s.theme.muted
                    font { family: s.theme.font; pixelSize: 13 * s.u }
                }
            }
            Row {
                spacing: 16 * s.u
                Rectangle {
                    width: 54 * s.u; height: width; radius: width / 2
                    color: s.theme.accent2
                    Text {
                        anchors.centerIn: parent
                        text: s.session.initial
                        color: s.theme.bg
                        font { family: s.theme.font; pixelSize: 24 * s.u; weight: Font.Bold }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * s.u
                    Text {
                        text: s.session.greeting + ", " + s.session.displayName
                        color: s.theme.fg
                        font { family: s.theme.font; pixelSize: 20 * s.u; weight: Font.Bold }
                    }
                    Text {
                        text: s.session.failed ? "That password didn't work, try again." : "Sign in to " + s.theme.host + " to continue."
                        color: s.session.failed ? s.theme.accent2 : s.theme.muted
                        font { family: s.theme.font; pixelSize: 14 * s.u }
                    }
                }
            }
            Rectangle {   // inline reply field
                width: parent.width; height: 50 * s.u
                radius: s.theme.rounding * 0.75
                color: s.theme.alpha(s.theme.c(0), 0.5)
                border.width: 1.5 * s.u
                border.color: password.activeFocus ? s.theme.accent : "transparent"
                Secret {
                    id: password
                    theme: s.theme; session: s.session
                    anchors { fill: parent; leftMargin: 18 * s.u; rightMargin: 18 * s.u }
                    font.pixelSize: 18 * s.u
                    hint: s.session.capsLock ? "password  (caps lock on)" : "password"
                }
            }
            Row {   // notification actions
                width: parent.width
                spacing: 10 * s.u
                Rectangle {
                    width: (parent.width - 10 * s.u) / 2; height: 42 * s.u
                    radius: s.theme.rounding * 0.75
                    color: s.theme.alpha(s.theme.fg, 0.08)
                    Glyph {
                        anchors.centerIn: parent
                        theme: s.theme; session: s.session
                        text: s.theme.iSession + "  " + s.session.sessionName
                        font.pixelSize: 15 * s.u
                        onClicked: s.session.cycleSession(1)
                    }
                }
                Rectangle {
                    width: (parent.width - 10 * s.u) / 2; height: 42 * s.u
                    radius: s.theme.rounding * 0.75
                    color: s.theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Sign in  ↵"
                        color: s.theme.bg
                        font { family: s.theme.font; pixelSize: 15 * s.u; weight: Font.Bold }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: s.session.login(password.text) }
                }
            }
        }
    }

    Surface {   // a second, quieter notification: the look this screen follows
        theme: s.theme; backdrop: s.backdrop
        tint: 0.8
        x: s.offscreen(s.cardX, Math.max(0, s.slide * 1.25 - 0.25))
        y: card.y + card.height + 2 * s.g
        width: s.cardW; height: look.height + 40 * s.u
        Column {
            id: look
            x: 22 * s.u; y: 20 * s.u
            width: parent.width - 44 * s.u
            spacing: 12 * s.u
            Text {
                text: s.theme.iPalette + "   wallust"
                color: s.theme.accent
                font { family: s.theme.font; pixelSize: 14 * s.u; weight: Font.Bold }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: [s.theme.gtk, s.theme.icons, s.theme.font].filter(function (x) { return x }).join("  ·  ")
                color: s.theme.fg
                font { family: s.theme.font; pixelSize: 14 * s.u }
            }
            Row {
                spacing: 6 * s.u
                Repeater {
                    model: 16
                    Rectangle { width: 22 * s.u; height: 22 * s.u; radius: 6 * s.u; color: s.theme.c(index) }
                }
            }
        }
    }
}
