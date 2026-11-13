#!/usr/bin/env python3
"""Diagnose a connected earbud, activate A2DP, and verify PipeWire output routing."""
import argparse
import datetime
import json
from pathlib import Path
import re
import socket
import subprocess
import sys
import time

STATE = Path.home() / '.local/state/earbud-audio-repair'
STATE.mkdir(parents=True, exist_ok=True)
LOG = STATE / ('repair-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '.log')


def say(message):
    print(message, flush=True)
    with LOG.open('a') as stream:
        stream.write(message + '\n')


def run(*args, required=True, timeout=15):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        say(f'{args[0]} failed: {error}')
        if required:
            raise RuntimeError(str(error)) from error
        return None
    with LOG.open('a') as stream:
        stream.write('$ ' + ' '.join(args) + '\n' + result.stdout + result.stderr + '\n')
    if required and result.returncode:
        raise RuntimeError((result.stderr or result.stdout or f'{args[0]} failed').strip())
    return result


def objects(kind):
    result = run('pactl', '--format=json', 'list', kind)
    return json.loads(result.stdout)


def belongs(item, mac):
    address = mac.upper().replace(':', '_')
    properties = item.get('properties', {})
    values = [item.get('name', '')] + [properties.get(key, '') for key in (
        'api.bluez5.address', 'device.string', 'device.name', 'api.bluez5.path',
    )]
    return any(address in str(value).upper().replace(':', '_') for value in values)


def a2dp_profile(card):
    profiles = card.get('profiles', {})
    if isinstance(profiles, list):
        profiles = {p['name']: p for p in profiles}
    candidates = [name for name, details in profiles.items()
                  if name.startswith('a2dp-sink') and details.get('available') != 'no']
    # Basic A2DP/SBC first for broad compatibility; leave other codecs selectable in settings.
    for preferred in ('a2dp-sink', 'a2dp-sink-sbc'):
        if preferred in candidates:
            return preferred
    return sorted(candidates)[0] if candidates else None


def choose_device(requested=None):
    listing = run('bluetoothctl', 'devices', 'Connected')
    devices = []
    for line in listing.stdout.splitlines():
        match = re.match(r'Device ([0-9A-Fa-f:]{17}) (.*)', line)
        if match:
            mac, name = match.groups()
            info = run('bluetoothctl', 'info', mac).stdout
            devices.append((mac, name, info))
    if requested:
        matches = [d for d in devices if d[0].lower() == requested.lower()]
    else:
        named = [d for d in devices if re.search(r'buds|xiaomi|redmi', d[1], re.I)]
        named_audio = [d for d in named if '0000110b-' in d[2].lower()]
        matches = named_audio or named or [d for d in devices if '0000110b-' in d[2].lower()]
    if len(matches) != 1:
        say('Connected Bluetooth entries:')
        for mac, name, info in devices:
            audio = 'Audio Sink service' if '0000110b-' in info.lower() else 'no classic Audio Sink service shown'
            say(f'  {mac}  {name}  ({audio})')
        raise RuntimeError('Could not identify exactly one connected earbud. Reconnect the earbuds, or rerun with --device MAC_ADDRESS.')
    return matches[0]


def forget_control_link(mac):
    if not re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', mac):
        raise RuntimeError('Give the exact Bluetooth address of the stale REDMI control entry.')
    mac = mac.upper()
    info = run('bluetoothctl', 'info', mac).stdout
    # Preserve any Classic or LE audio bond, even when its card is missing.
    audio_uuids = r'0000(?:110[89a-e]|111[ef]|184[ef]|185[0-5])-'
    if (not re.search(rf'^Device {mac} \(random\)\s*$', info, re.M)
            or not re.search(r'^\s*Name: REDMI Buds 8 Pro\s*$', info, re.M | re.I)
            or not re.search(r'^\s*Bonded: yes\s*$', info, re.M)
            or re.search(audio_uuids, info, re.I)):
        raise RuntimeError('No matching REDMI Buds 8 Pro control-only bond. Nothing was forgotten. If already removed, retry --pair-classic alone.')
    say(f'Forgetting the stale REDMI control pairing ({mac}).')
    run('bluetoothctl', 'remove', mac)
    bonded = run('bluetoothctl', 'devices', 'Bonded').stdout
    if re.search(rf'^Device {mac}\b', bonded, re.M):
        raise RuntimeError('BlueZ still reports the control entry as bonded. Stop and check the log.')


def direct_classic_candidate(mac):
    say(f'Opening Classic service discovery at the known earbud address {mac}.')
    try:
        with socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP) as connection:
            connection.settimeout(10)
            # SDP listens on Classic L2CAP PSM 1. Opening it creates the ACL
            # link BlueZ needs to expose an earbud that does not answer inquiry.
            connection.connect((mac, 1))
    except OSError as error:
        raise RuntimeError(f'Classic service discovery at {mac} failed: {error}. Check the address and keep the buds in pairing mode.') from error
    for _ in range(10):
        result = run('bluetoothctl', 'info', mac, required=False, timeout=3)
        info = result.stdout if result else ''
        if (re.search(rf'^Device {mac} \(public\)\s*$', info, re.M)
                and re.search(r'^\s*Name: REDMI Buds 8 Pro\s*$', info, re.M | re.I)):
            return mac, 'REDMI Buds 8 Pro', info
        time.sleep(0.5)
    raise RuntimeError(f'Classic service discovery opened at {mac}, but BlueZ did not identify it as REDMI Buds 8 Pro. No pairing was attempted.')


