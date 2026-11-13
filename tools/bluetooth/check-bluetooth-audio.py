#!/usr/bin/env python3
"""Read real Bluetooth/audio/battery state; optionally test a selected audio output."""
import argparse
import array
import datetime
import json
import math
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time
import wave

import gi
from gi.repository import Gio, GLib

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'config/hypr/UserScripts'))
from BluetoothState import DEVICE, AUDIO_SINK, audio_outputs, battery_readings


def pulse(kind):
    result = subprocess.run(['pactl', '--format=json', 'list', kind], capture_output=True, text=True, timeout=5, check=True)
    return json.loads(result.stdout)


def test_output(sink, directory):
    # A sink monitor validates digital routing, not acoustic sound from a speaker.
    sources = pulse('sources')
    monitor = next((s for s in sources if str(s.get('index')) == str(sink.get('monitor_source'))), None)
    if monitor is None:
        raise RuntimeError('The selected audio output has no readable monitor source.')
    tone = directory / 'test-tone.wav'
    with wave.open(str(tone), 'wb') as stream:
        stream.setnchannels(2)
        stream.setsampwidth(2)
        stream.setframerate(48000)
        data = bytearray()
        for i in range(48000):
            value = int(1000 * math.sin(2 * math.pi * 440 * i / 48000))
            left, right = (value, 0) if i < 24000 else (0, value)
            data.extend(struct.pack('<hh', left, right))
        stream.writeframes(data)
    raw = directory / 'output-monitor.raw'
    with raw.open('wb') as target:
        recorder = subprocess.Popen(['parec', '--device=' + monitor['name'], '--format=s16le',
            '--rate=48000', '--channels=2', '--latency-msec=50'], stdout=target, stderr=subprocess.PIPE)
        try:
            time.sleep(0.25)
            subprocess.run(['paplay', '--device=' + sink['name'], '--volume=12000', str(tone)], check=True, timeout=10)
            time.sleep(0.25)
        finally:
            if recorder.poll() is None:
                recorder.send_signal(signal.SIGTERM)
            try:
                recorder.wait(timeout=3)
            except subprocess.TimeoutExpired:
                recorder.kill()
                recorder.wait()
    samples = array.array('h')
    samples.frombytes(raw.read_bytes()[:raw.stat().st_size // 2 * 2])
    if sys.byteorder != 'little':
        samples.byteswap()
    peak = max((abs(v) for v in samples), default=0)
    return {'sink': sink['name'], 'monitor': monitor['name'], 'captured_samples': len(samples),
            'peak': peak, 'digital_audio_detected': peak > 0,
            'acoustic_playback_verified': False, 'capture': str(raw)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--match', default='', help='Only names containing this text')
    parser.add_argument('--test-audio', action='store_true', help='Play a quiet tone and record its digital output monitor')
    parser.add_argument('--logs', action='store_true', help='Include bounded Bluetooth/kernel/WirePlumber logs without pairing keys')
    args = parser.parse_args()
    directory = Path.home() / '.local/state/bluetooth-audio-check' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    directory.mkdir(parents=True, exist_ok=True)
    logs = {}
    if args.logs:
        commands = {
            'bluetooth': ['journalctl', '-b', '-u', 'bluetooth', '--no-pager', '-n', '120'],
            'wireplumber': ['journalctl', '--user', '-b', '-u', 'wireplumber', '--no-pager', '-n', '100'],
            'kernel': ['journalctl', '-k', '-b', '--no-pager', '-n', '2000'],
        }
        for name, command in commands.items():
            try:
                result = subprocess.run(command, capture_output=True, text=True, timeout=5)
                output = result.stdout
                if name == 'kernel':
                    output = '\n'.join(line for line in output.splitlines()
                                       if any(term in line.lower() for term in ('bluetooth', 'btusb', 'hci0')))
                logs[name] = {'returncode': result.returncode, 'stdout': output, 'stderr': result.stderr}
            except (OSError, subprocess.SubprocessError) as error:
                logs[name] = {'error': str(error)}
        (directory / 'logs.json').write_text(json.dumps(logs, indent=2) + '\n')
        print('Service/kernel logs saved:', directory / 'logs.json')
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    result = bus.call_sync('org.bluez', '/', 'org.freedesktop.DBus.ObjectManager', 'GetManagedObjects',
                          None, None, Gio.DBusCallFlags.NONE, 5000, None)
    objects = result.unpack()[0]
    sinks = pulse('sinks')
    try:
        controller = subprocess.run(['btmgmt', 'info'], capture_output=True, text=True, timeout=5)
        management = {'returncode': controller.returncode, 'stdout': controller.stdout, 'stderr': controller.stderr}
    except (OSError, subprocess.SubprocessError) as error:
        management = {'returncode': -1, 'stdout': '', 'stderr': str(error)}
    report = {'devices': [], 'test': None, 'controller_management': management, 'logs': logs}
    for path, interfaces in objects.items():
        props = interfaces.get(DEVICE)
        if props is None:
            continue
        name = props.get('Name') or props.get('Alias') or props.get('Address')
        if args.match and args.match.casefold() not in str(name).casefold():
            continue
        if not args.match and not (props.get('Connected') or props.get('Paired')):
            continue
        outputs = audio_outputs(sinks, props.get('Address', ''))
        batteries = battery_readings(objects, path)
        device = {'name': name, 'address': props.get('Address'), 'address_type': props.get('AddressType'),
            'connected': props.get('Connected', False), 'paired': props.get('Paired', False),
            'services_resolved': props.get('ServicesResolved'),
            'object_path': path, 'interfaces': sorted(interfaces),
            'preferred_bearer': props.get('PreferredBearer'), 'uuids': props.get('UUIDs', []),
            'audio_sink_service': AUDIO_SINK in [str(u).lower() for u in props.get('UUIDs', [])],
            'audio_outputs': [o['name'] for o in outputs], 'batteries': batteries,
            'left': None, 'right': None, 'case': None}
        for battery in batteries:
            if battery['component'] in ('left', 'right', 'case'):
                device[battery['component']] = battery
        report['devices'].append(device)
        print(f"{name} [{device['address']} / {device['address_type']}]: Bluetooth {'connected' if device['connected'] else 'disconnected'}; audio output {'present' if outputs else 'absent'}")
        print('  Classic Audio Sink service:', 'present' if device['audio_sink_service'] else 'absent')
        print('  Preferred bearer:', device['preferred_bearer'] or 'not exposed by BlueZ')
        for part in ('left', 'right', 'case'):
            reading = device[part]
            if reading:
                level = str(reading['percentage']) + '%' if reading['percentage'] is not None else 'unknown level'
                charging = 'yes' if reading['charging'] is True else 'no' if reading['charging'] is False else 'not reported'
                print(f'  {part}: {level} (charging: {charging})')
            else:
                print(f'  {part}: not reported by device/BlueZ')
        for battery in batteries:
            if battery['component'] == 'aggregate':
                print('  Aggregate battery:', battery['percentage'], '%')
    if args.test_audio:
        candidates = [item for device in report['devices'] if device['connected']
                      for item in sinks if item['name'] in device['audio_outputs']]
        if len(candidates) != 1:
            print('Audio test skipped: exactly one matching connected Bluetooth audio output is required.')
        else:
            print('Playing a quiet one-second left/right tone and checking its digital output monitor...')
            report['test'] = test_output(candidates[0], directory)
            print('Digital audio detected:', report['test']['digital_audio_detected'])
            print('Actual sound in the earbuds still requires a listening check.')
    path = directory / 'report.json'
    path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print('Saved:', path)
    return 0

if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (GLib.Error, OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('Could not verify live Bluetooth/audio state:', error, file=sys.stderr)
        raise SystemExit(1)
