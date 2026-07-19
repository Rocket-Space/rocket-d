#!/bin/bash
# rocket-d-restart-bar - Restart waybar
killall -q waybar 2>/dev/null
sleep 0.5
waybar &
echo "Waybar restarted."
