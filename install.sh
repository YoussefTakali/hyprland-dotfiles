#!/usr/bin/env bash
# Install this Hyprland desktop on Fedora.
#
# Recommended: the graphical installer —  ./setup   (or double-click "Desktop Setup")
# This script is the terminal version, kept for experienced users and automation:
#
#   ./install.sh            base (KooL Fedora-Hyprland, if Hyprland isn't installed yet) + extras + these configs
#   ./install.sh --no-base  skip the KooL base install (Hyprland already set up)
#   ./install.sh --sddm     also switch the login screen to SDDM with the Jake (sddm-astronaut) theme
#                           + the SDDM login fix (your keyboard layout + visible cursor); replaces GNOME's GDM
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
STEP="start"
# Say clearly where it stopped (otherwise a failed step can look like a finished install)
trap 'printf "\n\033[1;31m✗ Install stopped during: %s\033[0m\nNothing after this step was done. Fix the error above and run ./install.sh again (it is safe to re-run).\n" "$STEP" >&2' ERR

grep -qi fedora /etc/os-release || { echo "This setup targets Fedora."; exit 1; }

# 1. Base: JaKooLit's Fedora-Hyprland (Hyprland, Waybar, rofi, swaync, wallust, SDDM, themes, fonts…)
if (( BASE )) && ! command -v Hyprland >/dev/null; then
    STEP="KooL base install"
    say "Installing the KooL Fedora-Hyprland base (interactive)"
    echo "KooL asks a few questions; the options this desktop needs are already ticked, just press Enter."
    [[ -d "$HOME/Fedora-Hyprland" ]] || git clone --depth=1 https://github.com/JaKooLit/Fedora-Hyprland.git "$HOME/Fedora-Hyprland"
    # KooL offers to reboot when it finishes; that would stop this script half way, so postpone it
    SHIM=$(mktemp -d)
    cat > "$SHIM/systemctl" <<'SHIMEOF'
#!/usr/bin/env bash
if [[ "${1:-}" == reboot ]]; then echo "(Reboot postponed: the rest of the desktop is installed first.)"; exit 0; fi
exec /usr/bin/systemctl "$@"
SHIMEOF
    chmod +x "$SHIM/systemctl"
    # Pre-tick the options this desktop needs in KooL's checklist (its --preset no longer pre-selects them)
    sed -i -E 's/^([[:space:]]*"(input_group|gtk_themes|bluetooth|thunar|quickshell|xdph|zsh|dots)" .*)"OFF"$/\1"ON"/' \
        "$HOME/Fedora-Hyprland/install.sh"
    (cd "$HOME/Fedora-Hyprland" && PATH="$SHIM:$PATH" ./install.sh)
    rm -rf "$SHIM"
fi

# 2. Extra packages used by these configs
STEP="installing extra packages"
say "Installing extra packages"
sudo dnf copr enable -y errornointernet/quickshell
sudo dnf copr enable -y sdegler/hyprland        # mpvpaper (video wallpapers)
sudo dnf install -y --skip-unavailable \
    quickshell mpvpaper /usr/bin/ffmpeg qt6-qtmultimedia qt6-qt5compat qt6-qtsvg \
    cava wf-recorder tesseract tesseract-langpack-eng hyprpicker cliphist grim slurp swappy wl-clipboard \
    ImageMagick fastfetch lsd fzf kitty playerctl blueman nautilus thunar \
    python3-gobject jq tuned-ppd libnotify julietaula-montserrat-fonts nautilus-python qalculate

# 3. Back up what we replace, then copy configs
STEP="copying configs"
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

# Keyboard: keep this PC's layout (the repo carries the original author's French AZERTY)
SYS="$HOME/.config/hypr/configs/SystemSettings.conf"
KB=$(grep -m1 -oP '^\s*kb_layout\s*=\s*\K\S+' "$BACKUP/hypr/configs/SystemSettings.conf" 2>/dev/null || true)
KBV=$(grep -m1 -oP '^\s*kb_variant\s*=\s*\K\S+' "$BACKUP/hypr/configs/SystemSettings.conf" 2>/dev/null || true)
[[ -z "$KB" ]] && KB=$(localectl status 2>/dev/null | awk -F': *' '/X11 Layout/ {print $2}')
[[ -z "$KB" ]] && KB=$(localectl status 2>/dev/null | awk -F': *' '/VC Keymap/ {print $2}' | cut -d- -f1)
if [[ -n "$KB" && "$KB" != "n/a" && -f "$SYS" ]]; then
    sed -i -E "s/^([[:space:]]*kb_layout[[:space:]]*=).*/\1 $KB/; s/^([[:space:]]*kb_variant[[:space:]]*=).*/\1 $KBV/" "$SYS"
    echo "Keyboard layout: $KB${KBV:+ ($KBV)}"
