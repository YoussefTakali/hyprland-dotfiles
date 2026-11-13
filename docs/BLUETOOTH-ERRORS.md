# Bluetooth error audit — 2026-11-09

Bluetooth addresses below are examples. Use the address reported for your device.

Installed versions: Blueman 2.4.6, BlueZ 5.87 plus Fedora git snapshot,
PipeWire 1.6.11, WirePlumber 0.5.19, kernel 7.2.15-300.fc45.
Read from installed Python source, kernel headers, journal, and BlueZ 5.87 source.
The Fedora git snapshot may differ from the upstream tag; kernel upstream v7.2
provides context, not an assertion that every Fedora line is identical.

| Evidence | Meaning and status |
| --- | --- |
| Service-menu loop callbacks capture `service`/`instance` late | Reproduced against installed Blueman: first profile invokes final profile. Local patch binds each target and port; regression tested. |
| Generic Disconnect requires matching advertised services | Confirmed in installed menu code. Local patch always exposes Disconnect for connected links. GUI validation pending. |
| `GLib.MAXINT` in synchronous `Base.get`/`get_properties` and action timeouts | Unbounded property reads can stall the UI when the bus stalls; asynchronous actions can stay pending a long time. No profiling trace proves this caused the user's freezes; not patched speculatively. |
| Kernel: `ignoring IRK with invalid identity address` at 23:02 | Identity-key/address validation failed. This can affect address resolution, but the message does not identify which earbud entry caused it. Raw pairing keys were not accessed or changed. Unresolved. |
| BlueZ: public 02:00:00:00:00:02 accept-list removal rejected with `Invalid Parameters (0x0d)` at 00:13 | Kernel management operation failed. This is not evidence that RemoveDevice deleted a bond, and does not by itself prove broken firmware. Unresolved. |
| BlueZ: `More than one BATT service exists` | The battery plugin handles its first Battery service and skips additional ones. Explains limited battery export, not a demonstrated cause of missing A2DP. Component labels still cannot be guessed. |
| BlueZ: `GAS PPCP: Invalid Connection Parameters values` | The peer's proposed LE parameters failed validation; BlueZ declines to persist them. Not by itself evidence of a fatal audio failure. |
| `Host is down (112)`, Page Timeout, Authentication Failed, pairing Timeout 0x08 | Discovery/pairing/connection genuinely failed. A UI rewrite or repeated audio-service restart cannot establish a repair. Need a fresh attempt with the exact address and controller/profile trace. |
| WirePlumber `wp_properties_get: self != NULL`, destroyed nodes/links | Actual audio-session warnings; some coincide with the earlier restart. No trace yet ties them to an earbud audio card. Restarting repeatedly would mask the evidence. |
| Latest report: two names, no Audio Sink UUID and no PipeWire output | Both Bluetooth identities were present, but neither had verified audio. Connected/battery status is insufficient. Public address does not prove Classic transport. |
| RTL8822CU firmware loads successfully; both BR/EDR and LE enabled | No missing-firmware error found. No evidence justifies replacing the driver or disabling LE globally. |

Collect current state and bounded logs in the desktop terminal after reproducing:

```bash
python3 tools/bluetooth/check-bluetooth-audio.py --match REDMI --logs
```

This extends the existing diagnostic; it does not reset the adapter or read pairing
keys. Previous reports predate the latest attempts. The agent environment cannot
access the live Bluetooth/audio buses, so no successful physical reconnect is claimed.

Sources:
- Installed `/usr/lib/python3.15/site-packages/blueman/plugins/manager/Services.py`
- Installed `/usr/lib/python3.15/site-packages/blueman/gui/manager/ManagerDeviceMenu.py`
- [Blueman menu source](https://github.com/blueman-project/blueman/blob/2.4.6/blueman/gui/manager/ManagerDeviceMenu.py)
- [BlueZ battery handling](https://github.com/bluez/bluez/blob/5.87/profiles/battery/battery.c)
- [BlueZ GAP validation](https://github.com/bluez/bluez/blob/5.87/profiles/gap/gas.c)
- [BlueZ accept-list operation](https://github.com/bluez/bluez/blob/5.87/src/adapter.c)
- [Linux identity validation](https://github.com/torvalds/linux/blob/v7.2/net/bluetooth/mgmt.c)

## Driver/reconnection follow-up

The latest manager log resolves REDMI to 02:00:00:00:00:01 and still exposes only
GAP/GATT/Battery/Fast Pair/vendor services, not Audio Sink. The earlier identity
02:00:00:00:00:02 must not be assumed to be the sole current target. The kernel's
identity warning recurred at 00:38:46. Manager RemoveDevice also reported NotReady
while the adapter was being toggled. Neither event establishes a completed repair.

Kernel btrtl's RTL8822C USB entry matches the observed 0x8822 / revision 0x000c /
HCI 0x0a combination and selects rtl8822cu firmware/config, both loaded in the
journal. Realtek firmware package 20261019 is installed. PipeWire's bluez plugin and
SBC/AAC/etc. codecs are present; endpoints were registered. Adding another generic
sound driver is not supported by this evidence.

USB runtime PM was `auto` / `suspended` when sampled. That is a power state, not
proof of a resume failure. No autosuspend setting was changed or claimed repaired.
A transport trace during real reconnect is required before applying a driver quirk.
[Realtek driver source](https://github.com/torvalds/linux/blob/v7.2/drivers/bluetooth/btrtl.c)

The repair helper now supports `--reconnect-audio --cycles 3`; see
[automated verification](EARBUD-AUDIO.md). Its actual agent invocation stopped at
PipeWire access preflight: no physical cycles ran. Eight mocked reconnect/loop
checks pass. This limitation remains unresolved until the runner executes in the
real desktop session.

## Actual desktop cycle attempts at 00:50

Three reports now exist from actual desktop runs (005008, 005014, 005019). Each
stopped at device selection on cycle 1: BlueZ listed only named random-address
02:00:00:00:00:03 and an unrelated unnamed advertiser. No A2DP connect request was
made in those runs. USB power was active, not suspended. PipeWire cards/sinks
contained only ALSA HDMI/USB/integrated devices, with no bluez card.

The helper's earlier "No unique public earbud entry" message conflated zero
candidates with multiple candidates. It now distinguishes them and automatically
performs one bounded Classic scan when there is no candidate, then retries selection
once. It still refuses to pair an unrelated unnamed device or guess a MAC from
manufacturer bytes. A missing optional PreferredBearer property no longer aborts
the pairing helper before it can attempt the explicit audio profile.

`UUID: Unknown` for vendor/service UUIDs is a missing human-readable service name;
it is not proof of an unknown audio driver. The relevant audio UUID 0x110b is absent
from the captured entry. Renaming that entry or labeling vendor UUIDs as audio would
not make a sound card appear.

## Actual Classic discovery at 00:54

The 005415 report confirms `SetDiscoveryFilter success` and `Discovery started`,
followed by no new audio candidate. The random REDMI link remained Connected yes
before and after discovery; the adapter was active. This rules out claiming that
the scan command failed or the USB adapter was asleep during that sample. It does
not distinguish peer discoverability from controller/firmware failure.

Reconnect recovery now releases a single explicitly named, connected random entry
without audio services before discovery, verifies it disconnected, then scans once.
This tests whether the existing control connection prevents the peer from exposing
its audio entry; it is not a confirmed root cause. Multiple matching links remain
an error. No bonds, keys, drivers or services are reset. Exact cycle errors now
appear directly in terminal output instead of only in the JSON report.
