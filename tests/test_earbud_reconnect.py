#!/usr/bin/env python3
"""Verify bearer handling without changing a physical Bluetooth connection."""
import importlib.util
import json
import tempfile
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('repair', Path(__file__).resolve().parents[1] / 'tools/bluetooth/repair-earbud-audio.py')
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)
MAC = '02:00:00:00:00:01'


class ControlBondTests(unittest.TestCase):
    address = 'F8:53:84:DD:74:4D'
    info = f'Device {address} (random)\n  Name: REDMI Buds 8 Pro\n  Bonded: yes\n'

    def test_forget_checks_that_the_bond_is_gone(self):
        responses = [
            subprocess.CompletedProcess([], 0, self.info, ''),
            subprocess.CompletedProcess([], 0, 'Device has been removed', ''),
            subprocess.CompletedProcess([], 0, '', ''),
        ]
        with patch.object(repair, 'run', side_effect=responses) as run, patch.object(repair, 'say'):
            repair.forget_control_link(self.address.lower())
        self.assertEqual(run.call_args_list[1].args, ('bluetoothctl', 'remove', self.address))
        self.assertEqual(run.call_args_list[2].args, ('bluetoothctl', 'devices', 'Bonded'))

    def test_forget_preserves_audio_bonds_and_unrelated_devices(self):
        for info in (self.info.replace('(random)', '(public)'),
                     self.info.replace('REDMI Buds 8 Pro', 'Other headphones'),
                     self.info.replace('Bonded: yes', 'Bonded: no'),
                     self.info + '  UUID: Audio Sink (0000110b-0000-1000-8000-00805f9b34fb)\n',
                     self.info + '  UUID: Published Audio Capabilities (00001850-0000-1000-8000-00805f9b34fb)\n'):
            with self.subTest(info=info), patch.object(repair, 'run', return_value=
                    subprocess.CompletedProcess([], 0, info, '')) as run:
                with self.assertRaisesRegex(RuntimeError, 'Nothing was forgotten'):
                    repair.forget_control_link(self.address)
                run.assert_called_once_with('bluetoothctl', 'info', self.address)


class DirectClassicTests(unittest.TestCase):
    def test_sdp_connection_targets_classic_psm_and_checks_device_identity(self):
        info = f'Device {MAC} (public)\n  Name: REDMI Buds 8 Pro\n'
        with patch.object(repair.socket, 'socket') as socket, patch.object(repair, 'say'), \
                patch.object(repair, 'run', return_value=subprocess.CompletedProcess([], 0, info, '')):
            self.assertEqual(repair.direct_classic_candidate(MAC), (MAC, 'REDMI Buds 8 Pro', info))
        socket.return_value.__enter__.return_value.connect.assert_called_once_with((MAC, 1))

    def test_direct_connection_to_another_device_never_pairs(self):
        info = f'Device {MAC} (public)\n  Name: Another device\n'
        with patch.object(repair.socket, 'socket'), patch.object(repair, 'say'), \
                patch.object(repair.sys.stdin, 'isatty', return_value=False), \
                patch.object(repair.time, 'sleep'), \
                patch.object(repair, 'run', return_value=subprocess.CompletedProcess([], 0, info, '')) as run:
            with self.assertRaisesRegex(RuntimeError, 'No pairing was attempted'):
                repair.pair_classic_redmi(classic_address=MAC)
        self.assertTrue(all(call.args == ('bluetoothctl', 'info', MAC) for call in run.call_args_list))


