#!/usr/bin/env python3
"""Reject black/normal frames; check the verifier's failure/blocked behavior."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location("live_verify", Path(__file__).resolve().parents[1] / "tools/session/verify-loading-live.py")
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class CaptureChecks(unittest.TestCase):
    def test_badge_requires_its_actual_bright_glyphs_not_just_a_dark_rectangle(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            normal = Image.new("RGB", (320, 180), "#bd6b24")
            waiting = normal.copy()
            draw = ImageDraw.Draw(waiting)
            draw.rectangle((30, 120, 290, 165), fill="#15131e")
            draw.text((50, 130), "Starting your desktop...", fill="white")
            normal.save(path/"wallpaper.qoi")
            (path/"pixels.bgrx").write_bytes(waiting.tobytes("raw", "BGRX"))
            waiting.save(path/"waiting.png")
            normal.save(path/"normal.png")
            Image.new("RGB", normal.size, "black").save(path/"black.png")
            for file, valid in (("waiting.png", True), ("normal.png", False), ("black.png", False)):
                with self.subTest(file=file):
                    result = verify.visible_badge(path/file, path/"pixels.bgrx", path/"wallpaper.qoi", normal.size)
                    self.assertEqual(result["visible"], valid, result)

    def test_static_indicator_is_not_accepted_as_animation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            first = Image.new("RGB", (320, 180), "#15131e")
            second = first.copy()
            ImageDraw.Draw(second).rectangle((155, 130, 165, 140), fill="white")
            first.save(path/"first.png"); second.save(path/"second.png")
            self.assertFalse(verify.animation_changed(path/"first.png", path/"first.png", first.size)["animated"])
            self.assertTrue(verify.animation_changed(path/"first.png", path/"second.png", first.size)["animated"])

    def test_access_failure_stops_before_starting_a_client(self):
        denied = subprocess.CompletedProcess([], 1, "", "Operation not permitted")
        with patch.object(verify, "command", return_value=denied), patch.object(verify.subprocess, "Popen") as start:
            with self.assertRaisesRegex(verify.Blocked, "Cannot access"):
                verify.preflight({}, Path("/nonexistent"))
        start.assert_not_called()


if __name__ == "__main__":
    unittest.main()
