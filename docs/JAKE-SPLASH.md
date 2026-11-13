# Jake splash and repeated file-manager windows

The real login at 13:13 on 2026-11-10 launched Quickshell successfully but the
user reported the black transition remained. The earlier preview did not verify
the actual login transition. The old log contained configuration-load messages,
without evidence of when the splash became visible.

The startup bridge now uses Jake artwork instead of the desktop photo. The
animated splash starts alongside that bridge, holds for 2.8 seconds after its
first render tick (now shortened to two seconds), then fades once wallpaper and Waybar are ready. It has a
seven-second timeout. The timestamped log records surface visibility, first
render tick and fade at `~/.local/state/session-startup/jake-splash.log`.
These events do not prove optical presentation or eliminate display blanking
before the compositor starts.

Super+E invokes `$files --new-window`; the bundled file manager is Nautilus.
Two consecutive live launches were verified to create two separate windows.

Run Desktop Setup or `./install.sh --sddm` to install or upgrade the
shared scene and select the dotfiles session through the normal installer.
The installer prepares the desktop wallpaper cache from the available artwork.

Validation: startup-pipeline regression checks passed, Hyprland reported no
configuration errors, and a captured live preview showed the revised splash.
A fresh real login is still required to verify the user's reported transition.

## Greeter handoff change

After researching upstream SDDM and testing the actual Jake greeter inside a
nested Hyprland window, `repair-greeter-handoff.py` was applied on this computer.
It sets `DisplayServer=wayland` in `/etc/sddm.conf` (which takes precedence over
conf.d), with `start-hyprland --no-nixgl` as the greeter compositor. It preserves
the theme, authentication settings and user-session launcher. The generated
greeter config matches the active monitor modes, French AZERTY keyboard layout,
and dynamically selects the display-connected GPU. Software cursors address the
earlier missing-cursor problem. Xwayland and greeter animations are disabled.
Both compositor configurations now use Jake lavender for the initial clear.

This replaces the proprietary-Xorg-to-Hyprland transition with a Hyprland-to-Hyprland handoff. It still uses separate greeter and user compositor sessions; the
effect on physical display blanking remains unverified until a real reboot and
login. A nested preview verifies theme rendering, not DRM/VT handoff.

SDDM has no live reload on this machine. **Reboot when ready** to activate the
new greeter backend. No service was restarted and no session was terminated.

Applied backup:
`/var/backups/greeter-handoff/<backup>`

Restore the previous backend if needed, from a terminal or Ctrl+Alt+F3:

```bash
sudo python3 installer/session/repair-greeter-handoff.py --restore /var/backups/greeter-handoff/<backup>
```

On another computer, generate settings from that computer's active desktop:

```bash
python3 installer/session/repair-greeter-handoff.py
pkexec /usr/bin/python3 "$PWD/installer/session/repair-greeter-handoff.py" --apply "$HOME/.local/state/greeter-handoff/candidate"
```

The standard desktop-login repair preserves this backend once configured.

Primary sources: [SDDM configuration](https://github.com/sddm/sddm/blob/develop/data/man/sddm.conf.rst.in),
[SDDM VT/session handling](https://github.com/sddm/sddm/blob/develop/src/daemon/Display.cpp),
[Omarchy's Hyprland greeter configuration](https://github.com/omacom/omarchy/blob/master/default/sddm/hyprland.lua).

## Follow-up after real login

The user confirmed the handoff improvement worked. The 14:11:41 login log
records the splash's first render tick at 41.676 and fade at 44.477 without
Hyprland configuration errors. Follow-up refinements shorten the minimum hold
to two seconds and use a 450 ms fade.

The splash's Qt process no longer probes desktop portals. The startup queue
prepares the D-Bus environment and graphical-session target after the first
wallpaper submission, before launching other toolkit applications. This
addresses the logged early portal dependency failure; the portal services
were already healthy after the original race recovered.

SwayNC now starts through `StartSwaync.py` and its user-service drop-in. It
uses the built-in GTK4 theme for the notification process while preserving
the existing notification CSS, and omits the backlight widget on computers
without a brightness device. A live restart no longer emitted the Flat Remix
CSS parser errors or missing-backlight errors.

`repair-greeter-handoff.py --fix-locale` installs a scoped UTF-8 environment
for SDDM. It takes effect on the next daemon start and does not restart SDDM.

The custom Super + left drag change was reverted at the user's request.
The original native move-window binding is restored; Jake changes remain.

## Early solid-color screen

The next real login showed the lavender compositor clear before Quickshell's
first render tick. Hyprland's renderer supports its own startup wallpaper,
loaded before client applications. Jake is now installed as
`/usr/share/hypr/wall0.png`, and the greeter and desktop select wallpaper 0
with the built-in background enabled. The fallback clear uses a dark color
from the artwork. The animated loading screen follows this early Jake image.

The original system asset and greeter configuration are backed up under
`/var/backups/jake-backdrop/20261110-144006-006418`. A nested compositor test
rendered Jake with no splash client running and reported no config errors.
The next real login is required to verify the complete physical handoff.

`repair-greeter-handoff.py --jake-backdrop` reapplies the system image and
greeter settings. Both the greeter installation and desktop-login repair call
this operation. Hyprland package updates can replace the system image, so the
repair operation can be reapplied after an update.

Renderer source for the installed compositor revision is available at
https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/src/render/Renderer.cpp

## Shared loading scene from Login

The current implementation starts `JakeLoadingScene.qml` from the existing
SDDM `triggerLogin()` function, before `sddm.login()` is called. The existing
failed-login handler restores the form. The same component is used by the
desktop overlay, and its rendered frame is used for the built-in wallpaper and
native bridge. The separate bridge badge and spinner are disabled for this
shared frame. The desktop overlay has no two-second minimum hold.

The protected theme files and previous image are backed up under
`/var/backups/jake-backdrop/20261110-145205-966103`. The repair and installer
scripts include the component, image, and idempotent theme hooks.

Validation exercised the real Login handler and failed-login signal in SDDM
test mode. The first-surface pixels match the shared frame exactly. The desktop
overlay waits for readiness and then performs a single fade. Full physical
handoff still needs a real login test. Animation can pause during the session
switch because the compositor temporarily displays the matching saved frame.
