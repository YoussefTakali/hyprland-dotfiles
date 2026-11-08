#!/usr/bin/env bash
# Desktop installer backend: does the whole installation, step by step, without asking questions.
# The graphical installer (installer/setup.py) runs it and reads its progress lines; install.sh runs it in a
# terminal. Run as the user who gets the desktop (not root); it uses sudo, which the caller must have unlocked
# (the graphical installer installs a temporary password-less sudo rule for the duration, see grant.sh).
#
# Choices come from the environment (defaults in brackets):
#   OPT_KB=<xkb layout>        [this PC's]         OPT_KB_VARIANT=<variant> [""]
#   OPT_LOCK=Slate|Iris|Fog|Cards [Slate]        OPT_BAR=adaptive|glass   [adaptive]
#   OPT_LOGIN=keep|sddm        [keep: GNOME's login screen starts Hyprland]
#   OPT_DRIVERS=1|0            [1: install the graphics drivers this PC needs]
#   OPT_MOK_PASSWORD=<pw>      one-time password to approve the NVIDIA driver key at the next boot (Secure Boot on)
#   OPT_SKIP_BASE=1            skip the Hyprland base (packages) — configs only
#
# Progress protocol (one per line, everything else is log):
#   @@STEP <n> <total> <title>   @@PROGRESS <0-100>   @@NOTE <text for the final page>   @@WARN <text>
#   @@DONE                       @@FAIL <what failed>
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"          # the repository
KOOL="$HOME/Fedora-Hyprland"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/.config-backup-$STAMP"
LOGFILE="$HOME/.cache/desktop-install-$STAMP.log"
mkdir -p "$HOME/.cache"
exec > >(tee -a "$LOGFILE") 2>&1

: "${OPT_LOCK:=Slate}" "${OPT_BAR:=adaptive}" "${OPT_LOGIN:=keep}" "${OPT_DRIVERS:=1}" "${OPT_SKIP_BASE:=0}"
: "${OPT_KB:=}" "${OPT_KB_VARIANT:=}" "${OPT_MOK_PASSWORD:=}"

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
sudo -n true 2>/dev/null || fail "Administrator access is needed (sudo). Start the installer again and enter your password."

# KooL's scripts call chsh (asks for a password) and offer "systemctl reboot"; neither may happen mid-install
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

eval "$("$HERE/config/hypr/scripts/GpuInfo.sh")"

# ── 1. prepare ───────────────────────────────────────────────────────────────
step "Checking this PC"
grep -qi '^ID=fedora' /etc/os-release || fail "This installer is for Fedora (found: $(. /etc/os-release; echo "$PRETTY_NAME"))."
. /etc/os-release
echo "System: $PRETTY_NAME, graphics: $MODE ($GPUS), Secure Boot: $SECURE_BOOT"
curl -sfI --max-time 10 https://fedoraproject.org >/dev/null || fail "No internet connection. Connect to the internet and try again."
free_gb=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9)
(( free_gb >= 8 )) || fail "At least 8 GB of free disk space is needed (found ${free_gb} GB)."
run sudo dnf install -y -q git curl whiptail || fail "Couldn't install the basic tools (git, curl)."

# ── 2. repositories ─────────────────────────────────────────────────────────
step "Adding software sources"
fv=$(rpm -E %fedora)
if ! rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
    run sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fv.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fv.noarch.rpm" \
        || fail "Couldn't add RPM Fusion (needed for graphics drivers and video codecs)."
fi
sub 40
run sudo dnf copr enable -y errornointernet/quickshell || warn "Quickshell source not added."
run sudo dnf copr enable -y sdegler/hyprland || warn "Hyprland source (sdegler) not added."

# ── 3. Hyprland base (KooL's component scripts, without KooL's menus) ────────
step "Installing Hyprland and its tools (this is the long part)"
if (( OPT_SKIP_BASE )); then
    echo "Skipped (OPT_SKIP_BASE=1)"
