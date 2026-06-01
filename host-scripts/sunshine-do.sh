#!/bin/bash

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-previous-state"
VIRTUAL_OUTPUT="DP-2"
PHYSICAL_OUTPUT="DP-1"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Strip ANSI codes from kscreen-doctor output
kscreen_output=$(kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

# Save current state of virtual output
current_mode=$(echo "$kscreen_output" | grep -A50 "Output:.*${VIRTUAL_OUTPUT}" | grep -oP '\d+x\d+@[\d.]+\*' | tr -d '*' | sed 's/\.00$//')
current_hdr=$(echo "$kscreen_output" | grep -A50 "Output:.*${VIRTUAL_OUTPUT}" | grep -oP 'HDR: \K\w+' | head -1)
current_scale=$(echo "$kscreen_output" | grep -A50 "Output:.*${VIRTUAL_OUTPUT}" | grep -oP 'Scale: \K[\d.]+' | head -1)

# Check if physical monitor is connected
physical_connected=$(cat /sys/class/drm/card1-${PHYSICAL_OUTPUT}/status 2>/dev/null)

if [ -n "$current_mode" ]; then
  echo "MODE=${current_mode}" > "$STATE_FILE"
  echo "HDR=${current_hdr}" >> "$STATE_FILE"
  echo "SCALE=${current_scale}" >> "$STATE_FILE"
  echo "PHYSICAL=${physical_connected}" >> "$STATE_FILE"
fi

# Disable physical monitor so Sunshine only sees DP-2
if [ "$physical_connected" = "connected" ]; then
  kscreen-doctor "output.${PHYSICAL_OUTPUT}.disable"
fi

# Set resolution to client's requested mode
if [ -n "$SUNSHINE_CLIENT_WIDTH" ] && [ -n "$SUNSHINE_CLIENT_HEIGHT" ] && [ -n "$SUNSHINE_CLIENT_FPS" ]; then
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS}"

  # If exact mode not found, try without refresh rate
  if [ $? -ne 0 ]; then
    kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}"
  fi
fi

# Set scale to 2 for streaming (larger UI elements for remote viewing)
kscreen-doctor "output.${VIRTUAL_OUTPUT}.scale.2"

# Set HDR based on client capability
if [ "$SUNSHINE_CLIENT_HDR" = "true" ]; then
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.enable"
else
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.disable"
fi

# Switch to gaming scheduler mode for lower latency
scxctl switch -m gaming 2>/dev/null
