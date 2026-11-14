#!/usr/bin/env bash
# Install this Hyprland desktop on Arch, Fedora or Ubuntu (26.04+) — terminal version.
#
# Recommended: the graphical installer —  ./setup
# This script runs the same installer backend (installer/backend.sh) in the terminal:
#
#   ./install.sh                 everything: Hyprland base, drivers, apps, these configs
#   ./install.sh --no-base       skip the Hyprland base packages (Hyprland already set up; configs + apps)
#   ./install.sh --base          explicitly install the Hyprland base packages
#   ./install.sh --no-drivers    don't touch graphics drivers
#   ./install.sh --sddm          also switch the login screen to SDDM with the Hypr Login Styles theme
#   ./install.sh --bar=ultimate|adaptive|glass|liquid|liquid-v2|liquid-v3   bar style (default: ultimate)
#   ./install.sh --lock=Slate|Iris|Fog|Cards       lock screen style (default: Slate)
#   ./install.sh --kb=<layout>   keyboard layout (default: this PC's)
#   ./install.sh --jack-fix      keep the 3.5mm jack output on when the PC's jack detection is broken
#
# Everything this replaces is copied to ~/.config-backup-<date>/ first. Safe to re-run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

export OPT_SKIP_BASE=0 OPT_DRIVERS=1 OPT_LOGIN=keep OPT_BAR=ultimate OPT_LOCK=Slate OPT_KB="" OPT_JACK_FIX=0
if command -v Hyprland >/dev/null; then OPT_SKIP_BASE=1; fi
for a in "$@"; do
    case "$a" in
        --base)       OPT_SKIP_BASE=0 ;;
        --no-base)    OPT_SKIP_BASE=1 ;;
        --no-drivers) OPT_DRIVERS=0 ;;
        --sddm)       OPT_LOGIN=sddm ;;
        --jack-fix)   OPT_JACK_FIX=1 ;;
        --bar=*)      OPT_BAR=${a#*=} ;;
        --lock=*)     OPT_LOCK=${a#*=} ;;
        --kb=*)       OPT_KB=${a#*=} ;;
        -h|--help)    sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown option: $a (see --help)"; exit 1 ;;
    esac
done

[[ $EUID -ne 0 ]] || { echo "Run as your normal user, not root (sudo is used where needed)."; exit 1; }
echo "Administrator password (used for installing packages):"
sudo -v || exit 1
(while sleep 45; do sudo -n -v || exit; done) >/dev/null 2>&1 </dev/null &
keeper=$!
trap 'kill "$keeper" 2>/dev/null || true' EXIT

# Keep progress records available to callers that capture stdout.
if [[ ! -t 1 ]]; then
    bash "$HERE/installer/backend.sh"
    exit
fi

# Pretty-print the backend's progress lines; everything else is shown as-is (and is in the log file)
bash "$HERE/installer/backend.sh" | while IFS= read -r line; do
    case "$line" in
        "@@STEP "*)     set -- $line; shift; n=$1 t=$2; shift 2
                        printf '\n\033[1;35m==> [%s/%s] %s\033[0m\n' "$n" "$t" "$*" ;;
        "@@PROGRESS "*) ;;
        "@@WARN "*)     printf '\033[1;33m!  %s\033[0m\n' "${line#@@WARN }" ;;
        "@@NOTE BACKUP "*) echo "Previous configs: ${line#@@NOTE BACKUP }" ;;
        "@@NOTE LOG "*)    echo "Full log: ${line#@@NOTE LOG }" ;;
        "@@NOTE NVIDIA_INSTALLED") echo "NVIDIA driver installed: it loads after a reboot." ;;
        "@@NOTE NO_LOGIN_SCREEN")  echo "No login screen found: log in on the console and type Hyprland (or re-run with --sddm)." ;;
        "@@NOTE "*)     ;;
        "@@FAIL "*)     printf '\n\033[1;31m✗ Install stopped: %s\033[0m\nIt is safe to fix the problem and run ./install.sh again.\n' "${line#@@FAIL }"; exit 1 ;;
        "@@DONE")       printf '\n\033[1;32m✓ Done.\033[0m Reboot (or log out and pick Hyprland) to start the desktop.\n'
                        echo "  Lock: Super+L   Utilities: Super+X   Cheat sheet: Super+H   Themes: Super+Ctrl+T / Super+Shift+T" ;;
        *)              printf '%s\n' "$line" ;;
    esac
done
exit "${PIPESTATUS[0]}"
