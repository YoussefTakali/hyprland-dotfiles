import QtQuick
import "../components"

// A magazine spread: a solid panel in the palette's background with a huge thin
// clock and an underlined password line; the wallpaper as the full-bleed photo.
Item {
    id: s
    property var theme
    property var session
    property Item backdrop
    readonly property real u: theme.u
    readonly property real margin: 92 * u
    readonly property string position: theme.position || "left"
    property real reveal: 0
    NumberAnimation on reveal { from: 0; to: 1; duration: 700; easing.type: Easing.OutQuart }

    function caps(text) { return String(text).toUpperCase() }
    readonly property int week: {
        var d = new Date(Date.UTC(session.now.getFullYear(), session.now.getMonth(), session.now.getDate()))
        var day = d.getUTCDay() || 7
        d.setUTCDate(d.getUTCDate() + 4 - day)
        return Math.ceil(((d - new Date(Date.UTC(d.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7)
    }

    // caption on the photo
    Rectangle {
        anchors { bottom: parent.bottom; margins: 48 * s.u
                  right: s.position === "right" ? undefined : parent.right; left: s.position === "right" ? parent.left : undefined }
        width: caption.width + 40 * s.u; height: caption.height + 26 * s.u
        color: s.theme.alpha(s.theme.bg, 0.72)
        Text {
            id: caption
            anchors.centerIn: parent
            text: "Nº " + s.week + "   —   " + s.caps(s.theme.wm) + " / " + s.caps(s.theme.host)
            color: s.theme.fg
            font { family: s.theme.font; pixelSize: 13 * s.u; letterSpacing: 4 * s.u }
        }
    }

    Rectangle {
        id: panel
        width: parent.width * 0.44 * (0.85 + 0.15 * s.reveal)
        height: parent.height
        x: s.position === "right" ? parent.width - width : s.position === "center" ? (parent.width - width) / 2 : 0
        color: s.theme.bg
        Rectangle { visible: s.position !== "right"; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 3 * s.u; color: s.theme.accent2 }
        Rectangle { visible: s.position !== "left"; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 3 * s.u; color: s.theme.accent2 }

        Item {
            anchors { fill: parent; margins: s.margin; leftMargin: s.margin + 8 * s.u }
            opacity: s.reveal

            Text {
                id: dateline
                text: s.caps(Qt.formatDate(s.session.now, "dddd  —  d MMMM yyyy"))
                color: s.theme.accent2
                font { family: s.theme.font; pixelSize: 15 * s.u; letterSpacing: 6 * s.u; weight: Font.DemiBold }
            }
            Column {
                id: clock
                anchors { top: dateline.bottom; topMargin: 18 * s.u }
                spacing: -70 * s.u
                Text {
                    text: Qt.formatTime(s.session.now, "HH")
                    color: s.theme.fg
                    font: s.theme.thin(250 * s.u)
                }
                Text {
                    text: Qt.formatTime(s.session.now, "mm")
                    color: s.theme.accent
                    font: s.theme.thin(250 * s.u)
                }
            }
            Text {
                id: greeting
                anchors { top: clock.bottom; topMargin: 10 * s.u }
                text: s.session.greeting + ", " + s.session.displayName + "."
                color: s.theme.fg
                font: s.theme.light(34 * s.u)
            }

            Column {
                anchors { top: greeting.bottom; topMargin: 56 * s.u; left: parent.left; right: parent.right }
                spacing: 12 * s.u
                Text {
                    text: s.session.failed ? "INCORRECT — TRY AGAIN" : s.session.capsLock ? "PASSWORD  ·  CAPS LOCK" : "PASSWORD"
                    color: s.session.failed ? s.theme.accent2 : s.theme.muted
                    font { family: s.theme.font; pixelSize: 12 * s.u; letterSpacing: 5 * s.u; weight: Font.DemiBold }
                }
                Secret {
                    id: password
                    theme: s.theme; session: s.session
                    width: parent.width * 0.86; height: 44 * s.u
                    font.pixelSize: 26 * s.u
                    font.letterSpacing: 6 * s.u
                    hint: ""
                }
                Rectangle {
                    width: parent.width * 0.86; height: 1.5 * s.u
                    color: s.theme.alpha(s.theme.fg, 0.25)
                    Rectangle {
                        height: parent.height
                        width: password.activeFocus ? parent.width : 0
                        color: s.session.failed ? s.theme.accent2 : s.theme.accent
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    topPadding: 6 * s.u
                    text: "↵  SIGN IN      F1  SESSION      F2  USER"
                    color: s.theme.alpha(s.theme.fg, 0.4)
                    font { family: s.theme.font; pixelSize: 11 * s.u; letterSpacing: 3 * s.u }
                }
            }

            Row {   // footer: session · power
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                spacing: 30 * s.u
                Glyph {
                    theme: s.theme; session: s.session
                    text: s.caps(s.session.sessionName) + "  ▸"
                    normal: s.theme.accent
                    font { pixelSize: 12 * s.u; letterSpacing: 4 * s.u; weight: Font.Bold }
                    onClicked: s.session.cycleSession(1)
                }
                Repeater {
                    model: [["suspend", "SLEEP"], ["reboot", "RESTART"], ["poweroff", "SHUT DOWN"]]
                    Glyph {
                        theme: s.theme; session: s.session
                        action: modelData[0]; text: modelData[1]
                        normal: s.theme.muted
                        font { pixelSize: 12 * s.u; letterSpacing: 4 * s.u }
                    }
                }
            }
        }
    }
}
