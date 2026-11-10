#!/usr/bin/env bash
# Wi-Fi and Bluetooth menus in rofi. Usage: NetMenu.sh [--wifi|--bluetooth]   (no argument: pick one)

THEME="$HOME/.config/rofi/config-utilities-list.rasi"
menu() { rofi -dmenu -i -p "$1" -theme "$THEME" "${@:2}"; }

wifi_icon() {   # signal 0-100 -> icon
    local s=$1
    if   (( s >= 80 )); then echo "󰤨"
    elif (( s >= 60 )); then echo "󰤥"
    elif (( s >= 40 )); then echo "󰤢"
    elif (( s >= 20 )); then echo "󰤟"
    else echo "󰤯"; fi
}

wifi() {
    local radio rows=() ssids=() line sig sec use ssid
    radio=$(nmcli radio wifi)
    if [[ $radio != enabled ]]; then
        [[ $(printf '󰖩  Turn Wi-Fi on\n' | menu "Wi-Fi") ]] && nmcli radio wifi on && notify-send -a "Wi-Fi" "Wi-Fi on"
        return
    fi
    nmcli dev wifi rescan >/dev/null 2>&1 &   # refresh in the background; the menu uses the cached list (instant)
    rows+=("󰖪  Turn Wi-Fi off") ssids+=("__off")
    rows+=("󰑓  Rescan")         ssids+=("__scan")
    if [[ -n "$(nmcli -t -f TYPE con show | grep -E '^(vpn|wireguard)$')" ]]; then
        rows+=("󰖂  VPN…") ssids+=("__vpn")
    fi
    rows+=("󰺪  Hidden network…") ssids+=("__hidden")
    rows+=("󰒓  Network settings") ssids+=("__settings")
    declare -A seen
    while IFS=: read -r use sig sec ssid; do
        [[ -z "$ssid" || -n "${seen[$ssid]}" ]] && continue
        seen[$ssid]=1
        local lock=""; [[ -n "$sec" && "$sec" != "--" ]] && lock="  󰌾"
        local cur=""; [[ $use == "*" ]] && cur="   󰄬 connected"
        rows+=("$(wifi_icon "$sig")  ${ssid}${lock}   ${sig}%${cur}") ssids+=("$ssid")
    done < <(nmcli -t -e no -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan "${RESCAN:-no}" 2>/dev/null)

    local i
    i=$(printf '%s\n' "${rows[@]}" | menu "Wi-Fi" -format i) || return
    [[ -z "$i" ]] && return
    case "${ssids[$i]}" in
        __off)      nmcli radio wifi off && notify-send -a "Wi-Fi" "Wi-Fi off" ;;
        __scan)     notify-send -a "Wi-Fi" -t 1500 "Scanning…"; RESCAN=yes wifi ;;
        __settings) nm-connection-editor >/dev/null 2>&1 & ;;
        __vpn)      vpn ;;
        __hidden)   wifi_hidden ;;
        *)          wifi_network "${ssids[$i]}" "${rows[$i]}" ;;
    esac
}

