#!/bin/bash
# MediaInfo.sh — FIXED version

MODE=$1

STATUS=$(playerctl status 2>/dev/null)

# fallback instead of killing output
[ -z "$STATUS" ] && STATUS="Stopped"

case $MODE in
  icon)
    if [ "$STATUS" != "Playing" ]; then
      echo "󰝛"
      exit
    fi

    PLAYER=$(playerctl -l 2>/dev/null | head -1)
    case $PLAYER in
      *spotify*) echo "󰓇" ;;
      *firefox*|*chrome*|*chromium*) echo "󰗃" ;;
      *mpv*)     echo "󰎁" ;;
      *mpd*)     echo "󰎆" ;;
      *)         echo "󰝚" ;;
    esac
    ;;

  title)
    playerctl metadata title 2>/dev/null | cut -c1-35 || echo "No music"
    ;;

  artist)
    playerctl metadata artist 2>/dev/null | cut -c1-32 || echo ""
    ;;

  progress)
    POS=$(playerctl position 2>/dev/null | cut -d. -f1)
    LEN=$(playerctl metadata mpris:length 2>/dev/null)

    if [ -z "$POS" ] || [ -z "$LEN" ]; then
      echo "─────────────"
      exit
    fi

    LEN_SEC=$(( LEN / 1000000 ))
    [ $LEN_SEC -eq 0 ] && echo "─────────────" && exit

    PCT=$(( POS * 100 / LEN_SEC ))
    FILLED=$(( PCT * 15 / 100 ))
    EMPTY=$(( 15 - FILLED ))

    BAR=$(printf '━%.0s' $(seq 1 $FILLED))
    REST=$(printf '─%.0s' $(seq 1 $EMPTY))

    echo "${BAR}${REST} ${PCT}%"
    ;;

  time)
    POS=$(playerctl position 2>/dev/null | cut -d. -f1)
    LEN=$(playerctl metadata mpris:length 2>/dev/null)

    if [ -z "$POS" ] || [ -z "$LEN" ]; then
      echo ""
      exit
    fi

    LEN_SEC=$(( LEN / 1000000 ))

    printf "%d:%02d / %d:%02d" \
      $((POS/60)) $((POS%60)) \
      $((LEN_SEC/60)) $((LEN_SEC%60))
    ;;
esac
