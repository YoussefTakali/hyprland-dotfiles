#!/usr/bin/env python3
"""Reversible BlueZ Classic-only isolation test, not a replacement driver."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

CONFIG = Path('/etc/bluetooth/main.conf')
STATE = Path('/var/lib/hyprland-bluetooth-classic-test')


def classic_config(text):
    output = []
    general = False
    found = False
    for line in text.splitlines(keepends=True):
        section = re.match(r'^\s*\[([^]]+)\]', line)
        if section:
            general = section[1].strip().lower() == 'general'
            if general and not found:
                output.append(line if line.endswith('\n') else line + '\n')
                output.append('ControllerMode = bredr\n')
                found = True
                continue
        if general and re.match(r'^\s*ControllerMode\s*=', line, re.I):
            continue
        output.append(line)
    if not found:
        output.insert(0, '[General]\nControllerMode = bredr\n')
    return ''.join(output)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_config(data, mode):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=CONFIG.parent, prefix='.classic-test-')
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(name, mode)
        os.replace(name, CONFIG)
    finally:
        Path(name).unlink(missing_ok=True)
    if shutil.which('restorecon'):
        subprocess.run(['restorecon', str(CONFIG)], check=True)


def restore(saved):
    if saved['existed']:
        write_config((STATE/'original.conf').read_bytes(), saved['mode'])
    else:
        CONFIG.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--apply', action='store_true')
    modes.add_argument('--restore', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run with sudo. This changes BlueZ transport mode and restarts Bluetooth.')
    # Check host service access before changing any configuration.
    subprocess.run(['systemctl', 'is-active', '--quiet', 'bluetooth.service'], check=True)
    manifest = STATE/'state.json'
    if args.restore:
        if not manifest.exists():
            raise RuntimeError('No active Classic-only test backup exists.')
        saved = json.loads(manifest.read_text())
        if digest(CONFIG.read_bytes()) != saved['applied_hash']:
            raise RuntimeError(f'Config changed since the test; refusing to overwrite it. Original backup: {STATE}')
        restore(saved)
        subprocess.run(['systemctl', 'restart', 'bluetooth.service'], check=True)
        manifest.unlink()
        print('Original Bluetooth mode restored. Pairing records were not changed.')
        return
    if manifest.exists():
        raise RuntimeError('A Classic-only test is already active. Use --restore before starting another.')
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    original = CONFIG.read_bytes() if CONFIG.exists() else b''
    applied = classic_config(original.decode()).encode()
    saved = {'existed': CONFIG.exists(), 'mode': CONFIG.stat().st_mode & 0o777 if CONFIG.exists() else 0o644,
             'applied_hash': digest(applied)}
    (STATE/'original.conf').write_bytes(original)
    (STATE/'original.conf').chmod(0o600)
    manifest.write_text(json.dumps(saved, indent=2)+'\n')
    try:
        write_config(applied, saved['mode'])
        subprocess.run(['systemctl', 'restart', 'bluetooth.service'], check=True)
    except BaseException:
        restore(saved)
        subprocess.run(['systemctl', 'restart', 'bluetooth.service'], check=False)
        manifest.unlink(missing_ok=True)
        raise
    print('Classic-only Bluetooth test enabled. Bluetooth connections were restarted.')
    print('Low Energy devices/battery links are unavailable until --restore.')
    print('Open Blueman, search and pair the earbuds while the white pairing light flashes.')
    print('Success requires a real A2DP output; changing mode alone is not a verified fix.')
    print('Restore with: sudo python3 '+str(Path(__file__).resolve())+' --restore')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