fi

# Graphics: Hyprland settings for this PC's GPUs (hybrid laptops keep the discrete GPU asleep until needed)
"$HOME/.config/hypr/scripts/GpuConfig.sh" || true

# NVIDIA-only environment variables break GL/VA-API on machines without an NVIDIA GPU
if ! lspci 2>/dev/null | grep -qiE "vga.*nvidia|3d.*nvidia"; then
    sed -i -E 's/^(\s*env\s*=\s*(LIBVA_DRIVER_NAME|__GLX_VENDOR_LIBRARY_NAME),nvidia)/# (no NVIDIA GPU) \1/' \
        "$HOME/.config/hypr/configs/ENVariables.conf" "$HOME/.config/hypr/UserConfigs/ENVariables.conf" 2>/dev/null || true
fi

# Waybar layout/style symlinks
# Default Laptop layout with the adaptive style (colours from the wallpaper). Also in the Waybar menus:
# "[0 VERTICAL] [Catpuccin] Mocha.css" (fixed colours) and the "[TOP] Glass Islands" layout + "[Glass] Islands.css".
ln -sfn "$HOME/.config/waybar/configs/[TOP] Default Laptop" "$HOME/.config/waybar/config"
ln -sfn "$HOME/.config/waybar/style/[0 VERTICAL] [Wallust] Adaptive.css" "$HOME/.config/waybar/style.css"

# Scripts executable
find "$HOME/.config/hypr" "$HOME/.config/fastfetch" -name '*.sh' -exec chmod +x {} +
chmod +x "$HOME/.config/hypr/UserScripts/"*.py "$HOME/.config/hypr/scripts/"*.py 2>/dev/null || true
chmod +x "$HOME/.config/hypr/bin/"* 2>/dev/null || true      # hyprctl stand-in + config watcher (Lua mode)

# Nautilus right-click "Open in Kitty" (its own "Open in Console" is hard-wired to Ptyxis)
mkdir -p "$HOME/.local/share/nautilus-python/extensions"
cp "$HERE/home/nautilus-python/open-in-kitty.py" "$HOME/.local/share/nautilus-python/extensions/"

# "Keyboard Shortcuts" app in the app menu (Super+X → Keyboard shortcuts also opens it)
mkdir -p "$HOME/.local/share/applications"
sed "s|@HOME@|$HOME|g" "$HERE/home/applications/io.github.YoussefTakali.Shortcuts.desktop" \
    > "$HOME/.local/share/applications/io.github.YoussefTakali.Shortcuts.desktop"

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
python3 -I "$HOME/.config/hypr/scripts/AccentGuard.py" >/dev/null 2>&1 || true   # readable accent, GTK/kitty accent, Accent-Folders icons

# 6. Desktop settings
say "Applying desktop settings"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
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
    STEP="SDDM login screen"
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
    # Fedora Workstation uses GNOME's login screen (GDM); only one can run
    if systemctl is-enabled gdm >/dev/null 2>&1; then
        sudo systemctl disable gdm
    fi
    sudo systemctl enable sddm
    printf '[Last]\nUser=%s\nSession=/usr/share/wayland-sessions/hyprland.desktop\n' "$USER" | sudo tee /var/lib/sddm/state.conf >/dev/null   # SDDM would pre-select the first session (GNOME Classic)
fi

say "Done"
cat <<EOF
Log out and back in (or reboot) to start Hyprland with this setup.
  Lock screen:  Super+L        Utilities: Super+X        Cheat sheet: Super+H
Your previous configs are in $BACKUP
EOF
if (( SDDM )); then
    echo "Login screen: SDDM with sddm-astronaut-theme (jake_the_dog) — https://github.com/Keyitdev/sddm-astronaut-theme"
fi
exit 0
