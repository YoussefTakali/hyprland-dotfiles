#!/usr/bin/env python3
"""Prepare/apply a reversible SDDM Hyprland greeter; never restart SDDM."""
import argparse
import configparser
import datetime
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile


def render(monitors, keyboard):
    # These values come from this computer, not a bundled PCI/monitor address.
    lines = ['-- Generated SDDM-only Hyprland greeter. No user apps or key bindings.',
             'local probe = io.popen("/usr/bin/bash /usr/local/libexec/hyprland-sddm-gpu")',
             'if probe then',
             '  local devices = (probe:read("*l") or ""):match("^(%S+)")',
             '  probe:close()',
             '  if devices then hl.env("AQ_DRM_DEVICES", devices) end',
             'end',
             'hl.env("XCURSOR_THEME", "Adwaita")',
             'hl.env("XCURSOR_SIZE", "24")',
             'hl.config({',
             '  misc = { disable_hyprland_logo = false, disable_splash_rendering = true,',
             '           force_default_wallpaper = 0, background_color = "rgb(30283e)" },',
             '  animations = { enabled = false },',
             '  xwayland = { enabled = false },',
             '  general = { gaps_in = 0, gaps_out = 0, border_size = 0 },',
             '  decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } },',
             '  cursor = { no_hardware_cursors = 1, sync_gsettings_theme = false },',
             '  input = { kb_layout = ' + json.dumps(keyboard['layout']) + ',',
             '            kb_variant = ' + json.dumps(keyboard['variant']) + ',',
             '            kb_model = ' + json.dumps(keyboard['model']) + ' },',
             '})',
             'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })']
    for monitor in monitors:
        if monitor.get('disabled') or monitor.get('mirrorOf', 'none') != 'none':
            continue
        spec = dict(output=monitor['name'], mode=f"{monitor['width']}x{monitor['height']}@{monitor['refreshRate']}",
                    position=f"{monitor['x']}x{monitor['y']}", scale=monitor['scale'],
                    transform=monitor.get('transform', 0), bitdepth=8)
        lines.append('hl.monitor({ ' + ', '.join(k + ' = ' + json.dumps(v) for k, v in spec.items()) + ' })')
    return '\n'.join(lines) + '\n'


def prepare(destination):
    monitors = json.loads(subprocess.check_output(['/usr/bin/hyprctl', '-j', 'monitors'], timeout=5))
    status = subprocess.check_output(['localectl', 'status'], text=True, env=dict(os.environ, LC_ALL='C'), timeout=5)
    settings = dict(line.strip().split(': ', 1) for line in status.splitlines() if ': ' in line)
    keyboard = dict(layout=settings.get('X11 Layout', 'us'), variant=settings.get('X11 Variant', ''), model=settings.get('X11 Model', 'pc105'))
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'greeter.lua').write_text(render(monitors, keyboard))
    gpu = Path(__file__).resolve().parents[2] / 'config/hypr/scripts/GpuPrimary.sh'
    shutil.copy2(gpu, destination / 'gpu-primary.sh')
    (destination / 'settings.json').write_text(json.dumps(dict(monitors=monitors, keyboard=keyboard), indent=2) + '\n')
    print('Prepared:', destination)
    print('Preserves the current Jake theme and user-session launcher; changes only the greeter backend.')


