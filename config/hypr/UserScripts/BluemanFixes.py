#!/usr/bin/env python3
"""Scoped patches for Blueman 2.4.x; keep Fedora's UI and system files intact.

Patch installed source only when its exact known-bug patterns match. Fedora
updates that change these methods are left alone. Never alter radio/pairing state
merely by starting the UI.
"""
import inspect
import logging
import runpy
import textwrap


def patched_method(module, cls, name, replacements):
    original = getattr(cls, name)
    source = textwrap.dedent(inspect.getsource(original))
    for before, after in replacements:
        if source.count(before) != 1:
            logging.warning('Blueman patch skipped: %s.%s has changed upstream', cls.__name__, name)
            return False
        source = source.replace(before, after, 1)
    namespace = {}
    exec(compile(source, '<local Blueman fix: ' + name + '>', 'exec'), vars(module), namespace)
    setattr(cls, name, namespace[name])
    logging.info('Applied Blueman fix: %s.%s', cls.__name__, name)
    return True


def apply_fixes():
    import blueman.plugins.manager.Services as services
    import blueman.gui.manager.ManagerDeviceMenu as menu
    results = []
    results.append(patched_method(services, services.Services, 'on_request_menu_items', [
        ('lambda _item: manager_menu.connect_service(service.device, service.uuid)',
         'lambda _item, service=service: manager_menu.connect_service(service.device, service.uuid)'),
        ('lambda _item: manager_menu.disconnect_service(service.device, service.uuid, instance.port)',
         'lambda _item, service=service, port=instance.port: manager_menu.disconnect_service(service.device, service.uuid, port)'),
    ]))
    results.append(patched_method(menu, menu.ManagerDeviceMenu, 'generate', [
        ('show_generic_connect = self.show_generic_connect_calc(self.SelectedDevice[\'UUIDs\'])',
         'show_generic_connect = bool(row["connected"]) or self.show_generic_connect_calc(self.SelectedDevice[\'UUIDs\'])'),
    ]))
    return results


def main():
    # Configure before Blueman's entry point so patch application failures are logged.
    logging.basicConfig(level=logging.INFO)
    try:
        apply_fixes()
    except (ImportError, OSError, SyntaxError, AttributeError, TypeError):
        logging.exception('Local patches unavailable; opening stock Blueman')
    runpy.run_path('/usr/bin/blueman-manager', run_name='__main__')


if __name__ == '__main__':
    main()
