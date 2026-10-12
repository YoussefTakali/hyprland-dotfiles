#!/usr/bin/env python3
# Drag-to-seek for the hyprlock progress bar.
# Started by hyprlock's onclick (fires on mouse press). While the left button is
# held it follows the cursor and writes a preview fraction that MusicUId.py draws;
# on release it seeks the player to that spot.
import fcntl, glob, json, os, select, socket, struct, subprocess, sys, time

# Bar geometry — must match hyprlock.conf / MusicUId.py
BAR_OFFSET_X = -25      # label position x (halign = center)
BAR_W = 316.0           # fill width in px (bar minus its rounded ends)

RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
PREVIEW = os.path.join(RUN, "hyprlock-scrub")
BTN_LEFT, EV_KEY = 0x110, 0x01
EVIOCGKEY = (2 << 30) | (96 << 16) | (ord("E") << 8) | 0x18
EVENT = struct.Struct("llHHi")


HYPR_SOCK = os.path.join(RUN, "hypr", os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""), ".socket.sock")


def cursor_x():
    # Hyprland IPC socket directly: far cheaper than spawning hyprctl every frame
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(HYPR_SOCK)
            s.sendall(b"cursorpos")
            return float(s.recv(256).decode().split(",")[0])
    except (OSError, ValueError):
        return float(subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True).stdout.split(",")[0])


def cursor_frac(mon):
    x = cursor_x()
    left = mon["x"] + mon["width"] / mon["scale"] / 2 + BAR_OFFSET_X - BAR_W / 2
    f = (x - left) / BAR_W
    return min(max(f, 0.0), 1.0)


def pointer_devices():
    devs = []
    for path in glob.glob("/dev/input/event*"):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        keys = bytearray(96)
        try:
            fcntl.ioctl(fd, EVIOCGKEY, keys)
        except OSError:
            os.close(fd)
            continue
        devs.append((fd, bool(keys[BTN_LEFT // 8] & (1 << (BTN_LEFT % 8)))))
    return devs


def main():
    # hyprlock reads its commands' output until EOF; drop any pipe ends inherited
    # from it so a long-running helper can't keep hyprlock waiting (it hangs on exit)
    os.closerange(3, os.sysconf("SC_OPEN_MAX"))
    lock = open(os.path.join(RUN, "hyprlock-scrub.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return  # already dragging
    length = subprocess.run(["playerctl", "metadata", "mpris:length"], capture_output=True, text=True).stdout.strip()
    if not length.isdigit() or int(length) == 0:
        return
    pos = json.loads(subprocess.run(["hyprctl", "cursorpos", "-j"], capture_output=True, text=True).stdout)
    mons = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True).stdout)
    mon = next((m for m in mons if m["x"] <= pos["x"] < m["x"] + m["width"] / m["scale"]), mons[0])

    devs = pointer_devices()
    held = [fd for fd, down in devs if down]
    frac = cursor_frac(mon)
    deadline = time.time() + 30
    # Mouse button held → follow until release. Touchpad tap (no button) → seek right away.
    while held and time.time() < deadline:
        with open(PREVIEW, "w") as f:
            f.write(f"{frac:.4f}")
        r, _, _ = select.select(held, [], [], 0.008)
        for fd in r:
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, typ, code, val = EVENT.unpack_from(data, i)
                if typ == EV_KEY and code == BTN_LEFT and val == 0:
                    held.remove(fd)
                    break
        frac = cursor_frac(mon)

    subprocess.run(["playerctl", "position", f"{int(length) / 1e6 * frac:.2f}"])
    time.sleep(0.3)  # let the player report the new position before dropping the preview
    try:
        os.remove(PREVIEW)
    except FileNotFoundError:
        pass


if __name__ == "__main__":
    main()
