#!/usr/bin/env python3
"""Choose or preview installed animated login presets with matching loading scenes."""
import argparse
import configparser
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

THEME = Path('/usr/share/sddm/themes/sddm-astronaut-theme')
SYSTEM_HELPER = Path('/usr/local/libexec/hyprland-login-themes.py')
IDS = ('jake', 'itachi-eyes', 'itachi-rain', 'itachi-shadows')


def preset_media(assets, catalog, key):
    if key not in catalog:
        return None
    preset = catalog[key]
    video, poster = (assets / preset[name] for name in ('video', 'poster'))
    if key == 'jake':
        if not video.is_file():
            video = THEME / 'Backgrounds/jake_the_dog.mp4'
        if not poster.is_file():
            poster = THEME / 'Backgrounds/jake_the_dog.png'
    if video.is_file() and poster.is_file():
        return video, poster
    return None


def configuration(base, key):
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.optionxform = str
    config.read_string(base)
    values = {'Background': f'Backgrounds/preset-{key}.mp4',
              'BackgroundPlaceholder': f'Backgrounds/preset-{key}.png', 'BackgroundSpeed': '1.0'}
    if key != 'jake':
        values.update(Font='Montserrat', FormPosition='left', FormBackgroundColor='#220d16',
                      BackgroundColor='#160b10', DimBackgroundColor='#160b10',
                      HeaderTextColor='#ffe7ef', DateTextColor='#ffe7ef', TimeTextColor='#ffe7ef',
                      LoginFieldBackgroundColor='#ffe7ef', PasswordFieldBackgroundColor='#ffe7ef',
                      LoginButtonBackgroundColor='#ffe7ef', LoginButtonTextColor='#8e304a',
                      HighlightBackgroundColor='#ef335a', DropdownBackgroundColor='#32131f')
    for name, value in values.items():
        config.set('General', name, '"' + value + '"')
    import io
    output = io.StringIO()
    config.write(output, space_around_delimiters=False)
    return output.getvalue()


def commit(changes):
    if os.geteuid() != 0:
        raise SystemExit('Administrator authentication is required for the login screen.')
    changes = {path: data for path, data in changes.items() if not path.exists() or path.read_bytes() != data}
    if not changes:
        print('Login theme files are already installed.')
        return
    backup = Path('/var/backups/login-themes') / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True)
    created = []
    for path in changes:
        if path.exists():
            destination = backup / path.relative_to('/')
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
        else:
            created.append(str(path))
    (backup / 'created.json').write_text(json.dumps(created))
    try:
        for path, data in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
                stream.write(data)
                temporary = Path(stream.name)
            temporary.chmod(0o644)
            os.replace(temporary, path)
        if shutil.which('restorecon'):
            subprocess.run(['restorecon', *map(str, changes)], check=True)
    except Exception:
        for path in changes:
            original = backup / path.relative_to('/')
            if original.exists():
                shutil.copy2(original, path)
            else:
                path.unlink(missing_ok=True)
        raise
    print('Login theme files installed. Backup:', backup)


def system_install(assets):
    catalog = json.loads((assets / 'catalog.json').read_text())
    base = (THEME / 'Themes/jake_the_dog.conf').read_text()
    changes = {}
    for key in IDS:
        media = preset_media(assets, catalog, key)
        if media is None:
            continue
        for source, extension in zip(media, ('mp4', 'png')):
            changes[THEME / 'Backgrounds' / f'preset-{key}.{extension}'] = source.read_bytes()
        changes[THEME / 'Themes' / f'preset-{key}.conf'] = configuration(base, key).encode()
    commit(changes)


