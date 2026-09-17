#!/bin/bash

STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-previous-state"
VIRTUAL_OUTPUT="DP-2"
# Fallback for old state files; physicals are now auto-detected (was DP-3/card1,
# but the Philips panel is DP-1 on card0).
PHYSICAL_OUTPUT="DP-1"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

drm_status() {
  local out="$1"
  cat /sys/class/drm/card*-"${out}"/status 2>/dev/null | head -n 1
}

# Remove any custom modes added during streaming
kscreen-doctor "output.${VIRTUAL_OUTPUT}.removeCustomMode.0" 2>/dev/null
sleep 1

# Restore saved state
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"

  # Restore virtual output mode
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

  rm -f "$STATE_FILE"
fi

# Re-enable physical monitors saved in the state file.
# New format: PHYSICALS="DP-1 ...". Old format: PHYSICAL=connected.
restored=""
if [ -n "$PHYSICALS" ]; then
  restored="$PHYSICALS"
elif [ "$PHYSICAL" = "connected" ]; then
  restored="$PHYSICAL_OUTPUT"
fi

for p in $restored; do
  if [ "$(drm_status "$p")" = "connected" ]; then
    kscreen-doctor "output.${p}.enable"
  fi
done
if [ -n "$restored" ]; then
  sleep 2
  for p in $restored; do
    if [ "$(drm_status "$p")" = "connected" ]; then
      # Restore physical as primary so desktop lands back on the Philips panel.
      kscreen-doctor "output.${p}.priority.1" 2>/dev/null
    fi
  done
  sleep 1
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.640x480@60" \
                 "output.${VIRTUAL_OUTPUT}.position.0,0" \
                 "output.${VIRTUAL_OUTPUT}.priority.2" 2>/dev/null
  sleep 1
else
  # Headless mode — use 1080p for compatibility
  kscreen-doctor "output.${VIRTUAL_OUTPUT}.mode.1920x1080@60"
  sleep 1
fi

# Disable virtual display last so KWin never sees zero outputs.
kscreen-doctor "output.${VIRTUAL_OUTPUT}.disable"
sleep 1

# Restore Plasma panel auto-hide
dbus-send --session --dest=org.kde.plasmashell --type=method_call \
  /PlasmaShell org.kde.PlasmaShell.evaluateScript string:'
var p = panels();
for (var i = 0; i < p.length; i++) { p[i].hiding = "autohide"; }
' 2>/dev/null

# Switch back to auto scheduler mode
scxctl switch -m auto 2>/dev/null
