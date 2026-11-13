#!/usr/bin/env python3
"""A wallpaper refresh must never terminate other Quickshell components."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class RefreshSafety(unittest.TestCase):
    def exercise(self, active):
        for name in ('Refresh.sh', 'RefreshNoWaybar.sh'):
            with self.subTest(script=name), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                stubs = home/'stubs'
                stubs.mkdir()
                for command in ('pkill','killall','setsid','waybar','swaync','swaync-client','sleep'):
                    path = stubs/command
                    path.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$HOME/calls"\n')
                    path.chmod(0o755)
                (stubs/'pgrep').write_text('#!/bin/sh\ncase "$*" in *"[q]s -c overview"*) test -f "$HOME/active";; *) exit 1;; esac\n')
                (stubs/'pidof').write_text('#!/bin/sh\nexit 1\n')
                for path in stubs.iterdir():path.chmod(0o755)
                scripts = home/'.config/hypr/scripts'
                scripts.mkdir(parents=True)
                (scripts/'WallustSwww.sh').write_text('#!/bin/sh\nexit 0\n')
                (scripts/'WallustSwww.sh').chmod(0o755)
                if active:(home/'active').touch()
                subprocess.run(['bash',str(REPO/'config/hypr/scripts'/name)],
                               env=dict(os.environ, HOME=directory, PATH=str(stubs)+':'+os.environ['PATH']),
                               capture_output=True, timeout=5, check=True)
                calls = (home/'calls').read_text()
                self.assertNotIn('pkill qs\n', calls)
                self.assertNotIn('killall qs\n', calls)
                if active:
                    self.assertIn('-f [q]s -c overview', calls)
                    self.assertIn('setsid -f qs -c overview', calls)
                else:
                    self.assertNotIn('qs -c overview', calls)

    def test_inactive_overview_stays_on_demand(self):self.exercise(False)
    def test_active_overview_is_the_only_quickshell_restart(self):self.exercise(True)


if __name__ == '__main__':
    unittest.main()
