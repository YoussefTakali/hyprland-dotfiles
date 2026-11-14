import QtQuick
import "../components"

// The login screen as a Hyprland workspace: tiled windows with gaps, the
// gradient active border on the focused (login) window, blurred desktop behind.
Item {
    id: s
    property var theme
    property var session
    property Item backdrop
    readonly property real u: theme.u
    readonly property real g: 12 * u
    readonly property real m: 2 * g
    property real reveal: 0
    NumberAnimation on reveal { from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }

    WallView { anchors.fill: parent; backdrop: s.backdrop; blur: 0.8; brightness: -0.12 }
    Rectangle { anchors.fill: parent; color: s.theme.bg; opacity: 0.25 }

    // ---- geometry: login stack on the right, left, or between two wallpaper windows
    readonly property string position: theme.position || "right"
    readonly property real rw: position === "center" ? (width - 2 * m - 2 * g) * 0.38 : (width - 2 * m - g) * 0.4
    readonly property real sideW: position === "center" ? (width - 2 * m - 2 * g - rw) / 2 : width - 2 * m - g - rw
    readonly property real rx: position === "left" ? m : m + sideW + g

    component WallWindow: Item {
        property bool workspaces: false
        y: s.m
        height: s.height - 2 * s.m
        opacity: s.reveal
        Rectangle { anchors.fill: parent; radius: s.theme.rounding; color: Qt.rgba(1, 1, 1, 0.08) }
        WallView {
            anchors.fill: parent; anchors.margins: 2 * s.u
            backdrop: s.backdrop
            radius: s.theme.rounding - 2 * s.u
        }
        Rectangle {   // workspace indicator, like a waybar module
            visible: parent.workspaces
            anchors { left: parent.left; bottom: parent.bottom; margins: 22 * s.u }
            height: 40 * s.u; width: ws.width + 28 * s.u; radius: height / 2
            color: s.theme.alpha(s.theme.bg, 0.78)
            Row {
                id: ws
                anchors.centerIn: parent
                spacing: 8 * s.u
                Repeater {
                    model: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: index === 0 ? 26 * s.u : 9 * s.u; height: 9 * s.u; radius: height / 2
                        color: index === 0 ? s.theme.accent : s.theme.alpha(s.theme.fg, 0.35)
                    }
                }
            }
        }
    }
    WallWindow {   // the wallpaper itself, unblurred
        workspaces: true
        x: s.position === "left" ? s.rx + s.rw + s.g : s.m
        width: s.sideW
    }
    WallWindow {   // centered layout: a second wallpaper window on the right
        visible: s.position === "center"
        x: s.rx + s.rw + s.g
        width: s.sideW
    }

    readonly property real stackH: height - 2 * m - 2 * g

    Surface {   // clock
        id: clock
        theme: s.theme; backdrop: s.backdrop
        x: s.rx + (1 - s.reveal) * 40 * s.u; y: s.m
        width: s.rw; height: s.stackH * 0.33
        opacity: s.reveal
        Column {
            anchors.left: parent.left; anchors.leftMargin: 40 * s.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * s.u
            Text {
                text: Qt.formatTime(s.session.now, "HH:mm")
                color: s.theme.fg
                font: s.theme.light(112 * s.u)
            }
            Text {
                text: Qt.formatDate(s.session.now, "dddd d MMMM")
                color: s.theme.accent2
                font { family: s.theme.font; pixelSize: 24 * s.u }
            }
        }
    }

    Surface {   // login: the focused window
        id: login
        theme: s.theme; backdrop: s.backdrop
        gradientBorder: true
        x: s.rx + (1 - s.reveal) * 60 * s.u; y: clock.y + clock.height + s.g
        width: s.rw; height: s.stackH * 0.42
        opacity: s.reveal
        Column {
            anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 36 * s.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 24 * s.u
            Row {
                spacing: 18 * s.u
                Rectangle {
                    width: 64 * s.u; height: width; radius: s.theme.rounding
                    color: s.theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: s.session.initial
                        color: s.theme.bg
                        font { family: s.theme.font; pixelSize: 30 * s.u; weight: Font.Bold }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * s.u
                    Text {
                        text: s.session.greeting + ", " + s.session.displayName
                        color: s.theme.fg
                        font { family: s.theme.font; pixelSize: 26 * s.u; weight: Font.DemiBold }
                    }
                    Glyph {
                        theme: s.theme; session: s.session
                        text: s.theme.iUser + "  " + s.session.userName + "@" + s.theme.host + (s.session.userCount > 1 ? "   ⇄ F2" : "")
                        normal: s.theme.muted
                        font.pixelSize: 15 * s.u
                        onClicked: s.session.cycleUser(1)
                    }
                }
            }
            Rectangle {
                id: field
                width: parent.width; height: 58 * s.u
                radius: s.theme.rounding * 0.75
                color: s.theme.alpha(s.theme.c(0), 0.55)
                border.width: 1.5 * s.u
                border.color: s.session.failed ? s.theme.accent2 : password.activeFocus ? s.theme.accent : Qt.rgba(1, 1, 1, 0.08)
                Text {
                    id: lock
                    anchors { left: parent.left; leftMargin: 20 * s.u; verticalCenter: parent.verticalCenter }
                    text: s.theme.iLock
                    color: s.theme.accent
                    font { family: s.theme.font; pixelSize: 18 * s.u }
                }
                Secret {
                    id: password
                    theme: s.theme; session: s.session
                    anchors { left: lock.right; leftMargin: 16 * s.u; right: caps.left; rightMargin: 12 * s.u; verticalCenter: parent.verticalCenter }
                    height: parent.height
                    font.pixelSize: 20 * s.u
                    hint: s.session.failed ? "wrong password, try again" : "password"
                    hintColor: s.session.failed ? s.theme.accent2 : s.theme.muted
                }
                Text {
                    id: caps
                    anchors { right: parent.right; rightMargin: 20 * s.u; verticalCenter: parent.verticalCenter }
                    text: s.session.capsLock ? "CAPS" : ""
                    color: s.theme.accent2
                    font { family: s.theme.font; pixelSize: 13 * s.u; weight: Font.Bold }
                }
            }
            Row {
                spacing: 12 * s.u
                Rectangle {
                    height: 38 * s.u; width: sessionLabel.width + 30 * s.u; radius: height / 2
                    color: s.theme.alpha(s.theme.accent, 0.18)
                    border.width: 1 * s.u; border.color: s.theme.alpha(s.theme.accent, 0.5)
                    Glyph {
                        id: sessionLabel
                        anchors.centerIn: parent
                        theme: s.theme; session: s.session
                        text: s.theme.iSession + "  " + s.session.sessionName + "  ▾"
                        font.pixelSize: 15 * s.u
                        onClicked: s.session.cycleSession(1)
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "F1 session  ·  ↵ sign in"
                    color: s.theme.muted
                    font { family: s.theme.font; pixelSize: 13 * s.u }
                }
            }
        }
    }

    // ---- bottom row: system info + power ---------------------------------------
    Surface {
        id: info
        theme: s.theme; backdrop: s.backdrop
        x: s.rx + (1 - s.reveal) * 80 * s.u; y: login.y + login.height + s.g
        width: (s.rw - s.g) * 0.62; height: s.height - s.m - y
        opacity: s.reveal
        Column {
            anchors.left: parent.left; anchors.leftMargin: 28 * s.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * s.u
            Repeater {
                model: [[s.theme.iLinux, s.theme.os], [s.theme.iSession, s.theme.wm + (s.theme.kernel ? "  ·  " + s.theme.kernel : "")],
                        [s.theme.iPalette, s.theme.gtk || s.theme.font],
                        [s.theme.iKeyboard, (s.session.layout ? s.session.layout + "  ·  " : "") + s.theme.host]]
                Row {
                    spacing: 14 * s.u
                    Text { text: modelData[0]; color: s.theme.accent; font { family: s.theme.font; pixelSize: 15 * s.u } width: 18 * s.u }
                    Text { text: modelData[1]; color: s.theme.fg; elide: Text.ElideRight; width: info.width - 90 * s.u; font { family: s.theme.font; pixelSize: 15 * s.u } }
                }
            }
        }
    }
    Surface {
        theme: s.theme; backdrop: s.backdrop
        x: info.x + info.width + s.g; y: info.y
        width: s.rw - info.width - s.g; height: info.height
        opacity: s.reveal
        Row {
            anchors.centerIn: parent
            spacing: 34 * s.u
            Repeater {
                model: [["suspend", s.theme.iSleep], ["reboot", s.theme.iReboot], ["poweroff", s.theme.iPower]]
                Glyph {
                    theme: s.theme; session: s.session
                    action: modelData[0]; text: modelData[1]
                    font.pixelSize: 26 * s.u
                }
            }
        }
    }
}
