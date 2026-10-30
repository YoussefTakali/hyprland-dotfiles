#!/usr/bin/env python3
"""Keyboard Shortcuts — add, change and remove Hyprland shortcuts without editing config files.

Your shortcuts are kept in ~/.config/hypr/UserConfigs/shortcuts.json and written to CustomShortcuts.conf
(sourced from UserKeybinds.conf); Hyprland reloads after every change. The "All shortcuts" tab lists every
shortcut that is active right now (from `hyprctl binds`), so you can see what is already taken.
"""
import json
import os
import shlex
import subprocess
import sys
import uuid
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

APP_ID = "io.github.YoussefTakali.Shortcuts"
HOME = Path.home()
HYPR = HOME / ".config/hypr"
STORE = HYPR / "UserConfigs/shortcuts.json"
CONF = HYPR / "UserConfigs/CustomShortcuts.conf"
USER_KEYBINDS = HYPR / "UserConfigs/UserKeybinds.conf"
SOURCE_LINE = "source = $UserConfigs/CustomShortcuts.conf"

S = "$HOME/.config/hypr/scripts"
U = "$HOME/.config/hypr/UserScripts"

# What a shortcut can do without typing a command: (label, dispatcher, argument, asks for a workspace number)
BUILTINS = [
    ("Lock the screen", "exec", f"{S}/LockScreen.sh", False),
    ("Power menu", "exec", f"{S}/Wlogout.sh", False),
    ("Screenshot of an area", "exec", f"{S}/ScreenShot.sh --area", False),
    ("Screenshot of the whole screen", "exec", f"{S}/ScreenShot.sh --now", False),
    ("Start or stop screen recording", "exec", f"{U}/ScreenRecord.sh --toggle", False),
    ("Utilities menu", "exec", f"{U}/UtilityHub.sh", False),
    ("Clipboard history", "exec", f"{S}/ClipManager.sh", False),
    ("Color picker", "exec", f"{U}/ColorPicker.sh", False),
    ("Notification center", "exec", "swaync-client -t -sw", False),
    ("Night light on / off", "exec", f"{S}/Hyprsunset.sh toggle", False),
    ("Play / pause music", "exec", "playerctl play-pause", False),
    ("Next track", "exec", "playerctl next", False),
    ("Previous track", "exec", "playerctl previous", False),
    ("Volume up", "exec", f"{S}/Volume.sh --inc", False),
    ("Volume down", "exec", f"{S}/Volume.sh --dec", False),
    ("Mute / unmute", "exec", f"{S}/Volume.sh --toggle", False),
    ("Close the window", "killactive", "", False),
    ("Float / tile the window", "togglefloating", "", False),
    ("Full screen", "fullscreen", "0", False),
    ("Go to workspace…", "workspace", "", True),
    ("Move the window to workspace…", "movetoworkspace", "", True),
]

KINDS = ["Open an app", "Open a website", "Open a folder", "Built-in action", "Run a command"]

MODS = [("SUPER", Gdk.ModifierType.SUPER_MASK, 64, "Super"),
        ("CTRL", Gdk.ModifierType.CONTROL_MASK, 4, "Ctrl"),
        ("ALT", Gdk.ModifierType.ALT_MASK, 8, "Alt"),
        ("SHIFT", Gdk.ModifierType.SHIFT_MASK, 1, "Shift")]
MOD_BITS = {name: bit for name, _, bit, _ in MODS}
MODIFIER_KEYS = {"Super_L", "Super_R", "Control_L", "Control_R", "Alt_L", "Alt_R", "Shift_L", "Shift_R",
                 "Meta_L", "Meta_R", "ISO_Level3_Shift", "Hyper_L", "Hyper_R", "Caps_Lock"}
# keys kept by name in the config (others are stored by keycode, which works on every layout)
NAMED_KEYS = {"Return", "space", "Tab", "BackSpace", "Delete", "Insert", "Home", "End", "Page_Up", "Page_Down",
              "Left", "Right", "Up", "Down", "Print", "Escape", "Pause", "Menu"}
