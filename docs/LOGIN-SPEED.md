# Login transition measurements and changes

On November 9, the SDDM journal and wallpaper command log gave these times
(seconds since boot):

| Event | Before missing-socket fix | After missing-socket fix |
| --- | ---: | ---: |
| SDDM starts user session | 41.840 | 430.191 |
| Hyprland process created | — | 430.580 |
| Wallpaper helper starts | 43.240 | 431.380 |
| Wallpaper command completes | 44.210 | 431.650 |
| Session start to image submission | 2.370 | 1.459 |
| Wallpaper helper duration | 0.970 | 0.270 |

These are process and command timestamps, not independently measured display
frames. The remaining visible blackout includes the X11-to-Wayland display
handoff and monitor resynchronization. A zero-time handoff is not promised.

The whole active Lua/legacy configuration verified in 42 ms. Its compatibility
log reported 24 files, 176 binds, 142 rules, 91 options and no problems. The
startup path, environment, session launcher, monitor rules, wallpaper helper,
SDDM theme and Xorg/NVIDIA logs were inspected. Configuration size alone does
not explain the remaining initialization interval.

Additional changes applied to the current desktop:

- The monitor's explicit 10-bit request was changed to 8-bit, retaining
  2560×1440 at 99.946 Hz. The greeter uses a 24-bit framebuffer (8 bits per
  channel); Hyprland now reports `XRGB8888`. The log had shown a failed XR30
  allocation and fallback while requesting 10-bit. That message does not imply
  that all 10-bit formats were unsupported: the desktop had used XBGR2101010.
- Automatic startup of the dropdown Kitty terminal was removed. Its existing
  Super+Shift+Enter binding still creates it on demand.
- Overview is started on demand with Super+A. Its wrapper probes IPC directly
  instead of relying on the incorrect `quickshell` process name (the executable
  here is `qs`). Readiness polling replaces its unconditional 600 ms wait.
- The Ubuntu-only `nm-tray` startup entry is disabled on this Fedora desktop.

The repository's generic monitor configuration already uses the default 8-bit
mode. The current machine's resolution and refresh are kept in its installed
monitor files, not copied into the generic configuration.

## Match the login screen's refresh rate

SDDM/Xorg selected `nvidia-auto-select`, while the desktop explicitly requested
the monitor's 100 Hz mode. The first EDID/preferred mode is 59.95 Hz; the greeter's
actual refresh was not read from its authenticated X server. Matching both
stacks' requested mode avoids this likely additional display-mode change.

The following root installer sets an X11 `DisplayCommand`, preserving the
existing `/etc/sddm/Xsetup` hook and the Jake theme:

```bash
sudo python3 installer/session/repair-login-speed.py --width 2560 --height 1440 --refresh 99.95
```

It creates `/usr/local/libexec/hyprland-sddm-display` and
`/etc/sddm/hyprland-display.json`, and sets `[X11] DisplayCommand` in
`/etc/sddm.conf`. It saves replaced files under `/var/backups/login-speed/` and
records newly created files in `created-files.json`. It does not restart SDDM;
the next login screen uses the setting. Administrator authentication is required.

