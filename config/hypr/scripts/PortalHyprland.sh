#!/usr/bin/env bash
# Repair portals through systemd; never spawn duplicate backends.
exec "$HOME/.config/hypr/scripts/SessionInit.sh" --restart
