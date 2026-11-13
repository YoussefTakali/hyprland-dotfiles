#!/usr/bin/env bash
# Temporarily simplify desktop rendering while keeping the selected appearance settings.
set -euo pipefail
out="$HOME/.config/hypr/UserConfigs/GameMode.conf"
tmp=$(mktemp "$out.XXXXXX")
if grep -qx '# Game mode enabled' "$out"; then
    printf '# Game mode disabled.\n' >"$tmp"
    label='Game mode off'
else
    cat >"$tmp" <<'CONF'
# Game mode enabled
animations {
    enabled = false
}
general {
    gaps_in = 0
    gaps_out = 0
    border_size = 1
}
decoration {
    rounding = 0
    blur {
        enabled = false
    }
    shadow {
        enabled = false
    }
}
windowrule = match:class .*, opaque on
CONF
    label='Game mode on'
fi
mv "$tmp" "$out"
hyprctl reload >/dev/null
notify-send -u low "$label"
