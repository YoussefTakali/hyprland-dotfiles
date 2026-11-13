#!/usr/bin/env bash
# Probe the current Wayland display only after its wallpaper socket exists.
wallpaper_daemon_ready() {
    local runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    local display=${WAYLAND_DISPLAY:-wayland-0}
    if [[ -S "$runtime/$display-swww-daemon..sock" || -S "$runtime/$display-awww-daemon..socket" ||
          -S "$runtime/awww-$display.socket" ]]; then
        timeout 0.3s swww query >/dev/null 2>&1
    else
        return 1
    fi
}
