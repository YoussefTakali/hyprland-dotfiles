#!/usr/bin/env bash
# Waybar: network speed, shown only while something is actually transferring (≥ 150 KB/s); hidden otherwise.
# Prints one JSON line every 2 s.
THRESH=$((150 * 1024))
human() { awk -v b="$1" 'BEGIN{ if (b >= 1048576) printf "%.1f MB/s", b/1048576; else printf "%d KB/s", b/1024 }'; }
prev_rx=0 prev_tx=0 prev_if=""
while :; do
    iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if [[ -n $iface && -r /sys/class/net/$iface/statistics/rx_bytes ]]; then
        rx=$(</sys/class/net/$iface/statistics/rx_bytes); tx=$(</sys/class/net/$iface/statistics/tx_bytes)
        if [[ $iface == "$prev_if" ]]; then
            drx=$(( (rx - prev_rx) / 2 )); dtx=$(( (tx - prev_tx) / 2 ))
            text=""
            (( drx >= THRESH )) && text="󰇚 $(human $drx)"
            (( dtx >= THRESH )) && text="${text:+$text  }󰕒 $(human $dtx)"
            if [[ -n $text ]]; then
                printf '{"text":"%s","tooltip":"%s: down %s, up %s","class":"active"}\n' "$text" "$iface" "$(human $drx)" "$(human $dtx)"
            else
                echo '{"text":"","class":"idle"}'
            fi
        fi
        prev_rx=$rx prev_tx=$tx prev_if=$iface
    else
        echo '{"text":"","class":"idle"}'
    fi
    sleep 2
done
