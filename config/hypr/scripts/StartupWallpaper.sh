#!/usr/bin/env bash
# Paint a cached still immediately; start a saved video only after the desktop is visible.
set -u
ready_file=""
if [[ ${1:-} == --still-only && ${2:-} == --ready-file && -n ${3:-} ]]; then
    ready_file=$3
fi
signal_ready() { [[ -z $ready_file ]] || : > "$ready_file"; }
state="$HOME/.local/state/session-startup"
mkdir -p "$state"
exec >>"$state/wallpaper.log" 2>&1
printf '\nStartup wallpaper at uptime %s\n' "$(cut -d' ' -f1 /proc/uptime)"
# Avoid racing another invocation, and do not inherit this lock in the daemon.
exec 9>"${XDG_RUNTIME_DIR:-$state}/startup-wallpaper.lock"
flock -n 9 || exit 0
wall="$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"
selector="$HOME/.config/hypr/scripts/StartupWallpaperCache.py"
selection=()
if [[ -f $selector ]]; then
    mapfile -t selection < <(python3 "$selector" --startup)
    [[ -s ${selection[0]:-} ]] && wall=${selection[0]}
fi
painted=false
native_pid=""
refresh_cache=false
native="$HOME/.local/lib/hyprland-startup/wallpaper/hypr-start-wall"
if [[ -x $native && ${#selection[@]} == 5 && -s ${selection[4]} ]]; then
    native_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-$state}/startup-still.XXXXXX")
    HYPR_STARTUP_STATIC=$([[ -f $HOME/.config/quickshell/login-splash/transition.png ]] && echo 1 || echo 0) \
        "$native" "${selection[1]}" "${selection[2]}" "${selection[3]}" "${selection[4]}" "$native_dir/ready" 9>&- &
    native_pid=$!
    for ((i=0; i<25; i++)); do
        if [[ -f $native_dir/ready ]]; then
            painted=true
            printf 'Still submitted at uptime %s\n' "$(cut -d' ' -f1 /proc/uptime)"
            signal_ready
            break
        fi
        kill -0 "$native_pid" 2>/dev/null || break
        sleep 0.01
    done
    if [[ $painted != true ]]; then
        refresh_cache=true
        kill "$native_pid" 2>/dev/null || true
        wait "$native_pid" 2>/dev/null || true
        native_pid=""
    fi
    rm -rf "$native_dir"
fi
# swww 0.11 waits 500 ms before failing a query when its socket is absent.
# Do not probe a daemon that hasn't started: that delayed the first launch, then
# delayed the next readiness check again. A socket check is local and immediate.
source "$(dirname -- "${BASH_SOURCE[0]}")/WallpaperDaemonReady.sh"
if ! wallpaper_daemon_ready; then
    # The daemon's socket belongs to this Wayland display. A daemon on another
    # display must not prevent this session from starting its own wallpaper.
    swww-daemon --no-cache 9>&- &
fi
SECONDS=0
for ((i=0; i<50; i++)); do
    (( SECONDS < 3 )) || break
    if wallpaper_daemon_ready; then
        printf 'Daemon ready at uptime %s\n' "$(cut -d' ' -f1 /proc/uptime)"
        if [[ -s $wall ]]; then
            # The common loading scene covers the desktop before its real
            # wallpaper replaces the matching bridge image underneath it.
            if [[ -n ${JAKE_SPLASH_MAPPED:-} ]]; then
                for ((j=0; j<100; j++)); do
                    [[ -f $JAKE_SPLASH_MAPPED ]] && break
                    sleep 0.01
                done
            fi
            if timeout 2s swww img --transition-type none "$wall"; then
                if [[ $painted != true ]]; then
                    printf 'Still submitted at uptime %s\n' "$(cut -d' ' -f1 /proc/uptime)"
                else
                    printf 'Wallpaper daemon warmed at uptime %s\n' "$(cut -d' ' -f1 /proc/uptime)"
                fi
                painted=true
                signal_ready
                if [[ -n $native_pid ]]; then
                    # Request handoff, not destruction. The client waits for real
                    # presentation feedback (or a clearly labeled frame fallback).
                    kill -USR1 "$native_pid" 2>/dev/null || true
                    wait "$native_pid" 2>/dev/null || true
                fi
                [[ -z ${JAKE_DESKTOP_READY:-} ]] || : > "$JAKE_DESKTOP_READY"
            fi
        fi
        break
    fi
    sleep 0.05
done
if [[ $painted != true ]]; then
    printf 'WARNING: startup still was not submitted (daemon unavailable or image missing/failed).\n' >&2
fi
# Prepare the optional fast still for the next login, after the first image.
# A missing Pillow module, unsupported monitor layout or a changed wallpaper
# simply leaves the normal source-image path in use.
if [[ $painted == true && -f $selector ]] && { [[ ${selection[0]:-} == "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current" || $refresh_cache == true ]] || [[ -f $HOME/.cache/hypr-startup-wallpaper/provisional ]]; }; then
    python3 "$selector" </dev/null >/dev/null 2>&1 9>&- &
fi
if [[ ${HYPRLAND_DEFERRED_CURSOR_SYNC:-} == 1 ]]; then
    /usr/bin/hyprctl eval 'hl.config({cursor={sync_gsettings_theme=true}}); hl.env("HYPRLAND_DEFERRED_CURSOR_SYNC","0")' >/dev/null 2>&1 || true
fi
if [[ ${HYPRLAND_LOGIN_PROFILE:-} == 1 ]]; then
    # Keep the startup-only native trace before turning verbose logging off.
    trace="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/hyprland.log"
    [[ -f $trace ]] && cp "$trace" "$state/native-startup.log"
    /usr/bin/hyprctl eval 'hl.env("HYPRLAND_LOGIN_PROFILE","0"); hl.config({debug={disable_logs=true}})' >/dev/null 2>&1 || true
fi
if [[ ${1:-} != --still-only && -f $HOME/.config/hypr/wallpaper_effects/.live_wallpaper ]]; then
    bash "$HOME/.config/hypr/UserScripts/LiveWallpaper.sh" --restore 9>&-
fi