# Actions for one network: connect / disconnect, details, forget (saved networks only)
wifi_network() {
    local ssid=$1 saved="" active="" acts=() keys=() i
    nmcli -t -f NAME con show | grep -Fxq "$ssid" && saved=1
    nmcli -t -f NAME con show --active | grep -Fxq "$ssid" && active=1
    if [[ -n $active ]]; then acts+=("󰖪  Disconnect") keys+=(down)
    else acts+=("󰖩  Connect") keys+=(up); fi
    [[ -n $active ]] && { acts+=("󰋼  Details") keys+=(info); }
    [[ -n $saved ]] && { acts+=("󰩺  Forget this network") keys+=(forget); }
    [[ ${#acts[@]} -eq 1 && ${keys[0]} == up ]] && { wifi_connect "$ssid"; return; }
    i=$(printf '%s\n' "${acts[@]}" | menu "$ssid" -format i) || return
    case "${keys[$i]}" in
        up)     wifi_connect "$ssid" ;;
        down)   nmcli con down id "$ssid" >/dev/null && notify-send -a "Wi-Fi" "Disconnected" "$ssid" ;;
        info)
            local dev ip gw sig
            dev=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2=="wifi"{print $1; exit}')
            ip=$(nmcli -g IP4.ADDRESS dev show "$dev" | head -1)
            gw=$(nmcli -g IP4.GATEWAY dev show "$dev")
            sig=$(nmcli -t -f IN-USE,SIGNAL,RATE,CHAN dev wifi | awk -F: '$1=="*"{print $2"%  ·  "$3"  ·  ch "$4}')
            notify-send -a "Wi-Fi" "$ssid" "IP: $ip\nGateway: $gw\nSignal: $sig" ;;
        forget)
            [[ $(printf '%s\n' "󰩺  Yes, forget $ssid" "Cancel" | menu "Forget?") == *Yes* ]] || return
            nmcli con delete id "$ssid" >/dev/null && notify-send -a "Wi-Fi" "Forgot $ssid" ;;
    esac
}

wifi_hidden() {
    local ssid pass out
    ssid=$(menu "Network name (SSID)" -l 0 </dev/null) || return
    [[ -z "$ssid" ]] && return
    pass=$(menu "Password (empty if open)" -password -l 0 </dev/null) || return
    if [[ -n "$pass" ]]; then out=$(nmcli dev wifi connect "$ssid" password "$pass" hidden yes 2>&1)
    else out=$(nmcli dev wifi connect "$ssid" hidden yes 2>&1); fi
    if [[ $? -eq 0 ]]; then notify-send -a "Wi-Fi" "Connected" "$ssid"
    else notify-send -u critical -a "Wi-Fi" "Couldn't connect to $ssid" "$out"; fi
}

vpn() {
    local rows=() names=() name type state i
    while IFS=: read -r name type state; do
        [[ $type == vpn || $type == wireguard ]] || continue
        if [[ -n $state ]]; then rows+=("󰖂  $name   󰄬 on"); else rows+=("󰿆  $name"); fi
        names+=("$name")
    done < <(nmcli -t -e no -f NAME,TYPE,DEVICE con show)
    i=$(printf '%s\n' "${rows[@]}" | menu "VPN" -format i) || return
    name=${names[$i]}
    if nmcli -t -f NAME con show --active | grep -Fxq "$name"; then
        nmcli con down id "$name" >/dev/null && notify-send -a "VPN" "Disconnected" "$name"
    else
        if out=$(nmcli con up id "$name" 2>&1); then notify-send -a "VPN" "Connected" "$name"
        else notify-send -u critical -a "VPN" "Couldn't connect" "$out"; fi
    fi
}

wifi_connect() {
    local ssid=$1 out
    if nmcli -t -f NAME con show | grep -Fxq "$ssid"; then
        out=$(nmcli con up id "$ssid" 2>&1)
    else
        local pass
        pass=$(menu "Password for $ssid" -password -l 0 </dev/null) || return
        if [[ -n "$pass" ]]; then out=$(nmcli dev wifi connect "$ssid" password "$pass" 2>&1)
        else out=$(nmcli dev wifi connect "$ssid" 2>&1); fi
    fi
    if [[ $? -eq 0 ]]; then notify-send -a "Wi-Fi" "Connected" "$ssid"
    else notify-send -u critical -a "Wi-Fi" "Couldn't connect to $ssid" "$out"; fi
}

