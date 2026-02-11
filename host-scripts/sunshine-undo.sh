#!/bin/bash

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-previous-state"
VIRTUAL_OUTPUT="DP-2"
PHYSICAL_OUTPUT="DP-1"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Check if physical monitor is currently connected
physical_connected=$(cat /sys/class/drm/card1-${PHYSICAL_OUTPUT}/status 2>/dev/null)

# Restore saved state
if [ -f "$STATE_FILE" ]; then
  source "$STATE_FILE"

  # Restore virtual output mode
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

  rm -f "$STATE_FILE"
fi

# Try to re-enable physical monitor if it's connected
if [ "$physical_connected" = "connected" ]; then
  kscreen-doctor "output.${PHYSICAL_OUTPUT}.enable"
  sleep 1
  kscreen-doctor "output.${PHYSICAL_OUTPUT}.priority.1" \
                 "output.${VIRTUAL_OUTPUT}.mode.640x480@75" \
                 "output.${VIRTUAL_OUTPUT}.position.0,0" \
                 "output.${VIRTUAL_OUTPUT}.priority.2"
else
  # Headless mode — use 1080p for compatibility
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.1920x1080@60"
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.enable"
fi

# Switch back to auto scheduler mode
scxctl switch -m auto 2>/dev/null
