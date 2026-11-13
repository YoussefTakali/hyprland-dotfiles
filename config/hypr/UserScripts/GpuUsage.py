#!/usr/bin/env python3
"""Waybar GPU metrics: detect hardware, bound queries, and never invent readings."""
import csv
import glob
import json
import re
import subprocess
from pathlib import Path

def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ''

def emit(text='', tooltip='', css='none', percentage=None):
    result = dict(text=text, tooltip=tooltip, **{'class': css})
    if percentage is not None:
        result['percentage'] = percentage
    print(json.dumps(result, ensure_ascii=False))

def pci_name(pci, fallback):
    try:
        result = subprocess.run(['lspci', '-s', pci, '-mm'], capture_output=True,
                                text=True, timeout=1, check=True)
        fields = next(csv.reader(result.stdout.splitlines(), delimiter=' ', skipinitialspace=True))
        return fields[3] if len(fields) > 3 else fallback
    except (OSError, subprocess.SubprocessError, StopIteration):
        return fallback


def intel_clock(card, dev):
    pairs = [(card / 'gt_act_freq_mhz', card / 'gt_max_freq_mhz')]
    pairs.extend((p / 'act_freq', p / 'max_freq') for p in sorted(dev.glob('tile*/gt*/freq0')))
    for actual, maximum in pairs:
        current, limit = read(actual), read(maximum)
        if current.isdigit() and limit.isdigit() and int(limit):
            return f'Clock: {current} / {limit} MHz'
    return ''


def main():
    cards = []
    for path in sorted(glob.glob('/sys/class/drm/card[0-9]*')):
        card = Path(path)
        if not re.fullmatch(r'card\d+', card.name):
            continue
        dev = card / 'device'
        vendor = read(dev / 'vendor')
        if vendor not in ('0x10de', '0x1002', '0x8086'):
            continue
        connected = any(read(p) == 'connected' for p in card.glob(card.name + '-*/status'))
        cards.append((connected, vendor == '0x10de', card, dev, vendor))
    if not cards:
        emit(tooltip='No graphics device visible')
        return
    _, _, card, dev, vendor = max(cards, key=lambda c: (c[0], c[1]))
    pci = dev.resolve().name
    if vendor != '0x10de':
        name = pci_name(pci, {'0x1002': 'AMD GPU', '0x8086': 'Intel GPU'}[vendor])
        util = read(dev / 'gpu_busy_percent')
        details = [f'{name} ({pci})']
        if util.isdigit():
            used, total = read(dev / 'mem_info_vram_used'), read(dev / 'mem_info_vram_total')
            details.append(f'Usage: {util}%')
            if used.isdigit() and total.isdigit():
                details.append(f'VRAM: {int(used) // 1048576} / {int(total) // 1048576} MiB')
            for sensor in sorted(dev.glob('hwmon/hwmon*')):
                temperature = read(sensor / 'temp1_input')
                power = read(sensor / 'power1_average') or read(sensor / 'power1_input')
                if temperature.isdigit():
                    details.append(f'Temp: {int(temperature) / 1000:g} °C')
                if power.isdigit():
                    details.append(f'Power: {int(power) / 1000000:g} W')
            value = min(100, int(util))
            css = 'critical' if value >= 85 else 'high' if value >= 50 else 'normal'
            emit(f'{value}% 󰢮', '\n'.join(details + ['Right click: nvtop']), css, value)
        else:
            clock = intel_clock(card, dev) if vendor == '0x8086' else ''
            emit('󰢮', '\n'.join(details + [clock or 'Usage unavailable']), 'unavailable')
        return
    info = read(f'/proc/driver/nvidia/gpus/{pci}/information')
    model = re.search(r'^Model:\s*(.+)$', info, re.M)
    name = model[1] if model else pci_name(pci, f'NVIDIA GPU ({pci})')
    if read(dev / 'power/runtime_status') in ('suspended', 'suspending'):
        emit('off 󰢮', f'{name}\nGPU asleep (saving power)', 'off')
        return
    try:
        result = subprocess.run([
            'nvidia-smi', f'--id={pci}',
            '--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw',
            '--format=csv,noheader,nounits',
        ], capture_output=True, text=True, timeout=2, check=True)
        row = next(csv.reader(result.stdout.splitlines(), skipinitialspace=True))
        name, util, temp, used, total, power = [v.strip() for v in row]
        value = max(0, min(100, int(float(util))))
    except (OSError, subprocess.SubprocessError, ValueError, StopIteration):
        emit('? 󰢮', f'{name}\nGPU metrics unavailable. Run nvidia-smi in your desktop terminal.', 'unavailable')
        return
    css = 'critical' if value >= 85 else 'high' if value >= 50 else 'normal'
    emit(f'{value}% 󰢮', f'{name}\nUsage: {value}%\nTemp: {temp}°C\nVRAM: {used} / {total} MiB\nPower: {power} W\n\nRight click: nvtop', css, value)

if __name__ == '__main__':
    main()