class ReconnectTests(unittest.TestCase):
    def exercise(self, preference, audio=False, stuck=False, resolved=True):
        calls = []
        info_calls = 0
        def run(*args, **kwargs):
            nonlocal info_calls
            calls.append(args)
            text = ''
            if args[1] == 'devices':
                text = f'Device {MAC} REDMI Buds 8 Pro\n'
            elif args[1] == 'info':
                info_calls += 1
                connected = info_calls != 2 or stuck
                text = f'Device {MAC} (public)\n  Connected: {"yes" if connected else "no"}\n'
                if audio or (info_calls >= 3 and resolved):
                    text += '  UUID: Audio Sink (0000110b-0000-1000-8000-00805f9b34fb)\n'
            elif args[1] == 'bearer' and len(args) == 3 and preference:
                text = 'PreferredBearer: bredr\n'
            return subprocess.CompletedProcess(args, 0, text, '')
        with patch.object(repair, 'run', side_effect=run), patch.object(repair, 'say'):
            try:
                value = repair.reconnect_classic(MAC)
            except RuntimeError:
                return calls, False
            return calls, value == MAC

    def test_public_identity_without_audio_never_claimed_success(self):
        calls, success = self.exercise(False, resolved=False)
        self.assertFalse(success)
        self.assertTrue(any(c[-1] == 'a2dp-sink' for c in calls))

    def test_public_identity_can_resolve_classic_audio_without_experimental_api(self):
        calls, success = self.exercise(False)
        self.assertTrue(success)
        self.assertTrue(any(c[-1] == 'a2dp-sink' for c in calls))

    def test_confirmed_preference_disconnects_before_connect(self):
        calls, success = self.exercise(True)
        self.assertTrue(success)
        disconnect = calls.index(('bluetoothctl', 'disconnect', MAC))
        connect = next(i for i,c in enumerate(calls) if 'connect' in c)
        self.assertLess(disconnect, connect)
        self.assertEqual(calls[disconnect+1], ('bluetoothctl', 'info', MAC))

    def test_known_a2dp_works_without_optional_experimental_preference(self):
        calls, success = self.exercise(False, audio=True)
        self.assertTrue(success)
        self.assertTrue(any(c[-1] == 'a2dp-sink' for c in calls))

    def test_only_le_entry_triggers_one_classic_scan_and_no_wrong_connection(self):
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            output = ''
            if args[1] == 'devices':
                output = 'Device F8:53:84:DD:74:4D REDMI Buds 8 Pro\n'
            elif args[1] == 'info':
                output = 'Device F8:53:84:DD:74:4D (random)\n  UUID: Battery Service (0000180f-0000-1000-8000-00805f9b34fb)\n'
            return subprocess.CompletedProcess(args, 0, output, '')
        with patch.object(repair, 'run', side_effect=run), patch.object(repair, 'say'):
            with self.assertRaisesRegex(RuntimeError, 'No Classic audio candidate was discovered'):
                repair.reconnect_classic()
        self.assertEqual(sum('scan' in call for call in calls), 1)
        self.assertFalse(any('connect' in call or 'pair' in call or 'remove' in call for call in calls))

    def test_control_link_is_released_before_scan_and_failure_is_not_retried_forever(self):
        calls = []
        connected = True
        def run(*args, **kwargs):
            nonlocal connected
            calls.append(args)
            output = ''
            if args[1] == 'devices':
                output = 'Device F8:53:84:DD:74:4D REDMI Buds 8 Pro\n'
            elif args[1] == 'info':
                output = 'Device F8:53:84:DD:74:4D (random)\n  Connected: '+('yes' if connected else 'no')+'\n'
            elif args[1] == 'disconnect':
                connected = False
            return subprocess.CompletedProcess(args, 0, output, '')
        with patch.object(repair, 'run', side_effect=run), patch.object(repair, 'say'):
            with self.assertRaisesRegex(RuntimeError, 'No Classic audio candidate was discovered'):
                repair.reconnect_classic()
        disconnect = calls.index(('bluetoothctl','disconnect','F8:53:84:DD:74:4D'))
        scan = next(i for i,c in enumerate(calls) if 'scan' in c)
        self.assertLess(disconnect, scan)
        self.assertEqual(sum('scan' in c for c in calls), 1)
        self.assertFalse(any('pair' in c or 'remove' in c for c in calls))

    def test_unknown_preference_never_queries_the_missing_property(self):
        error = subprocess.CompletedProcess([], 1, 'Failed to set bredr: org.freedesktop.DBus.Error.UnknownProperty', '')
        with patch.object(repair, 'run', return_value=error) as run, patch.object(repair, 'say'):
            self.assertFalse(repair.set_classic_preference(MAC, required=False))
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.kwargs['timeout'], 3)

    def test_failed_disconnect_does_not_start_competing_connect(self):
        calls, success = self.exercise(True, stuck=True)
        self.assertFalse(success)
        self.assertFalse(any('connect' in c for c in calls))


