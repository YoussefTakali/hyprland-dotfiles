# Earbud audio and battery verification

Bluetooth addresses below are examples. Use the address reported for your device.

## Redmi Buds 8 Pro recovery on Fedora 45

BlueZ 5.88 is installed and running on the Fedora machine with the Realtek
RTL8822CU adapter. The stale Linux bond at `02:00:00:00:00:03` exposed battery
and control services only. It was removed individually. Classic inquiry
completed at the controller but returned no earbuds, even with the case
flashing white in Classic-only mode.

Opening the Classic SDP channel directly at the previously observed audio
address `02:00:00:00:00:01` made BlueZ expose the correct device. Native Classic
pairing then discovered its Audio Sink UUID and PipeWire created a stereo output.
After restoring the original dual-mode BlueZ config and restarting Bluetooth,
the Classic bond persisted. An explicit A2DP reconnect restored the default
PipeWire output `bluez_output.B8_53_84_DD_74_4C.1` with profile `a2dp-sink`.
Playback was heard in both earbuds. Playback also returned automatically after
closing the case for ten seconds, reopening it, and taking the earbuds out.

### Fedora package update

If this machine is restored to the old Fedora 45 BlueZ 5.87 snapshot, reapply
the package update from Fedora's repositories:

```bash
sudo dnf upgrade bluez bluez-libs bluez-cups bluez-obexd
bluetoothctl --version
```

The tested version is 5.88. The Fedora transaction restarted Bluetooth.
The temporary [Classic-only test](BLUETOOTH-CLASSIC-TEST.md) was restored.

### Reconnect or pair again

If the existing bond needs to reconnect, wake the earbuds and run:

```bash
python3 tools/bluetooth/repair-earbud-audio.py --prefer-classic --device 02:00:00:00:00:01
```

If the audio bond is missing and Classic scanning does not find the buds, put
both earbuds in the case, leave the lid open and hold the button for two
seconds until the white light flashes. Run the direct pairing helper and
follow its prompt:

```bash
python3 tools/bluetooth/repair-earbud-audio.py --pair-classic --classic-address 02:00:00:00:00:01
```

Use the actual Classic address for a different pair of earbuds. The helper
opens the SDP channel using a Linux Bluetooth socket, checks that BlueZ
identifies the device as REDMI Buds 8 Pro, pairs if needed and verifies the
PipeWire output. If this specific control bond returns, add
`--forget-control 02:00:00:00:00:03` to the pairing command. That option removes
only the specified existing control-only bond after validating its identity
and audio UUIDs. The case's factory reset was skipped to keep its other saved
pairings.

