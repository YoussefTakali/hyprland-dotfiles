import QtQuick

// A Hyprland "window": blurred wallpaper + palette tint + border, which can be the
// active-border gradient (color13 -> color12 -> color14, as in UserDecorations.conf).
Item {
    id: s
    property var theme
    property Item backdrop
    property real radius: theme.rounding
    property real borderWidth: 2 * theme.u
    property bool gradientBorder: false
    property color borderColor: Qt.rgba(1, 1, 1, 0.08)
    property color tintColor: theme.bg
    property real tint: 0.82
    property real blur: 0.7
    default property alias content: inner.data

    Rectangle {
        anchors.fill: parent
        radius: s.radius
        visible: !s.gradientBorder
        color: s.borderColor
        antialiasing: true
    }
    Rectangle {
        anchors.fill: parent
        radius: s.radius
        visible: s.gradientBorder
        antialiasing: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: s.theme.accent2 }
            GradientStop { position: 0.5; color: s.theme.accent }
            GradientStop { position: 1; color: s.theme.accent3 }
        }
    }
    WallView {
        anchors.fill: parent
        anchors.margins: s.borderWidth
        backdrop: s.backdrop
        blur: s.blur
        radius: Math.max(0, s.radius - s.borderWidth)
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: s.borderWidth
        radius: Math.max(0, s.radius - s.borderWidth)
        color: s.tintColor
        opacity: s.tint
        antialiasing: true
    }
    Item { id: inner; anchors.fill: parent; anchors.margins: s.borderWidth }
}
