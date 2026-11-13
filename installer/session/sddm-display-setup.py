#!/usr/bin/python3
"""Keep a single-monitor SDDM greeter in the desktop's resolution/refresh.

Installed by repair-login-speed.py. Unsupported modes and multiple connected
outputs are left alone; a display setup failure must never block the greeter.
"""
import json
from pathlib import Path
import re
import subprocess
import sys


def select_mode(query, width, height, refresh):
    connected = []
    current = None
    for line in query.splitlines():
        match = re.match(r"^(\S+) (connected|disconnected)\b", line)
        if match:
            current = None
            if match[2] == "connected":
                current = {"name": match[1], "rates": []}
                connected.append(current)
        elif current is not None:
            mode = re.match(r"^\s+(\d+)x(\d+)\s+(.+)$", line)
            if mode and (int(mode[1]), int(mode[2])) == (width, height):
                for token in mode[3].split():
                    rate = re.match(r"^(\d+(?:\.\d+)?)[*+]*$", token)
                    if rate:
                        current["rates"].append((float(rate[1]), "*" in token))
    if len(connected) != 1:
        return None
    output = connected[0]
    candidates = [item for item in output["rates"] if abs(item[0] - refresh) < 0.1]
    if not candidates or any(active for _, active in candidates):
        return None
    return ["/usr/bin/xrandr", "--output", output["name"], "--mode",
            f"{width}x{height}", "--rate", str(min(candidates, key=lambda item: abs(item[0] - refresh))[0])]


def main():
    # Preserve the existing distribution/administrator keyboard and display hook.
    subprocess.run(["/etc/sddm/Xsetup"], timeout=15, check=False)
    settings = json.loads(Path("/etc/sddm/hyprland-display.json").read_text())
    query = subprocess.run(["/usr/bin/xrandr", "--query"], capture_output=True,
                           text=True, timeout=5, check=True).stdout
    command = select_mode(query, settings["width"], settings["height"], settings["refresh"])
    if command:
        subprocess.run(command, timeout=5, check=True)
        print("SDDM matched desktop display:", " ".join(command), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print("SDDM display match skipped:", exc, file=sys.stderr)
