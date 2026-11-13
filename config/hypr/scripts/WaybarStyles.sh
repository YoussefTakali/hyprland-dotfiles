#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Script for waybar styles

IFS=$'\n\t'

# Define directories
waybar_styles="$HOME/.config/waybar/style"
waybar_style="$HOME/.config/waybar/style.css"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
rofi_config="$HOME/.config/rofi/config-waybar-style.rasi"
msg='Choose how the bar looks'

# Apply selected style
apply_style() {
    bash "${SCRIPTSDIR}/WaybarMode.sh" --style "$1"
}

main() {
    # resolve current symlink and strip .css
    current_target=$(readlink -f "$waybar_style")
    current_name=$(basename "$current_target" .css)
    [[ "$current_name" != "[Ultimate] Glass Adaptive" ]] || current_name="Follow desktop theme"

    # gather all style names (without .css) into an array
    mapfile -t options < <(
        printf '%s\n' 'Follow desktop theme'
        find -L "$waybar_styles" -maxdepth 1 -type f -name '*.css' ! -name '[[]Ultimate] Glass Adaptive.css' ! -name 'ultimate-reflection.css' \
            -exec basename {} .css \; \
            | sort
    )

    # mark the active style and record its index
    default_row=0
    MARKER="👉"
    for i in "${!options[@]}"; do
        if [[ "${options[i]}" == "$current_name" ]]; then
            options[i]="$MARKER ${options[i]}"
            default_row=$i
            break
        fi
    done

    # launch rofi with the annotated list and pre‑selected row
    choice=$(printf '%s\n' "${options[@]}" \
        | rofi -i -dmenu -no-custom \
               -config "$rofi_config" \
               -mesg "$msg" \
               -selected-row "$default_row"
    )

    [[ -z "$choice" ]] && { echo "No option selected. Exiting."; exit 0; }

    # remove annotation and apply
    choice=${choice#"$MARKER "}
    [[ "$choice" != "Follow desktop theme" ]] || choice="[Ultimate] Glass Adaptive"
    apply_style "$choice"
}

main
