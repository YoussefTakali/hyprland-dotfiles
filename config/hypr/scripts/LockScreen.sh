#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# For Hyprlock

# Ensure weather cache is up-to-date before locking
bash "$HOME/.config/hypr/UserScripts/WeatherWrap.sh" >/dev/null 2>&1

# Fetch current album art before locking so hyprlock shows fresh image
URL=$(playerctl metadata mpris:artUrl 2>/dev/null)
CACHE="$HOME/.cache/hyprlock_albumart.png"

if [[ -n "$URL" ]]; then
    if [[ "$URL" == file://* ]]; then
        cp "${URL#file://}" "$CACHE" 2>/dev/null
    else
        curl -sL "$URL" -o "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
    fi
fi

# Pick card / blank music background before hyprlock starts
"$HOME/.config/hypr/scripts/MusicCard.sh" >/dev/null 2>&1

loginctl lock-session
