#!/usr/bin/env bash
# Run as root by the graphical installer (through pkexec, so the user sees the normal password dialog).
#   grant.sh grant <user>    let <user> use sudo without a password while the installation runs
#   grant.sh revoke <user>   take it back
# Safety: the rule also disappears after 4 hours (timer) and at the next boot, so a crash can't leave it behind.
set -euo pipefail
action=${1:-} user=${2:-}
[[ $EUID -eq 0 ]] || { echo "must run as root"; exit 1; }
[[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] && id "$user" >/dev/null 2>&1 || { echo "bad user"; exit 1; }
F="/etc/sudoers.d/zz-desktop-installer-$user"
UNIT=desktop-installer-cleanup
case "$action" in
    grant)
        tmp=$(mktemp)
        echo "# Temporary (desktop installer): removed when the installation ends, after 4 h, or at next boot" > "$tmp"
        echo "$user ALL=(ALL) NOPASSWD: ALL" >> "$tmp"
        visudo -cf "$tmp" >/dev/null
        install -m 0440 "$tmp" "$F"; rm -f "$tmp"
        systemd-run --unit="$UNIT-timer-$user" --on-active=4h --timer-property=AccuracySec=1min \
            /usr/bin/rm -f "$F" >/dev/null 2>&1 || true
        cat > "/etc/systemd/system/$UNIT.service" <<UNITEOF
[Unit]
Description=Remove the desktop installer's temporary sudo rule
[Service]
Type=oneshot
ExecStart=/usr/bin/sh -c 'rm -f /etc/sudoers.d/zz-desktop-installer-*; systemctl disable $UNIT.service; rm -f /etc/systemd/system/$UNIT.service'
[Install]
WantedBy=multi-user.target
UNITEOF
        systemctl daemon-reload; systemctl enable "$UNIT.service" >/dev/null 2>&1
        echo granted ;;
    revoke)
        rm -f "$F"
        systemctl stop "$UNIT-timer-$user.timer" >/dev/null 2>&1 || true
        systemctl disable "$UNIT.service" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/$UNIT.service"; systemctl daemon-reload
        echo revoked ;;
    *) echo "usage: grant.sh grant|revoke <user>"; exit 1 ;;
esac