def prepare(assets, key, capture):
    catalog = json.loads((assets / 'catalog.json').read_text())
    media = preset_media(assets, catalog, key)
    if media is None:
        raise RuntimeError(f'Login media for {key} is unavailable.')
    video, poster = media
    plan = Path.home() / '.local/state/login-themes' / key
    plan.mkdir(parents=True, exist_ok=True)
    scene = (assets / 'JakeLoadingScene.qml').read_text()
    if key != 'jake':
        for old, new in {'#555080': '#160b10', '#10242455': '#10160b10', '#00242455': '#00160b10',
                         '#b8242455': '#c0160b10', '#d8d8ff': '#ffe7ef', '#f2bd68': '#ef335a',
                         '#dedcf3': '#f4dce5', '#cbc8e9': '#d8b5c2', '#bdb7df': '#bd8b9e'}.items():
            scene = scene.replace(old, new)
    (plan / 'JakeLoadingScene.qml').write_text(scene)
    shutil.copy2(poster, plan / 'jake.png')
    shutil.copy2(assets / 'shell.qml', plan / 'shell.qml')
    preview = plan / 'preview'
    preview.mkdir(exist_ok=True)
    for item in THEME.iterdir():
        if item.name in ['metadata.desktop', 'Components', 'Themes', 'Backgrounds']:
            continue
        link = preview / item.name
        if not link.exists():
            link.symlink_to(item, target_is_directory=item.is_dir())
    metadata = (THEME / 'metadata.desktop').read_text()
    metadata = '\n'.join('ConfigFile=Themes/selected.conf' if line.startswith('ConfigFile=') else line
                         for line in metadata.splitlines()) + '\n'
    (preview / 'metadata.desktop').write_text(metadata)
    for name in ['Components', 'Themes', 'Backgrounds']:
        (preview / name).mkdir(exist_ok=True)
    for item in (THEME / 'Components').iterdir():
        if item.name in ['JakeLoadingScene.qml', 'jake.png']:
            continue
        link = preview / 'Components' / item.name
        if not link.exists():
            link.symlink_to(item)
    for name in ['JakeLoadingScene.qml', 'jake.png']:
        shutil.copy2(plan / name, preview / 'Components' / name)
    config = configuration((THEME / 'Themes/jake_the_dog.conf').read_text(), key)
    (preview / 'Themes/selected.conf').write_text(config)
    for source, extension in zip((video, poster), ('mp4', 'png')):
        link = preview / 'Backgrounds' / f'preset-{key}.{extension}'
        if link.is_symlink() and link.readlink() != source:
            link.unlink()
        if not link.exists():
            link.symlink_to(source)
    if capture:
        frame = plan / 'transition.png'
        frame.unlink(missing_ok=True)
        env = dict(os.environ, QT_NO_XDG_DESKTOP_PORTAL='1', JAKE_SPLASH_EXPORT=str(frame))
        subprocess.run(['qs', '-n', '-p', str(plan / 'shell.qml')], env=env, check=True, timeout=10)
        if not frame.is_file():
            raise RuntimeError('The selected loading scene could not be rendered.')
    return plan


def system_apply(plan, key):
    metadata = (THEME / 'metadata.desktop').read_text()
    metadata = '\n'.join('ConfigFile=Themes/preset-' + key + '.conf' if line.startswith('ConfigFile=') else line
                         for line in metadata.splitlines()) + '\n'
    changes = {THEME / 'metadata.desktop': metadata.encode(),
               THEME / 'Components/JakeLoadingScene.qml': (plan / 'JakeLoadingScene.qml').read_bytes(),
               THEME / 'Components/jake.png': (plan / 'jake.png').read_bytes(),
               Path('/usr/share/hypr/wall0.png'): (plan / 'transition.png').read_bytes()}
    if not (THEME / 'Themes' / f'preset-{key}.conf').is_file():
        raise RuntimeError('Install the login preset catalogue first.')
    commit(changes)


