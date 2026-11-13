#!/usr/bin/env bash
# Install the selected SDDM greeter, theme, and privileged preset helper.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Administrator access required.' >&2; exit 1; }
repo=$(cd "$(dirname "$0")/../.." && pwd)
assets=${1:?Missing login theme catalogue}
theme=/usr/share/sddm/themes/sddm-astronaut-theme
helper=/usr/local/libexec/hyprland-login-themes.py

# Prepare the theme before replacing a working installation.
mkdir -p /usr/share/sddm/themes /var/backups
stage=$(mktemp -d /usr/share/sddm/themes/.dotfiles.XXXXXX)
trap 'python3 -I -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$stage"' EXIT
git -C "$stage" init -q source
git -C "$stage/source" fetch -q --depth=1 https://github.com/Keyitdev/sddm-astronaut-theme.git abb3163c724935af888ba5ea9ac0c4f22afd8048
mkdir "$stage/astronaut"
git -C "$stage/source" archive FETCH_HEAD | tar -x -C "$stage/astronaut"
backup=$(mktemp -d /var/backups/hyprland-sddm.XXXXXX)
if [[ -e /etc/sddm.conf ]]; then
    cp -a /etc/sddm.conf "$backup/"
fi
if [[ -e "$helper" ]]; then
    cp -a "$helper" "$backup/"
fi

python3 -I "$repo/installer/session/prepare-sddm-theme.py" "$stage/astronaut"
python3 -I "$repo/config/hypr/scripts/LoginThemes.py" --system-install --assets "$assets" --theme-dir "$stage/astronaut"
install -D -m 0644 "$repo/config/hypr/scripts/LoginThemes.py" "$helper"
mkdir -p /usr/local/share/fonts/sddm-astronaut
cp -a "$stage/astronaut/Fonts/." /usr/local/share/fonts/sddm-astronaut/
fc-cache -f
if [[ -e "$theme" ]]; then
    mv "$theme" "$backup/replaced"
fi
if ! mv "$stage/astronaut" "$theme"; then
    [[ ! -e "$backup/replaced" ]] || mv "$backup/replaced" "$theme"
    exit 1
fi

python3 -I - <<'PY'
import configparser
import os
from pathlib import Path
import tempfile
p = Path('/etc/sddm.conf')
c = configparser.ConfigParser(interpolation=None, strict=False)
c.optionxform = str
if p.exists(): c.read(p)
# Keep a separately validated Hyprland greeter when reinstalling the theme.
server = 'x11'
if c.get('General', 'DisplayServer', fallback='') == 'wayland' and c.get('Wayland', 'CompositorCommand', fallback='').endswith('--config /etc/sddm/hyprland-greeter.lua'):
    server = 'wayland'
for section, values in {
    'General': {'DisplayServer': server, 'InputMethod': 'qtvirtualkeyboard'},
    'Theme': {'Current': 'sddm-astronaut-theme', 'CursorTheme': 'Adwaita', 'CursorSize': '24'},
}.items():
    if not c.has_section(section): c.add_section(section)
    for key, value in values.items(): c.set(section, key, value)
with tempfile.NamedTemporaryFile(mode='w', dir=p.parent, delete=False) as stream:
    c.write(stream, space_around_delimiters=False)
    temporary = Path(stream.name)
temporary.chmod(0o644)
os.replace(temporary, p)
PY

if command -v restorecon >/dev/null; then
    restorecon -RF "$theme" "$helper" /etc/sddm.conf
fi
echo "SDDM Jake theme installed. Backup: $backup"