PRETTY = {"Return": "Enter", "space": "Space", "BackSpace": "Backspace", "Page_Up": "Page Up",
          "Page_Down": "Page Down", "Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Print": "Print",
          "Escape": "Esc", "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
          "mouse_down": "Scroll down", "mouse_up": "Scroll up"}


# ── helpers ───────────────────────────────────────────────────────────────────
def hyprctl_binds():
    try:
        out = subprocess.run(["hyprctl", "binds", "-j"], capture_output=True, text=True, timeout=3).stdout
        return json.loads(out)
    except Exception:
        return []


def keycode_label(code):
    """What is printed on the key with this keycode, on the current layout ('1', 'A', '&' …)."""
    disp = Gdk.Display.get_default()
    ok, _keys, keyvals = disp.map_keycode(code)
    if not ok or not keyvals:
        return f"key {code}"
    chars = [chr(Gdk.keyval_to_unicode(k)) for k in keyvals[:2] if Gdk.keyval_to_unicode(k)]
    for c in chars:                               # AZERTY number row: show the digit, not '&'
        if c.isdigit():
            return c
    if chars and chars[0].strip():
        return chars[0].upper()
    return Gdk.keyval_name(keyvals[0]) or f"key {code}"


def key_label(key):
    if key in PRETTY:
        return PRETTY[key]
    if key.startswith("code:"):
        try:
            return keycode_label(int(key[5:]))
        except ValueError:
            return key
    if len(key) == 1:
        return key.upper()
    return key.replace("XF86", "").replace("_", " ")


def normalize(keyval, keycode, state):
    """A pressed key → (Hyprland modifier names, Hyprland key). Letters, F-keys and named keys keep their name;
    everything else is stored by keycode, so it means the same physical key on any layout (AZERTY digits…)."""
    mods = [n for n, mask, _, _ in MODS if state & mask]
    name = Gdk.keyval_name(Gdk.keyval_to_lower(keyval)) or ""          # the letter as typed on this layout
    if len(name) == 1 and name.isalpha():
        return mods, name.upper()
    if name in NAMED_KEYS or (name.startswith("F") and name[1:].isdigit()) or name.startswith("XF86"):
        return mods, name
    return mods, f"code:{keycode}"


def mods_from_mask(mask):
    return [name for name, _, bit, _ in MODS if mask & bit]


def combo_text(mods, key):
    names = {n: p for n, _, _, p in MODS}
    return [names[m] for m in mods] + [key_label(key)]


def sanitize(text):
    """Hyprland splits binds on commas and treats # as a comment."""
    return " ".join(text.replace(",", " ").split()).replace("#", "##")


def load_store():
    try:
        return json.loads(STORE.read_text())
    except Exception:
        return []


def build_conf(entries):
    lines = ["# Written by Keyboard Shortcuts (UserScripts/Shortcuts.py) from shortcuts.json.",
             "# Change these in the app (Super+X → Keyboard shortcuts); edits here are overwritten.", ""]
    for e in entries:
        mods = " ".join(e["mods"])
        if e.get("replace"):
            lines.append(f"unbind = {mods}, {e['key']}")
        arg = e["arg"].replace("#", "##")
        lines.append(f"bindd = {mods}, {e['key']}, {sanitize(e['name'])}, {e['dispatcher']}, {arg}".rstrip(", "))
    return "\n".join(lines) + "\n"


def ensure_sourced():
    CONF.parent.mkdir(parents=True, exist_ok=True)
    if not CONF.exists():
        CONF.write_text(build_conf([]))
    if USER_KEYBINDS.exists() and SOURCE_LINE not in USER_KEYBINDS.read_text():
        with USER_KEYBINDS.open("a") as f:
            f.write("\n# Shortcuts added with the Keyboard Shortcuts app\n" + SOURCE_LINE + "\n")


def apply(entries):
    """Write the config, reload Hyprland; on a config error put the old file back. Returns an error or None."""
    old = CONF.read_text() if CONF.exists() else ""
    CONF.write_text(build_conf(entries))
    subprocess.run(["hyprctl", "reload"], capture_output=True)
    errors = subprocess.run(["hyprctl", "configerrors"], capture_output=True, text=True).stdout
    if "CustomShortcuts" in errors:
        CONF.write_text(old)
        subprocess.run(["hyprctl", "reload"], capture_output=True)
        return errors.strip()
    STORE.write_text(json.dumps(entries, indent=2))
    return None


