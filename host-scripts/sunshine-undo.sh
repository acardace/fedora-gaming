#!/bin/bash

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-previous-state"
OUTPUT="DP-2"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Restore saved state if available
if [ -f "$STATE_FILE" ]; then
  source "$STATE_FILE"

  if [ -n "$MODE" ]; then
    kscreen-doctor "output.${OUTPUT}.mode.${MODE}"
  fi

  if [ -n "$SCALE" ]; then
    kscreen-doctor "output.${OUTPUT}.scale.${SCALE}"
  fi

  if [ "$HDR" = "enabled" ]; then
    kscreen-doctor "output.${OUTPUT}.hdr.enable"
  elif [ "$HDR" = "disabled" ]; then
    kscreen-doctor "output.${OUTPUT}.hdr.disable"
  fi

  rm -f "$STATE_FILE"
else
  # No saved state — fall back to sensible default (idle/headless mode)
  # Use lowest resolution to save power when no one is connected
  kscreen-doctor "output.${OUTPUT}.mode.640x480@75"
  kscreen-doctor "output.${OUTPUT}.hdr.enable"
fi
