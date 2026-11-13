import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    settings.watchFiles: false
    property bool leaving: false
    property bool desktopReady: false
    property bool exporting: !!Quickshell.env("JAKE_SPLASH_EXPORT")
    property bool firstFrame: false
    function finish() { if (desktopReady && firstFrame && !exporting) { console.info("Jake splash fade", Date.now()); leaving = true; } }
    // A missing bar or failed wallpaper must never trap the user behind a splash.
    Timer { interval: 7000; running: true; onTriggered: root.leaving = true }
    Timer { interval: 200; running: root.leaving; onTriggered: Qt.quit() }
    Process {
        running: true
        command: ["bash", "-c", 'for ((i=0;i<60;i++)); do if [[ -f "$JAKE_SPLASH_READY" ]] && pgrep -u "$UID" -x waybar >/dev/null; then exit 0; fi; sleep .1; done; exit 1']
        onExited: { root.desktopReady = true; root.finish(); }
    }
    Process {
        running: root.firstFrame && !!Quickshell.env("JAKE_SPLASH_MAPPED")
        command: ["touch", Quickshell.env("JAKE_SPLASH_MAPPED")]
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "jake-login-splash"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            color: "transparent"
            onBackingWindowVisibleChanged: console.info("Jake surface visible", screen.name, backingWindowVisible, Date.now())
            FrameAnimation {
                running: panel.backingWindowVisible && !root.firstFrame
                onTriggered: {
                    root.firstFrame = true;
                    console.info("Jake first render tick", Date.now());
                    if (root.exporting) exportFrame.start();
                    else root.finish();
                }
            }
            Timer {
                id: exportFrame
                interval: 150
                onTriggered: scene.grabToImage(function(result) {
                    const saved = result.saveToFile(Quickshell.env("JAKE_SPLASH_EXPORT"));
                    console.info("Jake shared frame exported", saved);
                    Qt.quit();
                }, Qt.size(panel.width * panel.devicePixelRatio, panel.height * panel.devicePixelRatio))
            }
            Item {
                anchors.fill: parent
                opacity: root.leaving ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                JakeLoadingScene {
                    id: scene
                    anchors.fill: parent
                    animated: !root.exporting
                }
            }
        }
    }
}