def pair_classic_redmi(stale_control=None, classic_address=None):
    if stale_control:
        forget_control_link(stale_control)
    say('Pair the REDMI Buds 8 Pro audio entry: earbuds in case, lid open; hold the case button 2 seconds until the white light flashes.')
    say('Disconnect them from nearby phones or Windows while pairing.')
    if sys.stdin.isatty():
        input('Press Enter when the white light is flashing: ')
    mac, name, info = direct_classic_candidate(classic_address) if classic_address else scan_classic_redmi()
    say(f'Found a Classic audio candidate: {name} ({mac}).')
    if '0000110b-' not in info.lower():
        set_classic_preference(mac, required=False)
    if not re.search(r'^\s*Paired: yes\s*$', info, re.M):
        pair = run('bluetoothctl', '--agent', 'NoInputNoOutput', '--timeout', '30', 'pair', mac,
                   required=False, timeout=35)
        if pair is not None:
            say((pair.stdout + pair.stderr).strip())
        info = run('bluetoothctl', 'info', mac).stdout
        if not re.search(r'^\s*Paired: yes\s*$', info, re.M):
            raise RuntimeError('Pairing the Classic audio entry failed. No successful pairing is claimed.')
    run('bluetoothctl', 'trust', mac)
    connection = run('bluetoothctl', 'connect', mac, 'a2dp-sink', required=False, timeout=25)
    if connection is not None:
        say((connection.stdout + connection.stderr).strip())
    info = run('bluetoothctl', 'info', mac).stdout
    if not re.search(r'^\s*Connected: yes\s*$', info, re.M) or '0000110b-' not in info.lower():
        raise RuntimeError('BlueZ did not verify a connected device with the Classic Audio Sink service. See the connection error in the log.')
    return mac


def scan_classic_redmi():
    say('Searching Classic Bluetooth for 20 seconds...')
    scan = run('bluetoothctl', '--timeout', '20', 'scan', 'bredr', required=False, timeout=25)
    if scan is None or scan.returncode or 'Failed to start discovery' in scan.stdout + scan.stderr:
        raise RuntimeError('Classic Bluetooth discovery failed. See the captured scan error in the log.')
    listing = run('bluetoothctl', 'devices').stdout
    candidates = []
    for line in listing.splitlines():
        match = re.match(r'Device ([0-9A-Fa-f:]{17}) (.*)', line)
        if not match:
            continue
        mac, name = match.groups()
        if not re.search(r'(?:redmi|xiaomi)\s+buds\s*8\s*pro', name, re.I):
            continue
        info = run('bluetoothctl', 'info', mac).stdout
        header = info.splitlines()[0] if info.splitlines() else ''
        audio = '0000110b-' in info.lower()
        # The reported random-address entry exposes Fast Pair/GATT/battery, not audio.
        if audio or '(public)' in header:
            candidates.append((mac, name, info))
        else:
            say(f'Skipping control-only entry: {mac} {name}')
    if len(candidates) != 1:
        for mac, name, _ in candidates:
            say(f'Audio candidate: {mac} {name}')
        raise RuntimeError('No unique public/audio REDMI Buds 8 Pro entry was found. Keep the white light flashing and retry. The random LE entry will not be paired again.')
    return candidates[0]


