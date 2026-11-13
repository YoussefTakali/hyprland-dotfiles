# Bluetooth interface

The Waybar button and application-menu entry open Fedora's maintained
`blueman-manager` with two scoped service-menu patches. `Bluetooth.sh` starts its pairing-agent applet if needed and
closes superseded custom wrappers. Opening the window does not reset the adapter.
The custom BluetoothManager.py has been removed; BluetoothState.py supports
read-only diagnostics and regression checks.

```bash
bash ~/.config/hypr/UserScripts/Bluetooth.sh
```

Use Search to discover devices; right-click a device for Pair, Connect, Disconnect,
or Remove. Two equal names can represent different Bluetooth addresses or bearers.
Do not delete bonds solely because their names match. A Connected label proves a
Bluetooth link, not an audio output. [Audio verification](EARBUD-AUDIO.md).

Launcher logs: `~/.local/state/bluetooth-menu/blueman.log` and `applet.log`.
BlueZ can detect remote power-off only after controller link-loss detection.
A different interface cannot eliminate that delay or repair missing audio profiles.
Live GUI and physical reconnect behavior still require a desktop check.

References: [Fedora Blueman package](https://packages.fedoraproject.org/pkgs/blueman/blueman/),
[Blueman source](https://github.com/blueman-project/blueman),
[BlueZ Device API](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst).

## Installed-source audit and scoped patches

`config/hypr/UserScripts/BluemanFixes.py` uses Fedora's actual installed source.
It fixes two exact patterns and skips changed upstream methods on future updates:

- `Services.on_request_menu_items`: callbacks inside loops did not bind their
  service and port. With multiple profiles, clicking the first item could act on
  the final profile. Regression tests reproduce this in the installed method,
  then verify both connect and disconnect target the clicked service after patching.
- `ManagerDeviceMenu.generate`: generic Disconnect was hidden when a connected
  device's UUIDs did not match Blueman's service list. A connected link now always
  gets Disconnect, including battery/control links.

No system package files are edited. Quit the current manager and reopen to load:

```bash
bash ~/.config/hypr/UserScripts/Bluetooth.sh --restart-ui
```

This restarts only the Bluetooth window, not the radio or audio services. Existing
connections and pairing records are left intact. `--loglevel info` records actual
service results in `~/.local/state/bluetooth-menu/blueman.log`.

These changes address UI actions. They do not establish that pairing, sound, or
physical power-off detection is repaired. [Full error audit](BLUETOOTH-ERRORS.md).
