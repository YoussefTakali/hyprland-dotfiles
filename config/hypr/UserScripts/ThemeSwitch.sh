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

pidof rofi >/dev/null && pkill rofi

current=$(cat "$state" 2>/dev/null)
choice="$1"
if [[ "$choice" == "--next" || "$choice" == "--prev" ]]; then
  mapfile -t all < <(find -L "$looks_dir" -maxdepth 1 -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort -V)
  i=0; for k in "${!all[@]}"; do [[ "${all[$k]}" == "$current" ]] && i=$k; done
  step=1; [[ "$choice" == "--prev" ]] && step=-1
  choice="${all[$(( (i + step + ${#all[@]}) % ${#all[@]} ))]}"
fi
if [[ -z "$choice" ]]; then
  choice=$(find -L "$looks_dir" -maxdepth 1 -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort -V |
    sed "s/^${current//\//\\/}\$/& ●/" |
    rofi -i -dmenu -config "$rofi_theme" -mesg "Theme: look + animations (colours follow your wallpaper)")
  choice="${choice% ●}"
fi
[[ -z "$choice" ]] && exit 0

look="$looks_dir/$choice.conf"
[[ -f "$look" ]] || { notify-send -u critical "Theme not found" "$choice"; exit 1; }

cp "$look" "$user_dir/Ultimate/Look.conf"

anim=$(sed -n 's/^# animation: *//p' "$look" | head -1)
if [[ -n "$anim" && -f "$anim_dir/$anim.conf" ]]; then
  cp "$anim_dir/$anim.conf" "$user_dir/UserAnimations.conf"
fi

# ── match waybar + rofi to the theme's shape ("# shape:" line in the look file) ──
shape=$(sed -n 's/^# shape: *//p' "$look" | head -1)
bar_radius=14; item_radius=10; bar_alpha=0.55; border=1; rofi_radius=16
for kv in $shape; do
  case "${kv%%=*}" in
    bar_radius|item_radius|bar_alpha|border|rofi_radius) printf -v "${kv%%=*}" '%s' "${kv#*=}" ;;
  esac
done
tpl="$HOME/.config/waybar/style/ultimate-glass.css.in"
if [[ -f "$tpl" ]]; then
  sed -e "s/__BAR_RADIUS__/$bar_radius/g" -e "s/__ITEM_RADIUS__/$item_radius/g" \
      -e "s/__BAR_ALPHA__/$bar_alpha/g" -e "s/__BORDER__/$border/g" \
      "$tpl" > "$HOME/.config/waybar/style/[Ultimate] Glass Adaptive.css"
fi
small=$(( rofi_radius * 2 / 3 ))
cat > "$HOME/.config/rofi/ultimate-shape.rasi" <<EOF
/* written by ThemeSwitch.sh - rounded corners matching the Hyprland theme */
window   { border-radius: ${rofi_radius}px; }
inputbar { border-radius: ${small}px; }
element  { border-radius: ${small}px; }
EOF

echo "$choice" > "$state"
hyprctl reload >/dev/null
pkill -SIGUSR2 -x waybar   # reload waybar style in place
notify-send -u low -i "$icon" "Theme: $choice" "Animations: ${anim:-unchanged}"