def set_classic_preference(mac, required=True):
    result = run('bluetoothctl', 'bearer', mac, 'bredr', required=False, timeout=3)
    if result is not None:
        say((result.stdout + result.stderr).strip())
    # PreferredBearer is optional/experimental. Do not query a property that
    # the daemon just rejected, or spend 15 seconds waiting for missing output.
    response = '' if result is None else result.stdout + result.stderr
    if result is None or result.returncode or any(term in response for term in (
            'UnknownProperty', 'UnknownMethod', 'not available', 'not supported')):
        if required:
            raise RuntimeError('BlueZ does not expose the optional Classic bearer preference.')
        say('Optional bearer preference unavailable; proceeding directly to A2DP.')
        return False
    current = run('bluetoothctl', 'bearer', mac, required=False, timeout=3)
    text = '' if current is None else current.stdout + current.stderr
    if not re.search(r'PreferredBearer:\s*bredr', text, re.I):
        if required:
            raise RuntimeError('BlueZ did not confirm a Classic bearer preference for this entry. A public identity address can still be LE-only. Do not treat it as a working audio entry; use Blueman Search while the buds are in pairing mode.')
        say('Optional bearer preference unavailable; requesting the A2DP profile directly (support still needs verification).')
        return False
    return True


def reconnect_classic(requested=None, discovered=False):
    listing = run('bluetoothctl', 'devices').stdout
    candidates = []
    control_links = []
    for line in listing.splitlines():
        match = re.match(r'Device ([0-9A-Fa-f:]{17}) (.*)', line)
        if not match:
            continue
        mac, name = match.groups()
        if requested and mac.lower() != requested.lower():
            continue
        if not requested and not re.search(r'(?:redmi|xiaomi)\s+buds\s*8\s*pro', name, re.I):
            continue
        info = run('bluetoothctl', 'info', mac).stdout
        if '(public)' in info or '0000110b-' in info.lower():
            candidates.append((mac, name, info))
        elif '(random)' in info and re.search(r'^\s*Connected: yes\s*$', info, re.M):
            control_links.append((mac, name))
    if len(candidates) > 1 and not requested:
        audio = [candidate for candidate in candidates if '0000110b-' in candidate[2].lower()]
        connected = [candidate for candidate in candidates if re.search(r'^\s*Connected: yes\s*$', candidate[2], re.M)]
        if len(audio) == 1:
            candidates = audio
        elif len(connected) == 1:
            candidates = connected
    if not candidates:
        if not discovered:
            if len(control_links) == 1:
                control_mac, control_name = control_links[0]
                say(f'Releasing the non-audio link for {control_name} ({control_mac}) before discovery.')
                run('bluetoothctl', 'disconnect', control_mac)
                current = run('bluetoothctl', 'info', control_mac, required=False)
                if current is None or current.returncode:
                    raise RuntimeError('Could not verify release of the control link; no discovery was started.')
                if re.search(r'^\s*Connected: yes\s*$', current.stdout, re.M):
                    raise RuntimeError('The control link is still connected; no competing scan or connection was started.')
            elif len(control_links) > 1:
                raise RuntimeError('Multiple named control links are connected. Specify the intended device; no connection was changed.')
            say('No public/audio earbud entry is currently known. Searching Classic Bluetooth once for 20 seconds.')
            say('For new-device discovery, both buds must be in the open case with the white pairing light flashing.')
            scan = run('bluetoothctl', '--timeout', '20', 'scan', 'bredr', required=False, timeout=25)
            if scan is None or scan.returncode or 'Failed to start discovery' in scan.stdout + scan.stderr:
                raise RuntimeError('Classic discovery failed. No audio connection or pairing was attempted; see the scan error in the log.')
            return reconnect_classic(requested, discovered=True)
        raise RuntimeError('No Classic audio candidate was discovered. The remembered battery/GATT entry cannot supply sound. Put both buds in the open case and hold its button 2 seconds until white flashes, then retry. No address was guessed or pairing record deleted.')
    if len(candidates) != 1:
        raise RuntimeError('Multiple public/audio earbud candidates exist. Use --device with the intended address; no device was changed.')
    mac, name, info = candidates[0]
    say(f'Checking Classic reconnection for {name} ({mac}).')
    set_classic_preference(mac, required=False)
    # BlueZ documents that a bearer change takes effect only after disconnecting.
    run('bluetoothctl', 'disconnect', mac, required=False)
    disconnected = run('bluetoothctl', 'info', mac).stdout
    if re.search(r'^\s*Connected: yes\s*$', disconnected, re.M):
        raise RuntimeError('The device did not disconnect. No competing reconnect request was started.')
    # BlueZ 5.87 connect_profile explicitly selects BDADDR_BREDR. Unlike
    # generic Connect, this does not depend on an experimental preference API.
    result = run('bluetoothctl', '--timeout', '25', 'connect', mac, 'a2dp-sink',
                 required=False, timeout=30)
    if result is not None:
        say((result.stdout + result.stderr).strip())
    current = run('bluetoothctl', 'info', mac, required=False)
    if current is None or current.returncode or 'not available' in current.stdout:
        raise RuntimeError('BlueZ removed or replaced the selected device during the audio connection attempt. Its public identity is no longer available; no audio output was verified. See the connection events and saved state.')
    info = current.stdout
    if not re.search(r'^\s*Connected: yes\s*$', info, re.M):
        raise RuntimeError('Classic reconnection failed; the exact BlueZ response is in the log.')
    if '0000110b-' not in info.lower():
        raise RuntimeError('Reconnection still exposes no Audio Sink service. A control link is not an audio repair. Put the buds into new-device pairing mode and use --pair-classic; see the saved BlueZ response.')
    return mac


