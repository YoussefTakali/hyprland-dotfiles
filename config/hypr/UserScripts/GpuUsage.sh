#!/usr/bin/env bash
# Waybar: GPU usage as JSON - NVIDIA, AMD and Intel, with the real card name (nothing hard-coded).
#   NVIDIA: nvidia-smi, but never while the GPU is runtime-suspended (would wake it up and drain the battery).
#   AMD:    amdgpu sysfs (busy %, VRAM, temperature, power) - no extra tools needed.
#   Intel:  no usage counter without root, so the bar shows the current clock as % of the maximum.
# Prefers a discrete GPU (NVIDIA, then AMD) over an integrated one.

json() {  # text tooltip class percentage
    printf '{"text":"%s","tooltip":"%s","class":"%s","percentage":%s}\n' "$1" "$2" "$3" "${4:-0}"
}
level() { (( $1 >= 85 )) && echo critical && return; (( $1 >= 50 )) && echo high || echo normal; }
pci_name() {  # "Vendor Device" from lspci, without the "[...]" codes
    local n; n=$(lspci -s "${1##*/}" 2>/dev/null | sed -E 's/^[^:]+: *[^:]+: *//; s/ \(rev [0-9a-f]+\)//')
    n=$(sed -E 's/.*\[([^]]+)\].*/\1/' <<<"$n")          # NVIDIA/AMD put the marketing name in [brackets]
    echo "${n:-GPU}"
}

nv="" amd="" intel=""
for d in /sys/bus/pci/devices/*; do
    [[ $(<"$d/class") == 0x03* ]] || continue
    case $(<"$d/vendor") in
        0x10de) nv=${nv:-$d} ;;
        0x1002) amd=${amd:-$d} ;;
        0x8086) intel=${intel:-$d} ;;
    esac
done

# ── NVIDIA ──────────────────────────────────────────────────────────────────
if [[ -n "$nv" ]] && command -v nvidia-smi >/dev/null; then
    if [[ $(<"$nv/power/runtime_status") != active ]]; then
        json "off 󰢮" "$(pci_name "$nv") asleep (saving power)" off; exit 0
    fi
    IFS=', ' read -r util temp mused mtotal power < <(nvidia-smi \
        --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw \
        --format=csv,noheader,nounits 2>/dev/null)
    if [[ -n "$util" ]]; then
        name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        tip="${name:-$(pci_name "$nv")}\\nUsage: ${util}%\\nTemp: ${temp}°C\\nVRAM: ${mused} / ${mtotal} MiB\\nPower: ${power} W\\n\\nRight click: nvtop"
        json "${util}% 󰢮" "$tip" "$(level "$util")" "$util"; exit 0
    fi
fi

# ── AMD ─────────────────────────────────────────────────────────────────────
if [[ -n "$amd" && -r "$amd/gpu_busy_percent" ]]; then
    util=$(<"$amd/gpu_busy_percent")
    tip="$(pci_name "$amd")\\nUsage: ${util}%"
    if [[ -r "$amd/mem_info_vram_used" ]]; then
        tip+="\\nVRAM: $(( $(<"$amd/mem_info_vram_used") / 1048576 )) / $(( $(<"$amd/mem_info_vram_total") / 1048576 )) MiB"
    fi
    for h in "$amd"/hwmon/hwmon*; do
        [[ -r "$h/temp1_input" ]] && tip+="\\nTemp: $(( $(<"$h/temp1_input") / 1000 ))°C"
        for p in power1_average power1_input; do
            [[ -r "$h/$p" ]] && { tip+="\\nPower: $(( $(<"$h/$p") / 1000000 )) W"; break; }
        done
    done
    json "${util}% 󰢮" "$tip\\n\\nRight click: nvtop" "$(level "$util")" "$util"; exit 0
fi

# ── Intel (i915 or xe) ──────────────────────────────────────────────────────
if [[ -n "$intel" ]]; then
    for c in /sys/class/drm/card*; do
        [[ $(readlink -f "$c/device") == "$(readlink -f "$intel")" ]] || continue
        act="" max=""
        if [[ -r "$c/gt_act_freq_mhz" ]]; then
            act=$(<"$c/gt_act_freq_mhz"); max=$(<"$c/gt_max_freq_mhz")
        else
            f=$(ls -d "$c"/device/tile0/gt0/freq0 2>/dev/null | head -1)
            [[ -n "$f" ]] && { act=$(<"$f/act_freq"); max=$(<"$f/max_freq"); }
        fi
        if [[ -n "$act" && "${max:-0}" -gt 0 ]]; then
            pct=$(( act * 100 / max ))
            json "${pct}% 󰢮" "$(pci_name "$intel")\\nClock: ${act} / ${max} MHz\\n(Intel has no usage counter; this is the clock)\\n\\nRight click: nvtop" "$(level "$pct")" "$pct"
            exit 0
        fi
    done
fi

json "" "" none 0
