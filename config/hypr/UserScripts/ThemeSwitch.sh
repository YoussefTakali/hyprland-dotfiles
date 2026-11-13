#!/usr/bin/env bash
# Ultimate pack - theme switcher (HyDE / ML4W-style presets).
# A theme = a look file in ~/.config/hypr/looks (borders, corners, blur, shadows, gaps)
#         + the animation set named on its "# animation:" line (from ~/.config/hypr/animations).
# Colours still come from your wallpaper via wallust, so change wallpaper as usual to recolour.
#   ThemeSwitch.sh            -> rofi menu
#   ThemeSwitch.sh "<name>"   -> apply directly (name without .conf)

looks_dir="$HOME/.config/hypr/looks"
anim_dir="$HOME/.config/hypr/animations"
user_dir="$HOME/.config/hypr/UserConfigs"
state="$user_dir/Ultimate/.current-theme"
rofi_theme="$HOME/.config/rofi/config-Animations.rasi"
icon="$HOME/.config/swaync/images/ja.png"

current=$(cat "$state" 2>/dev/null)
choice="${1:-}"
if [[ "$choice" == "--next" || "$choice" == "--prev" ]]; then
  mapfile -t all < <(find -L "$looks_dir" -maxdepth 1 -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort -V)
  (( ${#all[@]} )) || exit 1
  i=0; for k in "${!all[@]}"; do [[ "${all[$k]}" == "$current" ]] && i=$k; done
  step=1; [[ "$choice" == "--prev" ]] && step=-1
  choice="${all[$(( (i + step + ${#all[@]}) % ${#all[@]} ))]}"
fi
if [[ -z "$choice" ]]; then
  choice=$(find -L "$looks_dir" -maxdepth 1 -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort -V |
    awk -v current="$current" '{ print $0 ($0 == current ? " ●" : "") }' |
    rofi -i -dmenu -no-custom -config "$rofi_theme" -mesg "Desktop look and preset defaults")
  choice="${choice% ●}"
fi
[[ -z "$choice" ]] && exit 0

look="$looks_dir/$choice.conf"
[[ -f "$look" ]] || { notify-send -u critical "Theme not found" "$choice"; exit 1; }

anim=$(sed -n 's/^# animation: *//p' "$look" | head -1)
[[ -n "$anim" && -f "$anim_dir/$anim.conf" ]] || {
  notify-send -u critical "Theme animations missing" "$anim"
  exit 1
}

# Keep the base animation config so switching looks is reversible.
look_tmp=$(mktemp "$user_dir/Ultimate/.Look.XXXXXX") || exit 1
if ! cat "$look" > "$look_tmp"; then
  rm -f "$look_tmp"
  exit 1
fi
mv -f "$look_tmp" "$user_dir/Ultimate/Look.conf" || exit 1
anim_tmp=$(mktemp "$user_dir/Ultimate/.Animations.XXXXXX") || exit 1
printf 'source = $HOME/.config/hypr/animations/%s.conf\n' "$anim" > "$anim_tmp"
mv -f "$anim_tmp" "$user_dir/Ultimate/Animations.conf" || exit 1

# ── match waybar + rofi to the theme's shape ("# shape:" line in the look file) ──
shape=$(sed -n 's/^# shape: *//p' "$look" | head -1)
bar_radius=14; item_radius=10; bar_alpha=0.55; border=1; rofi_radius=16
for kv in $shape; do
  case "${kv%%=*}" in
    bar_radius|item_radius|bar_alpha|border|rofi_radius) printf -v "${kv%%=*}" '%s' "${kv#*=}" ;;
  esac
done
bar_style="[Ultimate] Glass Adaptive"
style_dir="$HOME/.config/waybar/style"
style_tmp=$(mktemp "$style_dir/.ultimate-glass.XXXXXX") || exit 1
if ! sed -e "s/__BAR_RADIUS__/$bar_radius/g" -e "s/__ITEM_RADIUS__/$item_radius/g" \
    -e "s/__BAR_ALPHA__/$bar_alpha/g" -e "s/__BORDER__/$border/g" \
    "$style_dir/ultimate-glass.css.in" > "$style_tmp"; then
  rm -f "$style_tmp"
  notify-send -u critical "Could not generate the Waybar theme"
  exit 1
fi
if [[ $choice == '1 - Ultimate' ]]; then
  if ! { printf '\n'; cat "$style_dir/ultimate-reflection.css"; } >> "$style_tmp"; then
    rm -f "$style_tmp"
    notify-send -u critical "Could not add the Ultimate glass reflections"
    exit 1
  fi
fi
mv -f "$style_tmp" "$style_dir/$bar_style.css" || exit 1
small=$(( rofi_radius * 2 / 3 ))
cat > "$HOME/.config/rofi/ultimate-shape.rasi" <<EOF
/* written by ThemeSwitch.sh - rounded corners matching the Hyprland theme */
window   { border-radius: ${rofi_radius}px; }
inputbar { border-radius: ${small}px; }
element  { border-radius: ${small}px; }
EOF

echo "$choice" > "$state"
hyprctl reload >/dev/null
if [[ $(readlink -f "$HOME/.config/waybar/style.css") == "$style_dir/$bar_style.css" ]]; then
  bash "$HOME/.config/hypr/scripts/WaybarMode.sh" --refresh
fi
notify-send -u low -i "$icon" "Theme: $choice"
