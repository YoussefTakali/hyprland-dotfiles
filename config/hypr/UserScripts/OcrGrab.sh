#!/usr/bin/env bash
# Select an area of the screen; the text in it goes to the clipboard (tesseract OCR).
pkg_hint() {  # pkg_hint <arch pkgs> <fedora pkgs> <ubuntu pkgs>  -> the install command for this distro
    if command -v pacman >/dev/null; then echo "sudo pacman -S $1"
    elif command -v apt-get >/dev/null; then echo "sudo apt install $3"
    else echo "sudo dnf install $2"; fi
}
if ! command -v tesseract >/dev/null; then
    notify-send -u critical "Text grab" "tesseract isn't installed.\nRun: $(pkg_hint 'tesseract tesseract-data-eng' 'tesseract tesseract-langpack-eng' 'tesseract-ocr tesseract-ocr-eng')"
    exit 1
fi
geo=$(slurp -d) || exit 0
text=$(grim -g "$geo" -t png - | tesseract - - -l "${OCR_LANG:-eng}" 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/^$/N;/^\n$/D')
if [[ -z "${text//[[:space:]]/}" ]]; then
    notify-send -a "Text grab" "No text found"; exit 0
fi
printf '%s' "$text" | wl-copy
notify-send -a "Text grab" "Text copied" "$(printf '%s' "$text" | head -c 200)"