def apply(plan):
    if os.geteuid() != 0:
        raise SystemExit('Administrator authentication is required for /etc/sddm.conf.')
    if not Path('/usr/libexec/sddm-helper-start-wayland').is_file():
        raise SystemExit('The SDDM Wayland helper is missing; no files changed.')
    # Parse-check without starting a compositor before touching system settings.
    original_user = os.environ.get('PKEXEC_UID') or os.environ.get('SUDO_UID')
    if not original_user or original_user == '0':
        raise SystemExit('Run through pkexec/sudo from your desktop account.')
    verify_env = dict(os.environ)
    verify_env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
    check = subprocess.run(['runuser', '-u', __import__('pwd').getpwuid(int(original_user)).pw_name,
                            '--', '/usr/bin/Hyprland', '--verify-config', '--config', str(plan / 'greeter.lua')],
                           capture_output=True, text=True, timeout=15, env=verify_env)
    if check.returncode:
        raise SystemExit('Greeter config validation failed:\n' + check.stdout + check.stderr)
    paths = [Path('/etc/sddm.conf'), Path('/etc/sddm/hyprland-greeter.lua'),
             Path('/usr/local/libexec/hyprland-sddm-gpu')]
    backup = Path('/var/backups/greeter-handoff') / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True)
    missing = []
    for path in paths:
        if path.exists():
            dst = backup / path.relative_to('/')
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dst)
        else:
            missing.append(str(path))
    (backup / 'missing.json').write_text(json.dumps(missing))
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.optionxform = str
    config.read('/etc/sddm.conf')
    for section, values in {
        'General': {'DisplayServer': 'wayland'},
        'Wayland': {'CompositorCommand': '/usr/bin/start-hyprland --no-nixgl -- --config /etc/sddm/hyprland-greeter.lua'},
    }.items():
        if not config.has_section(section): config.add_section(section)
        for key, value in values.items(): config.set(section, key, value)
    paths[1].parent.mkdir(parents=True, exist_ok=True)
    paths[2].parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(plan / 'greeter.lua', paths[1]); paths[1].chmod(0o644)
    shutil.copyfile(plan / 'gpu-primary.sh', paths[2]); paths[2].chmod(0o755)
    with paths[0].open('w') as stream: config.write(stream, space_around_delimiters=False)
    subprocess.run(['restorecon', *map(str, paths)], check=True)
    apply_backdrop()
    print('Applied Wayland greeter. Reboot when ready: SDDM cannot reload this setting live.')
    print('Backup:', backup)
    print('Restore: sudo python3 ' + str(Path(__file__).resolve()) + ' --restore ' + str(backup))


def restore(backup):
    if os.geteuid() != 0: raise SystemExit('Administrator authentication required.')
    if backup.parent.resolve() != Path('/var/backups/greeter-handoff'):
        raise SystemExit('Expected a backup under /var/backups/greeter-handoff.')
    paths = ['/etc/sddm.conf', '/etc/sddm/hyprland-greeter.lua', '/usr/local/libexec/hyprland-sddm-gpu']
    missing = json.loads((backup / 'missing.json').read_text())
    for name in paths:
        path = Path(name)
        if name in missing: path.unlink(missing_ok=True)
        else: shutil.copy2(backup / path.relative_to('/'), path)
    subprocess.run(['restorecon', '/etc/sddm.conf'], check=True)
    print('Previous greeter configuration restored. No service restarted.')


def patch_login_theme(main, fields):
    if 'property bool unifiedLoading:' not in main:
        anchor = '    focus: true\n'
        if anchor not in main:
            raise ValueError('Unrecognized SDDM Main.qml; loading hook was not installed.')
        loading = '''
    // One visual scene spans authentication and desktop startup.
    property bool unifiedLoading: false
    function startLoading() { unifiedLoading = true; }
    JakeLoadingScene {
        anchors.fill: parent
        z: 1000
        visible: root.unifiedLoading
        animated: root.unifiedLoading
        MouseArea { anchors.fill: parent }
    }
'''
        main = main.replace(anchor, anchor + loading, 1)
    if 'root.startLoading()' not in fields:
        anchor = '        sddm.login(targetUser, password.text, sessionSelect.selectedSession)'
        failed = '        function onLoginFailed() {\n'
        if anchor not in fields or failed not in fields:
            raise ValueError('Unrecognized SDDM Input.qml; loading hook was not installed.')
        fields = fields.replace('    function triggerLogin() {\n',
                                '    function triggerLogin() {\n        if (root.unifiedLoading) return\n', 1)
        fields = fields.replace(anchor, '        root.startLoading()\n' + anchor, 1)
        fields = fields.replace(failed, failed + '            root.unifiedLoading = false\n', 1)
    return main, fields


