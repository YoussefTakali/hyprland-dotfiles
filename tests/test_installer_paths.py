#!/usr/bin/env python3
"""Run the real terminal/backend paths in temporary homes with root/network stubs.

This verifies orchestration/copying, not DNF transactions, firmware, or a real GUI
installation. System mutations and all network requests are deliberately stubbed.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class InstallerPaths(unittest.TestCase):
    def exercise(self, terminal):
        with tempfile.TemporaryDirectory(prefix="installer-path-") as directory:
            home = Path(directory)
            stubs = home / "stubs"
            stubs.mkdir()
            commands = {
                "sudo": 'printf "sudo %s\\n" "$*" >> "$HOME/boundaries"\nexit 0\n',
                "curl": 'printf "curl %s\\n" "$*" >> "$HOME/boundaries"\nexit 0\n',
                "git": "exit 0\n",
                "pkg-config": "exit 1\n",
                "fc-list": 'echo "JetBrainsMono Nerd Font"\n',
                "rpm": 'case "$*" in *%fedora*) echo 45;; esac\nexit 0\n',
                "mpv": 'echo "hevc HEVC decoder"\n',
                "Hyprland": 'case "$*" in *version-json*) echo \'{"flags":[]}\';; esac\nexit 0\n',
                "start-hyprland": 'echo "--no-nixgl"\n',
                "gsettings": 'exit 0\n', "xdg-mime": 'exit 0\n',
                "pkill": 'exit 1\n', "gtk-update-icon-cache": 'exit 0\n',
                "wallust": 'exit 0\n', "localectl": 'echo "X11 Layout: us"\n',
            }
            for name in ('waybar', 'qs', 'rofi', 'hypridle', 'hyprlock', 'swww', 'swww-daemon'):
                commands[name] = 'exit 0\n'
            for name, body in commands.items():
                path = stubs / name
                path.write_text('#!/bin/sh\n' + body)
                path.chmod(0o755)
            # A real previous configuration and Firefox profile must survive in backups.
            previous = home / '.config/hypr'
            previous.mkdir(parents=True)
            (previous / 'personal.txt').write_text('keep my old desktop\n')
            profile = home / '.mozilla/firefox/test.default-release'
            profile.mkdir(parents=True)
            (profile / 'user.js').write_text('// previous preferences\n')
            theme = home / '.cache/sddm-astronaut-repair/Themes'
            theme.mkdir(parents=True)
            (theme / 'jake_the_dog.conf').touch()
            # A loaded NVIDIA fixture makes this test independent of host GPUs.
            sysfs = home / 'sys'
            device = sysfs / 'bus/pci/devices/0000:99:00.0'
            device.mkdir(parents=True)
            for field, value in {'class':'0x030000','vendor':'0x10de','device':'0x2489','boot_vga':'1'}.items():
                (device / field).write_text(value)
            driver = sysfs / 'bus/pci/drivers/nvidia'
            driver.mkdir(parents=True)
            (device / 'driver').symlink_to(driver)
            version = sysfs / 'module/nvidia/version'
            version.parent.mkdir(parents=True)
            version.write_text('615.78.08')
            runtime = home / 'runtime'
            runtime.mkdir()
            os_release = home / 'os-release'
            os_release.write_text('ID=fedora\nPRETTY_NAME="Fedora test fixture"\n')
            env = dict(os.environ, HOME=directory, PATH=str(stubs) + ':' + os.environ['PATH'],
                       OS_RELEASE=str(os_release), XDG_RUNTIME_DIR=str(runtime),
                       OPT_SKIP_BASE='1', OPT_DRIVERS='1', OPT_LOGIN='sddm', OPT_BAR='glass', OPT_KB='us', GPU_SYSFS_ROOT=str(sysfs))
            command = (['bash', str(REPO/'install.sh'), '--no-base', '--no-drivers', '--bar=liquid-v3'] if terminal
                       else ['bash', str(REPO/'installer/backend.sh')])
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('@@DONE', result.stdout)
            self.assertNotIn('@@FAIL', result.stdout)
            self.assertTrue((home/'.config/hypr/scripts/GpuDetect.py').is_file())
            self.assertTrue((home/'.config/hypr/scripts/StartupWallpaper.sh').is_file())
            self.assertTrue((home/'.config/quickshell/login-splash/jake.png').is_file())
            self.assertTrue((home/'.local/share/hypr-login-themes/JakeLoadingScene.qml').is_file())
            self.assertTrue((home/'.local/share/hypr-login-themes/shell.qml').is_file())
            self.assertTrue((home/'.config/hypr/UserConfigs/GPU.conf').exists())
            backup = next(home.glob('.config-backup-*'))
            self.assertEqual((backup/'hypr/personal.txt').read_text(), 'keep my old desktop\n')
            self.assertEqual((backup/'firefox/.mozilla/firefox/test.default-release/user.js').read_text(), '// previous preferences\n')
            boundaries = (home/'boundaries').read_text()
            self.assertIn('installer/install-session.py', boundaries)
            if terminal:
                self.assertIn('installer/select-session.py', boundaries)
                self.assertIn('Driver installation skipped', result.stdout)
                self.assertEqual((home/'.config/waybar/config').resolve().name, '[TOP] Liquid Glass V3')
            else:
                self.assertIn('Preserving loaded NVIDIA driver', result.stdout)
                self.assertIn('--system', boundaries)

    def test_terminal_entry_point_and_gdm_selection(self):
        self.exercise(True)

    def test_graphical_backend_and_sddm_selection(self):
        self.exercise(False)


if __name__ == '__main__':
    unittest.main()