def describe(e):
    k = e.get("kind")
    v = e.get("value", "")
    if k == "Open an app":
        return f"Opens {e.get('app_name', v)}"
    if k == "Open a website":
        return f"Opens {v}"
    if k == "Open a folder":
        return f"Opens {v.replace(str(HOME), '~')}"
    if k == "Built-in action":
        return e["name"] if not e.get("number") else f"{v.rstrip('…')} {e['number']}"
    return f"Runs {v}"


# ── key chips ─────────────────────────────────────────────────────────────────
def keycaps(parts):
    box = Gtk.Box(spacing=4, valign=Gtk.Align.CENTER)
    for i, p in enumerate(parts):
        if i:
            box.append(Gtk.Label(label="+", css_classes=["dim-label"]))
        box.append(Gtk.Label(label=p, css_classes=["keycap"]))
    return box


CSS = b"""
.keycap { padding: 2px 9px; border-radius: 7px; background: alpha(currentColor, 0.10);
          border: 1px solid alpha(currentColor, 0.18); font-weight: bold; font-size: 0.92em; min-width: 14px; }
.capture { padding: 18px; border-radius: 14px; border: 2px dashed alpha(currentColor, 0.25); }
.capture.listening { border-color: @accent_color; background: alpha(@accent_color, 0.10); }
.conflict { color: @warning_color; }
/* the desktop's GTK theme is translucent for blur; the dialog needs a solid sheet to stay readable */
.solid-sheet { background-color: #181825; }
"""


