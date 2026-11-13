# Arch Linux (and Arch-based: EndeavourOS, CachyOS, Manjaro…) - sourced by installer/backend.sh
# Hyprland and almost everything else come from the official repos; a few packages from the AUR (via yay).

DISTRO_LABEL="Arch Linux"
PING_URL="https://archlinux.org"

d_check() {
    [[ "$ID" == arch || " ${ID_LIKE:-} " == *" arch "* ]]
}

d_prepare() {
    run sudo pacman -Sy --needed --noconfirm git curl base-devel pciutils libnewt \
        || fail "Couldn't install the basic tools (git, curl, base-devel)."
}

d_repos() {
    if ! command -v yay >/dev/null && ! command -v paru >/dev/null; then
        echo "Installing yay (AUR helper)"
        local t; t=$(mktemp -d -p "$HOME")
        run git clone -q --depth=1 https://aur.archlinux.org/yay-bin.git "$t/yay-bin" || fail "Couldn't download yay."
        (cd "$t/yay-bin" && makepkg -si --noconfirm) || fail "Couldn't build yay."
        rm -rf "$t"
    fi
}

aur() {  # aur <pkgs…>  (yay or paru, whichever is installed)
    local h; h=$(command -v yay || command -v paru)
    run "$h" -S --needed --noconfirm --answerdiff None --answerclean None --removemake "$@"
}

d_base() {
    run sudo pacman -Syu --needed --noconfirm \
        hyprland hypridle hyprlock hyprpicker hyprsunset hyprpolkitagent hyprland-guiutils \
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk qt5-wayland qt6-wayland \
        waybar rofi swaync awww quickshell qt6-multimedia qt6-5compat qt6-svg \
        qt5ct qt6ct kvantum nwg-look nwg-displays gnome-themes-extra adwaita-icon-theme papirus-icon-theme \
        pipewire pipewire-pulse wireplumber gvfs xdg-user-dirs xdg-utils \
        blueman bluez bluez-utils networkmanager network-manager-applet power-profiles-daemon \
        ttf-jetbrains-mono-nerd ttf-fira-code otf-font-awesome noto-fonts noto-fonts-emoji \
        zsh kitty \
        || fail "Couldn't install Hyprland and its tools."
    aur wallust wlogout bibata-cursor-theme-bin flat-remix-gtk \
        || warn "Some AUR packages (wallust, wlogout, cursor/GTK theme) didn't install; see the log."
    run sudo systemctl enable --now bluetooth.service power-profiles-daemon.service || true
    run sudo systemctl enable NetworkManager.service || true
}

d_drivers() {
    case " $GPUS " in *" intel "*)
        run sudo pacman -S --needed --noconfirm intel-media-driver vulkan-intel ;; esac
    case " $GPUS " in *" amd "*)
        run sudo pacman -S --needed --noconfirm mesa vulkan-radeon ;; esac   # VA-API is part of mesa now
    case " $GPUS " in *" nvidia "*)
        if [[ -n "$NVIDIA_DRIVER" ]]; then
            echo "NVIDIA driver already installed ($NVIDIA_DRIVER)."
        else
            local kernels=() k
            for k in linux linux-lts linux-zen linux-hardened; do pacman -Q "$k" >/dev/null 2>&1 && kernels+=("$k"); done
            if [[ "$NVIDIA_ARCH" == legacy ]]; then
                # Maxwell/Pascal/Volta: the open modules don't support them; proprietary 580 branch from the AUR
                run sudo pacman -S --needed --noconfirm "${kernels[@]/%/-headers}" dkms
                aur nvidia-580xx-dkms nvidia-580xx-utils || fail "Couldn't install the NVIDIA 580 driver."
            elif [[ "${kernels[*]}" == linux ]]; then
                run sudo pacman -S --needed --noconfirm nvidia-open || fail "Couldn't install the NVIDIA driver."
            else
                run sudo pacman -S --needed --noconfirm nvidia-open-dkms dkms "${kernels[@]/%/-headers}" \
                    || fail "Couldn't install the NVIDIA driver."
            fi
            if [[ "$NVIDIA_ARCH" != legacy ]]; then
                run sudo pacman -S --needed --noconfirm nvidia-utils nvidia-settings libva-nvidia-driver egl-wayland \
                    || fail "Couldn't install NVIDIA userspace tools."
            fi
            # keep nouveau out of the initramfs, enable KMS
            if grep -qE '^HOOKS=.*\bkms\b' /etc/mkinitcpio.conf; then
                sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
                sudo sed -i -E '/^HOOKS=/ s/ kms//' /etc/mkinitcpio.conf
            fi
            echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia-drm.conf >/dev/null
            run sudo mkinitcpio -P
            run sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service || true
            [[ "$SECURE_BOOT" == 1 ]] && warn "Secure Boot is on: sign the NVIDIA modules yourself (e.g. with sbctl) or turn Secure Boot off."
            note "NVIDIA_INSTALLED"
        fi
        ;; esac
}

d_extras() {
    run sudo pacman -S --needed --noconfirm \
        cava wf-recorder tesseract tesseract-data-eng cliphist grim slurp swappy wl-clipboard \
        imagemagick ffmpeg mpv fastfetch lsd fzf playerctl jq yad bc inxi wget unzip \
        libnotify libqalculate qalculate-gtk pamixer pavucontrol brightnessctl btop nvtop \
        python-gobject python-requests python-pillow gtk4 libadwaita \
        nautilus python-nautilus thunar mokutil \
        || fail "Couldn't install the desktop's apps."
    aur mpvpaper || warn "mpvpaper (video wallpapers) didn't install."
}

d_sddm() {
    run sudo pacman -S --needed --noconfirm sddm qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg || fail "Couldn't install SDDM."
}
DM_OTHERS=(gdm lightdm ly greetd)
