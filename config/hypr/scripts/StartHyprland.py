#!/usr/bin/env python3
"""Start the packaged compositor with its cached launcher options."""
import json
import os
from pathlib import Path
import subprocess
import sys


def warm_wallpaper_cache(home):
    """Advisory I/O only; decoding stays off the compositor launch path."""
    if not hasattr(os, "posix_fadvise"):
        return
    for name in ("wallpaper.bgrx", "wallpaper.qoi"):
        path = home / ".cache/hypr-startup-wallpaper" / name
        descriptor = None
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
            size = os.fstat(descriptor).st_size
            if 0 < size <= 64 * 1024 * 1024:
                os.posix_fadvise(descriptor, 0, size, os.POSIX_FADV_WILLNEED)
        except OSError:
            pass
        finally:
            if descriptor is not None:
                os.close(descriptor)


def launcher_signature():
    return [[str(path), path.stat().st_size, path.stat().st_mtime_ns]
            for path in map(Path, ("/usr/bin/Hyprland", "/usr/bin/start-hyprland"))]


def prepare_launcher(path):
    flags = []
    version = json.loads(subprocess.check_output(["/usr/bin/Hyprland", "--version-json"], timeout=3))
    rpm = subprocess.run(["rpm", "-q", "hyprland"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
    help_text = subprocess.check_output(["/usr/bin/start-hyprland", "--help"], text=True, timeout=3)
    if rpm.returncode == 0 and "nix" not in str(version.get("flags", [])).lower() and "--no-nixgl" in help_text:
        flags = ["--no-nixgl"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"signature": launcher_signature(), "flags": flags}) + "\n")


def launcher_flags(path):
    try:
        saved = json.loads(path.read_text())
        if saved["signature"] == launcher_signature() and saved["flags"] == ["--no-nixgl"]:
            return saved["flags"]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return []


if __name__ == "__main__":
    launcher = Path.home() / ".config/hypr/startup-launcher.json"
    arguments = sys.argv[1:]
    if arguments == ["--prepare-launcher"]:
        prepare_launcher(launcher)
    else:
        warm_wallpaper_cache(Path.home())
        os.execv("/usr/bin/start-hyprland", ["start-hyprland", *launcher_flags(launcher), *arguments])
