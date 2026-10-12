#!/usr/bin/env bash
# Waybar: NVIDIA GPU usage as JSON.
# Doesn't call nvidia-smi while the GPU is runtime-suspended, so the bar never wakes it up (battery).

dev=""
for d in /sys/bus/pci/devices/*; do
    [[ $(<"$d/vendor") == 0x10de && $(<"$d/class") == 0x03* ]] && { dev=$d; break; }
done

if [[ -z "$dev" ]] || ! command -v nvidia-smi >/dev/null; then
    echo '{"text":"","class":"none"}'; exit 0
fi

if [[ $(<"$dev/power/runtime_status") != active ]]; then
    echo '{"text":"off 󰢮","tooltip":"NVIDIA GPU asleep (saving power)","class":"off"}'; exit 0
fi

IFS=', ' read -r util temp mused mtotal power < <(nvidia-smi \
    --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw \
    --format=csv,noheader,nounits 2>/dev/null)
[[ -z "$util" ]] && { echo '{"text":"? 󰢮","class":"off"}'; exit 0; }

class=normal
(( util >= 85 )) && class=critical || { (( util >= 50 )) && class=high; }
tip="NVIDIA RTX 4060\\nUsage: ${util}%\\nTemp: ${temp}°C\\nVRAM: ${mused} / ${mtotal} MiB\\nPower: ${power} W\\n\\nRight click: nvtop"
printf '{"text":"%s%% 󰢮","tooltip":"%s","class":"%s","percentage":%s}\n' "$util" "$tip" "$class" "$util"
