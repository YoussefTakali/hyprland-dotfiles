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
    def exercise(self, terminal, existing=True, config_problem=False):
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
                "Hyprland": ('case "$*" in *version-json*) echo \'{"flags":[]}\';; '
                             '*verify-config*) printf "======== Config parsing result:\\n\\n%s\\n" '
                             + ("'UserSettings.conf:3: unknown option'" if config_problem else "'config ok'")
                             + ';; esac\nexit 0\n'),
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
            if existing:
                previous = home / '.config/hypr'
                previous.mkdir(parents=True)
                (previous / 'personal.txt').write_text('keep my old desktop\n')
                profile = home / '.mozilla/firefox/test.default-release'
                profile.mkdir(parents=True)
                (profile / 'user.js').write_text('// previous preferences\n')
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
            # install-sddm.sh runs behind the sudo stub, so provide the theme it would have installed.
            theme = home / 'sddm-astronaut-theme'
            (theme / 'Components').mkdir(parents=True)
            (theme / 'Components/jake.png').write_bytes(b'\x89PNG fixture')
            runtime = home / 'runtime'
            runtime.mkdir()
            os_release = home / 'os-release'
            os_release.write_text('ID=fedora\nPRETTY_NAME="Fedora test fixture"\n')
            env = dict(os.environ, HOME=directory, PATH=str(stubs) + ':' + os.environ['PATH'],
                       OS_RELEASE=str(os_release), XDG_RUNTIME_DIR=str(runtime), SDDM_THEME_DIR=str(theme),
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
            if config_problem:
                self.assertIn('@@WARN Hyprland reported problems in the installed config', result.stdout)
                self.assertIn('UserSettings.conf:3: unknown option', result.stdout)
            else:
                self.assertIn('Hyprland config check: ok', result.stdout)
                self.assertNotIn('@@WARN Hyprland reported problems', result.stdout)
            if existing:
                backup = next(home.glob('.config-backup-*'))
                self.assertEqual((backup/'hypr/personal.txt').read_text(), 'keep my old desktop\n')
                self.assertEqual((backup/'firefox/.mozilla/firefox/test.default-release/user.js').read_text(), '// previous preferences\n')
            else:
                self.assertEqual(list(home.glob(".config-backup-*")), [])
                self.assertNotIn("@@NOTE BACKUP", result.stdout)
            boundaries = (home/'boundaries').read_text()
            self.assertIn('installer/install-session.py', boundaries)
            if terminal:
                self.assertIn('installer/select-session.py', boundaries)
                self.assertIn('Driver installation skipped', result.stdout)
                self.assertEqual((home/'.config/waybar/config').resolve().name, '[TOP] Liquid Glass V3')
            else:
                self.assertIn('Preserving loaded NVIDIA driver', result.stdout)
                self.assertIn('installer/session/install-sddm.sh', boundaries)
                self.assertIn('installer/select-session.py', boundaries)

    def test_terminal_entry_point_and_gdm_selection(self):
        self.exercise(True)

    def test_graphical_backend_and_sddm_selection(self):
        self.exercise(False, existing=False)

    def test_config_problems_are_reported_without_failing(self):
        self.exercise(False, existing=False, config_problem=True)


if __name__ == '__main__':
    unittest.main()
