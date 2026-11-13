#!/usr/bin/env python3
"""Read PCI hardware independently of loaded DRM drivers. No device opens."""
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

VENDORS = {"0x10de": "nvidia", "0x1002": "amd", "0x8086": "intel"}


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def inventory(root=Path("/sys")):
    devices = {}
    for dev in sorted((root / "bus/pci/devices").glob("*")):
        if not read(dev / "class").startswith("0x03"):
            continue
        vendor = VENDORS.get(read(dev / "vendor"))
        if vendor:
            devices[dev.name] = dict(pci=dev.name, vendor=vendor, device=read(dev / "device"),
                                     subsystem_vendor=read(dev / "subsystem_vendor"), subsystem_device=read(dev / "subsystem_device"),
                                     driver=(dev / "driver").resolve().name if (dev / "driver").exists() else "",
                                     boot=read(dev / "boot_vga") == "1", cards=[], render="", connected=[])
    for card in sorted((root / "class/drm").glob("card*")):
        if not re.fullmatch(r"card\d+", card.name):
            continue
        dev = devices.get((card / "device").resolve().name)
        if dev is None:
            continue
        dev["cards"].append("/dev/dri/" + card.name)
        renders = sorted((card / "device/drm").glob("renderD*"))
        dev["render"] = "/dev/dri/" + renders[0].name if renders else ""
        dev["connected"].extend(p.parent.name for p in card.glob(card.name + "-*/status") if read(p) == "connected")
    return list(devices.values())


def command(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def facts(devices, root=Path("/sys")):
    vendors = list(dict.fromkeys(d["vendor"] for d in devices))
    mode = ("hybrid-nvidia" if "nvidia" in vendors and len(vendors) > 1 else
            "hybrid-amd" if "intel" in vendors and "amd" in vendors else
            vendors[0] if len(vendors) == 1 else "unknown")
    connected = [d for d in devices if d["connected"]]
    display = connected[0]["vendor"] if len(connected) == 1 else ""
    if not connected:
        boot = [d for d in devices if d["boot"]]
        display = boot[0]["vendor"] if len(boot) == 1 else ""
    state = command("mokutil", "--sb-state")
    result = dict(MODE=mode, GPUS=" ".join(vendors), DISPLAY_GPU=display,
                  IGPU="intel" if "intel" in vendors else "amd" if "amd" in vendors and "nvidia" in vendors else "",
                  DGPU="nvidia" if mode == "hybrid-nvidia" else "amd" if mode == "hybrid-amd" else "",
                  NVIDIA_DRIVER=read(root / "module/nvidia/version"),
                  NVIDIA_OPEN="1" if "MIT" in command("modinfo", "-F", "license", "nvidia") else "0",
                  NVIDIA_ARCH="unknown", SECURE_BOOT="1" if "enabled" in state else "0" if "disabled" in state or not (root / "firmware/efi").exists() else "?")
    for vendor in vendors:
        dev = next((d for d in connected if d["vendor"] == vendor), next(d for d in devices if d["vendor"] == vendor))
        if vendor == "nvidia" and re.fullmatch(r"0x[0-9a-fA-F]{4}", dev["device"]):
            result["NVIDIA_ARCH"] = "turing+" if int(dev["device"], 16) >= 0x1e00 else "legacy"
        prefix = vendor.upper()
        result[prefix + "_PCI"] = dev["pci"]
        result[prefix + "_RENDER"] = dev["render"]
        # PCI IDs are not chronological. Let libva detect its Intel driver.
        result[prefix + "_VA"] = {"amd": "radeonsi", "nvidia": "nvidia", "intel": ""}[vendor]
    return result


if __name__ == "__main__":
    # GPU_SYSFS_ROOT points directly at sysfs; upstream's fixture points at its parent.
    fixture = os.environ.get("GPUINFO_SYSROOT")
    root = Path(os.environ.get("GPU_SYSFS_ROOT") or (Path(fixture) / "sys" if fixture else "/sys"))
    devices = inventory(root)
    if sys.argv[1:] == ["--json"]:
        print(json.dumps({"devices": devices, "facts": facts(devices, root)}, indent=2))
    else:
        for key, value in facts(devices, root).items():
            print(key + "=" + shlex.quote(value))