def system_check(plans):
    if os.geteuid() != 0:
        raise SystemExit('Administrator authentication is required for the theme round-trip test.')
    paths = [THEME / 'metadata.desktop', THEME / 'Components/JakeLoadingScene.qml',
             THEME / 'Components/jake.png', Path('/usr/share/hypr/wall0.png')]
    original = {path: path.read_bytes() for path in paths}
    try:
        for key in IDS:
            if not (THEME / 'Themes' / f'preset-{key}.conf').is_file():
                continue
            plan = plans / key
            system_apply(plan, key)
            assert 'ConfigFile=Themes/preset-' + key + '.conf' in paths[0].read_text()
            assert paths[3].read_bytes() == (plan / 'transition.png').read_bytes()
            print('PASS: protected theme selection and matching startup frame:', key, flush=True)
    finally:
        commit(original)
    assert all(path.read_bytes() == data for path, data in original.items())
    print('PASS: original login selection and loading assets restored exactly.')


def main():
    global THEME
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, default=Path.home() / '.local/share/hypr-login-themes')
    parser.add_argument('--apply', choices=IDS)
    parser.add_argument('--preview', choices=IDS)
    parser.add_argument('--prepare', choices=IDS)
    parser.add_argument('--system-install', action='store_true')
    parser.add_argument('--system-apply', choices=IDS)
    parser.add_argument('--system-check', action='store_true')
    parser.add_argument('--plan', type=Path)
    parser.add_argument('--theme-dir', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    assets = args.assets.resolve()
    if args.system_install or args.system_apply or args.system_check:
        if os.geteuid() != 0:
            parser.error('Administrator authentication is required.')
    if args.system_install:
        if args.theme_dir is not None:
            THEME = args.theme_dir
        system_install(assets)
        return
    if args.system_apply:
        system_apply(args.plan.resolve(), args.system_apply)
        return
    if args.system_check:
        system_check(args.plan.resolve())
        return
    if args.prepare:
        print(prepare(assets, args.prepare, False))
        return
    key = args.apply or args.preview
    preview = bool(args.preview)
    catalog = json.loads((assets / 'catalog.json').read_text())
    if not key:
        available = [(name, media) for name in IDS if (media := preset_media(assets, catalog, name))]
        if not available:
            subprocess.run(['notify-send', 'Login themes', 'No installed login artwork is available.'])
            return
        choices = '\n'.join(catalog[name]['title'] + '\0icon\x1f' + str(media[1]) for name, media in available)
        selected = subprocess.run(['rofi', '-dmenu', '-i', '-p', 'Login theme', '-format', 'i', '-no-custom',
                                   '-kb-custom-1', 'Shift+Return', '-kb-accept-alt', '', '-mesg', 'Enter applies · Shift+Enter previews'],
                                  input=choices, text=True, capture_output=True)
        if selected.returncode not in [0, 10] or not selected.stdout.strip():
            return
        key = available[int(selected.stdout.strip())][0]
        preview = selected.returncode == 10
    if not preview and not SYSTEM_HELPER.is_file():
        raise SystemExit('Install the SDDM option in Desktop Setup to enable applying login themes.')
    plan = prepare(assets, key, not preview)
    if preview:
        subprocess.run(['sddm-greeter-qt6', '--test-mode', '--theme', str(plan / 'preview')])
        return
    subprocess.run(['pkexec', '/usr/bin/python3', '-I', str(SYSTEM_HELPER), '--system-apply', key,
                    '--plan', str(plan)], check=True)
    active = Path.home() / '.config/quickshell/login-splash'
    for name in ['JakeLoadingScene.qml', 'jake.png', 'transition.png']:
        shutil.copy2(plan / name, active / name)
    subprocess.run(['python3', str(Path.home() / '.config/hypr/scripts/StartupWallpaperCache.py')], check=True)
    (plan.parent / 'active.json').write_text(json.dumps({'id': key, 'title': catalog[key]['title']}) + '\n')
    subprocess.run(['notify-send', 'Login theme changed', catalog[key]['title'] + '\nApplies on the next login screen.'])


if __name__ == '__main__':
    main()