def repair_audio(requested=None):
    mac, name, info = choose_device(requested)
    say(f'Checking {name} ({mac}).')
    say('Classic Audio Sink service: ' + ('advertised' if '0000110b-' in info.lower() else 'not advertised yet'))

    cards = [card for card in objects('cards') if belongs(card, mac)]
    if not cards and '0000110b-' not in info.lower():
        raise RuntimeError('This entry exposes no Classic audio service or PipeWire audio card. A public address or battery reading is insufficient. Try --prefer-classic, or new-device pairing with --pair-classic. No audio service restart was made for this entry.')
    if not any(belongs(sink, mac) for sink in objects('sinks')):
        say('Requesting the earbuds’ A2DP audio connection...')
        connection = run('bluetoothctl', 'connect', mac, 'a2dp-sink', required=False, timeout=25)
        if connection is not None:
            say((connection.stdout + connection.stderr).strip())

    card = None
    for _ in range(20):
        cards = [item for item in objects('cards') if belongs(item, mac)]
        if cards:
            card = cards[0]
            if a2dp_profile(card):
                break
        time.sleep(0.5)
    if card is None or a2dp_profile(card) is None:
        current = run('bluetoothctl', 'info', mac).stdout
        say(current)
        if '0000110b-' not in current.lower():
            raise RuntimeError('The connected Bluetooth entry advertises no classic Audio Sink service. It may be a Low Energy control/battery entry. Put the earbuds into new-device pairing mode and pair their audio entry; do not connect random unnamed devices.')
        raise RuntimeError('The earbuds advertise audio, but PipeWire has no usable A2DP card. The captured connection error and logs are needed; no output change was made.')

    profile = a2dp_profile(card)
    run('pactl', 'set-card-profile', card['name'], profile)
    sink = None
    for _ in range(20):
        sinks = [item for item in objects('sinks') if belongs(item, mac)]
        if sinks:
            sink = sinks[0]
            break
        time.sleep(0.5)
    if sink is None:
        raise RuntimeError('A2DP profile selected but no earbud audio output appeared. Check the saved log.')
    run('pactl', 'set-default-sink', sink['name'])
    run('pactl', 'set-sink-mute', sink['name'], '0')
    for stream in objects('sink-inputs'):
        run('pactl', 'move-sink-input', str(stream['index']), sink['name'], required=False)
    default = run('pactl', 'get-default-sink').stdout.strip()
    if default != sink['name']:
        raise RuntimeError('The default output did not switch to the earbuds.')
    say(f'VERIFIED: {name} has an audio output and is selected as the default.')
    say(f'Profile: {profile}. Play audio now to confirm sound in the earbuds.')

    return {"address": mac, "sink": sink["name"], "profile": profile}


