#!/bin/bash

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-previous-state"
OUTPUT="DP-2"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Save current state before changing anything
# Strip ANSI codes and parse kscreen-doctor output
kscreen_output=$(kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

current_mode=$(echo "$kscreen_output" | grep -oP '\d+x\d+@[\d.]+\*' | tr -d '*' | sed 's/\.00$//')
current_hdr=$(echo "$kscreen_output" | grep -oP 'HDR: \K\w+')
current_scale=$(echo "$kscreen_output" | grep -oP 'Scale: \K[\d.]+')

if [ -n "$current_mode" ]; then
  echo "MODE=${current_mode}" > "$STATE_FILE"
  echo "HDR=${current_hdr}" >> "$STATE_FILE"
  echo "SCALE=${current_scale}" >> "$STATE_FILE"
fi

# Set resolution to client's requested mode
if [ -n "$SUNSHINE_CLIENT_WIDTH" ] && [ -n "$SUNSHINE_CLIENT_HEIGHT" ] && [ -n "$SUNSHINE_CLIENT_FPS" ]; then
  kscreen-doctor "output.${OUTPUT}.mode.${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS}"

  # If exact mode not found, try without refresh rate
  if [ $? -ne 0 ]; then
    kscreen-doctor "output.${OUTPUT}.mode.${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}"
  fi
fi

# Set scale to 1 for streaming (no point scaling for a remote client)
kscreen-doctor "output.${OUTPUT}.scale.1"

# Set HDR based on client capability
if [ "$SUNSHINE_CLIENT_HDR" = "true" ]; then
  kscreen-doctor "output.${OUTPUT}.hdr.enable"
else
  kscreen-doctor "output.${OUTPUT}.hdr.disable"
fi
