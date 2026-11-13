#!/usr/bin/env python3
"""Add a separate display-manager session, preserving the stock session/hooks."""
import datetime
import argparse
import os
from pathlib import Path
import shutil
import subprocess

WRAPPER = '''#!/bin/sh
# Display manager already ran its distribution/user profile setup.
state="$HOME/.local/state/session-startup"
mkdir -p "$state"
read -r uptime idle < /proc/uptime
printf 'session-entry %s\\nprofile-complete %s\\n' "$uptime" "$uptime" >> "$state/launcher.log"
printf 'measurement-origin post-profile\\n' >> "$state/launcher.log"
export HYPRLAND_LOGIN_PROFILE=1
if [ -f "$HOME/.config/hypr/scripts/StartHyprland.py" ]; then
    exec /usr/bin/python3 "$HOME/.config/hypr/scripts/StartHyprland.py" "$@"
fi
exec /usr/bin/start-hyprland "$@"
'''
ENTRY = '''[Desktop Entry]
Name=Hyprland (Desktop dotfiles)
Comment=Hyprland with portable graphics and wallpaper startup
Exec=/usr/local/libexec/hyprland-dotfiles-session
TryExec=/usr/bin/start-hyprland
Type=Application
DesktopNames=Hyprland
'''


def install(root=Path("/"), backups=None, trial=False):
    if backups is None:
        backups = root / "var/backups/hyprland-dotfiles-session" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    files = [
        ("usr/local/libexec/hyprland-dotfiles-session", WRAPPER, 0o755),
        ("usr/share/wayland-sessions/hyprland-dotfiles.desktop", ENTRY, 0o644),
    ]
    if trial:
        trial_wrapper = WRAPPER.replace('StartHyprland.py" "$@"', 'StartHyprland.py" --native-trial "$@"')
        assert '--native-trial' in trial_wrapper
        trial_entry = ENTRY.replace('Name=Hyprland (Desktop dotfiles)', 'Name=Hyprland (Fast startup trial)').replace(
            'Exec=/usr/local/libexec/hyprland-dotfiles-session', 'Exec=/usr/local/libexec/hyprland-dotfiles-trial-session')
        files += [('usr/local/libexec/hyprland-dotfiles-trial-session', trial_wrapper, 0o755),
                  ('usr/share/wayland-sessions/hyprland-dotfiles-trial.desktop', trial_entry, 0o644)]
    for relative, text, mode in files:
        path = root / relative
        if path.exists() and path.read_text() == text:
            continue
        backups.mkdir(parents=True, exist_ok=True)
        if path.exists():
            dest = backups / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
        else:
            with (backups / "created-files.txt").open("a") as file:
                file.write("/" + relative + "\n")
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".new")
        temporary.write_text(text)
        temporary.chmod(mode)
        os.replace(temporary, path)
        if root == Path("/") and shutil.which("restorecon"):
            subprocess.run(["restorecon", str(path)], check=True)
    return backups


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trial', action='store_true', help='Also install the explicit experimental startup session')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Run through the installer with administrator access.")
    if not Path("/usr/bin/start-hyprland").exists():
        raise SystemExit("The native Hyprland launcher is missing.")
    print("Installed the Desktop dotfiles session. Backups:", install(trial=args.trial))
