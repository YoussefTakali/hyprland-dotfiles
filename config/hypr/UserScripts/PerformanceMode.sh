#!/usr/bin/env bash
# Balanced keeps desktop effects; fast reduces rendering work for maximum responsiveness.
set -euo pipefail
out="$HOME/.config/hypr/UserConfigs/Performance.conf"
case ${1:-} in
    balanced)
        text='debug {
  vfr = true
}
decoration {
  blur {
    size = 4
    passes = 1
  }
}
' ;;
    fast)
        text='debug {
  vfr = true
}
decoration {
  blur {
    enabled = false
  }
  shadow {
    enabled = false
  }
}
animations {
  enabled = false
}
' ;;
    default) text='# Original decoration and animation settings apply.
' ;;
    *) echo 'Usage: PerformanceMode.sh balanced|fast|default'; exit 1 ;;
esac
mkdir -p "${out%/*}"
tmp=$(mktemp "${out}.XXXXXX")
printf '%s' "$text" > "$tmp"
mv "$tmp" "$out"
echo "Performance mode: $1 (config watcher reloads Hyprland automatically)"
