#!/bin/bash

kscreen-doctor output.DP-2.mode.${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS}

action="disable"
if [ "$SUNSHINE_CLIENT_HDR" = "true" ]; then
  action="enable"
fi
kscreen-doctor "output.DP-2.hdr.${action}"
