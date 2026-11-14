#!/usr/bin/env bash
# Desktop installer backend: does the whole installation, step by step, without asking questions.
# Works on Arch, Fedora and Ubuntu (26.04+); the distro-specific parts live in installer/distro/<id>.sh.
# The graphical installer (installer/setup.py) runs it and reads its progress lines; install.sh runs it in a
# terminal. Run as the user who gets the desktop (not root); it uses sudo, which the caller must have unlocked
# (the graphical installer installs a temporary password-less sudo rule for the duration, see grant.sh).
#
# Choices come from the environment (defaults in brackets):
#   OPT_KB=<xkb layout>        [this PC's]         OPT_KB_VARIANT=<variant> [""]
#   OPT_LOCK=Slate|Iris|Fog|Cards [Slate]
#   OPT_BAR=ultimate|adaptive|glass|liquid|liquid-v2|liquid-v3 [ultimate: glass bar whose shape follows the theme switcher]
#   OPT_LOGIN=keep|sddm        [keep: this PC's login screen starts Hyprland]
#   OPT_DRIVERS=1|0            [1: install the graphics drivers this PC needs]
#   OPT_MOK_PASSWORD=<pw>      Fedora + Secure Boot: one-time password to approve the NVIDIA driver key at next boot
#   OPT_SKIP_BASE=1            skip the Hyprland base (packages) — configs only
#   OPT_JACK_FIX=1|0           [0] keep the onboard 3.5mm output on even when jack detection is broken
#
# Progress protocol (one per line, everything else is log):
#   @@STEP <n> <total> <title>   @@PROGRESS <0-100>   @@NOTE <text for the final page>   @@WARN <text>
#   @@DONE                       @@FAIL <what failed>
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"          # the repository
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/.config-backup-$STAMP-$$"
LOGFILE="$HOME/.cache/desktop-install-$STAMP.log"
mkdir -p "$HOME/.cache"
exec > >(tee -a "$LOGFILE") 2>&1

: "${OPT_LOCK:=Slate}" "${OPT_BAR:=ultimate}" "${OPT_LOGIN:=keep}" "${OPT_DRIVERS:=1}" "${OPT_SKIP_BASE:=0}"
: "${OPT_KB:=}" "${OPT_KB_VARIANT:=}" "${OPT_MOK_PASSWORD:=}" "${OPT_JACK_FIX:=0}"

