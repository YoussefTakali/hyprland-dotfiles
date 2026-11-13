#!/usr/bin/env bash
# Required by video wallpapers: Fedora's ffmpeg-free omits HEVC decoding.
set -euo pipefail
as_root() {
    if [[ $EUID == 0 ]]; then
        "$@"
    elif sudo -n true 2>/dev/null; then
        sudo -n "$@"
    elif [[ -t 0 ]]; then
        sudo "$@"
    elif command -v pkexec >/dev/null && [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
        local executable
        executable=$(command -v "$1")
        shift
        pkexec "$executable" "$@"
    else
        echo 'Open Kitty and run this script there so sudo can ask for your password.' >&2
        return 1
    fi
}
has_hevc() {
    mpv --no-config --vd=help 2>/dev/null | awk '$1 == "hevc" {ok=1} END {exit !ok}'
}
if command -v mpv >/dev/null && has_hevc; then
    echo 'HEVC decoder already available.'
    exit 0
fi
if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    release=$(rpm -E %fedora)
    as_root dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm"
fi
as_root dnf install -y mpv /usr/bin/ffmpeg libavcodec-freeworld
has_hevc || { echo 'HEVC decoder still unavailable after package installation.' >&2; exit 1; }
echo 'HEVC multimedia codec support verified.'
