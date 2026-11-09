# Ubuntu 26.04 LTS and newer - sourced by installer/backend.sh
# Hyprland comes from the cppiber/hyprland PPA (0.57 for 26.04 / 26.10). Ubuntu itself packages most tools;
# what it doesn't (wallust, awww, mpvpaper; Quickshell before 26.10) is built from source into /usr/local.
# Older releases can't run this desktop: 24.04/25.10 ship an X11-only rofi and a Qt too old for Quickshell.

DISTRO_LABEL="Ubuntu"
PING_URL="https://launchpad.net"
BUILD="$HOME/.cache/desktop-build"
export DEBIAN_FRONTEND=noninteractive

d_check() {
    [[ "$ID" == ubuntu || " ${ID_LIKE:-} " == *" ubuntu "* ]] || return 1
    local v=${VERSION_ID:-0}
    [[ " ${ID_LIKE:-} " == *" ubuntu "* ]] && v=$(. "${OS_RELEASE:-/etc/os-release}"; echo "${UBUNTU_VERSION_ID:-$v}")  # Mint/Pop report their own number
    if awk -v v="$v" 'BEGIN{exit !(v+0 < 26.04)}'; then
        fail "Ubuntu $v is too old for this desktop (its rofi has no Wayland support and its Qt can't run Quickshell). Ubuntu 26.04 LTS or newer is needed."
    fi
}

apt_install() { run sudo -E apt-get install -y --no-install-recommends "$@"; }

d_prepare() {
    run sudo -E apt-get update -q || fail "Couldn't update the package lists."
    apt_install git curl ca-certificates software-properties-common whiptail pciutils \
        || fail "Couldn't install the basic tools (git, curl)."
}

d_repos() {
    run sudo add-apt-repository -y universe || warn "Couldn't enable 'universe'."
    run sudo add-apt-repository -y ppa:cppiber/hyprland || fail "Couldn't add the Hyprland PPA (ppa:cppiber/hyprland)."
    run sudo -E apt-get update -q || fail "Couldn't update the package lists."
}

d_base() {
    apt_install \
        hyprland hypridle hyprlock hyprpicker hyprsunset hyprpolkitagent hyprland-guiutils \
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk qt6-wayland qtwayland5 \
        waybar rofi sway-notification-center wlogout \
        qt5ct qt6ct qt5-style-kvantum qt6-style-kvantum nwg-look nwg-displays \
        gnome-themes-extra adwaita-icon-theme papirus-icon-theme \
        pipewire-pulse wireplumber gvfs-backends xdg-user-dirs \
        blueman bluez network-manager-gnome power-profiles-daemon \
        fonts-jetbrains-mono fonts-font-awesome fonts-noto-color-emoji \
        zsh kitty \
        || fail "Couldn't install Hyprland and its tools."
    sub 40
    # Quickshell: packaged from 26.10 on, built from source on 26.04
    if apt-cache show quickshell >/dev/null 2>&1; then
        apt_install quickshell || fail "Couldn't install Quickshell."
    elif ! command -v quickshell >/dev/null; then
        build_quickshell
    fi
    apt_install qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-window \
        qml6-module-qtmultimedia qml6-module-qt5compat-graphicaleffects qml6-module-qtquick-effects \
        qml6-module-qtqml-workerscript qml6-module-qtquick-shapes qml6-module-qtquick-dialogs qt6-svg-plugins \
        || warn "Some Qt modules for the lock screen didn't install."
    sub 70
    command -v wallust >/dev/null || build_wallust
    command -v awww >/dev/null || command -v swww >/dev/null || build_awww
    themes_ubuntu
    run sudo systemctl enable --now bluetooth.service power-profiles-daemon.service || true
}

# ── source builds (into /usr/local) ─────────────────────────────────────────
build_deps_rust() { apt_install build-essential pkg-config cargo rustc || fail "Couldn't install the Rust compiler."; }

build_quickshell() {
    echo "Building Quickshell v0.3.2 from source (Ubuntu doesn't package it yet; ~10 minutes)"
    apt_install build-essential cmake ninja-build pkg-config spirv-tools \
        qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev \
        qt6-wayland-dev qt6-wayland-private-dev qt6-shadertools-dev qt6-svg-dev \
        libwayland-dev wayland-protocols libcli11-dev libjemalloc-dev libpipewire-0.3-dev libpam0g-dev \
        libpolkit-agent-1-dev libglib2.0-dev libdrm-dev libgbm-dev libxcb1-dev \
        || fail "Couldn't install Quickshell's build tools."
    mkdir -p "$BUILD"; rm -rf "$BUILD/quickshell"
    run git clone -q --depth=1 --branch v0.3.2 https://github.com/quickshell-mirror/quickshell.git "$BUILD/quickshell" \
        || fail "Couldn't download Quickshell."
    ( cd "$BUILD/quickshell" \
      && cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr/local \
               -DCRASH_HANDLER=OFF -DDISTRIBUTOR="hyprland-dotfiles installer (source build)" \
      && cmake --build build \
      && sudo cmake --install build ) || fail "Quickshell didn't build (see the log)."
}

