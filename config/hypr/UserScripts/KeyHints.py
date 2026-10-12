#!/usr/bin/env python3
"""Cheat sheet (Super+H): live keybinds from `hyprctl binds`, grouped by category, shown in rofi.
Enter runs the selected bind. Binds without a description are skipped (add one with `bindd`)."""
import json
import re
import subprocess
import sys
from html import escape
from pathlib import Path

THEME = Path.home() / ".config/rofi/config-hints.rasi"
COLS = 4


def wal(name, default):
    """A color from rofi's wallust file, so the sheet follows the wallpaper theme."""
    try:
        m = re.search(rf"^\s*{name}:\s*(#[0-9A-Fa-f]{{6}})", (Path.home() / ".config/rofi/wallust/colors-rofi.rasi").read_text(), re.M)
        return m.group(1) if m else default
    except OSError:
        return default


ACCENT = wal("selected-normal-background", "#AF5CE5")
FG = wal("normal-foreground", "#D0D6E8")
MODS = [(64, "Super"), (4, "Ctrl"), (8, "Alt"), (1, "Shift")]
KEYNAMES = {
    "return": "Enter", "space": "Space", "tab": "Tab", "print": "Print", "delete": "Del",
    "left": "←", "right": "→", "up": "↑", "down": "↓", "period": ".", "comma": ",",
    "bracketleft": "[", "bracketright": "]", "mouse_down": "Scroll ↓", "mouse_up": "Scroll ↑",
    "mouse:272": "Left drag", "mouse:273": "Right drag", "shift_l": "Shift", "alt_l": "Alt",
}

# (category, icon, regex on "description | dispatcher arg"); first match wins
RULES = [
    ("Essentials", "󰌌", r"cheat sheet|app launcher|open terminal|close active|terminate active|lock screen|"
                         r"utilities|search keybinds|quick settings|powermenu|exit hyprland|notification panel|refresh bar"),
    ("Apps", "󰀻", r"browser|file manager|dropdown|web search|window switcher|overview|online music"),
    ("Utilities", "󰦬", r"clipboard|emoji|calculator|screenshot|record|color picker|night light|zoom|text grab"),
    ("Music", "󰝚", r"music"),
    ("Workspaces", "󰍹", r"workspace|monitor"),
    ("Layout & groups", "󰕰", r"master|split|pseudo|group"),
    ("Windows", "󰖯", r"fullscreen|maximize|float|opacity|focus|move window|swap window|resize|cycle|bring active"),
    ("Look & theme", "󰏘", r"wallpaper|waybar|rofi|animation|blur|game mode|zsh|keyboard layout"),
]

# Sets of binds that collapse to one row: regex on description -> (label, key text)
COLLAPSE = [
    (r"^workspace \d+$", "switch to workspace", "1 … 0"),
    (r"^move to workspace \d+$", "move window to workspace", "1 … 0"),
    (r"^move silently to workspace \d+$", "move window silently", "1 … 0"),
    (r"^focus (left|right|up|down)$", "focus window", "arrows"),
    (r"^move window (left|right|up|down)$", "move window", "arrows"),
    (r"^swap window (left|right|up|down)$", "swap window", "arrows"),
    (r"^resize (left|right|up|down)", "resize window", "arrows"),
    (r"^move workspace to \w+ monitor$", "move workspace to monitor", "F9 … F12"),
]


def mods_of(mask):
    return [name for bit, name in MODS if mask & bit]


def key_name(b):
    k = b["key"]
    if not k and b.get("keycode"):
        k = {10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0"}.get(b["keycode"], f"code:{b['keycode']}")
    return KEYNAMES.get(k.lower(), k.upper() if len(k) == 1 else k)


def keycaps(parts):
    return " ".join(f"<span background='#ffffff1a' foreground='{FG}'> {escape(p)} </span>" for p in parts)


def main():
    binds = json.loads(subprocess.run(["hyprctl", "binds", "-j"], capture_output=True, text=True, check=True).stdout)
    groups = {c: [] for c, _, _ in RULES}
    seen = set()
    for b in binds:
        desc = b["description"].strip()
        if not desc or b.get("submap"):
            continue
        if not b["modmask"] and b["key"].lower().startswith("xf86"):
            continue  # media / volume / brightness keys are printed on the keyboard
        mods = mods_of(b["modmask"])
        key = key_name(b)
        action = (b["dispatcher"], b["arg"])
        for rx, label, keytext in COLLAPSE:
            if re.search(rx, desc, re.I):
                desc, key, action = label, keytext, None
                break
        sig = (desc.lower(), tuple(mods), key)
        if sig in seen:
            continue
        seen.add(sig)
        cat = next((c for c, _, rx in RULES if re.search(rx, desc, re.I)), None) or \
            next((c for c, _, rx in RULES if re.search(rx, f"{b['dispatcher']} {b['arg']}", re.I)), None)
        if cat is None:
            cat = "Windows" if b["dispatcher"] != "exec" else "Utilities"
        if b["mouse"]:
            action = None
        groups[cat].append((mods + [key], desc, action))

    # Lay sections out in COLS columns of `lines` rows; a section never starts in the last rows of a column.
    sections = [(cat, icon, groups[cat]) for cat, icon, _ in RULES if groups[cat]]
    blank = (" \0nonselectable\x1ftrue", None)
    lines = 20
    while True:
        cells, col_used = [], 0
        for cat, icon, items in sections:
            need = 1 + min(len(items), 3)
            if col_used and col_used + 1 + need > lines:   # move the whole header block to the next column
                cells += [blank] * (lines - col_used); col_used = 0
            elif col_used:
                cells.append(blank); col_used += 1
            cells.append((f"<span size='11pt' foreground='{ACCENT}' weight='bold'>{icon}  {escape(cat.upper())}</span>"
                          "\0nonselectable\x1ftrue", None)); col_used += 1
            for keys, desc, action in items:
                if col_used == lines:
                    col_used = 0
                cells.append((f"{keycaps(keys)}  {escape(desc[0].upper() + desc[1:])}", action)); col_used += 1
        if len(cells) <= COLS * lines or lines > 60:
            break
        lines += 1
    rows = [c[0] for c in cells]
    actions = [c[1] for c in cells]

    res = subprocess.run(
        ["rofi", "-dmenu", "-i", "-markup-rows", "-format", "i", "-no-custom", "-selected-row", "1", "-p", "󰌌",
         "-mesg", "Enter runs the shortcut · Esc closes · Super+Shift+K: search every keybind",
         "-theme", str(THEME), "-theme-str", f"listview {{ lines: {lines}; }}"],
        input="\n".join(rows), capture_output=True, text=True)
    if res.returncode != 0 or not res.stdout.strip():
        return
    action = actions[int(res.stdout.strip())]
    if action:
        subprocess.Popen(["hyprctl", "dispatch", action[0], action[1]], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    sys.exit(main())
