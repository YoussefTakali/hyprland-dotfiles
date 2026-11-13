#!/usr/bin/env bash
# Set one Waybar preference, apply an explicit layout/style preset, or manage visibility.
set -euo pipefail
root="$HOME/.config/waybar"
user_config="$HOME/.config/hypr/UserConfigs"
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
hidden="$runtime/hypr-waybar-hidden"
uid=$(id -u)

refresh_bar() {
    if [[ -f "$hidden" ]] || grep -qx '# Zen mode enabled' "$user_config/Zen.conf" 2>/dev/null; then
        pkill -u "$uid" -x waybar 2>/dev/null || true
    elif pgrep -u "$uid" -x waybar >/dev/null; then
        pkill -SIGUSR2 -u "$uid" -x waybar
    else
        mkdir -p "$HOME/.local/state/waybar"
        nohup waybar >>"$HOME/.local/state/waybar/waybar.log" 2>&1 </dev/null 9>&- &
    fi
}

exec 9>"$runtime/hypr-waybar-mode.lock"
flock 9
layout="" style=""
case ${1:-} in
    liquid)    layout='[TOP] Liquid Glass'; style='[Glass] Liquid Glass' ;;
    liquid-v2) layout='[TOP] Liquid Glass V2'; style='[Glass] Liquid Glass V2' ;;
    liquid-v3) layout='[TOP] Liquid Glass V3'; style='[Glass] Liquid Glass V3' ;;
    --style)  style=${2:?Missing Waybar style} ;;
    --layout) layout=${2:?Missing Waybar layout} ;;
    --refresh) refresh_bar; exit ;;
    --hide) touch "$hidden"; refresh_bar; exit ;;
    --toggle)
        if [[ -f "$hidden" ]]; then
            rm "$hidden"
        else
            touch "$hidden"
        fi
        refresh_bar
        exit ;;
    *) echo 'Usage: WaybarMode.sh liquid|liquid-v2|liquid-v3 | --style NAME | --layout NAME | --refresh | --toggle | --hide' >&2; exit 1 ;;
esac

[[ -z "$layout" || -f "$root/configs/$layout" ]] || exit 1
[[ -z "$style" || -f "$root/style/$style.css" ]] || exit 1
if [[ -n "$layout" ]]; then
    ln -sfn "$root/configs/$layout" "$root/config"
fi
if [[ -n "$style" ]]; then
    ln -sfn "$root/style/$style.css" "$root/style.css"
    glass="$user_config/WaybarGlass.conf"
    tmp=$(mktemp "$glass.XXXXXX")
    case "$style" in
        '[Glass] Liquid Glass'|'[Glass] Liquid Glass V2'|'[Glass] Liquid Glass V3')
            cat >"$tmp" <<'CONF'
# Waybar-only blur parameters. The desktop look and performance profile control compositor blur.
layerrule = match:namespace waybar, blur on
layerrule = match:namespace waybar, ignore_alpha 0.02
CONF
            ;;
        *) printf '# Default Waybar layer settings apply.\n' >"$tmp" ;;
    esac
    mv "$tmp" "$glass"
    if [[ ${WAYBAR_SKIP_RELOAD:-0} != 1 ]]; then
        hyprctl reload >/dev/null
    fi
fi
if [[ ${WAYBAR_SKIP_RELOAD:-0} != 1 ]]; then
    refresh_bar
fi
