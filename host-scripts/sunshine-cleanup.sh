#!/bin/bash
#
# Run at login to recover from a previous Sunshine session whose undo
# never ran (e.g. shutdown via Moonlight, crash, abrupt disconnect).
# Re-enables the physical display and restores the virtual output state.

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-previous-state"
VIRTUAL_OUTPUT="DP-2"
PHYSICAL_OUTPUT="DP-1"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Nothing to do if there's no stale state
[ -f "$STATE_FILE" ] || exit 0

source "$STATE_FILE"

# Remove any leftover custom modes from streaming
kscreen-doctor "output.${VIRTUAL_OUTPUT}.removeCustomMode.0" 2>/dev/null

# Restore virtual output settings
if [ -n "$MODE" ]; then
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.${MODE}"
fi
if [ -n "$SCALE" ]; then
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.scale.${SCALE}"
fi
if [ "$HDR" = "enabled" ]; then
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.enable"
elif [ "$HDR" = "disabled" ]; then
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.disable"
fi

# Re-enable physical monitor if connected
physical_connected=$(cat /sys/class/drm/card1-${PHYSICAL_OUTPUT}/status 2>/dev/null)
if [ "$physical_connected" = "connected" ]; then
  kscreen-doctor "output.${PHYSICAL_OUTPUT}.enable"
  sleep 1
  kscreen-doctor "output.${PHYSICAL_OUTPUT}.priority.1" \
                 "output.${VIRTUAL_OUTPUT}.mode.640x480@75" \
                 "output.${VIRTUAL_OUTPUT}.position.0,0" \
                 "output.${VIRTUAL_OUTPUT}.priority.2"
fi

# Switch scheduler back to auto
scxctl switch -m auto 2>/dev/null

rm -f "$STATE_FILE"