build_wallust() {
    echo "Building wallust (colours from the wallpaper)"
    build_deps_rust
    local root; root=$(mktemp -d)
    run cargo install --locked --root "$root" wallust || fail "wallust didn't build."
    run sudo install -m755 "$root/bin/wallust" /usr/local/bin/wallust
    rm -rf "$root"
}

build_awww() {
    echo "Building awww (wallpaper daemon)"
    build_deps_rust
    apt_install liblz4-dev libwayland-dev wayland-protocols || fail "Couldn't install awww's build tools."
    mkdir -p "$BUILD"; rm -rf "$BUILD/awww"
    run git clone -q --depth=1 --branch v0.12.1 https://codeberg.org/LGFae/awww.git "$BUILD/awww" || fail "Couldn't download awww."
    ( cd "$BUILD/awww" && cargo build --release --locked ) || fail "awww didn't build."
    run sudo install -m755 "$BUILD/awww/target/release/awww" "$BUILD/awww/target/release/awww-daemon" /usr/local/bin/
}

build_mpvpaper() {
    echo "Building mpvpaper (video wallpapers)"
    apt_install build-essential meson ninja-build pkg-config libmpv-dev libwayland-dev wayland-protocols libegl-dev \
        || { warn "mpvpaper's build tools didn't install; video wallpapers won't work."; return; }
    mkdir -p "$BUILD"; rm -rf "$BUILD/mpvpaper"
    run git clone -q --depth=1 --branch 1.2.1 https://github.com/GhostNaN/mpvpaper.git "$BUILD/mpvpaper" || { warn "Couldn't download mpvpaper."; return; }
    ( cd "$BUILD/mpvpaper" && meson setup build --prefix=/usr/local && ninja -C build && sudo ninja -C build install ) \
        || warn "mpvpaper didn't build; video wallpapers won't work."
}

themes_ubuntu() {  # cursor + GTK theme the configs expect (Arch: AUR, Fedora: KooL's gtk_themes.sh)
    if [[ ! -d "$HOME/.icons/Bibata-Modern-Ice" && ! -d /usr/share/icons/Bibata-Modern-Ice ]]; then
        local t; t=$(mktemp -d)
        curl -fsSL --retry 3 -o "$t/b.tar.xz" https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Ice.tar.xz \
            && mkdir -p "$HOME/.icons" && tar -xJf "$t/b.tar.xz" -C "$HOME/.icons" || warn "Cursor theme (Bibata) not installed."
        rm -rf "$t"
    fi
    if [[ ! -d "$HOME/.themes/Flat-Remix-GTK-Blue-Dark" ]]; then
        local t; t=$(mktemp -d)
        git clone -q --depth=1 https://github.com/daniruiz/flat-remix-gtk.git "$t/fr" \
            && mkdir -p "$HOME/.themes" && cp -r "$t/fr/themes/Flat-Remix-GTK-Blue-Dark" "$HOME/.themes/" \
            || warn "GTK theme (Flat-Remix) not installed."
        rm -rf "$t"
    fi
}

d_drivers() {
    case " $GPUS " in *" intel "*) apt_install intel-media-va-driver-non-free || true ;; esac
    case " $GPUS " in *" amd "*)   apt_install mesa-vulkan-drivers || true ;; esac      # VA-API is in mesa itself
    case " $GPUS " in *" nvidia "*)
        if [[ -n "$NVIDIA_DRIVER" ]]; then
            echo "NVIDIA driver already installed ($NVIDIA_DRIVER)."
        else
            apt_install ubuntu-drivers-common || fail "Couldn't install ubuntu-drivers."
            run sudo ubuntu-drivers install || fail "Couldn't install the NVIDIA driver."
            apt_install libnvidia-egl-wayland1 nvidia-vaapi-driver 2>/dev/null || true
            echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia-drm.conf >/dev/null
            run sudo update-initramfs -u
            [[ "$SECURE_BOOT" == 1 ]] && warn "Secure Boot is on: Ubuntu asks to enroll the driver key (MOK) at the next boot; choose 'Enroll MOK' and use the password you're asked for."
            note "NVIDIA_INSTALLED"
        fi
        ;; esac
}

d_extras() {
    apt_install \
        cava wf-recorder tesseract-ocr tesseract-ocr-eng cliphist grim slurp swappy wl-clipboard \
        imagemagick ffmpeg mpv mpv-mpris fastfetch lsd fzf playerctl jq yad bc inxi wget unzip \
        libnotify-bin qalculate-gtk pamixer pavucontrol brightnessctl btop nvtop \
        python3-gi python3-requests python3-pil gir1.2-adw-1 gir1.2-gtk-4.0 \
        nautilus python3-nautilus thunar mokutil \
        || fail "Couldn't install the desktop's apps."
    command -v mpvpaper >/dev/null || build_mpvpaper
}

d_sddm() {
    apt_install sddm qml6-module-qtquick-virtualkeyboard qt6-virtualkeyboard-plugin qml6-module-qtmultimedia qt6-svg-plugins \
        || fail "Couldn't install SDDM."
    echo /usr/bin/sddm | sudo tee /etc/X11/default-display-manager >/dev/null
}
DM_OTHERS=(gdm3 gdm lightdm)
