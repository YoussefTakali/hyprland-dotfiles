import QtQuick

// A clickable icon/text (power actions, session switch...). Dimmed when the
// power action is not allowed.
Text {
    id: g
    property var theme
    property var session
    property string action: ""          // suspend | reboot | poweroff, or empty
    property color normal: theme.fg
    property color hover: theme.accent2
    signal clicked()

    readonly property bool allowed: action === "" || session.can(action)
    opacity: allowed ? 1 : 0.3
    color: area.containsMouse && allowed ? hover : normal
    font.family: theme.font
    Behavior on color { ColorAnimation { duration: 120 } }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -8 * g.theme.u
        hoverEnabled: true
        cursorShape: g.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: { if (g.action) g.session.power(g.action); g.clicked() }
    }
}
