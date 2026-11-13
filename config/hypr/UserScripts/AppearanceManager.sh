#!/usr/bin/env bash
set -euo pipefail
root="$HOME/.config/hypr"
rofi_config="$HOME/.config/rofi/config-Animations.rasi"
pick() {
    local label=$1
    shift
    rofi -i -dmenu -no-custom -config "$rofi_config" -p "$label" "$@"
}
active=$(cat "$root/UserConfigs/Ultimate/.current-theme" 2>/dev/null || true)
choice=$(printf '%s\n' 'Desktop theme' 'Waybar style' 'Waybar layout' 'Waybar preset' \
    'Animations' 'Rofi theme' 'Rofi corners' 'Desktop blur' 'Rendering profile' \
    'Wallpaper' 'Lock screen style' 'Login theme' 'Toggle Game mode' 'Toggle Zen mode' |
    pick Appearance -mesg "Desktop theme: ${active:-default}") || exit 0
case "$choice" in
    'Desktop theme') exec bash "$root/UserScripts/ThemeSwitch.sh" ;;
    'Waybar style') exec bash "$root/scripts/WaybarStyles.sh" ;;
    'Waybar layout') exec bash "$root/scripts/WaybarLayout.sh" ;;
    'Waybar preset')
        choice=$(printf '%s\n' 'Liquid Glass' 'Liquid Glass V2' 'Liquid Glass V3' | pick 'Apply matching Waybar style and layout') || exit 0
        case "$choice" in
            'Liquid Glass') preset=liquid ;;
            'Liquid Glass V2') preset=liquid-v2 ;;
            'Liquid Glass V3') preset=liquid-v3 ;;
            *) exit 0 ;;
        esac
        exec bash "$root/scripts/WaybarMode.sh" "$preset" ;;
    'Animations') exec bash "$root/scripts/Animations.sh" ;;
    'Rofi theme') exec bash "$root/scripts/RofiThemeSelector.sh" ;;
    'Rofi corners')
        choice=$(printf '%s\n' 'Follow desktop theme' 'Use Rofi theme corners' | pick 'Rofi corners') || exit 0
        case "$choice" in
            'Follow desktop theme') exec bash "$root/scripts/RofiShape.sh" follow ;;
            'Use Rofi theme corners') exec bash "$root/scripts/RofiShape.sh" custom ;;
        esac ;;
    'Desktop blur')
        choice=$(printf '%s\n' 'Follow desktop theme' 'Less blur' 'Off' | pick 'Desktop blur') || exit 0
        case "$choice" in
            'Follow desktop theme') exec bash "$root/scripts/ChangeBlur.sh" theme ;;
            'Less blur') exec bash "$root/scripts/ChangeBlur.sh" less ;;
            'Off') exec bash "$root/scripts/ChangeBlur.sh" off ;;
        esac ;;
    'Rendering profile')
        choice=$(printf '%s\n' 'default' 'balanced' 'fast' | pick 'Rendering profile') || exit 0
        [[ -n "$choice" ]] && exec bash "$root/UserScripts/PerformanceMode.sh" "$choice" ;;
    'Wallpaper') exec bash "$root/UserScripts/WallpaperSelect.sh" ;;
    'Lock screen style') exec bash "$root/UserScripts/LockStyle.sh" ;;
    'Login theme') exec python3 "$root/scripts/LoginThemes.py" ;;
    'Toggle Game mode') exec bash "$root/scripts/GameMode.sh" ;;
    'Toggle Zen mode') exec bash "$root/UserScripts/ZenMode.sh" ;;
esac
