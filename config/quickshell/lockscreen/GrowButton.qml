// Round icon button that grows and glows smoothly on hover (power + music controls).
import QtQuick

Item {
    id: btn
    property real size: 46
    property string glyph: ""
    property real glyphSize: 18
    property color hot: "#AF5CE5"          // glow / armed color
    property color restColor: "#7E8395"    // icon color at rest
    property bool armed: false
    property bool filled: false            // solid light circle with a dark icon (play/pause)
    property real restGlow: 0.13
    signal clicked()

    width: size; height: size
    readonly property bool hovered: mouse.containsMouse

    Rectangle {
        id: circle
        anchors.centerIn: parent
        width: btn.size; height: btn.size; radius: width / 2
        color: btn.filled ? Qt.rgba(1, 1, 1, btn.hovered ? 1.0 : 0.9)
                          : Qt.rgba(btn.hot.r, btn.hot.g, btn.hot.b, btn.armed ? 0.9 : (btn.hovered ? 0.4 : btn.restGlow))
        scale: btn.armed ? 1.18 : (mouse.pressed ? 0.94 : (btn.hovered ? 1.18 : 1.0))
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }
    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.filled ? "#181825" : (btn.hovered || btn.armed ? "#FFFFFF" : btn.restColor)
        font { family: "JetBrainsMono Nerd Font Propo"; pixelSize: btn.glyphSize * 1.333 }
        scale: circle.scale
        Behavior on color { ColorAnimation { duration: 200 } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