STEPS=(prepare repos base drivers extras configs settings login finish)
TOTAL=${#STEPS[@]}
N=0
step() { N=$((N + 1)); echo "@@STEP $N $TOTAL $*"; echo "@@PROGRESS $(( (N - 1) * 100 / TOTAL ))"; }
sub()  { echo "@@PROGRESS $(( (N - 1) * 100 / TOTAL + $1 * 100 / TOTAL / 100 ))"; }   # $1 = % of this step
note() { echo "@@NOTE $*"; }
warn() { echo "@@WARN $*"; }
fail() { echo "@@FAIL $*"; exit 1; }
run()  { echo "\$ $*"; "$@"; }

[[ $EUID -ne 0 ]] || fail "Run the installer as your normal user, not as root."

# ── which distro ────────────────────────────────────────────────────────────
OS_RELEASE=${OS_RELEASE:-/etc/os-release}     # overridable for testing
SDDM_THEME_DIR=${SDDM_THEME_DIR:-/usr/share/sddm/themes/sddm-astronaut-theme}   # where install-sddm.sh puts the theme; overridable for testing
# shellcheck source=/dev/null
. "$OS_RELEASE"
DISTRO=""
for d in arch fedora ubuntu; do
    [[ "$ID" == "$d" || " ${ID_LIKE:-} " == *" $d "* ]] && { DISTRO=$d; break; }
done
[[ -n "$DISTRO" ]] || fail "This installer supports Arch, Fedora and Ubuntu (found: $PRETTY_NAME)."
# shellcheck source=/dev/null
. "$HERE/installer/distro/$DISTRO.sh"

[[ "$DISTRO" == fedora ]] || export OPT_MOK_PASSWORD=""
sudo -n true 2>/dev/null || fail "Administrator access is needed (sudo). Start the installer again and enter your password."

# Base scripts may call chsh (asks for a password) or offer "systemctl reboot"; neither may happen mid-install
SHIM=$(mktemp -d)
cat > "$SHIM/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == reboot || "${1:-}" == poweroff ]]; then echo "(postponed until the installation is finished)"; exit 0; fi
exec /usr/bin/systemctl "$@"
EOF
cat > "$SHIM/chsh" <<EOF
#!/usr/bin/env bash
exec sudo /usr/bin/chsh "\$@" "$USER"
EOF
chmod +x "$SHIM"/*
export PATH="$SHIM:$PATH"
trap 'rm -rf "$SHIM"' EXIT

# GPU detection and the setup helpers are Python; minimal installs (e.g. Arch) may not have it yet
if ! command -v python3 >/dev/null; then
    case "$DISTRO" in
        arch)   run sudo pacman -S --needed --noconfirm python ;;
        fedora) run sudo dnf install -y python3 ;;
        ubuntu) run sudo apt-get install -y python3 ;;
    esac
    command -v python3 >/dev/null || fail "Python 3 is needed and couldn't be installed (see the log)."
fi
GPU_FACTS=$("$HERE/config/hypr/scripts/GpuInfo.sh") || fail "Couldn't detect this PC's graphics (see the log)."
eval "$GPU_FACTS"
[[ -n "${MODE:-}" ]] || fail "Couldn't detect this PC's graphics (see the log)."

# ── 1. prepare ───────────────────────────────────────────────────────────────
step "Checking this PC"
note "LOG $LOGFILE"
d_check || fail "This version of $PRETTY_NAME isn't supported."
echo "System: $PRETTY_NAME ($DISTRO), graphics: $MODE ($GPUS), Secure Boot: $SECURE_BOOT"
curl -sfI --max-time 10 "$PING_URL" >/dev/null || fail "No internet connection. Connect to the internet and try again."
free_gb=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9)
(( free_gb >= 8 )) || fail "At least 8 GB of free disk space is needed (found ${free_gb} GB)."
d_prepare

# ── 2. repositories ─────────────────────────────────────────────────────────
step "Adding software sources"
d_repos

# ── 3. Hyprland base ────────────────────────────────────────────────────────
step "Installing Hyprland and its tools (this is the long part)"
if (( OPT_SKIP_BASE )); then
    echo "Skipped (OPT_SKIP_BASE=1)"
else
    d_base
    command -v Hyprland >/dev/null || fail "Hyprland didn't get installed (see the log)."
fi
# The configs need Hyprland 0.53+ (rule syntax); 0.55+ reads hyprland.lua, older ones read hyprland.conf directly
HYPR_VER=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "Hyprland ${HYPR_VER:-?}"

# ── 4. graphics drivers ─────────────────────────────────────────────────────
step "Setting up graphics ($MODE)"
if (( OPT_DRIVERS )); then
    d_drivers
else
    echo "Driver installation skipped (OPT_DRIVERS=0); existing drivers retained."
fi
unset OPT_MOK_PASSWORD

# ── 5. extra packages ───────────────────────────────────────────────────────
step "Installing the desktop's apps and tools"
d_extras
if [[ "$DISTRO" == fedora ]]; then
    run bash "$HERE/installer/install-codecs.sh" || fail "Couldn't install or verify HEVC support for video wallpapers."
fi

# Nerd Font: bar and menu icons are empty boxes without it
if ! fc-list : family | grep -qi "JetBrainsMono Nerd Font"; then
    echo "Downloading the JetBrainsMono Nerd Font (bar and menu icons)"
    NF_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd" NF_TMP=$(mktemp)
    if curl -fsSL --retry 5 --retry-delay 3 -o "$NF_TMP" \
            https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz \
        && mkdir -p "$NF_DIR" && tar -xJf "$NF_TMP" -C "$NF_DIR"; then
        fc-cache -f "$NF_DIR" >/dev/null 2>&1
    else
        warn "Couldn't download the JetBrainsMono Nerd Font, so some icons will show as boxes. Run the installer again later."
    fi
    rm -f "$NF_TMP"
fi

# zsh + oh-my-zsh (Fedora's KooL base already does this; Arch/Ubuntu need it here)
sub 70
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    run git clone -q --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || warn "oh-my-zsh not installed."
fi
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    C="$HOME/.oh-my-zsh/custom/plugins"; mkdir -p "$C"
    [[ -d "$C/zsh-autosuggestions" ]] || git clone -q --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$C/zsh-autosuggestions"
    [[ -d "$C/zsh-syntax-highlighting" ]] || git clone -q --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$C/zsh-syntax-highlighting"
fi
ZSH_BIN=$(command -v zsh || true)
[[ -n "$ZSH_BIN" && "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_BIN" ]] && { sudo chsh -s "$ZSH_BIN" "$USER" || warn "Couldn't make zsh your shell."; }

# ── 6. configs ──────────────────────────────────────────────────────────────
step "Installing the desktop's settings"
mkdir -p "$HOME/.config" || fail "Could not create the configuration directory."
for d in "$HERE"/config/*; do
    n=$(basename "$d")
    if [[ -e "$HOME/.config/$n" ]]; then
        mkdir -p "$BACKUP" || fail "Could not create the configuration backup."
        cp -a "$HOME/.config/$n" "$BACKUP/" || fail "Backup failed for $n; refusing to overwrite it."
    fi
done
if [[ -f "$HOME/.zshrc" ]]; then
    mkdir -p "$BACKUP" || fail "Could not create the configuration backup."
    cp -a "$HOME/.zshrc" "$BACKUP/zshrc" || fail "Shell configuration backup failed."
fi
cp -a "$HERE"/config/. "$HOME/.config/" || fail "Could not install desktop configuration."
cp -a "$HERE/home/.zshrc" "$HOME/.zshrc" || fail "Could not install shell configuration."
grep -rlI "/home/rhast" "$HOME/.config/"{hypr,waybar,rofi,kitty,quickshell,fastfetch,gtk-3.0,gtk-4.0,gtk-theme} 2>/dev/null \
    | xargs -r sed -i "s|/home/rhast|$HOME|g"
sed -i "s|hello, rhast|hello, $USER|" "$HOME/.config/fastfetch/config-wall.jsonc" 2>/dev/null
find "$HOME/.config/hypr" "$HOME/.config/fastfetch" -name '*.sh' -exec chmod +x {} +
chmod +x "$HOME/.config/hypr/UserScripts/"*.py "$HOME/.config/hypr/scripts/"*.py "$HOME/.config/hypr/bin/"* 2>/dev/null
mkdir -p "$HOME/.local/share/rofi/themes" && ln -snf "$HOME/.config/rofi/themes/"* "$HOME/.local/share/rofi/themes/" 2>/dev/null
xdg-user-dirs-update 2>/dev/null || true
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    mkdir -p "$HOME/.oh-my-zsh/custom/themes" && cp "$HERE/oh-my-zsh/agnosterzak-mocha.zsh-theme" "$HOME/.oh-my-zsh/custom/themes/"
fi
mkdir -p "$HOME/.local/share/nautilus-python/extensions" "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/hypr-login-themes"
cp -a "$HERE/home/login-themes/." "$HOME/.local/share/hypr-login-themes/" || fail "Could not install the animated login catalogue."
cp "$HERE/config/quickshell/login-splash/"{JakeLoadingScene,shell}.qml "$HOME/.local/share/hypr-login-themes/" \
    || fail "Could not install the shared login scene."
cp "$HERE/home/nautilus-python/open-in-kitty.py" "$HOME/.local/share/nautilus-python/extensions/" || fail "Could not install Nautilus integration."
sed "s|@HOME@|$HOME|g" "$HERE/home/applications/io.github.YoussefTakali.Shortcuts.desktop" \
    > "$HOME/.local/share/applications/io.github.YoussefTakali.Shortcuts.desktop"
sed "s|@HOME@|$HOME|g" "$HERE/home/applications/blueman-manager.desktop" \
    > "$HOME/.local/share/applications/blueman-manager.desktop"

# Firefox customizations (only existing release profiles); preserve their originals.
for prof in "$HOME"/.mozilla/firefox/*.default-release "$HOME"/.config/mozilla/firefox/*.default-release; do
    [[ -d "$prof" ]] || continue
    dest="$BACKUP/firefox/${prof#"$HOME"/}"
    mkdir -p "$prof/chrome" || fail "Could not prepare Firefox configuration."
    for original in "$prof/user.js" "$prof/chrome/userChrome.css"; do
        if [[ -e "$original" || -L "$original" ]]; then
            mkdir -p "$dest" || fail "Could not prepare Firefox backup."
            cp -aL -- "$original" "$dest/" || fail "Could not back up Firefox settings at $original."
        fi
    done
    cp "$HERE/firefox/userChrome.css" "$prof/chrome/" || fail "Could not install Firefox style."
    cp "$HERE/firefox/user.js" "$prof/" || fail "Could not install Firefox settings."
done

# swww was renamed awww (Arch, Ubuntu source build): the scripts call swww, so add shims
if ! command -v swww >/dev/null && command -v awww >/dev/null && command -v awww-daemon >/dev/null; then
    H="$HOME/.config/hypr"; mkdir -p "$H/bin" "$HOME/.local/bin"
    printf '#!/bin/sh\nexec awww "$@"\n'        > "$H/bin/swww"
    printf '#!/bin/sh\nexec awww-daemon "$@"\n' > "$H/bin/swww-daemon"
    chmod +x "$H/bin/swww" "$H/bin/swww-daemon"
    ln -sf "$H/bin/swww" "$HOME/.local/bin/swww"; ln -sf "$H/bin/swww-daemon" "$HOME/.local/bin/swww-daemon"
fi

for required in Hyprland waybar qs rofi hypridle hyprlock; do
    command -v "$required" >/dev/null || fail "Required desktop command $required was not installed."
done
for required in swww swww-daemon; do
    command -v "$required" >/dev/null || [[ -x "$HOME/.config/hypr/bin/$required" ]] || fail "Missing wallpaper command $required."
done

# Hyprland 0.53/0.54 don't read hyprland.lua; they read hyprland.conf directly (the same files)
if [[ -n "$HYPR_VER" ]] && printf '%s\n0.55.0\n' "$HYPR_VER" | sort -V -C; then
    [[ "$HYPR_VER" == 0.55.0 ]] || { rm -f "$HOME/.config/hypr/hyprland.lua"; echo "Hyprland $HYPR_VER: using hyprland.conf"; }
fi
if [[ -n "$HYPR_VER" ]] && printf '%s\n0.53.0\n' "$HYPR_VER" | sort -V -C && [[ "$HYPR_VER" != 0.53.0 ]]; then
    warn "Hyprland $HYPR_VER is older than 0.53: window rules use the newer syntax and some won't apply. Update Hyprland."
fi

# Older releases can disable automatic HDR globally but lack the per-window rule.
if [[ -n "$HYPR_VER" && "$HYPR_VER" != 0.56.0 ]] && printf '%s\n0.56.0\n' "$HYPR_VER" | sort -V -C; then
    H="$HOME/.config/hypr"
    sed -i '/^windowrule = match:class \^brave-browser\$, no_auto_hdr on$/d' "$H/UserConfigs/WindowRules.conf"
    sed -i '/^render {/a\  cm_auto_hdr = 0 # older Hyprland lacks a per-window HDR rule' "$H/configs/SystemSettings.conf"
fi

# ── 7. per-PC settings ──────────────────────────────────────────────────────
step "Adjusting for this PC"
SYS="$HOME/.config/hypr/configs/SystemSettings.conf"
kb=$OPT_KB kbv=$OPT_KB_VARIANT
if [[ -z "$kb" ]]; then
    kb=$(grep -m1 -oP '^\s*kb_layout\s*=\s*\K\S+' "$BACKUP/hypr/configs/SystemSettings.conf" 2>/dev/null || true)
    [[ -z "$kb" ]] && kb=$(localectl status 2>/dev/null | awk -F': *' '/X11 Layout/ {print $2}')
    [[ -z "$kb" ]] && kb=$(localectl status 2>/dev/null | awk -F': *' '/VC Keymap/ {print $2}' | cut -d- -f1)
fi
if [[ -n "$kb" && "$kb" != "n/a" ]]; then
    sed -i -E "s/^([[:space:]]*kb_layout[[:space:]]*=).*/\1 $kb/; s/^([[:space:]]*kb_variant[[:space:]]*=).*/\1 $kbv/" "$SYS"
    echo "$kb" > "$HOME/.cache/kb_layout"
    echo "Keyboard layout: $kb${kbv:+ ($kbv)}"
fi
python3 -I "$HERE/installer/migrate-gpu-settings.py" || fail "Could not migrate existing graphics settings."
bash "$HOME/.config/hypr/scripts/GpuConfig.sh" || fail "Could not configure the detected graphics device."
if [[ "$DISTRO" == fedora ]]; then
    python3 "$HOME/.config/hypr/scripts/StartHyprland.py" --prepare-launcher || warn "Fast launcher cache unavailable; the native launcher will use its normal detection."
fi
if [[ "$MODE" != nvidia* && "$MODE" != hybrid-nvidia ]]; then      # NVIDIA-only variables break other GPUs
    sed -i -E 's/^(\s*env\s*=\s*(LIBVA_DRIVER_NAME|__GLX_VENDOR_LIBRARY_NAME|NVD_BACKEND),nvidia)/# (no NVIDIA GPU) \1/' \
        "$HOME/.config/hypr/configs/ENVariables.conf" 2>/dev/null
fi
echo "$OPT_LOCK" > "$HOME/.config/quickshell/lockscreen/style"

# CPU temperature sensor for the bar (AMD k10temp/zenpower, Intel coretemp)
cpu_hwmon="" cpu_input=temp1_input
for h in /sys/class/hwmon/hwmon*; do
    case "$(cat "$h/name" 2>/dev/null)" in k10temp|zenpower|coretemp|cpu_thermal)
        cpu_hwmon="$(readlink -f "$h/..")"; break ;; esac   # …/<device>/hwmon
