#!/usr/bin/env bash
# Prefer the sole display-connected card without embedding a model or PCI address.
# With multiple active GPUs, leave device selection to the compositor.
set -u
[[ ! ${AQ_DRM_DEVICES+x} ]] || exit 0
cards=() all=()
for card in "${GPU_SYSFS_ROOT:-/sys}"/class/drm/card[0-9]*; do
    [[ ${card##*/} =~ ^card[0-9]+$ ]] || continue
    [[ -r $card/device/vendor ]] || continue
    all+=("/dev/dri/${card##*/}")
    for status in "$card"/card*-*/status; do
        [[ -r $status && $(<"$status") == connected ]] || continue
        cards+=("$card"); break
    done
done
if [[ ${#cards[@]} == 1 ]]; then
    card=${cards[0]}
    primary="/dev/dri/${card##*/}"
    devices=$primary
    for other in "${all[@]}"; do
        [[ $other == "$primary" ]] || devices+=":$other"
    done
    printf '%s %s\n' "$devices" "$(cat "$card/device/vendor")"
fi
