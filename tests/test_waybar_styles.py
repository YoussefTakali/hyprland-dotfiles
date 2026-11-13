#!/usr/bin/env python3
"""Catch GTK import failures when Waybar loads CSS through its public symlink."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk

REPO = Path(__file__).resolve().parents[1]
STYLES = REPO / 'config/waybar/style'

class GlassStyles(unittest.TestCase):
    def test_styles_load_through_symlink_outside_style_directory(self):
        for name in ('[Glass] Liquid Glass.css', '[Glass] Liquid Glass V2.css', '[Glass] Liquid Glass V3.css',
                     '[Ultimate] Glass Classic.css', '[Ultimate] Glass iPhone.css'):
            with self.subTest(style=name), tempfile.TemporaryDirectory() as directory:
                preview = Path(directory) / 'preview'
                preview.mkdir()
                (Path(directory) / 'waybar').symlink_to(STYLES.parent, target_is_directory=True)
                link = preview / 'style.css'
                link.symlink_to(STYLES / name)
                Gtk.CssProvider().load_from_path(str(link))

    def test_liquid_glass_selects_matching_layout_and_style(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            bar = home / '.config/waybar'
            bar.mkdir(parents=True)
            for name in ('configs', 'style'):
                (bar / name).symlink_to(STYLES.parent / name)
            (home / '.config/hypr/UserConfigs').mkdir(parents=True)
            env = dict(os.environ, HOME=directory, XDG_RUNTIME_DIR=directory, WAYBAR_SKIP_RELOAD='1')
            manager = REPO / 'config/hypr/scripts/WaybarMode.sh'
            for option, value in (('--style', '[Glass] Liquid Glass V2'), ('--layout', '[TOP] Liquid Glass V3')):
                subprocess.run(['bash', manager, option, value], env=env, check=True)
                version = value.rsplit(' ', 1)[1]
                self.assertEqual((bar / 'config').resolve().name, f'[TOP] Liquid Glass {version}')
                self.assertEqual((bar / 'style.css').resolve().name, f'[Glass] Liquid Glass {version}.css')


if __name__ == '__main__':
    unittest.main()
