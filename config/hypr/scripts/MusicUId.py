#!/usr/bin/env python3
# Background renderer for the hyprlock music card (runs only while hyprlock is up).
# Every frame (~60 fps) it writes pango markup for each interactive widget into
# $XDG_RUNTIME_DIR/hyprlock-ui/<name>; hyprlock labels just print those files
# through MusicUI.sh. Position is interpolated between playerctl polls so the bar
# moves smoothly, and bar + knob are one label so they can never get out of sync.
#
# Geometry is in hyprlock coords (x offset from screen center, y from bottom) and
# must match hyprlock.conf. Glyph metrics were measured with pango at 96 dpi.
import fcntl, os, re, signal, socket, subprocess, threading, time

RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
OUT = os.path.join(RUN, "hyprlock-ui")
PREVIEW = os.path.join(RUN, "hyprlock-scrub")
FPS = 60

BAR_X, BAR_Y, BAR_W = -25, 830, 320       # bar center x, center y, total width
CAP_W = 2                                 # rounded end width at 2.5pt / 3pt
INNER = BAR_W - 2 * CAP_W
# Music controls: center x, center y, hover radius. Icons grow on hover like the power buttons
# (labels: 80pt spacer + glyph, rise -760/pt measured with pango; centers 40.5px / 43.5px above label bottom)
BUTTONS = {"prev": (185, 875, 22), "play": (255, 875, 30), "next": (325, 875, 22)}
BUTTON_PT = {"prev": (18.0, 22.0), "play": (24.0, 28.0), "next": (18.0, 22.0)}
MUSIC_RISE_PER_PT = -760
CAVA_BARS = 24

LCAP, RCAP, BLOCK, DOT = "", "", "█", "●"
ICONS = {"prev": "\U000f04ae", "next": "\U000f04ad", "play": "\U000f040a", "pause": "\U000f03e4"}
KNOB_MAX = 12.0                           # pt; knob grows 0 -> 12pt on hover/drag
ANIM = 0.16                               # seconds for the grow / shrink animation


def wal_color(name, default):
    try:
        with open(os.path.expanduser("~/.config/hypr/wallust/wallust-hyprland.conf")) as f:
            m = re.search(rf"^\${name} = rgb\((\w{{6}})\)", f.read(), re.M)
            return "#" + m.group(1) if m else default
    except OSError:
        return default


ACCENT = wal_color("color13", "#AF5CE5")
DIM = wal_color("color8", "#7E8395")
WARN = wal_color("color12", "#BC5C69")

# Lock-screen power buttons (LockPower.sh arms on first click, acts on the second).
# Each label = 80pt invisible spacer on both sides (fixed height, centered glyph) + the glyph, whose
# `rise` is scaled with its size so it grows around a fixed center. Rise/pt measured with pango at 96 dpi
# using "JetBrainsMono Nerd Font Propo"; centers sit 42.5px (icon) / 54.5px (dot) above the label bottom.
POWER_Y = 150                                   # button center, px from screen bottom
POWER = {"suspend": -80, "reboot": 0, "poweroff": 80}
POWER_ICONS = {"suspend": "\U000f0904", "reboot": "\U000f0709", "poweroff": "\U000f0425"}
ICON_PT, ICON_HOVER_PT = 22.0, 28.0
DOT_PT, DOT_HOVER_PT = 46.0, 58.0
RISE_PER_PT = {"suspend": -496, "reboot": -667, "poweroff": -667, "dot": -495}
POWER_R = 26                                    # hover radius, px
ARMED = os.path.join(RUN, "hyprlock-power-armed")
OUTPUT_Y = 772                                  # output picker center (below the card)


def strut(inner):
    pad = "<span size='80pt'> </span>"
    return f"<span font_family='JetBrainsMono Nerd Font Propo'>{pad}{inner}{pad}</span>"


def grown(glyph, size, base, kind, color):
    rise = int(RISE_PER_PT[kind] * (size - base))
    return strut(f"<span size='{size:.1f}pt' rise='{rise}' foreground='{color}'>{glyph}</span>")


