#!/usr/bin/env bash
# Install the SDDM login screen: the Hypr Login Styles theme (layouts, a background
# per layout, positions and presets, chosen later without a password through
# ~/.config/hypr/scripts/LoginThemes.py), plus sddm-astronaut, which provides the
# Japanese Aesthetic layout and the shared loading scene.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Administrator access required.' >&2; exit 1; }
[[ -n ${SUDO_UID:-} ]] || { echo 'Run through sudo: the login settings folder must belong to you.' >&2; exit 1; }
repo=$(cd "$(dirname "$0")/../.." && pwd)
theme=/usr/share/sddm/themes/sddm-astronaut-theme
styles=/usr/share/sddm/themes/hypr-login-styles
helper=/usr/local/libexec/sddm-login-theme
old_helper=/usr/local/libexec/hyprland-login-themes.py

# Prepare the theme before replacing a working installation.
mkdir -p /usr/share/sddm/themes /var/backups
stage=$(mktemp -d /usr/share/sddm/themes/.dotfiles.XXXXXX)
trap 'python3 -I -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$stage"' EXIT
git -C "$stage" init -q source
git -C "$stage/source" fetch -q --depth=1 https://github.com/Keyitdev/sddm-astronaut-theme.git abb3163c724935af888ba5ea9ac0c4f22afd8048
mkdir "$stage/astronaut"
git -C "$stage/source" archive FETCH_HEAD | tar -x -C "$stage/astronaut"
backup=$(mktemp -d /var/backups/hyprland-sddm.XXXXXX)
for previous in /etc/sddm.conf "$helper" "$old_helper"; do
    [[ ! -e "$previous" ]] || cp -a "$previous" "$backup/"
done
rm -f "$old_helper"   # the preset catalogue it managed is replaced by Hypr Login Styles

python3 -I "$repo/installer/session/prepare-sddm-theme.py" "$stage/astronaut"
mkdir -p /usr/local/share/fonts/sddm-astronaut
cp -a "$stage/astronaut/Fonts/." /usr/local/share/fonts/sddm-astronaut/
# The greeter runs as its own user and cannot read fonts in a home folder.
user_fonts="$(getent passwd "$SUDO_UID" | cut -d: -f6)/.local/share/fonts/JetBrainsMonoNerd"
if ! fc-list : file | grep -v '^/home/' | grep -i 'JetBrainsMonoNerdFont-Thin' >/dev/null && [[ -d "$user_fonts" ]]; then
    mkdir -p /usr/local/share/fonts/JetBrainsMonoNerd
    cp -a "$user_fonts/." /usr/local/share/fonts/JetBrainsMonoNerd/
fi
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
    # An empty InputMethod keeps Qt's on-screen keyboard from popping up.
    'General': {'DisplayServer': server, 'InputMethod': ''},
    'Theme': {'Current': 'hypr-login-styles', 'CursorTheme': 'Adwaita', 'CursorSize': '24'},
}.items():
    if not c.has_section(section): c.add_section(section)
    for key, value in values.items(): c.set(section, key, value)
with tempfile.NamedTemporaryFile(mode='w', dir=p.parent, delete=False) as stream:
    c.write(stream, space_around_delimiters=False)
    temporary = Path(stream.name)
temporary.chmod(0o644)
os.replace(temporary, p)
PY

# The helper installs the theme and gives the user its settings folder; run it
# again after editing the theme's QML.
install -D -m 0755 "$repo/installer/session/sddm-login-theme" "$helper"
"$helper" --install "$repo/installer/session/hypr-login-styles"

if command -v restorecon >/dev/null; then
    restorecon -RF "$theme" "$styles" "$helper" /etc/sddm.conf
fi
echo "SDDM login screen installed (Hypr Login Styles). Backup: $backup"
