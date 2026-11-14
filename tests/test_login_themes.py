"""Login screen: the Hypr Login Styles theme, its settings script and root helper."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
THEME_SOURCE = REPO / "installer/session/hypr-login-styles"


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


login_themes = load("login_themes", REPO / "config/hypr/scripts/LoginThemes.py")
greeter = load("greeter", REPO / "installer/session/prepare-sddm-theme.py")
helper = load("sddm_login_theme", REPO / "installer/session/sddm-login-theme")


def config_values(text):
    return dict(re.findall(r'^(\w+)="([^"]*)"$', text, re.M))


class ThemeSourceTests(unittest.TestCase):
    def test_every_layout_has_its_qml(self):
        metadata = (THEME_SOURCE / "metadata.desktop").read_text()
        self.assertIn("ConfigFile=Desktop/login.conf", metadata)
        self.assertTrue((THEME_SOURCE / "Main.qml").is_file())
        for key, (style, _) in login_themes.LAYOUTS.items():
            if key == "japanese":   # hosted from sddm-astronaut by Main.qml
                self.assertIn("sddm-astronaut-theme/Main.qml", (THEME_SOURCE / "Main.qml").read_text())
            else:
                self.assertTrue((THEME_SOURCE / f"styles/{style}.qml").is_file(), style)
            self.assertIn(login_themes.DEFAULT_POSITION[key], login_themes.POSITIONS)

    def test_helper_only_copies_theme_files(self):
        names = [p.name for p in THEME_SOURCE.rglob("*") if p.is_file()]
        for name in names:
            self.assertTrue(name == "metadata.desktop" or helper.QML.fullmatch(name), name)


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix="login-themes-test-"))
        self.addCleanup(shutil.rmtree, self.temp)
        japanese = self.temp / "japanese_aesthetic.conf"
        japanese.write_text('[General]\nFont="Electroharmonix"\nBackground="Backgrounds/japanese_aesthetic.png"\n'
                            'HaveFormBackground="false"\nFormPosition="left"\n')
        palette = self.temp / "wallust-hyprland.conf"
        palette.write_text("$background = rgb(202121)\n$foreground = rgb(EDE4D6)\n"
                           + "".join(f"$color{i} = rgb({i:02X}{i:02X}{i:02X})\n" for i in range(16)))
        self.patches = [patch.object(login_themes, name, value) for name, value in {
            "SETTINGS": self.temp / "login-screen.json", "JAPANESE": japanese, "PALETTE": palette,
            "OUT": self.temp / "theme/Desktop", "CACHE": self.temp / "cache",
            "WALL": self.temp / "wallpaper", "LIVE": self.temp / "live", "ARTWORK": self.temp / "artwork.png",
        }.items()]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def test_defaults_and_per_layout_choices(self):
        settings = login_themes.load()
        self.assertEqual(login_themes.background_choice(settings, "tiles"), "desktop")
        self.assertEqual(login_themes.background_choice(settings, "japanese"), "artwork")
        self.assertEqual(login_themes.position_choice(settings, "tiles"), "right")
        settings["positions"]["tiles"] = "center"
        self.assertEqual(login_themes.position_choice(settings, "tiles"), "center")
        self.assertEqual(login_themes.position_choice(settings, "rofi"), "center")

    def test_presets_round_trip(self):
        settings = login_themes.load()
        settings.update(layout="editorial", colors="desktop")
        settings["backgrounds"]["editorial"] = "/pictures/garden.png"
        settings["positions"]["editorial"] = "right"
        login_themes.save_preset(settings, "Garden")
        settings.update(layout="tiles", colors="background")
        login_themes.apply_preset(settings, "Garden")
        self.assertEqual(settings["layout"], "editorial")
        self.assertEqual(settings["colors"], "desktop")
        self.assertEqual(login_themes.background_choice(settings, "editorial"), "/pictures/garden.png")
        self.assertEqual(login_themes.position_choice(settings, "editorial"), "right")
        login_themes.save(settings)
        self.assertIn("Garden", json.loads(login_themes.SETTINGS.read_text())["presets"])

    def test_japanese_keeps_its_keys_and_takes_position(self):
        palette = login_themes.desktop_palette()
        login_themes.ARTWORK.write_bytes(b"art")
        values = config_values(login_themes.config_text("japanese", str(login_themes.ARTWORK), "", palette, "center"))
        self.assertEqual(values["Style"], "Japanese")
        self.assertEqual(values["Font"], "Electroharmonix")
        self.assertEqual(values["FormPosition"], "center")
        self.assertEqual(values["HaveFormBackground"], "false")   # the original look on its artwork
        values = config_values(login_themes.config_text("japanese", "/pictures/street.jpg", "", palette, "left"))
        self.assertEqual(values["HaveFormBackground"], "true")    # cream panel on any other picture
        self.assertEqual(values["Background"], "/pictures/street.jpg")

    def test_layout_config_has_palette_and_position(self):
        values = config_values(login_themes.config_text("bar", "/b.jpg", "", login_themes.desktop_palette(), "right"))
        self.assertEqual((values["Style"], values["Position"]), ("Bar", "right"))
        self.assertEqual(values["ColorBackground"], "#202121")
        self.assertEqual(values["Color15"], "#0f0f0f")

    def test_sync_follows_the_wallpaper_and_cleans_old_media(self):
        from PIL import Image
        login_themes.OUT.mkdir(parents=True)
        Image.new("RGB", (64, 36), "red").save(login_themes.WALL, format="PNG")
        settings, source = login_themes.sync()
        first = config_values((login_themes.OUT / "login.conf").read_text())["Background"]
        self.assertEqual(source, login_themes.WALL)
        self.assertTrue(Path(first).is_file())
        (login_themes.OUT / "style-tiles.conf").write_text("from an older version")
        Image.new("RGB", (64, 36), "blue").save(login_themes.WALL, format="PNG")
        os.utime(login_themes.WALL, ns=(1, 1))   # a different file signature, like a new wallpaper
        login_themes.sync()
        second = config_values((login_themes.OUT / "login.conf").read_text())["Background"]
        self.assertNotEqual(first, second)
        self.assertFalse(Path(first).exists())
        self.assertFalse((login_themes.OUT / "style-tiles.conf").exists())

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is not installed")
    def test_sync_plays_a_live_wallpaper(self):
        login_themes.OUT.mkdir(parents=True)
        video = self.temp / "live.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=10",
                        "-t", "1", "-pix_fmt", "yuv420p", str(video)], check=True)
        login_themes.LIVE.write_text(str(video))
        login_themes.sync()
        values = config_values((login_themes.OUT / "login.conf").read_text())
        self.assertTrue(values["Background"].endswith(".mp4") and Path(values["Background"]).is_file())
        self.assertTrue(values["BackgroundPlaceholder"].endswith(".jpg"))

    def test_sync_needs_the_installed_folder(self):
        with self.assertRaises(SystemExit):
            login_themes.sync()


class HelperTests(unittest.TestCase):
    def test_sddm_conf_keyboard_off_and_theme_selected(self):
        with tempfile.TemporaryDirectory() as temp:
            conf = Path(temp) / "sddm.conf"
            conf.write_text("[General]\nDisplayServer=x11\nInputMethod=qtvirtualkeyboard\n[Theme]\n    Current=old\n")
            with patch.object(helper.subprocess, "run"):
                for _ in range(2):   # idempotent
                    helper.set_keys(conf, "Theme", {"Current": "hypr-login-styles"})
                    helper.set_keys(conf, "General", {"InputMethod": ""})
            text = conf.read_text()
            self.assertEqual(text.count("Current="), 1)
            self.assertIn("Current=hypr-login-styles", text)
            self.assertIn("InputMethod=\n", text)
            self.assertIn("DisplayServer=x11", text)


class GreeterPatchTests(unittest.TestCase):
    def test_loading_scene_is_patched_into_astronaut(self):
        with tempfile.TemporaryDirectory() as temp:
            theme = Path(temp) / "astronaut"
            for name in ("Themes", "Backgrounds", "Components"):
                (theme / name).mkdir(parents=True)
            main = theme / "Main.qml"
            main.write_text("Item {\n    focus: true\n}\n")
            fields = theme / "Components/Input.qml"
            fields.write_text("    function triggerLogin() {\n"
                              "        sddm.login(targetUser, password.text, sessionSelect.selectedSession)\n"
                              "        function onLoginFailed() {\n")
            (theme / "metadata.desktop").write_text("ConfigFile=Themes/old.conf\n")
            poster = theme / "Backgrounds/jake_the_dog.png"
            poster.write_bytes(b"stock poster")
            greeter.prepare_theme(theme)
            self.assertIn("JakeLoadingScene {", main.read_text())
            self.assertIn("root.startLoading()", fields.read_text())
            self.assertIn("root.stopLoading()", fields.read_text())
            self.assertEqual((theme / "Components/jake.png").read_bytes(), poster.read_bytes())


if __name__ == "__main__":
    unittest.main()