class Cava(threading.Thread):
    """Audio visualizer: runs cava (raw ascii 0-7 per bar) and keeps the latest frame."""

    def __init__(self):
        super().__init__(daemon=True)
        self.levels = [0] * CAVA_BARS
        self.proc = None

    def run(self):
        conf = os.path.join(OUT, ".cava.conf")
        with open(conf, "w") as f:
            f.write(f"[general]\nframerate = 30\nbars = {CAVA_BARS}\n[input]\nmethod = pulse\nsource = auto\n"
                    "[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\nascii_max_range = 7\n"
                    "[smoothing]\nnoise_reduction = 60\n")
        try:
            self.proc = subprocess.Popen(["cava", "-p", conf], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            for line in self.proc.stdout:
                vals = [int(v) for v in line.strip().split(";") if v.isdigit()]
                if len(vals) == CAVA_BARS:
                    self.levels = vals
        except Exception:
            pass

    def stop(self):
        if self.proc:
            self.proc.terminate()


def cava_markup(levels, playing):
    """Bars in the accent color, brighter as they rise; flat and dim while paused."""
    glyphs = "▁▂▃▄▅▆▇█"
    if not playing:
        return f"<span foreground='{DIM}66' letter_spacing='3072'>{glyphs[0] * CAVA_BARS}</span>"
    out = []
    for v in levels:
        alpha = 0x70 + v * 0x12
        out.append(f"<span foreground='{ACCENT}{alpha:02X}'>{glyphs[max(0, min(7, v))]}</span>")
    return f"<span letter_spacing='3072'>{''.join(out)}</span>"


class Outputs(threading.Thread):
    """Usable audio outputs (AudioOutput.py), refreshed every second."""

    def __init__(self):
        super().__init__(daemon=True)
        self.items = []

    def run(self):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AudioOutput.py")
        import json
        while True:
            try:
                r = subprocess.run(["python3", "-I", script, "list"], capture_output=True, text=True, timeout=3)
                self.items = json.loads(r.stdout or "[]")
            except Exception:
                self.items = []
            time.sleep(1)


class Hypr:
    """Cursor position straight from Hyprland's IPC socket (much cheaper than hyprctl)."""

    def __init__(self):
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        self.path = os.path.join(RUN, "hypr", sig, ".socket.sock")
        self.mw, self.mh = 1920, 1080
        try:
            import json
            m = json.loads(self.ask("j/monitors"))[0]
            self.mw, self.mh = int(m["width"] / m["scale"]), int(m["height"] / m["scale"])
        except Exception:
            pass

    def ask(self, cmd):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(self.path)
            s.sendall(cmd.encode())
            data = b""
            while chunk := s.recv(65536):
                data += chunk
        return data.decode()

    def cursor(self):
        try:
            x, y = self.ask("cursorpos").split(",")
            return float(x), float(y)
        except Exception:
            return -1e4, -1e4

    def inside(self, cur, x, y, hw, hh):
        sx, sy = self.mw / 2 + x, self.mh - y
        return abs(cur[0] - sx) <= hw and abs(cur[1] - sy) <= hh


class Player(threading.Thread):
    """Polls playerctl a few times a second; position is extrapolated in between.
    `present` is False when no MPRIS player exists at all (the card is hidden then)."""

    def __init__(self):
        super().__init__(daemon=True)
        self.present, self.title, self.artist = False, "", ""
        self.status, self.pos, self.length, self.stamp = "Stopped", 0.0, 0.0, time.monotonic()

    def run(self):
        sep = "\x1f"
        fmt = sep.join(["{{status}}", "{{position}}", "{{mpris:length}}", "{{title}}", "{{artist}}"])
        while True:
            try:
                r = subprocess.run(["playerctl", "metadata", "--format", fmt], capture_output=True, text=True, timeout=1)
                st, pos, ln, title, artist = (r.stdout.rstrip("\n").split(sep) + [""] * 5)[:5]
                self.present = r.returncode == 0 or bool(subprocess.run(
                    ["playerctl", "-l"], capture_output=True, text=True, timeout=1).stdout.strip())
                self.status = st or "Stopped"
                self.pos, self.length = float(pos or 0) / 1e6, float(ln or 0) / 1e6
                self.title, self.artist = title, artist
            except Exception:
                self.present, self.status, self.pos, self.length = False, "Stopped", 0.0, 0.0
            self.stamp = time.monotonic()
            time.sleep(0.25)

    def position(self):
        p = self.pos + (time.monotonic() - self.stamp if self.status == "Playing" else 0)
        return min(p, self.length) if self.length else 0.0


def seg(width, color, size, rise):
    """Run of block glyphs exactly `width` px wide (letter_spacing squeezes them)."""
    if width <= 0.01:
        return ""
    n = max(1, int(-(-width // 2)))       # 2px advance at 2.5pt and 3pt
    ls = int(round((width - n * 2) / n * 1024))
    return f"<span size='{size}pt' rise='{rise}' foreground='{color}' letter_spacing='{ls}'>{BLOCK * n}</span>"


def bar_markup(frac, active, knob_pt):
    # Bar centered on the knob's center line (rise values measured; 1024 = 1px)
    size, rise = ("3", 4096) if active else ("2.5", 4608)
    track = "#6A6577" if active else "#57535F"   # opaque so overlapping glyphs leave no seams
    fill_px = round(max(0.0, min(1.0, frac)) * INNER * 2) / 2   # half-px steps: redraw only when it visibly moves
    lcap = ACCENT if fill_px > 0.5 else track
    rcap = ACCENT if fill_px >= INNER - 0.5 else track
    # Invisible zero-width 12pt space keeps the label height constant (single-char
    # spans only get half their letter_spacing, hence -2 x advance)
    m = f"<span font_family='JetBrainsMono Nerd Font'><span size='12pt' letter_spacing='-20480'> </span>"
    m += f"<span size='{size}pt' rise='{rise}' foreground='{lcap}'>{LCAP}</span>"
    if knob_pt >= 1:
        kw = knob_pt * 0.8                          # wanted knob width in px
        adv = round(knob_pt * 0.8)                  # pango's hinted advance of ●
        c = min(max(fill_px, kw / 2), INNER - kw / 2)
        krise = int((KNOB_MAX - knob_pt) * 0.45 * 1024)
        m += seg(c - kw / 2, ACCENT, size, rise)
        m += f"<span size='{knob_pt:.1f}pt' rise='{krise}' foreground='#FFFFFF' letter_spacing='{int((kw - adv) * 2048)}'>{DOT}</span>"
        m += seg(INNER - c - kw / 2, track, size, rise)
    else:
        m += seg(fill_px, ACCENT, size, rise) + seg(INNER - fill_px, track, size, rise)
    m += f"<span size='{size}pt' rise='{rise}' foreground='{rcap}'>{RCAP}</span></span>"
    return m


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def clip(text, n):
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def fmt(sec):
    sec = int(max(sec, 0))
    return f"{sec // 60}:{sec % 60:02d}"


def write(name, text, cache):
    if cache.get(name) == text:
        return
    cache[name] = text
    cache["__dirty"] = True
    tmp = os.path.join(OUT, f".{name}.tmp")
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, os.path.join(OUT, name))


def hyprlock_pid():
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                with open(f"/proc/{pid}/comm") as f:
                    if f.read().strip() == "hyprlock":
                        return int(pid)
            except OSError:
                pass
    return 0


def catches_sigusr2(pid):
    """True only if hyprlock installed a SIGUSR2 handler (force-update labels); otherwise
    the signal would kill it, so we never send it and labels fall back to their own timers."""
    try:
        with open(f"/proc/{pid}/status") as f:
            mask = next(int(l.split()[1], 16) for l in f if l.startswith("SigCgt:"))
        return bool(mask >> (signal.SIGUSR2 - 1) & 1)
    except (OSError, StopIteration, ValueError):
        return False


def flush(cache, pid, can_signal):
    """Ask hyprlock to redraw its labels now (SIGUSR2), only when a widget changed this frame."""
    # Disabled: hyprlock 0.9.6 aborts when SIGUSR2 arrives while it is running its label timers
    # (handleForceUpdateSignal re-enters CAsyncResourceManager and hits a locked mutex). Labels poll instead.
    cache.pop("__dirty", None)


def main():
    # hyprlock reads its commands' output until EOF; drop any pipe ends inherited
    # from it so a long-running helper can't keep hyprlock waiting (it hangs on exit)
    os.closerange(3, os.sysconf("SC_OPEN_MAX"))
    os.makedirs(OUT, exist_ok=True)
    lock = open(os.path.join(OUT, ".lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return  # already running
    with open(os.path.join(OUT, "pid"), "w") as f:
        f.write(str(os.getpid()))

    hypr, player, cache = Hypr(), Player(), {}
    player.start()
    outs = Outputs()
    outs.start()
    cava = Cava()
    cava.start()
    bgrow = {name: 0.0 for name in BUTTONS}
    grow = {name: 0.0 for name in POWER}       # 0 = normal, 1 = fully grown (hovered)
    knob, last, alive_check = 0.0, time.monotonic(), 0.0
    lock_pid, can_signal = 0, False
    while True:
        now = time.monotonic()
        dt, last = now - last, now
        if now - alive_check > 2:
            alive_check = now
            lock_pid = hyprlock_pid()
            if not lock_pid:
                break
            can_signal = catches_sigusr2(lock_pid)

        cur = hypr.cursor()
        dragging = os.path.exists(PREVIEW)
        if dragging:
            try:
                frac = float(open(PREVIEW).read() or 0)
            except (OSError, ValueError):
                frac = 0.0
            shown = frac * player.length
        else:
            shown = player.position()
            frac = shown / player.length if player.length else 0.0
        active = dragging or hypr.inside(cur, BAR_X, BAR_Y, BAR_W / 2 + 5, 15)

        # Ease the knob size toward its target
        target = KNOB_MAX if active and player.length else 0.0
        step = KNOB_MAX * dt / ANIM
        knob = min(target, knob + step) if knob < target else max(target, knob - step)

        armed = ""
        try:
            act, ts = open(ARMED).read().split()
            armed = act if time.time() - float(ts) <= 3 else ""
        except (OSError, ValueError):
            pass
        for name, x in POWER.items():
            on = hypr.inside(cur, x, POWER_Y, POWER_R, POWER_R)
            g = grow[name]
            g = min(1.0, g + dt / ANIM) if on or name == armed else max(0.0, g - dt / ANIM)
            grow[name] = g
            hot = WARN if name == "poweroff" or name == armed else ACCENT
            alpha = "FF" if name == armed else f"{int(0x22 + (0x66 - 0x22) * g):02X}"
            e = g * g * (3 - 2 * g)                 # smoothstep easing
            dot_pt = DOT_PT + (DOT_HOVER_PT - DOT_PT) * e
            icon_pt = ICON_PT + (ICON_HOVER_PT - ICON_PT) * e
            write(f"glow_{name}", grown(DOT, dot_pt, DOT_PT, "dot", f"{hot}{alpha}"), cache)
            color = "#FFFFFF" if g > 0.5 or name == armed else DIM
            write(f"icon_{name}", grown(POWER_ICONS[name], icon_pt, ICON_PT, name, color), cache)

        if not player.present:
            # No media source at all: blank every widget (card image hides itself too)
            for name in ["bar", "pos", "len", "title", "artist", "output", "cava"] + [f"{k}_{b}" for k in ("glow", "icon") for b in BUTTONS]:
                write(name, " ", cache)
            flush(cache, lock_pid, can_signal)
            time.sleep(max(0.0, 1 / FPS - (time.monotonic() - now)))
            continue

        write("title", esc(clip(player.title, 24)) if player.title else "Nothing Playing", cache)
        write("artist", esc(clip(player.artist, 30)) or " ", cache)
        write("bar", bar_markup(frac, active, knob), cache)
        write("pos", fmt(shown) if player.length else " ", cache)
        write("len", fmt(player.length) if player.length else " ", cache)
        cur_out = next((o for o in outs.items if o["default"]), None)
        if cur_out:
            text = f"{cur_out['icon']}  {clip(cur_out['label'], 28)}"
            half_w = len(text) * 4.6 + 22
            on = len(outs.items) > 1 and hypr.inside(cur, 0, OUTPUT_Y, half_w, 13)
            more = f"  <span foreground='{ACCENT if on else DIM}'>\U000f0140</span>" if len(outs.items) > 1 else ""
            color = "#FFFFFF" if on else DIM
            write("output", f"<span foreground='{color}'>{esc(text)}</span>{more}", cache)
        else:
            write("output", " ", cache)
        for name, (x, y, r) in BUTTONS.items():
            on = hypr.inside(cur, x, y, r, r)
            g = min(1.0, bgrow[name] + dt / ANIM) if on else max(0.0, bgrow[name] - dt / ANIM)
            bgrow[name] = g
            e = g * g * (3 - 2 * g)
            base, big = BUTTON_PT[name]
            size = base + (big - base) * e
            glyph = ICONS["pause" if name == "play" and player.status == "Playing" else name]
            # play/pause: dark glyph on the solid light circle; prev/next: soft white, full white on hover
            color = "#181825" if name == "play" else ("#FFFFFF" if g > 0.5 else "#FFFFFFB3")
            rise = int(MUSIC_RISE_PER_PT * (size - base))
            write(f"glow_{name}", " ", cache)
            write(f"icon_{name}", strut(f"<span size='{size:.1f}pt' rise='{rise}' foreground='{color}'>{glyph}</span>"), cache)
        write("cava", cava_markup(cava.levels, player.status == "Playing"), cache)

        flush(cache, lock_pid, can_signal)
        time.sleep(max(0.0, 1 / FPS - (time.monotonic() - now)))

    cava.stop()
    for name in os.listdir(OUT):
        if not name.startswith("."):
            os.remove(os.path.join(OUT, name))


if __name__ == "__main__":
    main()
