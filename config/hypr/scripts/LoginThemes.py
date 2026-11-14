#!/usr/bin/env python3
"""Login screen settings: pick the layout, a background for each layout, and colors.

  LoginThemes.py                     menu (Super+Ctrl+Alt+L)
  LoginThemes.py --sync              rebuild the login screen from the settings and
                                     the desktop (runs on every wallpaper change)
  LoginThemes.py --layout NAME       tiles | terminal | rofi | bar | editorial | japanese
  LoginThemes.py --background SRC    for the current layout: desktop | artwork | a file
  LoginThemes.py --position POS      for the current layout: left | center | right
  LoginThemes.py --colors MODE       background | desktop
  LoginThemes.py --save-preset NAME  save the current layout + background + position + colors
  LoginThemes.py --preset NAME       switch to a saved preset (--delete-preset NAME removes it)
  LoginThemes.py --preview           open the login screen in the SDDM test greeter
  LoginThemes.py --status

Nothing here needs a password: the theme reads Desktop/login.conf in a folder the
installer gave you (installer/session/install-sddm.sh). After editing the theme's
QML, reinstall it with:
  sudo /usr/local/libexec/sddm-login-theme --install <dotfiles>/installer/session/hypr-login-styles
"""
import argparse
import colorsys
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HOME = Path.home()
THEME = Path('/usr/share/sddm/themes/hypr-login-styles')
OUT = THEME / 'Desktop'
ASTRONAUT = Path('/usr/share/sddm/themes/sddm-astronaut-theme')
ARTWORK = ASTRONAUT / 'Backgrounds/japanese_aesthetic.png'
JAPANESE = ASTRONAUT / 'Themes/japanese_aesthetic.conf'
SETTINGS = HOME / '.config/hypr/login-screen.json'
CACHE = HOME / '.cache/hypr-login-screen'
WALL = HOME / '.config/hypr/wallpaper_effects/.wallpaper_current'
LIVE = HOME / '.config/hypr/wallpaper_effects/.live_wallpaper'
PALETTE = HOME / '.config/hypr/wallust/wallust-hyprland.conf'
DECORATIONS = HOME / '.config/hypr/UserConfigs/UserDecorations.conf'
WALLPAPERS = HOME / 'Pictures/wallpapers'
FONT = 'JetBrainsMono Nerd Font'
VIDEO = ('.mp4', '.mkv', '.mov', '.webm', '.m4v', '.avi')
IMAGE = ('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif')
LAYOUTS = {   # key: (Style value in the theme, description)
    'tiles': ('Tiles', 'Hyprland windows: tiles, gaps, gradient border'),
    'terminal': ('Terminal', 'kitty window with fastfetch and a login prompt'),
    'rofi': ('Rofi', 'launcher: password, sessions and power in one list'),
    'bar': ('Bar', 'vertical waybar with a notification to sign in'),
    'editorial': ('Editorial', 'magazine page: huge thin clock beside the picture'),
    'japanese': ('Japanese', 'Japanese Aesthetic (the original astronaut screen)'),
}
# Where the login form sits when you haven't picked a position for that layout.
DEFAULT_POSITION = {'tiles': 'right', 'terminal': 'center', 'rofi': 'center', 'bar': 'left',
                    'editorial': 'left', 'japanese': 'left'}
POSITIONS = ('left', 'center', 'right')


# ---- settings ---------------------------------------------------------------------
def load():
    try:
        settings = json.loads(SETTINGS.read_text())
    except (OSError, ValueError):
        settings = {}
    settings.setdefault('layout', 'tiles')
    settings.setdefault('backgrounds', {})
    settings.setdefault('colors', 'background')
    settings.setdefault('positions', {})
    settings.setdefault('presets', {})
    if settings['layout'] not in LAYOUTS:
        settings['layout'] = 'tiles'
    return settings


def save(settings):
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS.write_text(json.dumps(settings, indent=1) + '\n')


def background_choice(settings, layout):
    return settings['backgrounds'].get(layout) or ('artwork' if layout == 'japanese' else 'desktop')


def position_choice(settings, layout):
    return settings['positions'].get(layout) or DEFAULT_POSITION[layout]


def preset_summary(preset):
    return f"{LAYOUTS[preset['layout']][0]} · {describe(preset['background'])} · {preset['position']} · {preset['colors']} colors"


def save_preset(settings, name):
    layout = settings['layout']
    settings['presets'][name] = {'layout': layout, 'background': background_choice(settings, layout),
                                 'position': position_choice(settings, layout), 'colors': settings['colors']}