# ── the add / edit dialog ─────────────────────────────────────────────────────
class EditDialog(Adw.Dialog):
    def __init__(self, win, entry=None):
        super().__init__(title="Edit shortcut" if entry else "New shortcut", content_width=520)
        self.win, self.entry = win, entry
        self.mods, self.key = (list(entry["mods"]), entry["key"]) if entry else ([], None)
        self.listening = False
        self.apps = sorted((a for a in Gio.AppInfo.get_all() if a.should_show()), key=lambda a: a.get_display_name().lower())

        tv = Adw.ToolbarView(css_classes=["solid-sheet"])
        header = Adw.HeaderBar(show_end_title_buttons=False, show_start_title_buttons=False)
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda *_: self.close())
        self.save_btn = Gtk.Button(label="Save", css_classes=["suggested-action"])
        self.save_btn.connect("clicked", self.on_save)
        header.pack_start(cancel)
        header.pack_end(self.save_btn)
        tv.add_top_bar(header)

        page = Adw.PreferencesPage()
        # 1. the keys
        g1 = Adw.PreferencesGroup(title="Keys", description="Click the box, then press the keys together, for example Super + G.")
        self.capture = Gtk.Button(css_classes=["capture", "flat"])
        self.capture.connect("clicked", self.start_listening)
        g1.add(self.capture)
        self.conflict = Gtk.Label(wrap=True, xalign=0, css_classes=["conflict"], margin_top=8, visible=False)
        g1.add(self.conflict)
        page.add(g1)
        g1b = Adw.PreferencesGroup()            # its own group: libadwaita puts rows above other widgets
        self.replace_row = Adw.SwitchRow(title="Replace the existing shortcut",
                                         subtitle="The old action stops working with these keys", visible=False)
        self.replace_row.connect("notify::active", lambda *_: self.validate())
        g1b.add(self.replace_row)
        page.add(g1b)

        # 2. the action
        g2 = Adw.PreferencesGroup(title="What it does")
        self.kind_row = Adw.ComboRow(title="Action", model=Gtk.StringList.new(KINDS))
        self.kind_row.connect("notify::selected", lambda *_: self.on_kind())
        g2.add(self.kind_row)
        self.app_row = Adw.ComboRow(title="App", enable_search=True,
                                    model=Gtk.StringList.new([a.get_display_name() for a in self.apps]))
        self.app_row.set_expression(Gtk.PropertyExpression.new(Gtk.StringObject, None, "string"))
        ids = [a.get_id() for a in self.apps]
        for preferred in ("firefox.desktop", "org.mozilla.firefox.desktop", "kitty.desktop"):
            if preferred in ids:
                self.app_row.set_selected(ids.index(preferred))
                break
        self.app_row.connect("notify::selected", lambda *_: self.autoname())
        g2.add(self.app_row)
        self.url_row = Adw.EntryRow(title="Website address")
        self.url_row.connect("changed", lambda *_: (self.autoname(), self.validate()))
        g2.add(self.url_row)
        self.folder_row = Adw.ActionRow(title="Folder", subtitle="Choose a folder", activatable=True)
        self.folder_row.add_suffix(Gtk.Image(icon_name="folder-open-symbolic"))
        self.folder_row.connect("activated", self.pick_folder)
        self.folder = None
        g2.add(self.folder_row)
        self.builtin_row = Adw.ComboRow(title="Action", model=Gtk.StringList.new([b[0] for b in BUILTINS]))
        self.builtin_row.connect("notify::selected", lambda *_: (self.on_builtin(), self.autoname()))
        g2.add(self.builtin_row)
        self.number_row = Adw.SpinRow.new_with_range(1, 10, 1)
        self.number_row.set_title("Workspace number")
        self.number_row.connect("notify::value", lambda *_: self.autoname())
        g2.add(self.number_row)
        self.cmd_row = Adw.EntryRow(title="Command")
        self.cmd_row.connect("changed", lambda *_: (self.autoname(), self.validate()))
        g2.add(self.cmd_row)
        page.add(g2)

        # 3. the name shown in the cheat sheet
        g3 = Adw.PreferencesGroup(title="Name", description="Shown in the shortcut list and the Super+H cheat sheet.")
        self.name_row = Adw.EntryRow(title="Name")
        self.name_row.connect("changed", lambda *_: self.on_name_typed())
        self.name_auto = True
        g3.add(self.name_row)
        page.add(g3)

        tv.set_content(page)
        self.set_child(tv)

        keys = Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self.on_key)
        self.add_controller(keys)

        if entry:
            self.load(entry)
        self.on_kind()
        self.show_keys()

    # ── state ──
    def load(self, e):
        self.kind_row.set_selected(KINDS.index(e["kind"]))
        v = e.get("value", "")
        if e["kind"] == "Open an app":
            ids = [a.get_id() for a in self.apps]
            if v in ids:
                self.app_row.set_selected(ids.index(v))
        elif e["kind"] == "Open a website":
            self.url_row.set_text(v)
        elif e["kind"] == "Open a folder":
            self.folder = v
            self.folder_row.set_subtitle(v.replace(str(HOME), "~"))
        elif e["kind"] == "Built-in action":
            names = [b[0] for b in BUILTINS]
            if v in names:
                self.builtin_row.set_selected(names.index(v))
            if e.get("number"):
                self.number_row.set_value(e["number"])
        else:
            self.cmd_row.set_text(v)
        self.replace_row.set_active(bool(e.get("replace")))
        self.name_auto = False
        self.name_row.set_text(e["name"])

    def kind(self):
        return KINDS[self.kind_row.get_selected()]

    def on_kind(self):
        k = self.kind()
        self.app_row.set_visible(k == "Open an app")
        self.url_row.set_visible(k == "Open a website")
        self.folder_row.set_visible(k == "Open a folder")
        self.builtin_row.set_visible(k == "Built-in action")
        self.cmd_row.set_visible(k == "Run a command")
        self.on_builtin()
        self.autoname()

    def on_builtin(self):
        b = BUILTINS[self.builtin_row.get_selected()]
        self.number_row.set_visible(self.kind() == "Built-in action" and b[3])

    def on_name_typed(self):
        if not getattr(self, "_setting_name", False):
            self.name_auto = False
        self.validate()

    def autoname(self):
        if not self.name_auto:
            return
        k, name = self.kind(), ""
        if k == "Open an app" and self.apps:
            name = "Open " + self.apps[self.app_row.get_selected()].get_display_name()
        elif k == "Open a website" and self.url_row.get_text().strip():
            name = "Open " + self.url_row.get_text().strip().split("//")[-1].split("/")[0]
        elif k == "Open a folder" and self.folder:
            name = "Open " + Path(self.folder).name
        elif k == "Built-in action":
            b = BUILTINS[self.builtin_row.get_selected()]
            name = b[0].rstrip("…") + (f" {int(self.number_row.get_value())}" if b[3] else "")
        elif k == "Run a command" and self.cmd_row.get_text().strip():
            name = "Run " + self.cmd_row.get_text().strip().split()[0].split("/")[-1]
        self._setting_name = True
        self.name_row.set_text(name)
        self._setting_name = False
        self.validate()

    # ── keys ──
    def start_listening(self, *_):
        self.listening = True
        self.capture.add_css_class("listening")
        self.capture.set_child(Gtk.Label(label="Press the keys now…  (Esc to cancel)", css_classes=["title-4"]))
        self.grab_focus()

    def show_keys(self):
        self.capture.remove_css_class("listening")
        if self.key:
            self.capture.set_child(keycaps(combo_text(self.mods, self.key)))
        else:
            self.capture.set_child(Gtk.Label(label="Click here to choose the keys", css_classes=["dim-label", "title-4"]))
        self.check_conflict()
        self.validate()

    def on_key(self, _ctl, keyval, keycode, state):
        if not self.listening:
            return False
        name = Gdk.keyval_name(keyval) or ""
        if name in MODIFIER_KEYS:
            return True                                  # wait for the real key
        if name == "Escape" and not (state & Gdk.ModifierType.MODIFIER_MASK & ~Gdk.ModifierType.LOCK_MASK):
            self.listening = False
            self.show_keys()
            return True
        mods, key = normalize(keyval, keycode, state)
        if not mods and not (key.startswith("F") and key[1:].isdigit() or key.startswith("XF86") or key == "Print"):
            self.conflict.set_label("Add Super, Ctrl or Alt, so the keys don't get in the way of typing.")
            self.conflict.set_visible(True)
            return True
        self.mods, self.key = mods, key
        self.listening = False
        self.show_keys()
        return True

    def check_conflict(self):
        self.taken = None
        if not self.key:
            self.conflict.set_visible(False)
            self.replace_row.set_visible(False)
            return
        mask = sum(MOD_BITS[m] for m in self.mods)
        mine = {(e["key"].lower(), tuple(sorted(e["mods"]))) for e in self.win.entries if e is not self.entry}
        if (self.key.lower(), tuple(sorted(self.mods))) in mine:
            self.taken = "one of your shortcuts"
        else:
            own = self.entry and (self.entry["key"].lower(), tuple(sorted(self.entry["mods"])))
            for b in hyprctl_binds():
                bkey = b.get("key", "")
                if b.get("keycode") and not bkey:
                    bkey = f"code:{b['keycode']}"
                if b.get("modmask") != mask or bkey.lower() != self.key.lower() or b.get("submap"):
                    continue
                if own and (bkey.lower(), tuple(sorted(mods_from_mask(mask)))) == own:
                    continue
                self.taken = b.get("description") or f"{b.get('dispatcher')} {b.get('arg', '')}".strip()
                break
        if self.taken:
            builtin = self.taken != "one of your shortcuts"
            self.conflict.set_label(f"These keys already do: {self.taken}." + ("" if builtin else " Choose other keys."))
            self.conflict.set_visible(True)
            self.replace_row.set_visible(builtin)
        else:
            self.conflict.set_visible(False)
            self.replace_row.set_visible(False)
            self.replace_row.set_active(False)

    # ── folder ──
    def pick_folder(self, *_):
        dlg = Gtk.FileDialog(title="Choose a folder")

        def done(d, res):
            try:
                f = d.select_folder_finish(res)
            except GLib.Error:
                return
            self.folder = f.get_path()
            self.folder_row.set_subtitle(self.folder.replace(str(HOME), "~"))
            self.autoname()

        dlg.select_folder(self.win, None, done)

    # ── save ──
    def action(self):
        """(dispatcher, argument, value) for the chosen action, or None when incomplete."""
        k = self.kind()
        if k == "Open an app":
            if not self.apps:
                return None
            a = self.apps[self.app_row.get_selected()]
            return "exec", f"gtk-launch {shlex.quote(a.get_id())}", a.get_id()
        if k == "Open a website":
            url = self.url_row.get_text().strip()
            if not url:
                return None
            if "://" not in url:
                url = "https://" + url
            return "exec", f"xdg-open {shlex.quote(url)}", url
        if k == "Open a folder":
            return ("exec", f"xdg-open {shlex.quote(self.folder)}", self.folder) if self.folder else None
        if k == "Built-in action":
            label, disp, arg, needs_n = BUILTINS[self.builtin_row.get_selected()]
            if needs_n:
                arg = str(int(self.number_row.get_value()))
            return disp, arg, label
        cmd = self.cmd_row.get_text().strip()
        return ("exec", cmd, cmd) if cmd else None

    def validate(self):
        blocked = getattr(self, "taken", None) and not (self.replace_row.get_visible() and self.replace_row.get_active())
        ok = bool(self.key) and self.action() is not None and bool(self.name_row.get_text().strip()) and not blocked
        self.save_btn.set_sensitive(ok)

    def on_save(self, *_):
        disp, arg, value = self.action()
        e = {"id": self.entry["id"] if self.entry else uuid.uuid4().hex[:8],
             "mods": self.mods, "key": self.key, "name": self.name_row.get_text().strip(),
             "kind": self.kind(), "value": value, "dispatcher": disp, "arg": arg,
             "replace": bool(self.replace_row.get_visible() and self.replace_row.get_active())}
        if e["kind"] == "Open an app":
            e["app_name"] = self.apps[self.app_row.get_selected()].get_display_name()
        if e["kind"] == "Built-in action" and BUILTINS[self.builtin_row.get_selected()][3]:
            e["number"] = int(self.number_row.get_value())
        entries = [x for x in self.win.entries if x is not self.entry] + [e]
        if self.win.save(entries, f"“{e['name']}” saved. Try it now: {' + '.join(combo_text(e['mods'], e['key']))}"):
            self.close()


