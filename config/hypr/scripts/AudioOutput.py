#!/usr/bin/env python3
"""Audio outputs for the lock-screen music card.
  AudioOutput.py list   -> JSON [{name, label, icon, default}] of usable outputs (unplugged HDMI etc. skipped)
  AudioOutput.py next   -> switch to the next usable output and move playing streams to it"""
import json
import subprocess
import sys

ICONS = {"bluetooth": "\U000f02cb", "hdmi": "\U000f0841", "usb": "\U000f0e0c", "speaker": "\U000f04c3"}


def pactl(*args):
    return subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=2).stdout


def outputs():
    default = pactl("get-default-sink").strip()
    res = []
    for s in json.loads(pactl("-f", "json", "list", "sinks") or "[]"):
        ports = s.get("ports") or []
        if ports and all(p.get("availability") == "not available" for p in ports):
            continue
        props = s.get("properties", {})
        bus = props.get("device.bus", "")
        name = s["name"]
        if bus == "bluetooth":
            icon, label = ICONS["bluetooth"], props.get("device.description") or s["description"]
        elif "HDMI" in name or "hdmi" in name:
            icon, label = ICONS["hdmi"], "HDMI " + (s.get("active_port") or "").replace("[Out] ", "")
        elif bus == "usb":
            icon, label = ICONS["usb"], props.get("device.description") or s["description"]
        else:
            icon, label = ICONS["speaker"], "Speakers" if "Speaker" in name else s["description"]
        res.append({"name": name, "label": label.strip(), "icon": icon, "default": name == default})
    return res


def switch_next():
    outs = outputs()
    if len(outs) < 2:
        return
    i = next((k for k, o in enumerate(outs) if o["default"]), -1)
    target = outs[(i + 1) % len(outs)]["name"]
    pactl("set-default-sink", target)
    for line in pactl("list", "short", "sink-inputs").splitlines():
        pactl("move-sink-input", line.split()[0], target)


if __name__ == "__main__":
    if sys.argv[1:] == ["next"]:
        switch_next()
    else:
        print(json.dumps(outputs(), ensure_ascii=False))
