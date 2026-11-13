#!/usr/bin/env python3
"""Regression checks for portal activation and hardware-dependent GPU output."""
import importlib.util
import fcntl
import socket
import unittest
import json
import os
import sys
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch
from contextlib import redirect_stdout
from io import StringIO

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gpu_metrics', repo / 'config/hypr/UserScripts/GpuUsage.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def fake_read(path):
    s = str(path)
    if s.endswith('/vendor'): return '0x10de'
    if s.endswith('/status'): return 'connected'
    if s.endswith('/runtime_status'): return 'active'
    if s.endswith('/information'): return 'Model: NVIDIA Test GPU'
    return ''

class SessionIntegrationTests(unittest.TestCase):
    def test_portal_restart_and_display_gpu(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            for command in ['systemctl', 'dbus-update-activation-environment']:
                stub = p / command
                stub.write_text('''#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "$REPAIR_TEST_LOG"
case "$*" in *reset-failed*) exit 1;; esac
''')
                stub.chmod(0o755)
            env = dict(os.environ, PATH=tmp + ':' + os.environ['PATH'], XDG_RUNTIME_DIR=tmp,
                       REPAIR_TEST_LOG=tmp + '/commands', WAYLAND_DISPLAY='wayland-test',
                       HYPRLAND_INSTANCE_SIGNATURE='test-instance')
            subprocess.run(['bash', str(repo / 'config/hypr/scripts/SessionInit.sh'), '--restart'], env=env, check=True)
            lines = (p / 'commands').read_text().splitlines()
            assert lines[0].startswith('dbus-update-activation-environment')
            assert lines[2].endswith('start hyprland-dotfiles-session.target')
            assert any('--user restart xdg-desktop-portal-hyprland.service' in line for line in lines)
            # Validate display GPU choice, including a desktop with an unused AMD iGPU.
            scripts = p / '.config/hypr/scripts'
            scripts.mkdir(parents=True)
            (p / '.config/hypr/UserConfigs').mkdir()
            for gpu, driver in [('nvidia', 'nvidia'), ('amd', 'radeonsi'), ('intel', 'iHD')]:
                info = scripts / 'GpuInfo.sh'
                info.write_text(f'#!/bin/sh\nprintf \'MODE=hybrid-nvidia\\nGPUS="amd nvidia"\\nNVIDIA_DRIVER=615.78.08\\nIGPU=amd\\nDGPU=nvidia\\nDISPLAY_GPU={gpu}\\nINTEL_VA=iHD\\n\'\n')
                info.chmod(0o755)
                subprocess.run(['bash', str(repo / 'config/hypr/scripts/GpuConfig.sh')], env=dict(os.environ, HOME=tmp), check=True, capture_output=True)
                generated = (p / '.config/hypr/UserConfigs/GPU.conf').read_text()
                assert 'env = LIBVA_DRIVER_NAME,' not in generated
                assert 'env = __GLX_VENDOR_LIBRARY_NAME,nvidia' not in generated

    def test_gpu_metrics_and_timeout(self):
        with patch.object(module.glob, 'glob', return_value=['/sys/class/drm/card7']), \
             patch.object(module.Path, 'glob', return_value=[Path('/fake/status')]), \
             patch.object(module, 'read', side_effect=fake_read):
            output = StringIO()
            result = subprocess.CompletedProcess([], 0, 'NVIDIA Test GPU, 42, 60, 1024, 8192, 80.5\n', '')
            with patch.object(module.subprocess, 'run', return_value=result), redirect_stdout(output):
                module.main()
            metrics = json.loads(output.getvalue())
            assert metrics['percentage'] == 42 and 'NVIDIA Test GPU\nUsage' in metrics['tooltip']
            output = StringIO()
            with patch.object(module.subprocess, 'run', side_effect=subprocess.TimeoutExpired('nvidia-smi', 2)), redirect_stdout(output):
                module.main()
            metrics = json.loads(output.getvalue())
            assert metrics['class'] == 'unavailable' and 'percentage' not in metrics

    def test_wallpaper_daemon_readiness_and_handoff(self):
        with tempfile.TemporaryDirectory(prefix='socket-check-') as directory:
            try:
                with socket.socket(socket.AF_UNIX) as probe:
                    probe.bind(directory + '/probe')
            except PermissionError as exc:
                # These clients are shell stubs; they only need -S metadata, never a bus
                # connection. A delayed symlink to an existing socket exercises that gate.
                import stat
                candidates = [Path(os.environ.get('XDG_RUNTIME_DIR', '/nonexistent'))/'bus', Path('/run/dbus/system_bus_socket')]
                source = next((path for path in candidates if path.exists() and stat.S_ISSOCK(path.stat().st_mode)), None)
                if source is None:
                    print('BLOCKED: wallpaper socket fixtures: AF_UNIX bind denied:', exc)
                    self.skipTest("Unix socket fixture is unavailable")
                self.addCleanup(os.environ.pop, 'TEST_SOCKET_SOURCE', None)
                os.environ['TEST_SOCKET_SOURCE'] = str(source)
                print('NOTE: AF_UNIX bind denied; using an existing socket inode for stat-only shell fixtures. No live service connection.')
        with tempfile.TemporaryDirectory(prefix='startup-wallpaper-check-') as tmp:
            home = Path(tmp)
            scripts = home / 'stubs'
            scripts.mkdir()
            runtime = home / 'runtime'
            runtime.mkdir()
            wall = home / '.config/hypr/wallpaper_effects/.wallpaper_current'
            wall.parent.mkdir(parents=True)
            wall.write_text('test image')
            # Use a real Unix socket node: cold client queries otherwise hide swww's
            # 500 ms missing-socket retry behind an unrealistically fast stub.
            socket_path = runtime / 'wayland-test-swww-daemon..sock'
            (scripts / 'make-socket').write_text("""#!/usr/bin/env python3
import os, socket
if os.environ.get('TEST_SOCKET_SOURCE'):
    os.symlink(os.environ['TEST_SOCKET_SOURCE'], os.environ['XDG_RUNTIME_DIR'] + '/wayland-test-swww-daemon..sock')
    raise SystemExit(0)
s = socket.socket(socket.AF_UNIX)
s.bind(os.environ['XDG_RUNTIME_DIR'] + '/wayland-test-swww-daemon..sock')
""")
            (scripts / 'swww').write_text("""#!/bin/sh
case "$1" in
query)
    if ! test -S "$XDG_RUNTIME_DIR/wayland-test-swww-daemon..sock"; then
        touch "$HOME/queried-before-socket"
        sleep 0.5
        exit 1
    fi
    test -f "$HOME/ready";;
img) printf 'image %s\\n' "$*" >> "$HOME/commands";;
esac
""")
            (scripts / 'swww-daemon').write_text("""#!/bin/sh
printf 'daemon %s\\n' "$*" >> "$HOME/commands"
sleep 0.12
make-socket
touch "$HOME/ready"
""")
            (scripts / 'pgrep').write_text("""#!/bin/sh
if test -f "$HOME/existing"; then make-socket; touch "$HOME/ready"; exit 0; fi
exit 1
""")
            for command in scripts.iterdir():
                command.chmod(0o755)
            env = dict(os.environ, HOME=tmp, XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY='wayland-test', PATH=str(scripts)+':'+os.environ['PATH'])
            helper = str(repo / 'config/hypr/scripts/StartupWallpaper.sh')
            subprocess.run(['bash', helper], env=env, check=True)
            assert not (home/'queried-before-socket').exists(), 'Cold startup queried a missing socket'
            commands = (home/'commands').read_text()
            assert 'daemon --no-cache' in commands and '--format xrgb' not in commands
            assert 'image img --transition-type none' in commands, (commands, (home/'.local/state/session-startup/wallpaper.log').read_text())
            (home/'commands').unlink()
            (home/'ready').unlink()
            socket_path.unlink()
            (home/'existing').touch()
            subprocess.run([str(scripts/'make-socket')], env=env, check=True)
            (home/'ready').touch()
            subprocess.run(['bash', helper], env=env, check=True)
            assert 'daemon' not in (home/'commands').read_text()
            assert not (home/'queried-before-socket').exists()
            before = (home/'commands').read_text()
            with (runtime/'startup-wallpaper.lock').open('w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                subprocess.run(['bash', helper], env=env, check=True)
            assert (home/'commands').read_text() == before
            # Exercise the real bridge handoff and its failure fallback with a fake
            # layer-shell client while retaining the real startup shell script.
            selector = home/'.config/hypr/scripts/StartupWallpaperCache.py'
            selector.parent.mkdir(parents=True, exist_ok=True)
            raw = home/'pixels.bgrx'
            raw.write_bytes(b'pixels')
            selector.write_text('import os\nprint(os.environ["HOME"] + "/.config/hypr/wallpaper_effects/.wallpaper_current")\nprint(2)\nprint(2)\nprint(1)\nprint(os.environ["HOME"] + "/pixels.bgrx")\n')
            native = home/'.local/lib/hyprland-startup/wallpaper/hypr-start-wall'
            native.parent.mkdir(parents=True)
            native.write_text('#!/bin/sh\ntrap \'touch "$HOME/handoff-requested"; exit 0\' USR1\ntouch "$5"\nwhile :; do sleep 0.02; done\n')
            native.chmod(0o755)
            (home/'commands').unlink()
            subprocess.run(['bash', helper, '--still-only'], env=env, check=True, timeout=5)
            log = (home/'.local/state/session-startup/wallpaper.log').read_text()
            assert 'Wallpaper daemon warmed at uptime' in log
            assert 'image img --transition-type none' in (home/'commands').read_text()
            assert (home/'handoff-requested').exists(), 'Bridge was killed instead of requesting presentation-aware handoff'
            native.write_text('#!/bin/sh\nexit 1\n')
            (home/'commands').unlink()
            subprocess.run(['bash', helper, '--still-only'], env=env, check=True, timeout=5)
            assert 'image img --transition-type none' in (home/'commands').read_text()


if __name__ == "__main__":
    unittest.main()