done
for f in "$HOME/.config/waybar/configs/[TOP] Ultimate Desktop" "$HOME/.config/waybar/configs/[TOP] Ultimate Laptop"; do
    sed -i "s#@CPU_HWMON@#${cpu_hwmon:-/sys/class/hwmon}#; s#@CPU_TEMP_INPUT@#$cpu_input#" "$f"
done
echo "CPU sensor: ${cpu_hwmon:-none found}"

# Waybar
W="$HOME/.config/waybar"
case "$OPT_BAR" in
    liquid|liquid-v2|liquid-v3)
              WAYBAR_SKIP_RELOAD=1 bash "$HOME/.config/hypr/scripts/WaybarMode.sh" "$OPT_BAR" || fail "Could not configure Waybar mode." ;;
    glass)    ln -sfn "$W/configs/[TOP] Glass Islands" "$W/config"
              ln -sfn "$W/style/[Glass] Islands.css" "$W/style.css" ;;
    adaptive) ln -sfn "$W/configs/[TOP] Default Laptop" "$W/config"
              ln -sfn "$W/style/[0 VERTICAL] [Wallust] Adaptive.css" "$W/style.css" ;;
    ultimate) if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
                  ln -sfn "$W/configs/[TOP] Ultimate Laptop" "$W/config"
              else
                  ln -sfn "$W/configs/[TOP] Ultimate Desktop" "$W/config"
              fi
              ln -sfn "$W/style/[Ultimate] Glass Adaptive.css" "$W/style.css" ;;
    *)        fail "Unknown Waybar option: $OPT_BAR" ;;
