#!/usr/bin/env python3
"""Prepare a monitor-sized QOI outside login; select it only while still valid."""
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile


def signature(path):
    info = path.stat()
    return [info.st_size, info.st_mtime_ns]


def scene_signature():
    scene_dir = Path.home() / ".config/quickshell/login-splash"
    for name in ("transition.png", "jake.png"):
        path = scene_dir / name
        if path.is_file():
            return [name, signature(path)]
    return None


def select(wall, monitors, cache):
    try:
        saved = json.loads((cache / "manifest.json").read_text())
        if not isinstance(saved, dict):
            return wall
        image = cache / "wallpaper.qoi"
        scene = scene_signature()
        if saved.get("scene") != scene:
            return wall
        if (saved["wall"] == signature(wall) and saved["monitors"] == signature(monitors)
                and saved["image"] == signature(image)):
            return image
    except (OSError, ValueError, KeyError):
        pass
    return wall


def prepare(wall, monitors, cache, drm=Path("/sys/class/drm")):
    from PIL import Image, ImageOps, ImageDraw, ImageFont
    before = signature(wall), signature(monitors)
    provisional = False
    try:
        outputs = json.loads(subprocess.check_output(["/usr/bin/hyprctl", "-j", "monitors"], timeout=3, stderr=subprocess.DEVNULL))
    except (OSError, ValueError, subprocess.SubprocessError):
        outputs = []
    if not outputs:
        # During first installation Hyprland may not be running yet. Only
        # predict a size for the simple bundled monitor rule and one connector.
        rules = [line.split("#", 1)[0].strip() for line in monitors.read_text().splitlines()]
        rules = [line for line in rules if re.match(r"^monitor\s*=", line)]
        if len(rules) != 1 or not re.fullmatch(r"monitor\s*=\s*,\s*preferred\s*,\s*auto\s*,\s*1\s*", rules[0]):
            return
        connected = []
        for status in drm.glob("card*-*/status"):
            try:
                if status.read_text().strip() == "connected":
                    connected.append(status.parent)
            except OSError:
                continue
        if len(connected) != 1:
            return
        modes = (connected[0] / "modes").read_text().splitlines()
        if not modes or not re.fullmatch(r"[0-9]+x[0-9]+", modes[0]):
            return
        width, height = map(int, modes[0].split("x"))
        outputs = [{"width": width, "height": height, "scale": 1}]
        provisional = True
    if len(outputs) != 1:
        return
    output = outputs[0]
    dimensions = int(output["width"]), int(output["height"])
    if min(dimensions) <= 0 or max(dimensions) > 16384:
        return
    cache.mkdir(parents=True, exist_ok=True)
    scene_dir = Path.home() / ".config/quickshell/login-splash"
    shared_frame = scene_dir / "transition.png"
    scene_before = scene_signature()
    with tempfile.TemporaryDirectory(dir=cache, prefix="prepare-") as tmp:
        image = Path(tmp) / "wallpaper.qoi"
        raw = Path(tmp) / "wallpaper.bgrx"
        with Image.open(wall) as original:
            resized = ImageOps.fit(original.convert("RGB"), dimensions, method=Image.Resampling.LANCZOS)
            resized.save(image, format="QOI")
            # The short-lived bridge uses the user's photo with a discreet
            # waiting badge. The normal wallpaper remains entirely unchanged.
            splash = shared_frame if shared_frame.is_file() else scene_dir / "jake.png"
            if splash.is_file():
                # The fast first surface matches the login splash rather than
                # flashing the desktop photo before the animated shell loads.
                with Image.open(splash) as artwork:
                    waiting = ImageOps.fit(artwork.convert("RGBA"), dimensions, method=Image.Resampling.LANCZOS)
            else:
                waiting = resized.convert("RGBA")
            if not shared_frame.is_file():
                overlay = Image.new("RGBA", dimensions, (0, 0, 0, 0))
                draw = ImageDraw.Draw(overlay)
                unit = max(1, min(dimensions) // 900)
                font_size = max(16, min(dimensions) // 42)
                try:
                    font = ImageFont.truetype("DejaVuSans.ttf", font_size)
                except OSError:
                    font = ImageFont.load_default()
                label = "Starting your desktop..."
                bounds = draw.textbbox((0, 0), label, font=font)
                text_w, text_h = bounds[2] - bounds[0], bounds[3] - bounds[1]
                pad_x, pad_y = max(20, font_size), max(12, font_size // 2)
                box_w, box_h = text_w + 2 * pad_x, text_h + 2 * pad_y
                x, y = (dimensions[0] - box_w) // 2, int(dimensions[1] * .84) - box_h // 2
                draw.rounded_rectangle((x, y, x + box_w, y + box_h), radius=box_h // 2, fill=(20, 18, 32, 185), outline=(255, 255, 255, 80), width=unit)
                draw.text((x + pad_x, y + pad_y - bounds[1]), label, font=font, fill=(255, 255, 255, 245))
                waiting = Image.alpha_composite(waiting, overlay).convert("RGB")
            raw.write_bytes(waiting.convert("RGB").tobytes("raw", "BGRX"))
        if before != (signature(wall), signature(monitors)):
            return  # selection or display changed while decoding
        scene_after = scene_signature()
        if scene_before != scene_after:
            return
        metadata = {"scene": scene_before, "wall": before[0], "monitors": before[1], "image": signature(image),
                    "raw": signature(raw), "dimensions": dimensions, "scale": output.get("scale", 1)}
        manifest = Path(tmp) / "manifest.json"
        manifest.write_text(json.dumps(metadata) + "\n")
        os.replace(image, cache / "wallpaper.qoi")
        os.replace(raw, cache / "wallpaper.bgrx")
        os.replace(manifest, cache / "manifest.json")
        marker = cache / "provisional"
        if provisional:
            marker.touch()
        else:
            marker.unlink(missing_ok=True)


def sync_splash(wall, scene_dir=None, limit=(2560, 1440)):
    """Keep the login loading scene on the wallpaper selected now.

    The scene used to keep whatever image was copied into it once, so every
    login flashed an old wallpaper before the current one appeared.
    """
    from PIL import Image
    scene_dir = scene_dir or Path.home() / ".config/quickshell/login-splash"
    if not (scene_dir / "shell.qml").is_file():
        return
    target, stamp = scene_dir / "jake.png", scene_dir / ".jake-source.json"
    source = signature(wall)
    try:
        if target.is_file() and json.loads(stamp.read_text()) == source:
            return
    except (OSError, ValueError):
        pass
    with Image.open(wall) as original:
        image = original.convert("RGB")
    image.thumbnail(limit, Image.Resampling.LANCZOS)
    if signature(wall) != source:
        return  # the wallpaper changed again while decoding; that run syncs it
    with tempfile.NamedTemporaryFile(dir=scene_dir, prefix=".jake-", suffix=".png", delete=False) as stream:
        temporary = Path(stream.name)
    try:
        image.save(temporary, format="PNG", compress_level=1)
        temporary.chmod(0o644)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    stamp.write_text(json.dumps(source) + "\n")
    # A pre-rendered frame of the scene would still contain the old picture.
    (scene_dir / "transition.png").unlink(missing_ok=True)


def native_selection(wall, monitors, cache):
    if select(wall, monitors, cache) == wall:
        return []
    try:
        saved = json.loads((cache / "manifest.json").read_text())
        raw = cache / "wallpaper.bgrx"
        width, height = saved["dimensions"]
        scale = saved["scale"]
        if (saved["raw"] == signature(raw) and raw.stat().st_size == width * height * 4
                and int(scale) == scale and 1 <= scale <= 8 and width % scale == height % scale == 0):
            return [str(width), str(height), str(int(scale)), str(raw)]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return []


if __name__ == "__main__":
    home = Path.home()
    wall = home / ".config/hypr/wallpaper_effects/.wallpaper_current"
    monitors = home / ".config/hypr/monitors.conf"
    cache = home / ".cache/hypr-startup-wallpaper"
    if sys.argv[1:] == ["--startup"]:
        print(select(wall, monitors, cache))
        values = native_selection(wall, monitors, cache)
        for value in values if values else ["", "", "", ""]:
            print(value)
    elif sys.argv[1:] == ["--native"]:
        for value in native_selection(wall, monitors, cache):
            print(value)
    elif sys.argv[1:] == ["--select"]:
        print(select(wall, monitors, cache))
    else:
        try:
            sync_splash(wall)
        except (ImportError, OSError, ValueError) as exc:
            print("Login splash sync skipped:", exc, file=sys.stderr)
        try:
            prepare(wall, monitors, cache)
        except (ImportError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
            print("Startup wallpaper cache skipped:", exc, file=sys.stderr)
