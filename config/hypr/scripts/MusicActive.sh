#!/bin/bash

status=$(playerctl status 2>/dev/null)

if [ "$status" = "Playing" ] || [ "$status" = "Paused" ]; then
    echo "1"
else
    echo "0"
fi
