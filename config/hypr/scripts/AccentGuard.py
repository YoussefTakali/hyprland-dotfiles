#!/usr/bin/env python3
"""Accent guard — run after every `wallust run` (WallustSwww.sh, WallpaperEffects.sh).

1. Makes the wallpaper's accent colours ($color12, $color13, $color14) readable on the dark UI: if one is too dark
   (contrast < 4.5:1 against #11111b), it is lightened in place in every wallust output, so the bar, lock screen,
   menus, notifications and window borders all get the readable version.
2. Writes the accent for the apps wallust doesn't theme:
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


if __name__ == "__main__":
    main()
