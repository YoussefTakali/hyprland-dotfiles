#!/usr/bin/python3
"""Match SDDM's display mode to the single active desktop monitor, with backups.

Run with sudo and explicit dimensions/rate, e.g.:
sudo python3 installer/session/repair-login-speed.py --width 2560 --height 1440 --refresh 99.95
No services are restarted; the next greeter uses the new mode.
"""
import argparse
import configparser
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--refresh", type=float, required=True)
    parser.add_argument("--fast-start", action="store_true", help="Skip Nix probes for Fedora's RPM Hyprland; record detailed login timings")
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Administrator access is needed to update /etc/sddm.conf.")
    if not (320 <= args.width <= 16384 and 200 <= args.height <= 16384 and 20 <= args.refresh <= 1000):
        parser.error("Invalid display dimensions or refresh rate")
    source = Path(__file__).with_name("sddm-display-setup.py")
    compile(source.read_text(), str(source), "exec")
    session_source = Path(__file__).with_name("sddm-wayland-session.sh")
    session_target = Path("/usr/local/libexec/hyprland-wayland-session")
    if args.fast_start:
        version = json.loads(subprocess.check_output(["/usr/bin/Hyprland", "--version-json"], timeout=5))
        if "nix" in version.get("flags", []):
            parser.error("Nix build detected; the RPM fast launcher does not apply")
        subprocess.run(["rpm", "-q", "hyprland"], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["/bin/sh", "-n", str(session_source)], check=True)
    settings = Path("/etc/sddm.conf")
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.optionxform = str
    config.read(settings)
    if args.fast_start:
        session_hook = config.get("Wayland", "SessionCommand", fallback="/etc/sddm/wayland-session")
        if session_hook not in ("/etc/sddm/wayland-session", str(session_target)):
            parser.error(f"Custom Wayland SessionCommand {session_hook!r}; refusing to replace it")
    original_hook = config.get("X11", "DisplayCommand", fallback="/etc/sddm/Xsetup")
    target = Path("/usr/local/libexec/hyprland-sddm-display")
    if original_hook not in ("/etc/sddm/Xsetup", str(target)):
        parser.error(f"Custom X11 DisplayCommand {original_hook!r}; refusing to replace it")
    backup = Path("/var/backups/login-speed") / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup.mkdir(parents=True)
    created = []
    paths = [settings, target, Path("/etc/sddm/hyprland-display.json")]
    if args.fast_start:
        paths.append(session_target)
    for path in paths:
        if path.exists():
            dest = backup / path.relative_to("/")
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
        else:
            created.append(str(path))
    (backup / "created-files.json").write_text(json.dumps(created, indent=2) + "\n")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    target.chmod(0o755)
    display = Path("/etc/sddm/hyprland-display.json")
    display.parent.mkdir(parents=True, exist_ok=True)
    display.write_text(json.dumps(vars(args), indent=2) + "\n")
    display.chmod(0o644)
    if not config.has_section("X11"):
        config.add_section("X11")
    config.set("X11", "DisplayCommand", str(target))
    if args.fast_start:
        shutil.copyfile(session_source, session_target)
        session_target.chmod(0o755)
        if not config.has_section("Wayland"):
            config.add_section("Wayland")
        config.set("Wayland", "SessionCommand", str(session_target))
    with settings.open("w") as stream:
        config.write(stream, space_around_delimiters=False)
    if shutil.which("restorecon"):
        subprocess.run(["restorecon", *map(str, paths)], check=True)
    print(f"SDDM display match installed for the next login screen. Backup: {backup}", flush=True)


if __name__ == "__main__":
    main()