class CycleTests(unittest.TestCase):
    def test_multiple_cycles_keep_one_identity_and_verify_output_each_time(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(repair, 'LOG', Path(directory)/'test.log'), \
             patch.object(repair, 'reconnect_classic', return_value=MAC) as connect, \
             patch.object(repair, 'repair_audio', return_value={'sink':'bluez_output.test'}) as audio, \
             patch.object(repair, 'snapshot', return_value={}), \
             patch.object(repair.time, 'sleep'), patch.object(repair, 'say'):
            report = repair.cycle_test(None, 3)
            self.assertEqual(connect.call_count, 3)
            self.assertEqual(connect.call_args_list[1].args, (MAC,))
            self.assertEqual(audio.call_count, 3)
            self.assertTrue(all(item['passed'] for item in report['cycles']))
            self.assertFalse(report['physical_sound_verified'])

    def test_second_connection_failure_is_preserved_without_more_attempts(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(repair, 'LOG', Path(directory)/'test.log'), \
             patch.object(repair, 'reconnect_classic', side_effect=[MAC, RuntimeError('page timeout')]) as connect, \
             patch.object(repair, 'repair_audio', return_value={'sink':'bluez_output.test'}), \
             patch.object(repair, 'snapshot', return_value={'state':'failure preserved'}), \
             patch.object(repair.time, 'sleep'), patch.object(repair, 'say'):
            with self.assertRaises(RuntimeError):
                repair.cycle_test(MAC, 3)
            report = json.loads((Path(directory)/'test.cycles.json').read_text())
            self.assertEqual(connect.call_count, 2)
            self.assertEqual(len(report['cycles']), 2)
            self.assertTrue(report['cycles'][0]['passed'])
            self.assertFalse(report['cycles'][1]['passed'])
            self.assertEqual(report['cycles'][1]['snapshot']['state'], 'failure preserved')

    def test_missing_audio_output_is_a_failed_cycle_even_if_bluetooth_connected(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(repair, 'LOG', Path(directory)/'test.log'), \
             patch.object(repair, 'reconnect_classic', return_value=MAC) as connect, \
             patch.object(repair, 'repair_audio', side_effect=RuntimeError('no audio card')), \
             patch.object(repair, 'snapshot', return_value={}), patch.object(repair, 'say'):
            with self.assertRaises(RuntimeError):
                repair.cycle_test(None, 3)
            self.assertEqual(connect.call_count, 1)

class ClassicModeConfigTests(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location('classic_mode', Path(__file__).resolve().parents[1] / 'tools/bluetooth/classic-transport.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_preserves_unrelated_configuration_and_is_idempotent(self):
        module = self.module()
        original = '# comment\n[General]\nControllerMode=dual\nName=keep\n[Policy]\nAutoEnable=true\n'
        changed = module.classic_config(original)
        self.assertIn('ControllerMode = bredr', changed)
        self.assertIn('Name=keep\n[Policy]\nAutoEnable=true\n', changed)
        self.assertEqual(module.classic_config(changed), changed)

    def test_failed_restart_rolls_back_original_file(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)/'main.conf'
            config.write_text('[General]\nName=keep\n')
            original = config.read_bytes()
            restarts = 0
            def run(args, **kwargs):
                nonlocal restarts
                if args[:2] == ['systemctl', 'restart']:
                    restarts += 1
                    if restarts == 1:
                        raise subprocess.CalledProcessError(1, args)
                return subprocess.CompletedProcess(args,0)
            with patch.object(module, 'CONFIG', config), patch.object(module, 'STATE', Path(directory)/'state'), \
                 patch.object(module.os, 'geteuid', return_value=0), \
                 patch.object(module.subprocess, 'run', side_effect=run), \
                 patch.object(sys, 'argv', ['test-bluetooth-classic.py','--apply']):
                with self.assertRaises(subprocess.CalledProcessError):
                    module.main()
            self.assertEqual(config.read_bytes(), original)
            self.assertFalse((Path(directory)/'state/state.json').exists())

if __name__ == '__main__':
    unittest.main()
