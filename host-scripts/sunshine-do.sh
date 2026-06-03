#!/bin/bash

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-previous-state"
VIRTUAL_OUTPUT="DP-2"
PHYSICAL_OUTPUT="DP-1"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Self-heal: if a state file exists from a previous session whose undo
# never ran (e.g. shutdown via Moonlight, crash, client vanished), clean
# up the stale state before proceeding.
if [ -f "$STATE_FILE" ]; then
  source "$STATE_FILE"

  kscreen-doctor "output.${VIRTUAL_OUTPUT}.removeCustomMode.0" 2>/dev/null

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

  # Re-enable physical monitor if it was connected before
  prev_physical_connected=$(cat /sys/class/drm/card1-${PHYSICAL_OUTPUT}/status 2>/dev/null)
  if [ "$prev_physical_connected" = "connected" ]; then
    kscreen-doctor "output.${PHYSICAL_OUTPUT}.enable"
  fi

  scxctl switch -m auto 2>/dev/null

  rm -f "$STATE_FILE"
fi

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

# Enable virtual display
kscreen-doctor "output.${VIRTUAL_OUTPUT}.enable"

# Disable physical monitor so Sunshine only sees DP-2
if [ "$physical_connected" = "connected" ]; then
  kscreen-doctor "output.${PHYSICAL_OUTPUT}.disable"
fi

# Set resolution to client's requested mode
if [ -n "$SUNSHINE_CLIENT_WIDTH" ] && [ -n "$SUNSHINE_CLIENT_HEIGHT" ] && [ -n "$SUNSHINE_CLIENT_FPS" ]; then
  # Add the client's resolution as a custom mode so any resolution/refresh
  # rate combination works without needing it baked into the EDID.
  refresh_mhz=$(( SUNSHINE_CLIENT_FPS * 1000 ))
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.addCustomMode.${SUNSHINE_CLIENT_WIDTH}.${SUNSHINE_CLIENT_HEIGHT}.${refresh_mhz}.reduced"

  kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS}"
fi

# Compute scale dynamically to target ~1080px logical height.
# Round to nearest 0.25 step, minimum 1.
if [ -n "$SUNSHINE_CLIENT_HEIGHT" ]; then
  scale=$(awk "BEGIN { s = ${SUNSHINE_CLIENT_HEIGHT} / 1080; s = int(s * 4 + 0.5) / 4; if (s < 1) s = 1; print s }")
else
  scale=1
fi
kscreen-doctor "output.${VIRTUAL_OUTPUT}.scale.${scale}"

# Set HDR based on client capability
if [ "$SUNSHINE_CLIENT_HDR" = "true" ]; then
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.enable"
else
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.disable"
fi

# Inhibit DPMS/screensaver on the virtual display -- turning it off is
# useless and prevents Sunshine from finding a KMS monitor after the
# client disconnects.
busctl --user call org.freedesktop.ScreenSaver \
  /org/freedesktop/ScreenSaver org.freedesktop.ScreenSaver \
  Inhibit ss "sunshine" "keep virtual display awake" >/dev/null 2>&1

# Switch to gaming scheduler mode for lower latency
scxctl switch -m gaming 2>/dev/null
