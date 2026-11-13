#!/usr/bin/env python3
"""Exercise the real C pixel renderer with sanitizers, without a display server.

This tests memory bounds and animation pixels, not monitor visibility or Wayland
handoff. --preview DIR exports actual renderer frames using the installed cache.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import shutil
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "native/startup-wallpaper"
PROGRAM = r'''
#define main client_main
#include "startup-wallpaper.c"
#undef main
#include <assert.h>
int main(int argc, char **argv) {
    retire_requested = 1; display_acknowledged = false;
    assert(!can_retire(100));
    display_acknowledged = true; first_acknowledged = 10;
    assert(!can_retire(10.149)); assert(can_retire(10.151));
    retire_requested = 0; assert(!can_retire(100));
    display_acknowledged = false; feedback_pending = true;
    discarded(NULL, NULL);
    assert(!display_acknowledged && !feedback_pending);
    presented(NULL, NULL, 0, 1, 0, 0, 0, 0, 0);
    assert(display_acknowledged && !feedback_pending);
    for (int test = 0; test < 4; ++test) {
        width = (int[]){1, 16, 80, 1920}[test];
        height = (int[]){1, 9, 45, 1080}[test];
        size_t size = (size_t)width * height * 4;
        original = malloc(size);
        struct frame frame = { .pixels = malloc(size) };
        for (int i = 0; i < width * height; ++i) original[i] = 0xff201030;
        memcpy(frame.pixels, original, size);
        for (tick = 0; tick < 24; ++tick) draw_indicator(&frame);
        assert(original[0] == 0xff201030);
        free(frame.pixels); free(original);
    }
    if (argc == 5) {
        width = atoi(argv[1]); height = atoi(argv[2]);
        size_t size = (size_t)width * height * 4;
        original = malloc(size);
        struct frame frame = { .pixels = malloc(size) };
        FILE *input = fopen(argv[3], "rb"); assert(input);
        assert(fread(original, 1, size, input) == size); fclose(input);
        memcpy(frame.pixels, original, size);
        for (tick = 0; tick < 2; ++tick) {
            draw_indicator(&frame);
            char name[4096]; snprintf(name, sizeof(name), "%s/frame-%u.bgrx", argv[4], tick);
            FILE *out = fopen(name, "wb"); assert(out);
            assert(fwrite(frame.pixels, 1, size, out) == size); fclose(out);
        }
        free(frame.pixels); free(original);
    }
    return 0;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--no-sanitizers", action="store_true", help="Run pixel checks when sanitizer runtimes are unavailable")
    parser.add_argument("--undefined-traps", action="store_true", help="Use UBSan traps without an external sanitizer runtime")
    run_renderer(parser.parse_args())


def run_renderer(args):
    pkg = shutil.which("pkgconf") or "pkg-config"
    with tempfile.TemporaryDirectory(prefix="waiting-pixels-") as directory:
        work = Path(directory)
        protocol = SOURCE / "wlr-layer-shell-unstable-v1.xml"
        for mode, name in (("client-header", "wlr-layer-shell-client.h"), ("private-code", "layer.c")):
            subprocess.run(["wayland-scanner", mode, str(protocol), str(work / name)], check=True)
        protocols = subprocess.check_output([pkg, "--variable=pkgdatadir", "wayland-protocols"], text=True).strip()
        subprocess.run(["wayland-scanner", "private-code", str(Path(protocols) / "stable/xdg-shell/xdg-shell.xml"), str(work / "xdg.c")], check=True)
        presentation = Path(protocols) / "stable/presentation-time/presentation-time.xml"
        subprocess.run(["wayland-scanner", "client-header", str(presentation), str(work/"presentation-time-client.h")], check=True)
        subprocess.run(["wayland-scanner", "private-code", str(presentation), str(work/"presentation.c")], check=True)
        program = work / "test.c"
        program.write_text(PROGRAM)
        flags = subprocess.check_output([pkg, "--cflags", "--libs", "wayland-client"], text=True).split()
        sanitizers = (["-fsanitize=undefined", "-fsanitize-undefined-trap-on-error"] if args.undefined_traps else
                      [] if args.no_sanitizers else ["-fsanitize=address,undefined"])
        subprocess.run(["cc", "-g", "-O1", "-Wall", "-Wextra", "-Werror", *sanitizers,
                        "-I" + str(SOURCE), "-I" + str(work), str(program), str(work / "layer.c"), str(work / "xdg.c"), str(work/"presentation.c"),
                        *flags, "-lm", "-o", str(work / "test")], check=True)
        command = [str(work / "test")]
        if args.preview:
            cache = Path.home() / ".cache/hypr-startup-wallpaper"
            metadata = json.loads((cache / "manifest.json").read_text())
            width, height = metadata["dimensions"]
            args.preview.mkdir(parents=True, exist_ok=True)
            command += [str(width), str(height), str(cache / "wallpaper.bgrx"), str(args.preview)]
        subprocess.run(command, check=True)
        if args.preview:
            from PIL import Image
            frames = []
            for raw in sorted(args.preview.glob("frame-*.bgrx")):
                frame = Image.frombytes("RGB", (width, height), raw.read_bytes(), "raw", "BGRX")
                frame.save(raw.with_suffix(".png"))
                frames.append(frame)
            assert len(frames) == 2 and frames[0].tobytes() != frames[1].tobytes(), "Indicator pixels did not animate"
            print("Exported real C renderer preview:", args.preview)
    status = "UBSan traps" if args.undefined_traps else "sanitizers disabled" if args.no_sanitizers else "ASan/UBSan"
    print("PASS: C indicator renderer, 1x1 through 1920x1080, 24 ticks; " + status)


class WaitingIndicatorTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("cc") and shutil.which("wayland-scanner") and
                         (shutil.which("pkgconf") or shutil.which("pkg-config")),
                         "C compiler and Wayland development tools required")
    def test_renderer_bounds_and_presentation(self):
        pkg = shutil.which("pkgconf") or "pkg-config"
        if subprocess.run([pkg, "--exists", "wayland-client", "wayland-protocols"]).returncode:
            self.skipTest("Wayland client and protocol development packages required")
        run_renderer(argparse.Namespace(preview=None, no_sanitizers=False, undefined_traps=True))


if __name__ == "__main__":
    main()
