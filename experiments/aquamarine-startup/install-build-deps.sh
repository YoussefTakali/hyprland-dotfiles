#!/usr/bin/env bash
# Build dependencies only; never replace the packaged compositor or GPU driver.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Administrator authentication is required to install build dependencies.' >&2; exit 1; }
dnf install -y --setopt=install_weak_deps=False \
    gcc-c++ cmake ninja-build hyprwayland-scanner hyprutils-devel-0.14.3 \
    'pkgconfig(libseat)' 'pkgconfig(libinput)' 'pkgconfig(wayland-client)' \
    'pkgconfig(wayland-protocols)' 'pkgconfig(pixman-1)' 'pkgconfig(libdrm)' \
    'pkgconfig(gbm)' 'pkgconfig(libudev)' 'pkgconfig(libdisplay-info)' \
    'pkgconfig(hwdata)' 'pkgconfig(egl)' 'pkgconfig(glesv2)'
