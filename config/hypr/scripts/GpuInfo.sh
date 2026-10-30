#!/usr/bin/env bash
# GPU facts for this PC, as KEY=VALUE lines (source it, or read it): used by GpuConfig.sh, gpu-doctor,
# LiveWallpaper.sh and the installer.
#
#   MODE           nvidia | amd | intel | hybrid-nvidia | hybrid-amd | unknown
#   GPUS           vendors found, e.g. "intel nvidia"
#   IGPU / DGPU    vendor of the integrated / discrete GPU (hybrid only)
#   DISPLAY_GPU    vendor of the GPU the built-in / first screen is wired to (boot_vga)
#   *_PCI          PCI address, *_RENDER render node, *_VA its VA-API driver name (iHD, i965, radeonsi, nvidia)
#   NVIDIA_DRIVER  loaded NVIDIA driver version ("" if none), NVIDIA_OPEN=1 for the open kernel modules
#   NVIDIA_ARCH    turing+ (open modules supported) | legacy (Maxwell/Pascal/Volta: proprietary 580 branch)
#   SECURE_BOOT    1 / 0 / ? (signed modules needed when 1)
set -u

declare -A VENDOR=( [0x10de]=nvidia [0x1002]=amd [0x8086]=intel )
gpus=() ; declare -A pci render boot
for card in /sys/class/drm/card[0-9]*; do
    [[ "$card" == *-* ]] && continue
    v=$(cat "$card/device/vendor" 2>/dev/null) || continue
    name=${VENDOR[$v]:-}
    [[ -z "$name" ]] && continue
    [[ -n "${pci[$name]:-}" ]] && continue          # first card per vendor is enough
    gpus+=("$name")
    pci[$name]=$(basename "$(readlink -f "$card/device")")
    r=$(ls -d "$card"/device/drm/renderD* 2>/dev/null | head -1)
    render[$name]=${r:+/dev/dri/$(basename "$r")}
    boot[$name]=$(cat "$card/device/boot_vga" 2>/dev/null || echo 0)
done

has() { [[ " ${gpus[*]} " == *" $1 "* ]]; }

va_of() {
    case "$1" in
        nvidia) echo nvidia ;;
        amd) echo radeonsi ;;
        intel)
            # Broadwell (gen 8) and newer use iHD (intel-media-driver); older ones i965
            local dev; dev=$(cat "/sys/bus/pci/devices/${pci[intel]}/device" 2>/dev/null)
            if [[ -n "$dev" ]] && (( dev < 0x1600 )); then echo i965; else echo iHD; fi ;;
    esac
}

mode=unknown igpu="" dgpu=""
if has nvidia && { has intel || has amd; }; then
    dgpu=nvidia; igpu=$(has intel && echo intel || echo amd); mode=hybrid-nvidia
elif has amd && has intel; then
    dgpu=amd; igpu=intel; mode=hybrid-amd
elif (( ${#gpus[@]} > 0 )); then
    mode=${gpus[0]}
fi

display=""
for g in "${gpus[@]}"; do [[ "${boot[$g]}" == 1 ]] && display=$g; done
[[ -z "$display" ]] && display=${igpu:-${gpus[0]:-}}

nv_ver=$(cat /sys/module/nvidia/version 2>/dev/null || true)
nv_open=0
[[ -n "$nv_ver" ]] && modinfo -F license nvidia 2>/dev/null | grep -q "MIT" && nv_open=1
nv_arch=""
if has nvidia; then
    dev=$(cat "/sys/bus/pci/devices/${pci[nvidia]}/device" 2>/dev/null)
    # Turing (TU1xx, device ids from 0x1e00) and newer run the open kernel modules
    if [[ -n "$dev" ]] && (( dev >= 0x1e00 )); then nv_arch=turing+; else nv_arch=legacy; fi
fi

sb="?"
if command -v mokutil >/dev/null; then
    case "$(mokutil --sb-state 2>/dev/null)" in *enabled*) sb=1 ;; *disabled*) sb=0 ;; esac
fi

echo "MODE=$mode"
echo "GPUS=\"${gpus[*]}\""
echo "IGPU=$igpu"
echo "DGPU=$dgpu"
echo "DISPLAY_GPU=$display"
for g in "${gpus[@]}"; do
    G=${g^^}
    echo "${G}_PCI=${pci[$g]}"
    echo "${G}_RENDER=${render[$g]}"
    echo "${G}_VA=$(va_of "$g")"
done
echo "NVIDIA_DRIVER=$nv_ver"
echo "NVIDIA_OPEN=$nv_open"
echo "NVIDIA_ARCH=$nv_arch"
echo "SECURE_BOOT=$sb"
