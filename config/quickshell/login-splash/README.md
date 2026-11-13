# Shared Jake loading screen

`JakeLoadingScene.qml` supplies the same scene to SDDM and the desktop loader.
The Login button and Enter display it before submitting authentication. Failed
authentication restores the login form through the existing failure handler.

The installer uses the Astronaut poster for the initial handoff. The login theme
chooser can export `transition.png` to match the selected scene exactly.
When that frame is available, the native bridge uses its pixels without a spinner. The
wallpaper helper waits for the desktop overlay to render before replacing the
underlying frame. The desktop overlay exits with one 150 ms fade when the
wallpaper and Waybar are ready. There is no additional minimum display time.

The animation may pause while the compositor changes sessions. A real login
is required to verify the complete handoff on the monitor.

Artwork comes from the installed sddm-astronaut-theme.
Upstream theme https://github.com/Keyitdev/sddm-astronaut-theme
Upstream artwork credit https://motionbgs.com/jake-the-dog
The upstream theme license is included as LICENSE.sddm-theme.