esac
echo "Bar: $(basename "$(readlink "$W/config")") + $(basename "$(readlink "$W/style.css")")"

# Optional: 3.5mm jack stays on when jack detection is broken (onboard PCI HD-Audio card with an analog codec)
if (( OPT_JACK_FIX )); then
    card=""
    for c in /proc/asound/card*; do
        [[ -d "$c" ]] || continue
        grep -qs '^Codec:' "$c"/codec#* || continue
        grep -hs '^Codec:' "$c"/codec#* | grep -qviE 'hdmi|nvidia|ati r|generic' || continue   # skip HDMI-only codecs
        pci=$(basename "$(readlink -f "/sys/class/sound/$(basename "$c")/device")")
        [[ "$pci" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]$ ]] || continue
        card="alsa_card.pci-${pci//:/_}"; break       # 0000:2b:00.4 -> alsa_card.pci-0000_2b_00.4
    done
    if [[ -n "$card" ]]; then
        mkdir -p "$HOME/.local/share/wireplumber/scripts/device" "$HOME/.config/wireplumber/wireplumber.conf.d"
        sed "s|@CARD@|$card|" "$HERE/home/wireplumber/force-analog-profile.lua.in" \
            > "$HOME/.local/share/wireplumber/scripts/device/force-analog-profile.lua"
        cp "$HERE/home/wireplumber/90-force-analog-jack.conf" "$HOME/.config/wireplumber/wireplumber.conf.d/"
        echo "Jack fix: $card"
    else
        warn "Jack fix: no onboard analog sound card found; skipped."
    fi
