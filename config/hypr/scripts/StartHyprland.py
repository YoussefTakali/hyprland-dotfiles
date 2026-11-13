#!/usr/bin/env python3
"""Launch the version-checked optional native backend, otherwise the RPM backend."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import signal

PACKAGES = ["aquamarine", "hyprutils", "hyprland"]


def warm_wallpaper_cache(home):
    """Advisory I/O only; decoding stays off the compositor launch path."""
    if not hasattr(os, "posix_fadvise"):
        return
    for name in ("wallpaper.bgrx", "wallpaper.qoi"):
        path = home / ".cache/hypr-startup-wallpaper" / name
        descriptor = None
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
            size = os.fstat(descriptor).st_size
            if 0 < size <= 64 * 1024 * 1024:
                os.posix_fadvise(descriptor, 0, size, os.POSIX_FADV_WILLNEED)
        except OSError:
            pass
        finally:
            if descriptor is not None:
                os.close(descriptor)


def trial_failed_before_startup(return_code, trial_marker, interrupted=False, elapsed=None):
    # The marker is removed by the initial wallpaper submission: a liveness
    # confirmation, not an optical or performance claim. Never restart a normal
    # logout or an explicitly interrupted launcher.
    return not interrupted and trial_marker.exists() and (return_code != 0 or elapsed is None or elapsed < 10)


def run_trial(arguments, trial_env, packaged_env, state):
    started = time.monotonic()
    child = subprocess.Popen(arguments, env=trial_env)
    interrupted = False

    def stop(signum, frame):
        nonlocal interrupted
        interrupted = True
        if child.poll() is None:
            child.send_signal(signum)

    previous = {signum: signal.signal(signum, stop) for signum in (signal.SIGTERM, signal.SIGINT)}
    try:
        result = child.wait()
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
    marker = state / "native-trial.json"
    if trial_failed_before_startup(result, marker, interrupted, time.monotonic()-started):
        with (state / "launcher.log").open("a") as log:
            log.write(f"native-fallback-to-packaged exit={result}; one-shot candidate will not be reused\n")
        # One retry only. Exec the packaged watchdog directly, with the untouched
        # environment; do not recurse into the trial launcher.
        os.execve("/usr/bin/start-hyprland", arguments, packaged_env)
    return result


def packaged_environment(environ):
    env = dict(environ)
    if env.get("HYPRLAND_NATIVE_ACTIVE") == "1":
        original = env.pop("HYPRLAND_NATIVE_PREVIOUS_LD_LIBRARY_PATH", "")
        if original:
            env["LD_LIBRARY_PATH"] = original
        else:
            env.pop("LD_LIBRARY_PATH", None)
        env.pop("HYPRLAND_NATIVE_ACTIVE", None)
        env.pop("AQ_DRM_CACHED_MODES_DEADLINE", None)
    return env


def launcher_signature():
    return [[str(path), path.stat().st_size, path.stat().st_mtime_ns]
            for path in map(Path, ("/usr/bin/Hyprland", "/usr/bin/start-hyprland"))]


def prepare_launcher(path):
    flags = []
    version = json.loads(subprocess.check_output(["/usr/bin/Hyprland", "--version-json"], timeout=3))
    rpm = subprocess.run(["rpm", "-q", "hyprland"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
    help_text = subprocess.check_output(["/usr/bin/start-hyprland", "--help"], text=True, timeout=3)
    if rpm.returncode == 0 and "nix" not in str(version.get("flags", [])).lower() and "--no-nixgl" in help_text:
        flags = ["--no-nixgl"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"signature": launcher_signature(), "flags": flags}) + "\n")


def launcher_flags(path):
    try:
        saved = json.loads(path.read_text())
        if saved["signature"] == launcher_signature() and saved["flags"] == ["--no-nixgl"]:
            return saved["flags"]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return []


def native_environment(manifest, env):
    saved = json.loads(manifest.read_text())
    actual = subprocess.check_output(["rpm", "-q", *PACKAGES], text=True, timeout=3).splitlines()
    if actual != saved["packages"]:
        raise ValueError("native package versions changed")
    if saved.get("kernel", os.uname().release) != os.uname().release:
        raise ValueError("kernel changed since candidate preparation")
    if "nvidia_driver" in saved:
        version_file = Path("/sys/module/nvidia/version")
        current_driver = version_file.read_text().strip() if version_file.exists() else ""
        if saved["nvidia_driver"] != current_driver:
            raise ValueError("NVIDIA driver changed since candidate preparation")
    library = Path(saved["library"])
    if hashlib.sha256(library.read_bytes()).hexdigest() != saved["sha256"]:
        raise ValueError("native library checksum changed")
    trial = Path.home() / ".local/state/session-startup/native-trial.json"
    if trial.exists():
        raise ValueError("previous native login did not confirm its initial wallpaper; disable or rebuild the candidate")
    trial.parent.mkdir(parents=True, exist_ok=True)
    attempted = trial.with_name("native-trial-attempted.json")
    trial_key = saved.get("trial_id", saved["sha256"])
    if attempted.exists() and json.loads(attempted.read_text()).get("trial_id") == trial_key:
        raise ValueError("this candidate's one-shot trial was already attempted; using the packaged backend")
    with trial.open("x") as file:
        file.write(json.dumps({"started": time.time(), "library": str(library)}) + "\n")
    attempted.write_text(json.dumps({"trial_id": trial_key, "started": time.time(), "library": str(library)})+"\n")
    original = env.get("LD_LIBRARY_PATH", "")
    env["HYPRLAND_NATIVE_PREVIOUS_LD_LIBRARY_PATH"] = original
    env["LD_LIBRARY_PATH"] = str(library.parent) + (":" + original if original else "")
    env["HYPRLAND_NATIVE_ACTIVE"] = "1"
    return env


def main():
    launcher = Path.home() / ".config/hypr/startup-launcher.json"
    if sys.argv[1:] == ["--prepare-launcher"]:
        prepare_launcher(launcher)
        print("Prepared native launcher compatibility cache:", launcher)
        return
    manifest = Path.home() / ".config/hypr/native-startup.json"
    if sys.argv[1:] == ["--disable-native"]:
        if manifest.exists():
            manifest.replace(manifest.with_suffix(".disabled.json"))
        print("Packaged Aquamarine will be used at the next login.")
        return
    arguments = sys.argv[1:]
    native_trial = bool(arguments and arguments[0] == "--native-trial")
    if native_trial:
        arguments = arguments[1:]
    packaged_env = packaged_environment(os.environ)
    env = dict(packaged_env)
    state = Path.home() / ".local/state/session-startup"
    state.mkdir(parents=True, exist_ok=True)
    message = "packaged-backend"
    active_trial = False
    if native_trial and manifest.exists():
        try:
            env = native_environment(manifest, env)
            message = "native-candidate-active"
            active_trial = True
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
            message = "native-candidate-skipped: " + str(exc)
    with (state / "launcher.log").open("a") as log:
        log.write(message + "\n")
    # Keep the native watchdog. Only skip Nix detection when the launcher actually
    # supports it and the installed compositor is an RPM, without Nix build flags.
    flags = launcher_flags(launcher)
    warm_wallpaper_cache(Path.home())
    command = ["start-hyprland", *flags, *arguments]
    if active_trial:
        raise SystemExit(run_trial(["/usr/bin/start-hyprland", *flags, *arguments], env, packaged_env, state))
    os.execve("/usr/bin/start-hyprland", command, packaged_env)


if __name__ == "__main__":
    main()
