#!/usr/bin/env bash
# Lock-screen status line: waiting notifications + mic state.
n=$(swaync-client -c 2>/dev/null || echo 0)
case "$n" in
    0) notif="󰂚 no notifications" ;;
    1) notif="󰂞 1 notification" ;;
    *) notif="󰂞 $n notifications" ;;
esac
if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED; then mic="󰍭 mic muted"; else mic="󰍬 mic on"; fi
echo "$notif  ·  $mic"
