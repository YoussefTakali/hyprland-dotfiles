#!/usr/bin/env bash
# Build a fake sysfs GPU tree, to test the installer's GPU handling on hardware you don't have (e.g. in a VM):
#   installer/test/fake-gpus.sh DIR nvidia:0x28e0:0 amd:0x15bf:1      # vendor:pci-device-id:boot_vga, one per GPU
#   GPUINFO_SYSROOT=DIR ./install.sh
# boot_vga=1 marks the GPU the built-in screen is wired to. Drivers still install for real; they just find no card.
set -euo pipefail
root=$1; shift
rm -rf "$root/sys"; mkdir -p "$root/sys/class/drm" "$root/sys/bus/pci/devices"
declare -A VID=([nvidia]=0x10de [amd]=0x1002 [intel]=0x8086)
n=0
for spec in "$@"; do
    IFS=: read -r v dev boot <<<"$spec"
    pci=$(printf '0000:%02x:00.0' $((n + 1)))
    d="$root/sys/devices/pci0000:00/$pci"
    mkdir -p "$d/drm/card$n" "$d/drm/renderD$((128 + n))" "$root/sys/class/drm/card$n"
    echo "${VID[$v]}" > "$d/vendor"; echo "$dev" > "$d/device"; echo "${boot:-0}" > "$d/boot_vga"
    ln -s "$d" "$root/sys/bus/pci/devices/$pci"
    ln -s "$d" "$root/sys/class/drm/card$n/device"
    n=$((n + 1))
done
echo "Fake GPUs in $root/sys: $*"
