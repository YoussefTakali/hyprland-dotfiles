#!/usr/bin/env python3
"""Shared Fedora driver setup. --check is read-only; --install uses sudo.

Preserve loaded NVIDIA stacks; match a new RPM driver against NVIDIA's exact
supported PCI IDs, never a numeric-ID age guess. Do not unload a running driver.
"""
import argparse
import getpass
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("gpu_detect", REPO / "config/hypr/scripts/GpuDetect.py")
gpu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu)


def run(args, **kwargs):
    return subprocess.run(args, text=True, check=True, **kwargs)


def output(*args):
    return run(list(args), capture_output=True, timeout=30).stdout.strip()


def installed_akmod():
    result = subprocess.run(["rpm", "-qa", "--qf", "%{NAME}\n", "akmod-nvidia*"],
                            text=True, capture_output=True, timeout=10)
    return sorted(set(result.stdout.splitlines()))


def supported_ids(document):
    # Legacy tables in the same README are explicitly NOT supported by this release.
    current = document.split("Current NVIDIA GPUs", 1)
    if len(current) != 2 or "</tbody>" not in current[1]:
        raise ValueError("NVIDIA support table format changed; refusing to guess a driver")
    return set(re.findall(r'<tr\s+id="devid([0-9a-fA-F]{4})(?:_[^"]*)?"', current[1].split("</tbody>", 1)[0]))


def supports(document, devices):
    supported_ids(document)  # Validate the table before consuming entries.
    table = document.split("Current NVIDIA GPUs", 1)[1].split("</tbody>", 1)[0]
    # Keep the parser case-insensitive without assuming that PCI IDs encode age.
    products = set(re.findall(r'<tr\s+id="devid([0-9a-f_]+)"', table, re.I))
    products = {item.upper() for item in products}
    for dev in devices:
        if dev["vendor"] != "nvidia":
            continue
        number = dev["device"].removeprefix("0x").upper()
        subsystem = number + "_" + dev.get("subsystem_vendor", "").removeprefix("0x").upper() + "_" + dev.get("subsystem_device", "").removeprefix("0x").upper()
        if number not in products and subsystem not in products:
            return False
    return True


def choose_driver(devices):
    for package in ("akmod-nvidia", "akmod-nvidia-580xx"):
        try:
            versions = output("dnf", "repoquery", "--available", "--latest-limit=1", "--qf", "%{version}", package).splitlines()
            version = next(v.strip() for v in versions if re.fullmatch(r"\d+\.\d+(?:\.\d+)?", v.strip()))
            document = output("curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "20",
                              f"https://download.nvidia.com/XFree86/Linux-x86_64/{version}/README/supportedchips.html")
            if supports(document, devices):
                return package, version
        except (OSError, ValueError, StopIteration, subprocess.SubprocessError):
            continue
    raise RuntimeError("No available modern/580 NVIDIA branch could be verified for every NVIDIA PCI ID. "
                       "No driver was replaced. Check RPM Fusion/NVIDIA support, or use --no-drivers with an existing working stack.")


def secure_boot_key(password):
    cert = "/etc/pki/akmods/certs/public_key.der"
    exists = subprocess.run(["sudo", "test", "-f", cert]).returncode == 0
    if not exists:
        run(["sudo", "kmodgenca", "-a"])
    if subprocess.run(["sudo", "mokutil", "--test-key", cert], stdout=subprocess.DEVNULL).returncode == 0:
        return False
    if not password:
        if not os.isatty(0):
            raise RuntimeError("Secure Boot needs a one-time MOK password. Supply it in Desktop Setup or run the terminal installer interactively.")
        password = getpass.getpass("One-time Secure Boot MOK password (8–16 ASCII letters/digits): ")
        if password != getpass.getpass("Confirm MOK password: "):
            raise RuntimeError("MOK passwords did not match")
    if not re.fullmatch(r"[A-Za-z0-9]{8,16}", password):
        raise RuntimeError("Use 8–16 ASCII letters/digits for the firmware MOK password (QWERTY keyboard).")
    # No password in argv, logs, shell tracing or world-readable temporary files.
    hashed = run(["openssl", "passwd", "-6", "-stdin"], input=password + "\n", capture_output=True).stdout
    with tempfile.NamedTemporaryFile(mode="w", prefix="desktop-mok-", encoding="ascii") as file:
        file.write(hashed)
        file.flush()
        run(["sudo", "mokutil", "--import", cert, "--hash-file", file.name])
    print("@@NOTE SECURE_BOOT_KEY", flush=True)
    print("Enroll MOK in firmware at the next boot; a queued request is not enrollment.", flush=True)
    return True


