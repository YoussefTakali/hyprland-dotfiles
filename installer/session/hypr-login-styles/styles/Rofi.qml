import QtQuick
import "../components"

// A rofi launcher over the plain desktop, in the colors of the wallust rofi theme:
// type the password in the input bar, pick the session (or a power action) in
// the list with ↑/↓, Enter runs the highlighted row. Tab shows the users.
Item {
    id: s
    property var theme
    property var session
    property Item backdrop
    readonly property real u: theme.u
    readonly property real rowH: 54 * u
    property string mode: "sessions"
    property real reveal: 0
    NumberAnimation on reveal { from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }

    readonly property var entries: {
        var out = []
        if (mode === "users") {
            for (var i = 0; i < session.userCount; i++)
                out.push({ kind: "user", idx: i, icon: theme.iUser, label: session.userNameAt(i), note: i === session.userIndex ? "current" : "" })
        } else {
            for (var j = 0; j < session.sessionCount; j++)
                out.push({ kind: "session", idx: j, icon: theme.iSession, label: session.sessionNameAt(j), note: "session" })
            out.push({ kind: "power", action: "suspend", icon: theme.iSleep, label: "Suspend", note: "power" })
            out.push({ kind: "power", action: "reboot", icon: theme.iReboot, label: "Reboot", note: "power" })
            out.push({ kind: "power", action: "poweroff", icon: theme.iPower, label: "Shut down", note: "power" })
        }
        return out
    }
    function run(password) {
        var e = entries[list.currentIndex]
        if (!e) return session.login(password)
        if (e.kind === "power") session.power(e.action)
        else if (e.kind === "user") { session.userIndex = e.idx; mode = "sessions"; list.currentIndex = session.sessionIndex }
        else { session.sessionIndex = e.idx; session.login(password) }
    }
    function toggleMode() {
        mode = mode === "users" ? "sessions" : "users"
        list.currentIndex = mode === "users" ? session.userIndex : session.sessionIndex
    }
    Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
    Keys.onDownPressed: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
    Keys.onTabPressed: toggleMode()
    Keys.onEscapePressed: if (mode === "users") toggleMode()

    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.18 }
    Text {   // a small clock, like a bar module peeking from the desktop
        anchors { top: parent.top; margins: 28 * s.u; right: s.theme.position === "right" ? undefined : parent.right; left: s.theme.position === "right" ? parent.left : undefined }
        text: Qt.formatDate(s.session.now, "ddd d MMM") + "   " + Qt.formatTime(s.session.now, "HH:mm")
        color: s.theme.fg
        font { family: s.theme.font; pixelSize: 18 * s.u; weight: Font.DemiBold }
        style: Text.Raised; styleColor: s.theme.alpha("#000000", 0.4)
    }

    Surface {
        id: win
        theme: s.theme; backdrop: s.backdrop
        borderColor: s.theme.accent              // rofi: border-color
        tintColor: "#000000"; tint: 0.7          // rofi: background rgba(0,0,0,0.7)
        blur: 0.6
        width: 760 * s.u
        height: content.height + 2 * 22 * s.u + 2 * borderWidth
        x: s.theme.position === "left" ? 96 * s.u : s.theme.position === "right" ? s.width - width - 96 * s.u : (s.width - width) / 2
        y: s.height * 0.22 + (1 - s.reveal) * -16 * s.u
        opacity: s.reveal

        Column {
            id: content
            x: 22 * s.u; y: 22 * s.u
            width: parent.width - 44 * s.u
            spacing: 14 * s.u

            Rectangle {   // inputbar
                width: parent.width; height: 62 * s.u
                radius: s.theme.rounding * 0.75
                color: s.theme.alpha(s.theme.bg, 0.9)
                Rectangle {
                    id: prompt
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 7 * s.u }
                    width: promptText.width + 30 * s.u
                    radius: s.theme.rounding * 0.6
                    color: s.theme.accent2                   // rofi: selected-normal-background
                    Text {
                        id: promptText
                        anchors.centerIn: parent
                        text: s.theme.iLock + "  login"
                        color: s.theme.bg
                        font { family: s.theme.font; pixelSize: 17 * s.u; weight: Font.Bold }
                    }
                }
                Secret {
                    theme: s.theme; session: s.session
                    anchors { left: prompt.right; leftMargin: 16 * s.u; right: who.left; rightMargin: 12 * s.u; verticalCenter: parent.verticalCenter }
                    height: parent.height
                    font.pixelSize: 19 * s.u
                    hint: "password for " + s.session.displayName
                    submitHandler: s.run
                }
                Glyph {
                    id: who
                    anchors { right: parent.right; rightMargin: 18 * s.u; verticalCenter: parent.verticalCenter }
                    theme: s.theme; session: s.session
                    text: s.theme.iUser + " " + s.session.userName
                    normal: s.theme.muted
                    font.pixelSize: 15 * s.u
                    onClicked: s.toggleMode()
                }
            }

            Text {   // rofi -mesg
                visible: s.session.failed || s.session.capsLock
                text: s.theme.iWarn + "  " + (s.session.failed ? "Authentication failed, try again" : "Caps Lock is on")
                color: s.theme.accent2
                font { family: s.theme.font; pixelSize: 15 * s.u }
                leftPadding: 6 * s.u
            }

            ListView {
                id: list
                width: parent.width
                height: Math.min(count, 8) * s.rowH
                model: s.entries
                interactive: false
                currentIndex: s.session.sessionIndex
                highlightMoveDuration: 90
                highlight: Rectangle { radius: s.theme.rounding * 0.6; color: s.theme.accent2 }
                delegate: Item {
                    width: list.width; height: s.rowH
                    readonly property bool current: ListView.isCurrentItem
                    Row {
                        anchors { left: parent.left; leftMargin: 18 * s.u; verticalCenter: parent.verticalCenter }
                        spacing: 16 * s.u
                        Text {
                            width: 24 * s.u
                            text: modelData.icon
                            color: current ? s.theme.bg : (modelData.kind === "power" ? s.theme.accent2 : s.theme.accent)
                            font { family: s.theme.font; pixelSize: 19 * s.u }
                        }
                        Text {
                            text: modelData.label
                            color: current ? s.theme.bg : s.theme.fg
                            font { family: s.theme.font; pixelSize: 18 * s.u; weight: current ? Font.Bold : Font.Normal }
                        }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 18 * s.u; verticalCenter: parent.verticalCenter }
                        text: modelData.note
                        color: current ? s.theme.alpha(s.theme.bg, 0.7) : s.theme.muted
                        font { family: s.theme.font; pixelSize: 13 * s.u }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { list.currentIndex = index; if (modelData.kind !== "session") s.run("") }
                    }
                }
            }

            Row {   // mode switcher
                width: parent.width; height: 44 * s.u
                spacing: 10 * s.u
                Repeater {
                    model: [["sessions", s.theme.iSession + "  sessions"], ["users", s.theme.iUser + "  users"]]
                    Rectangle {
                        width: (parent.width - 10 * s.u) / 2; height: parent.height
                        radius: s.theme.rounding * 0.6
                        color: s.mode === modelData[0] ? s.theme.alpha(s.theme.accent, 0.35) : s.theme.alpha(s.theme.bg, 0.6)
                        Text {
                            anchors.centerIn: parent
                            text: modelData[1]
                            color: s.theme.fg
                            font { family: s.theme.font; pixelSize: 15 * s.u }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (s.mode !== modelData[0]) s.toggleMode() }
                    }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "↑↓ choose  ·  ↵ run  ·  Tab users"
                color: s.theme.muted
                font { family: s.theme.font; pixelSize: 13 * s.u }
            }
        }
    }
}
