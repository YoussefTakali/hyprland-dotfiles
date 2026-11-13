#!/usr/bin/env bash
set -euo pipefail
config="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config.rasi"
mode=${1:-}
[[ "$mode" == follow || "$mode" == custom ]] || exit 1
tmp=$(mktemp "$config.XXXXXX")
sed '/^[[:space:]]*@import .*\/ultimate-shape\.rasi"/d' "$config" >"$tmp"
if [[ "$mode" == follow ]]; then
    printf '\n@import "~/.config/rofi/ultimate-shape.rasi"\n' >>"$tmp"
fi
chmod --reference="$config" "$tmp"
mv "$tmp" "$config"
