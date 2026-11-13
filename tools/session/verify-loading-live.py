#!/usr/bin/env python3
"""Verify the installed loading client in a running Hyprland session.

Repeatedly checks real presentation feedback, screenshot visibility of its badge,
animation and clean handoff. Temporarily displays the selected loading image as
an input-transparent overlay. Never logs out, switches workspace, restarts a
service, changes drivers or stops the selected wallpaper. Stops on first failure.

Exit 0: component verified in an existing session; 1: failed; 77: desktop access
or supported monitor/cache/dependencies unavailable. No result here proves a
fresh-login transition or physical monitor visibility.
"""
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time


class Blocked(RuntimeError):
    pass


def pixels(image):
    method = getattr(image, "get_flattened_data", None)
    return method() if method is not None else image.getdata()


def command(args, env, timeout=5):
    return subprocess.run(args, env=env, text=True, capture_output=True, timeout=timeout)


def desktop_environment():
    env = dict(os.environ)
    runtime = Path(env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    env["XDG_RUNTIME_DIR"] = str(runtime)
    signature = env.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not signature or not (runtime/"hypr"/signature/".socket.sock").exists():
        instances = list((runtime/"hypr").glob("*/.socket.sock"))
        if len(instances) == 1:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = instances[0].parent.name
    return env


def preflight(env, home):
    try:
        from PIL import Image  # noqa: F401
    except ImportError as exc:
        raise Blocked("Pillow is required to verify captured image pixels.") from exc
    result = command(["/usr/bin/hyprctl", "-j", "monitors"], env)
    if result.returncode:
        raise Blocked("Cannot access the running Hyprland compositor: " + (result.stderr or result.stdout).strip())
    outputs = json.loads(result.stdout)
    if len(outputs) != 1:
        raise Blocked("This loading client currently supports one monitor; refusing to guess an output.")
    output = outputs[0]
    helper = home/".local/lib/hyprland-startup/wallpaper/hypr-start-wall"
    selector = home/".config/hypr/scripts/StartupWallpaperCache.py"
    if not helper.is_file() or not os.access(helper, os.X_OK):
        raise Blocked("The native loading client is not built.")
    values = command([sys.executable, str(selector), "--native"], env).stdout.splitlines()
    if len(values) != 4:
        raise Blocked("The selected wallpaper has no valid native cache; no old image will be substituted.")
    width, height, scale = map(int, values[:3])
    if (width, height, scale) != (output["width"], output["height"], output["scale"]):
        raise Blocked("The native cache does not match the current monitor dimensions/scale.")
    if not shutil.which("grim"):
        raise Blocked("grim is required for actual compositor-frame capture.")
    return helper, values, output


def visible_badge(capture, raw, normal, dimensions):
    from PIL import Image, ImageChops, ImageStat
    expected = Image.frombytes("RGB", dimensions, raw.read_bytes(), "raw", "BGRX")
    with Image.open(normal) as source:
        control = source.convert("RGB")
    bounds = ImageChops.difference(expected, control).getbbox()
    if bounds is None:
        raise RuntimeError("Cache contains no distinguishable waiting badge.")
    with Image.open(capture) as source:
        actual = source.convert("RGB")
    if actual.size != dimensions:
        raise RuntimeError("Captured output size differs from the tested client.")
    error = sum(ImageStat.Stat(ImageChops.difference(actual.crop(bounds), expected.crop(bounds))).mean)/3
    control_error = sum(ImageStat.Stat(ImageChops.difference(actual.crop(bounds), control.crop(bounds))).mean)/3
    changed = changed_matches = glyphs = glyph_matches = 0
    for wanted, baseline, seen in zip(pixels(expected.crop(bounds)), pixels(control.crop(bounds)), pixels(actual.crop(bounds))):
        if max(abs(a-b) for a, b in zip(wanted, baseline)) <= 25:
            continue
        changed += 1
        matches = max(abs(a-b) for a, b in zip(wanted, seen)) <= 35
        changed_matches += matches
        if min(wanted) >= 210 and max(abs(a-b) for a, b in zip(wanted, baseline)) > 40:
            glyphs += 1
            glyph_matches += matches
    changed_ratio = changed_matches/changed if changed else 0
    glyph_ratio = glyph_matches/glyphs if glyphs else 0
    return {"bounds": bounds, "badge_mean_error": error, "normal_wallpaper_mean_error": control_error,
            "changed_pixel_match": changed_ratio, "glyph_pixel_match": glyph_ratio, "glyph_pixels": glyphs,
            "visible": error < 20 and error + 3 < control_error and changed_ratio >= .85 and glyphs >= 10 and glyph_ratio >= .85}


def animation_changed(first, second, dimensions):
    from PIL import Image, ImageChops
    width, height = dimensions
    radius = max(5, min(40, height//70)) + 5
    x, y = width//2, height*3//4
    box = (max(0, x-radius), max(0, y-radius), min(width, x+radius+1), min(height, y+radius+1))
    with Image.open(first) as a, Image.open(second) as b:
        difference = ImageChops.difference(a.convert("RGB").crop(box), b.convert("RGB").crop(box))
        count = sum(max(pixel) > 5 for pixel in pixels(difference))
    return {"changed_pixels": count, "animated": count >= 8}


def namespaces(value):
    if isinstance(value, dict):
        if "namespace" in value:
            yield value["namespace"]
        for item in value.values():
            yield from namespaces(item)
    elif isinstance(value, list):
        for item in value:
            yield from namespaces(item)


def verify_cycle(number, directory, helper, values, output, env):
    cycle = directory/f"cycle-{number:02d}"
    cycle.mkdir()
    log = cycle/"client.log"
    result = {"cycle": number, "passed": False, "log": str(log)}
    child = None
    start = time.monotonic()
    try:
        with log.open("w") as stream:
            child = subprocess.Popen([str(helper), *values, str(cycle/"submitted")],
                                     env=dict(env, HYPR_STARTUP_VERIFY="1"), stdin=subprocess.DEVNULL,
                                     stdout=stream, stderr=subprocess.STDOUT)
            deadline = time.monotonic()+3
            while time.monotonic() < deadline:
                text = log.read_text()
                if re.search(r"^Bridge presented at uptime ", text, re.M):
                    break
                if child.poll() is not None:
                    raise RuntimeError("Loading client exited before presentation feedback: " + text.strip())
                time.sleep(.02)
            else:
                raise RuntimeError("No real presentation feedback arrived within 3 seconds.")
            result["presentation_seconds"] = round(time.monotonic()-start, 4)
            first, second = cycle/"first.png", cycle/"second.png"
            for path in (first, second):
                if child.poll() is not None:
                    raise RuntimeError("Loading client exited before frame capture.")
                capture = command(["grim", "-o", output["name"], str(path)], env, timeout=2)
                if capture.returncode:
                    raise RuntimeError("Compositor frame capture failed: " + capture.stderr.strip())
                if child.poll() is not None:
                    raise RuntimeError("Loading client exited during frame capture.")
                if path == first:
                    time.sleep(.12)
            dimensions = tuple(map(int, values[:2]))
            result["badge"] = visible_badge(first, Path(values[3]), Path(values[3]).with_name("wallpaper.qoi"), dimensions)
            result["animation"] = animation_changed(first, second, dimensions)
            if not result["badge"]["visible"]:
                raise RuntimeError("Screenshot did not verify the loading badge; presentation alone is insufficient.")
            if not result["animation"]["animated"]:
                raise RuntimeError("Captured indicator pixels did not change.")
            child.send_signal(signal.SIGUSR1)
            if child.wait(timeout=3) != 0:
                raise RuntimeError("The client failed during presentation-aware handoff.")
            text = log.read_text()
            if not re.search(r"Bridge retired .*display-acknowledged=1, handoff=1", text):
                raise RuntimeError("Client did not confirm a clean acknowledged handoff.")
        cleanup_deadline = time.monotonic()+1
        while time.monotonic() < cleanup_deadline:
            layers = command(["/usr/bin/hyprctl", "-j", "layers"], env)
            if layers.returncode:
                raise RuntimeError("Compositor layer access failed during cleanup verification.")
            if "hypr-startup-wallpaper" not in set(namespaces(json.loads(layers.stdout))):
                break
            time.sleep(.02)
        else:
            raise RuntimeError("Loading layer cleanup could not be verified.")
        result["passed"] = True
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        result["error"] = str(exc)
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    result["elapsed_seconds"] = round(time.monotonic()-start, 4)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cycles", type=int, choices=range(1, 21), default=3)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    home = Path.home()
    directory = args.output or home/".local/state/loading-verification"/datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    directory.mkdir(parents=True, exist_ok=False)
    report = {"scope": "running-session-loading-client", "status": "blocked", "cycles": [],
              "requested_cycles": args.cycles, "real_login_verified": False, "optical_blackout_verified": False}
    env = desktop_environment()
    report["access"] = {"runtime": env["XDG_RUNTIME_DIR"], "wayland_display": env.get("WAYLAND_DISPLAY"),
                        "dri_visible": Path("/dev/dri").exists(),
                        "hyprland_instance": env.get("HYPRLAND_INSTANCE_SIGNATURE")}
    exit_code = 77
    try:
        helper, values, output = preflight(env, home)
        lock = Path(env["XDG_RUNTIME_DIR"])/"startup-wallpaper.lock"
        with lock.open("a") as file:
            try:
                fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise Blocked("A startup wallpaper operation is already active.")
            layers = command(["/usr/bin/hyprctl", "-j", "layers"], env)
            if layers.returncode:
                raise Blocked("Cannot inspect compositor layers before testing.")
            if "hypr-startup-wallpaper" in set(namespaces(json.loads(layers.stdout))):
                raise Blocked("A loading surface already exists; refusing to disturb it.")
            report["status"] = "failed"
            for number in range(1, args.cycles+1):
                result = verify_cycle(number, directory, helper, values, output, env)
                report["cycles"].append(result)
                if not result["passed"]:
                    break
            passed = len(report["cycles"]) == args.cycles and all(c["passed"] for c in report["cycles"])
            report["status"] = "passed" if passed else "failed"
            exit_code = 0 if passed else 1
    except (Blocked, OSError, ValueError, subprocess.SubprocessError) as exc:
        report["reason"] = str(exc)
    destination = directory/"report.json"
    destination.write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))
    print("Saved:", destination)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
