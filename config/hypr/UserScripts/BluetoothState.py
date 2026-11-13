"""Pure Bluetooth state helpers; no guessed battery values or hardware calls."""
import re

DEVICE = 'org.bluez.Device1'
ADAPTER = 'org.bluez.Adapter1'
BATTERY = 'org.bluez.Battery1'
AUDIO_SINK = '0000110b-0000-1000-8000-00805f9b34fb'
AUDIO_SERVICES = {AUDIO_SINK, '00001108-0000-1000-8000-00805f9b34fb',
    '0000111e-0000-1000-8000-00805f9b34fb', '0000184e-0000-1000-8000-00805f9b34fb',
    '00001850-0000-1000-8000-00805f9b34fb'}

def has_audio_service(props):
    return bool(AUDIO_SERVICES.intersection(str(value).lower() for value in props.get('UUIDs', [])))

def address_key(value):
    return str(value).upper().replace(':', '_')

def audio_outputs(sinks, address):
    key = address_key(address)
    return [sink for sink in sinks if key and any(key in address_key(value) for value in (
        sink.get('name', ''), sink.get('properties', {}).get('api.bluez5.address', ''),
        sink.get('properties', {}).get('device.string', ''),
    ))]

def control_only(props):
    name = str(props.get('Name', props.get('Alias', '')))
    return bool(re.search(r'buds|earbuds|headphones', name, re.I)
                and props.get('AddressType') == 'random'
                and not has_audio_service(props))

def battery_readings(objects, device_path):
    readings = []
    for path, interfaces in objects.items():
        props = interfaces.get(BATTERY)
        if props is None or not (path == device_path or props.get('Device') == device_path):
            continue
        level = props.get('Percentage')
        readings.append({'component': props.get('Identifier', 'aggregate'),
            'percentage': level if isinstance(level, int) and not isinstance(level, bool) and 0 <= level <= 100 else None,
            'charging': props.get('Charging') if isinstance(props.get('Charging'), bool) else None,
            'source': props.get('Source'), 'path': path})
    return readings

def status(props, powered, sinks):
    if not powered:
        return 'Bluetooth off'
    if not props.get('Connected', False):
        return 'Paired · disconnected' if props.get('Paired') else 'Not connected'
    if audio_outputs(sinks, props.get('Address', '')):
        return 'Audio output connected'
    if control_only(props):
        return 'Control/battery link only · no audio'
    if has_audio_service(props):
        return 'Bluetooth connected · audio output unavailable'
    return 'Bluetooth link connected'

def merge_properties(objects, path, interface, changed, invalidated):
    values = objects.setdefault(path, {}).setdefault(interface, {})
    values.update(changed)
    for key in invalidated:
        values.pop(key, None)