def snapshot(mac):
    data = {}
    commands = {
        'bluez': ('bluetoothctl', 'info', mac) if mac else ('bluetoothctl', 'devices'),
        'cards': ('pactl', '--format=json', 'list', 'cards'),
        'sinks': ('pactl', '--format=json', 'list', 'sinks'),
        'bluetooth_log': ('journalctl', '-b', '-u', 'bluetooth', '--no-pager', '-n', '45'),
        'audio_log': ('journalctl', '--user', '-b', '-u', 'wireplumber', '--no-pager', '-n', '35'),
    }
    for name, command in commands.items():
        result = run(*command, required=False, timeout=5)
        data[name] = None if result is None else {
            'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
    for parent in Path('/sys/class/bluetooth/hci0').resolve().parents:
        if (parent / 'idVendor').is_file():
            data['usb'] = {'path': str(parent)}
            for field in ('idVendor', 'idProduct', 'power/control', 'power/runtime_status'):
                try:
                    data['usb'][field] = (parent / field).read_text().strip()
                except OSError:
                    pass
            break
    return data


def cycle_test(requested, count):
    report = {'requested_cycles': count, 'cycles': [], 'physical_sound_verified': False}
    destination = LOG.with_suffix('.cycles.json')
    # Stop at the first failed cycle: preserve its state instead of clearing it
    # with a radio reset, bond deletion, or audio-service restart.
    for number in range(1, count + 1):
        say(f'Automated reconnect cycle {number}/{count}')
        entry = {'cycle': number, 'passed': False}
        report['cycles'].append(entry)
        try:
            requested = reconnect_classic(requested)
            entry['audio'] = repair_audio(requested)
            entry['passed'] = True
        except (RuntimeError, ValueError, KeyError) as error:
            entry['error'] = str(error)
            say(f'Cycle {number} failed: {error}')
        finally:
            entry['snapshot'] = snapshot(requested)
            destination.write_text(json.dumps(report, indent=2) + '\n')
        if not entry['passed']:
            break
        if number < count:
            time.sleep(2)
    say(f'Cycle report saved: {destination}')
    if len(report['cycles']) != count or not all(entry['passed'] for entry in report['cycles']):
        raise RuntimeError(report['cycles'][-1].get('error', 'Not all reconnect cycles passed') + ' State saved; no pairing records or services were reset.')
    say(f'All {count} reconnect cycles produced a verified A2DP output.')
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', help='Explicit MAC address of your connected earbuds')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--pair-classic', action='store_true', help='Find and pair the Classic audio entry for REDMI Buds 8 Pro')
    mode.add_argument('--prefer-classic', '--reconnect-audio', action='store_true', help='Disconnect and explicitly reconnect A2DP; set Classic preference if supported')
    parser.add_argument('--forget-control', metavar='ADDRESS',
                        help='With --pair-classic, forget only this REDMI Buds 8 Pro control-only bond before scanning')
    parser.add_argument('--classic-address', metavar='ADDRESS',
                        help='With --pair-classic, open Classic service discovery at a known earbud address')
    parser.add_argument('--cycles', type=int, choices=range(1, 6), default=1, help='With --reconnect-audio, automatically verify 1–5 reconnect cycles')
    args = parser.parse_args()
    if args.cycles > 1 and not args.prefer_classic:
        parser.error('--cycles requires --reconnect-audio')
    if args.forget_control and not args.pair_classic:
        parser.error('--forget-control requires --pair-classic')
    if args.classic_address:
        if not args.pair_classic:
            parser.error('--classic-address requires --pair-classic')
        if not re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', args.classic_address):
            parser.error('--classic-address must be a Bluetooth MAC address')
        args.classic_address = args.classic_address.upper()
        if args.forget_control and args.classic_address == args.forget_control.upper():
            parser.error('The Classic and control addresses must be different')
    say(f'Audio repair log: {LOG}')
    # Preflight before any connection changes. A sandboxed run must stop here.
    run('pactl', 'info')
    run('bluetoothctl', 'list')
    if args.cycles > 1:
        cycle_test(args.device, args.cycles)
        return
    if args.pair_classic:
        args.device = pair_classic_redmi(args.forget_control, args.classic_address)
    elif args.prefer_classic:
        args.device = reconnect_classic(args.device)
    repair_audio(args.device)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, KeyError) as error:
        say('NOT FIXED: ' + str(error))
        say(f'Log saved to: {LOG}')
        raise SystemExit(1)
