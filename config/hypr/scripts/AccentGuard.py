#!/usr/bin/env python3
"""Accent guard — run after every `wallust run` (WallustSwww.sh, WallpaperEffects.sh).

1. Makes the wallpaper's accent colours ($color12, $color13, $color14) readable on the dark UI: if one is too dark
   (contrast < 4.5:1 against #11111b), it is lightened in place in every wallust output, so the bar, lock screen,
   menus, notifications and window borders all get the readable version.
2. Writes ~/.config/waybar/wallust/readable.css (colours 7-15, each made readable) for the adaptive Waybar style.
3. Writes the accent for the apps wallust doesn't theme:
   ~/.config/gtk-theme/accent-gtk3.css, ~/.config/gtk-theme/accent.css (GTK4/libadwaita), ~/.config/kitty/accent.conf
   and tells running kitty windows to reload.
Added 2026-10-28; undo with ~/.config/hypr/backup-desktop-2026-10-28/restore.sh
"""
import colorsys
import re
import subprocess
from pathlib import Path

HOME = Path.home()
C = HOME / ".config"
HYPR = C / "hypr/wallust/wallust-hyprland.conf"
OUTPUTS = [
    HYPR,
    C / "waybar/wallust/colors-waybar.css",
    C / "rofi/wallust/colors-rofi.rasi",
    C / "kitty/kitty-themes/01-Wallust.conf",
    C / "quickshell/qml_color.json",
    C / "cava/config",
]
BG = (0x11, 0x11, 0x1B)
MIN_CONTRAST = 4.5


def lum(rgb):
    def ch(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def to_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    return "".join(f"{round(c):02X}" for c in rgb)


def readable(hexcol):
    rgb = to_rgb(hexcol)
    if contrast(rgb, BG) >= MIN_CONTRAST:
        return hexcol
    h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in rgb))
    s = max(s, 0.35) if s > 0.08 else s          # keep greys grey, give weak colours some life
    while l < 0.92:
        l += 0.02
        cand = tuple(c * 255 for c in colorsys.hls_to_rgb(h, l, s))
        if contrast(cand, BG) >= MIN_CONTRAST:
            return to_hex(cand)
    return to_hex(tuple(c * 255 for c in colorsys.hls_to_rgb(h, 0.92, s)))


def main():
    text = HYPR.read_text()
    cols = {}
    for n in (12, 13, 14):
        m = re.search(rf"^\$color{n} = rgb\((\w{{6}})\)", text, re.M)
        if m:
            cols[n] = m.group(1).upper()
    if 13 not in cols:
        return

    fixed = {n: readable(h) for n, h in cols.items()}
    for n, old in cols.items():
        new = fixed[n]
        if new == old:
            continue
        pat = re.compile(rf"(?i)(?<![0-9a-f]){old}(?![0-9a-f])")
        for f in OUTPUTS:
            if f.exists():
                t = f.read_text()
                f.write_text(pat.sub(lambda m: new if m.group(0).isupper() else new.lower(), t))
        print(f"color{n}: {old} -> {new} (was too dark)")

    # readable copy of the whole bright half of the palette, for the multi-colour Waybar style
    pal = {}
    for n in range(7, 16):
        m = re.search(rf"^\$color{n} = rgb\((\w{{6}})\)", HYPR.read_text(), re.M)
        if m:
            pal[n] = readable(m.group(1).upper())
    (C / "waybar/wallust/readable.css").write_text(
        "/* written by AccentGuard.py: wallust colours 7-15 lightened until readable on the dark bar — do not edit */\n"
        + "".join(f"@define-color r{n} #{h};\n" for n, h in pal.items()))

    a = "#" + fixed[13]
    r, g, b = to_rgb(fixed[13])
    (C / "gtk-theme").mkdir(parents=True, exist_ok=True)
    (C / "gtk-theme/accent-gtk3.css").write_text(
        "/* written by AccentGuard.py from the wallpaper — do not edit */\n"
        f"@define-color c_accent  {a};\n"
        f"@define-color c_hover   rgba({r}, {g}, {b}, 0.14);\n"
        f"@define-color c_sel     rgba({r}, {g}, {b}, 0.30);\n")
    (C / "gtk-theme/accent.css").write_text(
        "/* written by AccentGuard.py from the wallpaper — do not edit */\n"
        f":root {{ --accent-color: {a}; --accent-bg-color: {a}; --accent-fg-color: #11111b; }}\n"
        f"@define-color accent_color {a};\n@define-color accent_bg_color {a};\n@define-color accent_fg_color #11111b;\n")
    (C / "kitty/accent.conf").write_text(
        "# written by AccentGuard.py from the wallpaper — do not edit\n"
        f"cursor {a}\nselection_background {a}\nselection_foreground #11111b\n"
        f"active_tab_background {a}\nactive_tab_foreground #11111b\nactive_border_color {a}\nurl_color {a}\n")
    subprocess.run(["pkill", "-SIGUSR1", "-x", "kitty"], check=False)

    # recolor Adwaita folder icons to match the accent
    recolor_folder_icons(fixed[13])


