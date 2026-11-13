# Optional one-shot Aquamarine startup trial

On this PC's saved trace, Aquamarine made two redundant probes after already
scanning connectors and probed GPU panels to determine an order even though
Hyprland had an explicit GPU order. Those intervals are the largest measured
single-compositor-code opportunities: two connector gaps of approximately 120 ms
plus one 131 ms panel-ordering gap.

The private candidate skips panel-ordering scans only when a nonempty explicit GPU
order is supplied. It **keeps the first full kernel connector probe**, because the
greeter's cache can be stale. It then reuses a connected, mode-populated connector
only immediately after a fresh scan. Unknown, disconnected and empty modes fall
back to a full probe. Hotplug and later rescans remain fresh.

This is experimental and version-specific. It changes no PCI address, GPU driver,
Secure Boot key, kernel option, display mode or packaged RPM. It is never selected
by normal login or by either default installer. The installer-compatible builder
checks exact RPM versions, a pinned upstream source archive hash, the patch, C++
fallback tests, shipped library tests, symbol resolution through the actual
Hyprland binary, and Hyprland config parsing. The trial launcher rechecks package,
library, kernel and NVIDIA driver identities. A pre-start failure falls back once
to packaged Hyprland, and later logins use the packaged backend automatically.

Prepare the trial as your normal user:

```bash
bash experiments/aquamarine-startup/enable-fast-start-trial.sh
```

It requires the active one-monitor session, a matching wallpaper cache, sudo, and
the same installed RPM versions. It builds privately, then installs/selects a
separate **Hyprland (Fast startup trial)** session. Your desktop keeps running.
At the next login, select that entry if the display manager does not preselect it.
The original packaged Hyprland session remains available.

The candidate targets about **250 ms** in intervals seen in this PC's trace. That
is an estimate, not a claimed improvement. After the login, check
`~/.local/state/session-startup/launcher.log` for `native-candidate-active` and use
`python3 tools/session/measure-login.py` to read presentation-aware command timestamps.
The verifier `python3 tools/session/verify-loading-live.py --cycles 3` checks actual
compositor-frame visibility and handoff on the already-running desktop. Neither
command proves that a hardware display emitted light earlier in the SDDM-to-Wayland
handoff; the screenshot's blackout still needs a real login/video retest.
