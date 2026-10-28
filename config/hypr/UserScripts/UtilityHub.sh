#!/usr/bin/env bash
# Utilities hub (Super+X): every desktop tool in one rofi grid.

S="$HOME/.config/hypr/scripts"
U="$HOME/.config/hypr/UserScripts"

pkill -x rofi && exit 0   # pressing the key again closes it

rec_label="Record screen"; rec_hint="Super+Alt+Print"
[[ -f "${XDG_RUNTIME_DIR:-/tmp}/screenrecord" ]] && pgrep -x wf-recorder >/dev/null && { rec_label="Stop recording"; rec_hint="recording now"; }

# icon | label | hint | command
items=(
    "󰹑|Screenshot|Super+Shift+S|$S/ScreenShot.sh --swappy"
    "󰑋|$rec_label|$rec_hint|$U/ScreenRecord.sh --toggle"
    "󰈊|Color picker|Super+Alt+X|$U/ColorPicker.sh"
    "󰅌|Clipboard|Super+Alt+V|$S/ClipManager.sh"
    "󰃬|Calculator|Super+Alt+C|$U/RofiCalc.sh"
    "󰞅|Emoji|Super+Alt+E|$S/RofiEmoji.sh"
    "󰖩|Wi-Fi|networks|$U/NetMenu.sh --wifi"
    "󰂯|Bluetooth|devices|$U/NetMenu.sh --bluetooth"
    "󰓅|Power profile|tuned|$U/PowerProfile.sh"
    "󰖨|Night light|Super+N|$S/Hyprsunset.sh toggle"
    "󰗊|Text grab (OCR)|Super+Alt+T|$U/OcrGrab.sh"
    "󰌾|Lock screen style|4 styles|$U/LockStyle.sh"
    "󰌌|Keybinds|Super+H|$S/KeyHints.sh"
)

# Icon color = rofi's wallust accent, so the menu follows the wallpaper theme
ACCENT=$(grep -m1 'selected-normal-background' "$HOME/.config/rofi/wallust/colors-rofi.rasi" | grep -o '#[0-9A-Fa-f]\{6\}')
ACCENT=${ACCENT:-#AF5CE5}

rows=""
for it in "${items[@]}"; do
    IFS='|' read -r icon label hint _ <<<"$it"
    rows+="<span size='22pt' foreground='$ACCENT'>$icon</span>"$'\n'"$label"$'\n'"<span size='8pt' alpha='55%'>$hint</span>|"
done

i=$(printf '%s' "${rows%|}" | rofi -dmenu -i -sep '|' -markup-rows -eh 4 -format i -no-custom \
    -mesg "↑↓←→ move · Enter run · type to filter · Super+Shift+E: more settings" \
    -theme "$HOME/.config/rofi/config-utilities.rasi") || exit 0
[[ -z "$i" ]] && exit 0

cmd=${items[$i]##*|}
sleep 0.15   # let rofi's window close first (screenshots, pickers)
exec bash -c "$cmd"
