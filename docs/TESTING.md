# Test suite

Run the complete suite from the repository root as a regular desktop user.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
```

Use the system Python with Pillow, PyGObject, GTK 3 and Blueman. Native coverage
uses C and C++ compilers, pkg-config or pkgconf, Wayland development headers and
protocols, the Wayland scanner, and libdrm development headers. The startup
queue test uses a Lua 5.1-compatible shared library. Tests report skips for
unavailable optional native dependencies.

The suite exercises both installer entry points in temporary homes, mocks
privileged and network commands, tests GPU detection and Bluetooth state, and
checks startup orchestration and the real C renderer. The renderer suite uses
UBSan traps. Its standalone command supports ASan/UBSan and exporting preview
frames. Hardware diagnostics and tools requiring a real session live in
`tools/`. They do not run during discovery.

For a live login-scene check, run `python3 tools/session/verify-loading-live.py
--cycles 3` in the desktop session. This measures a running compositor
component. A new login and a display observation are needed to verify a
full greeter-to-desktop transition.
