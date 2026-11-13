#!/usr/bin/env python3
"""PCI/DRM fixtures and installer decisions; never alters the host drivers."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]


def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, REPO / relative)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


gpu = module("gpu", "config/hypr/scripts/GpuDetect.py")
setup = module("setup_gpu", "installer/gpu-setup.py")
session = module("session", "installer/install-session.py")
launcher = module("launcher", "config/hypr/scripts/StartHyprland.py")


def pci(root, address, vendor, card=None, connected=False, device="0x2489", driver=None):
    dev = root / "bus/pci/devices" / address
    dev.mkdir(parents=True)
    for name, value in {"class": "0x030000", "vendor": vendor, "device": device, "boot_vga": "0"}.items():
        (dev / name).write_text(value)
    if driver:
        target = root / "bus/pci/drivers" / driver
        target.mkdir(parents=True, exist_ok=True)
        (dev / "driver").symlink_to(target)
    if card:
        path = root / "class/drm" / card
        path.mkdir(parents=True)
        (path / "device").symlink_to(dev)
        connector = path / (card + "-HDMI-A-1")
        connector.mkdir()
        (connector / "status").write_text("connected" if connected else "disconnected")
    return dev


class Detection(unittest.TestCase):
    def test_missing_nvidia_module_still_detected_with_amd(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pci(root, "0000:42:00.0", "0x10de")
            pci(root, "0000:09:00.0", "0x1002", "card8", True, driver="amdgpu")
            devices = gpu.inventory(root)
            with patch.object(gpu, "command", return_value=""):
                facts = gpu.facts(devices, root)
            self.assertEqual(facts["MODE"], "hybrid-nvidia")
            self.assertEqual(facts["DISPLAY_GPU"], "amd")
            self.assertEqual(facts["NVIDIA_DRIVER"], "")
            self.assertEqual(facts["NVIDIA_PCI"], "0000:42:00.0")

    def test_runtime_order_fallback_multi_display_and_user_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pci(root, "0000:99:00.0", "0x10de", "card12", True)
            pci(root, "0000:06:00.0", "0x1002", "card3", False)
            env = dict(os.environ, GPU_SYSFS_ROOT=tmp)
            env.pop("AQ_DRM_DEVICES", None)
            def primary():
                return subprocess.check_output(["bash", str(REPO / "config/hypr/scripts/GpuPrimary.sh")], text=True, env=env).strip()
            self.assertEqual(primary(), "/dev/dri/card12:/dev/dri/card3 0x10de")
            (root / "class/drm/card3/card3-HDMI-A-1/status").write_text("connected")
            self.assertEqual(primary(), "")
            env["AQ_DRM_DEVICES"] = "/custom/by-name/gpu"
            self.assertEqual(primary(), "")
            with patch.object(gpu, "command", return_value=""):
                self.assertEqual(gpu.facts(gpu.inventory(root), root)["DISPLAY_GPU"], "")

    def test_no_cards_headless_and_intel_id_not_assumed_chronological(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pci(root, "0000:00:02.0", "0x8086", device="0x0a16")
            with patch.object(gpu, "command", return_value=""):
                self.assertEqual(gpu.facts(gpu.inventory(root), root)["INTEL_VA"], "")
                self.assertEqual(gpu.facts([], root)["MODE"], "unknown")

    def test_custom_gpu_config_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            scripts = home / ".config/hypr/scripts"
            scripts.mkdir(parents=True)
            info = scripts / "GpuInfo.sh"
            info.write_text("printf 'MODE=amd\\nGPUS=amd\\nDISPLAY_GPU=amd\\nNVIDIA_DRIVER=\\n'\n")
            user = home / ".config/hypr/UserConfigs"
            user.mkdir()
            config = user / "GPU.conf"
            config.write_text("# My deliberate overrides\nenv = DRI_PRIME,1\n")
            old = config.read_bytes()
            subprocess.run(["bash", str(REPO / "config/hypr/scripts/GpuConfig.sh")],
                           env=dict(os.environ, HOME=tmp), check=True, capture_output=True)
            self.assertEqual(config.read_bytes(), old)


class DriverDecisions(unittest.TestCase):
    def test_support_table_excludes_legacy_appendices_and_accepts_nonmonotonic_ids(self):
        document = '<h3>Current NVIDIA GPUs</h3><tbody><tr id="devid1340"></tr></tbody><tr id="devid2489"></tr>'
        self.assertEqual(setup.supported_ids(document), {"1340"})
        real = Path("/usr/share/doc/xorg-x11-drv-nvidia/html/supportedchips.html")
        if real.exists():
            self.assertIn("2489", setup.supported_ids(real.read_text()))
            self.assertNotIn("1B80", setup.supported_ids(real.read_text()))

    def test_subsystem_only_support_is_not_generalized_to_other_laptops(self):
        document = '<h3>Current NVIDIA GPUs</h3><tbody><tr id="devid1340_103C_2B2B"></tr></tbody>'
        device = {"vendor": "nvidia", "device": "0x1340", "subsystem_vendor": "0x103c", "subsystem_device": "0x2b2b"}
        self.assertTrue(setup.supports(document, [device]))
        device["subsystem_device"] = "0x9999"
        self.assertFalse(setup.supports(document, [device]))

    def test_working_secure_boot_driver_has_no_nvidia_mutations(self):
        devices = [{"vendor": "nvidia", "driver": "nvidia"}]
        with patch.object(setup, "run") as run, patch.object(setup, "secure_boot_key") as key:
            setup.install(devices, {"NVIDIA_DRIVER": "615.78.08", "SECURE_BOOT": "1"}, "")
        run.assert_not_called()
        key.assert_not_called()

    def test_amd_does_not_install_nvidia_or_edit_boot(self):
        with patch.object(setup, "run") as run:
            setup.install([{"vendor": "amd"}], {}, "")
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][:4], ["sudo", "dnf", "install", "-y"])
        self.assertNotIn("akmod-nvidia", run.call_args.args[0])

    def test_unverifiable_branch_is_failure_before_any_install(self):
        with patch.object(setup, "output", side_effect=OSError("offline")):
            with self.assertRaisesRegex(RuntimeError, "No available"):
                setup.choose_driver([{"vendor": "nvidia", "device": "0x2489"}])

    def test_new_secure_boot_key_precedes_driver_install_and_build(self):
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, "", "")
        def output(*args):
            if "grubby" in args: return "/boot/vmlinuz-" + os.uname().release
            if args[0] == "sudo" or "sig_key" in args: return "AA:" * 19 + "AA"
            return "trusted-module"
        with patch.object(setup, "installed_akmod", return_value=[]), \
             patch.object(setup, "choose_driver", return_value=("akmod-nvidia", "615.78.08")), \
             patch.object(setup, "secure_boot_key", side_effect=lambda _: calls.append(["key"]) or True), \
             patch.object(setup, "output", side_effect=output), patch.object(setup, "run", side_effect=run):
            setup.install([{"vendor": "nvidia", "driver": ""}], {"NVIDIA_DRIVER": "", "SECURE_BOOT": "1"}, "password")
        key = calls.index(["key"])
        driver = next(i for i, args in enumerate(calls) if "akmod-nvidia-615.78.08" in args)
        build = next(i for i, args in enumerate(calls) if "akmods" in args and "--kernels" in args)
        self.assertLess(key, driver)
        self.assertLess(driver, build)

    def test_wrong_signing_key_rebuilds_and_still_refuses_untrusted_output(self):
        calls = []
        def output(*args):
            if 'grubby' in args: return '/boot/vmlinuz-' + os.uname().release
            if args[0] == 'sudo': return 'AA:' * 19 + 'AA'
            if 'sig_key' in args: return 'BB:' * 19 + 'BB'
            return 'module'
        with patch.object(setup, 'installed_akmod', return_value=[]), \
             patch.object(setup, 'choose_driver', return_value=('akmod-nvidia', '615.78.08')), \
             patch.object(setup, 'secure_boot_key', return_value=False), \
             patch.object(setup, 'output', side_effect=output), \
             patch.object(setup, 'run', side_effect=lambda args, **kw: calls.append(args)):
            with self.assertRaisesRegex(RuntimeError, 'does not match'):
                setup.install([{'vendor':'nvidia','driver':''}], {'NVIDIA_DRIVER':'','SECURE_BOOT':'1'}, '')
        self.assertTrue(any('--rebuild' in args for args in calls))

    def test_session_install_idempotent_preserves_stock_and_hooks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stock = root / "usr/share/wayland-sessions/hyprland.desktop"
            stock.parent.mkdir(parents=True)
            stock.write_text("stock\n")
            session.install(root)
            session.install(root)
            self.assertEqual(stock.read_text(), "stock\n")
            self.assertIn("DesktopNames=Hyprland", (stock.parent / "hyprland-dotfiles.desktop").read_text())
            self.assertFalse((root / "etc/sddm.conf").exists())

    def test_launcher_package_change_invalidates_cached_fast_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "launcher.json"
            path.write_text(json.dumps({"signature": [1], "flags": ["--no-nixgl"]}))
            with patch.object(launcher, "launcher_signature", return_value=[1]):
                self.assertEqual(launcher.launcher_flags(path), ["--no-nixgl"])
            with patch.object(launcher, "launcher_signature", return_value=[2]):
                self.assertEqual(launcher.launcher_flags(path), [])


if __name__ == "__main__":
    unittest.main()
