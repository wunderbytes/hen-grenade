#!/usr/bin/env bash
# tools/deploy-pi.sh — rsync the arm32 export to the Pi 400 and optionally launch.
# See docs/milestone-0-brief.md §8.
#
# Usage:
#   tools/deploy-pi.sh <pi-user@pi-host> [--launch]
#
# Launches with --rendering-driver opengl3 explicitly during M0 so there is no
# ambiguity about which renderer produced a measurement.
set -euo pipefail

if [ "$#" -lt 1 ]; then
	echo "usage: $0 <pi-user@pi-host> [--launch]" >&2
	exit 1
fi

PI_TARGET="$1"
LAUNCH=0
if [ "${2:-}" = "--launch" ]; then
	LAUNCH=1
fi

BIN="build/linux-arm32/HenGrenade.arm32"
PCK="build/linux-arm32/HenGrenade.pck"
REMOTE_DIR="/home/${PI_TARGET%%@*}/hen-grenade"

if [ ! -f "$BIN" ]; then
	echo "error: $BIN not found. Export the 'Linux arm32' preset first." >&2
	exit 1
fi

echo ">> deploying to ${PI_TARGET}:${REMOTE_DIR}"
rsync -avz --mkpath "$BIN" "$PCK" "${PI_TARGET}:${REMOTE_DIR}/"

echo ">> chmod +x on Pi"
ssh "$PI_TARGET" "chmod +x '${REMOTE_DIR}/$(basename "$BIN")'"

if [ "$LAUNCH" -eq 1 ]; then
	echo ">> launching on Pi (opengl3)"
	ssh "$PI_TARGET" "cd '${REMOTE_DIR}' && ./$(basename "$BIN") --rendering-driver opengl3"
fi

echo ">> done."
