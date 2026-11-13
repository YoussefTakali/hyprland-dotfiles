#!/usr/bin/env python3
"""Check on-demand overview startup."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

repo = Path(__file__).resolve().parents[1]


class OverviewTests(unittest.TestCase):
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