The helper reads `xrandr --query`, selects the supported matching refresh only
when exactly one output is connected, and skips unsupported or already matched
modes. A failed hook never prevents the greeter from starting. It does not
disable connected outputs or add unadvertised modelines. For details of SDDM's
hook, see its [configuration documentation](https://github.com/sddm/sddm/blob/develop/data/man/sddm.conf.rst.in).

To undo the system change, restore `/etc/sddm.conf` from the printed backup.
Remove the newly created helper and display JSON if listed in `created-files.json`.
To undo the local display/startup edits, restore the corresponding files from
`~/.local/state/login-speed-backups/`.

## Verification

```bash
python3 tests/test_login_speed.py
python3 tests/test_session_integration.py
Hyprland --verify-config
hyprctl configerrors
```

The regression checks cover safe mode selection and cold/warm overview startup.
The desktop's live display format and refresh were verified after reload.
The improvement from the new color-depth and SDDM changes still requires a
subsequent login; it cannot be inferred from syntax checks or mocked tests.

The SDDM mode-matching change was successfully installed at 01:49 on November 9.
The live `/etc/sddm.conf` now points to the installed helper, and its settings
request 2560×1440 at 99.95 Hz. The system backup is
`/var/backups/login-speed/20261109-014946-102702`. Earlier login tests occurred
before this system change was authenticated/applied. The next greeter/login
cycle is the first test of the matched display mode.

## First measured login after SDDM mode matching

Xorg logged `Setting mode "HDMI-0: 2560x1440_100 ..."` at uptime
1130.350s, confirming the greeter actually selected 100 Hz. The subsequent
login started `start-hyprland` at 1146.670s, created Hyprland at 1147.030s,
started the wallpaper helper at 1147.850s and completed its image command at
1148.210s. Total: 1.540 seconds. The launcher accounts for about 360 ms,
compositor initialization before the helper for 820 ms, and wallpaper handling
for 360 ms. These are approximate process timings, not optical frame timings.

The display match did not eliminate the visible blackout and did not demonstrate
a material improvement over the previous 1.581-second login. Do not describe
this as a solved blackout or a 100 ms login. The configuration still reports no
parse problems. Repeating logout/login tests without a new substantive change
is unnecessary. Keeping the session running via the existing Super+L lock avoids
restarting the compositor; a fresh login has a different startup path.

## Startup pipeline optimization and 0.5-second target

The follow-up repository scan read 651 text files (about 2.15 MB), and checked
all 113 shell executable sections and 26 Python files at that snapshot. RofiEmoji
embeds non-shell data after an unconditional exit; that data is excluded from
shell syntax checking. The later added measurement helper also compiles.

New changes are installed in the active configuration as well as the repository:

- `StartupWallpaperCache.py` prepares a single-monitor, native-size QOI when
  changing wallpaper. Login selects it only if the source image, cache image
  and monitor configuration signatures still match. Missing or stale caches
  fall back to the source. Pillow is needed only to prepare the optional cache.
  Cache generation never runs on the login critical path.
- The Lua compatibility layer starts the wallpaper command first, then releases
  the other configured startup commands concurrently. Video wallpaper restoration
  also happens after the initial still submission. Without the startup helper,
  the existing individual command-launch behavior is retained.
- Fedora's `start-hyprland --no-nixgl` skips repeated version probes used by the
  [native launcher's Nix compatibility detection](https://github.com/hyprwm/Hyprland/blob/v0.57.1/start/src/helpers/Nix.cpp).
  This preserves the native watchdog and the stock login-shell/profile setup.
  It is installed with `repair-login-speed.py --fast-start` (plus the existing
  display width/height/refresh arguments). Nix builds are refused.
- The measured launcher records entry and post-profile times in
  `~/.local/state/session-startup/launcher.log`. Native timestamped startup
  logging is temporarily enabled and saved to `native-startup.log`; the wallpaper
  helper turns verbose logging off after submission.

On the running desktop, submitting the source 3840×2160 PNG took 147 ms and
the prepared 2560×1440 QOI took 58 ms. The complete warm wallpaper helper took
90 ms. Launching `/usr/bin/true` through the native launcher took 63 ms normally
and 2 ms with `--no-nixgl`. These are component measurements with warm system
caches, not complete fresh-login measurements. They do not establish that the
0.5-second target has been achieved.

The new SDDM wrapper was installed at 02:00 on November 9, with system backup
`/var/backups/login-speed/20261109-020034-903388`. The previous measured
1.540-second login predates these pipeline changes. After the next login, run:

```bash
python3 tools/session/measure-login.py
```

This reports the latest real session entry to initial image-command submission,
with a clear result against the 0.500-second target. It excludes unrelated manual
wallpaper refreshes. It does not measure the monitor's first visible frame.

Validation: `test_startup_pipeline.py` exercises the real Lua queue with mocked
external commands and shell quoting, and checks cache generation/invalidation.
The stock SDDM session wrapper and fast launcher were exercised with
`--path /usr/bin/true`, preserving login profiles without starting another desktop.

## Measured result after the pipeline optimization

The first measured login with the fast wrapper entered at uptime 1892.990s;
login profiles completed at 1893.090s, the wallpaper helper began at 1893.930s,
and its image command completed at 1894.160s. Total: **1.170 seconds**, compared
with 1.540 seconds before the pipeline changes (about 24% lower). The 0.500-second
command-submission target is **not met**. The helper itself took 230 ms on this
cold daemon start; the earlier 90 ms warm-helper result must not be substituted
for this complete login measurement.

Native timestamps expose three long gaps: 128.3 ms while enumerating GPUs and
checking built-in panels, 168.8 ms before the first connector scan result, and
126.4 ms fetching the connected HDMI connector again. Aquamarine 0.16.0's
`src/backend/drm/DRM.cpp` calls `drmModeGetConnector` in `gpuNumBuiltinPanels`,
`scanConnectors`, and `recheckOutputs`. The timestamps locate native backend
work rather than shell sleeps. They do not by themselves establish which kernel
operation accounts for every millisecond.

Other gaps include 79.7 ms around shader initialization and 62.7 ms around cursor
theme loading. `AQ_DRM_DEVICES` was honored for backend selection, but Aquamarine
still inspected the GPU list and built-in panels before applying that filter.
A non-master read-only connector query in the running desktop returned quickly;
it is not equivalent to startup while acquiring DRM master, and does not prove
that the expensive startup probe can simply be removed.

## Follow-up: boot trace and portable installation

The November 9 boot journal shows NVIDIA DRM initialized before SDDM started,
so deferring NVIDIA initialization until after authentication is not the cause
of this boot's transition. Aquamarine reports that its nested Wayland backend
cannot connect; it then initializes the DRM backend and NVIDIA renderer, and
the desktop starts. This is not proof that every machine's initialization is
healthy. `nvidia-powerd` also reports an unsupported system, independently of
the compositor startup. Do not disable it generically: supported laptops may
need it.

An earlier login repair forced a PCI address from the
original PC and NVIDIA libraries for every user, including non-NVIDIA systems.
Both installer entry points run the migration, which removes the exact old
managed block, preserves surrounding user settings, and regenerates GPU.conf
using the detected display GPU. Both installers explicitly request swww and
Pillow and check that swww exists. After a successful first wallpaper submission,
the helper can prepare a cache in the background for the next login. Missing or
invalid caches still fall back to the selected wallpaper. The measurement tool
now selects the most recent matching record when uptimes repeat across boots.

The current desktop's existing startup cache was rebuilt. No login or display
manager was restarted during this work. The video shows a blackout between SDDM
and the desktop; it does not show a legible error dialog. The first Wayland
surface cannot be displayed before Hyprland owns and initializes the display,
so the wallpaper helper cannot guarantee a seamless wait screen through the
X11-to-Wayland handoff or monitor mode switch. This remains unresolved and needs
an actual subsequent login and visual measurement; submission timestamps alone
are not evidence that the screen stayed lit.

## Photo waiting bridge

The optional `native/startup-wallpaper/build-startup-wallpaper.py` builds the layer-shell still
helper in the user's home. Both installers attempt to install its build tools,
build it, and prepare a wallpaper cache. If a monitor is unavailable during
installation the cache is prepared after the first successful wallpaper. A
single supported monitor receives a temporary still made from the selected
wallpaper with a "Starting your desktop..." badge; swww replaces it with the
unchanged wallpaper when ready. Missing tools, stale cache, multiple monitors,
or an unavailable helper use the existing swww path. Changing the wallpaper or
monitor configuration invalidates the cached image.

On November 9, the helper was built and the updated wallpaper scripts were
installed for the current user (the previous scripts are backed up under
`~/.local/state/desktop-login-backups/`). A test in the existing Wayland session
submitted its surface in about 10 ms. This warm in-session test does not measure
the earlier greeter-to-compositor transition, and a fresh login is required to
assess whether the video-recorded blackout is improved. The bridge cannot draw
before Hyprland has a working display.


## First login with the waiting bridge

The 19:42 login entered the session at uptime 2246.99 s, started the
wallpaper helper at 2247.93 s and submitted the bridge at 2248.07 s.
The first image submission took 1.08 s from session entry, compared with
1.53 s in the preceding recorded login. The helper portion fell from 0.46 s
to 0.14 s. The regular wallpaper daemon then submitted its image at 2248.22 s.
These are software timestamps, not measurements of visible monitor frames.
The GPU repair was also applied to the current account with a backup in
`~/.local/state/desktop-login-backups/`.

## First installation audit

Both `./setup` (via `installer/backend.sh`) and `./install.sh` copy the
startup configuration, call the portable GPU repair and attempt to build the
waiting-image helper. A new single-monitor install with the bundled preferred,
scale-1 rule now prepares a provisional image from the kernel connector modes
when Hyprland is not running. The native client checks the actual output size;
if it does not match, swww paints the regular image and the cache is rebuilt
in the running session. Multi-monitor or custom configurations remain on the
safe source-image path until the compositor can report its actual output.

The graphical backend now reports failures while copying the configuration,
configuring the GPU or installing the wallpaper instead of reporting success
with those steps incomplete. Regression checks exercise the provisional cache,
the normal handoff and the helper-failure fallback. The real display handoff
still requires optical measurement: a Wayland client cannot draw before the
compositor initializes its output.

## Start applications while the waiting image is displayed

The startup queue now starts the wallpaper helper in the background and waits
for its first successful still submission (or a bounded failure/timeout), then
releases other startup applications while the regular wallpaper daemon warms.
Video wallpaper restoration still waits for the still helper to finish, to avoid
racing the regular wallpaper. The installed scripts and repository match; the
Lua regression test checks the application/daemon/video ordering. A new login
is needed to measure the real effect; this change cannot make the compositor
initialize before it owns the display.

The existing experimental Aquamarine connector-cache candidate passed the
isolated C++ fallback tests on November 9. This does not establish its behavior
on a real DRM handoff, so it remains disabled; the packaged backend is used.

## November 9 full integration review

See [the current investigation report](TESTING.md) and
[desktop documentation](README.md). Both installer entry points now use one
backend and a separate portable display-manager session. PCI-first discovery,
Secure Boot ordering/key checks, multi-GPU fallback and the animated wallpaper
indicator are integrated. The optional Aquamarine backend patch remains disabled.

The complete supplied video has approximately 5.42 seconds of visible blackout.
It cannot be conclusively matched to the saved boot identity. The last software
measurement remains 1.080 seconds to image submission and predates these changes.
Neither metric proves a post-change optical result. No instant-login or solved
blackout claim is made.

## User retest: no visible improvement

At the 21:21 login the user reported that nothing visibly changed. The new software
measurement is 1.020 seconds to submission, only 60 ms less than the preceding
1.080 seconds. This did not satisfy the visual goal. A follow-up corrects the
premature 50 ms loading-client termination and adds compositor presentation
feedback. It remains unverified in a subsequent real login. See the follow-up
section of [the test guide](TESTING.md).
