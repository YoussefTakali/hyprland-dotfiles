import QtQuick

// Everything a layout needs to look like the desktop, read from the theme config.
QtObject {
    id: t
    property real u: 1   // 1.0 at 1920x1080

    function cfg(key, fallback) {
        var x = config[key]
        if (x === undefined || x === null) return fallback
        x = String(x)
        return x.length ? x : fallback
    }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function hex(c) { return String(c) }

    readonly property var defaults: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5",
                                     "#bac2de", "#7f849c", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7",
                                     "#94e2d5", "#a6adc8"]
    readonly property var palette: {
        var out = []
        for (var i = 0; i < 16; i++) out.push(cfg("Color" + i, defaults[i]))
        return out
    }
    function c(i) { return palette[i] }

    readonly property string style: cfg("Style", "Tiles")
    readonly property string position: cfg("Position", "")   // left | center | right; each layout has its own default
    readonly property color bg: cfg("ColorBackground", "#1e1e2e")
    readonly property color fg: cfg("ColorForeground", "#cdd6f4")
    readonly property color accent: c(12)    // rofi border, active highlights
    readonly property color accent2: c(13)   // rofi selection, hyprlock date
    readonly property color accent3: c(14)
    readonly property color muted: c(8)

    readonly property string font: cfg("Font", "JetBrainsMono Nerd Font")
    // The greeter ignores font.weight for this family, so thin/light faces are
    // loaded straight from their files; a missing file falls back to `font`.
    readonly property string fontDir: cfg("FontDir", "/usr/local/share/fonts/JetBrainsMonoNerd/JetBrainsMonoNerd")
    property FontLoader thinLoader: FontLoader { source: "file://" + t.fontDir + "/JetBrainsMonoNerdFont-Thin.ttf" }
    property FontLoader lightLoader: FontLoader { source: "file://" + t.fontDir + "/JetBrainsMonoNerdFont-Light.ttf" }
    function face(loader, size) {
        return loader.status === FontLoader.Ready
            ? Qt.font({ family: loader.font.family, styleName: loader.font.styleName, pixelSize: size })
            : Qt.font({ family: font, pixelSize: size })
    }
    function thin(size) { return face(thinLoader, size) }
    function light(size) { return face(lightLoader, size) }
    readonly property real rounding: Number(cfg("Rounding", "12")) * u
    readonly property string background: cfg("Background", "")
    readonly property string placeholder: cfg("BackgroundPlaceholder", "")

    readonly property string host: cfg("InfoHost", sddm.hostName)
    readonly property string os: cfg("InfoOS", "Linux")
    readonly property string kernel: cfg("InfoKernel", "")
    readonly property string wm: cfg("InfoWM", "Hyprland")
    readonly property string shell: cfg("InfoShell", "")
    readonly property string gtk: cfg("InfoGtk", "")
    readonly property string icons: cfg("InfoIcons", "")
    readonly property string terminal: cfg("InfoTerminal", "")

    // Nerd Font glyphs (Font Awesome range, present in every Nerd Font)
    readonly property string iPower: ""
    readonly property string iReboot: ""
    readonly property string iSleep: ""
    readonly property string iUser: ""
    readonly property string iLock: ""
    readonly property string iSession: ""
    readonly property string iKeyboard: ""
    readonly property string iLinux: ""
    readonly property string iSearch: ""
    readonly property string iBell: ""
    readonly property string iPalette: ""
    readonly property string iWarn: ""
}