# bluetoothctl exits 0 even when power on/connect fail, so every action below checks the real state afterwards.
# A dual-mode headset (classic + LE) can be linked over LE only, for its battery level, with no sound; audio
# devices count as connected only when the classic (BR/EDR) link that carries the sound is up.
bt_connected() {
    local info; info=$(bluetoothctl info "$1")
    if grep -q "Icon: audio-" <<<"$info" && grep -q "BREDR.Connected:" <<<"$info"; then
        grep -q "BREDR.Connected: yes" <<<"$info"
    else
        grep -qE "^\s*Connected: yes" <<<"$info"
    fi
}
bt_wait() {   # bt_wait <mac> yes|no   wait up to 12 s for that state
    local _; for _ in {1..24}; do
        if bt_connected "$1"; then [[ $2 == yes ]] && return 0; else [[ $2 == no ]] && return 0; fi
        sleep 0.5
    done; return 1
}
bt_powered() { [[ $(bluetoothctl show | awk '/Powered:/ {print $2; exit}') == yes ]]; }
bt_power() {  # bt_power on|off   switch and confirm
    local _ want=no; [[ $1 == on ]] && want=yes
    bluetoothctl power "$1" >/dev/null 2>&1
    for _ in {1..15}; do [[ $(bluetoothctl show | awk '/Powered:/ {print $2; exit}') == "$want" ]] && return 0; sleep 0.3; done
    return 1
}
bt_why() {    # turn bluetoothctl's error into something useful
    case "$1" in
        *page-timeout*|*"Host is down"*|*"No route to host"*|*"Page Timeout"*)
            echo "The device is off, out of range, or connected to another device (a phone?)." ;;
        *NotReady*|*"not powered"*|*NotAvailable*) echo "Bluetooth is off." ;;
        *) grep -m1 -oE "Failed to [a-z]+: .*" <<<"$1" || echo "No answer from the device." ;;
    esac
}

bluetooth() {
    local powered rows=() macs=() mac name i
    if ! bt_powered; then
        [[ $(printf '󰂯  Turn Bluetooth on\n' | menu "Bluetooth") ]] || return
        if bt_power on; then notify-send -a "Bluetooth" "Bluetooth on"; bluetooth
        else notify-send -u critical -a "Bluetooth" "Couldn't turn Bluetooth on" "Check that it isn't blocked: rfkill list"; fi
        return
    fi
    rows+=("󰂲  Turn Bluetooth off") macs+=("__off")
    rows+=("󰂰  Scan & pair a new device…") macs+=("__pair")
    rows+=("󰒓  Bluetooth settings") macs+=("__settings")
    while read -r _ mac name; do
        [[ -z "$mac" ]] && continue
        local info batt="" state="" icon="󰂯"
        info=$(bluetoothctl info "$mac")
        if bt_connected "$mac"; then
            state="   󰄬 connected"; icon="󰂱"
            b=$(awk -F'[()]' '/Battery Percentage/ {print $2}' <<<"$info")
            [[ -n "$b" ]] && batt="  󰥉 ${b}%"
        fi
        case "$(awk '/Icon:/ {print $2}' <<<"$info")" in
            audio-headset|audio-headphones) icon="󰋋" ;;
            input-mouse)    icon="󰍽" ;;
            input-keyboard) icon="󰌌" ;;
            phone)          icon="󰏲" ;;
        esac
        rows+=("$icon  ${name}${batt}${state}") macs+=("$mac")
    done < <(bluetoothctl devices Paired)

    i=$(printf '%s\n' "${rows[@]}" | menu "Bluetooth" -format i) || return
    [[ -z "$i" ]] && return
    case "${macs[$i]}" in
        __off)  if bt_power off; then notify-send -a "Bluetooth" "Bluetooth off"
                else notify-send -u critical -a "Bluetooth" "Couldn't turn Bluetooth off"; fi ;;
        __pair)     bt_pair ;;
        __settings) blueman-manager >/dev/null 2>&1 & ;;
        *)          bt_device "${macs[$i]}" "${rows[$i]}" ;;
    esac
}

