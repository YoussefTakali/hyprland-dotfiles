import QtQuick

// Login state shared by every layout: user, session, clock, failures, power.
Item {
    id: s
    visible: false

    property int userIndex: Math.max(0, userModel.lastIndex)
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)
    property bool busy: false
    property bool failed: false
    property int failures: 0
    property date now: new Date()

    Repeater {
        id: users
        model: userModel
        delegate: Item { property string uname: model.name; property string rname: model.realName || "" }
    }
    Repeater {
        id: sessions
        model: sessionModel
        delegate: Item { property string sname: model.name }
    }

    readonly property int userCount: users.count
    readonly property int sessionCount: sessions.count
    readonly property string userName: (users.count, users.itemAt(userIndex) ? users.itemAt(userIndex).uname : (userModel.lastUser || ""))
    readonly property string realName: (users.count, users.itemAt(userIndex) && users.itemAt(userIndex).rname ? users.itemAt(userIndex).rname : userName)
    readonly property string displayName: realName.length ? realName.charAt(0).toUpperCase() + realName.slice(1) : ""
    readonly property string initial: displayName.length ? displayName.charAt(0) : "?"
    readonly property string sessionName: (sessions.count, sessions.itemAt(sessionIndex) ? sessions.itemAt(sessionIndex).sname : "")
    function sessionNameAt(i) { return sessions.itemAt(i) ? sessions.itemAt(i).sname : "" }
    function userNameAt(i) { return users.itemAt(i) ? users.itemAt(i).uname : "" }

    readonly property string greeting: {
        var h = now.getHours()
        return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }
    readonly property bool capsLock: keyboard.capsLock
    readonly property string layout: {
        try { return keyboard.layouts[keyboard.currentLayout].shortName } catch (e) { return "" }
    }

    function login(password) {
        if (busy) return
        failed = false
        busy = true
        sddm.login(userName, password, sessionIndex)
    }
    function cycleSession(step) { if (sessions.count) sessionIndex = (sessionIndex + step + sessions.count) % sessions.count }
    function cycleUser(step) { if (users.count) userIndex = (userIndex + step + users.count) % users.count }
    function can(action) {
        return action === "suspend" ? sddm.canSuspend : action === "reboot" ? sddm.canReboot : sddm.canPowerOff
    }
    function power(action) {
        if (!can(action)) return
        if (action === "suspend") sddm.suspend()
        else if (action === "reboot") sddm.reboot()
        else sddm.powerOff()
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: s.now = new Date() }
    Connections {
        target: sddm
        function onLoginFailed() { s.busy = false; s.failed = true; s.failures++ }
        function onLoginSucceeded() { s.busy = false }
    }
}