fi

sub 40
mkdir -p "$HOME/Pictures/wallpapers" "$HOME/.config/hypr/wallpaper_effects"
WP=$(find "$HERE/wallpapers" -maxdepth 1 -type f -name 'current.*' -print -quit)
[[ -f "$WP" ]] || fail "The bundled wallpaper is missing."
if [[ -s "$BACKUP/hypr/wallpaper_effects/.wallpaper_current" ]]; then
    WP="$BACKUP/hypr/wallpaper_effects/.wallpaper_current"
fi
cp -a --update=none "$HERE/wallpapers/." "$HOME/Pictures/wallpapers/" || fail "Could not install the bundled wallpapers."
cp "$WP" "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current" || fail "Could not set the startup wallpaper."
# Give the shared loading scene a still on a fresh checkout without personal media.
splash="$HOME/.config/quickshell/login-splash/jake.png"
if [[ "$OPT_LOGIN" != sddm && ! -f "$splash" ]]; then
    python3 - "$WP" "$splash" <<'PY_IMAGE' || warn "Could not prepare the loading scene still."
from PIL import Image
import sys

with Image.open(sys.argv[1]) as image:
    image.convert("RGB").save(sys.argv[2], "PNG")
PY_IMAGE
fi
case "$DISTRO" in
    fedora) run sudo dnf install -y --skip-unavailable gcc pkgconf-pkg-config wayland-devel wayland-protocols-devel ;;
    arch)   run sudo pacman -S --needed --noconfirm gcc pkgconf wayland wayland-protocols ;;
    ubuntu) run sudo apt-get install -y gcc pkg-config libwayland-dev wayland-protocols ;;
