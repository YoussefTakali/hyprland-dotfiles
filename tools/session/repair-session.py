#!/usr/bin/env python3
"""Repair the installed desktop using this checkout, with backups."""
from pathlib import Path
import datetime
import json
import shutil
import subprocess

home = Path.home()
repo = Path(__file__).resolve().parents[2]
backup = home / '.local/state/session-repair-backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
backup.mkdir(parents=True)
created = []
try:
    active_preset = json.loads((home / '.local/state/login-themes/active.json').read_text()).get('id', 'jake')
except (OSError, ValueError):
    active_preset = 'jake'

def write(path, text, executable=False):
    data = text.encode() if isinstance(text, str) else text
    if path.exists() and path.read_bytes() == data:
        return
    if path.exists():
        # Repositories can be checked out anywhere, including outside $HOME.
        try:
            relative = path.relative_to(home)
        except ValueError:
            relative = Path('external') / path.resolve().relative_to('/')
        dest = backup / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
    else:
        created.append(str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    if executable:
        path.chmod(0o755)

roots = [home / '.config']
for root in roots:
    # Reapply the first-login wallpaper fix from its canonical repository script.
    startup = repo / 'config/hypr/scripts/StartupWallpaper.sh'
    if startup.is_file():
        write(root / 'hypr/scripts/StartupWallpaper.sh', startup.read_text(), True)
    for rel in ('hypr/scripts/SessionInit.sh', 'hypr/scripts/StartSwaync.py', 'hypr/scripts/LoginThemes.py', 'hypr/scripts/OverviewToggle.sh',
                'hypr/scripts/StartupWallpaperCache.py', 'hypr/scripts/WallpaperDaemonReady.sh', 'hypr/scripts/WallustSwww.sh',
                'hypr/lua/hyprlang.lua', 'systemd/user/hyprland-dotfiles-session.target',
                'xdg-desktop-portal/hyprland-portals.conf', 'systemd/user/swaync.service.d/20-hyprland-theme.conf'):
        source = repo / 'config' / rel
        write(root / rel, source.read_text(), source.suffix == '.sh')
    for rel in ('quickshell/login-splash/shell.qml', 'quickshell/login-splash/JakeLoadingScene.qml',
                'quickshell/login-splash/jake.png', 'quickshell/login-splash/transition.png'):
        if active_preset in ('itachi-eyes', 'itachi-rain', 'itachi-shadows') and Path(rel).name != 'shell.qml' and (root / rel).exists():
            continue
        source = repo / 'config' / rel
        if source.is_file():
            write(root / rel, source.read_bytes())
    p = root / 'hypr/configs/Keybinds.conf'
    if p.exists():
        defaults = root / 'hypr/UserConfigs/01-UserDefaults.conf'
        configures_new_window = defaults.is_file() and any(
            line.startswith('$files') and '--new-window' in line.split('#', 1)[0]
            for line in defaults.read_text().splitlines()
        )
        command = '$files' if configures_new_window else '$files --new-window'
        write(p, p.read_text().replace(
            'bindd = $mainMod, E, file manager, exec, $files',
            f'bindd = $mainMod, E, new file manager window, exec, {command}'))
    p = root / 'hypr/UserConfigs/WindowRules.conf'
    if p.exists() and 'match:namespace ^(jake-login-splash)$' not in p.read_text():
        write(p, p.read_text().rstrip() + '\n\n# Show the login splash without an entry animation.\n'
              'layerrule = match:namespace ^(jake-login-splash)$, no_anim on\n')
    p = root / 'hypr/configs/SystemSettings.conf'
    if p.exists():
        text = p.read_text().replace('  disable_hyprland_logo = true', '  disable_hyprland_logo = false')
        text = text.replace('  background_color = rgb(8174b8) # Jake lavender while the first wallpaper surface loads',
                            '  background_color = rgb(30283e) # Dark edge color while the image is decoded')
        if 'force_default_wallpaper =' not in text:
            text = text.replace('  disable_splash_rendering = true',
                                '  disable_splash_rendering = true\n  force_default_wallpaper = 0 # Jake compositor startup asset')
        write(p, text)
    for rel in ['hypr/hyprland.conf', 'hypr/configs/Startup_Apps.conf', 'hypr/UserConfigs/Startup_Apps.conf']:
        p = root / rel
        if not p.exists():
            continue
        lines = p.read_text().splitlines()
        lines = [line for line in lines if line != '# Initialize the graphical session and screen-sharing portals.' and 'exec-shutdown = systemctl --user stop hyprland-dotfiles-session.target' not in line and not (
            line.strip().startswith('exec-once') and any(s in line for s in (
                'dbus-update-activation-environment', 'systemctl --user import-environment',
                'systemctl --user start hyprland-session.service', 'SessionInit.sh',
                'qs -c overview', 'StartupWallpaper.sh', 'swww-daemon --format xrgb',
                'sleep 2 && ~/.config/hypr/UserScripts/LiveWallpaper.sh --restore',
                'sleep 2 && (swww query')))]
        if rel == 'hypr/configs/Startup_Apps.conf':
            lines = ['exec-once = $HOME/.config/hypr/scripts/StartupWallpaper.sh',
                     '# Initialize the graphical session and screen-sharing portals.',
                     'exec-once = $HOME/.config/hypr/scripts/SessionInit.sh',
                     'exec-shutdown = systemctl --user stop hyprland-dotfiles-session.target',
                     '# Overview starts on demand through OverviewToggle.sh.'] + lines
        write(p, '\n'.join(lines) + '\n')
    p = root / 'hypr/scripts/PortalHyprland.sh'
    if p.exists():
        write(p, '#!/usr/bin/env bash\n# Repair portals through systemd; never spawn duplicate backends.\nexec "$HOME/.config/hypr/scripts/SessionInit.sh" --restart\n', True)
    p = root / 'quickshell/lockscreen/shell.qml'
    if p.exists():
        text = p.read_text().replace('interval: 760                       // let the iris finish opening, then really unlock',
                                     'interval: 180                       // brief transition after PAM succeeds')
        if 'root.pendingPassword = "";\n            root.busy = false;' not in text:
            text = text.replace('root.busy = false;\n            if (result',
                                'root.pendingPassword = "";\n            root.busy = false;\n            if (result')
            text = text.replace('onError: error => {\n            root.busy',
                                'onError: error => {\n            root.pendingPassword = "";\n            root.busy')
        text = text.replace('if (busy || password.length === 0)', 'if (busy || unlocking || password.length === 0)')
        write(p, text)
    p = root / 'quickshell/lockscreen/LockFog.qml'
    if p.exists():
        write(p, p.read_text().replace('view.unlocking ? 750 : 1100', 'view.unlocking ? 160 : 350')
              .replace('view.unlocking ? 300 : 900', 'view.unlocking ? 160 : 350'))

assets = repo / 'home/login-themes'
scenes = repo / 'config/quickshell/login-splash'
for source in (*assets.iterdir(), scenes/'JakeLoadingScene.qml', scenes/'shell.qml'):
    if source.is_file():
        write(home / '.local/share/hypr-login-themes' / source.name, source.read_bytes())
(backup / 'created-files.txt').write_text('\n'.join(created) + '\n')
print('Applied session, portal, duplicate startup, and lock transition repairs.')
print('Backups:', backup)
subprocess.run(['python3', str(home / '.config/hypr/scripts/StartupWallpaperCache.py')], check=False)
result = subprocess.run(['bash', str(home / '.config/hypr/scripts/SessionInit.sh'), '--restart'])
if result.returncode:
    print('Live activation unavailable. Log out and in, or run in a desktop terminal:')
    print('bash ~/.config/hypr/scripts/SessionInit.sh --restart')
