#!/usr/bin/env python3
"""Launch the notification center with GTK4 styling and available hardware."""
import json
import os
from pathlib import Path
import tempfile

home = Path.home()
config = json.loads((home / '.config/swaync/config.json').read_text())
config['ignore-gtk-theme'] = False
if not any(Path('/sys/class/backlight').glob('*/brightness')):
    config['widgets'] = [w for w in config.get('widgets', []) if w != 'backlight']
config.setdefault('widget-config', {}).setdefault('notifications', {})
runtime = Path(os.environ['XDG_RUNTIME_DIR'])
target = runtime / 'hypr-swaync.json'
with tempfile.NamedTemporaryFile(mode='w', dir=runtime, prefix='swaync-', delete=False) as stream:
    json.dump(config, stream)
    temporary = stream.name
os.replace(temporary, target)
# The existing CSS still supplies the cards and wallpaper accent. Flat Remix's
# GTK4 port contains GTK3-only shade()/mix() functions rejected by this GTK.
os.environ['GTK_THEME'] = 'Adwaita:dark'
os.execv('/usr/bin/swaync', ['swaync', '--config', str(target)])
