#!/usr/bin/env bash
# Video ("live") wallpaper with mpvpaper.
#   LiveWallpaper.sh <video>    play it as the wallpaper and theme the desktop from one of its frames
#   LiveWallpaper.sh --restore  at login: bring back the last video wallpaper (does nothing if an image was chosen)
#   LiveWallpaper.sh --stop     stop the video wallpaper and forget it
# Colors (wallust), the lock screen and the terminal card use a still frame, since they need an image.
STATE="$HOME/.config/hypr/wallpaper_effects/.live_wallpaper"
FRAMES="$HOME/.cache/video-wallpaper"
SCRIPTS="$HOME/.config/hypr/scripts"
LOGDIR="$HOME/.local/state/live-wallpaper"

fail() {
    echo "Live wallpaper: $*" >&2
    notify-send -u critical 'Live wallpaper' "$*" 2>/dev/null || true
    return 1
}

check_video() {
    [[ -f $1 ]] || { fail "Video not found: $1"; return 1; }
    command -v mpvpaper >/dev/null || { fail 'mpvpaper is not installed.'; return 1; }
    local codec decoders
    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$1") || return 1
    [[ -n $codec ]] || { fail 'No video stream found.'; return 1; }
    decoders=$(mpv --no-config --vd=help 2>/dev/null)
    if ! awk -v c="$codec" '$1 == c || index($1,c "_") == 1 || $2 == "(" c ")" {found=1} END {exit !found}' <<<"$decoders"; then
        fail "Missing decoder for $codec. Choose a video with a supported codec or rerun Desktop Setup to check multimedia support."
        return 1
    fi
}

play() {
    # Fail before stopping a working wallpaper or saving a broken selection.
    check_video "$1" || return 1
    local previous_players
    previous_players=$(pgrep -u "$(id -u)" -x mpvpaper || true)
    # Use native NVDEC on NVIDIA; VA-API on AMD/Intel.
    eval "$("$HOME/.config/hypr/scripts/GpuInfo.sh")"
    local g=${DISPLAY_GPU^^} hw="hwdec=auto"
    local render_var="${g}_RENDER" va_var="${g}_VA"
    if [[ $DISPLAY_GPU == nvidia ]]; then
        hw="hwdec=nvdec"
    elif [[ -n "${!render_var:-}" ]]; then
        hw="hwdec=vaapi vaapi-device=${!render_var}"
    fi
    mkdir -p "$LOGDIR"
    # -p: pause while the wallpaper is fully covered (fullscreen apps) to save battery
    local -a video_env=()
    [[ -z ${!va_var:-} ]] || video_env+=("LIBVA_DRIVER_NAME=${!va_var}")
    env "${video_env[@]}" setsid mpvpaper -p -o "no-audio loop-file=inf $hw panscan=1.0 load-scripts=no terminal=no" '*' "$1" >"$LOGDIR/mpvpaper.log" 2>&1 </dev/null &
    local player=$!
    sleep 1
    if ! kill -0 "$player" 2>/dev/null; then
        wait "$player" 2>/dev/null || true
        fail "Player failed to start. Read $LOGDIR/mpvpaper.log"
        tail -n 12 "$LOGDIR/mpvpaper.log" >&2
        return 1
    fi
    # Keep the previous wallpaper until the replacement survives startup.
    local previous
    while read -r previous; do
        [[ -z $previous ]] || kill "$previous" 2>/dev/null || true
    done <<< "$previous_players"
    swww kill 2>/dev/null || true
    pkill -x swaybg 2>/dev/null || true
    pkill -x hyprpaper 2>/dev/null || true
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
            play "$v" || exit 1
        fi ;;
    --stop)
        pkill -x mpvpaper 2>/dev/null
        rm -f "$STATE" ;;
    "")
        echo "usage: $0 <video> | --restore | --stop"; exit 1 ;;
    *)
        v=$(realpath "$1")
        if ! command -v mpvpaper >/dev/null; then
            notify-send -u critical "Live wallpaper" "mpvpaper isn't installed.\n$(command -v pacman >/dev/null && echo 'Run: yay -S mpvpaper' || { command -v apt-get >/dev/null && echo 'Run the desktop installer again (it builds mpvpaper)' || echo 'Run: sudo dnf copr enable sdegler/hyprland && sudo dnf install mpvpaper'; })"
            exit 1
        fi
        play "$v" || exit 1
        mkdir -p "${STATE%/*}"
        echo "$v" > "$STATE"
        f=$(frame_of "$v")
        if [[ -s "$f" ]]; then
            "$SCRIPTS/WallustSwww.sh" "$f"      # colors + lock-screen/terminal still image
            sleep 1
            "$SCRIPTS/Refresh.sh" >/dev/null 2>&1 &
        fi ;;
esac