# ── main window ───────────────────────────────────────────────────────────────
class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Keyboard Shortcuts", default_width=760, default_height=680)
        self.entries = load_store()

        self.toasts = Adw.ToastOverlay()
        tv = Adw.ToolbarView()
        header = Adw.HeaderBar()
        add = Gtk.Button(icon_name="list-add-symbolic", tooltip_text="Add a shortcut", css_classes=["suggested-action"])
        add.connect("clicked", lambda *_: EditDialog(self).present(self))
        header.pack_start(add)
        self.stack = Adw.ViewStack()
        switcher = Adw.ViewSwitcher(stack=self.stack, policy=Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)
        tv.add_top_bar(header)

        # tab 1: yours (a fixed holder; its page is rebuilt on every change)
        self.mine_holder = Adw.Bin()
        self.stack.add_titled_with_icon(self.mine_holder, "mine", "My shortcuts", "starred-symbolic")
        # tab 2: everything active
        all_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.search = Gtk.SearchEntry(placeholder_text="Search shortcuts", margin_top=12, margin_start=24, margin_end=24)
        self.search.connect("search-changed", lambda *_: self.all_list.invalidate_filter())
        all_box.append(self.search)
        self.all_list = Gtk.ListBox(css_classes=["boxed-list"], selection_mode=Gtk.SelectionMode.NONE,
                                    margin_top=12, margin_bottom=24, margin_start=24, margin_end=24)
        self.all_list.set_filter_func(self.filter_all)
        scroller = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        clamp = Adw.Clamp(maximum_size=760, child=self.all_list)
        scroller.set_child(clamp)
        all_box.append(scroller)
        self.stack.add_titled_with_icon(all_box, "all", "All shortcuts", "input-keyboard-symbolic")

        tv.set_content(self.stack)
        self.toasts.set_child(tv)
        self.set_content(self.toasts)
        self.refresh()

    # ── lists ──
    def refresh(self):
        # rebuild "My shortcuts"
        self.mine_page = Adw.PreferencesPage()
        if not self.entries:
            status = Adw.StatusPage(icon_name="input-keyboard-symbolic", title="No shortcuts yet",
                                    description="Make a key combination open an app, a website, a folder, or do a desktop action.")
            btn = Gtk.Button(label="Add a shortcut", halign=Gtk.Align.CENTER, css_classes=["suggested-action", "pill"])
            btn.connect("clicked", lambda *_: EditDialog(self).present(self))
            status.set_child(btn)
            group = Adw.PreferencesGroup()
            group.add(status)
            self.mine_page.add(group)
        else:
            group = Adw.PreferencesGroup(title="Your shortcuts",
                                         description="They work right away and appear in the Super+H cheat sheet.")
            for e in sorted(self.entries, key=lambda x: x["name"].lower()):
                row = Adw.ActionRow(title=GLib.markup_escape_text(e["name"]), subtitle=GLib.markup_escape_text(describe(e)))
                row.add_suffix(keycaps(combo_text(e["mods"], e["key"])))
                edit = Gtk.Button(icon_name="document-edit-symbolic", tooltip_text="Change", valign=Gtk.Align.CENTER, css_classes=["flat"])
                edit.connect("clicked", lambda _b, x=e: EditDialog(self, x).present(self))
                delete = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="Remove", valign=Gtk.Align.CENTER, css_classes=["flat"])
                delete.connect("clicked", lambda _b, x=e: self.confirm_delete(x))
                row.add_suffix(edit)
                row.add_suffix(delete)
                group.add(row)
            self.mine_page.add(group)
        self.mine_holder.set_child(self.mine_page)

        # rebuild "All shortcuts"
        while (child := self.all_list.get_first_child()) is not None:
            self.all_list.remove(child)
        seen = set()
        for b in sorted(hyprctl_binds(), key=lambda b: (b.get("description") or b.get("dispatcher", "")).lower()):
            if b.get("submap"):
                continue
            key = b.get("key") or (f"code:{b['keycode']}" if b.get("keycode") else "")
            if not key:
                continue
            desc = b.get("description") or f"{b.get('dispatcher', '')} {b.get('arg', '')}".strip()
            sig = (desc, b.get("modmask"), key)
            if sig in seen:
                continue
            seen.add(sig)
            row = Adw.ActionRow(title=GLib.markup_escape_text(desc[:1].upper() + desc[1:]))
            row.add_suffix(keycaps(combo_text(mods_from_mask(b.get("modmask", 0)), key)))
            row.search_text = (desc + " " + " ".join(combo_text(mods_from_mask(b.get("modmask", 0)), key))).lower()
            self.all_list.append(row)

    def filter_all(self, row):
        q = self.search.get_text().strip().lower()
        return not q or all(w in getattr(row, "search_text", "") for w in q.split())

    # ── changes ──
    def save(self, entries, message):
        err = apply(entries)
        if err:
            Adw.AlertDialog(heading="Couldn't save the shortcut",
                            body=f"Hyprland rejected it, so nothing was changed.\n\n{err}").present(self)
            return False
        self.entries = entries
        self.refresh()
        self.toasts.add_toast(Adw.Toast(title=message, timeout=4))
        return True

    def confirm_delete(self, e):
        dlg = Adw.AlertDialog(heading=f"Remove “{e['name']}”?",
                              body=" + ".join(combo_text(e["mods"], e["key"])) + " will stop doing this."
                              + (" The shortcut it replaced comes back." if e.get("replace") else ""))
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("remove", "Remove")
        dlg.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE)
        dlg.connect("response", lambda _d, r: r == "remove" and self.save(
            [x for x in self.entries if x is not e], f"“{e['name']}” removed"))
        dlg.present(self)


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_startup(self):
        Adw.Application.do_startup(self)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        ensure_sourced()

    def do_activate(self):
        win = self.props.active_window or Window(self)
        win.present()
        if os.environ.get("SHORTCUTS_TEST_NEW"):           # test hook: open "New shortcut", already listening
            dlg = EditDialog(win)
            dlg.present(win)
            GLib.timeout_add(300, lambda: (dlg.start_listening(), False)[1])


if __name__ == "__main__":
    sys.exit(App().run(sys.argv))
