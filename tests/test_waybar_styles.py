#!/usr/bin/env python3
"""Catch GTK import failures when Waybar loads CSS through its public symlink."""
from pathlib import Path
import tempfile
import unittest

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk

STYLES = Path(__file__).resolve().parents[1] / 'config/waybar/style'

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

if __name__ == '__main__':
    unittest.main()
