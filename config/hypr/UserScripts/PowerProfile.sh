#!/usr/bin/env bash
# Choose the power profile (tuned-ppd / power-profiles-daemon D-Bus API).
BUS=(net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile)
cur=$(busctl --system get-property "${BUS[@]}" | awk '{print $2}' | tr -d '"')
mark() { [[ $1 == "$cur" ]] && echo "  (current)"; }
choice=$(printf '%s\n' "󰾆  power-saver$(mark power-saver)" "󰾅  balanced$(mark balanced)" "󰓅  performance$(mark performance)" \
    | rofi -dmenu -i -p "Power" -theme "$HOME/.config/rofi/config-utilities-list.rasi") || exit 0
p=$(awk '{print $2}' <<<"$choice")
[[ -z "$p" || $p == "$cur" ]] && exit 0
busctl --system set-property "${BUS[@]}" s "$p" && notify-send -a "Power" "Power profile: $p"
