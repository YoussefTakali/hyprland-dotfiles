#!/usr/bin/env python3
"""Build a private, version-locked Aquamarine startup trial. Never replace RPMs.

The normal session ignores this manifest. Only the separately installed trial
session passes --native-trial. Actual DRM/login performance remains to be tested.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import uuid

SOURCE_SHA = "42339c3096c9de6582c0d71bc86b7e63334a3faf6a2b917d385ad093caf66c3c"
VERSIONS = {"aquamarine": "0.16.0", "hyprutils": "0.14.3", "hyprland": "0.57.1"}
HERE = Path(__file__).resolve().parent


def run(args, log, **kwargs):
    print(" ".join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), stdout=log, stderr=subprocess.STDOUT, check=True, **kwargs)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    args = parser.parse_args()
    if not 1 <= args.jobs <= 16:
        parser.error("Use 1–16 build jobs")
    home = Path.home()
    if (home/".local/state/session-startup/native-trial.json").exists():
        parser.error("An earlier native trial was not confirmed. Preserve its logs and disable the trial before preparing another.")
    packages = []
    for name, wanted in VERSIONS.items():
        actual = subprocess.check_output(["rpm", "-q", "--qf", "%{VERSION}", name], text=True).strip()
        if actual != wanted:
            parser.error(f"This candidate targets {name} {wanted}, installed {actual}; packaged backend retained.")
        packages.append(subprocess.check_output(["rpm", "-q", name], text=True).strip())
    cache = home/".cache/hyprland-native-startup"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache/"aquamarine-v0.16.0.tar.gz"
    patch = HERE/"aquamarine-0.16-startup.patch"
    digest = hashlib.sha256(patch.read_bytes()).hexdigest()
    work = cache/("trial-" + digest[:16])
    work.mkdir(exist_ok=True)
    with (work/"build.log").open("a") as log:
        if not archive.exists():
            pending = archive.with_suffix(".download")
            run(["curl", "-fL", "--max-time", "120", "--retry", "2", "-o", pending,
                 "https://github.com/hyprwm/aquamarine/archive/refs/tags/v0.16.0.tar.gz"], log)
            if hashlib.sha256(pending.read_bytes()).hexdigest() != SOURCE_SHA:
                pending.unlink()
                raise RuntimeError("Downloaded source hash differs; refusing to build")
            os.replace(pending, archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != SOURCE_SHA:
            raise RuntimeError("Cached source hash differs; refusing to build")
        source = work/"aquamarine-0.16.0"
        if not source.exists():
            with tarfile.open(archive) as file:
                file.extractall(work, filter="data")
            run(["patch", "--batch", "-p1", "-i", patch], log, cwd=source)
        run(["python3", HERE.parents[1]/"tests/test_connector_cache.py", source/"src/backend/drm/DRM.cpp"], log)
        build = work/"build"
        run(["cmake", "-S", source, "-B", build, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release"], log)
        run(["cmake", "--build", build, "--target", "aquamarine", "attachments", "output", "commitThread", "-j", args.jobs], log)
        run(["ctest", "--test-dir", build, "--output-on-failure", "--timeout", "10", "-R", "^(attachments|output|commitThread)$"], log)
        library = build/"libaquamarine.so.0.16.0"
        destination = home/".local/lib/hyprland-startup"/("candidate-" + digest[:16])
        destination.mkdir(parents=True, exist_ok=True)
        installed = destination/library.name
        temporary = installed.with_suffix(".new")
        shutil.copy2(library, temporary)
        os.replace(temporary, installed)
        for name in ("libaquamarine.so", "libaquamarine.so.15"):
            path = destination/name
            path.unlink(missing_ok=True)
            path.symlink_to(installed.name)
        env = dict(os.environ, LD_LIBRARY_PATH=str(destination)+(":"+os.environ["LD_LIBRARY_PATH"] if os.environ.get("LD_LIBRARY_PATH") else ""))
        link = subprocess.run(["ldd", "-r", str(installed)], env=env, capture_output=True, text=True, check=True)
        log.write(link.stdout+link.stderr)
        if "undefined symbol" in link.stdout+link.stderr or "not found" in link.stdout+link.stderr:
            raise RuntimeError("Candidate has unresolved library symbols")
        executable = subprocess.check_output(["ldd", "/usr/bin/Hyprland"], env=env, text=True)
        matches = [line for line in executable.splitlines() if 'libaquamarine' in line]
        if len(matches) != 1 or Path(matches[0].split('=>',1)[1].strip().split()[0]).resolve() != installed.resolve():
            raise RuntimeError("Hyprland did not resolve the private candidate library")
        log.write(executable)
        run(["/usr/bin/Hyprland", "--version-json"], log, env=env, timeout=10)
        run(["/usr/bin/Hyprland", "--verify-config"], log, env=env, timeout=10)
        manifest = home/".config/hypr/native-startup.json"
        if manifest.exists():
            backup = work/("manifest-"+datetime.datetime.now().strftime("%Y%m%d-%H%M%S")+".json")
            shutil.copy2(manifest, backup)
        data = {"packages": packages, "library": str(installed),
                "sha256": hashlib.sha256(installed.read_bytes()).hexdigest(), "patch_sha256": digest,
                "source_sha256": SOURCE_SHA, "experimental": True, "trial_id": uuid.uuid4().hex}
        data["kernel"] = os.uname().release
        driver = Path('/sys/module/nvidia/version')
        data["nvidia_driver"] = driver.read_text().strip() if driver.exists() else ''
        temporary_manifest = manifest.with_suffix(".new.json")
        temporary_manifest.write_text(json.dumps(data, indent=2)+"\n")
        os.replace(temporary_manifest, manifest)
    print("Prepared private experimental candidate:", installed)
    print("Build/test log:", work/"build.log")
    print("Normal session remains packaged. Candidate requires the separate trial session.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError, tarfile.TarError) as exc:
        raise SystemExit("Native trial preparation stopped: " + str(exc))