# Actions for one paired device: connect / disconnect, send a file, remove
bt_device() {
    local mac=$1 label=$2 acts=() keys=() i connected=""
    bt_connected "$mac" && connected=1
    if [[ -n $connected ]]; then acts+=("󰂲  Disconnect") keys+=(down)
    else acts+=("󰂱  Connect") keys+=(up); fi
    acts+=("󰕒  Send a file…") keys+=(send)
    acts+=("󰩺  Remove device") keys+=(remove)
    i=$(printf '%s\n' "${acts[@]}" | menu "${label%%   *}" -format i) || return
    case "${keys[$i]}" in
        down)
            bluetoothctl disconnect "$mac" >/dev/null 2>&1
            if bt_wait "$mac" no; then notify-send -a "Bluetooth" "Disconnected" "${label%%   *}"
            else notify-send -u critical -a "Bluetooth" "Couldn't disconnect" "${label%%   *}"; fi ;;
        up)
            local out
            notify-send -a "Bluetooth" -t 2000 "Connecting…" "${label%%   *}"
            out=$(timeout 20 bluetoothctl connect "$mac" 2>&1)
            if ! bt_wait "$mac" yes && ! bt_connected "$mac"; then
                # linked over LE only: drop that link and ask again, so the audio link is made
                bluetoothctl disconnect "$mac" >/dev/null 2>&1; sleep 1
                out=$(timeout 20 bluetoothctl connect "$mac" 2>&1)
                bt_wait "$mac" yes
            fi
            if bt_connected "$mac"; then notify-send -a "Bluetooth" "Connected" "${label%%   *}"
            else notify-send -u critical -a "Bluetooth" "Couldn't connect" "${label%%   *}: $(bt_why "$out")"; fi ;;
        send)   blueman-sendto --device="$mac" >/dev/null 2>&1 & ;;
        remove)
            [[ $(printf '%s\n' "󰩺  Yes, remove it" "Cancel" | menu "Remove?") == *Yes* ]] || return
            bluetoothctl remove "$mac" >/dev/null && notify-send -a "Bluetooth" "Removed" "$label" ;;
    esac
}

# Scan for ~8 s, list new devices, then pair + trust + connect the chosen one
bt_pair() {
    local rows=() macs=() mac name i
    notify-send -a "Bluetooth" -t 8000 "Scanning for devices…" "Put the device in pairing mode"
    bluetoothctl --timeout 8 scan on >/dev/null 2>&1
    while read -r _ mac name; do
        [[ -z "$mac" ]] && continue
        bluetoothctl info "$mac" | grep -q "Paired: yes" && continue
        [[ "$name" == "${mac//:/-}" ]] && continue          # skip nameless beacons
        rows+=("󰂯  $name") macs+=("$mac")
    done < <(bluetoothctl devices)
    if (( ${#rows[@]} == 0 )); then notify-send -a "Bluetooth" "No new devices found"; return; fi
    i=$(printf '%s\n' "${rows[@]}" | menu "Pair" -format i) || return
    mac=${macs[$i]}
    notify-send -a "Bluetooth" -t 3000 "Pairing…" "${rows[$i]}"
    local out; out=$(timeout 30 bluetoothctl pair "$mac" 2>&1)
    if bluetoothctl info "$mac" | grep -q "Paired: yes"; then
        bluetoothctl trust "$mac" >/dev/null 2>&1
        timeout 20 bluetoothctl connect "$mac" >/dev/null 2>&1
        if bt_wait "$mac" yes; then notify-send -a "Bluetooth" "Paired and connected" "${rows[$i]}"
        else notify-send -a "Bluetooth" "Paired, but not connected yet" "${rows[$i]}: pick it in the Bluetooth menu to connect"; fi
    else
        notify-send -u critical -a "Bluetooth" "Pairing failed" "$(bt_why "$out")"
    fi
}

case "$1" in
    --wifi)      wifi ;;
    --bluetooth) bluetooth ;;
    *)
        c=$(printf '%s\n' "󰖩  Wi-Fi" "󰂯  Bluetooth" | menu "Connections") || exit 0
        [[ $c == *Wi-Fi* ]] && wifi || { [[ $c == *Bluetooth* ]] && bluetooth; } ;;
esac
