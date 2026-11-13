#!/usr/bin/env bash
# Apply Zen geometry after theme settings and let Waybar manage its own visibility.
set -euo pipefail
root="$HOME/.config/hypr"
out="$root/UserConfigs/Zen.conf"
tmp=$(mktemp "$out.XXXXXX")
if grep -qx '# Zen mode enabled' "$out"; then
    printf '# Zen mode disabled.\n' >"$tmp"
    label='Zen mode off'
else
    cat >"$tmp" <<'CONF'
# Zen mode enabled
general {
    gaps_in = 0
    gaps_out = 0
    border_size = 0
}
decoration {
    rounding = 0
}
CONF
    label='Zen mode on'
fi
mv "$tmp" "$out"
hyprctl reload >/dev/null
bash "$root/scripts/WaybarMode.sh" --refresh
notify-send -u low "$label"
