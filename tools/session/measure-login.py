#!/usr/bin/env python3
"""Report the latest measured login, rather than a manual wallpaper refresh."""
from pathlib import Path
import re

state = Path.home() / ".local/state/session-startup"
launcher = state / "launcher.log"
if not launcher.exists():
    raise SystemExit("No login has been measured with the new SDDM wrapper yet.")
entry = profile = None
origin = "pre-profile-wrapper"
for line in launcher.read_text().splitlines():
    fields = line.split()
    if len(fields) != 2:
        continue
    if fields[0] == "session-entry":
        entry, profile = float(fields[1]), None
        origin = "pre-profile-wrapper"
    elif fields[0] == "profile-complete" and entry is not None:
        profile = float(fields[1])
    elif fields[0] == "measurement-origin" and entry is not None:
        origin = fields[1]
if entry is None:
    raise SystemExit("No measured session entry yet.")
wallpaper = state / "wallpaper.log"
records, current = [], None
for line in wallpaper.read_text().splitlines() if wallpaper.exists() else []:
    match = re.match(r"Startup wallpaper at uptime ([\d.]+)", line)
    if match:
        current = {"start": float(match[1])}
        records.append(current)
    match = re.match(r"Still submitted at uptime ([\d.]+)", line)
    if match and current is not None:
        current["submitted"] = float(match[1])
    match = re.match(r"Bridge presented at uptime ([\d.]+)", line)
    if match and current is not None:
        current["presented"] = float(match[1])
    if line.startswith("Bridge frame-callback-fallback") and current is not None:
        current["frame_fallback"] = True
    if re.match(r"Bridge client version=[2-9]\b", line) and current is not None:
        current["presentation_instrumented"] = True
record = next((r for r in reversed(records) if entry <= r["start"] < entry + 15), None)
if record is None or "submitted" not in record:
    raise SystemExit("Latest measured login has no successful initial wallpaper submission yet.")
print("Latest login (command timestamps, not optical frame measurements):")
if origin == "post-profile":
    print("  Timing begins after display-manager login profiles; not directly comparable with older pre-profile records.")
if profile is not None:
    print(f"  Login shell/profile:      {profile - entry:.3f} s")
    print(f"  After profile to helper: {record['start'] - profile:.3f} s")
print(f"  Wallpaper helper:        {record['submitted'] - record['start']:.3f} s")
elapsed = record["submitted"] - entry
print(f"  Session to submission:   {elapsed:.3f} s")
if "presented" in record:
    print(f"  Session to compositor-reported presentation: {record['presented'] - entry:.3f} s")
    print("  Presentation feedback is still not an optical monitor measurement.")
elif record.get("frame_fallback"):
    print("  No presentation feedback: frame callback fallback only.")
else:
    print("  Display presentation: unmeasured (submission is not visibility).")
print("0.500 s command-submission target:", "met" if elapsed <= .5 else "not met")
trace = state / "native-startup.log"
if trace.exists():
    print("Native initialization trace:", trace)
