import QtQuick

Item {
    id: scene
    property bool animated: true
    Rectangle { anchors.fill: parent; color: "#555080" }
    Image { anchors.fill: parent; source: "jake.png"; fillMode: Image.PreserveAspectCrop }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#10242455" }
            GradientStop { position: 0.55; color: "#00242455" }
            GradientStop { position: 1; color: "#b8242455" }
        }
    }
    Item {
        // Keep Jake visible on the left; put the welcome in the open sky.
        x: parent.width * .72 - width / 2
        y: parent.height * .48 - height / 2
        width: Math.min(parent.width * .43, 660)
        height: 280
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0; text: "A LITTLE MOMENT OF CHILL"
            color: "#d8d8ff"; font { family: "Montserrat"; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 4 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 38; text: "Welcome back."
            color: "#f8f5ff"; font { family: "Montserrat"; pixelSize: Math.min(48, scene.width / 35); weight: Font.DemiBold; letterSpacing: -1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 111; text: "Your next adventure is almost ready."
            color: "#dedcf3"; font { family: "Montserrat"; pixelSize: 16 }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 168; spacing: 10
            Repeater {
                model: 5
                Rectangle {
                    id: dot
                    required property int index
                    width: 6; height: 6; radius: 3
                    color: index === 2 ? "#f2bd68" : "#d8d8ff"
                    opacity: .55
                    SequentialAnimation {
                        running: scene.animated
                        PauseAnimation { duration: dot.index * 130 }
                        SequentialAnimation {
                            loops: Animation.Infinite
                            NumberAnimation { target: dot; property: "opacity"; to: 1; duration: 400; easing.type: Easing.InOutSine }
                            NumberAnimation { target: dot; property: "opacity"; to: .3; duration: 400; easing.type: Easing.InOutSine }
                            PauseAnimation { duration: 450 }
                        }
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 207; text: "Settling into your space"
            color: "#cbc8e9"; font { family: "Montserrat"; pixelSize: 12; letterSpacing: .6 }
        }
    }
    Text {
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: parent.height * .045 }
        text: "GOOD VIBES  /  GREAT ADVENTURES"
        color: "#bdb7df"; font { family: "Montserrat"; pixelSize: 9; letterSpacing: 3 }
    }
}
