# Fedora - sourced by installer/backend.sh
# Base: JaKooLit's Fedora-Hyprland component scripts (without KooL's menus); RPM Fusion + COPRs for the rest.

DISTRO_LABEL="Fedora"
PING_URL="https://fedoraproject.org"
KOOL="$HOME/Fedora-Hyprland"

d_check() { [[ "$ID" == fedora ]]; }

d_prepare() {
    run sudo dnf install -y -q git curl newt pciutils || fail "Couldn't install the basic tools (git, curl)."
}

d_repos() {
    local fv; fv=$(rpm -E %fedora)
    if ! rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
        run sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fv.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fv.noarch.rpm" \
            || fail "Couldn't add RPM Fusion (needed for graphics drivers and video codecs)."
    fi
    sub 40
    run sudo dnf copr enable -y sdegler/hyprland || warn "Hyprland source (sdegler) not added."
    # Quickshell is in Fedora itself since F45; the COPR covers older releases
    rpm -E %fedora | awk '{exit !($1 < 45)}' && { run sudo dnf copr enable -y errornointernet/quickshell || warn "Quickshell source not added."; }
}

d_base() {
    if [[ -d "$KOOL/.git" ]]; then run git -C "$KOOL" pull -q --ff-only || true
    else run git clone -q --depth=1 https://github.com/JaKooLit/Fedora-Hyprland.git "$KOOL" || fail "Couldn't download the KooL Hyprland base."; fi
    local parts=(copr.sh 00-hypr-pkgs.sh fonts.sh hyprland.sh gtk_themes.sh InputGroup.sh quickshell.sh xdph.sh
                 bluetooth.sh thunar.sh thunar_default.sh zsh.sh) i=0 p
    for p in "${parts[@]}"; do
        i=$((i + 1)); sub $(( i * 100 / (${#parts[@]} + 1) ))
        echo "── KooL: $p"
        if [[ -f "$KOOL/install-scripts/$p" ]]; then
            (cd "$KOOL" && bash "install-scripts/$p" </dev/null) || warn "KooL step $p reported a problem (see the log)."
        else
            warn "KooL step $p no longer exists; skipped."
        fi
    done
}

d_drivers() {
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
            return
        fi
        local pkgs=(akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-power libva-nvidia-driver)
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
                local h; h=$(mktemp); mokutil --generate-hash="$OPT_MOK_PASSWORD" > "$h"
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
        ;; esac
}

d_extras() {
    run sudo dnf install -y --skip-unavailable \
        quickshell waybar swww swaync python3-pillow gtk3 gtk-layer-shell bluez mpvpaper /usr/bin/ffmpeg qt6-qtmultimedia qt6-qt5compat qt6-qtsvg \
        cava wf-recorder tesseract tesseract-langpack-eng hyprpicker cliphist grim slurp swappy wl-clipboard \
        ImageMagick fastfetch lsd fzf kitty playerctl blueman nautilus Thunar \
        python3-gobject jq tuned-ppd libnotify julietaula-montserrat-fonts nautilus-python mokutil qalculate \
        || fail "Couldn't install the desktop's apps."
}

d_sddm() {
    run sudo dnf install -y sddm qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia || fail "Couldn't install SDDM."
}
DM_OTHERS=(gdm lightdm)
