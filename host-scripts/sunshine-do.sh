#!/bin/bash

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-previous-state"
VIRTUAL_OUTPUT="DP-2"
# Fallback for old state files; physicals are now auto-detected (was DP-3/card1,
# but the Philips panel is DP-1 on card0).
PHYSICAL_OUTPUT="DP-1"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Return "connected" if the given DRM connector is connected on any card.
drm_status() {
  local out="$1"
  cat /sys/class/drm/card*-"${out}"/status 2>/dev/null | head -n 1
}

# List all connected outputs except the virtual one (e.g. "DP-1 HDMI-A-1").
list_physicals() {
  local f name st
  for f in /sys/class/drm/card*-*/status; do
    name=$(basename "$(dirname "$f")")
    # name looks like card0-DP-1 -> strip card prefix
    name=${name#*-}
    [ "$name" = "$VIRTUAL_OUTPUT" ] && continue
    st=$(cat "$f" 2>/dev/null)
    [ "$st" = "connected" ] && echo "$name"
  done
}

# Self-heal: if a state file exists from a previous session whose undo
# never ran (e.g. shutdown via Moonlight, crash, client vanished), clean
# up the stale state before proceeding.
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"

  kscreen-doctor "output.${VIRTUAL_OUTPUT}.removeCustomMode.0" 2>/dev/null
  sleep 1

  if [ -n "$MODE" ]; then
    kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.${MODE}"
    sleep 1
  fi
  if [ -n "$SCALE" ]; then
    kscreen-doctor "output.${VIRTUAL_OUTPUT}.scale.${SCALE}"
  fi
  if [ "$HDR" = "enabled" ]; then
    kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.enable"
  elif [ "$HDR" = "disabled" ]; then
    kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.disable"
  fi

  # Re-enable physical monitors that were connected before.
  # New format: PHYSICALS="DP-1 ...". Old format: PHYSICAL=connected + PHYSICAL_OUTPUT.
  if [ -n "$PHYSICALS" ]; then
    for p in $PHYSICALS; do
      if [ "$(drm_status "$p")" = "connected" ]; then
        kscreen-doctor "output.${p}.enable"
      fi
    done
  elif [ "$PHYSICAL" = "connected" ]; then
    if [ "$(drm_status "$PHYSICAL_OUTPUT")" = "connected" ]; then
      kscreen-doctor "output.${PHYSICAL_OUTPUT}.enable"
    fi
  fi
  sleep 1

  scxctl switch -m auto 2>/dev/null

  rm -f "$STATE_FILE"
fi

# Strip ANSI codes from kscreen-doctor output
kscreen_output=$(kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

# Save current state of virtual output
current_mode=$(echo "$kscreen_output" | grep -A50 "Output:.*${VIRTUAL_OUTPUT}" | grep -oP '\d+x\d+@[\d.]+\*' | tr -d '*' | sed 's/\.00$//')
current_hdr=$(echo "$kscreen_output" | grep -A50 "Output:.*${VIRTUAL_OUTPUT}" | grep -oP 'HDR: \K\w+' | head -1)
current_scale=$(echo "$kscreen_output" | grep -A50 "Output:.*${VIRTUAL_OUTPUT}" | grep -oP 'Scale: \K[\d.]+' | head -1)

# Auto-detect connected physical monitors (excludes virtual).
physicals=$(list_physicals | tr '\n' ' ')

if [ -n "$current_mode" ]; then
  echo "MODE=${current_mode}" > "$STATE_FILE"
  echo "HDR=${current_hdr}" >> "$STATE_FILE"
  echo "SCALE=${current_scale}" >> "$STATE_FILE"
  echo "PHYSICALS=${physicals}" >> "$STATE_FILE"
fi

# Enable virtual display first so KWin never sees zero outputs
# (zero outputs caused "Qt: There are no outputs" + KMS fallback to DP-1).
kscreen-doctor "output.${VIRTUAL_OUTPUT}.enable"
sleep 1
kscreen-doctor "output.${VIRTUAL_OUTPUT}.priority.1"
sleep 1

# Disable physical monitors so Sunshine only sees the virtual output.
# This is what stops the 5120x1440@144 VRR vs virtual mode fight that
# flickers both locally and in Moonlight.
for p in $physicals; do
  kscreen-doctor "output.${p}.disable"
done
if [ -n "$physicals" ]; then
  # Let KWin settle after the topology change before touching modes.
  sleep 2
fi

# Set resolution to client's requested mode
if [ -n "$SUNSHINE_CLIENT_WIDTH" ] && [ -n "$SUNSHINE_CLIENT_HEIGHT" ] && [ -n "$SUNSHINE_CLIENT_FPS" ]; then
  # Add the client's resolution as a custom mode so any resolution/refresh
  # rate combination works without needing it baked into the EDID.
  refresh_mhz=$(( SUNSHINE_CLIENT_FPS * 1000 ))
  if kscreen-doctor "output.${VIRTUAL_OUTPUT}.addCustomMode.${SUNSHINE_CLIENT_WIDTH}.${SUNSHINE_CLIENT_HEIGHT}.${refresh_mhz}.reduced" 2>/dev/null; then
    sleep 1
  fi

  if ! kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS}" 2>/dev/null; then
    # Custom mode rejected (e.g. 1920x1200 reduced blanking on NVIDIA):
    # fall back to a known-good EDID mode instead of leaving 640x480.
    kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.1920x1080@60" 2>/dev/null
  fi
  sleep 1
else
  # No client geometry (shouldn't happen — global_prep_cmd gets SUNSHINE_CLIENT_*):
  # ensure a sane mode rather than whatever undo left behind.
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.1920x1080@60" 2>/dev/null
  sleep 1
fi

# VRR off on the virtual output: VRR negotiation during capture causes
# frame-pacing flicker on NVIDIA KMS grab.
kscreen-doctor "output.${VIRTUAL_OUTPUT}.vrr.disable" 2>/dev/null

# Compute scale dynamically to target ~1080px logical height.
# Round to nearest 0.25 step, minimum 1.
if [ -n "$SUNSHINE_CLIENT_HEIGHT" ]; then
  scale=$(awk "BEGIN { s = ${SUNSHINE_CLIENT_HEIGHT} / 1080; s = int(s * 4 + 0.5) / 4; if (s < 1) s = 1; print s }")
else
  scale=1
fi
kscreen-doctor "output.${VIRTUAL_OUTPUT}.scale.${scale}"

# HDR is not supported on NVIDIA virtual connectors — the driver only creates
# the required DRM HDR_OUTPUT_METADATA property on real physical HDMI 2.1
# connections with SCDC negotiation. Enabling HDR on the virtual output causes
# the cursor plane to lose its framebuffer, breaking Sunshine KMS capture.
kscreen-doctor "output.${VIRTUAL_OUTPUT}.hdr.disable"

sleep 1

# Show the Plasma panel (undo auto-hide) so it's accessible during streaming.
dbus-send --session --dest=org.kde.plasmashell --type=method_call \
  /PlasmaShell org.kde.PlasmaShell.evaluateScript string:'
var p = panels();
for (var i = 0; i < p.length; i++) { p[i].hiding = "none"; }
' 2>/dev/null

# Inhibit DPMS/screensaver on the virtual display -- turning it off is
# useless and prevents Sunshine from finding a KMS monitor after the
# client disconnects.
busctl --user call org.freedesktop.ScreenSaver \
  /org/freedesktop/ScreenSaver org.freedesktop.ScreenSaver \
  Inhibit ss "sunshine" "keep virtual display awake" >/dev/null 2>&1

# Switch to gaming scheduler mode for lower latency
scxctl switch -m gaming 2>/dev/null
