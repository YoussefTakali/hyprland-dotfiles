#!/usr/bin/env bash
# Install this Hyprland setup on a Fedora machine.
#
#   ./install.sh            base (KooL Fedora-Hyprland, if Hyprland isn't installed yet) + extras + these configs
#   ./install.sh --no-base  skip the KooL base install (Hyprland already set up)
#   ./install.sh --sddm     also install the Jake (sddm-astronaut) login theme + the SDDM login fix
#                           (French keyboard + visible cursor) — asks for sudo
#
# Everything this replaces is copied to ~/.config-backup-<date>/ first.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE=1 SDDM=0
for a in "$@"; do
    case "$a" in
        --no-base) BASE=0 ;;
        --sddm)    SDDM=1 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown option: $a"; exit 1 ;;
    esac
done

say() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

grep -qi fedora /etc/os-release || { echo "This setup targets Fedora."; exit 1; }

# 1. Base: JaKooLit's Fedora-Hyprland (Hyprland, Waybar, rofi, swaync, wallust, SDDM, themes, fonts…)
if (( BASE )) && ! command -v Hyprland >/dev/null; then
    say "Installing the KooL Fedora-Hyprland base (interactive)"
    [[ -d "$HOME/Fedora-Hyprland" ]] || git clone --depth=1 https://github.com/JaKooLit/Fedora-Hyprland.git "$HOME/Fedora-Hyprland"
    (cd "$HOME/Fedora-Hyprland" && ./install.sh)
fi

# 2. Extra packages used by these configs
say "Installing extra packages"
sudo dnf copr enable -y errornointernet/quickshell
sudo dnf copr enable -y sdegler/hyprland        # mpvpaper (video wallpapers)
sudo dnf install -y \
    quickshell mpvpaper ffmpeg qt6-qtmultimedia qt6-qt5compat qt6-qtsvg \
    cava wf-recorder tesseract tesseract-langpack-eng hyprpicker cliphist grim slurp swappy wl-clipboard \
    ImageMagick fastfetch lsd fzf kitty playerctl blueman nautilus thunar \
    python3-gobject jq tuned-ppd libnotify julietaula-montserrat-fonts

# 3. Back up what we replace, then copy configs
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/.config-backup-$STAMP"
say "Backing up current configs to $BACKUP"
mkdir -p "$BACKUP"
for d in "$HERE"/config/*; do
    n=$(basename "$d")
    [[ -e "$HOME/.config/$n" ]] && cp -a "$HOME/.config/$n" "$BACKUP/"
done
[[ -f "$HOME/.zshrc" ]] && cp -a "$HOME/.zshrc" "$BACKUP/zshrc"

say "Copying configs"
mkdir -p "$HOME/.config"
cp -a "$HERE"/config/. "$HOME/.config/"
cp -a "$HERE/home/.zshrc" "$HOME/.zshrc"

# Paths/names that were specific to the original machine
grep -rlI "/home/rhast" "$HOME/.config/"{hypr,waybar,rofi,kitty,quickshell,fastfetch,gtk-3.0,gtk-4.0,gtk-theme} 2>/dev/null \
    | xargs -r sed -i "s|/home/rhast|$HOME|g"
sed -i "s|hello, rhast|hello, $USER|" "$HOME/.config/fastfetch/config-wall.jsonc"
sed -i "s|\${SUDO_USER:-rhast}|\${SUDO_USER:-$USER}|" "$HOME/.config/hypr/UserScripts/sddm-login-fix.sh"

# NVIDIA-only environment variables break GL/VA-API on machines without an NVIDIA GPU
if ! lspci 2>/dev/null | grep -qiE "vga.*nvidia|3d.*nvidia"; then
    sed -i -E 's/^(\s*env\s*=\s*(LIBVA_DRIVER_NAME|__GLX_VENDOR_LIBRARY_NAME),nvidia)/# (no NVIDIA GPU) \1/' \
        "$HOME/.config/hypr/configs/ENVariables.conf" "$HOME/.config/hypr/UserConfigs/ENVariables.conf" 2>/dev/null || true
fi

# Waybar layout/style symlinks
# Glass Islands bar (the previous "[TOP] Default Laptop" + "[0 VERTICAL] [Catpuccin] Mocha.css" stay in the Waybar menus)
ln -sfn "$HOME/.config/waybar/configs/[TOP] Glass Islands" "$HOME/.config/waybar/config"
ln -sfn "$HOME/.config/waybar/style/[Glass] Islands.css" "$HOME/.config/waybar/style.css"

# Scripts executable
find "$HOME/.config/hypr" "$HOME/.config/fastfetch" -name '*.sh' -exec chmod +x {} +
chmod +x "$HOME/.config/hypr/UserScripts/"*.py "$HOME/.config/hypr/scripts/"*.py 2>/dev/null || true

# 4. Prompt theme (oh-my-zsh is installed by the KooL base)
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    mkdir -p "$HOME/.oh-my-zsh/custom/themes"
    cp "$HERE/oh-my-zsh/agnosterzak-mocha.zsh-theme" "$HOME/.oh-my-zsh/custom/themes/"
fi

# 5. Wallpaper
say "Setting the wallpaper"
mkdir -p "$HOME/Pictures/wallpapers" "$HOME/.config/hypr/wallpaper_effects"
W=$(ls "$HERE"/wallpapers/current.* | head -1)
cp "$W" "$HOME/Pictures/wallpapers/"
cp "$W" "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"
command -v wallust >/dev/null && wallust run "$W" >/dev/null 2>&1 || true
python3 -I "$HOME/.config/hypr/scripts/AccentGuard.py" >/dev/null 2>&1 || true   # readable accent + GTK/kitty accent

# 6. Mauve folder icons: recolor Flat-Remix-Blue-Dark's folders (installed by the KooL base)
SRC_ICONS="$HOME/.icons/Flat-Remix-Blue-Dark"
DST_ICONS="$HOME/.icons/Flat-Remix-Mauve-Dark"
if [[ -d "$SRC_ICONS" && ! -d "$DST_ICONS" ]]; then
    say "Creating the mauve folder icon theme"
    mkdir -p "$DST_ICONS"
    cp -r "$SRC_ICONS/places" "$DST_ICONS/"
    find "$DST_ICONS/places" -type f -name '*.svg' -exec sed -i 's/#367bf0/#a374ec/gI; s/#2b62c0/#7c4cc9/gI' {} +
    sed 's/^Name=.*/Name=Flat-Remix-Mauve-Dark/; s/^Inherits=.*/Inherits=Flat-Remix-Blue-Dark,breeze-dark,elementary,gnome,hicolor/' \
        "$SRC_ICONS/index.theme" > "$DST_ICONS/index.theme"
    gtk-update-icon-cache -f -t "$DST_ICONS" >/dev/null 2>&1 || true
