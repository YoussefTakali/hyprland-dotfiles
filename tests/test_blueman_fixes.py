#!/usr/bin/env python3
"""Exercise installed Blueman service callbacks without a display or Bluetooth."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import sys
sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('blueman_fixes', Path(__file__).resolve().parents[1] / 'config/hypr/UserScripts/BluemanFixes.py')
fixes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixes)
import blueman.plugins.manager.Services as services
import blueman.gui.manager.ManagerDeviceMenu as menu_module
ORIGINAL = services.Services.on_request_menu_items

class Item:
    def __init__(self, *args, **kwargs):
        self.props = SimpleNamespace()
        self.callback = None
    def connect(self, signal, callback): self.callback = callback
    def show(self): pass

class Config(dict):
    def __init__(self): super().__init__(services=[])
    def bind_to_menuitem(self, *args): pass


def callbacks(method):
    fake_services = [SimpleNamespace(device=f'device-{i}', uuid=f'uuid-{i}', name=f'service-{i}',
        icon='audio', description='', available=True, connectable=True, priority=i,
        connected_instances=[SimpleNamespace(name='connected', port=10+i)], common_actions=[])
        for i in range(2)]
    connected, disconnected = [], []
    manager = SimpleNamespace(connect_service=lambda *args: connected.append(args),
                              disconnect_service=lambda *args: disconnected.append(args))
    plugin = object.__new__(services.Services)
    plugin._make_x_icon = lambda *args: None
    with patch.object(services, 'get_services', return_value=fake_services), \
         patch.object(services, 'AppletService'), patch.object(services, 'AutoConnectConfig', Config), \
         patch.object(services, 'create_menuitem', side_effect=Item), \
         patch.object(services.Gtk, 'CheckMenuItem', Item):
        items = method(plugin, manager, {'Address':'AA:BB:CC:DD:EE:FF'}, True)
        for entry in items:
            if entry.group in (menu_module.DeviceMenuItem.Group.CONNECT, menu_module.DeviceMenuItem.Group.DISCONNECT):
                entry.item.callback(None)
    return connected, disconnected

class ServiceCallbacks(unittest.TestCase):
    def test_original_installed_bug_is_reproduced(self):
        connected, disconnected = callbacks(ORIGINAL)
        self.assertEqual(connected[0], ('device-1', 'uuid-1'))
        self.assertEqual(disconnected[0], ('device-1', 'uuid-1', 11))

    def test_patched_actions_keep_the_clicked_service_and_port(self):
        self.assertEqual(fixes.apply_fixes(), [True, True])
        connected, disconnected = callbacks(services.Services.on_request_menu_items)
        self.assertEqual(connected, [('device-0','uuid-0'),('device-1','uuid-1')])
        self.assertEqual(disconnected, [('device-0','uuid-0',10),('device-1','uuid-1',11)])

if __name__ == '__main__':
    unittest.main()