def install(devices, facts, password):
    vendors = {d["vendor"] for d in devices}
    if "amd" in vendors:
        # Never remove amdgpu or blacklist the integrated GPU.
        run(["sudo", "dnf", "install", "-y", "mesa-dri-drivers", "mesa-vulkan-drivers"])
    if "intel" in vendors:
        run(["sudo", "dnf", "install", "-y", "mesa-dri-drivers", "mesa-vulkan-drivers", "intel-media-driver", "libva-intel-driver"])
    nvidia = [d for d in devices if d["vendor"] == "nvidia"]
    if not nvidia:
        return
    # A loaded module under Secure Boot already passed kernel trust checks.
    # Preserve third-party, open/proprietary, DKMS and legacy working stacks.
    if facts["NVIDIA_DRIVER"] and all(d["driver"] == "nvidia" for d in nvidia):
        print("Preserving loaded NVIDIA driver " + facts["NVIDIA_DRIVER"] + "; no rebuild, key or boot changes.")
        return
    packages = installed_akmod()
    if len(packages) > 1:
        raise RuntimeError("Multiple NVIDIA akmod branches installed; resolve the package conflict before continuing.")
    if packages:
        package, version = packages[0], None
        print("Preserving installed NVIDIA branch:", package)
        version_installed = output("rpm", "-q", "--qf", "%{VERSION}", package)
        document = output("curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "20",
                          f"https://download.nvidia.com/XFree86/Linux-x86_64/{version_installed}/README/supportedchips.html")
        if not supports(document, devices):
            raise RuntimeError("The unloaded installed NVIDIA branch does not support all detected GPUs. "
                               "No branch was replaced; resolve the package choice before continuing.")
    else:
        package, version = choose_driver(devices)
    # Key must exist BEFORE installing a package that can trigger an akmod build.
    run(["sudo", "dnf", "install", "-y", "akmods", "kmodtool", "mokutil", "openssl"])
    if facts["SECURE_BOOT"] == "?":
        facts["SECURE_BOOT"] = gpu.facts(devices)["SECURE_BOOT"]
    if facts["SECURE_BOOT"] == "?":
        raise RuntimeError("Secure Boot state is unknown; refusing an unattended NVIDIA installation.")
    pending = secure_boot_key(password) if facts["SECURE_BOOT"] == "1" else False
    if not packages:
        suffix = "-580xx" if package.endswith("-580xx") else ""
        run(["sudo", "dnf", "install", "-y", f"{package}-{version}",
             "xorg-x11-drv-nvidia" + suffix + "-cuda", "xorg-x11-drv-nvidia" + suffix + "-power", "libva-nvidia-driver"])
    kernels = {os.uname().release}
    default = output("sudo", "grubby", "--default-kernel")
    if not Path(default).name.startswith("vmlinuz-"):
        raise RuntimeError("Could not identify the default boot kernel; no reboot readiness is claimed")
    kernels.add(Path(default).name.removeprefix("vmlinuz-"))
    for kernel in sorted(kernels):
        run(["sudo", "dnf", "install", "-y", "kernel-devel-" + kernel])
        run(["sudo", "akmods", "--force", "--kernels", kernel])
        output("modinfo", "-k", kernel, "nvidia")
        if facts["SECURE_BOOT"] == "1":
            certificate = output("sudo", "openssl", "x509", "-inform", "DER", "-in",
                                 "/etc/pki/akmods/certs/public_key.der", "-noout", "-ext", "subjectKeyIdentifier")
            wanted = re.search(r"(?:[0-9A-Fa-f]{2}:){10,}[0-9A-Fa-f]{2}", certificate)
            def matches():
                actual = output("modinfo", "-k", kernel, "-F", "sig_key", "nvidia")
                return wanted is not None and actual.replace(":", "").lower() == wanted[0].replace(":", "").lower()
            if not matches():
                # --force alone may retain an existing unsigned/wrong-key RPM.
                run(["sudo", "akmods", "--force", "--rebuild", "--kernels", kernel])
                if not matches():
                    raise RuntimeError("NVIDIA module does not match the akmods signing certificate for " + kernel)
    # RPM Fusion supplies its own nouveau policy. Keep existing boot arguments
    # and initramfs policy instead of forcing fbdev, blacklists or a PCI address.
    print("@@NOTE NVIDIA_INSTALLED", flush=True)
    if pending:
        print("Driver built and signed. NVIDIA remains pending firmware MOK approval and reboot.")
    else:
        print("Driver built; reboot to activate it. The running GPU was not unloaded.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    password = os.environ.pop("OPT_MOK_PASSWORD", "")
    root = Path(os.environ.get("GPU_SYSFS_ROOT", "/sys"))
    devices = gpu.inventory(root)
    facts = gpu.facts(devices, root)
    if not args.install:
        print(json.dumps({"devices": devices, "facts": facts, "akmods": installed_akmod()}, indent=2))
        return
    install(devices, facts, password)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        raise SystemExit("GPU setup stopped: " + str(exc))