esac || warn "Waiting-screen build tools unavailable; using the wallpaper fallback."
python3 "$HERE/native/startup-wallpaper/build-startup-wallpaper.py"
python3 "$HOME/.config/hypr/scripts/StartupWallpaperCache.py" || true
command -v wallust >/dev/null && wallust run "$WP" >/dev/null 2>&1 || true
python3 -I "$HOME/.config/hypr/scripts/AccentGuard.py" >/dev/null 2>&1 || true   # also builds the Accent-Folders icon theme
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
[[ -d /usr/share/themes/Flat-Remix-GTK-Blue-Dark || -d "$HOME/.themes/Flat-Remix-GTK-Blue-Dark" ]] \
    && gsettings set org.gnome.desktop.interface gtk-theme 'Flat-Remix-GTK-Blue-Dark' 2>/dev/null
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice' 2>/dev/null || true
gsettings set org.blueman.general plugin-list "['!StatusIcon', '!StatusNotifierItem']" 2>/dev/null || true
kvantummanager --set catppuccin-mocha-blue >/dev/null 2>&1 || true
xdg-mime default org.gnome.Nautilus.desktop inode/directory 2>/dev/null || true

# ── 8. login screen ─────────────────────────────────────────────────────────
step "Setting up the login screen"
run sudo python3 "$HERE/installer/install-session.py" || fail "Could not install the portable Hyprland session."
if [[ "$OPT_LOGIN" == sddm ]]; then
    d_sddm
    run sudo bash "$HERE/installer/session/install-sddm.sh" "$HOME/.local/share/hypr-login-themes" || fail "Could not install the SDDM theme."
    scene="$HOME/.config/quickshell/login-splash"
    artwork="$SDDM_THEME_DIR/Components/jake.png"
    [[ -f "$artwork" ]] || fail "The SDDM theme is missing its login artwork ($artwork); see the log."
    cp "$artwork" "$scene/jake.png" || fail "Could not install the desktop login artwork."
    if [[ -f "$scene/transition.png" ]]; then
        mkdir -p "$BACKUP" || fail "Could not create the configuration backup."
        mv "$scene/transition.png" "$BACKUP/previous-transition.png" || fail "Could not back up the previous transition frame."
    fi
    python3 "$HOME/.config/hypr/scripts/StartupWallpaperCache.py"
    run sudo systemctl enable -f sddm || fail "Couldn't enable SDDM."
    for dm in "${DM_OTHERS[@]}"; do
        if systemctl is-enabled "$dm" >/dev/null 2>&1; then
            run sudo systemctl disable "$dm" || fail "Could not disable $dm."
        fi
    done
