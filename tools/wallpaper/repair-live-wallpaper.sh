#!/usr/bin/env bash
# Run as your regular user from a desktop terminal.
# Install the missing HEVC decoder, verify playback, then apply the requested video.
set -euo pipefail
[[ $EUID != 0 ]] || { echo 'Run as your regular user; sudo is used only for packages.' >&2; exit 1; }
video=${1:?Usage: repair-live-wallpaper.sh VIDEO}
[[ -f $video ]] || { echo "Video not found: $video" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")/../.." && pwd)
bash "$HERE/installer/install-codecs.sh"
echo 'Checking one decoded frame before changing the wallpaper...'
mpv --no-config --vo=null --ao=null --frames=1 --hwdec=no "$video"
exec bash "$HOME/.config/hypr/UserScripts/LiveWallpaper.sh" "$video"
