#!/usr/bin/env python3
"""Select our session without discarding existing AccountsService settings."""
import configparser
import argparse
import datetime
import os
from pathlib import Path
import pwd
import shutil
import tempfile

def write_config(path, config, owner=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            config.write(stream, space_around_delimiters=False)
            stream.flush()
            if path.exists():
                shutil.copymode(path, temporary)
            if owner is not None:
                os.chown(temporary, owner.pw_uid, owner.pw_gid)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('user')
    args = parser.parse_args()
    session = "hyprland-dotfiles"
    if os.geteuid() != 0:
        raise SystemExit("Administrator access and an account name are required.")
    user = pwd.getpwnam(args.user).pw_name
    if not (Path('/usr/share/wayland-sessions')/(session+'.desktop')).is_file():
        raise SystemExit('The requested session entry has not been installed.')
    path = Path("/var/lib/AccountsService/users") / user
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.optionxform = str
    if path.exists():
        config.read(path)
        backup = Path("/var/backups/hyprland-dotfiles-session") / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup.mkdir(parents=True)
        shutil.copy2(path, backup / user)
    if not config.has_section("User"):
        config.add_section("User")
    config.set("User", "Session", session)
    config.set("User", "XSession", session)
    write_config(path, config)
    # "Keep login screen" may mean an existing SDDM installation rather than GDM.
    manager = Path('/etc/systemd/system/display-manager.service')
    if manager.resolve().name == 'sddm.service':
        state = Path('/var/lib/sddm/state.conf')
        saved = configparser.ConfigParser(interpolation=None, strict=False)
        saved.optionxform = str
        if state.exists():
            saved.read(state)
            backup = Path('/var/backups/hyprland-dotfiles-session') / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
            backup.mkdir(parents=True)
            shutil.copy2(state, backup/'sddm-state.conf')
        if not saved.has_section('Last'):
            saved.add_section('Last')
        saved.set('Last', 'User', user)
        saved.set('Last', 'Session', '/usr/share/wayland-sessions/'+session+'.desktop')
        state.parent.mkdir(parents=True, exist_ok=True)
        with state.open('w') as stream:
            saved.write(stream, space_around_delimiters=False)
        record = pwd.getpwnam('sddm')
        os.chown(state, record.pw_uid, record.pw_gid)
