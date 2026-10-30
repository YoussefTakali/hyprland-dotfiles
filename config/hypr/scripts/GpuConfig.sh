#!/usr/bin/env bash
# Write ~/.config/hypr/UserConfigs/GPU.conf for this PC's graphics (sourced last from UserConfigs/ENVariables.conf,
# so it overrides the defaults). Run by the installer, and again any time (e.g. after changing hardware).
#   hybrid laptop : the integrated GPU renders the desktop, apps and video; the NVIDIA/AMD GPU sleeps until an
#                   app is started with `gpu-run` (or an external monitor wired to it is plugged in)
#   NVIDIA only   : everything on NVIDIA (VA-API through nvidia-vaapi-driver)
#   AMD / Intel   : the matching VA-API driver
OUT="$HOME/.config/hypr/UserConfigs/GPU.conf"
eval "$("$HOME/.config/hypr/scripts/GpuInfo.sh")"

{
echo "# Written by scripts/GpuConfig.sh for this PC ($MODE: ${GPUS}). Re-run it after changing hardware."
case "$MODE" in
    hybrid-nvidia|hybrid-amd)
        iva_var="${IGPU^^}_VA"
        echo "# Hybrid: ${IGPU} renders the desktop and decodes video; ${DGPU} sleeps until something runs on it"
        echo "# (start an app on ${DGPU} with: gpu-run <app>, or the launcher's \"Run on ${DGPU^^}\")."
        echo "env = LIBVA_DRIVER_NAME,${!iva_var}"
        echo "env = __GLX_VENDOR_LIBRARY_NAME,mesa"
        echo "env = __EGL_VENDOR_LIBRARY_FILENAMES,/usr/share/glvnd/egl_vendor.d/50_mesa.json"
        ;;
    nvidia)
        echo "env = LIBVA_DRIVER_NAME,nvidia"
        echo "env = __GLX_VENDOR_LIBRARY_NAME,nvidia"
        echo "env = NVD_BACKEND,direct"
        ;;
    amd)   echo "env = LIBVA_DRIVER_NAME,radeonsi" ;;
    intel) echo "env = LIBVA_DRIVER_NAME,${INTEL_VA}" ;;
    *)     echo "# no known GPU found: Hyprland's defaults apply" ;;
esac
} > "$OUT"

ENV="$HOME/.config/hypr/UserConfigs/ENVariables.conf"
grep -q 'UserConfigs/GPU.conf' "$ENV" 2>/dev/null || \
    printf '\n# This PC'"'"'s graphics settings (written by scripts/GpuConfig.sh) — keep this last\nsource = $HOME/.config/hypr/UserConfigs/GPU.conf\n' >> "$ENV"
echo "Wrote $OUT ($MODE)"
