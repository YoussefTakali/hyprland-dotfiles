#!/usr/bin/env bash
# Select an area of the screen; the text in it goes to the clipboard (tesseract OCR).
if ! command -v tesseract >/dev/null; then
    notify-send -u critical "Text grab" "tesseract isn't installed.\nRun: sudo dnf install tesseract tesseract-langpack-eng"
    exit 1
fi
geo=$(slurp -d) || exit 0
text=$(grim -g "$geo" -t png - | tesseract - - -l "${OCR_LANG:-eng}" 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/^$/N;/^\n$/D')
if [[ -z "${text//[[:space:]]/}" ]]; then
    notify-send -a "Text grab" "No text found"; exit 0
fi
printf '%s' "$text" | wl-copy
notify-send -a "Text grab" "Text copied" "$(printf '%s' "$text" | head -c 200)"
