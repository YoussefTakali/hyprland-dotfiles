"""Keep the stock login preset available in checkouts without personal media."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("login_themes", REPO / "config/hypr/scripts/LoginThemes.py")
login_themes = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(login_themes)
SPEC = importlib.util.spec_from_file_location("greeter", REPO / "installer/session/repair-greeter-handoff.py")
greeter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(greeter)


class LoginThemesTests(unittest.TestCase):
    def test_install_uses_stock_jake_and_skips_missing_optional_media(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            assets = root / "catalogue"
            assets.mkdir()
            (assets / "catalog.json").write_bytes((REPO / "home/login-themes/catalog.json").read_bytes())
            theme = root / "astronaut"
            for name in ("Themes", "Backgrounds", "Components"):
                (theme / name).mkdir(parents=True)
            (theme / "Themes/jake_the_dog.conf").write_text("[General]\n")
            main = theme / "Main.qml"
            main.write_text("Item {\n    focus: true\n}\n")
            fields = theme / "Components/Input.qml"
            fields.write_text("    function triggerLogin() {\n"
                              "        sddm.login(targetUser, password.text, sessionSelect.selectedSession)\n"
                              "        function onLoginFailed() {\n")
            (theme / "metadata.desktop").write_text("ConfigFile=Themes/old.conf\n")
            video = theme / "Backgrounds/jake_the_dog.mp4"
            poster = theme / "Backgrounds/jake_the_dog.png"
            video.write_bytes(b"stock video")
            poster.write_bytes(b"stock poster")

            greeter.prepare_theme(theme)
            self.assertIn("JakeLoadingScene {", main.read_text())
            self.assertIn("root.startLoading()", fields.read_text())
            self.assertIn("root.stopLoading()", fields.read_text())
            self.assertEqual((theme / "Components/jake.png").read_bytes(), poster.read_bytes())
            with patch.object(login_themes, "THEME", theme), patch.object(login_themes, "commit") as commit:
                login_themes.system_install(assets)
            changes = commit.call_args.args[0]
            self.assertEqual(changes[theme / "Backgrounds/preset-jake.mp4"], video.read_bytes())
            self.assertEqual(changes[theme / "Backgrounds/preset-jake.png"], poster.read_bytes())
            self.assertIn(theme / "Themes/preset-jake.conf", changes)
            self.assertFalse(any("itachi" in path.name for path in changes))

    def test_optional_theme_requires_both_files(self):
        with tempfile.TemporaryDirectory() as temp:
            assets = Path(temp)
            catalog = json.loads((REPO / "home/login-themes/catalog.json").read_text())
            key = "itachi-eyes"
            video, poster = (assets / catalog[key][field] for field in ("video", "poster"))
            self.assertIsNone(login_themes.preset_media(assets, catalog, key))
            video.touch()
            self.assertIsNone(login_themes.preset_media(assets, catalog, key))
            poster.touch()
            self.assertEqual(login_themes.preset_media(assets, catalog, key), (video, poster))


if __name__ == "__main__":
    unittest.main()
