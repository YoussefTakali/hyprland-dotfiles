#!/usr/bin/env bash
# Shell-compatible PCI facts, including GPUs with no driver (e.g. pending MOK).
exec python3 "$(dirname "$(readlink -f "$0")")/GpuDetect.py" "$@"