fi

# 7. Desktop settings
say "Applying desktop settings"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
[[ -d "$DST_ICONS" ]] && gsettings set org.gnome.desktop.interface icon-theme 'Flat-Remix-Mauve-Dark' || true
gsettings set org.blueman.general plugin-list "['!StatusIcon', '!StatusNotifierItem']" 2>/dev/null || true
xdg-mime default org.gnome.Nautilus.desktop inode/directory 2>/dev/null || true

# 7b. Firefox: solid address bar dropdown (the GTK theme's see-through fields made it unreadable)
for prof in "$HOME"/.mozilla/firefox/*.default-release "$HOME"/.config/mozilla/firefox/*.default-release; do
    [[ -d "$prof" ]] || continue
    mkdir -p "$prof/chrome"
    cp "$HERE/firefox/userChrome.css" "$prof/chrome/"
    cp "$HERE/firefox/user.js" "$prof/"
done

# 8. Optional: SDDM login screen fix
if (( SDDM )); then
    say "Installing the Jake login theme (sddm-astronaut-theme)"
    sudo dnf install -y sddm qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia
    T=/usr/share/sddm/themes/sddm-astronaut-theme
    if [[ ! -d "$T" ]]; then
        sudo git clone --depth=1 https://github.com/Keyitdev/sddm-astronaut-theme.git "$T"
        sudo cp -r "$T/Fonts/." /usr/share/fonts/ 2>/dev/null || true
    fi
    sudo sed -i 's|^ConfigFile=.*|ConfigFile=Themes/jake_the_dog.conf|' "$T/metadata.desktop"
    printf '[Theme]\nCurrent=sddm-astronaut-theme\n' | sudo tee /etc/sddm.conf.d/10-theme.conf >/dev/null
    say "Applying the SDDM login fix"
    sudo bash "$HOME/.config/hypr/UserScripts/sddm-login-fix.sh"
fi

say "Done"
cat <<EOF
Log out and back in (or reboot) to start Hyprland with this setup.
  Lock screen:  Super+L        Utilities: Super+X        Cheat sheet: Super+H
Your previous configs are in $BACKUP
SDDM theme: the login screen used sddm-astronaut-theme (jake_the_dog) — https://github.com/Keyitdev/sddm-astronaut-theme
EOF