[Xiaomi pairing instructions](https://www.mi.com/ng/support/faq/details/KA-666754/) ·
[Fedora BlueZ update](https://packages.fedoraproject.org/pkgs/bluez/bluez/fedora-45-updates.html) ·
[BlueZ report on direct Classic SDP discovery](https://github.com/bluez/bluez/issues/2700)

## Earlier discovery and connection attempts

An earlier live report contained two named REDMI records: public identity
02:00:00:00:00:02 connected with aggregate battery 90%, and random address
02:00:00:00:00:03 disconnected. Neither had a PipeWire output or Classic Audio Sink
service. The controller reported both BR/EDR and LE enabled. This does not prove a
driver failure, nor does a public identity address prove a Classic connection.

BlueZ's generic Connect succeeds if at least one profile connects. For dual-mode
devices, bonded/last-used bearer selection can reconnect the control link instead
of audio. This is a hypothesis to test, not a confirmed diagnosis of these buds.
Try the existing public identity with the bounded reconnect mode:

```bash
python3 tools/bluetooth/repair-earbud-audio.py --prefer-classic --device 02:00:00:00:00:02
```

This verifies disconnect before explicitly requesting `a2dp-sink`. In the installed
BlueZ 5.87 source, ConnectProfile selects BR/EDR directly; it does not require the
experimental PreferredBearer API. When available, that preference is also set and
read back to help later generic reconnects. No experimental daemon feature is
enabled and no pairing keys are deleted. If the audio service still does not appear,
it stops. Success requires a real PipeWire A2DP output and verified default routing.
A successfully changed preference can be reset with
`bluetoothctl bearer ADDRESS last-seen` on daemons supporting that property.

The supported model includes A2DP/HFP according to [Xiaomi's specifications](https://www.mi.com/sg/product/redmi-buds-8-pro/specs/).
For new-device pairing, Xiaomi specifies both buds in the case, lid open, and the
case button held for two seconds until white flashes. Their audio entry must be
found while pairing mode is active. A remembered/control-only entry is insufficient.

```bash
python3 tools/bluetooth/repair-earbud-audio.py --pair-classic
```

The repair refuses to pair arbitrary unnamed devices or guess an address from
manufacturer data. It requires one named candidate and checks its bearer or advertised audio service,
then verifies a
PipeWire output before switching audio. If no candidate appears, it reports failure
and saves the actual discovery output instead of installing unrelated codecs.

## Read actual connection and battery data

```bash
python3 tools/bluetooth/check-bluetooth-audio.py --match REDMI
```

This reads BlueZ device and Battery1 objects and matching PipeWire outputs. It shows
left/right/case levels and charging flags only when those components are actually
reported. An aggregate percentage is not duplicated across both earbuds. Missing
fields say not reported.

Current BlueZ documentation defines optional component battery objects, but their
availability is experimental/provider-dependent. Finding that API does not prove
this particular model or installed daemon exposes it. Xiaomi documents individual
battery information in its own mobile app; that is not a guarantee of equivalent
Linux reporting. No verified model-specific battery decoder has been installed.

## Optional digital audio test

```bash
python3 tools/bluetooth/check-bluetooth-audio.py --match REDMI --test-audio
```

Only after exactly one matching connected Bluetooth output exists, this plays a
quiet one-second left/right tone on that output and captures its digital monitor.
It reports measured samples/peak without recording a microphone. It does not claim
that monitor activity proves sound reached the physical earbuds. Reports and the
short local recording are under `~/.local/state/bluetooth-audio-check/`.

References: [BlueZ component battery fields](https://hadess.github.io/bluez/org.bluez.Battery.html),
[Xiaomi battery instructions](https://www.mi.com/ng/support/faq/details/KA-666754/),
[BlueZ A2DP connection](https://github.com/bluez/bluez/blob/master/doc/bluetoothctl.rst#connect).

Source: [BlueZ bearer selection and PreferredBearer](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst).

Implementation: [BlueZ 5.87 ConnectProfile](https://github.com/bluez/bluez/blob/5.87/src/device.c).

## Automatic reconnection verification

Keep the buds awake and launch once in the real desktop terminal:

```bash
python3 tools/bluetooth/repair-earbud-audio.py --reconnect-audio --cycles 3
```

The existing helper runs bounded disconnect/A2DP reconnect cycles, verifies an
actual PipeWire A2DP output and default routing each time, and pins the identified
device for later cycles. It stops on the first failure and saves a `.cycles.json`
report beside its log. Bluetooth info, cards/sinks, Bluetooth/WirePlumber logs and
read-only USB power state are captured. No bond removal, automatic pairing,
controller reset, driver unload or audio-service restart occurs in the loop.
No acoustic playback is claimed. `--device ADDRESS` resolves ambiguous devices;
addresses are never guessed from advertisements or altered byte values.

A restricted agent run was attempted on 2026-11-09. PipeWire preflight failed with
Operation not permitted / Connection refused, before any hardware cycle ran.
Mocked regression tests validate loop behavior, including first-success/second-
failure, but are not physical hardware results.

When no public/audio candidate is listed, reconnect mode now runs one automatic
20-second Classic discovery and retries selection once. Discovery cannot make the
earbuds physically enter pairing mode: for new-device discovery, both buds must
be in the open case and the case button held two seconds until white flashes.
If no candidate appears, it saves the discovery output and stops without changing
an unrelated device. Vendor UUIDs labeled Unknown are not themselves driver errors.

If the sole named random-address control link is still connected and no public/audio
candidate exists, the helper disconnects that link and verifies release before its
one discovery attempt. This can interrupt the battery/control connection. Pairing
records remain intact. The exact reason for a failed cycle is printed immediately.
