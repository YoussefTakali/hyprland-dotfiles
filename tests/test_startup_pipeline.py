#!/usr/bin/env python3
"""Check cache invalidation and execute the generated Lua startup queue safely."""
import ctypes
from ctypes.util import find_library
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cache", repo / "config/hypr/scripts/StartupWallpaperCache.py")
cache_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache_module)

class StartupPipelineTests(unittest.TestCase):
    def test_wallpaper_cache_invalidation(self):
        with tempfile.TemporaryDirectory(prefix="wallpaper-cache-test-") as tmp:
            from PIL import Image
            home = Path(tmp)
            wall, monitors, cache = home / "source.png", home / "monitors.conf", home / "cache"
            Image.new("RGB", (160, 90), "#427a9c").save(wall)
            monitors.write_text("monitor=,preferred,auto,1\n")
            assert cache_module.select(wall, monitors, cache) == wall
            with patch.object(cache_module.subprocess, "check_output", return_value=b'[{"width":80,"height":45}]'):
                cache_module.prepare(wall, monitors, cache)
            selected = cache_module.select(wall, monitors, cache)
            assert selected == cache / "wallpaper.qoi"
            with Image.open(selected) as image:
                assert image.size == (80, 45)
            monitors.write_text("monitor=,highrr,auto,1\n")
            assert cache_module.select(wall, monitors, cache) == wall
            with patch.object(cache_module.subprocess, "check_output", return_value=b'[{"width":80,"height":45}]'):
                cache_module.prepare(wall, monitors, cache)
            wall.write_bytes(b"changed image")
            assert cache_module.select(wall, monitors, cache) == wall
            assert cache_module.select(wall, monitors, home / "missing") == wall
            (cache / "manifest.json").write_text("[]")
            assert cache_module.select(wall, monitors, cache) == wall

    def test_first_login_cache_without_compositor(self):
        with tempfile.TemporaryDirectory(prefix="first-login-cache-test-") as tmp:
            from PIL import Image
            home = Path(tmp)
            wall, monitors, cache, drm = home / "wall.png", home / "monitors.conf", home / "cache", home / "drm"
            Image.new("RGB", (160, 90), "#427a9c").save(wall)
            monitors.write_text("monitor=,preferred,auto,1\n")
            connector = drm / "card2-HDMI-A-1"
            connector.mkdir(parents=True)
            (connector / "status").write_text("connected\n")
            (connector / "modes").write_text("80x45\n")
            with patch.object(cache_module.subprocess, "check_output", side_effect=OSError("no Hyprland")):
                cache_module.prepare(wall, monitors, cache, drm)
                assert (cache / "provisional").exists()
                assert cache_module.native_selection(wall, monitors, cache)[:3] == ["80", "45", "1"]
                second = drm / "card1-DP-1"
                second.mkdir()
                (second / "status").write_text("connected\n")
                assert cache_module.prepare(wall, monitors, home / "ambiguous", drm) is None
                assert not (home / "ambiguous/manifest.json").exists()
            with patch.object(cache_module.subprocess, "check_output", return_value=b'[{"width":80,"height":45}]'):
                cache_module.prepare(wall, monitors, cache, drm)
                assert not (cache / "provisional").exists()

    def test_lua_startup_queue(self):
        candidates = (find_library("lua5.1"), find_library("luajit-5.1"), find_library("lua-5.1"))
        lua = next((ctypes.CDLL(name) for name in candidates if name), None)
        if lua is None:
            self.skipTest("Lua 5.1 or LuaJIT shared library required")
        lua.luaL_newstate.restype = ctypes.c_void_p
        lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lua.luaL_loadstring.restype = ctypes.c_int
        lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        lua.lua_pcall.restype = ctypes.c_int
        lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lua.lua_tolstring.restype = ctypes.c_char_p
        lua.lua_close.argtypes = [ctypes.c_void_p]

        with tempfile.TemporaryDirectory(prefix="startup-queue-test-") as tmp, patch.dict(os.environ, HOME=tmp, XDG_RUNTIME_DIR=tmp):
            home = Path(tmp)
            (home / ".cache").mkdir()
            scripts = home / ".config/hypr/scripts"
            scripts.mkdir(parents=True)
            paint = scripts / "StartupWallpaper.sh"
            paint.write_text('#!/bin/sh\nsleep 0.05\nprintf "paint\\n" >> "$HOME/events"\ntouch "$HOME/painted"\n')
            paint.chmod(0o755)
            session = scripts / "SessionInit.sh"
            session.write_text('#!/bin/sh\nif [ "$1" = --prepare-only ]; then touch "$HOME/environment-ready"; fi\n')
            live = home / ".config/hypr/UserScripts/LiveWallpaper.sh"
            live.parent.mkdir()
            live.write_text('#!/bin/sh\ntest -f "$HOME/painted" || touch "$HOME/early"\n')
            config = home / "minimal.conf"
            config.write_text('exec-once = $HOME/.config/hypr/scripts/StartupWallpaper.sh\n'
                              'exec-once = test -f "$HOME/painted" && test -f "$HOME/environment-ready" || touch "$HOME/early"; printf "%s\\n" "app\'s ready" >> "$HOME/events"\n')
            source = repo / "config/hypr/lua/hyprlang.lua"
            code = f'''
        local hook
        hl = {{env=function() end, version=function() return "test" end,
               on=function(name, callback) if name == "hyprland.start" then hook=callback end end,
               exec_cmd=function(command) local f=assert(io.open({json.dumps(str(home / 'command'))}, "w")); f:write(command); f:close() end}}
        local module = dofile({json.dumps(str(source))})
        module.load({json.dumps(str(config))})
        assert(hook)
        hook()
        '''
            state = lua.luaL_newstate()
            lua.luaL_openlibs(state)
            try:
                result = lua.luaL_loadstring(state, code.encode()) or lua.lua_pcall(state, 0, 0, 0)
                assert result == 0, lua.lua_tolstring(state, -1, None)
            finally:
                lua.lua_close(state)
            command = (home / "command").read_text()
            subprocess.run(["/bin/sh", "-c", command], env=dict(os.environ, HOME=tmp), capture_output=True, timeout=5, check=True)
            assert not (home / "early").exists()
            assert (home / "events").read_text().splitlines() == ["paint", "app's ready"]
            # The first surface releases apps while the wallpaper daemon is still
            # warming; video restoration waits until the helper has finished.
            (home / "events").unlink()
            (home / "painted").unlink()
            paint.write_text('#!/bin/sh\nprintf "paint\\n" >> "$HOME/events"\ntouch "$HOME/painted"\ntouch "$3"\nsleep 0.25\nprintf "daemon ready\\n" >> "$HOME/events"\n')
            live.write_text('#!/bin/sh\nprintf "video restore\\n" >> "$HOME/events"\n')
            subprocess.run(["/bin/sh", "-c", command], env=dict(os.environ, HOME=tmp), capture_output=True, timeout=5, check=True)
            events = (home / "events").read_text().splitlines()
            assert events.index("paint") < events.index("app's ready") < events.index("daemon ready"), events
            assert events.index("daemon ready") < events.index("video restore"), events


if __name__ == "__main__":
    unittest.main()
