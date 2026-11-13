#!/usr/bin/env python3
"""Check safe SDDM mode matching and on-demand overview startup."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sddm_display", repo / "installer/session/sddm-display-setup.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LoginAndOverviewTests(unittest.TestCase):
    def test_match_supported_display_mode(self):
        query = """Screen 0: minimum 8 x 8, current 2560 x 1440, maximum 32767 x 32767
HDMI-0 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis)
   2560x1440     59.95*+  99.95  84.98
   1920x1080     60.00
DP-0 disconnected (normal left inverted right x axis y axis)
"""
        assert module.select_mode(query, 2560, 1440, 99.95) == [
            "/usr/bin/xrandr", "--output", "HDMI-0", "--mode", "2560x1440", "--rate", "99.95"]
        assert module.select_mode(query.replace("59.95*+  99.95", "59.95+  99.95*"), 2560, 1440, 99.95) is None
        assert module.select_mode(query, 2560, 1440, 144) is None
        assert module.select_mode(query.replace("DP-0 disconnected", "DP-0 connected"), 2560, 1440, 99.95) is None
        assert module.select_mode(query, 3840, 2160, 99.95) is None

    def test_overview_startup_is_on_demand(self):
        with tempfile.TemporaryDirectory(prefix="overview-startup-check-") as tmp:
            home = Path(tmp)
            (home / "qs").write_text('''#!/bin/sh
printf '%s\n' "$*" >> "$HOME/calls"
case "$1" in
  ipc) test -f "$HOME/ready";;
  -c) touch "$HOME/ready";;
esac
''')
            (home / "qs").chmod(0o755)
            env = dict(os.environ, HOME=tmp, PATH=tmp + ":" + os.environ["PATH"])
            script = repo / "config/hypr/scripts/OverviewToggle.sh"
            subprocess.run(["bash", str(script)], env=env, timeout=5, check=True)
            assert (home / "calls").read_text().splitlines().count("-c overview") == 1
            (home / "calls").unlink()
            subprocess.run(["bash", str(script)], env=env, timeout=5, check=True)
            assert (home / "calls").read_text().splitlines() == ["ipc -c overview call overview toggle"]


if __name__ == "__main__":
    unittest.main()
