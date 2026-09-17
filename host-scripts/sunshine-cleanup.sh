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

drm_status() {
  local out="$1"
  cat /sys/class/drm/card*-"${out}"/status 2>/dev/null | head -n 1
}

# Nothing to do if there's no stale state
[ -f "$STATE_FILE" ] || exit 0

# shellcheck disable=SC1090
source "$STATE_FILE"

# Remove any leftover custom modes from streaming
kscreen-doctor "output.${VIRTUAL_OUTPUT}.removeCustomMode.0" 2>/dev/null
sleep 1

# Restore virtual output settings
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

# Re-enable physical monitors. New state: PHYSICALS="DP-1 ...", old: PHYSICAL=connected.
to_enable=""
if [ -n "$PHYSICALS" ]; then
  to_enable="$PHYSICALS"
elif [ "$PHYSICAL" = "connected" ]; then
  to_enable="$PHYSICAL_OUTPUT"
fi

for p in $to_enable; do
  if [ "$(drm_status "$p")" = "connected" ]; then
    kscreen-doctor "output.${p}.enable"
  fi
done
if [ -n "$to_enable" ]; then
  sleep 1
  for p in $to_enable; do
    if [ "$(drm_status "$p")" = "connected" ]; then
      kscreen-doctor "output.${p}.priority.1" \
                     "output.${VIRTUAL_OUTPUT}.mode.640x480@60" \
                     "output.${VIRTUAL_OUTPUT}.position.0,0" \
                     "output.${VIRTUAL_OUTPUT}.priority.2" 2>/dev/null
      break
    fi
  done
fi

# Switch scheduler back to auto
scxctl switch -m auto 2>/dev/null

rm -f "$STATE_FILE"
