# Reversible Classic-only isolation test

The in-kernel btusb/btrtl driver supports RTL8822C USB and loads the matching
rtl8822cu firmware. The alternative Realtek driver repository documents support
only for kernels 2.6.32–5.3, so it is not a supported replacement for kernel 7.2.
[Alternative driver requirements](https://github.com/rtlwifi-linux/rtk_btusb_rtl8822c/blob/master/Readme.txt)

Latest 010101 run: BlueZ rejected optional PreferredBearer with UnknownProperty;
the helper then unnecessarily queried it for 15 seconds. That wait is removed.
The subsequent explicit A2DP attempt saw the public device removed and no audio
output. This is not enough evidence to attribute removal to the USB driver or to
identify which client initiated it. No root cause is claimed.

Instead of another generic reconnect loop, isolate transport selection using
BlueZ's supported ControllerMode=bredr. This restarts Bluetooth and makes all LE
connections unavailable until restored. Existing pairing keys are retained.
It is an optional diagnostic, not enabled automatically by either installer.

```bash
sudo python3 tools/bluetooth/classic-transport.py --apply
```

Put the buds into pairing mode, then use Blueman Search and Pair. A successful
result requires the earbuds to appear as a real audio output and survive a
reconnect. Mode configuration alone is not proof of working sound.

Restore the original configuration after the test:

```bash
sudo python3 tools/bluetooth/classic-transport.py --restore
```

The script stores its original config under /var/lib/hyprland-bluetooth-classic-test,
rolls back if restart fails, and refuses to overwrite later config edits on restore.
The config edit and restart rollback are regression tested using temporary files
and mocked systemctl. In the physical Fedora 45 test, Classic inquiry completed
with zero results. A direct SDP connection exposed the buds for Classic pairing.
The audio connection then worked after restoring dual mode. See
[Redmi recovery and verification](EARBUD-AUDIO.md#redmi-buds-8-pro-recovery-on-fedora-45).

The older installed 7.2.11 kernel currently lacks its NVIDIA module according to
modinfo, so no automatic kernel downgrade/reboot has been configured.
Cached Fedora package metadata offers the currently installed BlueZ build; a fresh
repository refresh was not performed here. No manual BlueZ source install was done.

[BlueZ controller-mode documentation](https://github.com/bluez/bluez/blob/5.87/src/main.conf)
