# GPU and responsiveness repair

Applied 2026-11-08 to the installed configuration and both local dotfile repositories.

## Hardware evidence

- NVIDIA GeForce RTX 3060 Ti at `0000:01:00.0`, open NVIDIA driver `615.78.08`.
- AMD Cezanne integrated graphics at `0000:0d:00.0`, using `amdgpu`.
- Monitor connected to NVIDIA `HDMI-A-2`; AMD connectors are disconnected.
- Current Hyprland log reports `Renderer: NVIDIA GeForce RTX 3060 Ti/PCIe/SSE2`
  and explicit sync support. NVIDIA DRM `modeset` and `fbdev` are both enabled.
- Kernel module and installed NVIDIA userspace package versions match. No NVIDIA
  Xid GPU fault was found in the inspected boot journal.
- `nvidia-smi` cannot access the GPU in the restricted agent environment. This does
  not establish a driver failure in the desktop. Runtime metrics and video decoding
  still need to be checked in the real session.

## Changes

- Waybar's GPU tooltip contained a literal `NVIDIA RTX 4060`. It now reads the model
  and metrics from the selected display-connected GPU. NVIDIA queries have a two-second
  timeout, sleeping GPUs are not queried, and failures produce `unavailable` instead
  of invented readings. JSON is serialized correctly, including tooltip newlines.
- Removed the fixed PCI address in `hyprland.lua`. `GpuPrimary.sh` resolves the sole
  connected GPU from sysfs each launch. Multiple active cards keep compositor defaults.
- `GpuInfo.sh` and `GpuConfig.sh` select the connected display's vendor, avoiding the
  assumption that every AMD+NVIDIA machine renders on its integrated GPU. Generic
  default environment files no longer force NVIDIA settings on AMD/Intel machines.
- Disabled the looping border-angle animation, which continuously requested redraws.
- Hardware cursors use Hyprland's automatic mode instead of forced software cursors.
- Balanced mode reduces blur from size 6 / two passes to size 4 / one pass and enables
  variable frame rendering. It preserves normal animations and shadows.
- Fixed `SessionInit.sh` so unloaded units during `reset-failed` cannot abort portal
  startup. Errors from the actual start/restart still stop the helper.

## Activate and check

Run in your desktop terminal:

```bash
bash ~/.config/hypr/scripts/SessionInit.sh --restart
bash tools/diagnostics/check-desktop.sh
```

The config watcher handles live configuration changes. Waybar runs the new metrics
script at its next polling interval. Log out and back in for a clean session with
the new GPU environment. Capture must still be tested interactively in Discord.

For maximum responsiveness, disabling blur, shadows, and animations:

```bash
bash ~/.config/hypr/UserScripts/PerformanceMode.sh fast
```

Restore the lighter balanced effects, or the underlying original effect settings:

```bash
bash ~/.config/hypr/UserScripts/PerformanceMode.sh balanced
bash ~/.config/hypr/UserScripts/PerformanceMode.sh default
```

`default` resets only the performance profile overrides. The separate cursor and
looping-border corrections remain. File backups are in
`~/.local/state/gpu-performance-backups/`.

## Validation and limits

`Hyprland --verify-config` reports `config ok`. Shell syntax and Git whitespace
checks passed. `python3 tests/test_session_integration.py` covers the reported unloaded-unit
failure, GPU environment generation for NVIDIA/AMD/Intel displays, valid metrics
JSON, and query timeout handling. Bus and GPU device access are restricted here;
actual capture and FPS/latency measurements were not performed. No quantified speed
improvement is claimed.

Reviewed the [Hyprland performance guidance](https://wiki.hypr.land/configuring/extra/performance/),
[NVIDIA setup](https://wiki.hypr.land/0.55.0/Nvidia/), and
[NVIDIA VA-API documentation](https://github.com/elFarto/nvidia-vaapi-driver).
The display already uses integer scaling, the NVIDIA driver is loaded, and memory
has ample headroom. Driver replacement, disabling security, forcing maximum GPU
clocks, changing CPU governor, and network/sysctl tuning were not justified by the
evidence. VA-API being installed does not prove each app uses accelerated video;
`check-desktop.sh` gives the runtime graphics/session information for follow-up.

## Follow-up portability review

The [test guide](TESTING.md) supersedes the earlier generation and
single-device selection assumptions. Hardware is now read from PCI independently
of driver availability. Runtime selection retains other DRM cards for fallback
and monitor hotplug, honors explicit user selection and leaves multi-display
ownership to the compositor. Mixed vendors retain GLVND/libva auto-detection;
custom GPU.conf is preserved. Both installers use the same support-table-validated
NVIDIA and Secure Boot setup. No PCI address is installed as a universal setting.

Performance.conf is applied after WaybarGlass.conf so explicit fast mode can
actually disable blur. Real FPS/capture and post-change login verification remain
outstanding.
