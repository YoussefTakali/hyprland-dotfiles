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
    python3 "$HERE/installer/gpu-setup.py" --install || fail "Graphics setup failed; see the specific error above."
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
    run sudo dnf install -y --allowerasing sddm-x11 xorg-x11-server-Xorg qt6-qtdeclarative qt6-qtsvg qt6-qtvirtualkeyboard qt6-qtmultimedia || fail "Couldn't install SDDM."
}
DM_OTHERS=(gdm lightdm)
