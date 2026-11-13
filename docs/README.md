# Desktop documentation

- [Graphics and rendering profiles](GPU-PERFORMANCE.md)
- [Login startup and measurements](LOGIN-SPEED.md)
- [SDDM and the loading scene](JAKE-SPLASH.md)
- [Optional Aquamarine startup experiment](FAST-START-TRIAL.md)
- [Liquid Glass Waybar styles](LIQUID-GLASS.md)
- [Bluetooth manager](BLUETOOTH.md), [earbud audio](EARBUD-AUDIO.md), and [Bluetooth diagnostics](BLUETOOTH-ERRORS.md)
- [Middle-click paste](MOUSE-PASTE.md)
- [Running the regression suite](TESTING.md)

Run repository commands from the project root. The normal desktop entry points
are in `config/`. Both installers call `installer/backend.sh`, which uses the
session helpers in `installer/session/` and the optional wallpaper renderer in
`native/startup-wallpaper/`. The Aquamarine experiment requires explicit setup
and lives in `experiments/aquamarine-startup/`.

`tools/` contains separately invoked diagnostics and maintenance commands. The
Bluetooth Classic transport experiment can change system configuration. Its
apply and restore commands are described in the [transport guide](BLUETOOTH-CLASSIC-TEST.md).
