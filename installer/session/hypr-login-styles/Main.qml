// Hypr Login Styles: one greeter, several layouts. Layout, background and colors
// come from Desktop/login.conf, written by ~/.config/hypr/scripts/LoginThemes.py
// (Super+Ctrl+Alt+L) and refreshed on every wallpaper change.
import QtQuick
import QtQuick.Window
import "components"

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: theme.bg

    // The Japanese Aesthetic layout is the original sddm-astronaut screen, hosted
    // as-is; it reads its own keys from the same config file.
    readonly property url astronaut: "file:///usr/share/sddm/themes/sddm-astronaut-theme/Main.qml"
    readonly property bool hosted: theme.style === "Japanese"

    Theme { id: theme; u: Math.min(root.width / 1920, root.height / 1080) }
    Session { id: session }

    Backdrop {
        id: backdrop
        anchors.fill: parent
        visible: !root.hosted
        source: root.hosted ? "" : theme.background
        placeholder: root.hosted ? "" : theme.placeholder
        fill: theme.bg
    }

    Loader {
        id: layout
        anchors.fill: parent
        focus: true
        function fallback() { setSource("styles/Tiles.qml", { theme: theme, session: session, backdrop: backdrop }) }
        Component.onCompleted: {
            if (root.hosted) source = root.astronaut
            else setSource("styles/" + theme.style + ".qml", { theme: theme, session: session, backdrop: backdrop })
        }
        onStatusChanged: if (status === Loader.Error) fallback()
    }
}
