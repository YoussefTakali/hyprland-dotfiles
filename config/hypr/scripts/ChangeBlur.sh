#!/usr/bin/env bash
# Set the compositor blur override independently of the bar style or desktop look.
set -euo pipefail
out="$HOME/.config/hypr/UserConfigs/BlurOverride.conf"
mode=${1:-toggle}
if [[ "$mode" == toggle ]]; then
    if grep -qx '# Less blur' "$out"; then mode=theme; else mode=less; fi
fi
case "$mode" in
    theme) text='# Use desktop theme blur.'; label='Follow desktop theme' ;;
    less)  text='# Less blur
decoration {
    blur {
        size = 2
        passes = 1
    }
}'; label='Less blur' ;;
    off)   text='# Blur disabled
decoration {
    blur {
        enabled = false
    }
}'; label='Blur off' ;;
    *) exit 1 ;;
esac
tmp=$(mktemp "$out.XXXXXX")
printf '%s\n' "$text" >"$tmp"
mv "$tmp" "$out"
hyprctl reload >/dev/null
notify-send -u low 'Desktop blur' "$label"
