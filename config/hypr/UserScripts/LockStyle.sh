#!/usr/bin/env bash
# Pick the lock-screen style (Quickshell, ~/.config/quickshell/lockscreen/Lock<Style>.qml).
#   LockStyle.sh            menu: choose a style, then see it in a 6-second preview
#   LockStyle.sh <Style>    set it directly (Slate, Iris, Fog, Cards)
#   LockStyle.sh --preview  preview the current style
DIR="$HOME/.config/quickshell/lockscreen"
STYLE_FILE="$DIR/style"
current=$(cat "$STYLE_FILE" 2>/dev/null || echo Slate)

preview() { QS_LOCK_PREVIEW=6 setsid -f qs -p "$DIR/shell.qml" >/dev/null 2>&1 </dev/null; }

set_style() {
    [[ -f "$DIR/Lock$1.qml" ]] || { notify-send -u critical "Lock screen" "No style called \"$1\""; exit 1; }
    echo "$1" > "$STYLE_FILE"
    notify-send -a "Lock screen" -t 2500 "Lock screen style: $1" "Previewing it for 6 seconds"
    sleep 0.3; preview
}

case "${1:-}" in
    --preview) preview; exit 0 ;;
    "") ;;
    *) set_style "$1"; exit 0 ;;
esac

ACCENT=$(grep -m1 'selected-normal-background' "$HOME/.config/rofi/wallust/colors-rofi.rasi" | grep -o '#[0-9A-Fa-f]\{6\}')
ACCENT=${ACCENT:-#AF5CE5}
rows=(
    "Slate|Glass pane on the left, wallpaper drifting"
    "Iris|Clear lens between hours and minutes"
    "Fog|Misted glass with the time wiped clean"
    "Cards|The first design: centred clock"
)
menu=""
for r in "${rows[@]}"; do
    name=${r%%|*}; desc=${r#*|}
    mark=""; [[ $name == "$current" ]] && mark="  <span foreground='$ACCENT'>● current</span>"
    menu+="<b>$name</b>$mark"$'\n'"<span size='9pt' alpha='60%'>$desc</span>|"
done
i=$(printf '%s' "${menu%|}" | rofi -dmenu -i -sep '|' -markup-rows -eh 2 -format i -no-custom -p "Lock style" \
    -mesg "Choose a lock screen style (Enter previews it for 6 seconds)" \
    -theme "$HOME/.config/rofi/config-utilities-list.rasi") || exit 0
[[ -n "$i" ]] && set_style "$(cut -d'|' -f1 <<<"${rows[$i]}")"