def apply_backdrop():
    if os.geteuid() != 0:
        raise SystemExit('Administrator authentication required.')
    artwork = Path('/usr/share/sddm/themes/sddm-astronaut-theme/Backgrounds/jake_the_dog.png')
    metadata = artwork.parents[1] / 'metadata.desktop'
    if metadata.exists() and 'ConfigFile=Themes/preset-itachi-' in metadata.read_text():
        print('The selected Itachi preset already provides the matching loading frame.')
        return
    wallpaper = Path('/usr/share/hypr/wall0.png')
    greeter = Path('/etc/sddm/hyprland-greeter.lua')
    scene_dir = Path(__file__).resolve().parents[2] / 'config/quickshell/login-splash'
    shared_frame = scene_dir / 'transition.png'
    data = shared_frame.read_bytes() if shared_frame.is_file() else artwork.read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise SystemExit('Jake artwork must be a PNG image.')
    changes = {wallpaper: data}
    if shared_frame.is_file():
        theme = artwork.parents[1]
        main = theme / 'Main.qml'
        fields = theme / 'Components/Input.qml'
        main_text, fields_text = patch_login_theme(main.read_text(), fields.read_text())
        changes[main] = main_text.encode()
        changes[fields] = fields_text.encode()
        changes[theme / 'Components/JakeLoadingScene.qml'] = (scene_dir / 'JakeLoadingScene.qml').read_bytes()
        poster = scene_dir / 'jake.png'
        changes[theme / 'Components/jake.png'] = (poster if poster.is_file() else artwork).read_bytes()
    if greeter.exists():
        text = greeter.read_text()
        text = text.replace('disable_hyprland_logo = true', 'disable_hyprland_logo = false')
        text = text.replace('background_color = "rgb(8174b8)"', 'background_color = "rgb(30283e)"')
        changes[greeter] = text.encode()
    backup = Path('/var/backups/jake-backdrop') / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True)
    for path in changes:
        if path.exists():
            destination = backup / path.relative_to('/')
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
    try:
        for path, content in changes.items():
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
                stream.write(content)
                temporary = Path(stream.name)
            temporary.chmod(0o644)
            os.replace(temporary, path)
        subprocess.run(['restorecon', *map(str, changes)], check=True)
    except Exception:
        for path in changes:
            original = backup / path.relative_to('/')
            if original.exists():
                shutil.copy2(original, path)
            else:
                path.unlink(missing_ok=True)
        raise
    print('Installed Jake as the compositor startup wallpaper. Backup:', backup)


def fix_locale():
    if os.geteuid() != 0: raise SystemExit('Administrator authentication required.')
    locale = 'C.UTF-8'
    settings = Path('/etc/locale.conf')
    if settings.exists():
        for line in settings.read_text().splitlines():
            match = re.fullmatch(r'\s*LANG\s*=\s*[\"\x27]?([A-Za-z0-9_.@-]+)[\"\x27]?\s*', line)
            if match: locale = match[1]
    check = subprocess.run(['locale', 'charmap'], env=dict(os.environ, LANG=locale, LC_ALL=locale), capture_output=True, text=True)
    if check.returncode or check.stdout.strip() != 'UTF-8':
        raise SystemExit('System locale is not a usable UTF-8 locale; no files changed.')
    target = Path('/etc/systemd/system/sddm.service.d/20-utf8-locale.conf')
    backup = Path('/var/backups/greeter-handoff') / ('locale-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.mkdir(parents=True)
    if target.exists(): shutil.copy2(target, backup / target.name)
    else: (backup / 'created-path.txt').write_text(str(target) + '\n')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('[Service]\nEnvironment=LANG=' + locale + '\n')
    subprocess.run(['restorecon', str(target)], check=True)
    subprocess.run(['systemctl', 'daemon-reload'], check=True)
    print('SDDM UTF-8 environment installed for the next daemon start; no service restarted. Backup:', backup)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--prepare', type=Path)
    group.add_argument('--apply', type=Path)
    group.add_argument('--restore', type=Path)
    group.add_argument('--fix-locale', action='store_true')
    group.add_argument('--jake-backdrop', action='store_true')
    args = parser.parse_args()
    if args.jake_backdrop: apply_backdrop()
    elif args.fix_locale: fix_locale()
    elif args.apply: apply(args.apply.resolve())
    elif args.restore: restore(args.restore.resolve())
    else: prepare(args.prepare or Path.home() / '.local/state/greeter-handoff/candidate')
