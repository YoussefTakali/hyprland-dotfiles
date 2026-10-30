#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Lock now. Weather and album art refresh in the background: they can take many seconds on a slow network,
# and a lock must never wait for the internet. The lock screen shows the last saved weather.

setsid -f bash -c '
    timeout 30 bash "$HOME/.config/hypr/UserScripts/WeatherWrap.sh"
    URL=$(playerctl metadata mpris:artUrl 2>/dev/null)
    CACHE="$HOME/.cache/hyprlock_albumart.png"           # used by the hyprlock fallback
    if [[ "$URL" == file://* ]]; then
        cp "${URL#file://}" "$CACHE"
    elif [[ -n "$URL" ]]; then
        curl -sL --max-time 10 "$URL" -o "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
    fi
' >/dev/null 2>&1 </dev/null

loginctl lock-session