def apply_preset(settings, name):
    preset = settings['presets'][name]
    settings['layout'] = preset['layout']
    settings['backgrounds'][preset['layout']] = preset['background']
    settings['positions'][preset['layout']] = preset['position']
    settings['colors'] = preset['colors']


def describe(choice):
    if choice == 'desktop':
        return 'my desktop wallpaper (follows every change)'
    if choice == 'artwork':
        return 'Japanese Aesthetic artwork'
    return Path(choice).name


# ---- media ------------------------------------------------------------------------
def source_for(choice):
    if choice == 'desktop':
        if LIVE.is_file():
            live = Path(LIVE.read_text().strip())
            if live.is_file():
                return live
        return WALL
    if choice == 'artwork':
        return ARTWORK
    path = Path(choice)
    return path if path.is_file() else WALL


def key_of(path):
    info = path.stat()
    return hashlib.sha1(f'{path}:{info.st_size}:{info.st_mtime_ns}'.encode()).hexdigest()[:12]


def still_name(source):
    return f'bg-{key_of(source)}.jpg'


def atomic(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.tmp-', delete=False) as stream:
        stream.write(data)
        temporary = Path(stream.name)
    temporary.chmod(0o644)
    os.replace(temporary, path)


def still_of(source, key):
    """A JPEG of the picture (or of the video's first frame), at most 2560x1440."""
    still = OUT / f'bg-{key}.jpg'
    if still.is_file():
        return still
    from PIL import Image
    temporary = OUT / f'.tmp-{key}.jpg'
    if source.suffix.lower() in VIDEO:
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source), '-frames:v', '1',
                        '-vf', 'scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080',
                        '-q:v', '2', str(temporary)], check=True)
    else:
        with Image.open(source) as image:
            image = image.convert('RGB')
        image.thumbnail((2560, 1440), Image.Resampling.LANCZOS)
        image.save(temporary, format='JPEG', quality=92)
    temporary.chmod(0o644)
    os.replace(temporary, still)
    return still


def video_of(source, key):
    """A 1080p H.264 loop the greeter can play smoothly (made once per video)."""
    video = OUT / f'bg-{key}.mp4'
    if not video.is_file():
        temporary = OUT / f'.tmp-{key}.mp4'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source), '-t', '30', '-an',
                        '-vf', 'scale=1920:1080:force_original_aspect_ratio=increase:flags=lanczos,'
                               'crop=1920:1080,format=yuv420p',
                        '-fpsmax', '60', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '21',
                        '-movflags', '+faststart', str(temporary)], check=True)
        temporary.chmod(0o644)
        os.replace(temporary, video)
    return video


# ---- colors -----------------------------------------------------------------------
def desktop_palette():
    colors = dict(re.findall(r'^\$(\w+)\s*=\s*rgb\(([0-9A-Fa-f]{6})\)', PALETTE.read_text(), re.M))
    return {k: '#' + v.lower() for k, v in colors.items()}