else
    if [[ -d "$KOOL/.git" ]]; then run git -C "$KOOL" pull -q --ff-only || true
    else run git clone -q --depth=1 https://github.com/JaKooLit/Fedora-Hyprland.git "$KOOL" || fail "Couldn't download the KooL Hyprland base."; fi
    parts=(copr.sh 00-hypr-pkgs.sh fonts.sh hyprland.sh gtk_themes.sh InputGroup.sh quickshell.sh xdph.sh
           bluetooth.sh thunar.sh thunar_default.sh zsh.sh)
    i=0
    for p in "${parts[@]}"; do
        i=$((i + 1)); sub $(( i * 100 / (${#parts[@]} + 1) ))
        echo "── KooL: $p"
        if [[ -f "$KOOL/install-scripts/$p" ]]; then
            (cd "$KOOL" && bash "install-scripts/$p" </dev/null) || warn "KooL step $p reported a problem (see the log)."
        else
            warn "KooL step $p no longer exists; skipped."
        fi
    done
    command -v Hyprland >/dev/null || fail "Hyprland didn't get installed (see the log)."
fi

# ── 4. graphics drivers ─────────────────────────────────────────────────────
step "Setting up graphics ($MODE)"
if (( OPT_DRIVERS )); then
    case " $GPUS " in *" intel "*)
        [[ "${INTEL_VA:-}" == i965 ]] && run sudo dnf install -y libva-intel-driver || run sudo dnf install -y intel-media-driver
        ;; esac
    case " $GPUS " in *" amd "*)
        # Fedora's Mesa can't hardware-decode H.264/HEVC (patents); RPM Fusion's "freeworld" build can
        rpm -q mesa-va-drivers-freeworld >/dev/null || run sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld \
            || warn "AMD video decoding drivers not installed; videos will decode on the CPU."
        ;; esac
    case " $GPUS " in *" nvidia "*)
        if [[ -n "$NVIDIA_DRIVER" ]] || rpm -q akmod-nvidia >/dev/null 2>&1; then
            echo "NVIDIA driver already installed (${NVIDIA_DRIVER:-installed, loads after reboot})."
        else
            pkgs=(akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-power libva-nvidia-driver)
            if [[ "$NVIDIA_ARCH" == legacy ]]; then
                if dnf list -q --available akmod-nvidia-580xx >/dev/null 2>&1; then
                    pkgs=(akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda xorg-x11-drv-nvidia-580xx-power libva-nvidia-driver)
                else
                    warn "This NVIDIA card is older than the cards the current driver supports; installing the current driver anyway."
                fi
            fi
            run sudo dnf install -y "${pkgs[@]}" || fail "Couldn't install the NVIDIA driver."
            sub 30
            if [[ "$SECURE_BOOT" == 1 ]]; then
                # The driver is built on this PC, so it must be signed with a key the firmware trusts
                run sudo kmodgenca -a
                if [[ -n "$OPT_MOK_PASSWORD" ]]; then
                    h=$(mktemp); mokutil --generate-hash="$OPT_MOK_PASSWORD" > "$h"
                    run sudo mokutil --import /etc/pki/akmods/certs/public_key.der --hash-file "$h" \
                        && note "SECURE_BOOT_KEY" || warn "Couldn't queue the driver key for Secure Boot."
                    rm -f "$h"
                else
                    warn "Secure Boot is on but no key password was given: the NVIDIA driver won't load until its key is approved."
                fi
            fi
            echo "Building the NVIDIA driver for this kernel (a few minutes)…"
            run sudo akmods --force --kernels "$(uname -r)" || true
            modinfo -k "$(uname -r)" nvidia >/dev/null 2>&1 || fail "The NVIDIA driver didn't build for this kernel (see the log)."
            sub 80
            run sudo grubby --update-kernel=ALL --args="rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1 nvidia-drm.fbdev=1"
            run sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service || true
            note "NVIDIA_INSTALLED"
        fi
        ;; esac
else
    echo "Driver installation skipped (OPT_DRIVERS=0)."
fi

# ── 5. extra packages ───────────────────────────────────────────────────────
step "Installing the desktop's apps and tools"
run sudo dnf install -y --skip-unavailable \
    quickshell mpvpaper /usr/bin/ffmpeg qt6-qtmultimedia qt6-qt5compat qt6-qtsvg \
    cava wf-recorder tesseract tesseract-langpack-eng hyprpicker cliphist grim slurp swappy wl-clipboard \
    ImageMagick fastfetch lsd fzf kitty playerctl blueman nautilus thunar \
    python3-gobject jq tuned-ppd libnotify julietaula-montserrat-fonts nautilus-python mokutil qalculate \
    || fail "Couldn't install the desktop's apps."

# ── 6. configs ──────────────────────────────────────────────────────────────
step "Installing the desktop's settings"
mkdir -p "$BACKUP" "$HOME/.config"
for d in "$HERE"/config/*; do n=$(basename "$d"); [[ -e "$HOME/.config/$n" ]] && cp -a "$HOME/.config/$n" "$BACKUP/"; done
[[ -f "$HOME/.zshrc" ]] && cp -a "$HOME/.zshrc" "$BACKUP/zshrc"
echo "Previous settings saved in $BACKUP"
cp -a "$HERE"/config/. "$HOME/.config/"
cp -a "$HERE/home/.zshrc" "$HOME/.zshrc"
grep -rlI "/home/rhast" "$HOME/.config/"{hypr,waybar,rofi,kitty,quickshell,fastfetch,gtk-3.0,gtk-4.0,gtk-theme} 2>/dev/null \
    | xargs -r sed -i "s|/home/rhast|$HOME|g"
sed -i "s|hello, rhast|hello, $USER|" "$HOME/.config/fastfetch/config-wall.jsonc" 2>/dev/null
sed -i "s|\${SUDO_USER:-rhast}|\${SUDO_USER:-$USER}|" "$HOME/.config/hypr/UserScripts/sddm-login-fix.sh" 2>/dev/null
find "$HOME/.config/hypr" "$HOME/.config/fastfetch" -name '*.sh' -exec chmod +x {} +
chmod +x "$HOME/.config/hypr/UserScripts/"*.py "$HOME/.config/hypr/scripts/"*.py "$HOME/.config/hypr/bin/"* 2>/dev/null
mkdir -p "$HOME/.local/share/rofi/themes" && ln -snf "$HOME/.config/rofi/themes/"* "$HOME/.local/share/rofi/themes/" 2>/dev/null
xdg-user-dirs-update 2>/dev/null || true
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    mkdir -p "$HOME/.oh-my-zsh/custom/themes" && cp "$HERE/oh-my-zsh/agnosterzak-mocha.zsh-theme" "$HOME/.oh-my-zsh/custom/themes/"
fi
mkdir -p "$HOME/.local/share/nautilus-python/extensions" "$HOME/.local/share/applications"
cp "$HERE/home/nautilus-python/open-in-kitty.py" "$HOME/.local/share/nautilus-python/extensions/"
sed "s|@HOME@|$HOME|g" "$HERE/home/applications/io.github.YoussefTakali.Shortcuts.desktop" \
    > "$HOME/.local/share/applications/io.github.YoussefTakali.Shortcuts.desktop"

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
    echo "Keyboard layout: $kb${kbv:+ ($kbv)}"
fi
"$HOME/.config/hypr/scripts/GpuConfig.sh"
if [[ "$MODE" != nvidia* && "$MODE" != hybrid-nvidia ]]; then      # NVIDIA-only variables break other GPUs
    sed -i -E 's/^(\s*env\s*=\s*(LIBVA_DRIVER_NAME|__GLX_VENDOR_LIBRARY_NAME|NVD_BACKEND),nvidia)/# (no NVIDIA GPU) \1/' \
        "$HOME/.config/hypr/configs/ENVariables.conf" 2>/dev/null
fi
echo "$OPT_LOCK" > "$HOME/.config/quickshell/lockscreen/style"
if [[ "$OPT_BAR" == glass ]]; then
    ln -sfn "$HOME/.config/waybar/configs/[TOP] Glass Islands" "$HOME/.config/waybar/config"
    ln -sfn "$HOME/.config/waybar/style/[Glass] Islands.css" "$HOME/.config/waybar/style.css"
else
    ln -sfn "$HOME/.config/waybar/configs/[TOP] Default Laptop" "$HOME/.config/waybar/config"
    ln -sfn "$HOME/.config/waybar/style/[0 VERTICAL] [Wallust] Adaptive.css" "$HOME/.config/waybar/style.css"
fi
sub 40
mkdir -p "$HOME/Pictures/wallpapers" "$HOME/.config/hypr/wallpaper_effects"
W=$(ls "$HERE"/wallpapers/current.* | head -1)
cp "$W" "$HOME/Pictures/wallpapers/"
cp "$W" "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"
command -v wallust >/dev/null && wallust run "$W" >/dev/null 2>&1 || true
python3 -I "$HOME/.config/hypr/scripts/AccentGuard.py" >/dev/null 2>&1 || true
SRC_ICONS="$HOME/.icons/Flat-Remix-Blue-Dark" DST_ICONS="$HOME/.icons/Flat-Remix-Mauve-Dark"
if [[ -d "$SRC_ICONS" && ! -d "$DST_ICONS" ]]; then
    mkdir -p "$DST_ICONS" && cp -r "$SRC_ICONS/places" "$DST_ICONS/"
    find "$DST_ICONS/places" -type f -name '*.svg' -exec sed -i 's/#367bf0/#a374ec/gI; s/#2b62c0/#7c4cc9/gI' {} +
    sed 's/^Name=.*/Name=Flat-Remix-Mauve-Dark/; s/^Inherits=.*/Inherits=Flat-Remix-Blue-Dark,breeze-dark,elementary,gnome,hicolor/' \
        "$SRC_ICONS/index.theme" > "$DST_ICONS/index.theme"
    gtk-update-icon-cache -f -t "$DST_ICONS" >/dev/null 2>&1 || true
fi
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
[[ -d "$DST_ICONS" ]] && gsettings set org.gnome.desktop.interface icon-theme 'Flat-Remix-Mauve-Dark' 2>/dev/null || true
gsettings set org.blueman.general plugin-list "['!StatusIcon', '!StatusNotifierItem']" 2>/dev/null || true
xdg-mime default org.gnome.Nautilus.desktop inode/directory 2>/dev/null || true

# ── 8. login screen ─────────────────────────────────────────────────────────
step "Setting up the login screen"
if [[ "$OPT_LOGIN" == sddm ]]; then
    run sudo dnf install -y sddm qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia || fail "Couldn't install SDDM."
    T=/usr/share/sddm/themes/sddm-astronaut-theme
    [[ -d "$T" ]] || { run sudo git clone -q --depth=1 https://github.com/Keyitdev/sddm-astronaut-theme.git "$T" \
        && sudo cp -r "$T/Fonts/." /usr/share/fonts/ 2>/dev/null; }
    sudo sed -i 's|^ConfigFile=.*|ConfigFile=Themes/jake_the_dog.conf|' "$T/metadata.desktop" 2>/dev/null
    printf '[Theme]\nCurrent=sddm-astronaut-theme\n' | sudo tee /etc/sddm.conf.d/10-theme.conf >/dev/null
    run sudo bash "$HOME/.config/hypr/UserScripts/sddm-login-fix.sh"
    [[ "$MODE" == hybrid-* ]] && run sudo bash "$HOME/.config/hypr/UserScripts/gpu-login-screen-fix.sh"
    systemctl is-enabled gdm >/dev/null 2>&1 && run sudo systemctl disable gdm
    run sudo systemctl enable sddm
else
    # GNOME's login screen: pre-select Hyprland for this user
    printf '[User]\nSession=hyprland\nSystemAccount=false\n' | sudo tee "/var/lib/AccountsService/users/$USER" >/dev/null
    echo "The login screen will start Hyprland for $USER."
fi

# ── 9. finish ───────────────────────────────────────────────────────────────
step "Finishing"
"$HOME/.config/hypr/scripts/GpuInfo.sh"
note "BACKUP $BACKUP"
note "LOG $LOGFILE"
echo "@@PROGRESS 100"
echo "@@DONE"
