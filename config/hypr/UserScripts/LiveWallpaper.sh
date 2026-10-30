#!/usr/bin/env bash
# Video ("live") wallpaper with mpvpaper.
#   LiveWallpaper.sh <video>    play it as the wallpaper and theme the desktop from one of its frames
#   LiveWallpaper.sh --restore  at login: bring back the last video wallpaper (does nothing if an image was chosen)
#   LiveWallpaper.sh --stop     stop the video wallpaper and forget it
# Colors (wallust), the lock screen and the terminal card use a still frame, since they need an image.
STATE="$HOME/.config/hypr/wallpaper_effects/.live_wallpaper"
FRAMES="$HOME/.cache/video-wallpaper"
SCRIPTS="$HOME/.config/hypr/scripts"

play() {
    pkill -x mpvpaper 2>/dev/null
    # Decode on the GPU that drives the screen (on a hybrid laptop the integrated one, so the discrete GPU can sleep)
    eval "$("$HOME/.config/hypr/scripts/GpuInfo.sh")"
    local g=${DISPLAY_GPU^^} hw="hwdec=auto-safe"
    local render_var="${g}_RENDER" va_var="${g}_VA"
    [[ -n "${!render_var:-}" ]] && hw="hwdec=vaapi vaapi-device=${!render_var}"
    # -p: pause while the wallpaper is fully covered (fullscreen apps) to save battery
    LIBVA_DRIVER_NAME=${!va_var:-$LIBVA_DRIVER_NAME} \
        setsid -f mpvpaper -p -o "no-audio loop-file=inf $hw panscan=1.0 load-scripts=no" '*' "$1" >/dev/null 2>&1 </dev/null
}

frame_of() {   # a frame ~10% into the video, cached per video
    local v=$1 out
    mkdir -p "$FRAMES"
    out="$FRAMES/$(printf '%s' "$v" | md5sum | cut -c1-12).png"
    if [[ ! -s "$out" ]]; then
        local dur
        dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$v" 2>/dev/null)
        ffmpeg -v error -y -ss "$(awk -v d="${dur:-10}" 'BEGIN{print d*0.1}')" -i "$v" -frames:v 1 "$out"
    fi
    echo "$out"
}

case "${1:-}" in
    --restore)
        [[ -f "$STATE" ]] || exit 0
        v=$(<"$STATE")
        if [[ -f "$v" ]] && command -v mpvpaper >/dev/null; then
            swww kill 2>/dev/null          # the image daemon would sit under/over the video
            play "$v"
        fi ;;
    --stop)
        pkill -x mpvpaper 2>/dev/null
        rm -f "$STATE" ;;
    "")
        echo "usage: $0 <video> | --restore | --stop"; exit 1 ;;
    *)
        v=$(realpath "$1")
        if ! command -v mpvpaper >/dev/null; then
            notify-send -u critical "Live wallpaper" "mpvpaper isn't installed.\nRun: sudo dnf copr enable sdegler/hyprland && sudo dnf install mpvpaper"
            exit 1
        fi
        play "$v"
        echo "$v" > "$STATE"
        f=$(frame_of "$v")
        if [[ -s "$f" ]]; then
            "$SCRIPTS/WallustSwww.sh" "$f"      # colors + lock-screen/terminal still image
            sleep 1
            "$SCRIPTS/Refresh.sh" >/dev/null 2>&1 &
        fi ;;
esac