def palette_of(still, key):
    """wallust's palette for any picture, without touching the desktop's colors."""
    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / f'palette-{key}.json'
    if cached.is_file():
        return json.loads(cached.read_text())
    out = subprocess.run(['wallust', 'run', '-s', '-T', '-q', '--no-hooks', '--print-scheme', str(still)],
                         capture_output=True, text=True, timeout=60).stdout
    colors = re.findall(r'#[0-9A-Fa-f]{6}', out)
    if len(colors) < 16:
        raise RuntimeError('wallust gave no palette')
    p = {f'color{i}': c.lower() for i, c in enumerate(colors[:16])}
    r, g, b = (int(p['color0'][i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    p['background'] = '#%02x%02x%02x' % tuple(round(v * 255) for v in colorsys.hls_to_rgb(h, min(l, .11), s))
    p['foreground'] = p['color15']
    cached.write_text(json.dumps(p))
    return p


# ---- config -----------------------------------------------------------------------
def rounding():
    match = DECORATIONS.is_file() and re.search(r'^\s*rounding\s*=\s*(\d+)', DECORATIONS.read_text(), re.M)
    return match.group(1) if match else '12'


def system_info():
    import platform
    import pwd
    import socket
    os_name = 'Linux'
    try:
        os_name = re.search(r'^PRETTY_NAME="?([^"\n]*)', Path('/etc/os-release').read_text(), re.M).group(1)
    except (OSError, AttributeError):
        pass

    def gsetting(key):
        try:
            return subprocess.run(['gsettings', 'get', 'org.gnome.desktop.interface', key], capture_output=True,
                                  text=True, timeout=3).stdout.strip().strip("'")
        except (OSError, subprocess.SubprocessError):
            return ''
    return {'InfoHost': socket.gethostname().split('.')[0], 'InfoOS': os_name, 'InfoKernel': platform.release(),
            'InfoWM': 'Hyprland', 'InfoShell': Path(pwd.getpwuid(os.getuid()).pw_shell).name,
            'InfoGtk': gsetting('gtk-theme'), 'InfoIcons': gsetting('icon-theme'), 'InfoTerminal': 'kitty'}


def font_dir():
    """The system folder holding the JetBrainsMono Thin face; the greeter's user
    cannot read fonts under a home folder."""
    try:
        out = subprocess.run(['fc-list', f'{FONT}:style=Thin', 'file'], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ''
    for line in out.splitlines():
        path = Path(line.split(':', 1)[0].strip())
        if path.name == 'JetBrainsMonoNerdFont-Thin.ttf' and not path.is_relative_to(HOME):
            return str(path.parent)
    return ''


def config_text(layout, background, placeholder, palette, position='left'):
    values = {'Style': LAYOUTS[layout][0], 'Position': position, 'Background': background, 'BackgroundPlaceholder': placeholder,
              'ColorBackground': palette['background'], 'ColorForeground': palette['foreground'],
              'Font': FONT, 'FontDir': font_dir(), 'Rounding': rounding(), **system_info()}
    values.update({f'Color{i}': palette[f'color{i}'] for i in range(16)})
    if layout == 'japanese':
        # Every key of the original preset, with the chosen background.
        for key, value in re.findall(r'^(\w+)=(.*)$', JAPANESE.read_text(), re.M):
            if key not in ('Background', 'BackgroundPlaceholder'):
                values[key] = value.strip().strip('"')
        values.update(HideVirtualKeyboard='true', ScreenWidth='', ScreenHeight='',
                      FormPosition=position, VirtualKeyboardPosition=position)
        if Path(background) != ARTWORK and not str(background).endswith(still_name(ARTWORK)):
            # Its dark ink was drawn for the cream artwork: on another picture, keep
            # the cream as a panel behind the form so it stays readable.
            values.update(HaveFormBackground='true', PartialBlur='false', FullBlur='false',
                          FormBackgroundColor='#fbf1c7')
    body = '\n'.join(f'{k}="{str(v).replace(chr(34), chr(39))}"' for k, v in values.items())
    return f'[General]\n{body}\n'


def write_config(settings, background, placeholder, palette):
    layout = settings['layout']
    text = config_text(layout, str(background), str(placeholder or ''), palette, position_choice(settings, layout))
    atomic(OUT / 'login.conf', text.encode())


def sync():
    if not (OUT.is_dir() and os.access(OUT, os.W_OK)):
        sys.exit(f'{OUT} is not set up yet: run the install command once.')
    with open(OUT / '.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)   # a later change waits, then applies the latest settings
        settings = load()
        choice = background_choice(settings, settings['layout'])
        source = source_for(choice)
        key = key_of(source)
        still = still_of(source, key)
        if choice == 'desktop' or settings['colors'] == 'desktop':
            palette = desktop_palette()
        else:
            try:
                palette = palette_of(still, key)
            except (OSError, RuntimeError, subprocess.SubprocessError):
                palette = desktop_palette()
        keep = {still.name}
        if source.suffix.lower() in VIDEO:
            video = OUT / f'bg-{key}.mp4'
            if not video.is_file():
                # Show the right picture at once; the video replaces it when ready.
                write_config(settings, still, '', palette)
                video_of(source, key)
            write_config(settings, video, still, palette)
            keep.add(video.name)
        else:
            write_config(settings, still, '', palette)
        for item in OUT.iterdir():   # media of earlier choices, and files of older versions
            if (item.name.startswith('bg-') and item.name not in keep) or re.fullmatch(r'style-\w+\.conf|\.source\.json', item.name):
                item.unlink(missing_ok=True)
    return settings, source


def sync_detached():
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--sync'], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ---- menu -------------------------------------------------------------------------
def notify(title, body):
    subprocess.run(['notify-send', '-a', 'Login screen', title, body], check=False)


def rofi(prompt, rows, message, selected=0, icons=False, delete_key=False):
    lines = []
    for label, icon in rows:
        lines.append(label + (f'\0icon\x1f{icon}' if icon else ''))
    command = ['rofi', '-dmenu', '-i', '-p', prompt, '-format', 'i', '-no-custom', '-mesg', message,
               '-selected-row', str(selected)]
    if icons:
        command.append('-show-icons')
    if delete_key:
        command += ['-kb-custom-1', 'Alt+d']
    picked = subprocess.run(command, input='\n'.join(lines), text=True, capture_output=True)
    if picked.returncode not in (0, 10) or not picked.stdout.strip():
        return None
    index = int(picked.stdout.strip())
    return (index, picked.returncode == 10) if delete_key else index


def ask_text(prompt, message):
    typed = subprocess.run(['rofi', '-dmenu', '-p', prompt, '-l', '0', '-mesg', message],
                           input='', text=True, capture_output=True)
    return typed.stdout.strip() if typed.returncode == 0 else ''


def thumbnail(path):
    if path.suffix.lower() not in VIDEO:
        return str(path)
    CACHE.mkdir(parents=True, exist_ok=True)
    thumb = CACHE / f'thumb-{key_of(path)}.jpg'
    if not thumb.is_file():
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', '1', '-i', str(path), '-frames:v', '1',
                        '-vf', 'scale=320:-1', str(thumb)], check=False)
    return str(thumb) if thumb.is_file() else ''


def choose_layout(settings):
    names = list(LAYOUTS)
    rows = [(('● ' if n == settings['layout'] else '   ') + f'{LAYOUTS[n][0]:<11} {LAYOUTS[n][1]}', '') for n in names]
    pick = rofi('Layout', rows, 'Each layout keeps its own background.', names.index(settings['layout']))
    if pick is not None:
        settings['layout'] = names[pick]
        return True
    return False


def choose_background(settings):
    layout = settings['layout']
    current = background_choice(settings, layout)
    options = [('desktop', '  Follow my desktop wallpaper (updates on every change)', '')]
    if layout == 'japanese' or current == 'artwork':
        options.append(('artwork', '  Japanese Aesthetic artwork', str(ARTWORK)))
    options.append(('browse', '  Browse for an image or video…', ''))
    files = sorted((p for p in WALLPAPERS.rglob('*') if p.suffix.lower() in VIDEO + IMAGE), key=lambda p: p.name.lower())
    for path in files:
        options.append((str(path), ('▶ ' if path.suffix.lower() in VIDEO else '   ') + path.stem, thumbnail(path)))
    rows = [(('● ' if value == current else '') + label, icon) for value, label, icon in options]
    selected = next((i for i, o in enumerate(options) if o[0] == current), 0)
    pick = rofi(f'Background · {LAYOUTS[layout][0]}', rows, 'Videos play on the login screen. ● = current.',
                selected, icons=True)
    if pick is None:
        return False
    value = options[pick][0]
    if value == 'browse':
        patterns = ' '.join('*' + e for e in IMAGE + VIDEO)
        picker = (['zenity', '--file-selection', '--title=Login background', f'--filename={WALLPAPERS}/',
                   f'--file-filter=Images and videos | {patterns}'] if shutil.which('zenity') else
                  ['yad', '--file', '--title=Login background', f'--filename={WALLPAPERS}/',
                   f'--file-filter=Images and videos | {patterns}'])
        try:
            chosen = subprocess.run(picker, capture_output=True, text=True).stdout.strip().rstrip('|')
        except OSError:
            notify('No file picker', 'Install zenity or yad to browse for a background.')
            return False
        if not chosen:
            return False
        value = chosen
    settings['backgrounds'][layout] = value
    return True


def choose_position(settings):
    layout = settings['layout']
    current = position_choice(settings, layout)
    labels = {'left': '  Left', 'center': '  Center', 'right': '  Right'}
    rows = [(('● ' if p == current else '   ') + labels[p] + ('   (default)' if p == DEFAULT_POSITION[layout] else ''), '')
            for p in POSITIONS]
    pick = rofi(f'Position · {LAYOUTS[layout][0]}', rows, 'Where the login sits on the screen.', POSITIONS.index(current))
    if pick is not None:
        settings['positions'][layout] = POSITIONS[pick]
        return True
    return False


def choose_preset(settings):
    names = sorted(settings['presets'], key=str.lower)
    rows = [('  Save the current look as a preset…', '')]
    for name in names:
        preset = settings['presets'][name]
        icon = str(ARTWORK) if preset['background'] == 'artwork' else (
            '' if preset['background'] == 'desktop' else thumbnail(Path(preset['background'])))
        rows.append((f'   {name}   —   {preset_summary(preset)}', icon))
    pick = rofi('Presets', rows, 'Enter applies a preset · Alt+D deletes it', icons=True, delete_key=True)
    if pick is None:
        return False
    index, delete = pick
    if index == 0:
        name = ask_text('Preset name', 'Saves: ' + preset_summary({'layout': settings['layout'],
                        'background': background_choice(settings, settings['layout']),
                        'position': position_choice(settings, settings['layout']), 'colors': settings['colors']}))
        if not name:
            return False
        save_preset(settings, name)
        notify('Preset saved', name)
        return True
    name = names[index - 1]
    if delete:
        del settings['presets'][name]
        notify('Preset deleted', name)
        return True
    apply_preset(settings, name)
    notify('Login preset applied', name)
    return True


def choose_colors(settings):
    modes = ['background', 'desktop']
    rows = [(('● ' if settings['colors'] == 'background' else '   ') + 'Match the background picture', ''),
            (('● ' if settings['colors'] == 'desktop' else '   ') + 'Match my desktop (wallust colors)', '')]
    pick = rofi('Colors', rows, 'With "follow my desktop" both are the same.', modes.index(settings['colors']))
    if pick is not None:
        settings['colors'] = modes[pick]
        return True
    return False


def preview():
    subprocess.run(['sddm-greeter-qt6', '--test-mode', '--theme', str(THEME)], check=False)


def menu():
    if not (OUT.is_dir() and os.access(OUT, os.W_OK)):
        notify('Login screen not installed', 'Run the install command once (see LoginThemes.py --help).')
        return
    while True:
        settings = load()
        layout = settings['layout']
        rows = [(f'  Layout        {LAYOUTS[layout][0]} — {LAYOUTS[layout][1]}', ''),
                (f'  Background    {describe(background_choice(settings, layout))}', ''),
                (f'  Position      {position_choice(settings, layout)}', ''),
                (f'  Colors        ' + ('match the background' if settings['colors'] == 'background' else 'match my desktop'), ''),
                (f'  Presets       {len(settings["presets"])} saved — apply, save or delete', ''),
                ('  Preview the login screen', ''),
                ('  Done', '')]
        pick = rofi('Login screen', rows, 'Changes apply right away, no password needed.')
        if pick is None or pick == 6:
            return
        if pick == 5:
            preview()
            continue
        changed = [choose_layout, choose_background, choose_position, choose_colors, choose_preset][pick](settings)
        if changed:
            save(settings)
            sync_detached()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--sync', action='store_true')
    parser.add_argument('--layout', choices=list(LAYOUTS))
    parser.add_argument('--background', metavar='SRC')
    parser.add_argument('--colors', choices=['background', 'desktop'])
    parser.add_argument('--position', choices=POSITIONS)
    parser.add_argument('--save-preset', metavar='NAME')
    parser.add_argument('--preset', metavar='NAME')
    parser.add_argument('--delete-preset', metavar='NAME')
    parser.add_argument('--preview', action='store_true')
    parser.add_argument('--status', action='store_true')
    args = parser.parse_args()
    if args.save_preset or args.delete_preset:
        settings = load()
        if args.save_preset:
            save_preset(settings, args.save_preset)
            print('Saved preset', repr(args.save_preset) + ':', preset_summary(settings['presets'][args.save_preset]))
        if args.delete_preset:
            if settings['presets'].pop(args.delete_preset, None) is None:
                parser.error(f'no preset named {args.delete_preset!r}')
        save(settings)
    if args.preset or args.layout or args.background or args.colors or args.position:
        settings = load()
        if args.preset:
            if args.preset not in settings['presets']:
                parser.error(f"no preset named {args.preset!r}; saved: {', '.join(settings['presets']) or 'none'}")
            apply_preset(settings, args.preset)
        if args.layout:
            settings['layout'] = args.layout
        if args.background:
            value = args.background
            if value not in ('desktop', 'artwork'):
                value = str(Path(value).expanduser().resolve())
                if not Path(value).is_file():
                    parser.error(f'no such file: {args.background}')
            settings['backgrounds'][settings['layout']] = value
        if args.colors:
            settings['colors'] = args.colors
        if args.position:
            settings['positions'][settings['layout']] = args.position
        save(settings)
        args.sync = True
    if args.sync:
        settings, source = sync()
        print(f'Login screen: {LAYOUTS[settings["layout"]][0]} on {source}')
    elif args.preview:
        preview()
    elif args.save_preset or args.delete_preset:
        pass   # done above
    elif args.status:
        settings = load()
        for name in LAYOUTS:
            mark = '*' if name == settings['layout'] else ' '
            print(mark, f'{name:<10}', f'{position_choice(settings, name):<7}', describe(background_choice(settings, name)))
        print('colors:', settings['colors'])
        for name, preset in settings['presets'].items():
            print('preset:', name, '—', preset_summary(preset))
    else:
        menu()


if __name__ == '__main__':
    main()
