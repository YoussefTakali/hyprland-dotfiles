#!/usr/bin/env python3
"""Desktop Setup — graphical installer for this Hyprland desktop on Arch, Fedora and Ubuntu (26.04+).

Pages: Welcome → Your PC (checks) → Choices → Installing (progress + log) → Done.
The work is done by installer/backend.sh; this window shows its progress lines (@@STEP, @@PROGRESS, …).
Administrator access is asked once, with the system's password dialog (pkexec installer/grant.sh).
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

APP_ID = "io.github.YoussefTakali.DesktopSetup"
REPO = Path(__file__).resolve().parent.parent
BACKEND = REPO / "installer" / "backend.sh"
GRANT = REPO / "installer" / "grant.sh"
GPUINFO = REPO / "config" / "hypr" / "scripts" / "GpuInfo.sh"
USER = os.environ.get("USER") or os.getlogin()

LOCKS = [("Slate", "Glass pane on the left, wallpaper drifting"),
         ("Iris", "A clear lens between the hours and minutes"),
         ("Fog", "Misted glass with the time wiped clean"),
         ("Cards", "Centred clock with a music card")]
BARS = [("ultimate", "Ultimate glass bar", "Frosted bar of pills; its shape follows the theme switcher (Super+Ctrl+T)"),
        ("adaptive", "Classic bar", "One bar across the top, colours from the wallpaper"),
        ("glass", "Glass islands", "Three floating glass groups, colours from the wallpaper")]
LOGINS = [("keep", "This PC's login screen", "Recommended. Hyprland is pre-selected for you"),
          ("sddm", "Themed login screen (SDDM)", "Animated theme; replaces the current login screen")]

CSS = b"""
.step-title { font-size: 1.25em; font-weight: bold; }
.log { font-family: monospace; font-size: 0.85em; }
.check-ok { color: @success_color; }
.check-warn { color: @warning_color; }
.check-bad { color: @error_color; }
progressbar trough, progressbar progress { min-height: 10px; border-radius: 6px; }
"""
# The desktop's GTK theme draws windows see-through (glass, for Hyprland's blur). The installer must stay readable
# on any PC and over any window, so it gets solid colours, applied above the user's theme.
SOLID_CSS = b"""
:root { --window-bg-color: #181825; --view-bg-color: #1e1e2e; --headerbar-bg-color: #181825;
        --headerbar-backdrop-color: #181825; --card-bg-color: rgba(255, 255, 255, 0.06); }
@define-color window_bg_color #181825;
@define-color view_bg_color #1e1e2e;
window, window.background { background-color: #181825; }
"""


# ── facts about this PC ───────────────────────────────────────────────────────
def gpu_info():
    try:
        out = subprocess.run([str(GPUINFO)], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return {}
    info = {}
    for line in out.splitlines():
        k, _, v = line.partition("=")
        info[k] = v.strip('"')
    return info


def gpu_names():
    """'Intel …', 'NVIDIA GeForce RTX 4060 …' from lspci."""
    try:
        out = subprocess.run(["lspci"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return []
    names = []
    for line in out.splitlines():
        if re.search(r"VGA|3D controller|Display controller", line):
            name = line.split(": ", 1)[-1]
            name = re.sub(r"\s*\(rev \w+\)", "", name).replace("Corporation ", "").replace("Advanced Micro Devices, Inc. ", "AMD ")
            names.append(name)
    return names


def describe_graphics(info):
    mode = info.get("MODE", "unknown")
    driver = info.get("NVIDIA_DRIVER")
    if mode == "hybrid-nvidia":
        text = "Laptop with two GPUs: the built-in one runs the desktop, the NVIDIA one sleeps until a game or heavy app needs it."
    elif mode == "hybrid-amd":
        text = "Two GPUs: the built-in one runs the desktop, the AMD one wakes up for games and heavy apps."
    elif mode == "nvidia":
        text = "NVIDIA graphics."
    elif mode == "amd":
        text = "AMD graphics: drivers are built into Linux; full video decoding gets added."
    elif mode == "intel":
        text = "Intel graphics: drivers are built into Linux; full video decoding gets added."
    else:
        text = "No known graphics card found; the desktop may not start."
    if "nvidia" in mode:
        text += f" NVIDIA driver: {driver} (already installed)." if driver else " The NVIDIA driver will be installed."
    return text


def keyboard_layouts():
    layouts, current = [], ""
    rules = Path("/usr/share/X11/xkb/rules/evdev.lst")
    if rules.exists():
        section = None
        for line in rules.read_text(errors="replace").splitlines():
            if line.startswith("! "):
                section = line[2:].strip()
                continue
            if section == "layout" and line.strip():
                code, _, name = line.strip().partition(" ")
                layouts.append((code, name.strip()))
    try:
        out = subprocess.run(["localectl", "status"], capture_output=True, text=True, timeout=5).stdout
        m = re.search(r"X11 Layout:\s*(\S+)", out) or re.search(r"VC Keymap:\s*([a-z]+)", out)
        current = m.group(1).split(",")[0] if m else ""
    except Exception:
        pass
    layouts.sort(key=lambda x: x[1].lower())
    return layouts or [("us", "English (US)")], current or "us"


def secure_boot():
    try:
        out = subprocess.run(["mokutil", "--sb-state"], capture_output=True, text=True, timeout=5).stdout
        return "enabled" in out
    except Exception:
        return False


def os_release():
    info = {}
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            k, _, v = line.partition("=")
            info[k] = v.strip('"')
    except Exception:
        pass
    return info


def distro():
    """(id, ok, message): arch / fedora / ubuntu, whether this release can run the desktop, and why not."""
    osr = os_release()
    ids = [osr.get("ID", "")] + osr.get("ID_LIKE", "").split()
    for d in ("arch", "fedora", "ubuntu"):
        if d in ids:
            break
    else:
        return "", False, "This installer supports Arch, Fedora and Ubuntu."
    if d == "ubuntu":
        try:
            ver = float(osr.get("UBUNTU_VERSION_ID") or osr.get("VERSION_ID", "0"))
        except ValueError:
            ver = 0
        if ver < 26.04:
            return d, False, ("Ubuntu 26.04 LTS or newer is needed (older releases have an X11-only rofi "
                              "and a Qt too old for the lock screen).")
    return d, True, ""


def os_name():
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if line.startswith("PRETTY_NAME="):
                return line.split("=", 1)[1].strip('"')
    except Exception:
        pass
    return "Unknown"


# ── the window ────────────────────────────────────────────────────────────────
class Setup(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Desktop Setup", default_width=880, default_height=680)
        self.info = gpu_info()
        self.installing = False
        self.notes = []
        self.connect("close-request", self.on_close)

        self.toasts = Adw.ToastOverlay()
        tv = Adw.ToolbarView()
        self.header = Adw.HeaderBar()
        self.back = Gtk.Button(icon_name="go-previous-symbolic", visible=False)
        self.back.connect("clicked", lambda *_: self.go(self.prev_page))
        self.header.pack_start(self.back)
        tv.add_top_bar(self.header)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT, transition_duration=300)
        tv.set_content(self.stack)
        self.toasts.set_child(tv)
        self.set_content(self.toasts)

        self.stack.add_named(self.page_welcome(), "welcome")
        self.stack.add_named(self.page_check(), "check")
        self.stack.add_named(self.page_choices(), "choices")
        self.stack.add_named(self.page_install(), "install")
        self.done_holder = Adw.Bin()
        self.stack.add_named(self.done_holder, "done")
        self.prev_page = None
        self.go("welcome")

    # ── navigation ──
    ORDER = ["welcome", "check", "choices", "install", "done"]

    def go(self, name):
        i = self.ORDER.index(name)
        self.prev_page = self.ORDER[i - 1] if 0 < i < 3 else None
        self.back.set_visible(self.prev_page is not None)
        self.stack.set_visible_child_name(name)

    def footer(self, label, callback, sensitive=True):
        btn = Gtk.Button(label=label, css_classes=["suggested-action", "pill"], halign=Gtk.Align.CENTER,
                         margin_top=6, margin_bottom=24, sensitive=sensitive)
        btn.connect("clicked", callback)
        return btn

    # ── 1. welcome ──
    def page_welcome(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        status = Adw.StatusPage(icon_name="computer-symbolic", vexpand=True,
                                title="Install the desktop",
                                description="A Hyprland desktop with colours from your wallpaper, a glass lock screen, "
                                            "a utilities menu, notifications, volume and brightness pop-ups, and "
                                            "graphics set up for your GPU.\n\n"
                                            "It takes 20–40 minutes and needs an internet connection. "
                                            "Your current settings are backed up first.")
        box.append(status)
        box.append(self.footer("Get started", lambda *_: self.go("check")))
        return box

    # ── 2. checks ──
    def page_check(self):
        page = Adw.PreferencesPage()
        g = Adw.PreferencesGroup(title="Your PC", description="Checked before anything is installed.")
        problems = []

        def row(title, subtitle, state):
            r = Adw.ActionRow(title=title, subtitle=GLib.markup_escape_text(subtitle), subtitle_lines=3)
            icon = {"ok": "object-select-symbolic", "warn": "dialog-warning-symbolic", "bad": "dialog-error-symbolic"}[state]
            r.add_prefix(Gtk.Image(icon_name=icon, css_classes=[f"check-{state}"], pixel_size=20))
            g.add(r)

        name = os_name()
        self.distro, ok, why = distro()
        row("System", name if ok else f"{name}. {why}", "ok" if ok else "bad")
        if not ok:
            problems.append("unsupported system")

        names = gpu_names()
        mode = self.info.get("MODE", "unknown")
        row("Graphics", ("\n".join(names) + "\n" if names else "") + describe_graphics(self.info),
            "warn" if mode == "unknown" else "ok")

        sb = secure_boot()
        # Fedora builds the driver locally and signs it with a key approved via a password (MOK);
        # Ubuntu asks for its own MOK password in the terminal, Arch leaves signing to the user
        self.needs_mok = sb and "nvidia" in mode and not self.info.get("NVIDIA_DRIVER") and self.distro == "fedora"
        if self.needs_mok:
            row("Secure Boot", "On. The NVIDIA driver must be approved once at the next start: you'll choose a "
                               "password on the next page and type it on a blue screen after restarting.", "warn")
        else:
            row("Secure Boot", "On" if sb else "Off", "ok")

        free = shutil.disk_usage(Path.home()).free // 1024**3
        row("Free space", f"{free} GB" + ("" if free >= 8 else " — at least 8 GB is needed"), "ok" if free >= 8 else "bad")
        if free < 8:
            problems.append("disk")

        online = subprocess.run(["curl", "-sfI", "--max-time", "6", "https://github.com"],
                                capture_output=True).returncode == 0
        row("Internet", "Connected" if online else "Not connected — connect to the internet first", "ok" if online else "bad")
        if not online:
            problems.append("internet")

        self.has_hyprland = shutil.which("Hyprland") is not None
        if self.has_hyprland:
            row("Hyprland", "Already installed: only the desktop and its settings will be installed (faster).", "ok")
        page.add(g)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(page)
        page.set_vexpand(True)
        if problems:
            box.append(Gtk.Label(label="Fix the problems marked in red, then open the installer again.",
                                 css_classes=["dim-label"], margin_bottom=8))
        box.append(self.footer("Next", lambda *_: self.go("choices"), sensitive=not problems))
        return box

    # ── 3. choices ──
    def page_choices(self):
        page = Adw.PreferencesPage(vexpand=True)

        g1 = Adw.PreferencesGroup(title="Keyboard")
        self.layouts, current = keyboard_layouts()
        self.kb_row = Adw.ComboRow(title="Layout", enable_search=True,
                                   model=Gtk.StringList.new([n if f"({c})" in n.lower() else f"{n} ({c})" for c, n in self.layouts]))
        self.kb_row.set_expression(Gtk.PropertyExpression.new(Gtk.StringObject, None, "string"))
        codes = [c for c, _ in self.layouts]
        if current in codes:
            self.kb_row.set_selected(codes.index(current))
        g1.add(self.kb_row)
        page.add(g1)

        g2 = Adw.PreferencesGroup(title="Look", description="Both can be changed later (Super+X).")
        self.lock_row = self.combo("Lock screen", [(n, d) for n, d in LOCKS])
        g2.add(self.lock_row)
        self.bar_row = self.combo("Top bar", [(n, d) for _, n, d in BARS])
        g2.add(self.bar_row)
        page.add(g2)

        g3 = Adw.PreferencesGroup(title="Login screen")
        self.login_row = self.combo("Use", [(n, d) for _, n, d in LOGINS])
        g3.add(self.login_row)
        page.add(g3)

        g4 = Adw.PreferencesGroup(title="Graphics")
        mode = self.info.get("MODE", "unknown")
        parts = []
        if "nvidia" in mode and not self.info.get("NVIDIA_DRIVER"):
            parts.append({"fedora": "NVIDIA driver (RPM Fusion)", "ubuntu": "NVIDIA driver (ubuntu-drivers)",
                          "arch": "NVIDIA driver (nvidia-open)"}.get(getattr(self, "distro", ""), "NVIDIA driver"))
        if "intel" in self.info.get("GPUS", ""):
            parts.append("Intel video decoding")
        if "amd" in self.info.get("GPUS", ""):
            parts.append("AMD video decoding")
        self.drv_row = Adw.SwitchRow(title="Install graphics drivers", active=True,
                                     subtitle=", ".join(parts) if parts else "Nothing extra needed for this PC")
        g4.add(self.drv_row)
        self.mok_row = Adw.PasswordEntryRow(title="Driver key password (8+ characters, needed once at next start)",
                                            visible=getattr(self, "needs_mok", False))
        self.mok_row.connect("changed", lambda *_: self.validate_choices())
        g4.add(self.mok_row)
        self.base_row = Adw.SwitchRow(title="Reinstall the Hyprland base packages", active=False,
                                      subtitle="Hyprland is already installed; only needed to repair it",
                                      visible=getattr(self, "has_hyprland", False))
        g4.add(self.base_row)
        page.add(g4)

        g5 = Adw.PreferencesGroup(title="Sound")
        self.jack_row = Adw.SwitchRow(title="Headphone jack fix", active=False,
                                      subtitle="Only if headphones/speakers on the 3.5mm jack stay silent: keeps the "
                                               "jack output on even when the PC doesn't detect the plug")
        g5.add(self.jack_row)
        page.add(g5)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(page)
        self.install_btn = self.footer("Install", self.on_install)
        box.append(self.install_btn)
        GLib.idle_add(lambda: (self.validate_choices(), False)[1])
        return box

    def combo(self, title, options):
        """A dropdown showing the option's name; its description is shown under the title."""
        row = Adw.ComboRow(title=title, model=Gtk.StringList.new([n for n, _ in options]))
        row.set_subtitle(options[0][1])
        row.connect("notify::selected", lambda r, _p: r.set_subtitle(options[r.get_selected()][1]))
        return row

    def validate_choices(self):
        ok = True
        if self.mok_row.get_visible() and self.drv_row.get_active():
            ok = len(self.mok_row.get_text()) >= 8
        self.install_btn.set_sensitive(ok)

    # ── 4. installing ──
    def page_install(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin_top=36, margin_bottom=24,
                      margin_start=48, margin_end=48)
        self.step_title = Gtk.Label(label="Starting…", xalign=0, css_classes=["step-title"])
        self.step_sub = Gtk.Label(label="", xalign=0, css_classes=["dim-label"])
        self.progress = Gtk.ProgressBar()
        box.append(self.step_title)
        box.append(self.step_sub)
        box.append(self.progress)
        self.warn_label = Gtk.Label(label="", xalign=0, wrap=True, css_classes=["check-warn"], visible=False)
        box.append(self.warn_label)

        self.log_view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                     wrap_mode=Gtk.WrapMode.WORD_CHAR, css_classes=["log"],
                                     top_margin=8, bottom_margin=8, left_margin=10, right_margin=10)
        self.log_buf = self.log_view.get_buffer()
        scroller = Gtk.ScrolledWindow(vexpand=True, min_content_height=260, child=self.log_view)
        frame = Gtk.Frame(child=scroller)
        exp = Gtk.Expander(label="Details", child=frame, vexpand=True)
        box.append(exp)
        box.append(Gtk.Label(label="You can keep using the PC. Please don't turn it off until this finishes.",
                             css_classes=["dim-label"]))
        return box

    def log(self, text):
        end = self.log_buf.get_end_iter()
        self.log_buf.insert(end, text + "\n")
        if self.log_buf.get_line_count() > 5000:              # keep the view light; the full log is on disk
            ok, cut = self.log_buf.get_iter_at_line(1000)
            self.log_buf.delete(self.log_buf.get_start_iter(), cut)
        mark = self.log_buf.create_mark(None, self.log_buf.get_end_iter(), False)
        self.log_view.scroll_mark_onscreen(mark)

    def on_install(self, *_):
        code = self.layouts[self.kb_row.get_selected()][0]
        env = dict(os.environ,
                   OPT_KB=code, OPT_KB_VARIANT="",
                   OPT_LOCK=LOCKS[self.lock_row.get_selected()][0],
                   OPT_BAR=BARS[self.bar_row.get_selected()][0],
                   OPT_LOGIN=LOGINS[self.login_row.get_selected()][0],
                   OPT_DRIVERS="1" if self.drv_row.get_active() else "0",
                   OPT_MOK_PASSWORD=self.mok_row.get_text() if self.mok_row.get_visible() else "",
                   OPT_JACK_FIX="1" if self.jack_row.get_active() else "0",
                   OPT_SKIP_BASE="1" if (getattr(self, "has_hyprland", False) and not self.base_row.get_active()) else "0")
        # one password prompt, from the system
        r = subprocess.run(["pkexec", str(GRANT), "grant", USER], capture_output=True, text=True)
        if r.returncode != 0:
            self.toasts.add_toast(Adw.Toast(title="Administrator access is needed to install. Try again.", timeout=5))
            return
        self.installing = True
        self.go("install")
        self.back.set_visible(False)
        launcher = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
        for k, v in env.items():
            launcher.setenv(k, v, True)
        self.proc = launcher.spawnv(["bash", str(BACKEND)])
        self.stream = Gio.DataInputStream.new(self.proc.get_stdout_pipe())
        self.failed = None
        self.read_line()

    def read_line(self):
        self.stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    def on_line(self, stream, res):
        try:
            line, _ = stream.read_line_finish_utf8(res)
        except GLib.Error:
            line = None
        if line is None:
            self.proc.wait_async(None, self.on_exit)
            return
        self.handle(line)
        self.read_line()

    def handle(self, line):
        if line.startswith("@@STEP "):
            _, n, total, title = line.split(" ", 3)
            self.step_title.set_label(title)
            self.step_sub.set_label(f"Step {n} of {total}")
        elif line.startswith("@@PROGRESS "):
            try:
                self.progress.set_fraction(min(1, int(line.split()[1]) / 100))
            except ValueError:
                pass
        elif line.startswith("@@NOTE "):
            self.notes.append(line[7:])
        elif line.startswith("@@WARN "):
            self.warn_label.set_label("⚠ " + line[7:])
            self.warn_label.set_visible(True)
            self.log("WARNING: " + line[7:])
        elif line.startswith("@@FAIL "):
            self.failed = line[7:]
            self.log("FAILED: " + self.failed)
        elif line == "@@DONE":
            pass
        else:
            self.log(line)

    def on_exit(self, proc, res):
        try:
            proc.wait_finish(res)
        except GLib.Error:
            pass
        ok = proc.get_exit_status() == 0 and not self.failed
        subprocess.run(["sudo", "-n", str(GRANT), "revoke", USER], capture_output=True)
        self.installing = False
        self.done_holder.set_child(self.page_done(ok))
        self.go("done")

    # ── 5. done ──
    def page_done(self, ok):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        notes = {n.split(" ", 1)[0]: (n.split(" ", 1)[1] if " " in n else "") for n in self.notes}
        if ok:
            text = "Restart the PC to start using it. "
            text += "On the login screen, Hyprland is already selected for you."
            if "SECURE_BOOT_KEY" in notes:
                text += ("\n\nAfter restarting, a blue screen appears (MOK management): choose “Enroll MOK”, then "
                         "“Continue”, “Yes”, type the driver key password you chose, and “Reboot”. "
                         "This happens only once and lets the NVIDIA driver load with Secure Boot on.")
            if "NO_LOGIN_SCREEN" in notes:
                text += ("\n\nThis PC has no login screen: log in on the console and type “Hyprland”, "
                         "or run the installer again and choose the themed login screen.")
            if "NVIDIA_INSTALLED" in notes:
                text += "\n\nThe NVIDIA driver starts after the restart."
            text += "\n\nShortcuts: Super+H shows all of them, Super+X opens the utilities, Super+L locks."
            status = Adw.StatusPage(icon_name="object-select-symbolic", title="Your desktop is ready",
                                    description=GLib.markup_escape_text(text), vexpand=True)
            box.append(status)
            row = Gtk.Box(spacing=12, halign=Gtk.Align.CENTER, margin_bottom=24)
            later = Gtk.Button(label="Restart later", css_classes=["pill"])
            later.connect("clicked", lambda *_: self.close())
            now = Gtk.Button(label="Restart now", css_classes=["suggested-action", "pill"])
            now.connect("clicked", self.restart)
            row.append(later)
            row.append(now)
            box.append(row)
        else:
            what = self.failed or "an unexpected error"
            status = Adw.StatusPage(icon_name="dialog-error-symbolic", title="The installation stopped",
                                    description=GLib.markup_escape_text(
                                        f"{what}\n\nNothing after that step was changed, and your previous settings "
                                        f"are kept. Fix the problem and run the installer again — it is safe to "
                                        f"repeat. The full log is in {notes.get('LOG', '~/.cache')}."),
                                    vexpand=True)
            box.append(status)
            btn = Gtk.Button(label="Close", css_classes=["pill"], halign=Gtk.Align.CENTER, margin_bottom=24)
            btn.connect("clicked", lambda *_: self.close())
            box.append(btn)
        return box

    def restart(self, button):
        # logind directly: with interactive authorization GNOME asks for a password if a reboot needs one
        # (another user logged in, an app blocking shutdown) instead of the request failing silently
        button.set_sensitive(False)

        def finished(bus, res):
            try:
                bus.call_finish(res)
            except GLib.Error as e:
                button.set_sensitive(True)
                self.toasts.add_toast(Adw.Toast(title=f"Couldn't restart ({e.message}). Restart from the system menu.",
                                                timeout=10))

        Gio.bus_get_sync(Gio.BusType.SYSTEM).call(
            "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "Reboot",
            GLib.Variant("(b)", (True,)), None, Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, -1, None, finished)

    def on_close(self, *_):
        if self.installing:
            self.toasts.add_toast(Adw.Toast(title="Please wait: the installation is still running.", timeout=3))
            return True
        return False


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_startup(self):
        Adw.Application.do_startup(self)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.PREFER_DARK)
        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        solid = Gtk.CssProvider()
        solid.load_from_data(SOLID_CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), solid, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

    def do_activate(self):
        win = self.props.active_window or Setup(self)
        win.present()
        page = os.environ.get("SETUP_PAGE")                          # for screenshots / testing only
        if page in ("check", "choices"):
            win.go(page)
        elif page == "done":
            win.done_holder.set_child(win.page_done(True))
            win.go("done")


if __name__ == "__main__":
    sys.exit(App().run(sys.argv))