fi
run sudo python3 "$HERE/installer/select-session.py" "$USER" || fail "Could not select the Hyprland session."
if ! systemctl is-enabled display-manager >/dev/null 2>&1 && [[ "$OPT_LOGIN" != sddm ]]; then
    note "NO_LOGIN_SCREEN"
    echo "No login screen is installed: log in on the console and type Hyprland (or re-run with the SDDM option)."
fi

# ── 9. finish ───────────────────────────────────────────────────────────────
step "Finishing"
"$HOME/.config/hypr/scripts/GpuInfo.sh"
# Let Hyprland parse the installed config (strict: compatibility problems count too) before the first login
cfg="$HOME/.config/hypr/hyprland.lua"
[[ -f "$cfg" ]] || cfg="$HOME/.config/hypr/hyprland.conf"
verify=$(HYPRLANG_STRICT=1 timeout 60 Hyprland --verify-config --config "$cfg" 2>&1 </dev/null)
if grep -q 'Config parsing result' <<<"$verify"; then
    if grep -qx 'config ok' <<<"$verify"; then
        echo "Hyprland config check: ok"
    else
        sed -n '/Config parsing result/,$p' <<<"$verify"
        warn "Hyprland reported problems in the installed config (details in the log); the desktop may look different until they are fixed."
    fi
fi
[[ ! -d "$BACKUP" ]] || note "BACKUP $BACKUP"
note "LOG $LOGFILE"
echo "@@PROGRESS 100"
echo "@@DONE"
