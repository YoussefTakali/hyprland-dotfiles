#!/usr/bin/env bash
# Lock the session with the Quickshell lock screen (~/.config/quickshell/lockscreen), falling back to hyprlock.
# Called by hypridle's lock_cmd (so Super+L / LockScreen.sh / lid / suspend all land here).
#   - one instance only
#   - runs a frozen copy of the config, so editing the lock files while locked can't touch the live lock
#   - if Quickshell doesn't confirm a secure lock within 4 s, exits with an error/crash while locked, or its log
#     reports the lock being dropped, hyprlock takes over (misc:allow_session_lock_restore lets it replace a dead locker)
RUN="${XDG_RUNTIME_DIR:-/tmp}"
MARK="$RUN/qslock.secure"
LOG="$RUN/qslock.log"
SRC="$HOME/.config/quickshell/lockscreen"

exec 9>"$RUN/qslock.instance"
flock -n 9 || exit 0                       # already locking
pidof hyprlock >/dev/null && exit 0

fallback() {
    [[ -n "$QS" ]] && kill "$QS" 2>/dev/null
    pidof hyprlock >/dev/null || { "$HOME/.config/hypr/scripts/MusicCard.sh" >/dev/null 2>&1; hyprlock 9>&-; }
    rm -f "$MARK"; rm -rf "$SNAP"
    exit 0
}

# Frozen snapshot of the lock config
SNAP=$(mktemp -d "$RUN/qslock-cfg.XXXXXX") && cp -r "$SRC/." "$SNAP/" || { SNAP=""; fallback; }

rm -f "$MARK"
qs -p "$SNAP/shell.qml" >"$LOG" 2>&1 9>&- &
QS=$!

for _ in $(seq 40); do                     # wait up to 4 s for the compositor to confirm the lock
    [[ -f "$MARK" ]] && break
    kill -0 "$QS" 2>/dev/null || break
    sleep 0.1
done
[[ -f "$MARK" ]] || fallback

# Watch the running lock: a dropped/failed lock in the log, or a non-zero exit → hyprlock
while kill -0 "$QS" 2>/dev/null; do
    if grep -qE "destroyed without unlocking|Failed to acquire session lock" "$LOG" 2>/dev/null; then
        fallback
    fi
    sleep 0.5
done
wait "$QS"; rc=$?
rm -f "$MARK"; rm -rf "$SNAP"
(( rc != 0 )) && fallback               # crash/kill while locked → keep it locked with hyprlock
exit 0
