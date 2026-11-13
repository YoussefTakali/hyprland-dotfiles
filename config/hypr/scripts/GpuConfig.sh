#!/usr/bin/env bash
# Write managed defaults only. Hybrid systems retain vendor auto-detection.
set -euo pipefail
OUT="$HOME/.config/hypr/UserConfigs/GPU.conf"
mkdir -p "${OUT%/*}"
eval "$(bash "$HOME/.config/hypr/scripts/GpuInfo.sh")"
if [[ -s $OUT ]] && ! head -n1 "$OUT" | grep -qE '^# (Written by scripts/GpuConfig.sh|Managed by scripts/GpuConfig.sh)'; then
    echo "Preserving custom $OUT; hardware still detected at login."
    exit 0
fi
tmp=$(mktemp "${OUT}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{
    echo '# Managed by scripts/GpuConfig.sh. Runtime card selection is portable.'
    echo '# Mixed vendors use GLVND/libva auto-detection; no machine PCI addresses.'
    if [[ $GPUS == nvidia && -n $NVIDIA_DRIVER ]]; then
        echo 'env = LIBVA_DRIVER_NAME,nvidia'
        echo 'env = __GLX_VENDOR_LIBRARY_NAME,nvidia'
        echo 'env = NVD_BACKEND,direct'
    fi
} > "$tmp"
mv "$tmp" "$OUT"
ENV="$HOME/.config/hypr/UserConfigs/ENVariables.conf"
grep -q 'source.*UserConfigs/GPU.conf' "$ENV" 2>/dev/null || \
    printf '\n# Per-account GPU settings (hybrid vendors use auto-detection).\nsource = $HOME/.config/hypr/UserConfigs/GPU.conf\n' >> "$ENV"
echo "GPU defaults: $MODE ($GPUS); display: ${DISPLAY_GPU:-automatic}"
