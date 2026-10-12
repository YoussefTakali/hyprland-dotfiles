#!/usr/bin/env bash
# Lock-screen power buttons. A button acts only on a second click within 3 s, so a stray click can't shut down.
# Usage: LockPower.sh click suspend|reboot|poweroff   |   LockPower.sh hint
ARM="${XDG_RUNTIME_DIR:-/tmp}/hyprlock-power-armed"   # "<action> <epoch>"

case "$1" in
    click)
        read -r armed t 2>/dev/null <"$ARM"
        if [[ "$armed" == "$2" ]] && (( $(date +%s) - t <= 3 )); then
            rm -f "$ARM"
            systemctl "$2"
        else
            echo "$2 $(date +%s)" >"$ARM"
        fi ;;
    hint)
        read -r armed t 2>/dev/null <"$ARM"
        if [[ -n "$armed" ]] && (( $(date +%s) - t <= 3 )); then
            case "$armed" in
                suspend)  echo "Click again to sleep" ;;
                reboot)   echo "Click again to restart" ;;
                poweroff) echo "Click again to shut down" ;;
            esac
        else
            echo " "
        fi ;;
esac
