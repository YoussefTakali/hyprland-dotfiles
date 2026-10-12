#!/usr/bin/env bash
# Screen recorder (wf-recorder). Usage: ScreenRecord.sh --toggle|--full|--area|--full-audio|--area-audio|--stop|--status
# --toggle stops a running recording, otherwise opens a small rofi menu to pick a mode.
# --status prints Waybar JSON (empty text = module hidden).

DIR="$HOME/Videos/Recordings"
STATE="${XDG_RUNTIME_DIR:-/tmp}/screenrecord"   # holds "<pid> <start epoch> <file>"

running() {
    [[ -f "$STATE" ]] || return 1
    read -r pid _ _ <"$STATE"
    [[ -n "$pid" && -d /proc/$pid ]] && return 0
    rm -f "$STATE"; return 1
}

refresh_bar() { pkill -RTMIN+8 waybar 2>/dev/null; }

stop() {
    running || return 0
    read -r pid _ file <"$STATE"
    kill -INT "$pid"
    for _ in {1..50}; do [[ -d /proc/$pid ]] || break; sleep 0.1; done
    rm -f "$STATE"; refresh_bar
    action=$(notify-send -a "Screen recorder" -i video-x-generic "Recording saved" "${file/#$HOME/\~}" \
        -A open=Open -A folder="Show in folder")
    case "$action" in
        open)   xdg-open "$file" ;;
        folder) xdg-open "$DIR" ;;
    esac
}

start() {   # $1 = full|area, $2 = audio|""
    running && { stop; return; }
    if ! command -v wf-recorder >/dev/null; then
        notify-send -u critical "Screen recorder" "wf-recorder isn't installed.\nRun: sudo dnf install wf-recorder"
        exit 1
    fi
    mkdir -p "$DIR"
    local file="$DIR/rec_$(date +%Y-%m-%d_%H-%M-%S).mp4" args=(-f "$file")
    if [[ $1 == area ]]; then
        geo=$(slurp -d) || exit 0
        args+=(-g "$geo")
    else
        args+=(-o "$(hyprctl activeworkspace -j | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["monitor"])')")
    fi
    # Desktop audio (what you hear), not the mic
    [[ $2 == audio ]] && args+=(--audio="$(pactl get-default-sink).monitor")
    setsid -f wf-recorder "${args[@]}" >/dev/null 2>&1 </dev/null
    sleep 0.3
    pid=$(pgrep -nx wf-recorder) || { notify-send -u critical "Screen recorder" "Failed to start"; exit 1; }
    echo "$pid $(date +%s) $file" >"$STATE"
    refresh_bar
    notify-send -a "Screen recorder" -t 2000 "Recording started" "Stop: Super+Alt+Print, or click REC in the bar"
}

status() {
    if running; then
        read -r _ t0 file <"$STATE"
        s=$(( $(date +%s) - t0 ))
        printf '{"text":"● REC %02d:%02d","tooltip":"Recording to %s\\nClick to stop","class":"recording"}\n' \
            $((s/60)) $((s%60)) "${file/#$HOME/\~}"
    else
        echo '{"text":"","class":"idle"}'
    fi
}

menu() {
    choice=$(printf '%s\n' "󰹑  Full screen" "󰆞  Select area" "󰕾  Full screen + desktop audio" "󰕾  Area + desktop audio" \
        | rofi -dmenu -i -p "Record" -theme "$HOME/.config/rofi/config-utilities-list.rasi")
    case "$choice" in
        *"Full screen + "*) start full audio ;;
        *"Area + "*)        start area audio ;;
        *"Full screen"*)    start full ;;
        *"Select area"*)    start area ;;
    esac
}

case "$1" in
    --full)       start full ;;
    --area)       start area ;;
    --full-audio) start full audio ;;
    --area-audio) start area audio ;;
    --stop)       stop ;;
    --status)     status ;;
    --toggle|"")  running && stop || menu ;;
esac
