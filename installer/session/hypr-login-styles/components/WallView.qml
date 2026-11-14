import QtQuick
import QtQuick.Effects

// Shows the part of the wallpaper that lies under this item, optionally blurred
// and darkened, with rounded corners: the "window blur" of the desktop.
Item {
    id: v
    property Item backdrop
    property real blur: 0
    property real brightness: 0
    property real radius: 0
    readonly property real pad: blur > 0 ? 64 : 0

    // Position relative to the backdrop; reading every x/y keeps it live while
    // layouts slide in. (Transforms such as scale are not used by the layouts.)
    readonly property rect area: {
        var x = 0, y = 0, i = v
        while (i && backdrop && i !== backdrop.parent) { x += i.x; y += i.y; i = i.parent }
        return Qt.rect(x - (backdrop ? backdrop.x : 0), y - (backdrop ? backdrop.y : 0), width, height)
    }

    Item {
        anchors.fill: parent
        anchors.margins: -v.pad
        ShaderEffectSource {
            id: source
            anchors.fill: parent
            sourceItem: v.backdrop
            sourceRect: Qt.rect(v.area.x - v.pad, v.area.y - v.pad, v.area.width + 2 * v.pad, v.area.height + 2 * v.pad)
            live: true
            visible: false
        }
        Item {
            id: mask
            anchors.fill: parent
            layer.enabled: true
            visible: false
            Rectangle { x: v.pad; y: v.pad; width: v.width; height: v.height; radius: v.radius; antialiasing: true }
        }
        MultiEffect {
            anchors.fill: parent
            source: source
            autoPaddingEnabled: false
            blurEnabled: v.blur > 0
            blur: Math.min(1, v.blur)
            blurMax: 64
            brightness: v.brightness
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
}
