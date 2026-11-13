#!/usr/bin/env python3
"""Build the optional Wayland startup still in the user's home, or skip safely."""
from pathlib import Path
import shutil
import os
import subprocess
import tempfile

source = Path(__file__).resolve().parent
output = Path.home() / '.local/lib/hyprland-startup/wallpaper/hypr-start-wall'
try:
    flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'wayland-client'], text=True).split()
    protocols = subprocess.check_output(['pkg-config', '--variable=pkgdatadir', 'wayland-protocols'], text=True).strip()
    with tempfile.TemporaryDirectory(prefix='hypr-start-wall-build-') as tmp:
        work = Path(tmp)
        layer = source / 'wlr-layer-shell-unstable-v1.xml'
        subprocess.run(['wayland-scanner', 'client-header', str(layer), str(work / 'wlr-layer-shell-client.h')], check=True)
        subprocess.run(['wayland-scanner', 'private-code', str(layer), str(work / 'layer.c')], check=True)
        subprocess.run(['wayland-scanner', 'private-code', str(Path(protocols) / 'stable/xdg-shell/xdg-shell.xml'), str(work / 'xdg.c')], check=True)
        protocol = Path(protocols) / 'stable/presentation-time/presentation-time.xml'
        subprocess.run(['wayland-scanner', 'client-header', str(protocol), str(work / 'presentation-time-client.h')], check=True)
        subprocess.run(['wayland-scanner', 'private-code', str(protocol), str(work / 'presentation.c')], check=True)
        subprocess.run(['cc', '-O2', '-Wall', '-Wextra', '-Werror', '-I' + str(work), str(source / 'startup-wallpaper.c'), str(work / 'layer.c'), str(work / 'xdg.c'), str(work / 'presentation.c'), '-o', str(work / 'helper'), *flags, '-lm'], check=True)
        output.parent.mkdir(parents=True, exist_ok=True)
        # A running client can keep its old inode; never truncate its executable.
        temporary = output.with_suffix('.new')
        shutil.copy2(work / 'helper', temporary)
        temporary.chmod(0o755)
        os.replace(temporary, output)
    print('Installed optional startup still:', output)
except (OSError, subprocess.CalledProcessError) as exc:
    print('Optional startup still unavailable; swww remains the fallback:', exc)
