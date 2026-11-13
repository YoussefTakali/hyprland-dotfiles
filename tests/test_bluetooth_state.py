#!/usr/bin/env python3
"""Regression checks for stale Bluetooth state and truthful audio/battery labels."""
import ast
import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parents[1] / 'config/hypr/UserScripts'
sys.path.insert(0, str(SCRIPTS))
from BluetoothState import ADAPTER, AUDIO_SINK, BATTERY, DEVICE, audio_outputs, battery_readings, control_only, merge_properties, status

class StateTests(unittest.TestCase):
    def setUp(self):
        self.path = '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF'
        self.props = {'Address': 'AA:BB:CC:DD:EE:FF', 'Name': 'Example earbuds',
                      'AddressType': 'public', 'Paired': True, 'Connected': True, 'UUIDs': [AUDIO_SINK]}
        self.sinks = [{'name': 'bluez_output.AA_BB_CC_DD_EE_FF.1'}]

    def test_disconnect_beats_cached_audio_sink(self):
        objects = {self.path: {DEVICE: self.props.copy()}}
        merge_properties(objects, self.path, DEVICE, {'Connected': False}, [])
        self.assertEqual(status(objects[self.path][DEVICE], True, self.sinks), 'Paired · disconnected')

    def test_power_off_beats_old_connected_property(self):
        self.assertEqual(status(self.props, False, self.sinks), 'Bluetooth off')

    def test_invalidated_connection_not_kept(self):
        objects = {self.path: {DEVICE: self.props.copy()}}
        merge_properties(objects, self.path, DEVICE, {}, ['Connected'])
        self.assertNotIn('Connected', objects[self.path][DEVICE])
        self.assertIn('disconnected', status(objects[self.path][DEVICE], True, self.sinks))

    def test_control_connection_is_not_audio(self):
        self.props.update(AddressType='random', UUIDs=['0000180f-0000-1000-8000-00805f9b34fb'])
        self.assertTrue(control_only(self.props))
        self.assertEqual(status(self.props, True, []), 'Control/battery link only · no audio')

    def test_le_audio_is_not_rejected_as_control(self):
        self.props.update(AddressType='random', UUIDs=['0000184e-0000-1000-8000-00805f9b34fb'])
        self.assertFalse(control_only(self.props))

    def test_audio_status_requires_matching_output(self):
        self.assertEqual(status(self.props, True, self.sinks), 'Audio output connected')
        self.assertIn('unavailable', status(self.props, True, [{'name': 'alsa_output.usb.headset'}]))

    def test_unknown_component_batteries_not_invented(self):
        objects = {self.path: {BATTERY: {'Percentage': 90}}}
        readings = battery_readings(objects, self.path)
        self.assertEqual([r['component'] for r in readings], ['aggregate'])
        self.assertIsNone(readings[0]['charging'])

    def test_component_and_empty_battery_values(self):
        objects = {self.path + '/battery_left': {BATTERY: {
            'Device': self.path, 'Identifier': 'left', 'Percentage': 0, 'Charging': False}},
            self.path + '/battery_right': {BATTERY: {'Device': self.path, 'Identifier': 'right'}}}
        readings = battery_readings(objects, self.path)
        self.assertEqual(readings[0]['percentage'], 0)
        self.assertIs(readings[0]['charging'], False)
        self.assertIsNone(readings[1]['percentage'])

if __name__ == '__main__':
    unittest.main()
