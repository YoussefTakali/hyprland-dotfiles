// Lock screen (Quickshell) — replaces hyprlock. The page itself comes from a style file (Lock<Style>.qml).
// Run:      qs -c lockscreen                      (locks the session; started by ~/.config/hypr/scripts/QsLock.sh)
// Preview:  QS_LOCK_PREVIEW=8 qs -c lockscreen     (shows the page as an overlay for 8 s, never locks/authenticates)
//           test hooks: QS_LOCK_PREVIEW_TEXT=abc (pre-typed), QS_LOCK_PREVIEW_FAIL=N, QS_LOCK_PREVIEW_UNLOCK=N (seconds)
//
// Security: the session is locked through ext-session-lock (WlSessionLock). If this process dies while locked,
// Hyprland keeps the screen locked; QsLock.sh then falls back to hyprlock. Unlock happens only on PAM success.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam

ShellRoot {
    id: root
    // Never hot-reload while locked: a reload destroys the active lock (QsLock.sh also runs a frozen copy)
    settings.watchFiles: false

    // ── Style: Lock<Name>.qml, chosen in ./style (LockStyle.sh writes it), QS_LOCK_STYLE overrides ──
    readonly property var styles: ["Slate", "Iris", "Fog", "Cards"]
    FileView { id: styleFile; path: Quickshell.shellDir + "/style"; blockLoading: true; printErrors: false }
    readonly property string style: {
        const want = (Quickshell.env("QS_LOCK_STYLE") || styleFile.text() || "").trim();
        return styles.indexOf(want) >= 0 ? want : styles[0];
    }
    component StylePage: Loader {
        Component.onCompleted: setSource("Lock" + root.style + ".qml", { shell: root })
        // a broken style must never leave an empty lock: fall back to the default one
        onStatusChanged: {
            if (status !== Loader.Error) return;
            if (source.toString().indexOf("Lock" + root.styles[0]) < 0) setSource("Lock" + root.styles[0] + ".qml", { shell: root });
            else sourceComponent = plainPage;      // even the default failed: plain password page, never a dead lock
        }
    }
    Component {
        id: plainPage
        Rectangle {
            color: "#11111b"
            Column {
                anchors.centerIn: parent
                spacing: 16
                Text { anchors.horizontalCenter: parent.horizontalCenter; color: "white"; font.pixelSize: 22
                       text: root.failText !== "" ? root.failText : "Type your password and press Enter" }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 320; height: 48; radius: 24; color: "#313244"
                    TextInput {
                        id: plainInput
                        anchors.fill: parent; anchors.margins: 12
                        horizontalAlignment: TextInput.AlignHCenter
                        echoMode: TextInput.Password; color: "white"; font.pixelSize: 18
                        focus: true
                        onAccepted: { root.tryUnlock(text); text = ""; }
                    }
                }
            }
            Timer { interval: 300; running: true; repeat: true; onTriggered: if (!plainInput.activeFocus) plainInput.forceActiveFocus() }
        }
    }

    readonly property int previewSeconds: parseInt(Quickshell.env("QS_LOCK_PREVIEW") || "0")
    readonly property bool preview: previewSeconds > 0

    // ── Authentication ────────────────────────────────
    property string pendingPassword: ""
    property bool busy: false
    property int attempts: 0
    property string failText: ""
    property bool unlocking: false        // success animation running (LockView), then the session unlocks
    signal failed()

    function tryUnlock(password) {
        if (busy || unlocking || password.length === 0) return;
        if (preview) { unlocking = true; return; }   // preview: just play the success animation
        pendingPassword = password;
        busy = true;
        failText = "";
        pam.start();
    }

    PamContext {
        id: pam
        config: "hyprlock"                 // /etc/pam.d/hyprlock → includes "login"
        configDirectory: "/etc/pam.d"
        onResponseRequiredChanged: {
            if (responseRequired) {
                respond(root.pendingPassword);
                root.pendingPassword = "";
            }
        }
        onCompleted: result => {
            root.pendingPassword = "";
            root.busy = false;
            if (result === PamResult.Success) {
                root.unlocking = true;
                unlockTimer.start();
            } else {
                root.attempts += 1;
                root.failText = root.attempts > 1 ? "Wrong password, try again (" + root.attempts + " attempts)" : "Wrong password, try again";
                root.failed();
            }
        }
        onError: error => {
            root.pendingPassword = "";
            root.busy = false;
            root.failText = "Couldn't check the password. Try again.";
            root.failed();
        }
    }

    Timer {
        id: unlockTimer
        interval: 180                       // brief transition after PAM succeeds
        onTriggered: { lock.locked = false; Qt.callLater(Qt.quit); }
    }

    // ── Real lock ─────────────────────────────────────
    WlSessionLock {
        id: lock
        locked: !root.preview
        // Tell QsLock.sh the compositor confirmed the lock (it falls back to hyprlock if this never happens)
        onSecureChanged: if (secure) secureMarker.running = true

        WlSessionLockSurface {
            color: "black"
            StylePage { anchors.fill: parent }
        }
    }

    Process {
        id: secureMarker
        command: ["sh", "-c", "touch \"${XDG_RUNTIME_DIR:-/tmp}/qslock.secure\""]
    }
    // Never sit around unlocked: if the compositor hasn't confirmed the lock in 3 s, exit with an error
    Timer {
        interval: 3000; running: !root.preview
        onTriggered: if (!lock.secure) Qt.exit(1)
    }

    // ── Preview (overlay, no input grab, closes itself) ─
    Loader {
        active: root.preview
        sourceComponent: PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-lock-preview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "black"
            StylePage { anchors.fill: parent }
            Timer { interval: root.previewSeconds * 1000; running: true; onTriggered: Qt.quit() }
            // QS_LOCK_PREVIEW_UNLOCK=N plays the success animation after N s (for testing)
            Timer {
                interval: parseInt(Quickshell.env("QS_LOCK_PREVIEW_UNLOCK") || "0") * 1000
                running: interval > 0
                onTriggered: root.unlocking = true
            }
            // QS_LOCK_PREVIEW_FAIL=N plays the wrong-password animation after N s (for testing)
            Timer {
                interval: parseInt(Quickshell.env("QS_LOCK_PREVIEW_FAIL") || "0") * 1000
                running: interval > 0
                onTriggered: { root.attempts += 1; root.failText = "Wrong password, try again"; root.failed(); }
            }
        }
    }
}
