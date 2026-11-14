import QtQuick

// The password entry every layout uses. Enter signs in (or runs `submitHandler` when a
// layout sets it), F1 switches session, F2 switches user.
TextInput {
    id: f
    property var theme
    property var session
    property var submitHandler: null
    property string hint: "password"
    property color hintColor: theme.muted
    property bool showCursorBlock: false

    echoMode: TextInput.Password
    passwordCharacter: "•"
    passwordMaskDelay: 0
    font.family: theme.font
    color: theme.fg
    selectionColor: theme.accent
    selectedTextColor: theme.bg
    verticalAlignment: TextInput.AlignVCenter
    clip: true
    focus: true
    cursorDelegate: Rectangle { width: 2 * f.theme.u; color: f.theme.accent2; visible: !f.showCursorBlock && f.cursorVisible }

    onAccepted: {
        if (typeof submitHandler === "function") submitHandler(text)
        else session.login(text)
    }
    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_F1) { session.cycleSession(1); e.accepted = true }
        else if (e.key === Qt.Key_F2) { session.cycleUser(1); e.accepted = true }
    }
    Connections {
        target: f.session
        function onFailuresChanged() { f.text = "" }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: f.hint
        visible: f.text.length === 0
        color: f.hintColor
        font: f.font
    }
    Rectangle {   // terminal-style block cursor
        visible: f.showCursorBlock && f.activeFocus
        x: f.contentWidth + 3 * f.theme.u
        anchors.verticalCenter: parent.verticalCenter
        width: f.font.pixelSize * 0.6
        height: f.font.pixelSize * 1.2
        color: f.theme.fg
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 0 }
            PauseAnimation { duration: 530 }
            NumberAnimation { to: 0; duration: 0 }
            PauseAnimation { duration: 530 }
        }
    }
    Component.onCompleted: forceActiveFocus()
    Timer { interval: 250; running: true; onTriggered: f.forceActiveFocus() }
}
