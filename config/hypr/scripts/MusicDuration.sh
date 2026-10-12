#!/bin/bash
playerctl metadata --format '{{duration(mpris:length)}}' 2>/dev/null || echo "0:00"