# ── Folder icon recoloring ────────────────────────────────────────────────────

ADWAITA_PLACES = Path("/usr/share/icons/Adwaita/scalable/places")
# Adwaita's blue palette → we shift hue+saturation to the accent, preserving lightness ratios
BLUES = {
    "438de6": 0,    # darkest (back face)
    "62a0ea": 1,    # mid (gradient stops)
    "a4caee": 2,    # light (front face)
    "afd4ff": 3,    # lighter (gradient highlight)
    "c0d5ea": 4,    # lightest (gradient edge)
}


def hsl_shift(hex_src, target_h, target_s):
    """Shift hue and saturation of hex_src to target, keeping lightness."""
    r, g, b = to_rgb(hex_src)
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    nr, ng, nb = colorsys.hls_to_rgb(target_h, l, min(target_s * (0.5 + l * 0.7), 1.0))
    return to_hex((nr * 255, ng * 255, nb * 255))


def recolor_folder_icons(accent_hex):
    accent_rgb = to_rgb(accent_hex)
    ah, al, a_s = colorsys.rgb_to_hls(*(c / 255 for c in accent_rgb))

    replacements = {}
    for blue_hex in BLUES:
        new_hex = hsl_shift(blue_hex, ah, a_s)
        replacements[blue_hex] = new_hex

    theme_dir = HOME / ".local/share/icons/Accent-Folders"
    places_dir = theme_dir / "scalable/places"
    places_dir.mkdir(parents=True, exist_ok=True)

    (theme_dir / "index.theme").write_text(
        "[Icon Theme]\nName=Accent Folders\nComment=Adwaita with accent-colored folders\n"
        "Inherits=Adwaita\nDirectories=scalable/places\n\n"
        "[scalable/places]\nSize=128\nMinSize=8\nMaxSize=512\nType=Scalable\nContext=Places\n")

    if not ADWAITA_PLACES.is_dir():
        return

    icons = list(ADWAITA_PLACES.glob("folder*.svg")) + [ADWAITA_PLACES / f"user-{n}.svg" for n in ("desktop", "home", "bookmarks")]
    for svg_path in (p for p in icons if p.exists()):
        svg = svg_path.read_text()
        for old, new in replacements.items():
            svg = re.sub(rf"(?i)#{old}", lambda m: "#" + (new if m.group(0)[1:].isupper() else new.lower()), svg)
        (places_dir / svg_path.name).write_text(svg)

    # set the icon theme: gsettings for apps that read it through the settings portal, settings.ini for
    # GTK apps started where that portal doesn't answer (seen on a fresh install: Nautilus fell back to Adwaita)
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "Accent-Folders"], check=False)
    for gtk in ("gtk-3.0", "gtk-4.0"):
        ini = C / gtk / "settings.ini"
        lines = ini.read_text().splitlines() if ini.exists() else []
        if "[Settings]" not in (l.strip() for l in lines):
            lines.insert(0, "[Settings]")
        lines = [l for l in lines if not l.strip().startswith("gtk-icon-theme-name")]
        lines.insert([l.strip() for l in lines].index("[Settings]") + 1, "gtk-icon-theme-name=Accent-Folders")
        ini.parent.mkdir(parents=True, exist_ok=True)
        ini.write_text("\n".join(lines) + "\n")
    # clear icon cache so running apps pick up the new icons
    subprocess.run(["gtk-update-icon-cache", "-f", "-t", str(theme_dir)], check=False, capture_output=True)


if __name__ == "__main__":
    main()
