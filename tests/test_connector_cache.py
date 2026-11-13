#!/usr/bin/env python3
"""Compile and exercise the actual connector helper from the patched source."""
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
import unittest

PATCH = Path(__file__).resolve().parents[1] / "experiments/aquamarine-startup/aquamarine-0.16-startup.patch"


def check_connector_cache(path):
    source = path.read_text()
    if path.suffix == '.patch':
        source = '\n'.join(line[1:] for line in source.splitlines()
                           if line.startswith((' ', '+')) and not line.startswith('+++'))
    else:
        scan = source.split('void Aquamarine::CDRMBackend::scanConnectors()', 1)[1].split('void Aquamarine::', 1)[0]
        assert 'drmModeGetConnector(gpu->fd, connectorID)' in scan
        assert 'cachedInitialScan' not in scan and 'AQ_DRM_CACHED_MODES_DEADLINE' not in source
    start = source.index("static drmModeConnector* currentConnectorOrProbe")
    end = source.index("static int gpuNumBuiltinPanels", start)
    helpers = source[start:end]
    program = r'''
    #include <xf86drmMode.h>
    #include <cassert>
    #include <chrono>
    #include <cstdio>
    #include <cstdlib>
    static drmModeConnector cached{}, probed{};
    static bool available = true;
    static int probes = 0, frees = 0;
    extern "C" drmModeConnectorPtr drmModeGetConnectorCurrent(int, uint32_t) { return available ? &cached : nullptr; }
    extern "C" drmModeConnectorPtr drmModeGetConnector(int, uint32_t) { probes++; return &probed; }
    extern "C" void drmModeFreeConnector(drmModeConnectorPtr p) { assert(p == &cached); frees++; }
    ''' + helpers + r'''
    int main() {
        cached.connection = DRM_MODE_CONNECTED; cached.count_modes = 2;
        assert(currentConnectorOrProbe(0, 1) == &cached && probes == 0 && frees == 0);
        cached.count_modes = 0;
        assert(currentConnectorOrProbe(0, 1) == &probed && probes == 1 && frees == 1);
        cached.connection = DRM_MODE_UNKNOWNCONNECTION;
        assert(currentConnectorOrProbe(0, 1) == &probed && probes == 2 && frees == 2);
        available = false;
        assert(currentConnectorOrProbe(0, 1) == &probed && probes == 3 && frees == 2);
        available = true; cached.connection = DRM_MODE_DISCONNECTED;
        assert(currentConnectorOrProbe(0, 1) == &probed && probes == 4 && frees == 3);
        unsetenv("AQ_DRM_DEVICES"); assert(!hasExplicitDevices());
        setenv("AQ_DRM_DEVICES", "", 1); assert(!hasExplicitDevices());
        setenv("AQ_DRM_DEVICES", "/dev/dri/card9", 1); assert(hasExplicitDevices());
    }
    '''
    with tempfile.TemporaryDirectory(prefix="connector-cache-test-") as tmp:
        path = Path(tmp)
        (path / "test.cpp").write_text(program)
        subprocess.run(["c++", "-std=c++23", "-Wall", "-Wextra", "-Werror", "-I/usr/include/libdrm",
                        str(path / "test.cpp"), "-o", str(path / "test")], check=True)
        subprocess.run([str(path / "test")], check=True)


class ConnectorCacheTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("c++") and any(
        (Path(directory) / "xf86drmMode.h").is_file()
        for directory in ("/usr/include", "/usr/include/libdrm")
    ), "C++ compiler and libdrm development headers required")
    def test_connector_cache_fallback(self):
        check_connector_cache(PATCH)


if __name__ == "__main__":
    if len(sys.argv) == 2 and not sys.argv[1].startswith("-"):
        check_connector_cache(Path(sys.argv[1]))
    else:
        unittest.main()
